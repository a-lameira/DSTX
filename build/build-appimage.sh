#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Ubuntu rolling"

docker run --rm -v "$PROJECT_ROOT:/work" ubuntu:rolling /bin/bash -c '
set -ex

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y meson ninja-build valac pkg-config wget gettext desktop-file-utils \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Validate desktop file
cat /work/AppDir/usr/share/applications/dstx-gui.desktop
desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Download linuxdeploy and GTK plugin script
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget --no-verbose https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh

chmod +x linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-plugin-gtk.sh

# Extract linuxdeploy (to avoid FUSE)
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

# Run linuxdeploy with GTK plugin (no --verbose, use --verbosity=1 for info)
./linuxdeploy-extracted/AppRun \
    --appdir /work/AppDir \
    --plugin /work/linuxdeploy-plugin-gtk.sh \
    --output appimage \
    --verbosity=1

# Move generated AppImage
mv DSTX_GUI-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
