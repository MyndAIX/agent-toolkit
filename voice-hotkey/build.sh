#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/VoiceHotkey.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

# Signing identity — use your real Apple Development cert for TCC stability
# Ad-hoc (codesign --sign -) changes cdhash every build, breaking TCC grants.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"  # Use env var or ad-hoc signing

echo "=== Building VoiceHotkey ==="
cd "$SCRIPT_DIR"
swift build -c release 2>&1

echo "=== Packaging into .app bundle ==="
mkdir -p "$MACOS"
cp .build/arm64-apple-macosx/release/VoiceHotkey "$MACOS/"
cp Info.plist "$CONTENTS/"

echo "=== Signing with: $SIGN_IDENTITY ==="
codesign --force --sign "$SIGN_IDENTITY" --deep "$APP_DIR"

echo "=== Verifying ==="
codesign -dvvv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|CDHash"

echo ""
echo "=== Done ==="
echo "App bundle: $APP_DIR"
echo ""
echo "Next steps (first time only):"
echo "  1. Run:  open -a '$APP_DIR'"
echo "  2. Grant in System Settings > Privacy & Security:"
echo "     - Accessibility    → VoiceHotkey.app"
echo "     - Input Monitoring → VoiceHotkey.app"
echo "     - Microphone       → VoiceHotkey.app"
echo "  3. Install LaunchAgent:"
echo "     cp '$SCRIPT_DIR/com.voicehotkey.plist' ~/Library/LaunchAgents/"
echo "     launchctl load ~/Library/LaunchAgents/com.voicehotkey.plist"
