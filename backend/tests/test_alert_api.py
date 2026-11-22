from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def settings(**overrides):
    return Settings(
        _env_file=None,
        data_mode="fixtures",
        allow_demo_data=True,
        alert_principals={
            role: {"key": role[0] * 40, "actor_id": "test-" + role, "role": role}
            for role in ["integration", "operator", "approver"]
        },
        **overrides,
    )


def event():
    now = datetime.now(UTC)
    return {
        "source_event_id": "test-event",
        "rule_id": str(uuid4()),
        "event_kind": "rainfall_proxy",
        "metric": 0.8,
        "occurred_at": now.isoformat(),
        "valid_until": (now + timedelta(hours=1)).isoformat(),
        "evidence": "Synthetic test only",
        "title": "Practice alert",
        "message": "This is a test.",
        "recommended_action": "Practise reading the alert.",
        "place_ids": ["kibera"],
    }


def test_public_inbox_does_not_invent_alerts_and_administration_is_protected():
    with TestClient(create_app(settings())) as client:
        assert client.get("/api/v1/alerts").json() == []
        assert client.get("/api/v1/alerts?place_id=invalid%20area").status_code == 422
        assert client.get("/api/v1/admin/alerts").status_code == 401
        assert (
            client.post(
                "/api/v1/events", json=event(), headers={"X-FloodSafe-Key": "wrong"}
            ).status_code
            == 401
        )
        assert (
            client.post(
                "/api/v1/alert-rules",
                json={
                    "name": "test",
                    "version": 1,
                    "event_kind": "rainfall_proxy",
                    "threshold": 0.5,
                    "severity": "information",
                },
                headers={"X-FloodSafe-Key": "i" * 40},
            ).status_code
            == 403
        )


def test_authorisation_uses_server_roles_not_request_role():
    app = create_app(settings())
    calls = []
    app.state.alert_store.ingest = lambda request, actor: (
        calls.append(actor) or {"status": "pending_approval"}
    )
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/events", json=event(), headers={"X-FloodSafe-Key": "i" * 40}
        )
        assert response.status_code == 202
        assert calls[0].id == "test-integration"
        forged = {**event(), "role": "approver"}
        assert (
            client.post(
                "/api/v1/events", json=forged, headers={"X-FloodSafe-Key": "i" * 40}
            ).status_code
            == 422
        )
        assert (
            client.post(
                f"/api/v1/alerts/{uuid4()}/approve",
                json={"expected_revision": 1, "reason": "reviewed"},
                headers={"X-FloodSafe-Key": "o" * 40},
            ).status_code
            == 403
        )


@pytest.mark.parametrize(
    "changes",
    [
        {"occurred_at": "2099-01-01T00:00:00Z"},
        {"valid_until": "2020-01-01T00:00:00Z"},
        {"place_ids": []},
        {"place_ids": ["kibera", "kibera"]},
        {"is_demo": False},
        {"metric": float("inf")},
    ],
)
def test_invalid_or_operational_claims_are_rejected(changes):
    from pydantic import ValidationError

    from app.alert_models import EventInput

    with pytest.raises(ValidationError):
        EventInput(**{**event(), **changes})


def test_rainfall_score_cannot_become_critical_flood_warning():
    with TestClient(create_app(settings())) as client:
        result = client.post(
            "/api/v1/alert-rules",
            json={
                "name": "invalid-proxy",
                "version": 1,
                "event_kind": "rainfall_proxy",
                "threshold": 0.5,
                "severity": "critical",
            },
            headers={"X-FloodSafe-Key": "a" * 40},
        )
        assert result.status_code == 422


def test_acknowledgement_uses_supabase_verified_identity(monkeypatch):
    owner = str(uuid4())
    app = create_app(
        settings(auth_url="https://project.supabase.co", auth_publishable_key="public-example")
    )
    received = []
    app.state.alert_store.acknowledge = lambda alert_id, user_id: (
        received.append(user_id) or {"acknowledged_at": datetime.now(UTC)}
    )

    def user_lookup(url, **kwargs):
        assert kwargs["headers"]["Authorization"] == "Bearer test-user-session"
        return httpx.Response(200, json={"id": owner}, request=httpx.Request("GET", url))

    monkeypatch.setattr("app.alert_auth.httpx.get", user_lookup)
    with TestClient(app) as client:
        path = f"/api/v1/alerts/{uuid4()}/acknowledge"
        assert client.post(path).status_code == 401
        assert (
            client.post(
                path,
                headers={"Authorization": "Bearer test-user-session"},
                json={"user_id": str(uuid4())},
            ).status_code
            == 200
        )
        assert received == [owner]


def test_empty_operator_configuration_disables_writes():
    with TestClient(
        create_app(Settings(_env_file=None, data_mode="fixtures", allow_demo_data=True))
    ) as client:
        assert (
            client.post(
                "/api/v1/events", json=event(), headers={"X-FloodSafe-Key": "x" * 40}
            ).status_code
            == 503
        )


def test_demo_provisioning_generates_private_distinct_keys_without_overwrite(tmp_path):
    from app.provision_alert_demo import provision

    path = tmp_path / ".env.notifications"
    provision(path)
    before = path.read_bytes()
    parsed = Settings(_env_file=path)
    assert path.stat().st_mode & 0o777 == 0o600
    assert len({p.key.get_secret_value() for p in parsed.alert_principals.values()}) == 3
    assert not parsed.sms_enabled and not parsed.notification_worker_enabled
    with pytest.raises(FileExistsError):
        provision(path)
    assert path.read_bytes() == before
