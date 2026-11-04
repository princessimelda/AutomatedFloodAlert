"""Repeatable extract → clean → transform → analyse → load → train orchestration."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import plistlib
import sqlite3
import uuid
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path

import pandas as pd

from .data import (
    analyse_data,
    clean_data,
    create_targets,
    extract_data,
    file_hash,
    mask_persistent_values,
    split_data,
    transform_data,
)


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, allow_nan=False, default=str) + "\n"
    )
    os.replace(temporary, path)


def load_data(tables, run):
    """Write a new research snapshot atomically; never touches the app database."""
    run = Path(run)
    temporary = run / "research.sqlite.tmp"
    with closing(sqlite3.connect(temporary)) as connection, connection:
        for name, table in tables.items():
            table = table.copy()
            table.columns = [
                "__".join(map(str, c)) if isinstance(c, tuple) else str(c)
                for c in table.columns
            ]
            for column in table:
                if pd.api.types.is_datetime64_any_dtype(table[column]):
                    table[column] = table[column].dt.strftime("%Y-%m-%d")
            table.to_sql(name, connection, index=False, if_exists="fail")
        connection.execute(
            "CREATE UNIQUE INDEX station_day ON cleaned_weather(station_id,time)"
        )
        connection.execute("CREATE INDEX modelling_time ON features(time)")
    os.replace(temporary, run / "research.sqlite")


def write_report(run, metadata, analyses, comparison=None):
    run = Path(run)
    quality = analyses["station_quality"]
    lines = [
        "# Nairobi station pipeline run",
        "",
        "**Research only. High rainfall is not an observed flood label or a calibrated flood probability.**",
        "",
        "Inputs came only from the explicit station CSV manifest, or an explicitly supplied source notebook.",
        "The supplied files were already cleaned upstream. Original missing-value masks and any prior imputation/smoothing are unknown.",
        "This pipeline cannot undo or certify that upstream processing. Results are exploratory.",
        "",
        f"Mode: `{metadata['config']['mode']}`. Training ends {metadata['config']['train_end']}; validation ends {metadata['config']['validation_end']}.",
        "",
        "## Data quality",
        "",
        "| Station | Original days | Calendar gaps inserted | Invalid/absent measurement rows |",
        "| --- | ---: | ---: | ---: |",
    ]
    for row in quality.to_dict("records"):
        lines.append(
            f"| {row['station_id']} | {row['observed_days']} | {row['inserted_gap_days']} | {row['invalid_measurement_rows']} |"
        )
    lines += [
        "",
        f"Long constant non-zero-rain/other-measurement runs flagged: {len(analyses['constant_runs'])}.",
        "Audit flags are not proof of error. Source values remain intact; a separate modelling view withholds a field from day 30 of an unchanged run onward. Zero rain is exempt. Earlier days are not retroactively masked.",
        "Metadata gives ACC/FIC and Dagoretti the same coordinates; they were retained as distinct, potentially dependent sources.",
        "Doonholm filename HKRE0 was explicitly linked to metadata HKJK by the supplied station name. The discrepancy remains unverified.",
        "",
        "No averaging across stations, invented dry days, winsorisation, backward fill or automatic outlier deletion was applied.",
        f"Proxy thresholds use only the calibration period through {metadata['config']['calibration_end']}, before all CV validation blocks.",
        "Predictors use previous calendar days only. Model imputation, scaling and encoding are fitted inside each training fold.",
        "",
    ]
    if comparison is not None:
        lines += [
            "## Validation comparison",
            "",
            "| Model | Precision | Recall | F1 | Average precision |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
        for row in comparison.to_dict("records"):
            lines.append(
                f"| {row['model']} | {row['precision']:.4f} | {row['recall']:.4f} | {row['f1']:.4f} | {row['average_precision']:.4f} |"
            )
        freeze = json.loads((run / "selection.json").read_text())
        lines += [
            "",
            f"Frozen validation-selected model: `{freeze['selected_model']}`.",
            f"Training strategy: {freeze['cv_strategy']['status']}.",
            f"Beats best baseline validation AP: {freeze['beats_best_baseline_validation_ap']}.",
            "These scores measure the configured target only; there are no validated flood-prediction metrics.",
            "Test scoring is a separate explicit command. If TEST_REPORT.md exists, this snapshot has already been evaluated. No model is approved for deployment.",
            "",
        ]
    else:
        lines += ["Audit-only run: no model was fitted.", ""]
    lines += [
        "## Artefacts",
        "",
        "See source_manifest.json, run.json, research.sqlite, cleaned_weather.csv, rejected_rows.csv,",
        "features.csv, station_quality.csv, constant_runs.csv, station_overlap.csv and training-only analysis CSVs.",
        "Model runs also include target eligibility, CV results, validation predictions, per-station metrics and frozen artefact checksums.",
    ]
    if (run / "test_metrics.csv").exists():
        lines += [
            "",
            "## Final test evaluation",
            "",
            "The frozen artefacts were scored on their stored test partition. Selection was not changed.",
            "See test_metrics.csv, test_predictions.csv and test_evaluation.json.",
            "Do not tune from these results and continue describing this period as untouched.",
        ]
    (run / "REPORT.md").write_text("\n".join(lines) + "\n")


def run_pipeline(config, quick=False):
    """One automated entry point; identical inputs/config/code reuse a complete run."""
    bundle = extract_data(config)
    code = hashlib.sha256(
        b"".join(p.read_bytes() for p in sorted(Path(__file__).parent.glob("*.py")))
    ).hexdigest()
    versions = {}
    for package in ["pandas", "numpy", "scikit-learn", "xgboost", "joblib"]:
        try:
            versions[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            versions[package] = None
    signature = {
        "source": bundle["manifest"],
        "config": config.validate(),
        "code_sha256": code,
        "versions": versions,
        "quick": quick,
        "python": platform.python_version(),
        "labels_sha256": file_hash(config.labels) if config.labels else None,
    }
    fingerprint = hashlib.sha256(
        json.dumps(signature, sort_keys=True).encode()
    ).hexdigest()
    root = Path(config.output_root)
    root.mkdir(parents=True, exist_ok=True)
    # O_EXCL prevents concurrent scheduled writers from corrupting shared state.
    lock = root / ".pipeline.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, str(os.getpid()).encode())
        latest = root / "latest.json"
        if latest.exists():
            previous = json.loads(latest.read_text())
            run = root / previous["run_id"]
            if (
                previous.get("fingerprint") == fingerprint
                and (run / "run.json").exists()
            ):
                record = json.loads((run / "run.json").read_text())
                if record.get("status") == "complete" and all(
                    (run / name).is_file() and file_hash(run / name) == expected
                    for name, expected in record["artefact_sha256"].items()
                ):
                    return run
        run = root / (
            datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8]
        )
        run.mkdir()
        write_json(run / "source_manifest.json", bundle["manifest"])
        print("Extracted explicitly selected station sources.", flush=True)
        clean, rejected, cleaning = clean_data(bundle["raw"], bundle["stations"])
        model_weather = mask_persistent_values(clean)
        features = transform_data(model_weather)
        analyses = analyse_data(clean, bundle["stations"], config.train_end)
        tables = {
            "raw_weather": bundle["raw"],
            "stations": bundle["stations"],
            "cleaned_weather": clean,
            "rejected_rows": rejected,
            "cleaning_audit": cleaning,
            "model_weather": model_weather,
            "features": features,
            **analyses,
        }
        comparison = None
        if config.mode != "audit":
            modelling, thresholds = create_targets(model_weather, features, config)
            snapshot, parts = split_data(modelling, config)
            tables["modelling_data"] = snapshot
            tables["target_eligibility"] = pd.DataFrame(
                thresholds,
                columns=[
                    "station_id",
                    "calibration_rain_days",
                    "positive_rain_days",
                    "positive_rain_unique_values",
                    "eligible",
                    "threshold_mm",
                    "reason",
                ],
            )
            from .models import train_models

            print(
                "Training three models with training-only preprocessing and supported chronological CV.",
                flush=True,
            )
            result = train_models(
                parts,
                run,
                config.seed,
                quick=quick,
                calibration_end=config.calibration_end,
            )
            write_json(run / "selection.json", result["freeze"])
            tables.update(
                {
                    "validation_comparison": result["comparison"],
                    "validation_predictions": result["validation_predictions"],
                    "validation_by_station": result["station_metrics"],
                }
            )
            result["cv_results"].drop(columns=["params"]).assign(
                params=result["cv_results"].params.map(str)
            ).to_csv(run / "cv_results.csv", index=False)
            comparison = result["comparison"]
        for name, table in tables.items():
            table = table.copy()
            table.columns = [
                "__".join(map(str, c)).rstrip("_") if isinstance(c, tuple) else str(c)
                for c in table.columns
            ]
            table.to_csv(run / f"{name}.csv", index=False)
        load_data(tables, run)
        record = {
            "status": "complete",
            "fingerprint": fingerprint,
            "config": config.validate(),
            "signature": signature,
            "purpose": "experimental_weather_pipeline_NOT_operational_flood_prediction",
            "test_evaluated_during_training": False,
            "feature_timing": "target day t uses weather no later than t-1",
        }
        write_report(run, record, analyses, comparison)
        record["artefact_sha256"] = {
            str(p.relative_to(run)): file_hash(p)
            for p in run.rglob("*")
            if p.is_file() and p.name != "run.json"
        }
        write_json(run / "run.json", record)
        write_json(latest, {"run_id": run.name, "fingerprint": fingerprint})
        print(f"Complete: {run}", flush=True)
        return run
    finally:
        os.close(descriptor)
        lock.unlink(missing_ok=True)


def evaluate_test(run):
    """Never re-fit or silently re-score a changed test snapshot/model."""
    run = Path(run)
    record = json.loads((run / "run.json").read_text())
    if record["config"]["mode"] == "audit":
        raise ValueError("An audit-only run has no trained model.")
    for name, expected in record["artefact_sha256"].items():
        if file_hash(run / name) != expected:
            raise ValueError(f"Frozen artefact changed: {name}")
    destination = run / "test_evaluation.json"
    if destination.exists():
        previous = json.loads(destination.read_text())
        if (
            file_hash(run / "test_metrics.csv") != previous["test_metrics_sha256"]
            or file_hash(run / "test_predictions.csv")
            != previous["test_predictions_sha256"]
        ):
            raise ValueError("Existing final-test outputs changed.")
        return previous
    from .models import evaluate_models

    with closing(sqlite3.connect(run / "research.sqlite")) as connection:
        test = pd.read_sql_query(
            "SELECT * FROM modelling_data WHERE partition='test'",
            connection,
            parse_dates=["time"],
        )
    freeze = json.loads((run / "selection.json").read_text())
    metrics, predictions = evaluate_models(test, run, freeze)
    metrics.to_csv(run / "test_metrics.csv", index=False)
    predictions.to_csv(run / "test_predictions.csv", index=False)
    outcome = {
        "selected_model_unchanged": freeze["selected_model"],
        "test_rows": len(test),
        "test_evaluated": True,
        "evaluated_at_utc": datetime.now(UTC).isoformat(),
        "snapshot_sha256": file_hash(run / "research.sqlite"),
        "purpose": record["purpose"],
        "deployable": False,
        "test_metrics_sha256": file_hash(run / "test_metrics.csv"),
        "test_predictions_sha256": file_hash(run / "test_predictions.csv"),
    }
    write_json(destination, outcome)
    lines = [
        "# Frozen test evaluation",
        "",
        "**Experimental target only; not validated flood risk.**",
        "",
        f"Validation-selected model (unchanged): {freeze['selected_model']}",
        "",
        "| Model | Precision | Recall | F1 | Average precision |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for row in metrics.to_dict("records"):
        ap = (
            f"{row['average_precision']:.4f}"
            if pd.notna(row["average_precision"])
            else "undefined (single class)"
        )
        lines.append(
            f"| {row['model']} | {row['precision']:.4f} | {row['recall']:.4f} | {row['f1']:.4f} | {ap} |"
        )
    lines += [
        "",
        "These test scores must not be used to retune the frozen selection while claiming an untouched test period.",
    ]
    (run / "TEST_REPORT.md").write_text("\n".join(lines) + "\n")
    # Test outputs are separate from, and do not mutate, the frozen training run.
    return outcome


def generate_schedule(destination, python_executable, hour=7, minute=0):
    """Generate (but do not install) a macOS LaunchAgent for cached daily runs."""
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        raise ValueError("Invalid schedule time.")
    root = Path(__file__).resolve().parents[2]
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    config = {
        "Label": "org.floodsafe.station-pipeline",
        "ProgramArguments": [
            str(Path(python_executable).absolute()),
            "-m",
            "scripts.nairobi_pipeline",
            "run",
        ],
        "WorkingDirectory": str(root),
        "StartCalendarInterval": {"Hour": hour, "Minute": minute},
        "StandardOutPath": str(destination.parent.resolve() / "schedule.stdout.log"),
        "StandardErrorPath": str(destination.parent.resolve() / "schedule.stderr.log"),
    }
    with destination.open("wb") as handle:
        plistlib.dump(config, handle)
    return destination
