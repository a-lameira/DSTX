#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Fedora 41"

docker run --rm -v "$PROJECT_ROOT:/work" fedora:41 /bin/bash -c '
set -ex

dnf install -y meson ninja-build gcc gcc-c++ vala pkg-config wget gettext desktop-file-utils file \
    gtk4-devel libadwaita-devel libgee-devel json-glib-devel librsvg2-devel \
    libxml2-devel glib2-devel cairo-devel pango-devel gdk-pixbuf2-devel \
    wayland-devel libX11-devel libXrandr-devel libXrender-devel libXi-devel \
    mesa-libGL-devel mesa-libEGL-devel vulkan-devel

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

sed -i "s/Icon=org.dstx.gui/Icon=dstx/" /work/AppDir/usr/share/applications/dstx-gui.desktop

desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
