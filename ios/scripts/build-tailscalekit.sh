#!/bin/bash
# Builds TailscaleKit.xcframework (the built-in Tailscale) from a pinned libtailscale into ios/Frameworks.
# Needs Go and Xcode. Run once, and again only to update libtailscale.
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT=d1dc45d039edb7759ecbee6ba2aea0c4bca884b8
SRC=../vendor/libtailscale
[ -d "$SRC" ] || git clone -q https://github.com/tailscale/libtailscale.git "$SRC"
git -C "$SRC" fetch -q --depth 1 origin "$COMMIT" 2>/dev/null || true
git -C "$SRC" checkout -q "$COMMIT"
make -C "$SRC/swift" ios-fat
rm -rf Frameworks/TailscaleKit.xcframework
mkdir -p Frameworks
cp -R "$SRC/swift/build/Build/Products/Release-iphonefat/TailscaleKit.xcframework" Frameworks/
echo "Frameworks/TailscaleKit.xcframework ready"
