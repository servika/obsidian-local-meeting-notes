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
#
# Pass --release to also publish a GitHub Release (tag v<VERSION>) with the DMG
# attached under the stable name AI-Meeting-Notes.dmg - that's the filename the
# landing page's "Download for macOS" button points at via /releases/latest/.
# Requires the `gh` CLI authenticated, and a signed + notarized DMG.
#
#   DEVELOPER_ID_APP="…" NOTARY_PROFILE="…" ./scripts/make-dmg.sh --release

set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE=0
for arg in "$@"; do
	case "$arg" in
		--release) RELEASE=1 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

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

NOTARIZED=0
if [ -n "${NOTARY_PROFILE:-}" ]; then
	echo "notarizing (this can take a few minutes)…"
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
	NOTARIZED=1
	echo "notarized + stapled."
else
	echo "(not notarized - set DEVELOPER_ID_APP + NOTARY_PROFILE to produce a Gatekeeper-clean DMG)"
fi

if [ "$RELEASE" -eq 1 ]; then
	if [ "$NOTARIZED" -ne 1 ]; then
		echo "refusing to --release a non-notarized DMG (set DEVELOPER_ID_APP + NOTARY_PROFILE)." >&2
		exit 1
	fi
	command -v gh >/dev/null || { echo "--release needs the gh CLI (https://cli.github.com)." >&2; exit 1; }

	TAG="v${VERSION}"
	# Stable, version-less asset name → permanent /releases/latest/download URL.
	ASSET=".build/AI-Meeting-Notes.dmg"
	cp "$DMG" "$ASSET"

	if gh release view "$TAG" >/dev/null 2>&1; then
		echo "release $TAG exists - replacing its DMG asset…"
		gh release upload "$TAG" "${ASSET}#AI-Meeting-Notes.dmg" --clobber
	else
		echo "creating release ${TAG}…"
		gh release create "$TAG" \
			--title "AI Meeting Notes ${VERSION}" \
			--notes "Signed & notarized macOS app - opens cleanly on any Mac (no Gatekeeper warning). Requires macOS 14.4+.

See the [CHANGELOG](https://github.com/servika/ai-meeting-notes/blob/main/CHANGELOG.md) for details." \
			"${ASSET}#AI-Meeting-Notes.dmg"
	fi
	echo "released: https://github.com/servika/ai-meeting-notes/releases/tag/${TAG}"
fi