#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
CORE_SRC="$PROJECT_ROOT/dstx"
OUTPUT_DIR="$PROJECT_ROOT/build/deb"

echo "📦 Building Debian package (core only) for version $VERSION"

# Create temporary package directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/DEBIAN"
mkdir -p "$TEMP_DIR/usr/local/bin"
mkdir -p "$TEMP_DIR/lib/systemd/system"
mkdir -p "$TEMP_DIR/lib/udev/rules.d"
mkdir -p "$TEMP_DIR/usr/share/polkit-1/rules.d"
mkdir -p "$TEMP_DIR/etc/sudoers.d"
mkdir -p "$TEMP_DIR/usr/share/dbus-1/system.d"

# Copy static binaries to /usr/local/bin
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$TEMP_DIR/usr/local/bin/"
chmod 755 "$TEMP_DIR/usr/local/bin/"*

# Copy systemd service files
cp "$CORE_SRC/data/dstx-daemon.service" "$TEMP_DIR/lib/systemd/system/"
cp "$CORE_SRC/data/dstx-dbus.service"   "$TEMP_DIR/lib/systemd/system/"

# Copy udev rules
cp "$CORE_SRC/data/99-dstx.rules" "$TEMP_DIR/lib/udev/rules.d/"

# Copy D-Bus policy
cp "$CORE_SRC/data/org.dstx.Bridge.conf" "$TEMP_DIR/usr/share/dbus-1/system.d/"

# Copy Polkit rule
cp "$CORE_SRC/data/10-dstx.rules" "$TEMP_DIR/usr/share/polkit-1/rules.d/"

# Copy sudoers file
cp "$CORE_SRC/data/dstx-sudoers" "$TEMP_DIR/etc/sudoers.d/dstx"
chmod 440 "$TEMP_DIR/etc/sudoers.d/dstx"

# Create control file
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

# Create postinst script
cat > "$TEMP_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

# Create system group 'dstx' if it doesn't exist
if ! getent group dstx >/dev/null; then
    groupadd --system dstx
    echo "Created system group 'dstx'."
fi

# Reload systemd, enable and start services
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable dstx-daemon.service dstx-dbus.service 2>/dev/null || true
    systemctl start dstx-daemon.service dstx-dbus.service 2>/dev/null || true
fi

# Reload udev rules
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
fi

# Reload D-Bus to pick up new policy
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload dbus 2>/dev/null || true
fi

# Inform user about group membership
REAL_USER="${SUDO_USER:-$USER}"
echo "=================================================="
echo "DSTX Core installed successfully."
echo "To allow your user ($REAL_USER) to control the service, run:"
echo "  sudo usermod -aG dstx $REAL_USER"
echo "Then log out and back in (or restart your session)."
echo "=================================================="

exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/postinst"

# Create prerm script
cat > "$TEMP_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e

# Stop and disable services before removal
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop dstx-daemon.service dstx-dbus.service 2>/dev/null || true
    systemctl disable dstx-daemon.service dstx-dbus.service 2>/dev/null || true
fi

exit 0
EOF
chmod 755 "$TEMP_DIR/DEBIAN/prerm"

# Build the .deb package
mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$TEMP_DIR" "$OUTPUT_DIR/dstx-${VERSION}_amd64.deb"

echo "✅ Debian package built: $OUTPUT_DIR/dstx-${VERSION}_amd64.deb"
