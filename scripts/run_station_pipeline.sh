#!/bin/sh
set -eu
PIPELINE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PIPELINE_ROOT"
exec "${FLOODSAFE_RESEARCH_PYTHON:-python3}" -m scripts.nairobi_pipeline run "$@"
