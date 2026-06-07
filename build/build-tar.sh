#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
CORE_SRC="$PROJECT_ROOT/dstx"
OUTPUT_DIR="$PROJECT_ROOT/build/tar"

echo "📦 Creating tarball dstx-core-$VERSION.tar.gz"

# Create a temporary staging directory
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

# Copy static binaries to staging root
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$STAGING_DIR/"

# Copy the setup script
if [ -f "$CORE_SRC/setup-dstx.sh" ]; then
    cp "$CORE_SRC/setup-dstx.sh" "$STAGING_DIR/"
else
    echo "ERROR: setup-dstx.sh not found in $CORE_SRC/ or $CORE_SRC/data/"
    exit 1
fi
chmod +x "$STAGING_DIR/setup-dstx.sh"

# Copy LICENSE and README.md from project root
if [ -f "$PROJECT_ROOT/LICENSE" ]; then
    cp "$PROJECT_ROOT/LICENSE" "$STAGING_DIR/"
else
    echo "WARNING: LICENSE not found in project root"
fi

if [ -f "$PROJECT_ROOT/README.md" ]; then
    cp "$PROJECT_ROOT/README.md" "$STAGING_DIR/"
else
    echo "WARNING: README.md not found in project root"
fi

# Create the tarball
mkdir -p "$OUTPUT_DIR"
cd "$STAGING_DIR"
tar czf "$OUTPUT_DIR/dstx-core-$VERSION.tar.gz" *

echo "✅ Tarball created: $OUTPUT_DIR/dstx-core-$VERSION.tar.gz"
echo "Contents:"
tar tzf "$OUTPUT_DIR/dstx-core-$VERSION.tar.gz"
