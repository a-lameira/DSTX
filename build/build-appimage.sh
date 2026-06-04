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

cat /work/AppDir/usr/share/applications/dstx-gui.desktop
desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Download linuxdeploy (continuous) and GTK plugin (stable 2.0.0)
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/releases/download/2.0.0/linuxdeploy-plugin-gtk-x86_64.AppImage
chmod +x *.AppImage

ls -lh linuxdeploy*.AppImage

# Extract both AppImages
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted
./linuxdeploy-plugin-gtk-x86_64.AppImage --appimage-extract
mv squashfs-root plugin-extracted

export LINUXDEPLOY_PLUGIN_PATH=/work/plugin-extracted/usr/lib/linuxdeploy/plugins

/work/linuxdeploy-extracted/AppRun \
    --appdir /work/AppDir \
    --desktop-file /work/AppDir/usr/share/applications/dstx-gui.desktop \
    --icon-file /work/AppDir/usr/share/icons/hicolor/scalable/apps/dstx.svg \
    --plugin gtk \
    --output appimage \
    --verbose

mv DSTX_GUI-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
