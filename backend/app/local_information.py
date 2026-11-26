"""Public place lookup and weather estimates; neither produces a flood assessment."""

import json
import math
import unicodedata
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from threading import Lock
from time import monotonic
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import AwareDatetime, Field, field_validator

from .models import ContractModel
from .routing import Point


class SearchRequest(ContractModel):
    query: str = Field(min_length=3, max_length=120)

    @field_validator("query")
    @classmethod
    def public_place_name(cls, value):
        if any(unicodedata.category(c).startswith("C") for c in value):
            raise ValueError("Use a public place name.")
        value = " ".join(value.split())
        if len(value) < 3 or "@" in value or "://" in value:
            raise ValueError("Use a neighbourhood, road or landmark name.")
        return value


class SearchPlace(ContractModel):
    id: str
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(max_length=240)
    latitude: float = Field(ge=-1.50, le=-1.10)
    longitude: float = Field(ge=36.60, le=37.12)
    source: Literal["OpenStreetMap"] = "OpenStreetMap"


class LocalWeather(ContractModel):
    source: Literal["Open-Meteo"] = "Open-Meteo"
    kind: Literal["weather_estimate"] = "weather_estimate"
    rain_mm: float = Field(ge=0)
    interval_minutes: int = Field(ge=1, le=60)
    valid_at: AwareDatetime
    forecast_rain_mm: float = Field(ge=0)
    forecast_start: AwareDatetime
    forecast_end: AwareDatetime
    retrieved_at: AwareDatetime
    valid_until: AwareDatetime


class CachedPublicService:
    def __init__(self, endpoint, ttl):
        self.endpoint = endpoint
        self.ttl = ttl
        self.cache = OrderedDict()
        self.lock = Lock()
        self.last_fetch = -math.inf

    def load(self, key, params, parse):
        if not self.lock.acquire(blocking=False):
            raise HTTPException(429, "Please wait a moment and try again.")
        try:
            tick = monotonic()
            cached = self.cache.get(key)
            if cached and tick - cached[0] < self.ttl:
                self.cache.move_to_end(key)
                return cached[1]
            if tick - self.last_fetch < 1:
                raise HTTPException(429, "Please wait a moment and try again.")
            self.last_fetch = tick
            try:
                with httpx.Client(timeout=12, follow_redirects=False) as client:
                    with client.stream(
                        "GET",
                        self.endpoint,
                        params=params,
                        headers={
                            "User-Agent": "FloodSafe/0.1 (+https://github.com/princessimelda/AutomatedFloodAlert)"
                        },
                    ) as response:
                        response.raise_for_status()
                        body = bytearray()
                        for chunk in response.iter_bytes():
                            body.extend(chunk)
                            if len(body) > 256000:
                                raise ValueError("Response too large")
                result = parse(json.loads(body), datetime.now(timezone.utc))
            except (httpx.HTTPError, ValueError, KeyError, TypeError, OverflowError):
                raise HTTPException(503, "Local information is temporarily unavailable.") from None
            self.cache[key] = (monotonic(), result)
            self.cache.move_to_end(key)
            while len(self.cache) > 128:
                self.cache.popitem(last=False)
            return result
        finally:
            self.lock.release()


def parse_places(data, now):
    features = data["features"]
    if not isinstance(features, list) or len(features) > 100:
        raise ValueError("Invalid place results")
    places, seen = [], set()
    for feature in features:
        props, geometry = feature["properties"], feature["geometry"]
        if not isinstance(props, dict) or not isinstance(geometry, dict):
            raise ValueError("Invalid place result")
        if geometry["type"] != "Point":
            raise ValueError("Invalid geometry")
        lon, lat = geometry["coordinates"]
        if (
            isinstance(lat, bool)
            or isinstance(lon, bool)
            or not math.isfinite(lat)
            or not math.isfinite(lon)
        ):
            raise ValueError("Invalid coordinates")
        country = props.get("countrycode", "")
        if not isinstance(country, str):
            raise ValueError("Invalid country code")
        if not (-1.50 <= lat <= -1.10 and 36.60 <= lon <= 37.12) or country.upper() != "KE":
            continue
        name = props.get("name") or props.get("street")
        if not isinstance(name, str) or not name.strip():
            continue
        name = " ".join(name.split())[:120]
        kind, identity = props["osm_type"], props["osm_id"]
        if (
            kind not in {"N", "W", "R"}
            or not isinstance(identity, int)
            or isinstance(identity, bool)
            or identity <= 0
        ):
            raise ValueError("Invalid place identifier")
        key = (name.casefold(), round(lat, 5), round(lon, 5))
        if key in seen:
            continue
        seen.add(key)
        area = []
        for field in ("district", "city", "county", "state"):
            text = props.get(field)
            if (
                isinstance(text, str)
                and text
                and text.casefold() not in {name.casefold(), *(a.casefold() for a in area)}
            ):
                area.append(text)
        places.append(
            SearchPlace(
                id=f"gps:search:{kind}{identity}",
                name=name,
                description=", ".join(area)[:240] or "Nairobi area",
                latitude=lat,
                longitude=lon,
            )
        )
    return places[:6]


def parse_weather(data, now):
    current, hourly = data["current"], data["hourly"]
    for group in ("current_units", "hourly_units"):
        if (
            any(data[group][name] != "mm" for name in ("rain", "showers"))
            or data[group]["time"] != "unixtime"
        ):
            raise ValueError("Unexpected weather units")

    def amount(value):
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or value < 0
        ):
            raise ValueError("Missing or invalid rainfall")
        return value

    def timestamp(value):
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError("Invalid weather time")
        return datetime.fromtimestamp(value, timezone.utc)

    valid_at = timestamp(current["time"])
    if not now - timedelta(minutes=90) <= valid_at <= now + timedelta(minutes=15):
        raise ValueError("Weather estimate out of date")
    interval = current["interval"]
    if (
        isinstance(interval, bool)
        or not isinstance(interval, int)
        or not 60 <= interval <= 3600
        or interval % 60
    ):
        raise ValueError("Invalid rainfall interval")
    start = valid_at.replace(minute=0, second=0, microsecond=0)
    end = start + timedelta(hours=24)
    times, rain, showers = hourly["time"], hourly["rain"], hourly["showers"]
    if not (len(times) == len(rain) == len(showers)) or len(times) > 48:
        raise ValueError("Incomplete forecast")
    rows = [(timestamp(t), r, s) for t, r, s in zip(times, rain, showers)]
    selected = [(t, r, s) for t, r, s in rows if start < t <= end]
    expected = [start + timedelta(hours=i) for i in range(1, 25)]
    if [t for t, _, _ in selected] != expected:
        raise ValueError("Incomplete forecast period")
    return LocalWeather(
        rain_mm=round(amount(current["rain"]) + amount(current["showers"]), 2),
        interval_minutes=interval // 60,
        valid_at=valid_at,
        forecast_rain_mm=round(sum(amount(r) + amount(s) for _, r, s in selected), 2),
        forecast_start=start,
        forecast_end=end,
        retrieved_at=now,
        valid_until=min(now + timedelta(minutes=15), valid_at + timedelta(minutes=90)),
    )


def local_information_router(settings, search_service=None, weather_service=None):
    router = APIRouter()
    search_service = search_service or CachedPublicService(settings.geocoding_url, 86400)
    weather_service = weather_service or CachedPublicService(
        "https://api.open-meteo.com/v1/forecast", 600
    )

    @router.post("/v1/places/search", response_model=list[SearchPlace])
    def search(request: SearchRequest):
        query = request.query.casefold()
        return search_service.load(
            query,
            {
                "q": query,
                "bbox": "36.60,-1.50,37.12,-1.10",
                "countrycode": "KE",
                "limit": 10,
                "lang": "en",
            },
            parse_places,
        )

    @router.post("/v1/weather", response_model=LocalWeather)
    def weather(request: Point):
        # Weather grids do not need precise device coordinates. No coordinate persistence.
        key = (round(request.latitude, 2), round(request.longitude, 2))
        return weather_service.load(
            key,
            {
                "latitude": key[0],
                "longitude": key[1],
                "current": "rain,showers",
                "hourly": "rain,showers",
                "forecast_hours": 25,
                "timezone": "UTC",
                "timeformat": "unixtime",
            },
            parse_weather,
        )

    return router
