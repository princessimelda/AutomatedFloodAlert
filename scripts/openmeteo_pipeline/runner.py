"""Isolated API research pipeline, sharing the audited chronological model code."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
import platform
import plistlib
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

import pandas as pd

from scripts.nairobi_pipeline.data import (
    analyse_data,
    clean_data,
    create_targets,
    file_hash,
    split_data,
    transform_data,
)
from scripts.nairobi_pipeline.runner import evaluate_test, load_data, write_json

from .source import Config, extract_data


def analyse(clean, grids, config):
    """Full-period quality audits; distributions/correlations use training data only."""
    return analyse_data(clean, grids, config.train_end)


def build_models(clean, features, config, run, *, quick=False):
    """Calibrate target, split by date, fit three estimators, compare and freeze."""
    from scripts.nairobi_pipeline.models import train_models

    modelling, eligibility = create_targets(clean, features, config)
    snapshot, parts = split_data(modelling, config)
    result = train_models(
        parts, run, config.seed, quick=quick, calibration_end=config.calibration_end
    )
    write_json(run / "selection.json", result["freeze"])
    result["cv_results"].assign(params=result["cv_results"].params.map(str)).to_csv(
        run / "cv_results.csv", index=False
    )
    return {
        "modelling_data": snapshot,
        "target_eligibility": pd.DataFrame(
            eligibility,
            columns=[
                "station_id",
                "calibration_rain_days",
                "positive_rain_days",
                "positive_rain_unique_values",
                "eligible",
                "threshold_mm",
                "reason",
            ],
        ),
        "validation_comparison": result["comparison"],
        "validation_predictions": result["validation_predictions"],
        "validation_by_station": result["station_metrics"],
    }


def write_report(run, config, bundle, tables):
    manifest = bundle["manifest"]
    lines = [
        "# Open-Meteo Nairobi experiment",
        "",
        "**Experimental high-rainfall classification; not observed or calibrated flood risk.**",
        "",
        f"Source: Open-Meteo historical forecast archive; fixed `{manifest['model']}` model; {config.start_date} through {config.end_date}.",
        f"Three approximate study queries resolved to {manifest['grid_count']} distinct provider grid cells; {manifest['duplicate_grid_day_rows_removed']} repeated grid/day rows were removed.",
        "Internal `station_id` keys identify provider cells, not weather stations. Coordinates and elevations are returned model-grid metadata.",
        "This is gridded forecast-model output, not measured station ground truth. Adjacent cells are spatially dependent; testing is temporal and does not establish generalization to new regions.",
        "",
        "## Method",
        "",
        "Annual API requests, preserved raw JSON/checksum receipts and explicit units. UTC calendar days; no local-time conversion.",
        "Strict schema/unit/date checks, numeric conversion, physical-range and temperature-order checks; duplicate/conflict detection and missing-day audit. Null rainfall stays missing, never zero.",
        "The station experiment's persistent-value masking is not applied to this separate provider source; long runs remain visible in quality audits.",
        "Features: 1/2-day lags, previous 3/7-day means, previous 7-day rainfall sum, season and grid metadata. No target-day weather in predictors.",
        f"Proxy: rain greater than the grid's {config.rain_quantile:.0%} positive-rain quantile, calibrated only through {config.calibration_end}; applies only in rainfall_proxy mode.",
        f"Mode: {config.mode}. Training ends {config.train_end}; validation ends {config.validation_end}; subsequent dates form the final test partition.",
        "Median imputation, scaling and category encoding are fitted inside chronological training folds; three model families are compared with majority and rainfall-persistence baselines where applicable.",
        "Selection uses validation average precision; threshold fixed at 0.5. Final test evaluation is a separate command against frozen, hashed artefacts. Neither tuning nor model selection uses test results.",
        "",
        "## Data quality",
        "",
    ]
    lines.append(tables["station_quality"].to_csv(index=False))
    if "validation_comparison" in tables:
        lines += [
            "## Validation results",
            "",
            tables["validation_comparison"].to_csv(index=False),
        ]
        freeze = json.loads((run / "selection.json").read_text())
        lines.append(
            f"Validation-selected model: `{freeze['selected_model']}`. See selection.json for CV strategy and baseline comparison."
        )
    lines += [
        "",
        "## Interpretation and next use",
        "",
        "The stitched archive combines early forecast hours from successive runs. It does not preserve the exact inputs available at a historical prediction issuance time. These retrospective scores are not proof of an operational forecast's lead-time skill.",
        "Using one model family reduces source switching but does not pin NOAA model versions or guarantee equal archive/live preprocessing. Validate as-issued runs and observed outcomes before operational alerts.",
        "The API's free non-commercial access still has usage limits. Small annual requests are cached; explicit refresh creates new raw evidence and a new run if bytes change.",
        "The automated command runs the research workflow. No recurring job is installed, no new daily app predictions are published, and neither Supabase nor Flutter is changed.",
        "",
        "## Outputs",
        "",
        "research.sqlite and CSV tables contain query-to-grid mapping, cleaned records, rejections, features, training-only analyses, modelling partitions and validation scores.",
        "source_manifest.json links each request to raw files, retrieval time and checksums; run.json pins source/code/config/library versions and every frozen output.",
        "Optional evaluate-test writes TEST_REPORT.md and test_metrics.csv without changing model selection. The previous station experiment remains separate.",
        "",
        "Source and attribution: [Open-Meteo historical forecast API](https://open-meteo.com/en/docs/historical-forecast-api), [Open-Meteo licence and terms](https://open-meteo.com/en/terms). Weather data by Open-Meteo.com / NOAA GFS; CC BY 4.0.",
    ]
    (run / "REPORT.md").write_text("\n".join(lines) + "\n")


def run_pipeline(config=None, *, quick=False, refresh=False, api=None):
    """Execute ETL and modelling; atomically publish only a complete research snapshot."""
    config = config or Config()
    config.validate()
    root = Path(config.output_root)
    root.mkdir(parents=True, exist_ok=True)
    lock = root / ".pipeline.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, str(os.getpid()).encode())
        bundle = extract_data(config, api=api, refresh=refresh)
        paths = [
            p
            for folder in [
                Path(__file__).parent,
                Path(__file__).parent.parent / "nairobi_pipeline",
            ]
            for p in sorted(folder.glob("*.py"))
        ]
        signature = {
            "config": config.validate(),
            "source": bundle["manifest"],
            "code": {
                str(p.relative_to(Path(__file__).parents[2])): file_hash(p)
                for p in paths
            },
            "versions": {
                name: importlib.metadata.version(name)
                for name in [
                    "httpx",
                    "numpy",
                    "pandas",
                    "scikit-learn",
                    "xgboost",
                    "joblib",
                ]
            },
            "python": platform.python_version(),
            "labels_sha256": file_hash(config.labels) if config.labels else None,
            "quick": quick,
        }
        fingerprint = hashlib.sha256(
            json.dumps(signature, sort_keys=True).encode()
        ).hexdigest()
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
                    (run / name).is_file() and file_hash(run / name) == digest
                    for name, digest in record["artefact_sha256"].items()
                ):
                    print(f"Reusing verified research snapshot: {run}", flush=True)
                    return run
        run = root / (
            datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8]
        )
        run.mkdir()
        write_json(run / "source_manifest.json", bundle["manifest"])
        clean, rejected, audit = clean_data(bundle["raw"], bundle["stations"])
        features = transform_data(clean)
        tables = {
            "raw_weather": bundle["raw"],
            "stations": bundle["stations"],
            "query_grid_mapping": bundle["query_grid_mapping"],
            "cleaned_weather": clean,
            "rejected_rows": rejected,
            "cleaning_audit": audit,
            "features": features,
            **analyse(clean, bundle["stations"], config),
        }
        if config.mode != "audit":
            print(
                "Training Logistic Regression, Random Forest and XGBoost with chronological folds.",
                flush=True,
            )
            tables.update(build_models(clean, features, config, run, quick=quick))
        for name, table in tables.items():
            table = table.copy()
            table.columns = [
                "__".join(map(str, c)).rstrip("_") if isinstance(c, tuple) else str(c)
                for c in table.columns
            ]
            table.to_csv(run / f"{name}.csv", index=False)
        load_data(tables, run)
        write_report(run, config, bundle, tables)
        record = {
            "status": "complete",
            "fingerprint": fingerprint,
            "config": config.validate(),
            "signature": signature,
            "purpose": "OpenMeteo_model_rainfall_proxy_NOT_validated_flood_prediction",
            "test_evaluated_during_training": False,
            "feature_timing": "target UTC day t uses data dated <= t-1; retrospective archive does not establish as-issued availability",
            "artefact_sha256": {
                str(p.relative_to(run)): file_hash(p)
                for p in run.rglob("*")
                if p.is_file()
            },
        }
        write_json(run / "run.json", record)
        write_json(latest, {"run_id": run.name, "fingerprint": fingerprint})
        print(f"Complete: {run}", flush=True)
        return run
    finally:
        os.close(descriptor)
        lock.unlink(missing_ok=True)


def generate_schedule(destination, python_executable=sys.executable, hour=7, minute=0):
    """Write a reviewable research replay template; never install/enable it."""
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        raise ValueError("Invalid schedule time.")
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    schedule = {
        "Label": "org.floodsafe.openmeteo-research",
        "ProgramArguments": [
            str(Path(python_executable).absolute()),
            "-m",
            "scripts.openmeteo_pipeline",
            "run",
        ],
        "WorkingDirectory": str(Path(__file__).resolve().parents[2]),
        "StartCalendarInterval": {"Hour": hour, "Minute": minute},
        "StandardOutPath": str(destination.parent.resolve() / "openmeteo.stdout.log"),
        "StandardErrorPath": str(destination.parent.resolve() / "openmeteo.stderr.log"),
    }
    with destination.open("wb") as handle:
        plistlib.dump(schedule, handle)
    return destination


__all__ = [
    "analyse",
    "build_models",
    "evaluate_test",
    "generate_schedule",
    "run_pipeline",
]
