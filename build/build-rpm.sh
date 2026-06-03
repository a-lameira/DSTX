#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"
OUTPUT_DIR="$PROJECT_ROOT/build/rpm"

echo "📦 Building RPM package for version $VERSION"

# Copy static binaries
mkdir -p "$GUI_SRC/src/bin"
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$GUI_SRC/src/bin/"

# Copy spec file and set version
cp "$SCRIPT_DIR/rpm/dstx.spec" "$GUI_SRC/dstx.spec"
sed -i "s/@VERSION@/$VERSION/g" "$GUI_SRC/dstx.spec"

# Build inside Fedora container
docker build -t dstx-fedora-builder -f "$SCRIPT_DIR/containers/fedora-rawhide.Dockerfile" .
docker run --rm -v "$GUI_SRC:/build" dstx-fedora-builder sh -c '
    cd /build
    rpmbuild -bb --define "_topdir $PWD/rpmbuild" dstx.spec
'

mkdir -p "$OUTPUT_DIR"
cp "$GUI_SRC/rpmbuild/RPMS/x86_64/"*.rpm "$OUTPUT_DIR/" 2>/dev/null || true
echo "✅ RPM packages built:"
ls -lh "$OUTPUT_DIR"
