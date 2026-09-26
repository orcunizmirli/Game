#!/usr/bin/env bash
# Runs the package tests on an iOS simulator, then launches the app in demo mode
# (levels played by their recorded solutions) and captures screenshots.
set -euo pipefail

BUNDLE_ID=com.orcunizmirli.tricktiles
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone") and "Pro" in d["name"]:
            print(d["udid"]); sys.exit()
for runtime in sorted(devices, reverse=True):
    for d in devices[runtime]:
        if "iOS" in runtime and d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()
')
echo "Simulator: $UDID"

xcodebuild test -quiet \
  -project Game.xcodeproj -scheme Game \
  -destination "id=$UDID" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

APP=$(find build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "*.app" | head -1)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
mkdir -p screenshots

shot() {
  xcrun simctl io "$UDID" screenshot "screenshots/$1.png" >/dev/null
  echo "captured $1"
}

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
sleep 5
shot menu

LEVELS=$(ls Packages/GameCore/Sources/GameCore/Levels/level_*.json | wc -l | tr -d ' ')
for level in $(seq 1 "$LEVELS"); do
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -demoLevel "$level"
  sleep 3.2
  shot "level_$(printf %02d "$level")_a"
  sleep 1.6
  shot "level_$(printf %02d "$level")_b"
done

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -demoLevel 1 -debugOverlay YES
sleep 3
shot debug_overlay
