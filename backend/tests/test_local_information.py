from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.config import Settings
from app.local_information import CachedPublicService, parse_places, parse_weather
from app.main import create_app

NOW = datetime(2026, 11, 25, 17, 30, tzinfo=timezone.utc)


def place(name="Mathare", lon=36.87, lat=-1.26, country="KE", identity=100):
    return {
        "properties": {
            "name": name,
            "city": "Nairobi",
            "countrycode": country,
            "osm_type": "N",
            "osm_id": identity,
        },
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
    }


def weather():
    start = NOW.replace(minute=0)
    return {
        "current_units": {"time": "unixtime", "rain": "mm", "showers": "mm"},
        "hourly_units": {"time": "unixtime", "rain": "mm", "showers": "mm"},
        "current": {"time": int(NOW.timestamp()), "interval": 900, "rain": 0, "showers": 0.2},
        "hourly": {
            "time": [int((start + timedelta(hours=i)).timestamp()) for i in range(25)],
            "rain": [1] * 25,
            "showers": [0.5] * 25,
        },
    }


def test_geocoder_deduplicates_and_filters_foreign_or_out_of_area_places():
    results = parse_places(
        {
            "features": [
                place(),
                place(identity=101),
                place("Other", country="GB"),
                place("Far away", lat=0),
            ]
        },
        NOW,
    )
    assert len(results) == 1
    assert results[0].id == "gps:search:N100"
    assert results[0].description == "Nairobi"
    assert results[0].source == "OpenStreetMap"
    assert "assessment" not in results[0].model_dump()


def test_weather_estimate_uses_both_rain_and_showers_and_complete_forecast_window():
    result = parse_weather(weather(), NOW)
    assert result.rain_mm == 0.2
    assert result.forecast_rain_mm == 36
    assert result.forecast_end - result.forecast_start == timedelta(hours=24)
    assert result.kind == "weather_estimate"
    assert result.valid_until > NOW
    assert "risk" not in result.model_dump()


@pytest.mark.parametrize("invalid", [None, -1, float("nan"), True])
def test_missing_or_invalid_rainfall_never_becomes_zero(invalid):
    data = weather()
    data["hourly"]["rain"][3] = invalid
    with pytest.raises(ValueError):
        parse_weather(data, NOW)


def test_stale_wrong_units_and_incomplete_forecast_are_rejected():
    data = weather()
    with pytest.raises(ValueError):
        parse_weather(data, NOW + timedelta(hours=2))
    data["hourly"]["time"].pop()
    with pytest.raises(ValueError):
        parse_weather(data, NOW)
    data = weather()
    data["current_units"]["rain"] = "inch"
    with pytest.raises(ValueError):
        parse_weather(data, NOW)


def test_public_service_caches_limits_requests_and_distinguishes_outage(monkeypatch):
    tick = [10.0]
    monkeypatch.setattr("app.local_information.monotonic", lambda: tick[0])
    calls = []
    original = httpx.Client

    def respond(request):
        calls.append(request)
        return httpx.Response(200, json={"features": [place()]})

    monkeypatch.setattr(
        "app.local_information.httpx.Client",
        lambda **kw: original(transport=httpx.MockTransport(respond), **kw),
    )
    service = CachedPublicService("https://photon.komoot.io/api/", 100)
    assert service.load("mathare", {"q": "mathare"}, parse_places)[0].name == "Mathare"
    service.load("mathare", {"q": "mathare"}, parse_places)
    assert len(calls) == 1
    with pytest.raises(HTTPException) as limited:
        service.load("ngara", {"q": "ngara"}, parse_places)
    assert limited.value.status_code == 429
    tick[0] += 2
    monkeypatch.setattr(
        "app.local_information.httpx.Client",
        lambda **kw: original(transport=httpx.MockTransport(lambda r: httpx.Response(503)), **kw),
    )
    with pytest.raises(HTTPException) as failed:
        service.load("ngara", {"q": "ngara"}, parse_places)
    assert failed.value.status_code == 503


def test_post_search_contract_and_weather_rounding():
    calls = []

    class Search:
        def load(self, key, params, parse):
            calls.append((key, params))
            return parse({"features": [place()]}, NOW)

    class Weather:
        def load(self, key, params, parse):
            calls.append((key, params))
            return parse(weather(), NOW)

    settings = Settings(_env_file=None, data_mode="fixtures", allow_demo_data=True)
    with TestClient(
        create_app(settings, search_service=Search(), weather_service=Weather())
    ) as client:
        found = client.post("/v1/places/search", json={"query": "  Mathare  "})
        assert found.status_code == 200
        assert found.json()[0]["id"] == "gps:search:N100"
        assert calls[0][0] == "mathare"
        assert calls[0][1]["countrycode"] == "KE"
        assert client.get("/v1/places/search").status_code == 405
        invalid = client.post("/v1/places/search", json={"query": "private@example.com"})
        assert invalid.status_code == 422
        assert "private@example" not in invalid.text
        response = client.post(
            "/v1/weather", json={"latitude": -1.2584151, "longitude": 36.8712653}
        )
        assert response.status_code == 200
        assert calls[-1][0] == (-1.26, 36.87)
        assert response.headers["cache-control"] == "no-store"
