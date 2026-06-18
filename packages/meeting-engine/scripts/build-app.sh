#!/usr/bin/env bash
# Build MeetingEngineApp as a code-signed .app bundle.
#
# A real, signed app (not a CLI) is what lets macOS present the
# "Screen & System Audio Recording" permission prompt. Ad-hoc signing is fine
# for local testing; distribution needs a Developer ID + notarization.
#
# Output: .build/AI Meeting Notes.app

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"

swift build -c release --product MeetingEngineApp
BIN="$(swift build -c release --show-bin-path)/MeetingEngineApp"
APP=".build/AI Meeting Notes.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetingEngineApp"

# Bundle a self-contained whisper-cli (static, native; built/cached by
# build-whisper.sh) so the app needs no `brew install whisper-cpp`.
echo "  bundling whisper-cli..."
./scripts/build-whisper.sh
cp vendor/whisper-cli "$APP/Contents/Resources/whisper-cli"
chmod +x "$APP/Contents/Resources/whisper-cli"

# Generate + embed the app icon (best-effort).
if swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
	ICON_KEY="	<key>CFBundleIconFile</key><string>AppIcon</string>"
else
	echo "  (icon generation skipped)"
	ICON_KEY=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>AI Meeting Notes</string>
	<key>CFBundleDisplayName</key><string>AI Meeting Notes</string>
	<key>CFBundleIdentifier</key><string>com.servika.meeting-engine</string>
	<key>CFBundleExecutable</key><string>MeetingEngineApp</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>${VERSION}</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key><string>14.4</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
${ICON_KEY}
	<key>NSAudioCaptureUsageDescription</key><string>Records system audio (the other meeting participants) to transcribe your meetings locally.</string>
	<key>NSMicrophoneUsageDescription</key><string>Records your microphone to transcribe your meetings locally.</string>
</dict>
</plist>
PLIST

# Sign. With a Developer ID (set DEVELOPER_ID_APP), use Hardened Runtime +
# entitlements so the app can be notarized; otherwise ad-hoc sign for local use.
# Sign nested code (the bundled whisper-cli) first, then the app - inside-out.
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
	echo "  signing with Developer ID: $DEVELOPER_ID_APP"
	codesign --force --options runtime --sign "$DEVELOPER_ID_APP" "$APP/Contents/Resources/whisper-cli"
	codesign --force --deep --options runtime \
		--entitlements scripts/app.entitlements \
		--sign "$DEVELOPER_ID_APP" "$APP"
else
	codesign --force --sign - "$APP/Contents/Resources/whisper-cli"
	codesign --force --deep --sign - --identifier com.servika.meeting-engine "$APP"
fi
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "built: $APP"
echo "run it:  open '$APP'   (a window appears; click Record, then Allow the prompt)"