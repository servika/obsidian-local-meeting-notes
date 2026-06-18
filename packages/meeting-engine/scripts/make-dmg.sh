#!/usr/bin/env bash
# Build a distributable .dmg of AI Meeting Notes.
#
# Works with no Apple Developer account (produces an ad-hoc-signed app inside an
# unsigned DMG - fine for your own use; other users right-click → Open the first
# time). For a clean public download, set these env vars to also sign + notarize:
#
#   DEVELOPER_ID_APP   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE     name of a stored notarytool profile (see below)
#
#   # one-time, to store notarization credentials in the keychain:
#   xcrun notarytool store-credentials NOTARY_PROFILE \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
# Output: .build/AI Meeting Notes.dmg

set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"
APP=".build/AI Meeting Notes.app"
DMG=".build/AI Meeting Notes ${VERSION}.dmg"
STAGING=".build/dmg-staging"
VOL="AI Meeting Notes"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications" # drag-to-install layout

hdiutil create -volname "$VOL" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "built: $DMG"

if [ -n "${DEVELOPER_ID_APP:-}" ]; then
	echo "signing DMG…"
	codesign --force --sign "$DEVELOPER_ID_APP" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
	echo "notarizing (this can take a few minutes)…"
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
	echo "notarized + stapled."
else
	echo "(not notarized - set DEVELOPER_ID_APP + NOTARY_PROFILE to produce a Gatekeeper-clean DMG)"
fi