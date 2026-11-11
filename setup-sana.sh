#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

command -v uv >/dev/null 2>&1 || {
  echo "Install uv first with: brew install uv"
  exit 1
}

PROJECT_DIR="$PWD"
SOURCE_DIR="$PROJECT_DIR/.build/coreai-models"
REVISION="e7b356c574b71f994ad0ea8341ac907534b3e337"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/apple/coreai-models.git "$SOURCE_DIR"
fi
if ! git -C "$SOURCE_DIR" cat-file -e "$REVISION^{commit}" 2>/dev/null; then
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$REVISION"
fi
git -C "$SOURCE_DIR" checkout --detach "$REVISION"

uv sync --project "$SOURCE_DIR" --frozen --no-default-groups --python 3.11
uv run --project "$SOURCE_DIR" --frozen --no-default-groups \
  coreai.diffusion.export sana-sprint-0.6b --output-dir "$PROJECT_DIR/models"

echo "SANA Sprint is ready. Select SANA Sprint in Diffusion Studio."
