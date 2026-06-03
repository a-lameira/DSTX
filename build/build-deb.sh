#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"          # Vala GUI source
OUTPUT_DIR="$PROJECT_ROOT/build/deb"

echo "📦 Building Debian package for version $VERSION"

# 1. Copy static binaries into the GUI source tree (expected by debian/rules)
mkdir -p "$GUI_SRC/src/bin"
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$GUI_SRC/src/bin/"

# 2. Prepare debian/ directory inside the GUI source
cp -r "$SCRIPT_DIR/debian" "$GUI_SRC/"
# Generate changelog with version and current date
DATE=$(date -R)
sed -e "s/@VERSION@/$VERSION/g" -e "s/@DATE@/$DATE/g" \
    "$SCRIPT_DIR/debian/changelog.in" > "$GUI_SRC/debian/changelog"
chmod +x "$GUI_SRC/debian/rules"

# 3. Build the Debian package inside a container (reproducible)
docker build -t dstx-debian-builder -f "$SCRIPT_DIR/containers/debian-bookworm.Dockerfile" .

docker run --rm -v "$GUI_SRC:/build" dstx-debian-builder sh -c '
    cd /build
    dpkg-buildpackage -us -uc -b
'

# 4. Move resulting .deb files to the output directory
mkdir -p "$OUTPUT_DIR"
mv "$GUI_SRC"/../*.deb "$OUTPUT_DIR/" 2>/dev/null || true

echo "✅ Debian packages built:"
ls -lh "$OUTPUT_DIR"
