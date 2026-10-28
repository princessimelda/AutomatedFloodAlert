# FloodSafe backend

A local FastAPI service backed by Supabase PostgreSQL/PostGIS. This increment implements public place lookup, timestamped risk summaries and approved advisories. Private profile/location/device storage is designed but no personal-data API routes are exposed yet.

## Install

From the repository root (Python 3.13):

```sh
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
```

`requirements.in` records direct dependencies; `requirements.txt` pins the tested environment. Python tooling configuration lives in `pyproject.toml`.

## Connect Supabase privately

Copy `backend/config.example.env` to `backend/.env` if the local file does not already exist. Never overwrite a configured file. `.env` is Git-ignored; the template has no credentials.

In your Supabase project, choose **Connect → Session pooler → View parameters**. Enter these values in the local file:

| Supabase field | Local setting |
| --- | --- |
| Host | `FLOODSAFE_DB_HOST` |
| Port | `FLOODSAFE_DB_PORT` (usually 5432 for session pooling) |
| Database | `FLOODSAFE_DB_NAME` (postgres) |
| User | `FLOODSAFE_DB_USER` (usually postgres followed by the project reference) |
| Database password chosen at project creation | `FLOODSAFE_DB_PASSWORD` |

If Supabase shows `postgresql://USER:PASSWORD@HOST:5432/postgres`, use USER and HOST from that string. Enter the password directly in its separate setting, not URL-encoded. Quote dotenv values containing spaces or comment characters. Do not paste passwords into chat, command arguments, screenshots or tracked files.

Keep `FLOODSAFE_DB_SSLMODE=require`. This uses IPv4-compatible session pooling and a maximum of three pooled API connections. A Supabase publishable key or service-role key is not required for this read-only backend increment. Those do not replace the database password.

From `backend/`:

```sh
.venv/bin/python -m app.manage check
.venv/bin/python -m app.manage migrate
.venv/bin/python -m app.manage seed
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

`check` makes no schema changes. `migrate` applies versioned SQL transactionally and verifies checksums for applied versions. `seed` requires `FLOODSAFE_ALLOW_DEMO_DATA=true` and inserts development examples explicitly. Neither API startup nor refresh runs migrations, renews seeds, or invokes a model.

Open `http://127.0.0.1:8000/docs` for generated OpenAPI documentation. `/healthz` checks the process; `/readyz` checks database access under the application's restricted reader role. A database failure produces HTTP 503, never an automatic switch to fixtures.

Hosted development connection verified on 2026-10-28: encrypted connection, migration `202610280001_core`, explicit development seed, RLS on all nine application tables, anonymous-profile denial and restricted-reader access checks passed. The Dart client successfully parsed places, dashboard assessments and advisories through the Python API from Supabase. The existing local preview uses API port 8001; fresh-start commands above use 8000, so match the Flutter API URL to the port you start.

## Try the API without credentials

From `backend/`, run this explicit fixture mode:

```sh
FLOODSAFE_DATA_MODE=fixtures FLOODSAFE_ALLOW_DEMO_DATA=true .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

All fixture risk/advisory records identify themselves as test data. This mode has no database connection and is not a substitute for database integration testing.

## Connect Flutter

From `floodsafe/`:

```sh
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8765 --dart-define=FLOODSAFE_API_URL=http://127.0.0.1:8000
```

Home uses the API for the place list and risk assessment. Preparedness opens published advisories from the API alongside the built-in general guidance. Without the define, the app remains in explicitly labelled standalone demo mode. Configured API failures never silently become sample risk.

Only the API URL belongs in Flutter; database credentials stay in the Python backend. Remote API URLs require HTTPS. HTTP is accepted only for localhost/loopback or the Android emulator bridge `10.0.2.2`. Configure exact browser origins in `FLOODSAFE_CORS_ORIGINS`; the defaults allow port 8765 on localhost and 127.0.0.1.

The read-only cross-runtime check uses the same Dart client as the app:

```sh
dart run tool/check_api.dart http://127.0.0.1:8000
```

## HTTP contract

All timestamps include an explicit timezone; coordinates use WGS84 latitude/longitude. Data freshness is based on issue/expiry time, not download time. Responses use `Cache-Control: no-store` in this increment.

| Route | Request | Response |
| --- | --- | --- |
| `GET /healthz` | None | Process status and data mode |
| `GET /readyz` | None | Reader-role DB readiness, or 503 |
| `GET /v1/places` | None | Published `{id,name,is_demo}` records |
| `POST /v1/dashboard` | `{place_id}` for a named place; `{place_id: "gps:…",latitude,longitude}` for GPS | `{place_id,source,is_demo,assessment}` |
| `GET /v1/advisories` | Optional named `place_id`, language en/sw, limit 1–100 | Current, published general and place-specific advisories |

A dashboard `assessment` is null when absent; otherwise it contains `level` (low/moderate/high), `issued_at`, and `valid_until`. Expired assessments may be returned for a visible stale state; future assessments are excluded. GPS matches published non-demo polygons only, including boundary points via `ST_Covers`. Overlapping active zones prioritise higher severity. This is an integration rule, not validation that a polygon accurately represents flooding.

Advisories include ID, title, body, language, source, HTTPS source URL, publication/expiry timestamps and `is_demo`. Draft, expired and future advisories are excluded. Only reviewed English development content is seeded; Kiswahili content still needs review.

Errors have `{code,message}`: 422 invalid input, 404 unknown/unpublished place, 503 unavailable data, 500 unexpected failure. Validation responses do not echo coordinate bodies or credentials. GPS uses a POST body, not a URL; the backend neither stores those fixes nor logs bodies. Run without access logging and apply equivalent redaction if adding a reverse proxy.

No `/me`, write/publishing, phone-verification, model-inference, route, SMS or notification endpoint is implemented here. Protected user routes require verified Supabase JWTs, ownership enforcement, rate limiting and tests in a subsequent increment; do not accept a client-supplied user ID as authentication.

## Database tests

From the repository root:

```sh
docker compose -p floodsafe-db-tests -f backend/compose.test.yml up -d
```

Then from `backend/`:

```sh
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 FLOODSAFE_RUN_DB_TESTS=1 .venv/bin/python -m pytest -q
.venv/bin/ruff check app tests
.venv/bin/ruff format --check app tests
```

Database tests use only the fixed loopback port 55432 and database `floodsafe_test`, protected by a test-only identity marker. They ignore `backend/.env` and never target Supabase. They verify constraints, migration/seed repeatability, reader grants, per-user RLS, geometry boundaries, demo exclusion, repository reads and rollback/reapply. The container's sample password is for this isolated test database only.

This increment passed 21 Python/API/database tests, 35 Flutter tests, Python lint/format checks, Flutter static analysis and the connected web build. The Dart connection check read four places and one test advisory through the running Python API from both isolated PostGIS and the hosted Supabase development database. Destructive database tests run only against the isolated database, not Supabase. On a cloud-synced workspace, Python dependency/bytecode files can stall; a virtual environment in a nonsynced local directory avoids that issue. The final Python verification used the same pinned dependencies in such a temporary environment.

Without `FLOODSAFE_RUN_DB_TESTS=1`, the API tests run and database tests are explicitly skipped. GitHub Actions is configured to run both Python/database and Flutter checks; its first remote run remains pending until this branch is pushed.

To remove only the disposable test stack when finished:

```sh
docker compose -p floodsafe-db-tests -f backend/compose.test.yml down --volumes
```

The test-bootstrap `auth` schema is a minimal stand-in for RLS tests, not an authentication service or a replacement for verifying real Supabase sessions.
