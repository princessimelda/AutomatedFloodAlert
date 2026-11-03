"""Training-only preprocessing and date-grouped model selection."""

from __future__ import annotations

import hashlib
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, ClassifierMixin
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GridSearchCV, TimeSeriesSplit
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from .macos_runtime import prepare_macos_runtime


class RainPersistence(ClassifierMixin, BaseEstimator):
    def fit(self, X, y):
        self.classes_ = np.array([0, 1])
        self.medians_ = X.groupby("station_id").prcp_lag1.median().to_dict()
        self.fallback_ = float(X.prcp_lag1.median())
        return self

    def predict_proba(self, X):
        rain = X.prcp_lag1.fillna(X.station_id.map(self.medians_)).fillna(
            self.fallback_
        )
        high = rain.gt(X.rain_threshold_mm).astype(float).to_numpy()
        return np.column_stack([1 - high, high])

    def predict(self, X):
        return self.predict_proba(X)[:, 1].astype(int)


def feature_columns(data):
    # Explicit allowlist: target-day weather, labels, provenance and partitions
    # can never enter the estimator even if the source schema grows.
    allowed = [
        "latitude",
        "longitude",
        "elevation_m",
        "rain_history_days",
        "season_sin",
        "season_cos",
        "prcp_sum_prev7",
    ]
    allowed += [
        f"{name}_{suffix}"
        for name in ["tavg", "tmin", "tmax", "prcp", "wspd", "pres"]
        for suffix in ["lag1", "lag2", "mean_prev3", "mean_prev7"]
    ]
    if not set(allowed).issubset(data.columns):
        raise ValueError("Missing engineered predictors.")
    return allowed


class InsufficientHistory(ValueError):
    pass


def expanding_date_folds(train, splits=3, calibration_end=None):
    dates = np.array(sorted(train.time.unique()))
    if len(dates) < splits + 3:
        raise InsufficientHistory(
            "Insufficient distinct dates for chronological cross-validation."
        )
    folds = []
    if calibration_end is None:
        date_folds = [
            (dates[a], dates[b])
            for a, b in TimeSeriesSplit(n_splits=splits, gap=1).split(dates)
        ]
    else:
        available = dates[dates > pd.Timestamp(calibration_end) + pd.Timedelta(days=1)]
        blocks = np.array_split(available, splits)
        if any(len(block) == 0 for block in blocks):
            raise InsufficientHistory("Not enough post-calibration dates for CV.")
        date_folds = [
            (dates[dates < pd.Timestamp(block[0]) - pd.Timedelta(days=1)], block)
            for block in blocks
        ]
    for earlier, later in date_folds:
        first = np.flatnonzero(train.time.isin(earlier).to_numpy())
        second = np.flatnonzero(train.time.isin(later).to_numpy())
        if (
            train.iloc[first].target.nunique() != 2
            or train.iloc[second].target.nunique() != 2
        ):
            raise InsufficientHistory(
                "A chronological CV fold lacks a target class; change the justified split/data, not randomise it."
            )
        folds.append((first, second))
    return folds


def build_models(numeric_columns, seed=42, quick=False):
    prepare_macos_runtime()
    from xgboost import XGBClassifier

    def preprocessing(scale):
        numeric_steps = [
            (
                "impute",
                SimpleImputer(
                    strategy="median", add_indicator=True, keep_empty_features=True
                ),
            )
        ]
        if scale:
            numeric_steps.append(("scale", StandardScaler()))
        return ColumnTransformer(
            [
                ("numeric", Pipeline(numeric_steps), numeric_columns),
                (
                    "station",
                    OneHotEncoder(handle_unknown="ignore", sparse_output=False),
                    ["station_id"],
                ),
            ]
        )

    count = 20 if quick else 150
    candidates = {
        "logistic_regression": (
            LogisticRegression(
                max_iter=2000, class_weight="balanced", random_state=seed
            ),
            {"model__C": [0.1, 1.0]},
        ),
        "random_forest": (
            RandomForestClassifier(
                n_estimators=count,
                min_samples_leaf=5,
                class_weight="balanced",
                n_jobs=2,
                random_state=seed,
            ),
            {"model__max_depth": [5, 10]},
        ),
        "xgboost": (
            XGBClassifier(
                n_estimators=count,
                learning_rate=0.05,
                subsample=0.8,
                colsample_bytree=0.8,
                tree_method="hist",
                eval_metric="logloss",
                n_jobs=2,
                random_state=seed,
            ),
            {"model__max_depth": [2, 3]},
        ),
    }
    return {
        name: (
            Pipeline(
                [
                    ("preprocess", preprocessing(name == "logistic_regression")),
                    ("model", estimator),
                ]
            ),
            {key: values[:1] if quick else values for key, values in grid.items()},
        )
        for name, (estimator, grid) in candidates.items()
    }


def measure(y, score, threshold=0.5):
    prediction = np.asarray(score) >= threshold
    tn, fp, fn, tp = confusion_matrix(y, prediction, labels=[0, 1]).ravel()
    both = len(np.unique(y)) == 2
    return {
        "rows": len(y),
        "positive_rows": int(np.sum(y)),
        "accuracy": float(accuracy_score(y, prediction)),
        "balanced_accuracy": float(balanced_accuracy_score(y, prediction))
        if both
        else None,
        "precision": float(precision_score(y, prediction, zero_division=0)),
        "recall": float(recall_score(y, prediction, zero_division=0)),
        "f1": float(f1_score(y, prediction, zero_division=0)),
        "roc_auc": float(roc_auc_score(y, score)) if both else None,
        "average_precision": float(average_precision_score(y, score)) if both else None,
        "true_negatives": int(tn),
        "false_positives": int(fp),
        "false_negatives": int(fn),
        "true_positives": int(tp),
    }


def train_models(parts, output, seed=42, quick=False, calibration_end=None):
    train, validation = parts["train"], parts["validation"]
    columns = feature_columns(train)
    predictors = columns + ["station_id"]
    try:
        folds = expanding_date_folds(train, calibration_end=calibration_end)
        cv_strategy = {
            "status": "expanding_date_grouped_cv",
            "fold_count": len(folds),
            "folds": [
                {
                    "train_last_date": str(train.iloc[a].time.max().date()),
                    "validation_first_date": str(train.iloc[b].time.min().date()),
                    "validation_last_date": str(train.iloc[b].time.max().date()),
                }
                for a, b in folds
            ],
        }
    except InsufficientHistory as error:
        folds = []
        cv_strategy = {
            "status": "fixed_predeclared_parameters_no_cv",
            "reason": str(error),
            "fold_count": 0,
        }
    artefacts = Path(output) / "models"
    artefacts.mkdir()
    rows, parameters, predictions, station_metrics, cv_results = [], {}, [], [], []
    candidates = build_models(columns, seed, quick)
    candidates["majority_baseline"] = (
        Pipeline(
            [
                ("preprocess", SimpleImputer()),
                ("model", DummyClassifier(strategy="most_frequent")),
            ]
        ),
        {},
    )
    if "rain_threshold_mm" in train:
        candidates["rain_persistence_baseline"] = (RainPersistence(), {})
    # Baselines remain explicit and do not enter learned-model selection.
    for name, (pipeline, grid) in candidates.items():
        inputs = (
            ["season_sin"]
            if name == "majority_baseline"
            else ["station_id", "prcp_lag1", "rain_threshold_mm"]
            if name == "rain_persistence_baseline"
            else predictors
        )
        if grid and folds:
            search = GridSearchCV(
                pipeline,
                grid,
                cv=folds,
                scoring="average_precision",
                refit=True,
                n_jobs=1,
                error_score="raise",
                return_train_score=True,
            )
            search.fit(train[inputs], train.target)
            estimator = search.best_estimator_
            parameters[name] = {
                "best_params": search.best_params_,
                "training_cv_average_precision": float(search.best_score_),
            }
            results = pd.DataFrame(search.cv_results_)
            results.insert(0, "model", name)
            cv_results.append(results)
        else:
            fixed = {key: values[0] for key, values in grid.items()}
            estimator = pipeline.set_params(**fixed).fit(train[inputs], train.target)
            parameters[name] = {"fixed_params": fixed, "cross_validated": False}
        score = estimator.predict_proba(validation[inputs])[:, 1]
        rows.append({"model": name, **measure(validation.target, score)})
        predictions.append(
            validation[["station_id", "time", "target"]].assign(
                model=name, score=score, prediction=(score >= 0.5).astype(int)
            )
        )
        for station in validation.station_id.unique():
            select = validation.station_id.eq(station).to_numpy()
            station_metrics.append(
                {
                    "model": name,
                    "station_id": station,
                    **measure(validation.target.to_numpy()[select], score[select]),
                }
            )
        joblib.dump(
            {
                "pipeline": estimator,
                "predictors": inputs,
                "purpose": "experimental_rainfall_or_observed_label_classifier_NOT_operational_flood_alert",
            },
            artefacts / f"{name}.joblib",
        )
    comparison = pd.DataFrame(rows).sort_values(
        ["average_precision", "f1", "model"], ascending=[False, False, True]
    )
    learned = comparison.loc[
        comparison.model.isin(["logistic_regression", "random_forest", "xgboost"])
    ]
    selected = learned.iloc[0]["model"]
    hashes = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in artefacts.glob("*.joblib")
    }
    freeze = {
        "selected_model": selected,
        "selection_rule": "validation average precision, then F1, then model name",
        "score_threshold": 0.5,
        "seed": seed,
        "model_sha256": hashes,
        "deployable": False,
        "calibrated_flood_probability": False,
        "training_rows": len(train),
        "validation_rows": len(validation),
        "test_used_for_selection": False,
        "beats_best_baseline_validation_ap": bool(
            learned.iloc[0].average_precision
            > comparison.loc[
                comparison.model.str.endswith("baseline"), "average_precision"
            ].max()
        ),
        "parameters": parameters,
        "cv_strategy": cv_strategy,
    }
    return {
        "comparison": comparison,
        "freeze": freeze,
        "validation_predictions": pd.concat(predictions, ignore_index=True),
        "station_metrics": pd.DataFrame(station_metrics),
        "cv_results": pd.concat(cv_results, ignore_index=True)
        if cv_results
        else pd.DataFrame(columns=["model", "params", "mean_test_score"]),
    }


def evaluate_models(test, output, freeze):
    """Score an immutable test snapshot only after validation selection is frozen."""
    prepare_macos_runtime()
    rows, predictions = [], []
    for name, expected in freeze["model_sha256"].items():
        path = Path(output) / "models" / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("Model changed after selection was frozen.")
        # Only locally generated, hash-verified artefacts; never load untrusted joblib.
        model = joblib.load(path)
        score = model["pipeline"].predict_proba(test[model["predictors"]])[:, 1]
        rows.append({"model": path.stem, **measure(test.target, score)})
        predictions.append(
            test[["station_id", "time", "target"]].assign(
                model=path.stem, score=score, prediction=(score >= 0.5).astype(int)
            )
        )
    return pd.DataFrame(rows), pd.concat(predictions, ignore_index=True)
