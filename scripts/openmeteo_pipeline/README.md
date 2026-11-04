# Open-Meteo research pipeline

This independent experiment extracts Nairobi weather from Open-Meteo, cleans and transforms it, analyses training data, compares Logistic Regression / Random Forest / XGBoost, and loads versioned local research snapshots. Open [the notebook](../../openmeteo_pipeline.ipynb) for the complete walkthrough.

It shares the station pipeline's tested feature engineering and chronological model routines. The station pipeline, station inputs, old model experiments, Flutter app and Supabase data are separate.

## What the source means

We request **GFS Global** explicitly from the [Historical Forecast API](https://open-meteo.com/en/docs/historical-forecast-api). This gives identifiable, reproducible source requests and an archive from a model family also available through the forecast service. It does not establish that its estimates are more accurate than local observations.

This archive stitches early hours of successive forecast runs. It is **model output**, not a station observation dataset or a record of exactly what was available at each historical prediction time. Use individual archived forecast runs to assess a particular operational lead time. Model-family selection does not pin NOAA software versions; the API does not return these versions or original run issuance timestamps here.

The three approximate study queries are western Nairobi (-1.30169, 36.75919), southern Nairobi (-1.320572, 36.815446), and eastern Nairobi (-1.28, 36.87). They are based on the previous experiment's locations, without claiming verified station identities. GFS weather grids are much larger than neighbourhoods. The extractor records the **returned grid** coordinates and native elevation, maps each query to a cell, removes repeated cell/day records, and rejects conflicting duplicates. Actual probing resolved the first two queries to the same cell.

All requests use `models=gfs_global`, `cell_selection=nearest`, `elevation=nan` (disable elevation downscaling), `timezone=GMT`. Rain sums and other daily summaries therefore describe **UTC days**, not Kenya calendar days. The same parameters must be used in any later live adapter. No automatic `best_match`, ERA5 or alternate-provider fallback is allowed.

| API daily field | Research column | Unit |
| --- | --- | --- |
| temperature_2m_mean | tavg | °C |
| temperature_2m_min | tmin | °C |
| temperature_2m_max | tmax | °C |
| precipitation_sum | prcp | mm |
| wind_speed_10m_mean | wspd | km/h |
| pressure_msl_mean | pres | hPa |

## Setup and execution

Use Python 3.13 from the repository root:

```bash
python3 -m venv .venv-research
.venv-research/bin/python -m pip install -r scripts/openmeteo_pipeline/requirements.txt
.venv-research/bin/python -m scripts.nairobi_pipeline prepare-runtime
.venv-research/bin/python -m scripts.openmeteo_pipeline run
```

`prepare-runtime` handles the existing Intel macOS XGBoost/OpenMP issue with a pinned, verified, project-local library. On other platforms it does nothing. See the [shared runtime documentation](../nairobi_pipeline/README.md) if system OpenMP is already installed.

An equivalent shell wrapper is available:

```bash
FLOODSAFE_RESEARCH_PYTHON=.venv-research/bin/python bash scripts/run_openmeteo_pipeline.sh
```

Default study period: **2021-04-01–2025-12-31**. Target calibration ends 2022-12-31; training ends 2023-12-31; validation covers 2024; final testing covers 2025. GFS archive coverage starts 2021-03-23, so these requests intentionally do not reuse the older station experiment's dates.

Other useful commands:

```bash
# Audit/ETL only; no classifiers.
.venv-research/bin/python -m scripts.openmeteo_pipeline run --mode audit

# Retrieve new raw receipts; retain every previous raw response.
.venv-research/bin/python -m scripts.openmeteo_pipeline run --refresh

# Small smoke-test estimators, identified separately in the run signature.
.venv-research/bin/python -m scripts.openmeteo_pipeline run --quick

# Score the untouched test partition AFTER validation selection is frozen.
.venv-research/bin/python -m scripts.openmeteo_pipeline evaluate-test data/processed/openmeteo/RUN_ID

# Generate a macOS replay template; does not install or enable any job.
.venv-research/bin/python -m scripts.openmeteo_pipeline schedule-template .cache/openmeteo-research.plist
```

The environment created above is covered by the repository's root allowlist and is not committed. No API key or database credentials are required for this public, non-commercial research endpoint. Do not put credentials in source code.

## Function-based stages

1. **Extract:** `source.extract_data()` requests annual chunks with bounded retries for timeouts, HTTP 429 and server errors. Requests are spaced; numeric Retry-After is respected up to 60 seconds. Other HTTP errors fail immediately. Raw JSON and receipt files contain exact parameters, retrieval time, provider identity and SHA-256. Cached responses are checked before use. Explicit refresh creates new files; previous evidence remains available.
2. **Clean:** `nairobi_pipeline.data.clean_data()` converts numeric fields, checks broad physical bounds and temperature ordering, quarantines invalid dates and conflicting records, collapses exact duplicates and inserts missing calendar days as missing. API schema, units, arrays and complete ordered date ranges are validated first. API nulls remain missing; all-null responses fail. No interpolation, filling rainfall with zero or automatic clipping of extremes. Persistent-value runs are audited but the previous station-specific masking policy is not imposed on this source.
3. **Transform:** `transform_data()` creates prior-day lags, 3/7-day means, 7-day rainfall totals, history completeness, season and grid metadata. Only data dated through t-1 enters predictors for target date t. Missing rolling-window days remain missing and estimator imputation is learned from training only.
4. **Analyse:** `runner.analyse()` produces coverage, missingness, long constant runs, cell overlap, descriptive statistics, correlations and monthly rain count/mean/maximum. Distribution analyses use training dates only; full-period quality audits are labelled separately. Monthly partial coverage is not reported as a complete rainfall total.
5. **Build models:** `runner.build_models()` calls target construction, date splitting and the existing three-model training function. Calibration, feature preprocessing and chronological model selection remain separate. All cells for a date stay in the same temporal partition/fold. Expanding folds use a one-day gap; unsupported class counts trigger documented fixed parameters rather than a random split. Majority and prior-day rain-persistence baselines accompany validation comparisons. Average precision is the main selection metric; precision, recall, F1, ROC AUC and confusion counts are retained. Models are frozen before final test evaluation.
6. **Load:** `load_data()` atomically creates a new `research.sqlite` with a unique cell/date key and saves CSV tables. No application tables are written. The source manifest, code/dependency/config signature, hashes, models and reports are stored in a uniquely named run directory.
7. **Automate:** `runner.run_pipeline()` executes all stages. A writer lock prevents overlapping runs; a complete snapshot with unchanged input/config/code/library hashes is reused. `latest.json` is updated only after a complete run. The command can be run by a scheduler; the supplied macOS template replays this fixed research configuration and is not installed automatically.

If a process is forcibly terminated and leaves `.pipeline.lock`, confirm that no pipeline writer is running before removing that lock. Failed requests or failed runs never replace a successful `latest.json`.

## Targets and fair evaluation

**No observed flood labels are available.** Default `rainfall_proxy` targets identify days whose provider-modelled rain exceeds the cell's 95th percentile of positive rain in the early calibration period. Each cell needs at least 365 valid calibration days, 30 wet days and multiple positive rainfall values. Missing rain produces no target. The threshold is part of the experimental definition, not a verified flood-warning threshold.

The three learned classifiers predict that proxy using prior weather. A high classification score is not a calibrated probability of flooding. These metrics cannot establish whether real floods were detected. Likewise, scores against this source cannot be compared directly with station scores to claim improvement: the period, spatial units and target-generating data differ.

`observed_labels` mode accepts an explicit CSV with `station_id,time,target,label_source`, where station_id is the **provider cell key**, target is an explicitly observed 0/1 value, and every observation has a source. Unlisted dates are not assumed to be non-events. Spatial/time matching and adequacy of those labels need a separate study before this mode is scientifically useful.

`evaluate-test RUN_ID` verifies frozen hashes, scores all frozen models and baselines, and writes a separate test report. It does not change selection. Repeating the command returns the verified existing result. Once inspected, the test period must not be tuned against while still called an untouched holdout.

## Files and next integration

Raw responses are under ignored `data/raw/openmeteo/`. Processed outputs are under ignored `data/processed/openmeteo/RUN_ID/`, with a verified `latest.json` pointer. Important outputs include `REPORT.md`, `TEST_REPORT.md` after explicit evaluation, `source_manifest.json`, `query_grid_mapping.csv`, `cleaning_audit.csv`, `station_quality.csv`, `features.csv`, `target_eligibility.csv`, `validation_comparison.csv`, `selection.json`, `models/`, `research.sqlite` and `run.json`. `station_*` table names are shared research interfaces; here their IDs represent grid cells.

The research `run` command performs ETL/training/loading. The separate **`refresh-inputs` command retrieves fresh recent GFS weather and prepares today's feature rows**, with no model training or inference. See [fresh-input operation and scheduling](LIVE_INPUTS.md). The [cloud worker](../weather_worker/README.md) adds frozen-model execution and private Supabase persistence. Serving results through the backend and Flutter integration remain separate work. Validate prospective lead-time skill with archived individual runs, and actual flood usefulness with observed events, before presenting operational flood risk.

## First completed experiment: 2026-11-03

The full API run produced **3,472 distinct grid/day records**, from 1,736 days across two provider cells. Deduplication removed 1,736 repeated query/day records. There were no missing calendar dates, invalid temperature ordering or conflicting cell/day measurements. Precipitation had 32 missing values (16 in each cell); these stayed missing. Other requested weather fields were complete.

After target/history eligibility checks, the partitions contain 1,966 training rows, 732 validation rows and 730 final-test rows. The latter has 52 high-rainfall proxy positives. Three expanding date-grouped folds were supported. Validation average precision selected **Logistic Regression**, and that selection stayed frozen for final testing.

| Frozen candidate | 2025 precision | 2025 recall | 2025 F1 | 2025 average precision |
| --- | ---: | ---: | ---: | ---: |
| Logistic Regression (validation-selected) | 0.2558 | 0.8462 | 0.3929 | 0.3535 |
| Random Forest | 0.2843 | 0.5577 | 0.3766 | 0.3246 |
| XGBoost | 0.0000 | 0.0000 | 0.0000 | 0.3933 |
| Previous-day rain persistence | 0.3654 | 0.3654 | 0.3654 | 0.1787 |
| Majority baseline | 0.0000 | 0.0000 | 0.0000 | 0.0712 |

The selected model found 44 of 52 proxy-positive rows, with 128 false positives. That is substantial overprediction at the predeclared 0.5 threshold. Average precision evaluates score ranking across thresholds, whereas precision/recall/F1 above use 0.5; XGBoost ranked cases but made no positive predictions at that threshold. Its higher test average precision does not change the validation-based selection. No threshold was retuned from the test results.

These are retrospective scores against **provider-generated rainfall labels**, with spatially dependent cells. They neither validate flood forecasts nor prove higher accuracy than the station experiment. The notebook reproduces the comparisons and points to the local run's reports; published outputs are cleared for portability. This first run is `data/processed/openmeteo/20261103T200731Z_a824a6ce/` (generated artefacts remain ignored by Git).

## Verification and attribution

```bash
.venv-research/bin/python -m ruff check scripts/openmeteo_pipeline tests/test_openmeteo_pipeline.py
.venv-research/bin/python -m ruff format --check scripts/openmeteo_pipeline tests/test_openmeteo_pipeline.py
.venv-research/bin/python -m unittest discover -s tests -p 'test_*pipeline.py' -v
```

API tests use offline HTTP fixtures: malformed units/schema/dates, retries, failed requests, cache corruption, immutable refresh evidence, shared-grid deduplication, conflicting duplicates, missing rain, and a complete three-model SQLite/frozen-test workflow. The notebook was executed successfully against an actual API run before its outputs were cleared for publication. CI performs only offline fixture tests.

Weather data by [Open-Meteo.com](https://open-meteo.com/) and NOAA GFS, under [CC BY 4.0](https://open-meteo.com/en/licence). See [API documentation](https://open-meteo.com/en/docs/historical-forecast-api) and [current usage terms](https://open-meteo.com/en/terms). The free API is for non-commercial use and has request limits; API billing weights may differ from the number of HTTP requests for larger date ranges.
