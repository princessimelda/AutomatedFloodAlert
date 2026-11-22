"""Transactional prototype alerts, immutable events/audit, durable delivery outbox."""

import hashlib
import json
from contextlib import contextmanager
from datetime import UTC, datetime

from psycopg import Error
from psycopg_pool import PoolTimeout

from .alert_models import PublishedAlert
from .repositories import DatabaseUnavailable


class AlertConflict(Exception):
    pass


class AlertMissing(Exception):
    pass


class AlertStore:
    def __init__(self, repository, settings):
        self.repository = repository
        self.settings = settings

    @contextmanager
    def connection(self, *, reader=False):
        if self.settings.data_mode != "postgres":
            raise DatabaseUnavailable()
        try:
            with self.repository._get_pool().connection() as db:
                with db.transaction():
                    db.execute(
                        "SET LOCAL ROLE "
                        + ("floodsafe_reader" if reader else "floodsafe_alert_service")
                    )
                    db.execute("SET LOCAL statement_timeout='5s'")
                    if reader:
                        db.execute("SET TRANSACTION READ ONLY")
                    yield db
        except (Error, PoolTimeout) as error:
            raise DatabaseUnavailable() from error

    def public_alerts(self, place_id=None):
        if self.settings.data_mode == "fixtures":
            return []
        with self.connection(reader=True) as db:
            rows = db.execute(
                """SELECT * FROM floodsafe_alerting.published_alerts
                WHERE (%s OR NOT is_demo) AND (%s::text IS NULL OR locations @> jsonb_build_array(jsonb_build_object('id',%s::text)))
                ORDER BY issued_at DESC,id LIMIT 100""",
                (self.settings.allow_demo_data, place_id, place_id),
            ).fetchall()
        return [PublishedAlert(**row) for row in rows]

    def ping(self):
        if self.settings.data_mode == "postgres":
            with self.connection(reader=True) as db:
                db.execute("SELECT id FROM floodsafe_alerting.published_alerts LIMIT 1").fetchall()

    def create_rule(self, request, actor):
        with self.connection() as db:
            row = db.execute(
                """INSERT INTO floodsafe_alerting.alert_rules(name,version,event_kind,threshold,severity,approved_by)
                VALUES (%s,%s,%s,%s,%s,%s) ON CONFLICT(name,version) DO NOTHING RETURNING *""",
                (
                    request.name,
                    request.version,
                    request.event_kind,
                    request.threshold,
                    request.severity,
                    actor.id,
                ),
            ).fetchone()
            if row is None:
                raise AlertConflict()
            return row

    def rules(self):
        with self.connection() as db:
            return db.execute(
                "SELECT * FROM floodsafe_alerting.alert_rules ORDER BY approved_at DESC LIMIT 100"
            ).fetchall()

    @staticmethod
    def audit(db, row, actor, action, reason):
        db.execute(
            "INSERT INTO floodsafe_alerting.alert_audit_logs(alert_id,actor_id,action,revision,reason) VALUES (%s,%s,%s,%s,%s)",
            (row["id"], actor.id, action, row["revision"], reason),
        )

    def ingest(self, request, actor):
        encoded = json.dumps(request.model_dump(mode="json"), sort_keys=True, allow_nan=False)
        digest = hashlib.sha256(encoded.encode()).hexdigest()
        with self.connection() as db:
            db.execute(
                "SELECT pg_advisory_xact_lock(hashtextextended(%s,0))",
                (actor.id + ":" + request.source_event_id,),
            )
            old = db.execute(
                """SELECT e.id,e.payload_sha256,a.id AS alert_id FROM floodsafe_alerting.alert_events e
                LEFT JOIN floodsafe_alerting.alerts a ON a.event_id=e.id WHERE e.source=%s AND e.source_event_id=%s""",
                (actor.id, request.source_event_id),
            ).fetchone()
            if old:
                if old["payload_sha256"] != digest:
                    raise AlertConflict()
                return {"status": "duplicate", "event_id": old["id"], "alert_id": old["alert_id"]}
            rule = db.execute(
                "SELECT * FROM floodsafe_alerting.alert_rules WHERE id=%s", (request.rule_id,)
            ).fetchone()
            if rule is None or rule["event_kind"] != request.event_kind:
                raise AlertConflict()
            places = db.execute(
                "SELECT id FROM public.places WHERE id=ANY(%s) AND is_published",
                (request.place_ids,),
            ).fetchall()
            if len(places) != len(request.place_ids):
                raise AlertConflict()
            event = db.execute(
                """INSERT INTO floodsafe_alerting.alert_events(source,source_event_id,payload_sha256,event_kind,metric,occurred_at,valid_until,evidence)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (
                    actor.id,
                    request.source_event_id,
                    digest,
                    request.event_kind,
                    request.metric,
                    request.occurred_at,
                    request.valid_until,
                    request.evidence,
                ),
            ).fetchone()
            if request.metric < rule["threshold"]:
                return {"status": "no_alert", "event_id": event["id"], "alert_id": None}
            alert = db.execute(
                """INSERT INTO floodsafe_alerting.alerts(event_id,rule_id,title,message,recommended_action,severity,status,created_by,valid_until)
                VALUES (%s,%s,%s,%s,%s,%s,'pending_approval',%s,%s) RETURNING *""",
                (
                    event["id"],
                    rule["id"],
                    request.title,
                    request.message,
                    request.recommended_action,
                    rule["severity"],
                    actor.id,
                    request.valid_until,
                ),
            ).fetchone()
            for place in request.place_ids:
                db.execute(
                    "INSERT INTO floodsafe_alerting.alert_locations VALUES (%s,%s)",
                    (alert["id"], place),
                )
            self.audit(
                db,
                alert,
                actor,
                "created",
                "Rule matched; awaiting independent approval. TEST event.",
            )
            return {"status": "pending_approval", "event_id": event["id"], "alert_id": alert["id"]}

    def transition(self, alert_id, action, request, actor):
        target = {
            "approve": "approved",
            "publish": "published",
            "resolve": "resolved",
            "cancel": "cancelled",
        }[action]
        allowed = {
            "approve": {"pending_approval"},
            "publish": {"approved"},
            "resolve": {"published"},
            "cancel": {"pending_approval", "approved", "published"},
        }
        with self.connection() as db:
            row = db.execute(
                "SELECT * FROM floodsafe_alerting.alerts WHERE id=%s FOR UPDATE", (alert_id,)
            ).fetchone()
            if row is None:
                raise AlertMissing()
            if row["status"] == target and request.expected_revision == row["revision"] - 1:
                return row
            if row["revision"] != request.expected_revision or row["status"] not in allowed[action]:
                raise AlertConflict()
            if action in {"approve", "publish"} and row["valid_until"] <= datetime.now(UTC):
                raise AlertConflict()
            if action == "approve" and row["created_by"] == actor.id:
                raise AlertConflict()
            row = db.execute(
                """UPDATE floodsafe_alerting.alerts SET status=%s,revision=revision+1,updated_at=now(),
                approved_by=CASE WHEN %s='approve' THEN %s ELSE approved_by END,
                approved_at=CASE WHEN %s='approve' THEN now() ELSE approved_at END,
                issued_at=CASE WHEN %s='publish' THEN now() ELSE issued_at END WHERE id=%s RETURNING *""",
                (target, action, actor.id, action, action, alert_id),
            ).fetchone()
            self.audit(db, row, actor, action, request.reason)
            if action == "publish":
                db.execute(
                    """INSERT INTO floodsafe_alerting.notification_jobs(alert_id,revision,channel,recipient_key,status)
                VALUES (%s,%s,'in_app','public','available') ON CONFLICT DO NOTHING""",
                    (alert_id, row["revision"]),
                )
                if self.settings.sms_enabled:
                    for key, destination in self.settings.sms_test_recipients.items():
                        db.execute(
                            """INSERT INTO floodsafe_alerting.notification_jobs(alert_id,revision,channel,recipient_key,destination,status)
                        VALUES (%s,%s,'sms',%s,%s,'queued') ON CONFLICT DO NOTHING""",
                            (alert_id, row["revision"], key, destination.get_secret_value()),
                        )
            elif action in {"cancel", "resolve"}:
                db.execute(
                    """UPDATE floodsafe_alerting.notification_jobs SET status='cancelled',updated_at=now()
                WHERE alert_id=%s AND status IN ('queued','retry','available')""",
                    (alert_id,),
                )
            return row

    def history(self):
        with self.connection() as db:
            return db.execute("""SELECT id,title,severity,revision,created_by,approved_by,issued_at,valid_until,
                CASE WHEN valid_until<=now() AND status NOT IN ('resolved','cancelled') THEN 'expired' ELSE status END AS status
                FROM floodsafe_alerting.alerts ORDER BY created_at DESC LIMIT 100""").fetchall()

    def audit_log(self, alert_id):
        with self.connection() as db:
            return db.execute(
                "SELECT actor_id,action,revision,reason,recorded_at FROM floodsafe_alerting.alert_audit_logs WHERE alert_id=%s ORDER BY id",
                (alert_id,),
            ).fetchall()

    def notifications(self):
        with self.connection() as db:
            return db.execute("""SELECT id,alert_id,channel,recipient_key,status,attempt_count,provider_id,error_code,updated_at
                FROM floodsafe_alerting.notification_jobs ORDER BY created_at DESC LIMIT 100""").fetchall()

    def detail(self, alert_id):
        with self.connection() as db:
            row = db.execute(
                """SELECT a.*,e.source,e.source_event_id,e.event_kind,e.metric,e.evidence,
                ARRAY(SELECT place_id FROM floodsafe_alerting.alert_locations WHERE alert_id=a.id ORDER BY place_id) AS place_ids
                FROM floodsafe_alerting.alerts a JOIN floodsafe_alerting.alert_events e ON e.id=a.event_id
                WHERE a.id=%s""",
                (alert_id,),
            ).fetchone()
            if not row:
                raise AlertMissing()
            return row

    def events(self, actor):
        with self.connection() as db:
            return db.execute(
                """SELECT id,source,source_event_id,event_kind,metric,occurred_at,valid_until,received_at
                FROM floodsafe_alerting.alert_events WHERE (%s OR source=%s) ORDER BY received_at DESC LIMIT 100""",
                (actor.role != "integration", actor.id),
            ).fetchall()

    def report(self):
        with self.connection() as db:
            return {
                "alerts": db.execute(
                    "SELECT severity,status,count(*) AS count FROM floodsafe_alerting.alerts GROUP BY severity,status ORDER BY severity,status"
                ).fetchall(),
                "notifications": db.execute(
                    "SELECT channel,status,count(*) AS count FROM floodsafe_alerting.notification_jobs GROUP BY channel,status ORDER BY channel,status"
                ).fetchall(),
                "acknowledgements": db.execute(
                    "SELECT count(*) AS count FROM floodsafe_alerting.alert_acknowledgements"
                ).fetchone()["count"],
            }

    def acknowledge(self, alert_id, user_id):
        with self.connection() as db:
            row = db.execute(
                "SELECT id FROM floodsafe_alerting.alerts WHERE id=%s AND status='published' AND issued_at<=now() AND valid_until>now() FOR SHARE",
                (alert_id,),
            ).fetchone()
            if not row:
                raise AlertMissing()
            db.execute(
                "INSERT INTO floodsafe_alerting.alert_acknowledgements(alert_id,user_id) VALUES (%s,%s) ON CONFLICT DO NOTHING",
                (alert_id, user_id),
            )
            return db.execute(
                "SELECT acknowledged_at FROM floodsafe_alerting.alert_acknowledgements WHERE alert_id=%s AND user_id=%s",
                (alert_id, user_id),
            ).fetchone()
