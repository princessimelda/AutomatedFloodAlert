"""Durable outbox processing. Run beside the API, not from an unreliable cron."""

from .sms import TwilioSms


def dispatch_once(store, provider=None):
    if not store.settings.sms_enabled:
        return {"processed": 0, "delivery_updates": 0}
    sms = provider or TwilioSms(store.settings)
    try:
        with store.connection() as db:
            db.execute("""UPDATE floodsafe_alerting.notification_jobs SET status='unknown',error_code='worker_interrupted',updated_at=now()
                WHERE status='processing' AND updated_at<now()-interval '5 minutes'""")
            db.execute("""UPDATE floodsafe_alerting.notification_jobs j SET status='cancelled',updated_at=now()
                FROM floodsafe_alerting.alerts a WHERE j.alert_id=a.id AND j.status IN ('queued','retry')
                AND (a.status<>'published' OR a.valid_until<=now())""")
            job = db.execute("""SELECT j.*,a.title,a.severity,a.recommended_action,a.issued_at,a.valid_until,
                (SELECT string_agg(p.name,', ' ORDER BY p.name) FROM floodsafe_alerting.alert_locations l
                JOIN public.places p ON p.id=l.place_id WHERE l.alert_id=a.id) AS locations
                FROM floodsafe_alerting.notification_jobs j JOIN floodsafe_alerting.alerts a ON a.id=j.alert_id
                WHERE j.channel='sms' AND j.status IN ('queued','retry') AND j.next_attempt_at<=now()
                AND j.attempt_count<3 AND a.status='published' AND a.valid_until>now()
                ORDER BY j.created_at,j.id LIMIT 1 FOR UPDATE OF j SKIP LOCKED""").fetchone()
            if job:
                job["attempt_count"] += 1
                db.execute(
                    "UPDATE floodsafe_alerting.notification_jobs SET status='processing',attempt_count=%s,updated_at=now() WHERE id=%s",
                    (job["attempt_count"], job["id"]),
                )
                db.execute(
                    "INSERT INTO floodsafe_alerting.notification_attempts(job_id,attempt,outcome) VALUES (%s,%s,'processing')",
                    (job["id"], job["attempt_count"]),
                )
        if job:
            result = sms.send(job)
            status = (
                "failed"
                if result.status == "retry" and job["attempt_count"] >= 3
                else result.status
            )
            with store.connection() as db:
                db.execute(
                    """UPDATE floodsafe_alerting.notification_jobs SET status=%s,provider_id=%s,error_code=%s,
                    next_attempt_at=now()+(%s*interval '1 second'),updated_at=now() WHERE id=%s""",
                    (
                        status,
                        result.provider_id,
                        result.error_code,
                        30 * 2 ** job["attempt_count"],
                        job["id"],
                    ),
                )
                db.execute(
                    """UPDATE floodsafe_alerting.notification_attempts SET outcome=%s,provider_id=%s,error_code=%s,finished_at=now()
                    WHERE job_id=%s AND attempt=%s""",
                    (
                        status,
                        result.provider_id,
                        result.error_code,
                        job["id"],
                        job["attempt_count"],
                    ),
                )
        updates = 0
        with store.connection() as db:
            pending = db.execute(
                "SELECT id,provider_id FROM floodsafe_alerting.notification_jobs WHERE channel='sms' AND status='accepted' ORDER BY updated_at LIMIT 20"
            ).fetchall()
        for pending_job in pending:
            status = sms.delivery(pending_job["provider_id"])
            if status:
                with store.connection() as db:
                    db.execute(
                        "UPDATE floodsafe_alerting.notification_jobs SET status=%s,updated_at=now() WHERE id=%s AND status='accepted'",
                        (status, pending_job["id"]),
                    )
                updates += 1
        return {"processed": int(job is not None), "delivery_updates": updates}
    finally:
        if provider is None:
            sms.close()
