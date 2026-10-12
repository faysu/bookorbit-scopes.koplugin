#!/bin/sh
# Crea dist/bookorbit-scopes.koplugin.zip con solo lo que necesita el lector
# (sin tests, herramientas ni archivos ocultos de macOS).
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
mkdir -p "$TMP/bookorbit-scopes.koplugin" "$HERE/dist"
for f in _meta.lua main.lua bscopes_*.lua README.md LICENSE; do
    [ -f "$HERE/$f" ] && COPYFILE_DISABLE=1 cp -X "$HERE/$f" "$TMP/bookorbit-scopes.koplugin/"
done
rm -f "$HERE/dist/bookorbit-scopes.koplugin.zip"
(cd "$TMP" && COPYFILE_DISABLE=1 zip -qrX "$HERE/dist/bookorbit-scopes.koplugin.zip" bookorbit-scopes.koplugin -x '*/._*' '*/.DS_Store')
rm -rf "$TMP"
unzip -l "$HERE/dist/bookorbit-scopes.koplugin.zip"
