#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

PROJECT_DIR="$PWD"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' DreamLiteDesktop/Info.plist)
PRODUCTS_DIR="$PROJECT_DIR/build/release-products"
OUTPUT_DIR="$PROJECT_DIR/build/releases"
mkdir -p "$OUTPUT_DIR"

xcodebuild -project DreamLiteDesktop.xcodeproj -scheme DreamLiteDesktop \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build CONFIGURATION_BUILD_DIR="$PRODUCTS_DIR" build -quiet

STAGING_DIR=$(mktemp -d "$PROJECT_DIR/build/release-stage.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
RELEASE_DIR="$STAGING_DIR/Diffusion Studio"
mkdir -p "$RELEASE_DIR"
ditto "$PRODUCTS_DIR/Diffusion Studio.app" "$RELEASE_DIR/Diffusion Studio.app"
cp README.md "$RELEASE_DIR/"
cp RELEASE-INSTALL.md "$RELEASE_DIR/INSTALL.md"

# Keep support for assets from older releases placed beside the app.
APP_PLIST="$RELEASE_DIR/Diffusion Studio.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set DreamLitePythonPath backend/.venv/bin/python3' "$APP_PLIST"
/usr/libexec/PlistBuddy -c 'Set SanaModelPath models/Sana_Sprint_0.6B_1024px_diffusers' "$APP_PLIST"

python3 - "$PROJECT_DIR/.build/SourcePackages/checkouts" "$RELEASE_DIR/Licenses" <<'PY'
import shutil
import sys
from pathlib import Path

checkouts, destination = map(Path, sys.argv[1:])
for source in checkouts.rglob('*'):
    if not source.is_file() or '.git' in source.parts:
        continue
    if not source.name.upper().startswith(('LICENSE', 'NOTICE', 'COPYING')):
        continue
    target = destination / source.relative_to(checkouts)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
PY

# Ad-hoc signing preserves integrity without a Developer ID identity.
codesign --force --sign - "$RELEASE_DIR/Diffusion Studio.app"
codesign --verify --strict "$RELEASE_DIR/Diffusion Studio.app"

ARCHIVE="Diffusion-Studio-$VERSION-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$RELEASE_DIR" "$OUTPUT_DIR/$ARCHIVE"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Release archive: $OUTPUT_DIR/$ARCHIVE"
