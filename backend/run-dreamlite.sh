#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f .venv/bin/activate ]]; then
  echo 'Install the backend first: ./setup-mac.sh'
  exit 1
fi
source .venv/bin/activate
export PYTORCH_ENABLE_MPS_FALLBACK=1
exec python3 server.py "$@"
