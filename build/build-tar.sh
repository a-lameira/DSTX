#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
OUTPUT_DIR="$PROJECT_ROOT/build/tar"

echo "📦 Creating tarball dstx-core-$VERSION.tar.gz"

STAGING="$OUTPUT_DIR/dstx-core-$VERSION"
mkdir -p "$STAGING/bin"
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$STAGING/bin/"

# Optionally include system files (udev, systemd, dbus) for convenience
mkdir -p "$STAGING/system"
cp "$PROJECT_ROOT/dstx/data/"*.service "$STAGING/system/" 2>/dev/null || true
cp "$PROJECT_ROOT/dstx/data/"*.rules "$STAGING/system/" 2>/dev/null || true
cp "$PROJECT_ROOT/dstx/data/"*.conf "$STAGING/system/" 2>/dev/null || true

cd "$OUTPUT_DIR"
tar czf "dstx-core-$VERSION.tar.gz" "dstx-core-$VERSION"
rm -rf "$STAGING"
echo "✅ Tarball created: $OUTPUT_DIR/dstx-core-$VERSION.tar.gz"
