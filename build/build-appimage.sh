#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Debian Sid – manual GTK bundling"

docker run --rm -v "$PROJECT_ROOT:/work" debian:sid /bin/bash -c '
set -ex

# Install base dependencies
apt-get update
apt-get install -y --no-install-recommends ca-certificates dpkg-dev
update-ca-certificates

apt-get install -y --no-install-recommends \
    meson ninja-build gcc g++ valac pkg-config wget gettext desktop-file-utils file \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev \
    libglib2.0-dev libcairo2-dev libpango1.0-dev libgdk-pixbuf-2.0-dev \
    libwayland-dev libx11-dev libxrandr-dev libxrender-dev libxi-dev \
    libgl1-mesa-dev libgles2-mesa-dev libvulkan-dev \
    flex bison gperf \
    gsettings-desktop-schemas adwaita-icon-theme

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Fix desktop file icon
sed -i "s/Icon=org.dstx.gui/Icon=dstx/" /work/AppDir/usr/share/applications/dstx-gui.desktop
desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Download linuxdeploy
wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-x86_64.AppImage
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted
export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

# First pass: deploy basic libraries
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# --- Manual GTK bundling ---
# Find GTK modules directory and copy it to AppDir
GTK_MODULES_DIR=$(find /usr/lib -type d -name "gtk-4.0" -print -quit 2>/dev/null)
if [ -n "$GTK_MODULES_DIR" ]; then
    echo "Found GTK modules at: $GTK_MODULES_DIR"
    mkdir -p /work/AppDir/usr/lib
    cp -r "$GTK_MODULES_DIR" /work/AppDir/usr/lib/
else
    echo "WARNING: Could not find GTK modules directory. Trying to use system GTK."
fi

# Copy GLib schemas and GSettings schema files
mkdir -p /work/AppDir/usr/share/glib-2.0/schemas
cp -r /usr/share/glib-2.0/schemas/* /work/AppDir/usr/share/glib-2.0/schemas/ 2>/dev/null || true

# Copy adwaita icon theme and other required icons
mkdir -p /work/AppDir/usr/share/icons
cp -r /usr/share/icons/Adwaita /work/AppDir/usr/share/icons/ 2>/dev/null || true
cp -r /usr/share/icons/hicolor /work/AppDir/usr/share/icons/ 2>/dev/null || true

# Force the use of our bundled GTK libraries
export LD_LIBRARY_PATH=/work/AppDir/usr/lib:$LD_LIBRARY_PATH

# Second pass: deploy any remaining libraries (should pick up the copied GTK)
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Create the AppImage
$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Move result
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
