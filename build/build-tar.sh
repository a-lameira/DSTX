#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"
OUTPUT_DIR="$PROJECT_ROOT/build/tar"

echo "📦 Creating tarball dstx-$VERSION.tar.gz"

# Verifica se os binários estáticos existem
if [ ! -f "$CORE_BIN/dstx" ] || [ ! -f "$CORE_BIN/dstx-dbus" ]; then
    echo "❌ Static binaries not found. Run build-core-static.sh first."
    exit 1
fi

# Compila a GUI dinamicamente (assumindo que as libs estão no sistema)
cd "$GUI_SRC"
if [ ! -d "builddir" ]; then
    meson setup builddir --prefix=/usr
fi
ninja -C builddir

# Cria diretório de staging
STAGING="$OUTPUT_DIR/dstx-$VERSION"
rm -rf "$STAGING" "$OUTPUT_DIR/dstx-$VERSION.tar.gz"
mkdir -p "$STAGING"/{bin,share/dstx-gui}

# Copia binários estáticos e GUI
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$STAGING/bin/"
cp "$GUI_SRC/builddir/dstx-gui" "$STAGING/bin/"

# Copia dados (ícones, temas, desktop)
cp -r "$GUI_SRC/data" "$STAGING/share/dstx-gui/"
cp "$GUI_SRC/data/themes.json" "$STAGING/share/dstx-gui/"

# Cria script de execução (opcional)
cat > "$STAGING/dstx-gui.sh" << EOF
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\$0")")"
export PATH="\$HERE/bin:\$PATH"
export LD_LIBRARY_PATH="\$HERE/lib:\$LD_LIBRARY_PATH"
exec "\$HERE/bin/dstx-gui" "\$@"
EOF
chmod +x "$STAGING/dstx-gui.sh"

# Empacota
cd "$OUTPUT_DIR"
tar czf "dstx-$VERSION.tar.gz" "dstx-$VERSION"

echo "✅ Tarball: $OUTPUT_DIR/dstx-$VERSION.tar.gz"
