#!/usr/bin/env bash
set -euo pipefail

cd /workspace/target
python /workspace/control/bin/preflight_target.py

if [[ -z "${RUN_CMD:-}" ]]; then
  echo "RUN_CMD is not set."
  exit 1
fi

bash -lc "${RUN_CMD}"
