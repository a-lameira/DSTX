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
        libgtk-4-dev libadwaita-1-dev libgee-0.8-dev \
        libjson-glib-dev librsvg2-dev

    cd /work/dstx-gui
    meson setup builddir --prefix=/usr
    ninja -C builddir

    # Install into AppDir
    DESTDIR=/work/AppDir ninja -C builddir install

    # Download linuxdeploy and GTK plugin
    wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
    wget -q https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/releases/download/continuous/linuxdeploy-plugin-gtk-x86_64.AppImage
    chmod +x linuxdeploy*.AppImage

    # Run linuxdeploy – it will automatically find the .desktop file and icon inside AppDir
    ./linuxdeploy-x86_64.AppImage --appdir /work/AppDir --plugin gtk --output appimage

    # Move result
    mv DSTX_GUI-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
