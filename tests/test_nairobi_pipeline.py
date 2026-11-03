"""Small synthetic fixtures only; these are not scientific flood/rainfall results."""

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

from scripts.nairobi_pipeline.data import (
    Config,
    analyse_data,
    clean_data,
    coordinate,
    create_targets,
    extract_data,
    mask_persistent_values,
    notebook_sources,
    split_data,
    transform_data,
)
from scripts.nairobi_pipeline.models import (
    expanding_date_folds,
    feature_columns,
    train_models,
)
from scripts.nairobi_pipeline.runner import (
    evaluate_test,
    file_hash,
    load_data,
    write_json,
)


def station_metadata():
    return pd.DataFrame(
        [
            {
                "station_id": s,
                "latitude": -1.3,
                "longitude": 36.8,
                "elevation_m": 1700,
                "station_name": s,
                "county": "Nairobi",
                "metadata_station_id": s,
                "metadata_alias_requires_source_confirmation": False,
            }
            for s in ["a", "b"]
        ]
    )


def raw_fixture(days=15):
    rows = []
    for station in ["a", "b"]:
        for i, day in enumerate(pd.date_range("2020-01-01", periods=days)):
            rows.append(
                {
                    "station_id": station,
                    "time": str(day.date()),
                    "tavg": "20",
                    "tmin": "10",
                    "tmax": "25",
                    "prcp": str(i % 5),
                    "wspd": "12",
                    "pres": "1010",
                    "source_filename": station + ".csv",
                    "source_row": i + 2,
                }
            )
    return pd.DataFrame(rows)


class PipelineTests(unittest.TestCase):
    def test_default_manifest_needs_no_exploratory_notebook(self):
        manifest = json.loads(
            Path("scripts/nairobi_pipeline/station_sources.json").read_text()
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data").mkdir()
            metadata = []
            for name in manifest["files"]:
                station = name.split("_")[0]
                frame = raw_fixture(2).loc[
                    lambda f: f.station_id.eq("a"),
                    ["time", "tavg", "tmin", "tmax", "prcp", "wspd", "pres"],
                ]
                frame.to_csv(root / "data" / name, index=False)
                metadata.append(
                    {
                        "station_id": "HKJK" if station == "HKRE0" else station,
                        "station_name": "Doonholm" if station == "HKRE0" else station,
                        "county": "Nairobi",
                        "latitude": "1.3 S",
                        "longitude": "36.8 E",
                        "elevation(m)": 1700,
                    }
                )
            pd.DataFrame(metadata).to_csv(root / "stations_metadata.csv", index=False)
            result = extract_data(Config(source_root=str(root)))
        self.assertEqual(len(result["raw"]), 8)
        self.assertEqual(result["manifest"]["selection_kind"], "explicit_csv_manifest")
        self.assertIsNone(result["manifest"]["notebook_sha256"])
        self.assertEqual(len(result["stations"]), 4)

    def test_directional_coordinates_and_bad_signs(self):
        self.assertEqual(coordinate(" 1.3° S "), -1.3)
        self.assertEqual(coordinate("36.8° E", latitude=False), 36.8)
        with self.assertRaises(ValueError):
            coordinate("-1.3 N")

    def test_notebook_is_read_without_executing_code(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.ipynb"
            path.write_text(
                json.dumps(
                    {
                        "cells": [
                            {
                                "cell_type": "code",
                                "source": [
                                    'raise Exception("never execute")\npd.read_csv("/elsewhere/a.csv")'
                                ],
                            }
                        ]
                    }
                )
            )
            self.assertEqual(notebook_sources(path), ["a.csv"])

    def test_types_invalids_dates_and_temperature_order(self):
        raw = raw_fixture()
        raw.loc[0, "prcp"] = "-3"
        raw.loc[1, "pres"] = "wrong"
        raw.loc[2, "tmin"] = "40"
        raw.loc[3, "time"] = "not-a-date"
        clean, rejected, _ = clean_data(raw, station_metadata())
        first = clean.loc[clean.station_id.eq("a")]
        self.assertTrue(pd.api.types.is_numeric_dtype(clean.prcp))
        self.assertTrue(pd.isna(first.iloc[0].prcp))
        self.assertTrue(pd.isna(first.iloc[1].pres))
        self.assertTrue(pd.isna(first.iloc[2].tmin))
        self.assertIn("invalid_or_future_date", set(rejected.rejection_reason))
        self.assertEqual(int(first.calendar_inserted.sum()), 1)

    def test_duplicate_collapse_and_conflict_quarantine(self):
        raw = raw_fixture()
        exact = raw.iloc[[1]].copy()
        conflicting = raw.iloc[[2]].copy()
        conflicting["prcp"] = "7"
        clean, rejected, _ = clean_data(
            pd.concat([raw, exact, conflicting]), station_metadata()
        )
        self.assertEqual(int(rejected.rejection_reason.eq("exact_duplicate").sum()), 1)
        self.assertEqual(
            int(rejected.rejection_reason.eq("conflicting_station_date").sum()), 2
        )
        self.assertFalse(clean.duplicated(["station_id", "time"]).any())
        self.assertTrue(
            pd.isna(
                clean.loc[
                    clean.station_id.eq("a") & clean.time.eq("2020-01-03"), "prcp"
                ].iloc[0]
            )
        )

    def test_calendar_gap_is_not_a_dry_day_or_previous_observation_lag(self):
        raw = raw_fixture().drop(index=1)
        clean, _, _ = clean_data(raw, station_metadata())
        features = transform_data(clean)
        self.assertTrue(
            pd.isna(
                features.loc[
                    features.station_id.eq("a") & features.time.eq("2020-01-03"),
                    "prcp_lag1",
                ].iloc[0]
            )
        )
        self.assertTrue(
            pd.isna(features.loc[features.station_id.eq("b")].iloc[0].prcp_lag1)
        )

    def test_features_cannot_see_current_or_future_weather(self):
        clean, _, _ = clean_data(raw_fixture(), station_metadata())
        before = transform_data(clean)
        changed = clean.copy()
        changed.loc[changed.time.ge("2020-01-10"), "prcp"] = 999
        after = transform_data(changed)
        pd.testing.assert_frame_equal(
            before.loc[before.time.le("2020-01-10")],
            after.loc[after.time.le("2020-01-10")],
        )
        self.assertNotIn("prcp", feature_columns(before))
        self.assertNotIn("target", feature_columns(before))

    def test_target_threshold_is_fitted_only_on_training_weather(self):
        clean, _, _ = clean_data(raw_fixture(), station_metadata())
        config = Config(
            calibration_end="2020-01-05",
            train_end="2020-01-10",
            validation_end="2020-01-12",
            min_train_observations=3,
            min_train_wet_days=2,
        )
        _, first = create_targets(clean, transform_data(clean), config)
        clean.loc[clean.time.gt(config.train_end), "prcp"] = 999
        _, second = create_targets(clean, transform_data(clean), config)
        self.assertEqual(first, second)

    def test_constant_rainfall_cannot_define_a_high_rainfall_tail(self):
        clean, _, _ = clean_data(raw_fixture(), station_metadata())
        clean["prcp"] = 0.7
        config = Config(
            calibration_end="2020-01-10",
            train_end="2020-01-12",
            validation_end="2020-01-14",
            min_train_observations=3,
            min_train_wet_days=2,
        )
        target, eligibility = create_targets(clean, transform_data(clean), config)
        self.assertTrue(target.target.isna().all())
        self.assertEqual(
            {row["reason"] for row in eligibility},
            {"constant_positive_rainfall_in_calibration"},
        )

    def test_sparse_station_is_retained_in_audit_but_not_given_proxy_labels(self):
        clean, _, _ = clean_data(raw_fixture(), station_metadata())
        target, eligibility = create_targets(clean, transform_data(clean), Config())
        self.assertTrue(target.target.isna().all())
        self.assertTrue(all(not row["eligible"] for row in eligibility))
        self.assertEqual(
            len(
                analyse_data(clean, station_metadata(), "2021-12-31")["station_quality"]
            ),
            2,
        )

    def test_persistent_value_mask_never_uses_future_run_length(self):
        clean, _, _ = clean_data(raw_fixture(days=40), station_metadata())
        clean.loc[clean.station_id.eq("a"), "prcp"] = 43.9
        masked = mask_persistent_values(clean)
        station = masked.loc[masked.station_id.eq("a")]
        self.assertEqual(station.iloc[28].prcp, 43.9)
        self.assertTrue(pd.isna(station.iloc[29].prcp))
        prefix = clean.loc[clean.time.le("2020-01-20")]
        prefix_masked = mask_persistent_values(prefix)
        pd.testing.assert_series_equal(
            masked.loc[masked.time.le("2020-01-20"), "prcp"], prefix_masked.prcp
        )
        self.assertEqual(clean.loc[clean.station_id.eq("a"), "prcp"].notna().sum(), 40)

    def test_conflicts_at_calendar_boundaries_remain_visible_as_gaps(self):
        raw = raw_fixture()
        conflict = raw.iloc[[0]].copy()
        conflict["prcp"] = "9"
        clean, _, _ = clean_data(pd.concat([raw, conflict]), station_metadata())
        first = clean.loc[clean.station_id.eq("a")].iloc[0]
        self.assertEqual(str(first.time.date()), "2020-01-01")
        self.assertTrue(first.calendar_inserted)

    def test_folds_keep_all_stations_on_the_same_side_of_each_date(self):
        dates = pd.date_range("2018-01-01", periods=200)
        train = pd.DataFrame(
            {"time": np.repeat(dates, 2), "target": np.tile([0, 1], 200)}
        )
        for earlier, later in expanding_date_folds(train):
            self.assertLess(
                train.iloc[earlier].time.max(), train.iloc[later].time.min()
            )
            self.assertFalse(
                set(train.iloc[earlier].time) & set(train.iloc[later].time)
            )

    def test_observed_labels_do_not_make_unlabelled_days_negative(self):
        clean, _, _ = clean_data(raw_fixture(), station_metadata())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "labels.csv"
            pd.DataFrame(
                [
                    {
                        "station_id": "a",
                        "time": "2020-01-05",
                        "target": 1,
                        "label_source": "synthetic unit fixture",
                    }
                ]
            ).to_csv(path, index=False)
            target, _ = create_targets(
                clean,
                transform_data(clean),
                Config(mode="observed_labels", labels=str(path)),
            )
            self.assertEqual(int(target.target.notna().sum()), 1)
            self.assertEqual(int(target.target.dropna().iloc[0]), 1)

    def test_three_model_smoke_and_frozen_test_integrity(self):
        rng = np.random.default_rng(42)
        raw = raw_fixture(days=600)
        raw["prcp"] = rng.gamma(1.5, 5, len(raw)).round(2).astype(str)
        clean, _, _ = clean_data(raw, station_metadata())
        config = Config(
            calibration_end="2020-04-30",
            train_end="2020-10-31",
            validation_end="2021-03-31",
            min_train_observations=100,
        )
        target, _ = create_targets(clean, transform_data(clean), config)
        snapshot, parts = split_data(target, config)
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            result = train_models(
                parts, run, quick=True, calibration_end=config.calibration_end
            )
            self.assertTrue(
                {"logistic_regression", "random_forest", "xgboost"}.issubset(
                    set(result["comparison"].model)
                )
            )
            write_json(run / "selection.json", result["freeze"])
            load_data(
                {
                    "cleaned_weather": clean,
                    "features": transform_data(clean),
                    "modelling_data": snapshot,
                },
                run,
            )
            write_json(
                run / "run.json",
                {
                    "config": {"mode": "rainfall_proxy"},
                    "purpose": "synthetic unit test only",
                    "artefact_sha256": {
                        str(p.relative_to(run)): file_hash(p)
                        for p in run.rglob("*")
                        if p.is_file()
                    },
                },
            )
            outcome = evaluate_test(run)
            self.assertEqual(outcome["test_rows"], len(parts["test"]))
            self.assertEqual(evaluate_test(run), outcome)
            with (run / "research.sqlite").open("ab") as handle:
                handle.write(b"changed")
            with self.assertRaises(ValueError):
                evaluate_test(run)


if __name__ == "__main__":
    unittest.main()
