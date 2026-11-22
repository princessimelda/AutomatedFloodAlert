"""One hosted run: temporary working files, durable database inputs and scores."""

import json
import tempfile
from pathlib import Path

import pandas as pd

from scripts.nairobi_pipeline.data import file_hash
from scripts.openmeteo_pipeline.fresh import refresh_inputs, utc_now

from .contract import InferenceContractError, infer_current


def run_worker(bundle, store, *, now=None, api=None):
    clock = utc_now(now)
    if not store.lock():
        return {"status": "busy"}
    run = None
    try:
        run = store.begin(bundle, clock)
        if run is None:
            return {"status": "already_complete"}
        with tempfile.TemporaryDirectory(prefix="floodsafe-worker-") as temporary:
            root = Path(temporary)
            cache = api.root if api is not None else root / "raw"
            snapshot = refresh_inputs(
                output_root=root / "inputs",
                cache_root=str(cache),
                reference_run=bundle["path"] / "reference",
                now=now,
                api=api,
            )
            run_path = root / "inputs" / snapshot["run_id"]
            frame = pd.read_csv(run_path / "current_inputs.csv")
            predictions = []
            if snapshot["status"] == "ready":
                result = infer_current(bundle, frame, snapshot, now=utc_now(now))
                predictions = result.pop("predictions")
                snapshot["inference_contract"] = result
            source = json.loads((run_path / "source_manifest.json").read_text())
            responses = []
            for receipt in source["requests"]:
                path = cache / receipt["body_file"]
                if file_hash(path) != receipt["body_sha256"]:
                    raise ValueError("Fresh raw evidence changed before persistence.")
                responses.append({"receipt": receipt, "body": path.read_bytes()})
            status = store.finish(
                run,
                snapshot,
                pd.read_csv(run_path / "cleaned_weather.csv"),
                predictions,
                responses,
                utc_now(now),
            )
            return {
                "status": status,
                "run_id": run["id"],
                "model_version": bundle["manifest"]["model_version"],
                "prediction_count": len(predictions) if status == "ready" else 0,
            }
    except Exception as error:
        if run is not None:
            code = (
                error.code
                if isinstance(error, InferenceContractError)
                else type(error).__name__
            )
            store.fail(run, code, utc_now(now))
        raise
    finally:
        store.unlock()
