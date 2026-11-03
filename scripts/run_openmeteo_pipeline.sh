#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${FLOODSAFE_RESEARCH_PYTHON:-python3}" -m scripts.openmeteo_pipeline run "$@"
