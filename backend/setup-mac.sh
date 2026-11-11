#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Missing $PYTHON_BIN. Install it with: brew install python@3.11"
  exit 1
fi
"$PYTHON_BIN" -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install 'torch>=2.5' 'torchvision' 'Pillow>=10' 'transformers==4.57.3' 'diffusers==0.39.0' 'accelerate' 'safetensors'
python -m pip check
python - <<'PY'
import torch
from diffusers import DreamLiteMobilePipeline
print('PyTorch:', torch.__version__)
print('MPS available:', torch.backends.mps.is_available())
print('DreamLiteMobilePipeline: import OK')
PY
echo 'Setup complete. Start the server with ./run-dreamlite.sh'
