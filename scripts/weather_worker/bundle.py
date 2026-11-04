"""Load only the repository's checksum-verified frozen model bundle."""

import hashlib
import importlib.metadata
import json
from pathlib import Path

import joblib
import numpy as np

from scripts.nairobi_pipeline.data import file_hash

DEFAULT_BUNDLE = Path(__file__).resolve().parents[2] / "models/openmeteo_rainfall_v1"


def load_bundle(path=DEFAULT_BUNDLE):
    path = Path(path)
    expected = (path / "bundle.sha256").read_text().strip()
    if file_hash(path / "bundle.json") != expected:
        raise ValueError("Bundle manifest checksum mismatch.")
    manifest = json.loads((path / "bundle.json").read_text())
    for package, version in manifest["runtime_versions"].items():
        if importlib.metadata.version(package) != version:
            raise ValueError(
                "Runtime versions differ from the frozen model environment."
            )
    if (
        manifest["target_kind"] != "high_rainfall_proxy"
        or manifest["operational_flood_model"]
    ):
        raise ValueError("Unsupported model purpose.")
    required = {
        "model.joblib",
        "reference/stations.csv",
        "reference/source_manifest.json",
        "reference/run.json",
    }
    if set(manifest["files"]) != required:
        raise ValueError("Bundle must checksum every required model/reference member.")
    for name, digest in manifest["files"].items():
        candidate = (path / name).resolve()
        if (
            not candidate.is_relative_to(path.resolve())
            or file_hash(candidate) != digest
        ):
            raise ValueError("Bundle member/checksum mismatch.")
    # The exported model contains standard sklearn objects only, not custom
    # project estimators or XGBoost; no runtime training data is needed.
    artifact = joblib.load(path / "model.joblib")
    if artifact["predictors"] != manifest["predictors"]:
        raise ValueError("Model predictor order differs from the bundle contract.")
    return {
        "path": path,
        "manifest": manifest,
        "sha256": expected,
        "artifact": artifact,
    }


def predict(bundle, frame):
    manifest = bundle["manifest"]
    predictors = manifest["predictors"]
    expected_grids = set(manifest["rain_threshold_mm"])
    if frame.station_id.duplicated().any() or set(frame.station_id) != expected_grids:
        raise ValueError("Inference requires exactly the trained grid cells.")
    if not set(predictors).issubset(frame) or frame[predictors].isna().any().any():
        raise ValueError("Incomplete predictor rows cannot be published.")
    numeric = frame[[key for key in predictors if key != "station_id"]].to_numpy(
        dtype=float
    )
    if not np.isfinite(numeric).all():
        raise ValueError("Predictors must be finite.")
    scores = bundle["artifact"]["pipeline"].predict_proba(frame[predictors])[:, 1]
    if not np.isfinite(scores).all() or ((scores < 0) | (scores > 1)).any():
        raise ValueError("Invalid model scores.")
    rows = []
    for (_, row), score in zip(frame.iterrows(), scores, strict=True):
        features = {
            name: str(row[name]) if name == "station_id" else float(row[name])
            for name in predictors
        }
        encoded = json.dumps(features, sort_keys=True, allow_nan=False)
        rows.append(
            {
                "grid_id": row.station_id,
                "score": float(score),
                "predicted_high_rainfall": bool(score >= manifest["score_threshold"]),
                "rain_threshold_mm": manifest["rain_threshold_mm"][row.station_id],
                "features": features,
                "feature_sha256": hashlib.sha256(encoded.encode()).hexdigest(),
            }
        )
    return rows
