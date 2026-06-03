#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"
OUTPUT_DIR="$PROJECT_ROOT/build/tar"

echo "📦 Creating tarball dstx-$VERSION.tar.gz"

# Compile GUI dynamically (assumes dev libs are installed)
cd "$GUI_SRC"
meson setup builddir --prefix=/usr
ninja -C builddir

# Staging directory
STAGING="$OUTPUT_DIR/dstx-$VERSION"
rm -rf "$STAGING" "$OUTPUT_DIR/dstx-$VERSION.tar.gz"
mkdir -p "$STAGING"/{bin,share/dstx-gui}

# Copy binaries
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$STAGING/bin/"
cp "$GUI_SRC/builddir/dstx-gui" "$STAGING/bin/"

# Copy data files
cp -r "$GUI_SRC/data" "$STAGING/share/dstx-gui/"
cp "$GUI_SRC/data/themes.json" "$STAGING/share/dstx-gui/"

# Create launcher script
cat > "$STAGING/dstx-gui.sh" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/lib:$LD_LIBRARY_PATH"
exec "$HERE/bin/dstx-gui" "$@"
EOF
chmod +x "$STAGING/dstx-gui.sh"

# Pack tarball
cd "$OUTPUT_DIR"
tar czf "dstx-$VERSION.tar.gz" "dstx-$VERSION"
echo "✅ Tarball created: $OUTPUT_DIR/dstx-$VERSION.tar.gz"
