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

# Fails the job if the app is no longer running (i.e. it crashed).
alive() {
  local services
  services=$(xcrun simctl spawn "$UDID" launchctl list)
  if ! grep -q "$BUNDLE_ID" <<<"$services"; then
    echo "::error::app is not running after $1 (crash?)"
    ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5
    latest=$(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -1)
    [ -n "$latest" ] && head -80 "$latest"
    exit 1
  fi
}

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
sleep 5
shot menu
alive menu

LEVELS=$(ls Packages/GameCore/Sources/GameCore/Levels/level_*.json | wc -l | tr -d ' ')
for level in $(seq 1 "$LEVELS"); do
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -demoLevel "$level"
  # Taking a screenshot itself takes a few seconds, so shoot almost immediately.
  sleep 0.3
  shot "level_$(printf %02d "$level")_a"
  shot "level_$(printf %02d "$level")_b"
  alive "level $level"
done

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -demoLevel 1 -debugOverlay YES
sleep 3
shot debug_overlay

alive debug_overlay

# Text previews of the screenshots for environments that cannot download artifacts.
python3 -m pip install --quiet --break-system-packages pillow 2>/dev/null || python3 -m pip install --quiet pillow
python3 scripts/screenshot_ascii.py screenshots/*.png
