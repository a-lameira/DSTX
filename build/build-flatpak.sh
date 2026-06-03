#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_BUNDLE="$PROJECT_ROOT/build/flatpak-bundle/dstx-gui.flatpak"
REPO_DIR="$PROJECT_ROOT/build/flatpak-repo"
BUILD_DIR="$PROJECT_ROOT/build/flatpak-build"
MANIFEST="$SCRIPT_DIR/flatpak/org.dstx.gui.yml"

echo "📦 Building Flatpak bundle for DSTX"

# Remove past builds
rm -rf "$REPO_DIR" "$BUILD_DIR"
mkdir -p "$(dirname "$OUTPUT_BUNDLE")"

# Build the Flatpak application
flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"

# Create a single-file bundle
flatpak build-bundle "$REPO_DIR" "$OUTPUT_BUNDLE" org.dstx.gui

echo "✅ Flatpak bundle created: $OUTPUT_BUNDLE"
