#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
OUTPUT_DIR="$PROJECT_ROOT/build/deb"

echo "📦 Building Debian package (core only) for version $VERSION"

# Create a temporary directory with the core binaries and system files
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/DEBIAN"
mkdir -p "$TEMP_DIR/usr/bin"
mkdir -p "$TEMP_DIR/lib/systemd/system"
mkdir -p "$TEMP_DIR/lib/udev/rules.d"
mkdir -p "$TEMP_DIR/etc/dbus-1/system.d"

# Copy static binaries
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$TEMP_DIR/usr/bin/"

# Copy system files (adjust paths to your actual files)
cp "$PROJECT_ROOT/dstx/data/dstx.service" "$TEMP_DIR/lib/systemd/system/"
cp "$PROJECT_ROOT/dstx/data/dstx-dbus.service" "$TEMP_DIR/lib/systemd/system/"
cp "$PROJECT_ROOT/dstx/data/99-dstx.rules" "$TEMP_DIR/lib/udev/rules.d/"
cp "$PROJECT_ROOT/dstx/data/org.dstx.Bridge.conf" "$TEMP_DIR/etc/dbus-1/system.d/"

# Create control file
cat > "$TEMP_DIR/DEBIAN/control" << EOF
Package: dstx-core
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: André Lameira <alameira@dstx.org>
Depends: systemd, udev, dbus
Description: DSTX Core (daemon and D-Bus bridge)
 Advanced controller driver for PlayStation DualSense, DS4 and Nintendo Switch Pro.
 This package contains only the core daemon and D-Bus bridge, not the graphical interface.
EOF

# Create postinst script (optional, to enable services)
cat > "$TEMP_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e
systemctl enable dstx-daemon.service
systemctl enable dstx-dbus.service
systemctl start dstx-daemon.service
systemctl start dstx-dbus.service
udevadm control --reload-rules
exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/postinst"

# Create prerm script (optional)
cat > "$TEMP_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e
systemctl stop dstx-daemon.service || true
systemctl stop dstx-dbus.service || true
exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/prerm"

# Build the .deb
mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$TEMP_DIR" "$OUTPUT_DIR/dstx-core_${VERSION}_amd64.deb"
rm -rf "$TEMP_DIR"

echo "✅ Debian package built: $OUTPUT_DIR/dstx-core_${VERSION}_amd64.deb"
