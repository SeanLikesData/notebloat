#!/bin/bash
# Build the application and verify the assembled bundle has the expected shape.
set -euo pipefail

cd "$(dirname "$0")/.."

./build.sh >/tmp/notebloat-build.log

APP_DIR="build/Notebloat.app"
BINARY="$APP_DIR/Contents/MacOS/Notebloat"
PLIST="$APP_DIR/Contents/Info.plist"
ICON="$APP_DIR/Contents/Resources/AppIcon.icns"

[[ -x "$BINARY" ]] || { echo "Missing executable: $BINARY" >&2; exit 1; }
[[ -f "$PLIST" ]] || { echo "Missing Info.plist: $PLIST" >&2; exit 1; }
[[ -f "$ICON" ]] || { echo "Missing app icon: $ICON" >&2; exit 1; }

LSUIELEMENT=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")
[[ "$LSUIELEMENT" == "true" ]] || { echo "LSUIElement is not true" >&2; exit 1; }

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
[[ "$BUNDLE_ID" == "com.notebloat.app" ]] || { echo "Unexpected bundle identifier: $BUNDLE_ID" >&2; exit 1; }

ICON_FILE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")
[[ "$ICON_FILE" == "AppIcon" ]] || { echo "Unexpected icon file: $ICON_FILE" >&2; exit 1; }

echo "Notebloat smoke test passed."
