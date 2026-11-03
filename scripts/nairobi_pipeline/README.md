# Nairobi station pipeline

A function-based research pipeline built around the **four CSV files listed in `station_sources.json`**. The source files are not rewritten; no exploratory notebook is required. Start with the executable [Nairobi station notebook](../../nairobi_station_pipeline.ipynb).

## What is being predicted?

The station files contain weather, not observed flood outcomes. The default experiment predicts whether **target-day recorded rainfall exceeds a station-specific 95th percentile of positive rainfall in an early calibration period**. Predictors use weather from the previous calendar day or earlier. This is an exploratory **high-rainfall proxy**, not a verified flood-risk model, calibrated flood probability or evacuation trigger. It must not be connected to live app warnings as though it were validated flooding.

Floods also depend on catchment rainfall, river conditions, drainage, terrain, exposure and other factors absent from these files. Independently sourced, spatially and temporally matched flood outcomes are needed to evaluate actual flood prediction. An explicit observed-label path is provided for a later verified dataset.

The older GloFAS/high-flow experiment and its reserved test period are untouched. These are separate inputs and a different target.

## Input selection and important findings

The explicit source manifest selects only these files, not all Kenyan stations:

| Notebook file / station ID | Recorded days in supplied file | Missing days inside its date range |
| --- | ---: | ---: |
| `63740_Nairobi_ACC-FIC-RCC-MET-COM-_cleaned.csv` | 3,882 | 73 |
| `63741_Nairobi_-_Dagoretti_cleaned.csv` | 2,770 | 1,181 |
| `63742_Nairobi_-_Wilson_cleaned.csv` | 3,123 | 821 |
| `HKRE0_Nairobi_-_Doonholm_cleaned.csv` | 164 | 3,765 |

These counts were inspected on 3 November 2026; generated run reports are authoritative if files change. The combined extraction contains 9,939 original rows. Each row retains station identity; weather is not averaged into one Nairobi series.

Source documentation credits Charity Githogora with prior processing and describes research/educational use. It does **not** provide the original missing-value masks, exact imputation/smoothing steps, or fully specified original provider lineage. Zero nulls therefore do not establish complete or leakage-free observations.

Notable issues:

- ACC/FIC and Dagoretti have identical metadata coordinates but different weather tables. Both identities are retained and the possible dependence is reported.
- Doonholm's filename ID is `HKRE0`, while the supplied metadata calls Nairobi Doonholm `HKJK`. The alias is explicit, name-checked and flagged as unverified. It is not an assertion that station identity has been independently established.
- ACC/FIC records exactly 43.9 mm/day for 184 consecutive days and other long constant non-zero runs. Wilson repeats 0.7 mm frequently. These are suspicious for prior filling, not independently proven measurement errors.
- Doonholm lacks the default minimum calibration history. Wilson's positive rainfall in the default calibration period has no variation. Both remain in ETL/analysis but are excluded from this proxy's training under the default quality rules.

The pipeline cannot reverse undocumented upstream imputation. Even after the additional quality checks, results remain conditional on the supplied preprocessed source.

## Stages and functions

```text
explicit CSV manifest + station CSVs + metadata
    → extract_data
    → clean_data                     original strings + quarantine + daily calendar
    → mask_persistent_values         separate, causal modelling view
    → transform_data                 station-specific past-only predictors
    → analyse_data                   quality + training-only descriptive analysis
    → create_targets                 frozen early calibration / explicit labels
    → split_data                     global date boundaries across all stations
    → train_models                   fold-local preprocessing + model comparison
    → load_data                      versioned research SQLite and CSV snapshots
    → freeze selection and artefact checksums
    → evaluate_test                  separate, explicit final scoring
```

`run_pipeline` orchestrates the stages automatically. `generate_schedule` writes an optional macOS schedule template. Network access is not needed for ETL/training after packages and any required native runtime are installed. No records are loaded into the FloodSafe app database.

### Extraction

The default source list is the version-controlled `station_sources.json` manifest. An optional `--notebook` override can parse literal `read_csv` references without executing notebook cells. Files are resolved by basename beneath the configured source root. Metadata uses UTF-8 where possible and an explicit CP1252 fallback for the supplied degree characters. Southern latitudes become negative numeric coordinates; station IDs remain strings. CSV bytes are hashed at extraction and source row/file references are retained. Missing/ambiguous required columns or non-Nairobi metadata matches stop the run; unexpected measurement columns are recorded and excluded rather than silently becoming predictors.

### Cleaning

- Strip header/text whitespace and recognise explicit missing tokens.
- Convert weather text to numbers; accept valid English thousands grouping without guessing decimal-comma conventions.
- Reject invalid/future dates into `rejected_rows`.
- Mask non-finite values, negative rain/wind, broad physical sanity violations and inconsistent temperature ordering. Per-field flags remain available.
- Collapse canonical exact duplicate station-days. Quarantine **all** rows for a conflicting station-day rather than arbitrarily taking a last value or mean.
- Reindex separately by station to a daily calendar, including conflicted boundary dates. Missing days remain missing, never dry days.
- Retain original raw strings and source row numbers in the snapshot. Partial measurement failures do not automatically delete an otherwise useful row.

Default broad bounds are temperatures −90…60 °C, rainfall 0…2,000 mm/day, wind 0…500 km/h and sea-level pressure 800…1,100 hPa. They are transparent sanity limits, **not locally calibrated extreme-weather thresholds**. `clean_data(..., bounds=...)` can accept reviewed replacements. There is no generic IQR deletion, clipping or winsorisation of plausible extremes.

### Quality view, features and analysis

The clean source table remains intact. A separate `model_weather` view withholds a measurement from day 30 of an unchanged run onward, independently within each station. Zero rainfall is exempt because extended dry spells can be real. This is a configurable conservative modelling exclusion (`mask_persistent_values(..., minimum_run=...)`), not a declaration that all repetition is erroneous. The flag uses only the run length known up to that day; earlier days are not retroactively masked using future observations. Initial suspicious days and unknown upstream filling can still affect results.

Weather lags, rolling means/sums, prior rainfall availability counts, season terms and station metadata are created without cross-station mixing. Full rolling windows require complete observations. At least three observed/model-usable rainfall days in the prior week are required for a model row. No backward fill or interpolated rain is used.

Full-period outputs audit coverage, conflicts and suspicious runs; descriptive statistics, correlations and monthly summaries are restricted to training dates. Grouping is used only for station/calendar correctness, rolling features, seasonal summaries and per-station comparisons. No arbitrary discretisation of the weather variables is needed.

### Targets and splitting

Default dates:

- **Calibration:** available station records through 31 December 2019, within the training period.
- **Training:** through 31 December 2021.
- **Validation:** 1 January 2022–31 December 2023.
- **Final test:** 1 January 2024 onward in the supplied data.

Calibration precedes every internal CV validation block. This prevents the data-derived target threshold from looking into those blocks. A station needs 365 usable calibration rain observations, 30 positive-rain observations and more than one distinct positive amount. Those are configurable data-support guards, not a statistical-power guarantee. Unsupported stations have no proxy target; missing target rainfall is never labelled zero.

The positive target is `recorded_rain > calibration_positive_rain_Q95`. This quantile is distinct from the classifier score threshold 0.5. Current-day weather and the target-defining threshold are excluded from the learned-model predictor allowlist.

All stations for a given date stay on the same side of a split. Validation and test features may use legitimately available earlier history. The experiment concerns future dates at known stations, not unseen-station generalisation. Dates are treated as supplied daily calendar dates; source timezone and original publication timing are not independently verified.

### Training, comparison and testing

The three models are scikit-learn-compatible pipelines:

1. Numeric median imputation and missingness indicators, fitted on training data only.
2. Scaling for Logistic Regression; no unnecessary scaling for tree models.
3. Station one-hot encoding with explicit unknown-category handling.
4. Logistic Regression, Random Forest or XGBoost.

Three expanding, date-grouped CV blocks with a one-day gap select among small, predefined parameter grids using average precision. Each fold fits a new complete preprocessing pipeline. If a chronological fold cannot support both classes, the run records that limitation and fits **predeclared fixed settings**, instead of silently randomising observations or pretending CV succeeded. The default real-data run records its actual strategy in `selection.json`.

Logistic Regression and Random Forest use balanced class weighting fitted by their estimators; XGBoost's default experiment is unweighted. This comparison evaluates those complete candidate configurations, not algorithm identity alone. Seed 42 is fixed; CV runs serially and tree estimators use two workers.

Majority and prior-rain classification baselines are included. Prior-rain missing values use training-only medians for this baseline, not an assumed zero. The selected **learned** model is frozen by validation average precision, then F1, then model name. The report separately states whether it beat the best baseline by that selection metric. Higher AP does not imply better F1 at threshold 0.5 or better emergency decisions.

Metrics include class support, accuracy, balanced accuracy, precision, recall, F1, ROC-AUC, average precision, confusion counts, validation predictions and station-level results. Undefined single-class ranking metrics are left undefined. Scores are not claimed to be calibrated probabilities.

`evaluate_test` verifies the frozen SQLite/model checksums, scores all frozen candidates/baselines without changing selection, and writes separate final-test artefacts. Repeating it returns the same verified evaluation. Never use these results to retune and then call the same period untouched. `joblib` artefacts are local trusted outputs; do not load models from untrusted sources.

## Setup and run

From the repository root, using Python 3.13:

```sh
python3 -m venv .venv-stations
.venv-stations/bin/python -m pip install -r scripts/nairobi_pipeline/requirements.txt
```

On an Intel Mac with a missing OpenMP runtime, an optional helper downloads a small pinned conda-forge `llvm-openmp` package, verifies its SHA-256, and reads only the library/licence files into ignored project-local cache:

```sh
.venv-stations/bin/python -m scripts.nairobi_pipeline prepare-runtime
```

No system library path is modified by this helper. It is unnecessary on platforms with a working XGBoost runtime. The library is preloaded from the verified cache before XGBoost is imported. The standard Homebrew route attempted on the development Mac required a CMake source build and failed, so the prebuilt runtime was used for verification. The cache is not committed.

Audit only:

```sh
.venv-stations/bin/python -m scripts.nairobi_pipeline run --mode audit
```

Full experimental rainfall workflow, including model training and validation:

```sh
.venv-stations/bin/python -m scripts.nairobi_pipeline run
```

Explicit final test, **after** inspecting and freezing the method:

```sh
.venv-stations/bin/python -m scripts.nairobi_pipeline evaluate-test data/processed/nairobi_stations/<run-id>
```

Paths/date boundaries can be overridden with `--source-root`, `--notebook`, `--output-root`, `--calibration-end`, `--train-end` and `--validation-end`. Other scientific settings are explicit fields on `Config` for notebook/programmatic use. Do not tune date/quality settings from final-test scores.

For VS Code/Jupyter, select the research environment's interpreter. If needed, register it with:

```sh
.venv-stations/bin/python -m ipykernel install --user --name floodsafe-stations --display-name 'FloodSafe station research'
```

The pipeline imports are repository-relative and the notebook locates the project root. Machine-specific exploratory notebook paths are not required by the workflow.

## Loaded artefacts and automation

Each successful run has a unique directory under ignored `data/processed/nairobi_stations/`, containing:

- `source_manifest.json`: selected source files and hashes, selection/metadata provenance and encoding.
- `raw_weather.csv`, `cleaned_weather.csv`, `rejected_rows.csv`, `cleaning_audit.csv`, `model_weather.csv`, `features.csv` and `stations.csv`.
- Coverage, constant-run, overlap and training-only statistics/correlation/monthly reports.
- `research.sqlite`: raw, clean, feature, audit and optional modelling/validation tables; a unique station/date index protects the clean calendar.
- Modelling runs: target eligibility, labelled partition snapshot, CV records, validation metrics/predictions, model artefacts and frozen selection/checksums.
- `REPORT.md` and `run.json`: method, limitations, versions, code/input signature and output checksums.
- Explicit test stage: `test_metrics.csv`, `test_predictions.csv`, `test_evaluation.json` and `TEST_REPORT.md`.

SQLite is built in a temporary file then atomically published, and metadata pointers are atomically replaced. Identical source/configuration/code/dependencies reuse a hash-verified completed run. Changed or incomplete runs do not silently overwrite historical results. A single-writer lock prevents concurrent scheduled ETL writers. If a process is forcibly killed, inspect the lock/PID and remove a stale lock only after confirming that no writer is running.

The runner automates local extraction, not retrieval of new upstream station observations. New or replaced selected files trigger a new run. No hosted app credentials, Supabase writes or paid service is required.

A shell entry point and optional local-time macOS LaunchAgent template are included:

```sh
FLOODSAFE_RESEARCH_PYTHON="$PWD/.venv-stations/bin/python" scripts/run_station_pipeline.sh
.venv-stations/bin/python -m scripts.nairobi_pipeline schedule-template --hour 7 --minute 0
```

The template is generated under the output folder. It is **not installed or enabled automatically**; 07:00 is an editable example. Installation, if wanted, consists of copying the generated plist into the user's LaunchAgents folder and loading it with `launchctl`. Ensure the selected Python environment and source files remain available. Scheduled runs never automatically score the final test set.

## Observed flood labels later

Use `--mode observed_labels --labels /path/to/verified_labels.csv`. Required columns are:

```csv
station_id,time,target,label_source
```

Dates must be ISO daily dates and targets explicitly 0/1. Every label needs a source and must match a selected station/calendar record. Duplicates, unknown keys, empty provenance and non-binary targets fail validation. Unlabelled days remain unlabelled. Independent verification of event coverage, negatives, flood-to-station mapping, reporting bias and timing remains the researcher's responsibility; matching CSV keys alone does not establish a valid flood target.

## Verification

```sh
.venv-stations/bin/python -m unittest discover -s tests -p 'test_nairobi_pipeline.py' -v
```

Tests use small **synthetic fixtures only**, including all three models, and do not claim scientific performance. They cover type/date failures, duplicate conflicts, missing calendar dates, causal lags and quality masks, calibration isolation, sparse/constant stations, label coverage, chronological folds, snapshot loading and final-evaluation integrity. Actual-data validation and test scores are separate run artefacts.

Method references: [scikit-learn leakage and pipelines](https://scikit-learn.org/stable/common_pitfalls.html), [time-ordered splitting](https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.TimeSeriesSplit.html), and [XGBoost estimator interface](https://xgboost.readthedocs.io/en/release_3.0.0/python/sklearn_estimator.html). Dataset units and source attribution come from the supplied dataset README and data dictionary. No external flood labels were inferred from those documents.
