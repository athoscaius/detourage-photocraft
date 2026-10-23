#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h:h}"
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
ICON_SET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICON_SET"
xcrun swift -module-cache-path "$ICON_WORK/cache" "$PACKAGE_DIR/source/PackageIcon.swift" \
  "$PACKAGE_DIR/assets/manul-opaque.png" "$PACKAGE_DIR/assets/app-icon.png"
for LOGICAL_SIZE in 16 32 128 256 512; do
  sips -z "$LOGICAL_SIZE" "$LOGICAL_SIZE" "$PACKAGE_DIR/assets/app-icon.png" --out "$ICON_SET/icon_${LOGICAL_SIZE}x${LOGICAL_SIZE}.png" >/dev/null
  RETINA_SIZE=$((LOGICAL_SIZE * 2))
  sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$PACKAGE_DIR/assets/app-icon.png" --out "$ICON_SET/icon_${LOGICAL_SIZE}x${LOGICAL_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o "$PACKAGE_DIR/assets/AppIcon.icns"
print "Icône macOS créée : $PACKAGE_DIR/assets/AppIcon.icns"
