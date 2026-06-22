#!/usr/bin/env bash
#
# Build, Developer-ID-sign, notarize, and staple a distributable Wardlume DMG.
# This is THE fix for the "Wardlume is damaged and can't be opened" Gatekeeper
# error — a notarized + stapled DMG opens on any Mac with no warning.
#
# Requires a paid Apple Developer Program membership:
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. A one-time notarytool credential profile:
#        xcrun notarytool store-credentials wardlume-notary \
#          --apple-id "you@example.com" --team-id "XXXXXXXXXX" \
#          --password "<app-specific-password from appleid.apple.com>"
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/notarize.sh 1.2.0
#
set -euo pipefail

VERSION="${1:?usage: notarize.sh <version>   e.g. ./scripts/notarize.sh 1.2.0}"
DEV_ID="${DEV_ID:?set DEV_ID to your 'Developer ID Application: NAME (TEAMID)' identity}"
PROFILE="${NOTARY_PROFILE:-wardlume-notary}"
SCHEME="Wardlume"
PROJECT="Wardlume.xcodeproj"
BUILD_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
DMG="Wardlume-${VERSION}.dmg"
trap 'rm -rf "$BUILD_DIR" "$STAGE"' EXIT

echo "▸ Building Release, signed with Developer ID + hardened runtime…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEV_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build

APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Packaging DMG (drag-to-Applications layout)…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$SCHEME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$DEV_ID" --timestamp "$DMG"

echo "▸ Submitting to Apple notary service (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling the notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✓ $DMG is signed, notarized, and stapled — opens with no Gatekeeper warning."
