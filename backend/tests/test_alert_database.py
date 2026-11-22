from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest
from pydantic import SecretStr
from test_database import database_settings as database_settings

from app.alert_auth import Actor
from app.alert_models import ActionInput, EventInput, RuleInput
from app.alert_store import AlertConflict, AlertMissing, AlertStore
from app.notification_worker import dispatch_once
from app.repositories import PostgresRepository
from app.sms import SendResult

pytestmark = pytest.mark.database


@pytest.fixture
def prototype(database_settings):
    settings = database_settings.model_copy(
        update={"sms_enabled": True, "sms_test_recipients": {"tester": SecretStr("+15005550009")}}
    )
    repo = PostgresRepository(settings)
    store = AlertStore(repo, settings)
    prefix = "test-" + uuid4().hex
    source = Actor(prefix, "integration")
    reviewer = Actor(prefix + "-reviewer", "approver")
    rule = store.create_rule(
        RuleInput(
            name=prefix, version=1, event_kind="manual_report", threshold=1, severity="warning"
        ),
        reviewer,
    )
    now = datetime.now(UTC)
    event = EventInput(
        source_event_id=prefix,
        rule_id=rule["id"],
        event_kind="manual_report",
        metric=1,
        occurred_at=now,
        valid_until=now + timedelta(hours=1),
        evidence="Synthetic test, not a flood observation",
        title="Practice alert",
        message="Test only",
        recommended_action="Read this practice message.",
        place_ids=["kibera", "westlands"],
    )
    try:
        yield store, source, reviewer, event
    finally:
        repo.close()
        # Only this fixture's records in the guarded disposable database.
        with psycopg.connect(**settings.connection_kwargs()) as db:
            assert (
                db.execute("SELECT marker FROM floodsafe_test_marker.identity").fetchone()[0]
                == "isolated-floodsafe-tests"
            )
            db.execute(
                "DELETE FROM floodsafe_alerting.notification_attempts WHERE job_id IN (SELECT j.id FROM floodsafe_alerting.notification_jobs j JOIN floodsafe_alerting.alerts a ON a.id=j.alert_id JOIN floodsafe_alerting.alert_events e ON e.id=a.event_id WHERE e.source=%s)",
                (prefix,),
            )
            for table in [
                "notification_jobs",
                "alert_acknowledgements",
                "alert_audit_logs",
                "alert_locations",
            ]:
                db.execute(
                    f"DELETE FROM floodsafe_alerting.{table} WHERE alert_id IN (SELECT a.id FROM floodsafe_alerting.alerts a JOIN floodsafe_alerting.alert_events e ON e.id=a.event_id WHERE e.source=%s)",
                    (prefix,),
                )
            db.execute(
                "DELETE FROM floodsafe_alerting.alerts WHERE event_id IN (SELECT id FROM floodsafe_alerting.alert_events WHERE source=%s)",
                (prefix,),
            )
            db.execute("DELETE FROM floodsafe_alerting.alert_events WHERE source=%s", (prefix,))
            db.execute("DELETE FROM floodsafe_alerting.alert_rules WHERE id=%s", (rule["id"],))


def publish(prototype):
    store, source, reviewer, event = prototype
    created = store.ingest(event, source)
    alert_id = created["alert_id"]
    store.transition(
        alert_id,
        "approve",
        ActionInput(expected_revision=1, reason="Reviewed synthetic evidence"),
        reviewer,
    )
    store.transition(
        alert_id,
        "publish",
        ActionInput(expected_revision=2, reason="Publish controlled test"),
        Actor(source.id + "-operator", "operator"),
    )
    return alert_id


class Provider:
    def __init__(self, status="accepted"):
        self.status = status
        self.delivered = False
        self.calls = 0
        self.id = "SM" + uuid4().hex

    def send(self, job):
        self.calls += 1
        return SendResult(self.status, provider_id=self.id if self.status == "accepted" else None)

    def delivery(self, message_id):
        return "delivered" if self.delivered else None


def test_event_approval_publication_two_channels_and_resolution(prototype):
    store, source, reviewer, event = prototype
    created = store.ingest(event, source)
    alert_id = created["alert_id"]
    assert store.ingest(event, source)["status"] == "duplicate"
    assert not any(a.id == alert_id for a in store.public_alerts())
    with pytest.raises(AlertConflict):
        store.ingest(event.model_copy(update={"message": "Changed content"}), source)
    with pytest.raises(AlertConflict):
        store.transition(
            alert_id,
            "publish",
            ActionInput(expected_revision=1, reason="Bypass approval"),
            reviewer,
        )
    with pytest.raises(AlertConflict):
        store.transition(
            alert_id, "approve", ActionInput(expected_revision=1, reason="Self approve"), source
        )
    store.transition(
        alert_id, "approve", ActionInput(expected_revision=1, reason="Reviewed"), reviewer
    )
    action = ActionInput(expected_revision=2, reason="Publish test")
    store.transition(alert_id, "publish", action, reviewer)
    store.transition(alert_id, "publish", action, reviewer)
    assert any(a.id == alert_id for a in store.public_alerts("kibera"))
    assert not any(a.id == alert_id for a in store.public_alerts("embakasi"))
    jobs = [j for j in store.notifications() if j["alert_id"] == alert_id]
    assert sorted(j["channel"] for j in jobs) == ["in_app", "sms"]
    assert all("destination" not in j for j in jobs)
    assert len(store.audit_log(alert_id)) == 3
    provider = Provider()
    assert dispatch_once(store, provider)["processed"] == 1
    assert (
        next(
            j for j in store.notifications() if j["alert_id"] == alert_id and j["channel"] == "sms"
        )["status"]
        == "accepted"
    )
    provider.delivered = True
    assert dispatch_once(store, provider)["delivery_updates"] == 1
    assert provider.calls == 1
    store.transition(
        alert_id, "resolve", ActionInput(expected_revision=3, reason="Exercise complete"), reviewer
    )
    assert not any(a.id == alert_id for a in store.public_alerts())
    assert store.audit_log(alert_id)[-1]["reason"] == "Exercise complete"


def test_no_match_and_revision_conflict_are_explicit(prototype):
    store, source, reviewer, event = prototype
    no_match = store.ingest(event.model_copy(update={"metric": 0}), source)
    assert no_match["status"] == "no_alert" and no_match["alert_id"] is None
    result = store.ingest(event.model_copy(update={"source_event_id": "other"}), source)
    with pytest.raises(AlertConflict):
        store.transition(
            result["alert_id"],
            "approve",
            ActionInput(expected_revision=8, reason="Stale view"),
            reviewer,
        )


def test_uncertain_submission_stays_unknown_without_duplicate_send(prototype):
    store, *_ = prototype
    alert_id = publish(prototype)
    provider = Provider("unknown")
    dispatch_once(store, provider)
    dispatch_once(store, provider)
    assert provider.calls == 1
    assert (
        next(
            j for j in store.notifications() if j["alert_id"] == alert_id and j["channel"] == "sms"
        )["status"]
        == "unknown"
    )


def test_cancelled_alert_cancels_unsent_sms(prototype):
    store, _, reviewer, _ = prototype
    alert_id = publish(prototype)
    store.transition(
        alert_id, "cancel", ActionInput(expected_revision=3, reason="Test cancelled"), reviewer
    )
    provider = Provider()
    assert dispatch_once(store, provider)["processed"] == 0
    assert provider.calls == 0


def test_acknowledgement_is_idempotent_and_does_not_resolve_everyones_alert(
    prototype, database_settings
):
    store, *_ = prototype
    alert_id = publish(prototype)
    owner = uuid4()
    with psycopg.connect(**database_settings.connection_kwargs()) as db:
        db.execute("INSERT INTO auth.users(id) VALUES (%s)", (owner,))
    try:
        first = store.acknowledge(alert_id, str(owner))
        assert store.acknowledge(alert_id, str(owner)) == first
        assert store.detail(alert_id)["status"] == "published"
        with pytest.raises(AlertMissing):
            store.acknowledge(uuid4(), str(owner))
    finally:
        with psycopg.connect(**database_settings.connection_kwargs()) as db:
            db.execute("DELETE FROM auth.users WHERE id=%s", (owner,))


def test_private_tables_and_audit_are_not_client_writable(prototype, database_settings):
    with psycopg.connect(**database_settings.connection_kwargs()) as db:
        assert (
            db.execute(
                "SELECT count(*) FROM pg_tables WHERE schemaname='floodsafe_alerting' AND rowsecurity"
            ).fetchone()[0]
            == 8
        )
        db.execute("SET LOCAL ROLE floodsafe_reader")
        with pytest.raises(psycopg.errors.InsufficientPrivilege), db.transaction():
            db.execute("SELECT destination FROM floodsafe_alerting.notification_jobs")
        db.execute("SET LOCAL ROLE floodsafe_alert_service")
        with pytest.raises(psycopg.errors.InsufficientPrivilege), db.transaction():
            db.execute("DELETE FROM floodsafe_alerting.alert_audit_logs")


def test_retryable_rejections_stop_after_three_attempts(prototype, database_settings):
    store, *_ = prototype
    alert_id = publish(prototype)
    provider = Provider("retry")
    for _ in range(3):
        with psycopg.connect(**database_settings.connection_kwargs()) as db:
            db.execute(
                "UPDATE floodsafe_alerting.notification_jobs SET next_attempt_at=now() WHERE alert_id=%s",
                (alert_id,),
            )
        dispatch_once(store, provider)
    assert dispatch_once(store, provider)["processed"] == 0
    assert provider.calls == 3
    job = next(
        j for j in store.notifications() if j["alert_id"] == alert_id and j["channel"] == "sms"
    )
    assert job["status"] == "failed" and job["attempt_count"] == 3


def test_expired_alert_is_hidden_and_unsent_sms_is_cancelled(prototype, database_settings):
    store, *_ = prototype
    alert_id = publish(prototype)
    with psycopg.connect(**database_settings.connection_kwargs()) as db:
        db.execute(
            "UPDATE floodsafe_alerting.alerts SET issued_at=now()-interval '2 minutes',valid_until=now()-interval '1 second' WHERE id=%s",
            (alert_id,),
        )
    assert not any(a.id == alert_id for a in store.public_alerts())
    provider = Provider()
    assert dispatch_once(store, provider)["processed"] == 0
    assert provider.calls == 0


def test_concurrent_workers_cannot_claim_the_same_sms(prototype):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event

    store, *_ = prototype
    publish(prototype)
    entered, release = Event(), Event()

    class SlowProvider(Provider):
        def send(self, job):
            entered.set()
            assert release.wait(timeout=5)
            return super().send(job)

    provider = SlowProvider()
    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(dispatch_once, store, provider)
        try:
            assert entered.wait(timeout=5)
            second = executor.submit(dispatch_once, store, provider)
            assert second.result(timeout=5)["processed"] == 0
        finally:
            release.set()
        assert first.result(timeout=5)["processed"] == 1
    assert provider.calls == 1
