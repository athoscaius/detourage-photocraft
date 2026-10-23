#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h}"
APP_NAME='Détourage PhotoCraft.app'
LEGACY_APP_NAME='ArtCraft Détourage IA.app'
APP_ID='local.artcraft.detourage-ia'
DESTINATION="/Applications/$APP_NAME"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/companion-install.XXXXXX")"
SUCCESS=0
PREVIOUS_PATH=''
cleanup() {
 if [[ "$SUCCESS" != 1 && -d "$STAGING/previous.app" ]]; then
  rm -rf "$DESTINATION"
  mv "$STAGING/previous.app" "$PREVIOUS_PATH"
 fi
 rm -rf "$STAGING"
}
trap cleanup EXIT
ditto -x -k "$PACKAGE_DIR/Detourage-PhotoCraft-macOS-arm64.zip" "$STAGING"
SOURCE_APP="$STAGING/$APP_NAME"
codesign --verify --deep --strict "$SOURCE_APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" == "$APP_ID" ]]
if [[ -e "$DESTINATION" ]]; then PREVIOUS_PATH="$DESTINATION"
elif [[ -e "/Applications/$LEGACY_APP_NAME" ]]; then PREVIOUS_PATH="/Applications/$LEGACY_APP_NAME"; fi
if [[ -n "$PREVIOUS_PATH" ]]; then
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PREVIOUS_PATH/Contents/Info.plist")" == "$APP_ID" ]]
 BACKUPS="$HOME/Library/Application Support/ArtCraft Detourage IA/backups.noindex"
 mkdir -p "$BACKUPS";chmod 700 "$BACKUPS"
 ditto -c -k --keepParent --noextattr --norsrc "$PREVIOUS_PATH" "$BACKUPS/Detourage-PhotoCraft-$(date +%Y%m%d-%H%M%S)-$$.zip"
 '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -u "$PREVIOUS_PATH" || true
 mv "$PREVIOUS_PATH" "$STAGING/previous.app"
fi
ditto --noextattr --norsrc "$SOURCE_APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
SUCCESS=1
'/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -f "$DESTINATION"
print "Installé : $DESTINATION"
