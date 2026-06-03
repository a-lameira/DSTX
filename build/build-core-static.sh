#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_SRC="$PROJECT_ROOT/DSTX"
OUTPUT_DIR="$PROJECT_ROOT/build/core-static"

echo "🔨 Building static core (dstx, dstx-dbus) using Alpine..."

docker build -t dstx-alpine-static -f "$SCRIPT_DIR/containers/alpine-static.Dockerfile" .

docker run --rm -v "$CORE_SRC:/work" dstx-alpine-static sh -c '
    set -e
    # Compiles static dbus
    cd /tmp
    git clone --depth 1 https://gitlab.freedesktop.org/dbus/dbus.git
    cd dbus
    mkdir build && cd build
    meson setup .. \
        --prefix=/usr/local/dbus-static \
        --localstatedir=/var \
        --buildtype=release \
        --default-library=static \
        -Dmessage_bus=false \
        -Dtools=false \
        -Dsystemd=auto \
        -Dselinux=auto \
        -Dapparmor=auto
    ninja
    ninja install

    # Compiles static dstx and dstx-dbus
    cd /work
    make static-all DBUS_STATIC_DIR=/usr/local/dbus-static
'

mkdir -p "$OUTPUT_DIR"
cp "$CORE_SRC/dstx" "$CORE_SRC/dstx-dbus" "$OUTPUT_DIR/"
echo "✅ Static core binaries ready:"
ls -lh "$OUTPUT_DIR"
