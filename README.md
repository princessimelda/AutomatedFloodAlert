# Automated Flood Alert

Final-year project investigating flood-related risk in Nairobi and developing the FloodSafe application.

## Repository contents

| Path | Purpose |
| --- | --- |
| `weatherdata.ipynb` | Research and model-development notebook |
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
