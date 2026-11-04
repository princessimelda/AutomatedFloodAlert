# Fresh Nairobi weather inputs

`refresh-inputs` retrieves the **previous seven completed UTC days** from the [Open-Meteo Forecast API](https://open-meteo.com/en/docs), using the same explicit `gfs_global` model, six daily fields, units, native grid elevation, nearest-cell selection and UTC days as the research experiment. It prepares the target day's features using those completed days. Today's partial weather is excluded. These are recent weather-model estimates, not measured station observations.

The first successful retrieval on 2026-11-03 covered **2026-10-27 through 2026-11-02**, producing 14 cleaned cell/day records and complete feature rows for both trained Nairobi grid cells for **2026-11-03**. All live grid coordinates and elevations matched the frozen research snapshot.

## Run manually

The local persistent environment is `.venv-weather`, with only the weather ingestion dependencies. For a fresh checkout, first set up a historical research snapshot using the main pipeline README; the compatibility guard requires its manifest and grid metadata. Then:

```bash
python3 -m venv .venv-weather
.venv-weather/bin/python -m pip install -r scripts/openmeteo_pipeline/requirements-live.txt
.venv-weather/bin/python -m scripts.openmeteo_pipeline refresh-inputs
.venv-weather/bin/python -m scripts.openmeteo_pipeline input-status
```

`refresh-inputs --reference-run data/processed/openmeteo/RUN_ID` pins a particular study snapshot. Without that option, it uses the historical pipeline's local latest pointer. It never retrains or selects a model.

Every refresh makes new API requests. Raw response bytes, retrieval receipts and checksums are retained under ignored `data/raw/openmeteo_live/`. Retry/backoff handles transient transport errors, rate limits and server failures. There is no cached-response or alternate-model fallback.

## What is saved

Each retrieval creates a new ignored directory under `data/live/openmeteo/`. It contains:

- `cleaned_weather.csv`: the seven completed days per unique grid cell.
- `current_inputs.csv`: today's feature rows, ready for later frozen-model inference.
- `grid_readiness.csv`: whether each grid has complete features, including missing-field names.
- `features.csv`, raw records, cleaning/rejection audits and query-to-grid mapping.
- `research.sqlite`: the same tables in an atomic local SQLite snapshot.
- `source_manifest.json`: exact API requests, raw-file links and retrieval checksums.
- `snapshot.json`: target date, weather coverage, expiry, reference study and all output hashes.

The source compatibility check verifies the reference manifest/metadata hashes, model name, all weather request options, exact returned grid identities/elevations and the feature-engineering code used at training. It fails rather than silently remapping changed grids or using changed features. Provider model-version/issuance timestamps are not supplied by this response; they remain explicitly unknown.

Removing the exploratory station notebook changed source-selection configuration, not preprocessing. `feature_compatibility.json` records the original module hash and its preprocessing AST fingerprint. That one documented migration is accepted only while all non-selection code remains identical; tests verify that changing a weather lag or using an unknown reference still fails. Existing frozen models therefore remain usable without retraining for a file-selection change.

## Readiness and failures

`latest_inputs()` is the checked interface for later backend integration. It returns feature rows only when the latest attempt is ready, the target date is today UTC, the snapshot has not expired, and all stored hashes match.

- **ready:** both grids have complete features from the seven-day history.
- **incomplete:** at least one required feature is missing. Values are not fabricated; `refresh-inputs` exits with code 2.
- **unavailable:** the most recent refresh failed, no snapshot exists, or the clock precedes its retrieval. A failed attempt does not expose an older successful snapshot as current.
- **stale:** the current UTC day has ended. Yesterday's target-day features are withheld even if the computer was asleep.

Missing precipitation stays missing; invalid readings undergo the shared numeric/range/order checks. Strict readiness deliberately requires complete seven-day features, even though the research classifiers can impute some missing predictors. This helps establish a clear initial ingestion contract.

`status.json` records the last attempt; `latest.json` points to the last completed snapshot. A single-writer lock prevents overlapping manual/scheduled refreshes. After a forcibly terminated process, confirm no refresh is running before removing `.refresh.lock`.

## Hourly local refresh

The macOS LaunchAgent template refreshes once per hour and when loaded. It uses the persistent `.venv-weather` interpreter, never the temporary research environment, and can pin a specific historical reference. Generate a reviewable template with:

```bash
.venv-weather/bin/python -m scripts.openmeteo_pipeline fresh-schedule-template \
  .cache/openmeteo-fresh.plist \
  --python-executable .venv-weather/bin/python \
  --reference-run data/processed/openmeteo/20261103T200731Z_a824a6ce
```

The job was **enabled and verified on this Mac on 2026-11-03**. Its first automatic run completed successfully, returned ready inputs for both grid cells, and exited with code 0 with no stderr output. The installed job is `org.floodsafe.openmeteo-fresh` in the current user's `~/Library/LaunchAgents/`. Check it with:

```bash
launchctl list org.floodsafe.openmeteo-fresh
```

To stop the background refresh:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/org.floodsafe.openmeteo-fresh.plist
```

To enable it again:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.floodsafe.openmeteo-fresh.plist
```

Logs are `.cache/fresh.stdout.log` and `.cache/fresh.stderr.log`. The job only runs while this Mac is awake and the user session is available; it is not hosted infrastructure. Moving the project or deleting its interpreter/reference snapshot requires updating the job. The job refreshes current inputs independently of historical model training.

## What comes next

This command ingests weather and prepares compatible, dated feature rows. The separate [cloud worker](../weather_worker/README.md) now applies the frozen classifier and persists experimental results in Supabase. Backend endpoints and Flutter integration remain the next application step. The historical archive's retrospective evaluation still does not establish as-issued lead-time skill or actual flood prediction accuracy.
