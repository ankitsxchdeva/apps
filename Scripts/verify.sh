#!/bin/bash
# Regenerate projects and build every app for the simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${DEST:-platform=iOS Simulator,name=iPhone 17}"

for app in Sweep Groove; do
  echo "── $app: generating project"
  (cd "$app" && xcodegen generate --quiet)
  echo "── $app: building"
  xcodebuild -project "$app/$app.xcodeproj" -scheme "$app" \
    -destination "$DEST" -quiet build
done

echo "OK: all apps build"
