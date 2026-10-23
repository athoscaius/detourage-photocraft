#!/bin/zsh
set -euo pipefail
DMG_STAGE="$(mktemp -d /private/tmp/artcraft-dmg.XXXXXX)"
trap 'rm -rf "$DMG_STAGE"' EXIT
ditto --noextattr --norsrc "${1:?Chemin de l’application .app requis}" "$DMG_STAGE/ArtCraft Détourage IA.app"
ln -s /Applications "$DMG_STAGE/Applications"
cat > "$DMG_STAGE/Installation.txt" <<'TXT'
ArtCraft Détourage IA 1.3.1 — Mac Apple Silicon, macOS 14 ou ultérieur

1. Glissez ArtCraft Détourage IA sur Applications.
2. Ouvrez l’application depuis Applications, puis cliquez sur Ouvrir PhotoCraft.
3. Si PhotoCraft était déjà ouvert, enregistrez votre travail puis quittez-le et rouvrez-le une fois.

L’application configure sa connexion locale au premier lancement. Le traitement reste sur le Mac.
Python 3 des outils Apple est nécessaire au pont PhotoCraft ; le modèle IA et son propre runtime sont inclus.

Cette version utilise une signature locale ad hoc. Elle n’est pas signée Developer ID ni notariée par Apple : sur un autre Mac, Gatekeeper peut demander une autorisation dans Réglages Système > Confidentialité et sécurité.
Projet indépendant de la suite ArtCraft.
TXT
codesign --verify --deep --strict "$DMG_STAGE/ArtCraft Détourage IA.app"
hdiutil create -volname 'ArtCraft Détourage IA' -srcfolder "$DMG_STAGE" -format UDZO -ov ArtCraft-Detourage-IA-1.3.1-arm64.dmg
hdiutil verify ArtCraft-Detourage-IA-1.3.1-arm64.dmg
