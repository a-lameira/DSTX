#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using custom builder with old glibc + recent GTK4"

# Replace with your GitHub repository name (e.g., 'yourname/dstx')
REPO_NAME="${GITHUB_REPOSITORY:-local/dstx}"
BUILDER_IMAGE="ghcr.io/$REPO_NAME/appimage-builder:latest"

# If running locally (not in CI), build the image on the fly
if [ -z "$GITHUB_ACTIONS" ]; then
    echo "Local build: building builder image..."
    docker build -t "$BUILDER_IMAGE" -f "$SCRIPT_DIR/containers/appimage-builder.Dockerfile" "$PROJECT_ROOT"
fi

docker run --rm -v "$PROJECT_ROOT:/work" "$BUILDER_IMAGE" /bin/bash -c '
set -ex

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Fix desktop file icon name
sed -i "s/Icon=org.dstx.gui/Icon=dstx/" /work/AppDir/usr/share/applications/dstx-gui.desktop

desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Download linuxdeploy and GTK plugin script
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget --no-verbose https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

# Extract linuxdeploy (avoid FUSE)
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

# First pass: basic libraries
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Second pass: GTK plugin (will pick up our custom GTK4 and libadwaita)
./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

# Third pass: create AppImage
$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Move result
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
