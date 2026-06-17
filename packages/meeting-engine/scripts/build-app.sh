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

swift build -c release --product MeetingEngineApp
BIN="$(swift build -c release --show-bin-path)/MeetingEngineApp"
APP=".build/AI Meeting Notes.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MeetingEngineApp"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>AI Meeting Notes</string>
	<key>CFBundleDisplayName</key><string>AI Meeting Notes</string>
	<key>CFBundleIdentifier</key><string>com.servika.meeting-engine</string>
	<key>CFBundleExecutable</key><string>MeetingEngineApp</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>0.1.0</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>LSMinimumSystemVersion</key><string>14.4</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSAudioCaptureUsageDescription</key><string>Records system audio (the other meeting participants) to transcribe your meetings locally.</string>
	<key>NSMicrophoneUsageDescription</key><string>Records your microphone to transcribe your meetings locally.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign with a stable identifier so TCC can track the grant.
codesign --force --deep --sign - --identifier com.servika.meeting-engine "$APP"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "built: $APP"
echo "run it:  open '$APP'   (a window appears; click Record, then Allow the prompt)"