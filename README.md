# Automated Flood Alert

Final-year project investigating flood-related risk in Nairobi and developing the FloodSafe application.

## Repository contents

| Path | Purpose |
| --- | --- |
| `weatherdata.ipynb` | Research and model-development notebook |
| `nairobi_station_pipeline.ipynb` | Function-based station ETL and experimental high-rainfall model comparison |
| `openmeteo_pipeline.ipynb` | API-based Nairobi weather ETL, grid deduplication and separate model comparison |
| `scripts/` | Data preparation, training, model comparison, and evaluation scripts |
| `models/` | Saved research model experiments |
| `floodsafe/` | Flutter interface prototype for Android and web |
| `backend/` | Local FastAPI service, configuration template and API/database tests |
| `supabase/` | PostgreSQL/PostGIS schema, migrations, development seeds and database design |

Datasets, research documents, local environments, and generated application builds are excluded. Model scripts require local data under `data/`; cloning this repository alone does not provide the training inputs.

The models remain experimental. The Flutter app can use a local API backed by PostgreSQL/PostGIS for published places, timestamped risk summaries and advisories. Current seeds and fixtures are explicitly labelled demonstration data, not live predictions. The local API connection to the hosted Supabase development database was verified on 2026-10-28; automated destructive database tests remain isolated locally.

See the [backend setup](backend/README.md) and [database design](supabase/README.md) for the connected development flow. No paid services are required for local development.

[Download the FloodSafe Android APK](https://github.com/princessimelda/AutomatedFloodAlert/raw/refs/heads/main/floodsafe/downloads/FloodSafe-0.1.0.apk).

See the [Flutter application README](floodsafe/README.md) for setup and demonstration instructions.

## Nairobi station research workflow

The [station pipeline notebook](nairobi_station_pipeline.ipynb) uses the four datasets listed in [the source manifest](scripts/nairobi_pipeline/station_sources.json). It audits and preserves station identity, creates calendar-safe features, loads local research snapshots, and compares Logistic Regression, Random Forest and XGBoost. See the [pipeline setup and methodology](scripts/nairobi_pipeline/README.md) for one-command execution, explicit final testing and optional scheduling.

The weather files have no observed flood labels. The default target is an explicitly labelled high-rainfall proxy, with missingness, suspicious repeated readings and undocumented upstream processing reported. These experiments are not deployed flood-risk predictions.

## Open-Meteo research workflow

The [Open-Meteo notebook](openmeteo_pipeline.ipynb) runs a separate API-based extract, clean, transform, analyse, model and load workflow using a fixed GFS model. It preserves raw API receipts, deduplicates shared grid cells and compares the same three model families with temporal splits and frozen final testing. See the [setup and methodology](scripts/openmeteo_pipeline/README.md). Generated data stays local; the default target remains experimental high rainfall rather than observed flooding.

Fresh recent weather can be retrieved with `python -m scripts.openmeteo_pipeline refresh-inputs`. This prepares today's inputs from seven completed UTC days, checks compatibility with the training snapshot and tracks missing/stale/failed refreshes. See [fresh inputs and hourly local scheduling](scripts/openmeteo_pipeline/LIVE_INPUTS.md). Model inference and serving predictions to Flutter remain separate integration work.
