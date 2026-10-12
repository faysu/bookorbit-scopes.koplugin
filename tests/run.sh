#!/bin/sh
# Ejecuta los tests en el Mac con LuaJIT (brew install luajit).
# Descarga una vez Bookshelf, en el commit probado, para validar la fuente
# contra su registro real (lib/bookshelf_sources.lua).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
BOOKSHELF_COMMIT=2c8bfd8
CACHE="$HERE/.cache/bookshelf"
if [ ! -f "$CACHE/lib/bookshelf_sources.lua" ]; then
    mkdir -p "$HERE/.cache"
    git clone -q https://github.com/AndyHazz/bookshelf.koplugin.git "$CACHE"
    git -C "$CACHE" checkout -q "$BOOKSHELF_COMMIT"
fi
cd "$HERE/.."
BOOKSHELF_DIR="$CACHE" luajit tests/run.lua "$@"
