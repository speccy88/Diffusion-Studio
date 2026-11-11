#!/bin/bash
set -euo pipefail

MODEL="$1"
DATA_DIR="$2"
RESOURCES=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$DATA_DIR/tools"
WORK_DIR=$(mktemp -d "$DATA_DIR/setup.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
export UV_PYTHON_INSTALL_DIR="$DATA_DIR/python"
export UV_CACHE_DIR="$DATA_DIR/cache/uv"
export UV_NO_PROGRESS=1
export UV_NO_CONFIG=1
export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
export PYTHONUNBUFFERED=1
unset VIRTUAL_ENV PYTHONHOME PYTHONPATH

stage() { printf 'STUDIO_STAGE:%s\n' "$1"; }
fetch() { /usr/bin/curl --fail --location --silent --show-error --retry 2 "$1" --output "$2"; }

UV_VERSION=0.11.6
UV="$DATA_DIR/tools/uv-$UV_VERSION"
if [[ ! -x "$UV" ]]; then
    stage 'Downloading setup tools…'
    fetch "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-apple-darwin.tar.gz" "$WORK_DIR/uv.tar.gz"
    (cd "$WORK_DIR" && printf '%s  uv.tar.gz\n' '4b69a4e366ec38cd5f305707de95e12951181c448679a00dce2a78868dfc9f5b' | /usr/bin/shasum -a 256 -c - >&2)
    /usr/bin/tar -xzf "$WORK_DIR/uv.tar.gz" -C "$WORK_DIR" uv-aarch64-apple-darwin/uv
    mv "$WORK_DIR/uv-aarch64-apple-darwin/uv" "$UV"
fi

stage 'Preparing Python 3.11…'
"$UV" python install 3.11 --no-bin >&2

case "$MODEL" in
    dreamLite)
        RUNTIME="$DATA_DIR/dreamlite"
        mkdir -p "$RUNTIME"
        PYTHON="$RUNTIME/.venv/bin/python3"
        stage 'Installing DreamLite dependencies…'
        rm -f "$RUNTIME/runtime-ready"
        if [[ ! -x "$PYTHON" ]]; then
            "$UV" venv --managed-python --python 3.11 "$RUNTIME/.venv" >&2
        fi
        "$UV" pip install --python "$PYTHON" --only-binary :all: \
            'torch>=2.5' torchvision 'Pillow>=10' 'transformers==4.57.3' \
            'diffusers==0.39.0' accelerate safetensors >&2
        "$UV" pip check --python "$PYTHON" >&2
        "$PYTHON" - <<'PY' >&2
import torch
from diffusers import DreamLiteMobilePipeline

if not torch.backends.mps.is_available():
    raise RuntimeError("The installed PyTorch runtime cannot use the Apple GPU.")
PY
        touch "$RUNTIME/runtime-ready"
        stage 'Downloading DreamLite model files…'
        "$PYTHON" "$RESOURCES/download-model.py" "$MODEL" "$RUNTIME/model-path"
        ;;
    sanaSprint)
        REVISION=e7b356c574b71f994ad0ea8341ac907534b3e337
        SOURCE_DIR="$DATA_DIR/coreai-models-$REVISION"
        stage 'Installing SANA export tools…'
        if [[ ! -f "$SOURCE_DIR/uv.lock" ]]; then
            fetch "https://codeload.github.com/apple/coreai-models/tar.gz/$REVISION" "$WORK_DIR/coreai.tar.gz"
            /usr/bin/tar -xzf "$WORK_DIR/coreai.tar.gz" -C "$WORK_DIR"
            mv "$WORK_DIR/coreai-models-$REVISION" "$SOURCE_DIR"
        fi
        "$UV" sync --project "$SOURCE_DIR" --frozen --no-default-groups --managed-python --python 3.11 >&2
        stage 'Downloading SANA model files…'
        "$SOURCE_DIR/.venv/bin/python3" "$RESOURCES/download-model.py" "$MODEL"
        stage 'Converting SANA for Apple Core AI…'
        HF_HUB_OFFLINE=1 "$SOURCE_DIR/.venv/bin/coreai.diffusion.export" \
            sana-sprint-0.6b --output-dir "$WORK_DIR/models" >&2
        NAME=Sana_Sprint_0.6B_1024px_diffusers
        EXPORTED="$WORK_DIR/models/$NAME"
        for asset in metadata.json tokenizer/tokenizer.json Transformer.aimodel TextEncoder.aimodel VAEDecoder.aimodel; do
            test -e "$EXPORTED/$asset"
        done
        mkdir -p "$DATA_DIR/models"
        if [[ -e "$DATA_DIR/models/$NAME" ]]; then
            mv "$DATA_DIR/models/$NAME" "$WORK_DIR/previous-export"
        fi
        mv "$EXPORTED" "$DATA_DIR/models/$NAME"
        ;;
    *) echo "Unknown model: $MODEL" >&2; exit 2 ;;
esac
