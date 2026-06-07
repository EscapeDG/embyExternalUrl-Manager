#!/bin/bash
# build_app.sh
# 构建 embyExternalUrl-Manager Swift Package 为 macOS .app 包

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="embyExternalUrl-Manager"
BUNDLE_ID="com.embyexternalurl.manager"
VERSION="1.0.2"
BUILD_NUMBER="102"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

ICON_FILE="${PROJECT_DIR}/Sources/EmbyExternalUrlManager/Resources/AppIcon.icns"
CORE_MANIFEST="${PROJECT_DIR}/RustCore/Cargo.toml"
CORE_BIN="${PROJECT_DIR}/RustCore/target/release/plex2alist-core"

echo "🧹 Cleaning previous build..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "🔨 Building Swift Package for release..."
swift build -c release --disable-sandbox

if [ -f "$CORE_MANIFEST" ]; then
    if ! command -v cargo >/dev/null 2>&1; then
        echo "❌ Error: cargo not found. Rust core is required for the 1.0 release build."
        exit 1
    fi
    echo "🦀 Building Rust core for release..."
    cargo build --release --manifest-path "$CORE_MANIFEST"
else
    echo "❌ Error: Rust core manifest not found at $CORE_MANIFEST"
    exit 1
fi

BIN_PATH=$(swift build -c release --disable-sandbox --show-bin-path)/EmbyExternalUrlManager

if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Error: Executable not found at $BIN_PATH"
    exit 1
fi

echo "📦 Copying executable to app bundle..."
cp "$BIN_PATH" "${MACOS_DIR}/EmbyExternalUrlManager"
chmod 755 "${MACOS_DIR}/EmbyExternalUrlManager"

if [ ! -f "$CORE_BIN" ]; then
    echo "❌ Error: Rust core executable not found at $CORE_BIN"
    exit 1
fi

echo "📦 Copying Rust core to app bundle..."
install -m 755 "$CORE_BIN" "${MACOS_DIR}/plex2alist-core"

echo "📦 Copying resource bundle..."
BUNDLE_SRC="${PROJECT_DIR}/.build/release/embyExternalUrl-Manager_EmbyExternalUrlManager.bundle"
if [ -d "$BUNDLE_SRC" ]; then
    cp -R "$BUNDLE_SRC" "${RESOURCES_DIR}/embyExternalUrl-Manager_EmbyExternalUrlManager.bundle"
    echo "  ✅ Resource bundle copied"
else
    echo "  ⚠️  Resource bundle not found at $BUNDLE_SRC"
fi

if [ -f "$ICON_FILE" ]; then
    echo "🎨 Copying app icon..."
    install -m 644 "$ICON_FILE" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "⚠️  App icon not found; bundle will use the default icon."
fi

echo "📝 Generating Info.plist..."
cat <<EOF > "${APP_DIR}/Contents/Info.plist"
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
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>EmbyExternalUrlManager</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf "APPL????" > "${APP_DIR}/Contents/PkgInfo"

echo "🔎 Validating Info.plist..."
plutil -lint "${APP_DIR}/Contents/Info.plist"

echo "🧽 Clearing extended attributes..."
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "🔏 Applying ad-hoc signature..."
codesign --force --deep --sign - --timestamp=none "$APP_DIR"

echo "✅ Build complete! App bundle created at ${APP_DIR}"
echo "   Size: $(du -sh "$APP_DIR" | cut -f1)"
