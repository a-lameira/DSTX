#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Ubuntu rolling"

docker run --rm -v "$PROJECT_ROOT:/work" ubuntu:rolling bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y meson ninja-build valac pkg-config wget gettext \
        desktop-file-utils \
        libgtk-4-dev libadwaita-1-dev libgee-0.8-dev \
        libjson-glib-dev librsvg2-dev

    cd /work/dstx-gui
    meson setup builddir --prefix=/usr
    ninja -C builddir

    DESTDIR=/work/AppDir ninja -C builddir install

    # Validate desktop file
    echo "Validating desktop file..."
    desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

    # Download linuxdeploy and GTK plugin
    wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    wget -q https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/releases/download/continuous/linuxdeploy-plugin-gtk-x86_64.AppImage
    chmod +x linuxdeploy*.AppImage

    # Extract linuxdeploy (FUSE doesn't work in Docker)
    ./linuxdeploy-x86_64.AppImage --appimage-extract
    mv squashfs-root linuxdeploy-extracted
    # Extract the plugin similarly
    ./linuxdeploy-plugin-gtk-x86_64.AppImage --appimage-extract
    mv squashfs-root plugin-extracted

    # Run linuxdeploy using the extracted AppRun
    export LINUXDEPLOY_PLUGIN_PATH=/work/plugin-extracted/usr/lib/linuxdeploy/plugins/
    ./linuxdeploy-extracted/AppRun --appdir /work/AppDir --plugin gtk --output appimage --verbose

    # Move result
    mv DSTX_GUI-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
