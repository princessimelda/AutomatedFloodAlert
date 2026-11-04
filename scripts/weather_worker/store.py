"""Transactional PostgreSQL persistence with a private, restricted worker role."""

import json
import os
import uuid
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pandas as pd
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


def db_config(path=None):
    raw = (
        Path(path).read_text()
        if path
        else os.environ.get("FLOODSAFE_WORKER_DB_CONFIG", "")
    )
    config = json.loads(raw)
    required = {"host", "port", "dbname", "user", "password", "sslmode"}
    if set(config) != required or not all(config.values()):
        raise ValueError("Worker database configuration is incomplete.")
    if config["sslmode"] != "require" and not (
        config["host"] == "127.0.0.1" and config["dbname"] == "floodsafe_test"
    ):
        raise ValueError("Hosted worker connections require TLS.")
    if config["host"] != "127.0.0.1" and int(config["port"]) != 5432:
        raise ValueError(
            "Use the session pooler on port 5432; transaction pooling cannot hold the worker lock."
        )
    return {
        **config,
        "connect_timeout": 10,
        "application_name": "floodsafe-weather-worker",
    }


class PostgresStore:
    def __init__(self, connection):
        self.connection = connection
        connection.row_factory = dict_row

    @contextmanager
    def transaction(self):
        with self.connection.transaction():
            self.connection.execute("SET LOCAL ROLE floodsafe_worker")
            self.connection.execute("SET LOCAL statement_timeout='20s'")
            yield self.connection

    def lock(self):
        with self.connection.transaction():
            return self.connection.execute(
                "SELECT pg_try_advisory_lock(hashtext('floodsafe-weather-worker')) AS locked"
            ).fetchone()["locked"]

    def unlock(self):
        with self.connection.transaction():
            self.connection.execute(
                "SELECT pg_advisory_unlock(hashtext('floodsafe-weather-worker'))"
            )

    def begin(self, bundle, clock):
        manifest = bundle["manifest"]
        version = manifest["model_version"]
        expiry = min(
            clock + timedelta(hours=2),
            datetime.combine(
                clock.date() + timedelta(days=1), datetime.min.time(), tzinfo=UTC
            ),
        )
        slot = clock.replace(minute=0, second=0, microsecond=0)
        with self.transaction() as db:
            db.execute(
                "INSERT INTO floodsafe_pipeline.model_versions(version,bundle_sha256,metadata) VALUES (%s,%s,%s) ON CONFLICT DO NOTHING",
                (version, bundle["sha256"], Jsonb(manifest)),
            )
            existing = db.execute(
                "SELECT bundle_sha256 FROM floodsafe_pipeline.model_versions WHERE version=%s",
                (version,),
            ).fetchone()
            if existing["bundle_sha256"] != bundle["sha256"]:
                raise ValueError(
                    "Registered model version has a different bundle hash."
                )
            previous = db.execute(
                "SELECT id,status FROM floodsafe_pipeline.worker_runs WHERE model_version=%s AND scheduled_hour=%s",
                (version, slot),
            ).fetchone()
            if previous and previous["status"] == "ready":
                return None
            run_id = str(previous["id"]) if previous else str(uuid.uuid4())
            db.execute(
                """INSERT INTO floodsafe_pipeline.worker_runs(id,model_version,scheduled_hour,target_date,status,started_at,valid_until)
                VALUES (%s,%s,%s,%s,'running',%s,%s)
                ON CONFLICT(id) DO UPDATE SET status='running',started_at=EXCLUDED.started_at,valid_until=EXCLUDED.valid_until,finished_at=NULL,error_code=NULL""",
                (run_id, version, slot, clock.date(), clock, expiry),
            )
            return {"id": run_id, "valid_until": expiry, "target_date": clock.date()}

    def finish(self, run, snapshot, cleaned, predictions, responses, clock):
        status = snapshot["status"]
        if clock.date() != run["target_date"] or clock >= run["valid_until"]:
            self.fail(run, "expired", clock, status="expired")
            return "expired"
        with self.transaction() as db:
            for row in cleaned.to_dict("records"):
                values = [
                    None if pd.isna(row[name]) else float(row[name])
                    for name in ["tavg", "tmin", "tmax", "prcp", "wspd", "pres"]
                ]
                db.execute(
                    """INSERT INTO floodsafe_pipeline.weather_inputs(run_id,grid_id,day,tavg,tmin,tmax,prcp,wspd,pres)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT(run_id,grid_id,day) DO UPDATE SET tavg=EXCLUDED.tavg,tmin=EXCLUDED.tmin,tmax=EXCLUDED.tmax,prcp=EXCLUDED.prcp,wspd=EXCLUDED.wspd,pres=EXCLUDED.pres""",
                    (run["id"], row["station_id"], str(row["time"])[:10], *values),
                )
            for index, response in enumerate(responses):
                db.execute(
                    """INSERT INTO floodsafe_pipeline.source_responses(run_id,request_index,receipt,body_sha256,body) VALUES (%s,%s,%s,%s,%s)
                   ON CONFLICT(run_id,request_index) DO UPDATE SET receipt=EXCLUDED.receipt,body_sha256=EXCLUDED.body_sha256,body=EXCLUDED.body""",
                    (
                        run["id"],
                        index,
                        Jsonb(response["receipt"]),
                        response["receipt"]["body_sha256"],
                        response["body"],
                    ),
                )
            for row in predictions:
                db.execute(
                    """INSERT INTO floodsafe_pipeline.rainfall_predictions(run_id,grid_id,target_date,score,predicted_high_rainfall,rain_threshold_mm,features,feature_sha256,generated_at,valid_until)
                  VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                  ON CONFLICT(run_id,grid_id) DO UPDATE SET score=EXCLUDED.score,predicted_high_rainfall=EXCLUDED.predicted_high_rainfall,rain_threshold_mm=EXCLUDED.rain_threshold_mm,features=EXCLUDED.features,feature_sha256=EXCLUDED.feature_sha256,generated_at=EXCLUDED.generated_at,valid_until=EXCLUDED.valid_until""",
                    (
                        run["id"],
                        row["grid_id"],
                        run["target_date"],
                        row["score"],
                        row["predicted_high_rainfall"],
                        row["rain_threshold_mm"],
                        Jsonb(row["features"]),
                        row["feature_sha256"],
                        clock,
                        run["valid_until"],
                    ),
                )
            db.execute(
                "UPDATE floodsafe_pipeline.worker_runs SET status=%s,finished_at=%s,metadata=%s WHERE id=%s",
                (status, clock, Jsonb(snapshot), run["id"]),
            )
        return status

    def fail(self, run, code, clock, status="failed"):
        with self.transaction() as db:
            db.execute(
                "UPDATE floodsafe_pipeline.worker_runs SET status=%s,error_code=%s,finished_at=%s WHERE id=%s",
                (status, code, clock, run["id"]),
            )
