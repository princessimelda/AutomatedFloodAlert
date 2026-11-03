"""Offline API-contract tests and an end-to-end synthetic research run."""

import copy
import hashlib
import json
import plistlib
import sqlite3
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import pandas as pd

from scripts.nairobi_pipeline.data import clean_data, file_hash, transform_data
from scripts.openmeteo_pipeline.fresh import (
    LIVE_ENDPOINT,
    generate_fresh_schedule,
    latest_inputs,
    preprocessing_fingerprint,
    refresh_inputs,
    verify_preprocessing,
)
from scripts.openmeteo_pipeline.runner import evaluate_test, run_pipeline
from scripts.openmeteo_pipeline.source import (
    MODEL,
    VARIABLES,
    ApiClient,
    Config,
    extract_data,
    request_parameters,
    validate_response,
    year_chunks,
)


def response_document(params):
    dates = pd.date_range(params["start_date"], params["end_date"])
    east = float(params["longitude"]) > 36.85
    values = {
        "temperature_2m_mean": [20.0] * len(dates),
        "temperature_2m_min": [15.0] * len(dates),
        "temperature_2m_max": [25.0] * len(dates),
        "precipitation_sum": [
            ((day.toordinal() * 17 + int(east)) % 101) / 5 for day in dates
        ],
        "wind_speed_10m_mean": [10.0] * len(dates),
        "pressure_msl_mean": [1010.0] * len(dates),
    }
    return {
        "latitude": -1.23 if east else -1.35,
        "longitude": 36.91 if east else 36.8,
        "elevation": 1600 if east else 1731,
        "utc_offset_seconds": 0,
        "timezone": "GMT",
        "daily_units": {
            "time": "iso8601",
            **{variable: unit for variable, (_, unit) in VARIABLES.items()},
        },
        "daily": {"time": dates.strftime("%Y-%m-%d").tolist(), **values},
    }


class OpenMeteoTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.params = request_parameters(-1.3, 36.8, "2021-04-01", "2021-04-03")

    def tearDown(self):
        self.temporary.cleanup()

    def client(self, handler):
        transport = httpx.MockTransport(handler)
        client = httpx.Client(transport=transport)
        self.addCleanup(client.close)
        return ApiClient(self.root / "raw", client=client, sleep=lambda _: None)

    def test_schema_dates_units_numeric_and_timezone_rejected(self):
        good = response_document(self.params)
        validate_response(good, self.params)
        broken = []
        bad = copy.deepcopy(good)
        bad["daily_units"]["precipitation_sum"] = "inch"
        broken.append(bad)
        bad = copy.deepcopy(good)
        bad["daily"]["time"][1] = bad["daily"]["time"][0]
        broken.append(bad)
        bad = copy.deepcopy(good)
        bad["daily"]["temperature_2m_mean"] = ["20"] * 3
        broken.append(bad)
        bad = copy.deepcopy(good)
        bad["utc_offset_seconds"] = 10800
        broken.append(bad)
        for document in broken:
            with self.subTest(document=document), self.assertRaises(ValueError):
                validate_response(document, self.params)

    def test_retry_then_cache_and_checksum_protection(self):
        calls = []

        def handler(request):
            calls.append(request)
            if len(calls) == 1:
                return httpx.Response(429, headers={"Retry-After": "1"})
            return httpx.Response(200, json=response_document(self.params))

        api = self.client(handler)
        first, receipt = api.fetch(self.params)
        second, repeated = api.fetch(self.params)
        self.assertEqual(first, second)
        self.assertEqual(receipt, repeated)
        self.assertEqual(len(calls), 2)
        (api.root / receipt["body_file"]).write_text("{}")
        with self.assertRaisesRegex(ValueError, "checksum"):
            api.fetch(self.params)

    def test_refresh_preserves_previous_raw_evidence(self):
        api = self.client(
            lambda _: httpx.Response(200, json=response_document(self.params))
        )
        _, first = api.fetch(self.params)
        api.refresh = True
        _, second = api.fetch(self.params)
        self.assertNotEqual(first["body_file"], second["body_file"])
        self.assertTrue((api.root / first["body_file"]).exists())

    def test_http_failure_not_cached(self):
        api = self.client(lambda _: httpx.Response(400, json={"error": True}))
        with self.assertRaises(httpx.HTTPStatusError):
            api.fetch(self.params)
        self.assertEqual(list(api.root.iterdir()), [])

    def test_shared_cells_deduplicated_and_null_not_dry(self):
        def handler(request):
            doc = response_document(dict(request.url.params))
            doc["daily"]["precipitation_sum"][1] = None
            return httpx.Response(200, json=doc)

        api = self.client(handler)
        bundle = extract_data(Config(cache_root=str(api.root)), api=api)
        self.assertEqual(len(bundle["stations"]), 2)
        self.assertEqual(bundle["manifest"]["query_count"], 3)
        self.assertGreater(bundle["manifest"]["duplicate_grid_day_rows_removed"], 0)
        self.assertFalse(bundle["raw"].duplicated(["station_id", "time"]).any())
        clean, _, _ = clean_data(bundle["raw"], bundle["stations"])
        self.assertTrue(clean.loc[clean.time.eq("2021-04-02"), "prcp"].isna().all())
        features = transform_data(clean)
        self.assertTrue(
            features.loc[features.time.eq("2021-04-03"), "prcp_lag1"].isna().all()
        )

    def test_conflicting_same_grid_measurements_rejected(self):
        def handler(request):
            params = dict(request.url.params)
            doc = response_document(params)
            if float(params["latitude"]) < -1.31:
                doc["daily"]["precipitation_sum"][0] += 1
            return httpx.Response(200, json=doc)

        with self.assertRaisesRegex(ValueError, "Conflicting"):
            extract_data(Config(), api=self.client(handler))

    def test_annual_chunks_and_source_identity(self):
        chunks = list(year_chunks("2021-04-01", "2025-12-31"))
        self.assertEqual(len(chunks), 5)
        self.assertEqual(str(chunks[0][1]), "2021-12-31")
        self.assertEqual(self.params["models"], MODEL)
        self.assertEqual(self.params["elevation"], "nan")
        self.assertEqual(len(VARIABLES), 6)
        with self.assertRaises(ValueError):
            Config(start_date="2015-01-01").validate()

    def test_end_to_end_frozen_test_and_idempotence(self):
        api = self.client(
            lambda request: httpx.Response(
                200, json=response_document(dict(request.url.params))
            )
        )
        config = Config(output_root=str(self.root / "runs"), cache_root=str(api.root))
        run = run_pipeline(config, quick=True, api=api)
        with sqlite3.connect(run / "research.sqlite") as connection:
            self.assertEqual(
                connection.execute("PRAGMA integrity_check").fetchone()[0], "ok"
            )
            partitions = pd.read_sql_query(
                "SELECT partition, MIN(time) first, MAX(time) last FROM modelling_data GROUP BY partition",
                connection,
            ).set_index("partition")
        self.assertLess(
            partitions.loc["train", "last"], partitions.loc["validation", "first"]
        )
        self.assertLess(
            partitions.loc["validation", "last"], partitions.loc["test", "first"]
        )
        before = {
            p.name: p.stat().st_mtime_ns for p in (run / "models").glob("*.joblib")
        }
        self.assertEqual(run_pipeline(config, quick=True, api=api), run)
        self.assertEqual(
            before,
            {p.name: p.stat().st_mtime_ns for p in (run / "models").glob("*.joblib")},
        )
        selected = json.loads((run / "selection.json").read_text())["selected_model"]
        result = evaluate_test(run)
        self.assertEqual(result["selected_model_unchanged"], selected)
        self.assertEqual(result, evaluate_test(run))
        self.assertFalse(result["deployable"])


class FreshInputTests(unittest.TestCase):
    def test_source_selection_migration_preserves_feature_contract(self):
        path = Path("scripts/nairobi_pipeline/data.py")
        migration = json.loads(
            Path("scripts/openmeteo_pipeline/feature_compatibility.json").read_text()
        )["legacy_modules"][0]
        source = path.read_text()
        self.assertEqual(
            preprocessing_fingerprint(source), migration["preprocessing_ast_sha256"]
        )
        verify_preprocessing(migration["module_sha256"], path)
        changed = self.root / "changed.py"
        changed.write_text(source.replace("s.shift(1).rolling", "s.shift(0).rolling"))
        with self.assertRaisesRegex(ValueError, "Feature engineering changed"):
            verify_preprocessing(migration["module_sha256"], changed)
        with self.assertRaisesRegex(ValueError, "Feature engineering changed"):
            verify_preprocessing("unknown-training-code", path)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.clock = datetime(2025, 12, 3, 9, tzinfo=UTC)
        self.reference = self.root / "training"
        self.reference.mkdir()
        rows = []
        for lat, lon, elev in [(-1.35, 36.8, 1731), (-1.23, 36.91, 1600)]:
            identity = json.dumps([MODEL, lat, lon], separators=(",", ":"))
            rows.append(
                {
                    "station_id": MODEL
                    + "_"
                    + hashlib.sha256(identity.encode()).hexdigest()[:16],
                    "latitude": lat,
                    "longitude": lon,
                    "elevation_m": elev,
                }
            )
        pd.DataFrame(rows).to_csv(self.reference / "stations.csv", index=False)
        manifest = {
            "model": MODEL,
            "requests": [
                {
                    "request": {
                        "parameters": request_parameters(
                            0, 0, "2021-04-01", "2021-12-31"
                        )
                    }
                }
            ],
        }
        (self.reference / "source_manifest.json").write_text(json.dumps(manifest))
        feature_path = "scripts/nairobi_pipeline/data.py"
        record = {
            "artefact_sha256": {
                name: file_hash(self.reference / name)
                for name in ["stations.csv", "source_manifest.json"]
            },
            "signature": {"code": {feature_path: file_hash(feature_path)}},
        }
        (self.reference / "run.json").write_text(json.dumps(record))
        self.calls = []

    def tearDown(self):
        self.temporary.cleanup()

    def api(self, mutate=None, *, status=200):
        def handler(request):
            self.calls.append(request)
            doc = response_document(dict(request.url.params))
            if mutate:
                mutate(doc)
            return httpx.Response(status, json=doc)

        client = httpx.Client(transport=httpx.MockTransport(handler))
        self.addCleanup(client.close)
        return ApiClient(
            self.root / "raw",
            client=client,
            endpoint=LIVE_ENDPOINT,
            refresh=True,
            sleep=lambda _: None,
        )

    def refresh(self, api=None):
        return refresh_inputs(
            output_root=self.root / "live",
            cache_root=str(self.root / "raw"),
            reference_run=self.reference,
            now=self.clock,
            api=api or self.api(),
        )

    def test_recent_inputs_only_completed_days_and_no_training(self):
        result = self.refresh()
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["history_start_utc"], "2025-11-26")
        self.assertEqual(result["history_end_utc"], "2025-12-02")
        self.assertFalse(result["model_training_performed"])
        self.assertFalse(result["model_inference_performed"])
        self.assertEqual(len(self.calls), 3)
        current = latest_inputs(self.root / "live", now=self.clock)
        self.assertEqual(len(current["inputs"]), 2)
        self.assertTrue(all(row["time"] == "2025-12-03" for row in current["inputs"]))
        run = self.root / "live" / result["run_id"]
        raw = pd.read_csv(run / "raw_weather.csv")
        self.assertEqual(len(raw), 14)
        self.assertFalse((run / "models").exists())
        for row in current["inputs"]:
            last = (
                raw.loc[raw.station_id.eq(row["station_id"])]
                .sort_values("time")
                .iloc[-1]
            )
            self.assertEqual(row["prcp_lag1"], last.prcp)

    def test_refresh_never_reuses_live_cache(self):
        api = self.api()
        first, second = self.refresh(api), self.refresh(api)
        self.assertNotEqual(first["run_id"], second["run_id"])
        self.assertEqual(len(self.calls), 6)

    def test_stale_or_future_snapshot_has_no_usable_inputs(self):
        self.refresh()
        self.assertEqual(
            latest_inputs(self.root / "live", now=self.clock + timedelta(days=1))[
                "status"
            ],
            "stale",
        )
        self.assertEqual(
            latest_inputs(self.root / "live", now=self.clock - timedelta(minutes=1))[
                "inputs"
            ],
            [],
        )

    def test_missing_measurements_not_ready_or_imputed(self):
        def mutate(doc):
            doc["daily"]["precipitation_sum"][-1] = None

        self.assertEqual(self.refresh(self.api(mutate))["status"], "incomplete")
        self.assertEqual(
            latest_inputs(self.root / "live", now=self.clock)["inputs"], []
        )

    def test_failed_attempt_hides_old_success(self):
        success = self.refresh()
        with self.assertRaises(httpx.HTTPStatusError):
            self.refresh(self.api(status=503))
        status = latest_inputs(self.root / "live", now=self.clock)
        self.assertEqual(status["status"], "unavailable")
        self.assertEqual(status["inputs"], [])
        pointer = json.loads((self.root / "live/latest.json").read_text())
        self.assertEqual(pointer["run_id"], success["run_id"])

    def test_changed_grid_fails_compatibility_check(self):
        def mutate(doc):
            doc["elevation"] += 1

        with self.assertRaisesRegex(ValueError, "cells/elevations"):
            self.refresh(self.api(mutate))

    def test_corrupt_fresh_artefacts_rejected(self):
        result = self.refresh()
        (self.root / "live" / result["run_id"] / "current_inputs.csv").write_text(
            "changed"
        )
        with self.assertRaisesRegex(ValueError, "artefact changed"):
            latest_inputs(self.root / "live", now=self.clock)

    def test_hourly_schedule_uses_fresh_command(self):
        path = generate_fresh_schedule(
            self.root / "fresh.plist",
            python_executable="/tmp/persistent-env/bin/python",
            reference_run=self.reference,
        )
        config = plistlib.loads(path.read_bytes())
        self.assertEqual(config["StartInterval"], 3600)
        self.assertTrue(config["RunAtLoad"])
        self.assertIn("refresh-inputs", config["ProgramArguments"])
        self.assertEqual(config["ProgramArguments"][-1], str(self.reference.absolute()))
        with self.assertRaises(ValueError):
            generate_fresh_schedule(self.root / "too-often.plist", interval=60)


if __name__ == "__main__":
    unittest.main()
