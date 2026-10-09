#!/bin/sh
# Generates the Xcode project and builds the app into ./build.
# SwiftTerm ships a build plugin, which xcodebuild only runs with validation skipped.
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project QueenBee.xcodeproj -scheme QueenBee -configuration "${1:-Debug}" \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build 2>&1 \
  | grep -E "error:|warning: var|BUILD (SUCCEEDED|FAILED)|^\*\*" || true
