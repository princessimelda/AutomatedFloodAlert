"""Fetch recent model weather and prepare dated inputs without training/inference."""

from __future__ import annotations

import ast
import hashlib
import json
import os
import plistlib
import sys
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pandas as pd

from scripts.nairobi_pipeline.data import WEATHER, clean_data, file_hash, transform_data
from scripts.nairobi_pipeline.runner import load_data, write_json

from .source import MODEL, ApiClient, extract_data, request_parameters

LIVE_ENDPOINT = "https://api.open-meteo.com/v1/forecast"


def utc_now(now=None):
    value = now or datetime.now(UTC)
    if value.tzinfo is None:
        raise ValueError("An explicit clock must include its timezone.")
    return value.astimezone(UTC)


@dataclass(frozen=True)
class RecentWindow:
    start_date: str
    end_date: str
    cache_root: str

    def validate(self):
        if (pd.Timestamp(self.end_date) - pd.Timestamp(self.start_date)).days != 6:
            raise ValueError("Fresh inputs require exactly seven completed UTC days.")


def resolve_reference(reference_run=None):
    if reference_run is not None:
        return Path(reference_run)
    root = Path("data/processed/openmeteo")
    return root / json.loads((root / "latest.json").read_text())["run_id"]


def preprocessing_fingerprint(source):
    """Ignore source-selection config only; preserve every preprocessing/feature AST node."""
    tree = ast.parse(source)
    tree.body = [
        node
        for node in tree.body
        if not isinstance(node, (ast.FunctionDef, ast.ClassDef))
        or node.name not in {"Config", "extract_data"}
    ]
    return hashlib.sha256(ast.dump(tree, include_attributes=False).encode()).hexdigest()


def verify_preprocessing(reference_hash, path):
    if reference_hash == file_hash(path):
        return
    migration = json.loads(
        Path(__file__).with_name("feature_compatibility.json").read_text()
    )
    fingerprint = preprocessing_fingerprint(Path(path).read_text())
    if any(
        item["module_sha256"] == reference_hash
        and item["preprocessing_ast_sha256"] == fingerprint
        for item in migration["legacy_modules"]
    ):
        return
    raise ValueError(
        "Feature engineering changed since training; review compatibility first."
    )


def verify_reference(bundle, reference):
    """Match live grid/units/feature definitions to the existing research snapshot."""
    record = json.loads((reference / "run.json").read_text())
    for filename in ["stations.csv", "source_manifest.json"]:
        if file_hash(reference / filename) != record["artefact_sha256"][filename]:
            raise ValueError(f"Training reference changed: {filename}")
    feature_path = "scripts/nairobi_pipeline/data.py"
    verify_preprocessing(
        record["signature"]["code"][feature_path],
        Path(__file__).parents[2] / feature_path,
    )
    manifest = json.loads((reference / "source_manifest.json").read_text())
    if manifest["model"] != MODEL:
        raise ValueError("Training and live provider models differ.")
    expected = request_parameters(0, 0, "2000-01-01", "2000-01-07")
    contract = {
        "models",
        "daily",
        "timezone",
        "temperature_unit",
        "wind_speed_unit",
        "precipitation_unit",
        "cell_selection",
        "elevation",
    }
    for receipt in manifest["requests"]:
        if any(
            receipt["request"]["parameters"].get(key) != expected[key]
            for key in contract
        ):
            raise ValueError("Training and live weather contracts differ.")
    trained = (
        pd.read_csv(reference / "stations.csv").set_index("station_id").sort_index()
    )
    incoming = bundle["stations"].set_index("station_id").sort_index()
    try:
        pd.testing.assert_frame_equal(
            trained, incoming, check_dtype=False, check_exact=True
        )
    except AssertionError as error:
        raise ValueError(
            "Live provider cells/elevations differ from training; no automatic remapping."
        ) from error


def prepare_inputs(cleaned, stations, target_date):
    """Append an empty target day; only earlier completed days feed its features."""
    target = stations.copy().assign(time=pd.Timestamp(target_date))
    for name in WEATHER:
        target[name] = float("nan")
    history = cleaned[
        ["station_id", "time", "latitude", "longitude", "elevation_m", *WEATHER]
    ]
    features = transform_data(
        pd.concat([history, target], ignore_index=True)
        .sort_values(["station_id", "time"])
        .reset_index(drop=True)
    )
    current = features.loc[features.time.eq(pd.Timestamp(target_date))].copy()
    readiness = []
    for _, row in current.iterrows():
        missing = [
            name
            for name in current
            if name not in {"station_id", "time"} and pd.isna(row[name])
        ]
        readiness.append(
            {
                "station_id": row.station_id,
                "ready": not missing,
                "missing_features": json.dumps(missing),
            }
        )
    return features, current, pd.DataFrame(readiness)


def refresh_inputs(
    *,
    output_root="data/live/openmeteo",
    cache_root="data/raw/openmeteo_live",
    reference_run=None,
    now=None,
    api=None,
):
    """Always refresh recent API bytes; commit a new local snapshot, never refit models."""
    clock = utc_now(now)
    target_date = clock.date()
    root = Path(output_root)
    root.mkdir(parents=True, exist_ok=True)
    lock = root / ".refresh.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    client = None
    try:
        os.write(descriptor, str(os.getpid()).encode())
        reference = resolve_reference(reference_run)
        window = RecentWindow(
            str(target_date - timedelta(days=7)),
            str(target_date - timedelta(days=1)),
            cache_root,
        )
        client = api or ApiClient(cache_root, endpoint=LIVE_ENDPOINT, refresh=True)
        if client.endpoint != LIVE_ENDPOINT or not client.refresh:
            raise ValueError(
                "Fresh ingestion must use a new Forecast API retrieval, never a cached/archive fallback."
            )
        bundle = extract_data(window, api=client)
        verify_reference(bundle, reference)
        cleaned, rejected, audit = clean_data(bundle["raw"], bundle["stations"])
        features, current, readiness = prepare_inputs(
            cleaned, bundle["stations"], target_date
        )
        run = root / (clock.strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8])
        run.mkdir()
        tables = {
            "raw_weather": bundle["raw"],
            "stations": bundle["stations"],
            "query_grid_mapping": bundle["query_grid_mapping"],
            "cleaned_weather": cleaned,
            "rejected_rows": rejected,
            "cleaning_audit": audit,
            "features": features,
            "current_inputs": current,
            "grid_readiness": readiness,
        }
        for name, table in tables.items():
            table.to_csv(run / f"{name}.csv", index=False)
        load_data(tables, run)
        write_json(run / "source_manifest.json", bundle["manifest"])
        status = {
            "status": "ready" if readiness.ready.all() else "incomplete",
            "run_id": run.name,
            "retrieved_at_utc": clock.isoformat(),
            "completed_at_utc": utc_now(now).isoformat(),
            "target_date_utc": str(target_date),
            "history_start_utc": window.start_date,
            "history_end_utc": window.end_date,
            "expires_at_utc": datetime.combine(
                target_date + timedelta(days=1), datetime.min.time(), tzinfo=UTC
            ).isoformat(),
            "grid_count": len(bundle["stations"]),
            "ready_grids": int(readiness.ready.sum()),
            "provider_model": MODEL,
            "endpoint": LIVE_ENDPOINT,
            "source_kind": "recent_model_weather_NOT_station_observations",
            "reference_run": str(reference.absolute()),
            "model_training_performed": False,
            "model_inference_performed": False,
            "forecast_issued_at_utc": None,
            "feature_timing": "target day uses seven completed UTC days, excluding today's partial weather",
            "artefact_sha256": {
                p.name: file_hash(p) for p in run.iterdir() if p.is_file()
            },
        }
        write_json(run / "snapshot.json", status)
        # status.json is authoritative: incomplete/latest failures must not expose
        # a previous successful snapshot as current.
        write_json(
            root / "latest.json",
            {"run_id": run.name, "snapshot_sha256": file_hash(run / "snapshot.json")},
        )
        write_json(
            root / "status.json",
            {
                "status": status["status"],
                "run_id": run.name,
                "attempted_at_utc": clock.isoformat(),
            },
        )
        return status
    except Exception as error:
        write_json(
            root / "status.json",
            {
                "status": "unavailable",
                "attempted_at_utc": clock.isoformat(),
                "reason": type(error).__name__,
            },
        )
        raise
    finally:
        if client is not None and api is None:
            client.close()
        os.close(descriptor)
        lock.unlink(missing_ok=True)


def latest_inputs(output_root="data/live/openmeteo", *, now=None):
    """Return usable inputs only while the latest attempt, day and hashes are valid."""
    clock, root = utc_now(now), Path(output_root)
    if not (root / "status.json").exists():
        return {"status": "unavailable", "inputs": []}
    state = json.loads((root / "status.json").read_text())
    if state["status"] != "ready":
        return {**state, "inputs": []}
    pointer = json.loads((root / "latest.json").read_text())
    run = root / pointer["run_id"]
    if (
        state["run_id"] != run.name
        or file_hash(run / "snapshot.json") != pointer["snapshot_sha256"]
    ):
        raise ValueError("Latest weather pointer or snapshot changed.")
    snapshot = json.loads((run / "snapshot.json").read_text())
    if clock >= datetime.fromisoformat(snapshot["expires_at_utc"]) or snapshot[
        "target_date_utc"
    ] != str(clock.date()):
        return {
            "status": "stale",
            "target_date_utc": snapshot["target_date_utc"],
            "inputs": [],
        }
    if clock < datetime.fromisoformat(snapshot["retrieved_at_utc"]):
        return {"status": "unavailable", "reason": "snapshot_from_future", "inputs": []}
    for name, digest in snapshot["artefact_sha256"].items():
        if file_hash(run / name) != digest:
            raise ValueError(f"Fresh weather artefact changed: {name}")
    return {
        **snapshot,
        "inputs": pd.read_csv(run / "current_inputs.csv").to_dict("records"),
    }


def generate_fresh_schedule(
    destination, *, python_executable=sys.executable, interval=3600, reference_run=None
):
    """Create a macOS hourly refresh template; installation is a separate action."""
    if interval < 3600:
        raise ValueError("Refresh no more than hourly for this development workflow.")
    path = Path(destination)
    path.parent.mkdir(parents=True, exist_ok=True)
    schedule = {
        "Label": "org.floodsafe.openmeteo-fresh",
        "ProgramArguments": [
            str(Path(python_executable).absolute()),
            "-m",
            "scripts.openmeteo_pipeline",
            "refresh-inputs",
        ],
        "WorkingDirectory": str(Path(__file__).resolve().parents[2]),
        "RunAtLoad": True,
        "StartInterval": interval,
        "StandardOutPath": str(path.parent.resolve() / "fresh.stdout.log"),
        "StandardErrorPath": str(path.parent.resolve() / "fresh.stderr.log"),
    }
    if reference_run is not None:
        schedule["ProgramArguments"] += [
            "--reference-run",
            str(Path(reference_run).absolute()),
        ]
    with path.open("wb") as handle:
        plistlib.dump(schedule, handle)
    return path
