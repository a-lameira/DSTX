#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
CORE_SRC="$PROJECT_ROOT/dstx"
OUTPUT_DIR="$PROJECT_ROOT/build/deb"

echo "📦 Building Debian package (core only) for version $VERSION"

TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/DEBIAN"
mkdir -p "$TEMP_DIR/usr/local/bin"
mkdir -p "$TEMP_DIR/lib/systemd/system"
mkdir -p "$TEMP_DIR/lib/udev/rules.d"
mkdir -p "$TEMP_DIR/etc/dbus-1/system.d"
mkdir -p "$TEMP_DIR/etc/polkit-1/rules.d"
mkdir -p "$TEMP_DIR/etc/sudoers.d"

# Copy static binaries to /usr/local/bin
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$TEMP_DIR/usr/local/bin/"

# Copy system files from dstx/data/
cp "$CORE_SRC/data/dstx-daemon.service" "$TEMP_DIR/lib/systemd/system/"
cp "$CORE_SRC/data/dstx-dbus.service" "$TEMP_DIR/lib/systemd/system/"
cp "$CORE_SRC/data/99-dstx.rules" "$TEMP_DIR/lib/udev/rules.d/"
cp "$CORE_SRC/data/org.dstx.Bridge.conf" "$TEMP_DIR/etc/dbus-1/system.d/"
cp "$CORE_SRC/data/10-dstx.rules" "$TEMP_DIR/etc/polkit-1/rules.d/"
cp "$CORE_SRC/data/dstx-sudoers" "$TEMP_DIR/etc/sudoers.d/dstx"
chmod 440 "$TEMP_DIR/etc/sudoers.d/dstx"

# control file
cat > "$TEMP_DIR/DEBIAN/control" << EOF
Package: dstx-core
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: André Lameira <alameira@dstx.org>
Depends: systemd, udev, dbus, polkitd
Description: DSTX Core (daemon and D-Bus bridge)
 Advanced controller driver for PlayStation DualSense, DS4 and Nintendo Switch Pro.
 This package contains only the core daemon and D-Bus bridge, not the graphical interface.
EOF

# postinst script (enable services, reload udev)
cat > "$TEMP_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable dstx-daemon.service dstx-dbus.service || true
    systemctl start dstx-daemon.service dstx-dbus.service || true
fi

if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
fi

exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/postinst"

# prerm script (stop services before removal)
cat > "$TEMP_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop dstx-daemon.service dstx-dbus.service || true
    systemctl disable dstx-daemon.service dstx-dbus.service || true
fi

exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/prerm"

mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$TEMP_DIR" "$OUTPUT_DIR/dstx-core_${VERSION}_amd64.deb"
rm -rf "$TEMP_DIR"

echo "✅ Debian package built: $OUTPUT_DIR/dstx-core_${VERSION}_amd64.deb"
