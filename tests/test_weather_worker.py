"""Cloud model checks and guarded local PostgreSQL persistence tests."""

import copy
import hashlib
import os
import tempfile
import unittest
import uuid
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

import httpx
import pandas as pd
import psycopg
from psycopg.rows import dict_row

from scripts.openmeteo_pipeline.fresh import LIVE_ENDPOINT
from scripts.openmeteo_pipeline.source import VARIABLES, ApiClient
from scripts.weather_worker.bundle import load_bundle, predict
from scripts.weather_worker.store import PostgresStore
from scripts.weather_worker.worker import run_worker


class MemoryStore:
    def __init__(self):
        self.saved = None
        self.failed = None
        self.unlocked = False
        self.complete = False

    def lock(self):
        return True

    def unlock(self):
        self.unlocked = True

    def begin(self, bundle, clock):
        return (
            None if self.complete else {"id": "test-run", "target_date": clock.date()}
        )

    def finish(self, run, snapshot, cleaned, predictions, responses, clock):
        self.saved = {
            "weather": cleaned,
            "predictions": predictions,
            "responses": responses,
        }
        self.complete = True
        return snapshot["status"]

    def fail(self, run, code, clock):
        self.failed = code


class WorkerFixtures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bundle = load_bundle()
        self.clock = datetime.now(UTC)
        self.calls = 0

    def tearDown(self):
        self.temporary.cleanup()

    def api(self, *, failed=False, missing=False):
        def handler(request):
            self.calls += 1
            if failed:
                return httpx.Response(503, json={"error": True})
            params = dict(request.url.params)
            dates = pd.date_range(params["start_date"], params["end_date"])
            east = float(params["longitude"]) > 36.85
            constants = {
                "temperature_2m_mean": 20.0,
                "temperature_2m_min": 15.0,
                "temperature_2m_max": 25.0,
                "precipitation_sum": 4.0,
                "wind_speed_10m_mean": 10.0,
                "pressure_msl_mean": 1010.0,
            }
            values = {name: [value] * len(dates) for name, value in constants.items()}
            if missing:
                values["precipitation_sum"][-1] = None
            return httpx.Response(
                200,
                json={
                    "latitude": -1.2300644 if east else -1.3472137,
                    "longitude": 36.914062 if east else 36.796875,
                    "elevation": 1586.0 if east else 1731.0,
                    "timezone": "GMT",
                    "utc_offset_seconds": 0,
                    "daily_units": {
                        "time": "iso8601",
                        **{key: unit for key, (_, unit) in VARIABLES.items()},
                    },
                    "daily": {"time": dates.strftime("%Y-%m-%d").tolist(), **values},
                },
            )

        client = httpx.Client(transport=httpx.MockTransport(handler))
        self.addCleanup(client.close)
        return ApiClient(
            self.root / "raw",
            endpoint=LIVE_ENDPOINT,
            refresh=True,
            client=client,
            sleep=lambda _: None,
        )


class WorkerTests(WorkerFixtures):
    def test_complete_worker_keeps_raw_evidence_and_model_provenance(self):
        store = MemoryStore()
        result = run_worker(self.bundle, store, now=self.clock, api=self.api())
        self.assertEqual(result["status"], "ready")
        self.assertEqual(len(store.saved["weather"]), 14)
        self.assertEqual(len(store.saved["predictions"]), 2)
        self.assertEqual(len(store.saved["responses"]), 3)
        for source in store.saved["responses"]:
            self.assertEqual(
                hashlib.sha256(source["body"]).hexdigest(),
                source["receipt"]["body_sha256"],
            )
        self.assertTrue(store.unlocked)
        self.assertEqual(
            run_worker(self.bundle, store, now=self.clock, api=self.api())["status"],
            "already_complete",
        )
        self.assertEqual(self.calls, 3)

    def test_incomplete_weather_never_gets_a_prediction(self):
        store = MemoryStore()
        result = run_worker(
            self.bundle, store, now=self.clock, api=self.api(missing=True)
        )
        self.assertEqual(result["status"], "incomplete")
        self.assertEqual(store.saved["predictions"], [])

    def test_provider_outage_records_failure_and_releases_lock(self):
        store = MemoryStore()
        with self.assertRaises(httpx.HTTPStatusError):
            run_worker(self.bundle, store, now=self.clock, api=self.api(failed=True))
        self.assertEqual(store.failed, "HTTPStatusError")
        self.assertTrue(store.unlocked)
        self.assertIsNone(store.saved)

    def test_corrupt_bundle_rejected_before_loading_pickle(self):
        import shutil

        folder = self.root / "bundle"
        shutil.copytree(self.bundle["path"], folder)
        (folder / "model.joblib").write_bytes(b"invalid")
        with self.assertRaisesRegex(ValueError, "checksum"):
            load_bundle(folder)

    def test_unknown_grids_or_infinite_features_are_rejected(self):
        grids = pd.read_csv(self.bundle["path"] / "reference/stations.csv")
        frame = pd.DataFrame(
            [
                {**{key: 0.0 for key in self.bundle["manifest"]["predictors"]}, **row}
                for row in grids.to_dict("records")
            ]
        )
        self.assertEqual(len(predict(self.bundle, frame)), 2)
        invalid = frame.copy()
        invalid.loc[0, "station_id"] = "untrained-grid"
        with self.assertRaises(ValueError):
            predict(self.bundle, invalid)
        frame.loc[0, "prcp_lag1"] = float("inf")
        with self.assertRaises(ValueError):
            predict(self.bundle, frame)


@unittest.skipUnless(
    os.getenv("FLOODSAFE_RUN_DB_TESTS") == "1",
    "Explicit isolated database opt-in required",
)
class WorkerDatabaseTests(WorkerFixtures):
    def setUp(self):
        super().setUp()
        self.db = psycopg.connect(
            host="127.0.0.1",
            port=55432,
            dbname="floodsafe_test",
            user="postgres",
            password="floodsafe-test-only",
            row_factory=dict_row,
        )
        self.addCleanup(self.db.close)
        with self.db.transaction():
            self.assertEqual(
                self.db.execute(
                    "SELECT marker FROM floodsafe_test_marker.identity"
                ).fetchone()["marker"],
                "isolated-floodsafe-tests",
            )
        self.bundle = copy.deepcopy(self.bundle)
        self.bundle["manifest"]["model_version"] += "-test-" + uuid.uuid4().hex[:8]

    def test_atomic_persistence_idempotence_and_restricted_reader(self):
        store = PostgresStore(self.db)
        result = run_worker(self.bundle, store, now=self.clock, api=self.api())
        self.assertEqual(result["status"], "ready")
        self.assertEqual(
            run_worker(self.bundle, store, now=self.clock, api=self.api())["status"],
            "already_complete",
        )
        with self.db.transaction():
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.weather_inputs WHERE run_id=%s",
                    (result["run_id"],),
                ).fetchone()["n"],
                14,
            )
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.source_responses WHERE run_id=%s",
                    (result["run_id"],),
                ).fetchone()["n"],
                3,
            )
            self.db.execute("SET LOCAL ROLE floodsafe_reader")
            rows = self.db.execute(
                "SELECT * FROM floodsafe_pipeline.current_predictions WHERE model_version=%s",
                (self.bundle["manifest"]["model_version"],),
            ).fetchall()
            self.assertEqual(len(rows), 2)
            self.assertTrue(all(row["experimental"] for row in rows))
            with (
                self.assertRaises(psycopg.errors.InsufficientPrivilege),
                self.db.transaction(),
            ):
                self.db.execute("SELECT * FROM floodsafe_pipeline.source_responses")
        with self.db.transaction():
            self.db.execute("SET LOCAL ROLE authenticated")
            with (
                self.assertRaises(psycopg.errors.InsufficientPrivilege),
                self.db.transaction(),
            ):
                self.db.execute("SELECT * FROM floodsafe_pipeline.current_predictions")

    def test_failed_retry_does_not_expose_an_old_success(self):
        store = PostgresStore(self.db)
        result = run_worker(self.bundle, store, now=self.clock, api=self.api())
        with self.db.transaction():
            self.db.execute(
                "UPDATE floodsafe_pipeline.worker_runs SET status='failed' WHERE id=%s",
                (result["run_id"],),
            )
        with self.assertRaises(httpx.HTTPStatusError):
            run_worker(self.bundle, store, now=self.clock, api=self.api(failed=True))
        with self.db.transaction():
            self.db.execute("SET LOCAL ROLE floodsafe_reader")
            row = self.db.execute(
                "SELECT status FROM floodsafe_pipeline.latest_status WHERE model_version=%s",
                (self.bundle["manifest"]["model_version"],),
            ).fetchone()
            self.assertEqual(row["status"], "failed")
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.current_predictions WHERE model_version=%s",
                    (self.bundle["manifest"]["model_version"],),
                ).fetchone()["n"],
                0,
            )

    def test_bad_prediction_rolls_back_weather_and_raw_writes(self):
        def invalid_score(bundle, frame):
            rows = predict(bundle, frame)
            rows[0]["score"] = 2.0
            return rows

        with (
            patch("scripts.weather_worker.worker.predict", side_effect=invalid_score),
            self.assertRaises(psycopg.errors.CheckViolation),
        ):
            run_worker(
                self.bundle, PostgresStore(self.db), now=self.clock, api=self.api()
            )
        with self.db.transaction():
            run = self.db.execute(
                "SELECT id,status FROM floodsafe_pipeline.worker_runs WHERE model_version=%s",
                (self.bundle["manifest"]["model_version"],),
            ).fetchone()
            self.assertEqual(run["status"], "failed")
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.weather_inputs WHERE run_id=%s",
                    (run["id"],),
                ).fetchone()["n"],
                0,
            )
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.source_responses WHERE run_id=%s",
                    (run["id"],),
                ).fetchone()["n"],
                0,
            )

    def test_expired_prediction_rows_are_withheld(self):
        result = run_worker(
            self.bundle, PostgresStore(self.db), now=self.clock, api=self.api()
        )
        with self.db.transaction():
            self.db.execute(
                "UPDATE floodsafe_pipeline.rainfall_predictions SET generated_at=now()-interval '3 hours',valid_until=now()-interval '1 second' WHERE run_id=%s",
                (result["run_id"],),
            )
            self.db.execute("SET LOCAL ROLE floodsafe_reader")
            self.assertEqual(
                self.db.execute(
                    "SELECT count(*) n FROM floodsafe_pipeline.current_predictions WHERE run_id=%s",
                    (result["run_id"],),
                ).fetchone()["n"],
                0,
            )

    def test_worker_cannot_access_app_user_profiles(self):
        with self.db.transaction():
            self.db.execute("SET LOCAL ROLE floodsafe_worker")
            with (
                self.assertRaises(psycopg.errors.InsufficientPrivilege),
                self.db.transaction(),
            ):
                self.db.execute("SELECT * FROM public.profiles")


if __name__ == "__main__":
    unittest.main()
