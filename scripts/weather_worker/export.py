"""One-time packaging from an already selected experiment; never fits a model."""

import json
import shutil
from pathlib import Path

import pandas as pd

from scripts.nairobi_pipeline.data import file_hash
from scripts.nairobi_pipeline.runner import write_json

from .bundle import load_bundle


def export_bundle(source, destination):
    source, destination = Path(source), Path(destination)
    record = json.loads((source / "run.json").read_text())
    for name in [
        "selection.json",
        "stations.csv",
        "source_manifest.json",
        "target_eligibility.csv",
    ]:
        if file_hash(source / name) != record["artefact_sha256"][name]:
            raise ValueError("Research source changed after freezing.")
    selection = json.loads((source / "selection.json").read_text())
    if (
        selection["selected_model"] != "logistic_regression"
        or selection["test_used_for_selection"]
    ):
        raise ValueError(
            "This release supports the validation-selected Logistic Regression only."
        )
    model = source / "models/logistic_regression.joblib"
    digest = selection["model_sha256"][model.name]
    if file_hash(model) != digest:
        raise ValueError("Selected model checksum mismatch.")
    if destination.exists():
        bundle = load_bundle(destination)
        if bundle["manifest"]["source_run_sha256"] != file_hash(source / "run.json"):
            raise ValueError("Export destination belongs to a different frozen run.")
        return bundle
    (destination / "reference").mkdir(parents=True)
    shutil.copyfile(model, destination / "model.joblib")
    for name in ["stations.csv", "source_manifest.json"]:
        shutil.copyfile(source / name, destination / "reference" / name)
    write_json(
        destination / "reference/run.json",
        {
            "kind": "minimal_exported_reference_NOT_a_new_training_run",
            "source_run_sha256": file_hash(source / "run.json"),
            "signature": {"code": record["signature"]["code"]},
            "artefact_sha256": {
                name: file_hash(destination / "reference" / name)
                for name in ["stations.csv", "source_manifest.json"]
            },
        },
    )
    import joblib

    artifact = joblib.load(model)
    thresholds = pd.read_csv(source / "target_eligibility.csv")
    manifest = {
        "schema_version": 1,
        "model_version": "nairobi-gfs-rainfall-lr-" + digest[:12],
        "model_family": "logistic_regression",
        "provider_model": "gfs_global",
        "target_kind": "high_rainfall_proxy",
        "operational_flood_model": False,
        "calibrated_flood_probability": False,
        "score_threshold": selection["score_threshold"],
        "source_run": source.name,
        "source_run_sha256": file_hash(source / "run.json"),
        "predictors": artifact["predictors"],
        "rain_threshold_mm": dict(
            zip(thresholds.station_id, thresholds.threshold_mm, strict=True)
        ),
        "runtime_versions": {
            name: record["signature"]["versions"][name]
            for name in ["numpy", "pandas", "scikit-learn", "joblib"]
        },
        "files": {
            str(path.relative_to(destination)): file_hash(path)
            for path in destination.rglob("*")
            if path.is_file()
        },
    }
    write_json(destination / "bundle.json", manifest)
    (destination / "bundle.sha256").write_text(
        file_hash(destination / "bundle.json") + "\n"
    )
    return load_bundle(destination)
