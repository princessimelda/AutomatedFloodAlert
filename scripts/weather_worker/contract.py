"""Versioned, timestamped internal inference boundary; no HTTP endpoint."""

from datetime import UTC, date, datetime, timedelta

import pandas as pd

from .bundle import predict

CONTRACT_VERSION = "rainfall-inference/v1"
LIMITATIONS = [
    "Experimental high-rainfall proxy; not a calibrated flood probability.",
    "Provider model weather, not station observations or verified flood events.",
    "Coarse trained grid cells; no street-level hazards or safe-route claims.",
    "As-issued forecast lead time has not been validated.",
]


class InferenceContractError(ValueError):
    """Stable non-sensitive failure code for worker records."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _timestamp(value):
    try:
        parsed = datetime.fromisoformat(value) if isinstance(value, str) else value
        if not isinstance(parsed, datetime) or parsed.tzinfo is None:
            raise ValueError
        return parsed.astimezone(UTC)
    except (ValueError, TypeError):
        raise InferenceContractError("invalid_timestamp") from None


def infer_current(bundle, frame, snapshot, *, now):
    """Score fresh target-day inputs using a verified bundle/ingestion snapshot.

    The worker verifies raw-source evidence and frozen preprocessing upstream.
    Historic replay belongs in the research pipeline, not this current boundary.
    """
    clock = _timestamp(now)
    required = {
        "status",
        "target_date_utc",
        "retrieved_at_utc",
        "completed_at_utc",
        "expires_at_utc",
        "history_start_utc",
        "history_end_utc",
        "provider_model",
    }
    if not required.issubset(snapshot):
        raise InferenceContractError("missing_snapshot_fields")
    if snapshot["status"] != "ready":
        raise InferenceContractError("inputs_not_ready")
    retrieved = _timestamp(snapshot["retrieved_at_utc"])
    completed = _timestamp(snapshot["completed_at_utc"])
    expires = _timestamp(snapshot["expires_at_utc"])
    try:
        target = date.fromisoformat(snapshot["target_date_utc"])
        start = date.fromisoformat(snapshot["history_start_utc"])
        end = date.fromisoformat(snapshot["history_end_utc"])
    except (TypeError, ValueError):
        raise InferenceContractError("invalid_date") from None
    if not retrieved <= completed <= clock or expires <= completed:
        raise InferenceContractError("invalid_timestamp_order")
    expiry = min(
        expires,
        retrieved + timedelta(hours=2),
        datetime.combine(target + timedelta(days=1), datetime.min.time(), tzinfo=UTC),
    )
    if target != clock.date() or clock >= expiry:
        raise InferenceContractError("stale_inputs")
    if start != target - timedelta(days=7) or end != target - timedelta(days=1):
        raise InferenceContractError("invalid_history_window")
    if snapshot["provider_model"] != bundle["manifest"]["provider_model"]:
        raise InferenceContractError("provider_model_mismatch")
    if "time" not in frame:
        raise InferenceContractError("missing_target_dates")
    dates = pd.to_datetime(frame["time"], errors="coerce", utc=True)
    if dates.isna().any() or not dates.eq(pd.Timestamp(target, tz="UTC")).all():
        raise InferenceContractError("target_date_mismatch")
    if "station_id" not in frame:
        raise InferenceContractError("missing_grid_ids")
    try:
        rows = predict(bundle, frame)
    except (ValueError, TypeError, KeyError):
        raise InferenceContractError("invalid_predictors") from None
    manifest = bundle["manifest"]
    return {
        "contract_version": CONTRACT_VERSION,
        "model_version": manifest["model_version"],
        "bundle_sha256": bundle["sha256"],
        "target_kind": "high_rainfall_proxy",
        "experimental": True,
        "calibrated_flood_probability": False,
        "target_date_utc": str(target),
        "input_retrieved_at_utc": retrieved.isoformat(),
        "generated_at_utc": clock.isoformat(),
        "valid_until_utc": expiry.isoformat(),
        "score_threshold": manifest["score_threshold"],
        "limitations": list(LIMITATIONS),
        "predictions": rows,
    }
