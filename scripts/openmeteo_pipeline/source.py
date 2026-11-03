"""API extraction with validated, immutable raw receipts and explicit grid identity."""

from __future__ import annotations

import hashlib
import json
import math
import os
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime
from pathlib import Path

import httpx
import pandas as pd

from scripts.nairobi_pipeline.data import WEATHER, file_hash
from scripts.nairobi_pipeline.data import Config as StationConfig

ENDPOINT = "https://historical-forecast-api.open-meteo.com/v1/forecast"
MODEL = "gfs_global"
VARIABLES = {
    "temperature_2m_mean": ("tavg", "°C"),
    "temperature_2m_min": ("tmin", "°C"),
    "temperature_2m_max": ("tmax", "°C"),
    "precipitation_sum": ("prcp", "mm"),
    "wind_speed_10m_mean": ("wspd", "km/h"),
    "pressure_msl_mean": ("pres", "hPa"),
}
# Study queries based on the existing Nairobi experiment. These are approximate
# query points, not certified station identities or independent observations.
POINTS = (
    ("western_nairobi", -1.30169, 36.75919),
    ("southern_nairobi", -1.320572, 36.815446),
    ("eastern_nairobi", -1.28, 36.87),
)


@dataclass(frozen=True)
class Config:
    start_date: str = "2021-04-01"
    end_date: str = "2025-12-31"
    calibration_end: str = "2022-12-31"
    train_end: str = "2023-12-31"
    validation_end: str = "2024-12-31"
    rain_quantile: float = 0.95
    min_train_observations: int = 365
    min_train_wet_days: int = 30
    min_history_days: int = 3
    seed: int = 42
    mode: str = "rainfall_proxy"
    labels: str | None = None
    output_root: str = "data/processed/openmeteo"
    cache_root: str = "data/raw/openmeteo"

    def validate(self):
        dates = [
            date.fromisoformat(getattr(self, field))
            for field in [
                "start_date",
                "calibration_end",
                "train_end",
                "validation_end",
                "end_date",
            ]
        ]
        if not (
            date(2021, 3, 23)
            <= dates[0]
            <= dates[1]
            < dates[2]
            < dates[3]
            < dates[4]
            < datetime.now(UTC).date()
        ):
            raise ValueError(
                "Require GFS coverage start <= start <= calibration < train < validation < end < today UTC."
            )
        StationConfig(
            calibration_end=self.calibration_end,
            train_end=self.train_end,
            validation_end=self.validation_end,
            rain_quantile=self.rain_quantile,
            min_history_days=self.min_history_days,
            mode=self.mode,
            labels=self.labels,
        ).validate()
        if self.min_train_observations < 1 or self.min_train_wet_days < 1:
            raise ValueError("Calibration support counts must be positive.")
        return asdict(self)


def request_parameters(latitude, longitude, start, end):
    return {
        "latitude": latitude,
        "longitude": longitude,
        "start_date": str(start),
        "end_date": str(end),
        "models": MODEL,
        "daily": ",".join(VARIABLES),
        "timezone": "GMT",
        "temperature_unit": "celsius",
        "wind_speed_unit": "kmh",
        "precipitation_unit": "mm",
        "cell_selection": "nearest",
        "elevation": "nan",
    }


def validate_response(document, params):
    """Reject ambiguous dates, changed units, malformed arrays and empty coverage."""
    if not isinstance(document, dict) or document.get("error"):
        raise ValueError("Expected one successful Open-Meteo location response.")
    if document.get("utc_offset_seconds") != 0 or document.get("timezone") not in {
        "GMT",
        "UTC",
    }:
        raise ValueError("Daily timestamps must use UTC/GMT.")
    for key, limit in [("latitude", 90), ("longitude", 180)]:
        value = document.get(key)
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or abs(value) > limit
        ):
            raise ValueError(f"Invalid returned {key}.")
    elevation = document.get("elevation")
    if (
        isinstance(elevation, bool)
        or not isinstance(elevation, (int, float))
        or not math.isfinite(elevation)
    ):
        raise ValueError("Missing finite grid elevation.")
    daily = document.get("daily", {})
    units = document.get("daily_units", {})
    expected = (
        pd.date_range(params["start_date"], params["end_date"])
        .strftime("%Y-%m-%d")
        .tolist()
    )
    if daily.get("time") != expected or units.get("time") != "iso8601":
        raise ValueError(
            "Daily dates must cover the requested range exactly, once, in order."
        )
    any_data = False
    for variable, (_, unit) in VARIABLES.items():
        values = daily.get(variable)
        if (
            units.get(variable) != unit
            or not isinstance(values, list)
            or len(values) != len(expected)
        ):
            raise ValueError(f"Malformed array or unexpected unit: {variable}.")
        for value in values:
            if value is None:
                continue
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
            ):
                raise ValueError(f"Non-numeric API measurement: {variable}.")
            any_data = True
    if not any_data:
        raise ValueError("API returned no usable measurements.")
    return document


class ApiClient:
    def __init__(
        self,
        cache_root,
        *,
        client=None,
        sleep=time.sleep,
        refresh=False,
        interval=1.1,
        endpoint=ENDPOINT,
    ):
        self.root = Path(cache_root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(60, connect=20), follow_redirects=False
        )
        self.owns_client = client is None
        self.sleep = sleep
        self.refresh = refresh
        self.interval = interval
        if endpoint not in {ENDPOINT, "https://api.open-meteo.com/v1/forecast"}:
            raise ValueError("Unsupported Open-Meteo endpoint.")
        self.endpoint = endpoint

    def close(self):
        if self.owns_client:
            self.client.close()

    def fetch(self, params):
        request = {"endpoint": self.endpoint, "parameters": params}
        key = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
        pointer = self.root / f"{key}.latest.json"
        if pointer.exists() and not self.refresh:
            receipt = json.loads(pointer.read_text())
            if (
                receipt["request"] != request
                or Path(receipt["body_file"]).name != receipt["body_file"]
            ):
                raise ValueError("Raw cache request identity changed.")
            body = self.root / receipt["body_file"]
            if file_hash(body) != receipt["body_sha256"]:
                raise ValueError(
                    "Raw cache checksum mismatch; inspect it or explicitly refresh."
                )
            return validate_response(json.loads(body.read_bytes()), params), receipt
        response = None
        for attempt in range(4):
            self.sleep(self.interval)
            try:
                response = self.client.get(self.endpoint, params=params)
                if response.status_code == 429 or response.status_code >= 500:
                    response.raise_for_status()
                response.raise_for_status()
                break
            except (httpx.TransportError, httpx.HTTPStatusError) as error:
                retryable = (
                    not isinstance(error, httpx.HTTPStatusError)
                    or error.response.status_code == 429
                    or error.response.status_code >= 500
                )
                if not retryable or attempt == 3:
                    raise
                retry_after = (
                    response.headers.get("Retry-After", "")
                    if response is not None
                    else ""
                )
                delay = (
                    min(60, float(retry_after))
                    if retry_after.isdigit()
                    else 2 ** (attempt + 1)
                )
                self.sleep(delay)
        document = validate_response(response.json(), params)
        body = response.content
        digest = hashlib.sha256(body).hexdigest()
        stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
        body_name = f"{key}.{stamp}.{digest[:12]}.json"
        (self.root / body_name).write_bytes(body)
        receipt = {
            "request": request,
            "retrieved_at_utc": datetime.now(UTC).isoformat(),
            "body_file": body_name,
            "body_sha256": digest,
            "provider_model": MODEL,
            "provider_model_version": "not supplied by API",
            "forecast_run_issued_at": "not supplied by API; retrieval time is not model issuance time",
            "http_status": response.status_code,
        }
        encoded = json.dumps(receipt, indent=2, allow_nan=False) + "\n"
        (self.root / f"{body_name}.receipt.json").write_text(encoded)
        temporary = pointer.with_suffix(f".{uuid.uuid4().hex}.tmp")
        temporary.write_text(encoded)
        os.replace(temporary, pointer)
        return document, receipt


def year_chunks(start, end):
    cursor, end = date.fromisoformat(str(start)), date.fromisoformat(str(end))
    while cursor <= end:
        finish = min(date(cursor.year, 12, 31), end)
        yield cursor, finish
        cursor = finish + pd.Timedelta(days=1)


def extract_data(config, *, api=None, refresh=False, points=POINTS):
    """Extract annual chunks; canonicalize provider cells, never multiply shared cells."""
    config.validate()
    client = api or ApiClient(config.cache_root, refresh=refresh)
    rows, grids, mappings, receipts = [], {}, [], []
    try:
        for name, latitude, longitude in points:
            for start, end in year_chunks(config.start_date, config.end_date):
                params = request_parameters(latitude, longitude, start, end)
                document, receipt = client.fetch(params)
                lat, lon = document["latitude"], document["longitude"]
                # Full numeric representations prevent rounding from merging nearby cells.
                identity = json.dumps([MODEL, lat, lon], separators=(",", ":"))
                station = (
                    MODEL + "_" + hashlib.sha256(identity.encode()).hexdigest()[:16]
                )
                metadata = {
                    "station_id": station,
                    "latitude": lat,
                    "longitude": lon,
                    "elevation_m": document["elevation"],
                }
                if station in grids and grids[station] != metadata:
                    raise ValueError(
                        "Provider grid metadata changed within the extraction."
                    )
                grids[station] = metadata
                mappings.append(
                    {
                        "query_id": name,
                        "requested_latitude": latitude,
                        "requested_longitude": longitude,
                        "station_id": station,
                    }
                )
                daily = document["daily"]
                frame = pd.DataFrame(
                    {
                        internal: daily[external]
                        for external, (internal, _) in VARIABLES.items()
                    }
                )
                frame["time"] = daily["time"]
                frame["station_id"] = station
                frame["source_row"] = range(1, len(frame) + 1)
                frame["source_filename"] = receipt["body_file"]
                rows.append(frame)
                receipts.append(receipt)
                print(f"Extracted {name}: {start} to {end} → {station}", flush=True)
    finally:
        if api is None:
            client.close()
    raw = pd.concat(rows, ignore_index=True)
    canonical = raw.drop_duplicates(["station_id", "time", *WEATHER])
    if canonical.duplicated(["station_id", "time"]).any():
        raise ValueError(
            "Conflicting measurements for the same provider grid/day; no averaging or arbitrary overwrite."
        )
    return {
        "raw": canonical.reset_index(drop=True),
        "stations": pd.DataFrame(grids.values()),
        "query_grid_mapping": pd.DataFrame(mappings)
        .drop_duplicates()
        .reset_index(drop=True),
        "manifest": {
            "provider": "Open-Meteo / NOAA GFS",
            "model": MODEL,
            "endpoint": client.endpoint,
            "daily_timezone": "GMT",
            "attribution": "Weather data by Open-Meteo.com; NOAA GFS. CC BY 4.0.",
            "source_kind": "stitched_historical_forecasts_NOT_station_observations"
            if client.endpoint == ENDPOINT
            else "forecast_api_recent_model_weather_NOT_station_observations",
            "grid_count": len(grids),
            "query_count": len(points),
            "duplicate_grid_day_rows_removed": len(raw) - len(canonical),
            "requests": receipts,
        },
    }
