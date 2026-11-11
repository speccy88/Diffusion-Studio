#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f .venv/bin/activate ]]; then
  source .venv/bin/activate
fi
python3 -c 'from PIL import Image' 2>/dev/null || { echo 'Pillow is missing: python3 -m pip install Pillow'; exit 1; }
exec python3 server.py --demo
