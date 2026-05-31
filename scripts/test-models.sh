#!/bin/bash
# Compile and run lightweight model tests without Swift Package Manager.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx14.0"
TEST_BINARY="/tmp/notebloat-model-tests"

swiftc \
    -parse-as-library \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -framework SwiftUI \
    Sources/Notebloat/Models/AppSettings.swift \
    Sources/Notebloat/Models/Note.swift \
    Sources/Notebloat/Models/NoteStore.swift \
    Sources/Notebloat/Utilities/DateFormatting.swift \
    Tests/NotebloatModelTests.swift \
    -o "$TEST_BINARY"

"$TEST_BINARY"
