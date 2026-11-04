# Cloud weather and experimental rainfall worker

The worker fetches recent GFS inputs, prepares compatible features, applies the frozen validation-selected Logistic Regression model, and persists the run in PostgreSQL/Supabase. Each invocation can start from a clean checkout or Linux container. It does not need the development Mac, research CSVs, local SQLite files or the original training directory.

**Results represent experimental high-rainfall scores, not validated flood probabilities.** They are stored separately from the application's existing public risk summaries. No Flutter screens or public risk assessments are changed by this worker.

## Runtime flow

1. Verify the committed model bundle, member hashes and pinned model-library versions.
2. Connect using a restricted database login and acquire a single-worker advisory lock.
3. Register the immutable model version and claim the UTC hourly slot. A completed slot is reused rather than scored twice.
4. Fetch seven completed UTC days from Open-Meteo's Forecast API with explicit `gfs_global`, units, native elevations and grid selection.
5. Verify exact grid/feature compatibility and completeness. Today's partial weather does not enter the predictors.
6. Score both grid cells using the frozen model and threshold. No runtime fitting or parameter selection occurs.
7. Atomically persist cleaned weather, exact raw response bytes/checksums, model provenance, feature rows, scores and completion status. Temporary working files are then discarded.

Failed attempts have an explicit status/error code. Incomplete input produces no predictions. Partial database writes roll back together. The backend's current-prediction view follows the latest run, so a failed/running/incomplete attempt does not silently fall back to an older successful run. Scores expire after at most two hours and at the end of their UTC target day; abandoned running attempts become failed in the status view after 15 minutes. A database outage can prevent failure recording, but previously stored scores still expire.

## Packaged model

`models/openmeteo_rainfall_v1/` contains the selected 6.7 KB model, predictor order, rainfall thresholds, provider contract, grid metadata, a minimal compatible reference and checksums. The package preserves its original source-run hash and experimental purpose. The current version is `nairobi-gfs-rainfall-lr-a5bacdf0368b`.

The model was selected on validation data before the original test evaluation. Its 2025 test precision was 0.2558 and recall 0.8462 against the provider-derived rainfall proxy. Deployment does not improve or revalidate these metrics. See the [research method and limitations](../openmeteo_pipeline/README.md).

Only the selected model and necessary metadata are packaged. Original research snapshots and weather datasets remain excluded from Git. The repository bundle is trusted release material; member/checksum and library-version checks run before loading the joblib file. A new model release requires a new reviewed package and model-version registration.

To reproduce an export from a local, already frozen research run:

```bash
python -m scripts.weather_worker export-bundle \
  data/processed/openmeteo/20261103T200731Z_a824a6ce \
  models/openmeteo_rainfall_v1
```

## Private Supabase persistence

Migration `202611040001_weather_worker.sql` creates the private `floodsafe_pipeline` schema:

| Relation | Purpose |
| --- | --- |
| `model_versions` | Immutable bundle identity, feature contract and model provenance |
| `worker_runs` | Hourly claims, target date, status, timestamps, expiry and safe error codes |
| `weather_inputs` | Cleaned grid/day measurements, preserving null values |
| `source_responses` | Exact API response bytes, requests, retrieval receipts and checksums |
| `rainfall_predictions` | Experimental scores, threshold outcomes, feature hashes and validity |
| `latest_status` | Latest run per model, including failure and stale status |
| `current_predictions` | Still-valid experimental scores from the latest ready run only |

All tables enable RLS. The worker role has only the required private-schema permissions; it cannot access application profiles or publish public risk assessments. Anonymous and authenticated Flutter clients have no access. `floodsafe_reader` can read only the two bounded status/prediction views, providing a future backend integration point.

Initial migration and login provisioning use the existing administrator configuration **once**:

```bash
cd backend
.venv/bin/python -m app.manage migrate
.venv/bin/python -m app.provision_worker
```

Provisioning creates `floodsafe_ingestor`, a login with no inherited administrative privileges, and saves its configuration in the ignored, mode-0600 root `.env.worker` file. It refuses to overwrite existing credentials or silently rotate an existing login. The process does not print passwords. Migration and provisioning were applied to the development Supabase project on 4 November 2026; the first real worker invocation persisted two predictions successfully.

Use the **Session pooler on port 5432**, with TLS required. Custom pooler usernames use `role.projectref`; transaction pooling is rejected because the worker uses a session advisory lock. See [Supabase connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres).

## Local verification

```bash
python3 -m venv .venv-cloud
.venv-cloud/bin/python -m pip install -r scripts/weather_worker/requirements.txt
.venv-cloud/bin/python -m scripts.weather_worker run --db-config-file .env.worker
```

The first invocation in an hour fetches and persists data. Repeating it after success returns `already_complete`. A failed or incomplete slot may be retried. Two schedulers cannot run this worker concurrently: database locking supplements the hosted workflow's concurrency group. Existing local **input-only** refreshes do not create cloud predictions and can be disabled after hosted runs are verified.

## Hosted schedule

`.github/workflows/weather-worker.yml` uses a GitHub-hosted Ubuntu runner, Python 3.13 and the committed model bundle. It runs at **17 minutes past each hour** (also 17 minutes past each hour in Nairobi), supports manual dispatch, and permits execution only from `main`. It has a ten-minute timeout, one-run concurrency and read-only repository permissions.

One repository Actions secret is required:

- Name: `FLOODSAFE_WORKER_DB_CONFIG`
- Value: the complete JSON contents of the private root `.env.worker` file.

Add it under **GitHub repository → Settings → Secrets and variables → Actions**. Do not put it in workflow YAML, commit the file, or paste it into chat. It contains only the restricted worker login, not the administrator password. GitHub provides that secret as an environment variable; the CLI logs only status, run ID, model version and error type.

Merging reviewed worker/model changes into `main` triggers an initial run automatically. You can also open **Actions → Experimental rainfall worker → Run workflow**, select `main`, and verify a successful run plus ready records in Supabase. A slot already completed locally returns `already_complete`; the next hourly slot performs a new retrieval and prediction. Only a checked hosted run establishes hosted operation. Committing a workflow or configuring a secret alone does not prove that the cloud job is active.

GitHub schedules can be delayed and inactive public repositories can have schedules disabled after 60 days. This free-tier prototype is not a guaranteed real-time emergency service. See [GitHub's scheduling documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule). Hosting the Flutter interface alone does not activate this job.

## Container deployment option

```bash
docker build -f scripts/weather_worker/Dockerfile -t floodsafe-weather-worker .
```

The image contains the runtime code and frozen bundle, runs as an unprivileged user and uses temporary scratch space. `.dockerignore` excludes credentials, datasets and application builds from the build context. Supply `FLOODSAFE_WORKER_DB_CONFIG` through the hosting provider's secret environment and schedule the container's one-shot entrypoint hourly. No persistent disk or laptop mount is required.

## Verification and remaining integration

Worker tests cover normal inference, incomplete weather, provider outage, checksum failures, unknown grids, transaction rollback, hourly idempotence, raw-evidence persistence, expired results and read/write separation. Database tests require the existing **isolated** loopback test database and marker; they never target Supabase. The backend and original research suites run separately.

```bash
python -m unittest discover -s tests -p test_weather_worker.py -v
FLOODSAFE_RUN_DB_TESTS=1 python -m unittest discover -s tests -p test_weather_worker.py -v
```

The first command skips database cases; the second requires the guarded test service. CI runs all cases against its disposable PostGIS database. Neither training nor model selection happens in the scheduled workflow.

Next steps are to expose the bounded views through a backend endpoint, define place-to-grid presentation honestly, and connect Flutter. Flood-event validation and as-issued forecast lead-time evaluation remain research work. Monitor database storage as operational history accumulates; automatic pruning is not enabled in this increment.
