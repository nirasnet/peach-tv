#!/bin/bash
# Archives Peach Remote and uploads it to TestFlight with the App Store Connect API key.
# Needs the app record for your bundle ID (PRODUCT_BUNDLE_IDENTIFIER in project.yml) in App Store Connect (My Apps → + → New App).
# The build number is the current time, so every upload is accepted.
set -euo pipefail
cd "$(dirname "$0")/.."
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key ID)}"
ISSUER="${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer ID)}"
AUTH=(-authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8"
      -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
scripts/gen-pairing.sh
xcodegen generate --quiet
rm -rf build/archive build/export-store
xcodebuild -project PeachRemote.xcodeproj -scheme PeachRemote -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/archive/PeachRemote.xcarchive -derivedDataPath build/DerivedArchive \
  CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates "${AUTH[@]}" -quiet archive
xcodebuild -exportArchive -archivePath build/archive/PeachRemote.xcarchive -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export-store -allowProvisioningUpdates "${AUTH[@]}" -quiet
IPA=$(ls build/export-store/*.ipa)
[ "${SKIP_UPLOAD:-0}" = 1 ] && { echo "Built $IPA (build $BUILD), not uploaded"; exit 0; }
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
echo "Uploaded build $BUILD. Apple processes it in about 10–20 min, then: python3 scripts/testflight_invite.py --build $BUILD"
