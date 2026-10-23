#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
AI_DIR="${1:?Dossier de destination requis}"
INSTALLED='/Applications/ArtCraft Détourage IA.app/Contents/Resources/ai'
mkdir -p "$AI_DIR/models"
# Reuse a complete signed local installation, otherwise fetch pinned official assets.
if [[ -f "$INSTALLED/matting-model.json" ]] && cmp -s "$SOURCE_DIR/matting-model.json" "$INSTALLED/matting-model.json" && codesign --verify --deep --strict '/Applications/ArtCraft Détourage IA.app' 2>/dev/null; then
  ditto --noextattr --norsrc "$INSTALLED" "$AI_DIR"
else
  FETCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-ai-fetch.XXXXXX")"
  trap 'rm -rf "$FETCH_DIR"' EXIT
  curl --fail --location --retry 2 'https://github.com/astral-sh/python-build-standalone/releases/download/20261021/cpython-3.13.17%2B20261021-aarch64-apple-darwin-install_only_stripped.tar.gz' -o "$FETCH_DIR/python.tar.gz"
  print "8dc60610a82f1e73be7faf964383e02520f95f6e39592a5c37c3809f5a7b798e  $FETCH_DIR/python.tar.gz" | shasum -a 256 -c -
  tar -xzf "$FETCH_DIR/python.tar.gz" -C "$AI_DIR"
  "$AI_DIR/python/bin/python3" -I -B -m pip install --disable-pip-version-check --no-compile --only-binary=:all: --require-hashes -r "$SOURCE_DIR/requirements-matting.lock"
  curl --fail --location --retry 2 'https://github.com/ZhengPeng7/BiRefNet/releases/download/v1/BiRefNet-matting-epoch_100.onnx' -o "$AI_DIR/models/BiRefNet-matting-epoch_100.onnx"
fi
print "6065d27c615ea27308f5b88598dd8db116eb07436c7a323ca40d13b2866c309e  $AI_DIR/models/BiRefNet-matting-epoch_100.onnx" | shasum -a 256 -c -
cp "$SOURCE_DIR/high_resolution_matting.py" "$AI_DIR/"
cp "$SOURCE_DIR/matting-model.json" "$AI_DIR/"
cp "$SOURCE_DIR/requirements-matting.lock" "$AI_DIR/"
cp "$SOURCE_DIR/BiRefNet-LICENSE.txt" "$AI_DIR/"
ditto --noextattr --norsrc "$SOURCE_DIR/runtime-licenses" "$AI_DIR/runtime-licenses"
