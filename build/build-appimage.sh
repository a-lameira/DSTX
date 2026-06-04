#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Fedora 40 (glibc 2.38, GTK4 4.20+, libadwaita 1.8+)"

docker run --rm -v "$PROJECT_ROOT:/work" fedora:40 /bin/bash -c '
set -ex

# Install build dependencies and required libraries
dnf install -y meson ninja-build gcc gcc-c++ vala pkg-config wget gettext desktop-file-utils file \
    libgtk4-devel libadwaita-devel libgee-devel json-glib-devel librsvg2-devel \
    libxml2-devel glib2-devel cairo-devel pango-devel gdk-pixbuf2-devel \
    wayland-devel libX11-devel libXrandr-devel libXrender-devel libXi-devel \
    mesa-libGL-devel mesa-libEGL-devel vulkan-devel

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

# Extract linuxdeploy
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Run GTK plugin (it will pick up the system’s GTK4 and libadwaita)
./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Move generated AppImage
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
