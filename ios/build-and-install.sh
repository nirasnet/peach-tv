#!/bin/bash
# Builds Peach Remote and installs it on a connected/paired iPhone.
#   ./build-and-install.sh                 # first available iPhone
#   DEVICE=<devicectl id> ./build-and-install.sh
set -euo pipefail
cd "$(dirname "$0")"
scripts/gen-pairing.sh
xcodegen generate --quiet
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')}"
[ -n "$DEVICE" ] || { echo "No available iPhone found (xcrun devicectl list devices)." >&2; exit 1; }
xcodebuild -project PeachRemote.xcodeproj -scheme PeachRemote -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath build -allowProvisioningUpdates -quiet build
APP="build/Build/Products/Release-iphoneos/Peach Remote.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.example.PeachRemote || true
echo "Installed Peach Remote on $DEVICE"
