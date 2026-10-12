#!/bin/sh
# Copia el plugin al Kindle montado por USB (macOS), sin los archivos ocultos
# "._*" que macOS crea en discos FAT (Bookshelf intenta cargarlos como módulos).
# Uso: tools/instalar_kindle.sh [/Volumes/Kindle]
set -e
VOL=${1:-/Volumes/Kindle}
DEST="$VOL/koreader/plugins/bookorbit-scopes.koplugin"
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$VOL/koreader/plugins" ] || { echo "No encuentro $VOL/koreader/plugins"; exit 1; }
mkdir -p "$DEST"
for f in _meta.lua main.lua bscopes_*.lua README.md LICENSE CHANGELOG.md; do
    [ -f "$HERE/$f" ] && COPYFILE_DISABLE=1 cp -X "$HERE/$f" "$DEST/"
done
find "$DEST" "$VOL/koreader/plugins" -maxdepth 1 -name '._*' -type f -delete
sync
echo "Instalado en $DEST. Reinicia KOReader."
