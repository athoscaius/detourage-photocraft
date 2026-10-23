#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h}"
APP_NAME='ArtCraft Détourage IA.app'
APP_ID='local.artcraft.detourage-ia'
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-detourage-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP_DIR="$BUILD_DIR/$APP_NAME"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin" "$APP_DIR/Contents/Resources/source"
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD_DIR/cache-engine" \
  "$PACKAGE_DIR/source/MattingEngine.swift" -o "$APP_DIR/Contents/Resources/bin/matting-engine"
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path "$BUILD_DIR/cache-ui" \
  "$PACKAGE_DIR/source/Companion.swift" -o "$APP_DIR/Contents/MacOS/ArtCraftDetourageIA"
cp "$PACKAGE_DIR/source/configure_connection.py" "$APP_DIR/Contents/Resources/source/"
cp "$PACKAGE_DIR/source/photocraft_bridge.py" "$APP_DIR/Contents/Resources/source/photocraft_bridge.py"
zsh "$PACKAGE_DIR/source/prepare_icon.command"
zsh "$PACKAGE_DIR/source/prepare_ai.command" "$APP_DIR/Contents/Resources/ai"
/usr/bin/python3 "$PACKAGE_DIR/source/sign_runtime.py" "$APP_DIR/Contents/Resources/ai/python"
cp "$PACKAGE_DIR/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon-v4.icns"
cp "$PACKAGE_DIR/assets/app-icon.png" "$APP_DIR/Contents/Resources/AppIcon-v3.png"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.artcraft.detourage-ia</string>
<key>CFBundleName</key><string>ArtCraft Détourage IA</string>
<key>CFBundleDisplayName</key><string>ArtCraft Détourage IA</string>
<key>CFBundleExecutable</key><string>ArtCraftDetourageIA</string>
<key>CFBundleIconFile</key><string>AppIcon-v4.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Extension personnelle de détourage pour PhotoCraft. Moteur local BiRefNet-matting (MIT), repérage Vision fourni par macOS.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR/Contents/Resources/bin/matting-engine"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --keepParent --noextattr --norsrc "$APP_DIR" "$PACKAGE_DIR/ArtCraft-Detourage-IA-macOS-arm64.zip"
print "Archive construite : $PACKAGE_DIR/ArtCraft-Detourage-IA-macOS-arm64.zip"
