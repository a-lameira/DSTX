#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using GNOME 49 SDK from Quay.io"

docker run --rm -v "$PROJECT_ROOT:/work" quay.io/gnome_infrastructure/gnome-runtime-images:x86_64-gnome-49 /bin/bash -c '
set -ex

# Install additional tools needed for linuxdeploy and desktop file validation
apt-get update
apt-get install -y wget desktop-file-utils file gettext

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
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

# Extract linuxdeploy (avoid FUSE)
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

# Deploy basic libraries
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Deploy GTK libraries using the plugin
./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

# Create AppImage
$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Move generated AppImage
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
