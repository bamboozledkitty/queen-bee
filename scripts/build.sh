#!/bin/sh
# Generates the Xcode project and builds the app into ./build.
# SwiftTerm ships a build plugin, which xcodebuild only runs with validation skipped.
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
xcodebuild -project QueenBee.xcodeproj -scheme QueenBee -configuration "${1:-Debug}" \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build > "$LOG" 2>&1 || true
grep -E "error:|warning: var|BUILD (SUCCEEDED|FAILED)|^\*\*" "$LOG" || true
# The filter above hides most of the log, so the script itself has to say whether the build worked.
grep -q "BUILD SUCCEEDED" "$LOG"
