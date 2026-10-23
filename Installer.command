#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h}"
APP_NAME='ArtCraft Détourage IA.app'
APP_ID='local.artcraft.detourage-ia'
ARCHIVE="$PACKAGE_DIR/ArtCraft-Detourage-IA-macOS-arm64.zip"
DESTINATION="/Applications/$APP_NAME"
[[ -f "$ARCHIVE" ]] || { print -u2 'Archive absente. Lancez build.command.'; exit 1; }
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-detourage-install.XXXXXX")"
INSTALL_SUCCESS=0
PREVIOUS_APP="$STAGING_DIR/previous.app"
cleanup() {
  if [[ "$INSTALL_SUCCESS" != 1 && -d "$PREVIOUS_APP" ]]; then
    rm -rf "$DESTINATION"
    mv "$PREVIOUS_APP" "$DESTINATION"
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
ditto -x -k "$ARCHIVE" "$STAGING_DIR"
codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME"
SOURCE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$STAGING_DIR/$APP_NAME/Contents/Info.plist")"
[[ "$SOURCE_ID" == "$APP_ID" ]] || { print -u2 'Archive incompatible.'; exit 1; }
if [[ -e "$DESTINATION" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$EXISTING_ID" == "$APP_ID" ]] || { print -u2 'Le chemin est occupé par une autre application.'; exit 1; }
  BACKUP_DIR="$HOME/Library/Application Support/ArtCraft Detourage IA/backups.noindex"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  BACKUP_FILE="$BACKUP_DIR/ArtCraft-Detourage-IA-$(date +%Y%m%d-%H%M%S)-$$.zip"
  ditto -c -k --keepParent --noextattr --norsrc "$DESTINATION" "$BACKUP_FILE"
  mv "$DESTINATION" "$PREVIOUS_APP"
  print "Version précédente conservée : $BACKUP_FILE"
fi
ditto --noextattr --norsrc "$STAGING_DIR/$APP_NAME" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
/usr/bin/python3 "$DESTINATION/Contents/Resources/source/configure_connection.py"
INSTALL_SUCCESS=1
'/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -f "$DESTINATION"
print "Installé : $DESTINATION"
