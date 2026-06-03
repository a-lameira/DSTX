#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_VERSION=$(cat "$PROJECT_ROOT/VERSION")
VERSION="${RAW_VERSION//-/.}"
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"
OUTPUT_DIR="$PROJECT_ROOT/build/rpm"

echo "📦 Building RPM package for version $VERSION (original: $RAW_VERSION)"

# Copy static binaries into GUI source tree
mkdir -p "$GUI_SRC/src/bin"
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$GUI_SRC/src/bin/"

# Create a source tarball for RPM
TARBALL_NAME="dstx-$VERSION.tar.gz"
TEMP_DIR=$(mktemp -d)
cp -r "$GUI_SRC" "$TEMP_DIR/dstx-$VERSION"
tar -czf "$TEMP_DIR/$TARBALL_NAME" -C "$TEMP_DIR" "dstx-$VERSION"

# Prepare RPM build directory structure
RPM_TOPDIR="$GUI_SRC/rpmbuild"
mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp "$TEMP_DIR/$TARBALL_NAME" "$RPM_TOPDIR/SOURCES/"

# Copy spec file and set version
cp "$SCRIPT_DIR/rpm/dstx.spec" "$RPM_TOPDIR/SPECS/"
sed -i "s/@VERSION@/$VERSION/g" "$RPM_TOPDIR/SPECS/dstx.spec"

# Build inside Fedora container
docker build -t dstx-fedora-builder -f "$SCRIPT_DIR/containers/fedora-rawhide.Dockerfile" .
docker run --rm -v "$RPM_TOPDIR:/build/rpmbuild" dstx-fedora-builder sh -c '
    cd /build/rpmbuild
    rpmbuild -bb --define "_topdir $PWD" SPECS/dstx.spec
'

mkdir -p "$OUTPUT_DIR"
cp "$RPM_TOPDIR/RPMS/x86_64/"*.rpm "$OUTPUT_DIR/" 2>/dev/null || true
echo "✅ RPM packages built:"
ls -lh "$OUTPUT_DIR"

# Cleanup
rm -rf "$TEMP_DIR"
