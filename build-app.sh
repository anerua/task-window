#!/bin/bash

set -e

APP_NAME="Task Window"
BUNDLE_ID="com.anerua.task-window"
BINARY_NAME="task-window"
VERSION="1.0"
MIN_MACOS="13.0"

echo "🔨 Building $APP_NAME..."
swift build -c release

BINARY_PATH=".build/release/$BINARY_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Build failed: binary not found at $BINARY_PATH"
    exit 1
fi

APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$BINARY_NAME"

cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "✅ Done! App bundle created: $APP_BUNDLE"
echo ""
echo "To open it, run:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "⚠️  First launch: if macOS blocks it, right-click → Open → Open"