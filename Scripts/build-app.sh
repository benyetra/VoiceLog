#!/bin/bash
set -euo pipefail

# Build VoiceLog.app bundle from Swift Package Manager output
# Usage: ./Scripts/build-app.sh [release|debug]

CONFIG="${1:-release}"
APP_NAME="VoiceLog"
BUNDLE_ID="com.bennettyetz.voicelog"
VERSION="1.0.0"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME} (${CONFIG})..."

# Build with SPM
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

# Verify executable exists
EXECUTABLE="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Executable not found at ${EXECUTABLE}"
    exit 1
fi

# Clean previous build
rm -rf "$APP_DIR"

# Create .app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$EXECUTABLE" "$MACOS_DIR/${APP_NAME}"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceLog needs microphone access to record meetings for transcription.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoiceLog needs automation access to register global hotkeys.</string>
</dict>
</plist>
PLIST

# Create entitlements (for ad-hoc signing)
cat > "${CONTENTS_DIR}/entitlements.plist" << ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.audio.capture</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Ad-hoc code sign
codesign --force --deep --sign - \
    --entitlements "${CONTENTS_DIR}/entitlements.plist" \
    "$APP_DIR" 2>/dev/null || echo "Warning: Code signing skipped (run with valid identity for distribution)"

# Clean up entitlements file from bundle (not needed at runtime)
rm -f "${CONTENTS_DIR}/entitlements.plist"

echo ""
echo "Built: ${APP_DIR}"
echo ""
echo "To run:  open ${APP_DIR}"
echo "To install: cp -r ${APP_DIR} /Applications/"
