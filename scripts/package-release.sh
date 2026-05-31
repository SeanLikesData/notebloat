#!/bin/bash
# Build Notebloat and create a distributable zip archive.
set -euo pipefail

cd "$(dirname "$0")/.."

./build.sh

APP_DIR="build/Notebloat.app"
ZIP_PATH="build/Notebloat.zip"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created $ZIP_PATH"
