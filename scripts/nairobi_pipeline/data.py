"""Pure data stages; never interpolate weather or turn missing rain into zero."""

from __future__ import annotations

import ast
import hashlib
import io
import itertools
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
import pandas as pd

WEATHER = ["tavg", "tmin", "tmax", "prcp", "wspd", "pres"]
# Broad, configurable sanity checks; not locally calibrated weather-alert limits.
BOUNDS = {
    "tavg": (-90, 60),
    "tmin": (-90, 60),
    "tmax": (-90, 60),
    "prcp": (0, 2000),
    "wspd": (0, 500),
    "pres": (800, 1100),
}
MISSING = {"", "na", "n/a", "nan", "null", "none", "-", "--", "-999", "-9999"}


@dataclass(frozen=True)
class Config:
    source_root: str = "Kenya Weather Stations Data (2015-2025)"
    notebook: str | None = None
    output_root: str = "data/processed/nairobi_stations"
    calibration_end: str = "2019-12-31"
    train_end: str = "2021-12-31"
    validation_end: str = "2023-12-31"
    rain_quantile: float = 0.95
    min_train_observations: int = 365
    min_train_wet_days: int = 30
    min_history_days: int = 3
    seed: int = 42
    mode: str = "rainfall_proxy"
    labels: str | None = None

    def validate(self):
        if pd.Timestamp(self.calibration_end) >= pd.Timestamp(self.train_end):
            raise ValueError("Target calibration must precede the end of training.")
        if pd.Timestamp(self.train_end) >= pd.Timestamp(self.validation_end):
            raise ValueError("Training must end before validation.")
        if not 0 < self.rain_quantile < 1:
            raise ValueError("rain_quantile must be between zero and one.")
        if not 1 <= self.min_history_days <= 7:
            raise ValueError("History requirement must be within a seven-day window.")
        if self.mode not in {"audit", "rainfall_proxy", "observed_labels"}:
            raise ValueError("Unknown target mode.")
        if self.mode == "observed_labels" and not self.labels:
            raise ValueError("Observed flood labels require an explicit labels file.")
        return asdict(self)


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def coordinate(value, latitude=True):
    text = str(value).strip().upper()
    match = re.fullmatch(r"([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEW]?)", text)
    if not match:
        raise ValueError(f"Unrecognised coordinate: {text}")
    number, hemisphere = float(match[1]), match[2]
    if hemisphere:
        if hemisphere not in ("NS" if latitude else "EW") or number < 0:
            raise ValueError("Contradictory coordinate sign/hemisphere.")
        number *= -1 if hemisphere in "SW" else 1
    if abs(number) > (90 if latitude else 180):
        raise ValueError("Coordinate out of range.")
    return number


def notebook_sources(notebook):
    """Read literal read_csv references without executing user notebook cells."""
    document = json.loads(Path(notebook).read_text())
    names = []
    for cell in document["cells"]:
        if cell["cell_type"] != "code":
            continue
        tree = ast.parse("".join(cell["source"]))
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "read_csv"
                and node.args
                and isinstance(node.args[0], ast.Constant)
            ):
                name = Path(str(node.args[0].value)).name
                if name not in names:
                    names.append(name)
    if not names:
        raise ValueError("No literal CSV references were found in the source notebook.")
    return names


def extract_data(config):
    config.validate()
    root = Path(config.source_root)
    metadata_file = root / "stations_metadata.csv"
    metadata_bytes = metadata_file.read_bytes()
    try:
        metadata = pd.read_csv(
            io.BytesIO(metadata_bytes), dtype=str, encoding="utf-8-sig"
        )
        encoding = "utf-8-sig"
    except UnicodeDecodeError:
        metadata = pd.read_csv(io.BytesIO(metadata_bytes), dtype=str, encoding="cp1252")
        encoding = "cp1252"
    metadata.columns = metadata.columns.str.strip().str.lower()
    metadata["station_id"] = metadata.station_id.str.strip()
    if metadata.station_id.duplicated().any():
        raise ValueError("Metadata contains duplicate station identifiers.")
    selection_path = Path(__file__).with_name("station_sources.json")
    selected = (
        notebook_sources(config.notebook)
        if config.notebook
        else json.loads(selection_path.read_text())["files"]
    )
    if (
        not selected
        or len(set(selected)) != len(selected)
        or any(
            not isinstance(name, str)
            or Path(name).name != name
            or not name.endswith(".csv")
            for name in selected
        )
    ):
        raise ValueError("Source selection must contain unique CSV basenames.")
    frames, manifests, stations = [], [], []
    for name in selected:
        path = root / "data" / name
        station = name.split("_")[0]
        # Explicit source inconsistency, NOT a guessed station equivalence.
        metadata_id = {"HKRE0": "HKJK"}.get(station, station)
        match = metadata.loc[metadata.station_id.eq(metadata_id)]
        if len(match) != 1 or match.iloc[0]["county"].strip().lower() != "nairobi":
            raise ValueError(f"{station}: expected exactly one Nairobi metadata entry.")
        entry = match.iloc[0]
        if station == "HKRE0" and "doonholm" not in entry.station_name.lower():
            raise ValueError(
                "Doonholm metadata alias no longer matches the supplied source."
            )
        content = path.read_bytes()
        frame = pd.read_csv(
            io.BytesIO(content), dtype=str, keep_default_na=False, encoding="utf-8-sig"
        )
        frame.columns = frame.columns.str.strip().str.lower()
        if frame.columns.duplicated().any() or not {"time", *WEATHER}.issubset(
            frame.columns
        ):
            raise ValueError(f"{name}: ambiguous or missing required columns.")
        extras = sorted(set(frame.columns) - {"time", *WEATHER})
        frame = frame[["time", *WEATHER]].copy()
        frame["station_id"] = station
        frame["source_row"] = np.arange(2, len(frame) + 2)
        frame["source_filename"] = name
        frames.append(frame)
        manifests.append(
            {
                "file": name,
                "sha256": hashlib.sha256(content).hexdigest(),
                "rows": len(frame),
                "excluded_extra_columns": extras,
            }
        )
        stations.append(
            {
                "station_id": station,
                "metadata_station_id": metadata_id,
                "station_name": entry.station_name.strip(),
                "county": "Nairobi",
                "latitude": coordinate(entry.latitude),
                "longitude": coordinate(entry.longitude, latitude=False),
                "elevation_m": float(entry["elevation(m)"]),
                "metadata_alias_requires_source_confirmation": station != metadata_id,
            }
        )
    return {
        "raw": pd.concat(frames, ignore_index=True),
        "stations": pd.DataFrame(stations),
        "manifest": {
            "notebook_sha256": file_hash(config.notebook) if config.notebook else None,
            "selection_kind": "notebook"
            if config.notebook
            else "explicit_csv_manifest",
            "selection_sha256": file_hash(config.notebook or selection_path),
            "metadata_sha256": hashlib.sha256(metadata_bytes).hexdigest(),
            "metadata_encoding": encoding,
            "files": manifests,
            "upstream_already_cleaned": True,
            "upstream_imputation_method_known": False,
        },
    }


def numeric(series):
    text = series.astype("string").str.strip()
    text = text.mask(text.str.lower().isin(MISSING))
    # Accept English thousands grouping, never guess decimal-comma conventions.
    thousands = text.str.fullmatch(r"[+-]?\d{1,3}(?:,\d{3})+(?:\.\d+)?", na=False)
    text = text.where(~thousands, text.str.replace(",", "", regex=False))
    result = pd.to_numeric(text, errors="coerce").astype(float)
    return result.mask(~np.isfinite(result))


def clean_data(raw, stations, bounds=None):
    bounds = bounds or BOUNDS
    frame = raw.copy()
    frame["raw_time"] = frame.time
    frame["time"] = pd.to_datetime(
        frame.time.astype("string").str.strip(), format="%Y-%m-%d", errors="coerce"
    )
    invalid_date = frame.time.isna() | frame.time.gt(pd.Timestamp.now().normalize())
    rejected = (
        frame.loc[invalid_date].copy().assign(rejection_reason="invalid_or_future_date")
    )
    frame = frame.loc[~invalid_date].copy()
    audit = []
    for column in WEATHER:
        parsed = numeric(frame[column])
        invalid = parsed.isna() | ~parsed.between(*bounds[column])
        frame[f"{column}_invalid"] = invalid
        frame[column] = parsed.mask(invalid)
        audit.append({"field": column, "invalid_or_missing_cells": int(invalid.sum())})
    inconsistent_range = frame.tmin.gt(frame.tmax)
    frame.loc[inconsistent_range, ["tavg", "tmin", "tmax"]] = np.nan
    frame.loc[inconsistent_range, ["tavg_invalid", "tmin_invalid", "tmax_invalid"]] = (
        True
    )
    inconsistent_mean = frame.tavg.lt(frame.tmin) | frame.tavg.gt(frame.tmax)
    frame.loc[inconsistent_mean, "tavg"] = np.nan
    frame.loc[inconsistent_mean, "tavg_invalid"] = True
    date_bounds = frame.groupby("station_id").time.agg(["min", "max"])
    # Different formatting can describe the same reading. Compare canonical values.
    exact = frame.duplicated(["station_id", "time", *WEATHER], keep="first")
    exact_rows = frame.loc[exact].copy().assign(rejection_reason="exact_duplicate")
    frame = frame.loc[~exact].copy()
    conflicts = frame.duplicated(["station_id", "time"], keep=False)
    conflict_rows = (
        frame.loc[conflicts].copy().assign(rejection_reason="conflicting_station_date")
    )
    frame = frame.loc[~conflicts].copy()
    pieces = [part for part in [rejected, exact_rows, conflict_rows] if not part.empty]
    rejected = pd.concat(pieces, ignore_index=True) if pieces else rejected
    daily = []
    for station, bounds_row in date_bounds.iterrows():
        group = (
            frame.loc[frame.station_id.eq(station)]
            .sort_values("time")
            .set_index("time")
        )
        group["calendar_inserted"] = False
        dates = pd.date_range(bounds_row["min"], bounds_row["max"], freq="D")
        group = group.reindex(dates)
        group.index.name = "time"
        group["station_id"] = station
        group["calendar_inserted"] = group.calendar_inserted.isna()
        for column in WEATHER:
            group[f"{column}_invalid"] = (
                group[f"{column}_invalid"].astype("boolean").fillna(True).astype(bool)
            )
        daily.append(group.reset_index())
    if not daily:
        raise ValueError("No valid station observations remain.")
    clean = pd.concat(daily, ignore_index=True).merge(
        stations, on="station_id", validate="many_to_one"
    )
    clean["row_has_invalid_measurement"] = clean[[f"{c}_invalid" for c in WEATHER]].any(
        axis=1
    )
    clean["source_row"] = clean.source_row.astype("Int64")
    audit += [
        {
            "field": "temperature_order",
            "invalid_or_missing_cells": int(
                inconsistent_range.sum() + inconsistent_mean.sum()
            ),
        },
        {"field": "exact_duplicate_rows", "invalid_or_missing_cells": len(exact_rows)},
        {"field": "conflicting_rows", "invalid_or_missing_cells": len(conflict_rows)},
    ]
    return (
        clean.sort_values(["station_id", "time"]).reset_index(drop=True),
        rejected,
        pd.DataFrame(audit),
    )


def mask_persistent_values(clean, minimum_run=30):
    """Conservative modelling view; source data stays intact, flags never look ahead."""
    if minimum_run < 2:
        raise ValueError("A persistent run needs at least two days.")
    model = clean.copy()
    for column in WEATHER:
        age = clean.groupby("station_id", sort=False)[column].transform(
            lambda s: s.groupby(s.ne(s.shift()).cumsum()).cumcount() + 1
        )
        flag = age.ge(minimum_run) & clean[column].notna()
        if column == "prcp":
            flag &= clean[column].ne(0)
        model[f"{column}_persistent_flag"] = flag
        model.loc[flag, column] = np.nan
    return model


def transform_data(clean):
    """Features for target day t use only station measurements dated <= t-1."""
    output = clean[
        ["station_id", "time", "latitude", "longitude", "elevation_m"]
    ].copy()
    for column in WEATHER:
        group = clean.groupby("station_id", sort=False)[column]
        output[f"{column}_lag1"] = group.shift(1)
        output[f"{column}_lag2"] = group.shift(2)
        for window in [3, 7]:
            output[f"{column}_mean_prev{window}"] = group.transform(
                lambda s, window=window: (
                    s.shift(1).rolling(window, min_periods=window).mean()
                )
            )
    rain = clean.groupby("station_id", sort=False).prcp
    output["prcp_sum_prev7"] = rain.transform(
        lambda s: s.shift(1).rolling(7, min_periods=7).sum()
    )
    output["rain_history_days"] = rain.transform(
        lambda s: s.shift(1).rolling(7, min_periods=1).count()
    )
    day = clean.time.dt.dayofyear
    output["season_sin"] = np.sin(2 * np.pi * day / 365.25)
    output["season_cos"] = np.cos(2 * np.pi * day / 365.25)
    return output


def analyse_data(clean, stations, train_end):
    summaries, runs, pairs = [], [], []
    for station, group in clean.groupby("station_id"):
        row = {
            "station_id": station,
            "first_date": str(group.time.min().date()),
            "last_date": str(group.time.max().date()),
            "calendar_days": len(group),
            "observed_days": int((~group.calendar_inserted).sum()),
            "inserted_gap_days": int(group.calendar_inserted.sum()),
            "invalid_measurement_rows": int(group.row_has_invalid_measurement.sum()),
        }
        for column in WEATHER:
            row[f"{column}_missing_pct"] = float(group[column].isna().mean() * 100)
            groups = group[column].ne(group[column].shift()).cumsum()
            for _, run in group.groupby(groups):
                if (
                    len(run) >= 30
                    and run[column].notna().all()
                    and not (column == "prcp" and run[column].iloc[0] == 0)
                ):
                    runs.append(
                        {
                            "station_id": station,
                            "field": column,
                            "value": float(run[column].iloc[0]),
                            "start": str(run.time.iloc[0].date()),
                            "end": str(run.time.iloc[-1].date()),
                            "consecutive_days": len(run),
                        }
                    )
        summaries.append(row)
    for a, b in itertools.combinations(sorted(clean.station_id.unique()), 2):
        left = clean.loc[clean.station_id.eq(a), ["time", *WEATHER]]
        right = clean.loc[clean.station_id.eq(b), ["time", *WEATHER]]
        joined = left.merge(right, on="time", suffixes=("_a", "_b"))
        valid = (
            joined[[f"{c}_{side}" for c in WEATHER for side in ["a", "b"]]]
            .notna()
            .all(axis=1)
        )
        complete = joined.loc[valid]
        same = pd.Series(True, index=complete.index)
        for column in WEATHER:
            same &= complete[f"{column}_a"].eq(complete[f"{column}_b"])
        ma = stations.set_index("station_id").loc[a]
        mb = stations.set_index("station_id").loc[b]
        pairs.append(
            {
                "station_a": a,
                "station_b": b,
                "complete_overlap_days": len(complete),
                "identical_weather_fraction": float(same.mean())
                if len(complete)
                else None,
                "metadata_coordinates_equal": bool(
                    ma.latitude == mb.latitude and ma.longitude == mb.longitude
                ),
            }
        )
    training = clean.loc[clean.time.le(pd.Timestamp(train_end))]
    return {
        "station_quality": pd.DataFrame(summaries),
        "constant_runs": pd.DataFrame(
            runs,
            columns=[
                "station_id",
                "field",
                "value",
                "start",
                "end",
                "consecutive_days",
            ],
        ),
        "station_overlap": pd.DataFrame(pairs),
        "training_descriptive_statistics": training.groupby("station_id")[WEATHER]
        .describe()
        .reset_index(),
        "training_correlations": training[WEATHER].corr().reset_index(),
        "training_monthly_rainfall": training.assign(month=training.time.dt.month)
        .groupby(["station_id", "month"])
        .prcp.agg(["count", "mean", "max"])
        .reset_index(),
    }


def create_targets(clean, features, config):
    data = features.copy()
    if config.mode == "observed_labels":
        labels = pd.read_csv(config.labels, dtype={"station_id": str})
        required = {"station_id", "time", "target", "label_source"}
        if not required.issubset(labels):
            raise ValueError(f"Labels require columns {sorted(required)}.")
        labels["time"] = pd.to_datetime(labels.time, format="%Y-%m-%d", errors="raise")
        labels["target"] = pd.to_numeric(labels.target, errors="raise")
        if (
            labels.duplicated(["station_id", "time"]).any()
            or not labels.target.isin([0, 1]).all()
        ):
            raise ValueError("Labels must be unique, explicitly binary observations.")
        if (
            labels.label_source.isna().any()
            or labels.label_source.astype(str).str.strip().eq("").any()
        ):
            raise ValueError(
                "Every label needs a source; absent events are not assumed negative."
            )
        known = set(map(tuple, clean[["station_id", "time"]].to_numpy()))
        if not set(map(tuple, labels[["station_id", "time"]].to_numpy())).issubset(
            known
        ):
            raise ValueError(
                "Some labels do not match the selected station/calendar data."
            )
        return data.merge(
            labels[list(required)],
            on=["station_id", "time"],
            how="left",
            validate="one_to_one",
        ), []
    thresholds, mapping = [], {}
    for station, group in clean.groupby("station_id"):
        history = group.loc[
            group.time.le(pd.Timestamp(config.calibration_end)), "prcp"
        ].dropna()
        wet = history.loc[history.gt(0)]
        supported = (
            len(history) >= config.min_train_observations
            and len(wet) >= config.min_train_wet_days
        )
        eligible = supported and wet.nunique() > 1
        value = float(wet.quantile(config.rain_quantile)) if eligible else None
        thresholds.append(
            {
                "station_id": station,
                "calibration_rain_days": len(history),
                "positive_rain_days": len(wet),
                "positive_rain_unique_values": int(wet.nunique()),
                "eligible": eligible,
                "threshold_mm": value,
                "reason": "eligible"
                if eligible
                else "constant_positive_rainfall_in_calibration"
                if supported
                else "insufficient_training_rainfall_history",
            }
        )
        if eligible:
            mapping[station] = value
    threshold = clean.station_id.map(mapping)
    data["rain_threshold_mm"] = threshold
    data["target"] = (
        clean.prcp.gt(threshold)
        .astype(float)
        .where(clean.prcp.notna() & threshold.notna())
    )
    data["label_source"] = (
        "early_training_calibration_rainfall_quantile_proxy_NOT_observed_flood"
    )
    return data, thresholds


def split_data(data, config):
    if data.duplicated(["station_id", "time"]).any():
        raise ValueError("Modelling rows must be unique per station and date.")
    usable = data.target.notna() & data.rain_history_days.ge(config.min_history_days)
    frame = data.loc[usable].copy().sort_values(["time", "station_id"])
    frame["target"] = frame.target.astype(int)
    frame["partition"] = np.select(
        [
            frame.time.le(pd.Timestamp(config.train_end)),
            frame.time.le(pd.Timestamp(config.validation_end)),
        ],
        ["train", "validation"],
        default="test",
    )
    parts = {
        name: frame.loc[frame.partition.eq(name)].copy()
        for name in ["train", "validation", "test"]
    }
    for name, part in parts.items():
        if part.empty:
            raise ValueError(f"{name} partition has no eligible labelled rows.")
    if (
        parts["train"].target.nunique() != 2
        or parts["validation"].target.nunique() != 2
    ):
        raise ValueError("Training/validation each require both target classes.")
    return frame, parts
