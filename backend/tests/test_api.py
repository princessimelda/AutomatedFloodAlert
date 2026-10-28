from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.repositories import DatabaseUnavailable, FixtureRepository


def fixture_settings(**overrides):
    return Settings(_env_file=None, data_mode="fixtures", allow_demo_data=True, **overrides)


@pytest.fixture
def client():
    with TestClient(create_app(fixture_settings())) as client:
        yield client


def test_place_dashboard_and_advisory_contract(client):
    places = client.get("/v1/places")
    assert places.status_code == 200
    assert {place["id"] for place in places.json()} == {
        "kibera",
        "westlands",
        "embakasi",
        "kasarani",
    }
    response = client.post("/v1/dashboard", json={"place_id": "kibera"})
    assert response.status_code == 200
    result = response.json()
    assert result["is_demo"] is True
    assert result["assessment"]["level"] == "high"
    assert result["place_id"] == "kibera"
    advisory = client.get("/v1/advisories?place_id=kibera").json()[0]
    assert advisory["is_demo"] is True
    assert advisory["source_url"].startswith("https://")
    assert client.get("/v1/advisories?language=sw").json() == []
    assert response.headers["cache-control"] == "no-store"


def test_unavailable_and_expired_do_not_become_current_low_risk(client):
    assert client.post("/v1/dashboard", json={"place_id": "westlands"}).json()["assessment"] is None
    expired = client.post("/v1/dashboard", json={"place_id": "embakasi"}).json()["assessment"]
    assert datetime.fromisoformat(expired["valid_until"].replace("Z", "+00:00")) < datetime.now(
        timezone.utc
    )
    assert (
        client.post("/v1/dashboard", json={"place_id": "embakasi"}).json()["assessment"] == expired
    )


def test_coordinates_do_not_inherit_fixture_risk(client):
    response = client.post(
        "/v1/dashboard",
        json={"place_id": "gps:test", "latitude": -1.29, "longitude": 36.82},
    )
    assert response.status_code == 200
    assert response.json()["assessment"] is None


@pytest.mark.parametrize(
    "payload",
    [
        {"place_id": "gps:test", "latitude": 91, "longitude": 36.82},
        {"place_id": "gps:test", "latitude": -1.29},
        {"place_id": "kibera", "latitude": -1.29, "longitude": 36.82},
        {"place_id": "kibera", "extra": "secret-value"},
        {"place_id": "x' OR true--"},
        {"place_id": "gps:test"},
    ],
)
def test_invalid_requests_have_consistent_redacted_errors(client, payload):
    response = client.post("/v1/dashboard", json=payload)
    assert response.status_code == 422
    assert set(response.json()) == {"code", "message"}
    assert "secret-value" not in response.text
    assert "36.82" not in response.text


def test_not_found_and_disallowed_operations(client):
    assert client.post("/v1/dashboard", json={"place_id": "unknown"}).status_code == 404
    assert client.post("/v1/places", json={}).status_code == 405
    assert client.get("/v1/advisories?limit=101").status_code == 422
    assert client.get("/v1/advisories?language=xx").status_code == 422
    assert client.get("/v1/me").status_code == 404


def test_cors_exact_origins(client):
    headers = {
        "origin": "http://localhost:8765",
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type",
    }
    response = client.options("/v1/dashboard", headers=headers)
    assert response.headers["access-control-allow-origin"] == "http://localhost:8765"
    headers["origin"] = "https://untrusted.example"
    response = client.options("/v1/dashboard", headers=headers)
    assert "access-control-allow-origin" not in response.headers


def test_database_outage_is_not_replaced_with_fixtures():
    class BrokenStore(FixtureRepository):
        def dashboard(self, request):
            raise DatabaseUnavailable("never disclose this database detail")

        def ping(self):
            raise DatabaseUnavailable()

    with TestClient(create_app(fixture_settings(), BrokenStore())) as client:
        response = client.post("/v1/dashboard", json={"place_id": "kibera"})
        assert response.status_code == 503
        assert "detail" not in response.text
        assert "assessment" not in response.json()
        assert client.get("/healthz").status_code == 200
        assert client.get("/readyz").status_code == 503


def test_fixture_mode_requires_opt_in():
    with pytest.raises(ValueError):
        create_app(Settings(_env_file=None, data_mode="fixtures", allow_demo_data=False))


def test_guided_assistant_catalogue_does_not_accept_arbitrary_chat(client):
    assert client.get("/v1/assistant/questions").json() == []
    missing = client.get("/v1/assistant/questions/not-approved")
    assert missing.status_code == 404
    assert missing.json()["code"] == "answer_unavailable"
    assert (
        client.post("/v1/assistant/questions", json={"message": "invent a route"}).status_code
        == 405
    )
    assert client.get("/v1/assistant/questions?language=xx").status_code == 422
    assert client.get("/v1/assistant/questions/invalid%20id").status_code == 422
