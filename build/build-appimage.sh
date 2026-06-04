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
apt-get install -y meson ninja-build valac pkg-config wget gettext desktop-file-utils file \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Fix desktop file icon name
sed -i "s/Icon=org.dstx.gui/Icon=dstx/" /work/AppDir/usr/share/applications/dstx-gui.desktop

cat /work/AppDir/usr/share/applications/dstx-gui.desktop
desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Download linuxdeploy and the GTK plugin script
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget --no-verbose https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-plugin-gtk.sh

# Extract linuxdeploy (avoid FUSE)
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

# Set environment variable for linuxdeploy
export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

# First pass: deploy basic libraries (no AppImage output yet)
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Second pass: deploy GTK4 libraries using the plugin
./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

# Third pass: finally create the AppImage
$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Move the generated AppImage (name is DSTX-x86_64.AppImage) to dstx-gui.AppImage
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
