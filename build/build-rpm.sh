#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_VERSION=$(cat "$PROJECT_ROOT/VERSION")
VERSION="${RAW_VERSION//-/.}"
CORE_BIN="$PROJECT_ROOT/build/core-static"
CORE_SRC="$PROJECT_ROOT/dstx"
OUTPUT_DIR="$PROJECT_ROOT/build/rpm"

echo "📦 Building RPM package (core only) for version $VERSION"

RPM_TOPDIR=$(mktemp -d)

mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Generate changelog date
CHANGELOG_DATE=$(date +"%a %b %d %Y")

# Create spec file
cat > "$RPM_TOPDIR/SPECS/dstx-core.spec" << 'SPECEOF'
Name:           dstx-core
Version:        VERSION_PLACEHOLDER
Release:        1%{?dist}
Summary:        DSTX Core (daemon and D-Bus bridge)
License:        GPL-3.0-only
URL:            https://dstx.org
BuildArch:      x86_64
Requires:       systemd udev dbus polkit

%description
Advanced controller driver for PlayStation DualSense, DS4 and Nintendo Switch Pro.
This package contains only the core daemon and D-Bus bridge, not the graphical interface.

%prep
# Nothing to prep - binaries are pre-built

%build
# Nothing to build - binaries are pre-built

%install
rm -rf %{buildroot}

# Create directories
mkdir -p %{buildroot}/usr/local/bin
mkdir -p %{buildroot}/lib/systemd/system
mkdir -p %{buildroot}/lib/udev/rules.d
mkdir -p %{buildroot}/usr/share/polkit-1/rules.d
mkdir -p %{buildroot}/etc/sudoers.d
mkdir -p %{buildroot}/usr/share/dbus-1/system.d

# Install binaries to /usr/local/bin
install -Dm755 %{_sourcedir}/dstx %{buildroot}/usr/local/bin/dstx
install -Dm755 %{_sourcedir}/dstx-dbus %{buildroot}/usr/local/bin/dstx-dbus

# Install systemd units
install -Dm644 %{_sourcedir}/dstx-daemon.service %{buildroot}/lib/systemd/system/dstx-daemon.service
install -Dm644 %{_sourcedir}/dstx-dbus.service %{buildroot}/lib/systemd/system/dstx-dbus.service

# Install udev rules
install -Dm644 %{_sourcedir}/99-dstx.rules %{buildroot}/lib/udev/rules.d/99-dstx.rules

# Install D-Bus policy
install -Dm644 %{_sourcedir}/org.dstx.Bridge.conf %{buildroot}/usr/share/dbus-1/system.d/org.dstx.Bridge.conf

# Install Polkit rule
install -Dm644 %{_sourcedir}/10-dstx.rules %{buildroot}/usr/share/polkit-1/rules.d/10-dstx.rules

# Install sudoers file
install -Dm644 %{_sourcedir}/dstx-sudoers %{buildroot}/etc/sudoers.d/dstx
chmod 440 %{buildroot}/etc/sudoers.d/dstx

%pre
# Create dstx group before installation if it doesn't exist
getent group dstx >/dev/null || groupadd --system dstx

%post
# Reload systemd, enable and start services
systemctl daemon-reload
systemctl enable dstx-daemon.service dstx-dbus.service
systemctl start dstx-daemon.service dstx-dbus.service

# Reload udev rules
udevadm control --reload-rules || true

# Reload D-Bus to pick up new policy
systemctl reload dbus || true

# Display group membership message
echo "=================================================="
echo "DSTX Core installed successfully."
echo "To allow your user to control the service, run:"
echo "  sudo usermod -aG dstx \$USER"
echo "Then log out and back in (or restart your session)."
echo "=================================================="

%preun
# Stop and disable services before removal
if [ \$1 -eq 0 ]; then
    systemctl stop dstx-daemon.service dstx-dbus.service || true
    systemctl disable dstx-daemon.service dstx-dbus.service || true
fi

%postun
# Reload systemd after removal
if [ \$1 -eq 0 ]; then
    systemctl daemon-reload || true
    udevadm control --reload-rules || true
    systemctl reload dbus || true
fi

%files
/usr/local/bin/dstx
/usr/local/bin/dstx-dbus
/lib/systemd/system/dstx-daemon.service
/lib/systemd/system/dstx-dbus.service
/lib/udev/rules.d/99-dstx.rules
/usr/share/polkit-1/rules.d/10-dstx.rules
/etc/sudoers.d/dstx
/usr/share/dbus-1/system.d/org.dstx.Bridge.conf

%changelog
* CHANGELOG_DATE_PLACEHOLDER André Lameira <alameira@dstx.org> - VERSION_PLACEHOLDER-1
- Core-only package with /usr/local/bin consistency
SPECEOF

# Replace placeholders in the spec file
sed -i "s/VERSION_PLACEHOLDER/$VERSION/g" "$RPM_TOPDIR/SPECS/dstx-core.spec"
sed -i "s/CHANGELOG_DATE_PLACEHOLDER/$CHANGELOG_DATE/g" "$RPM_TOPDIR/SPECS/dstx-core.spec"

# Copy static binaries
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$RPM_TOPDIR/SOURCES/"

# Copy system files from dstx/data/
cp "$CORE_SRC/data/dstx-daemon.service" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/dstx-dbus.service" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/99-dstx.rules" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/org.dstx.Bridge.conf" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/10-dstx.rules" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/dstx-sudoers" "$RPM_TOPDIR/SOURCES/"

# Build RPM using Docker container
docker build -t dstx-fedora-builder -f "$SCRIPT_DIR/containers/fedora-rawhide.Dockerfile" .
docker run --rm -v "$RPM_TOPDIR:/build" dstx-fedora-builder sh -c '
    cd /build
    rpmbuild -bb --define "_topdir $PWD" SPECS/dstx-core.spec
'

mkdir -p "$OUTPUT_DIR"
# Copy RPM files with sudo to avoid permission issues
sudo cp "$RPM_TOPDIR/RPMS/x86_64/"*.rpm "$OUTPUT_DIR/" 2>/dev/null || \
     cp "$RPM_TOPDIR/RPMS/x86_64/"*.rpm "$OUTPUT_DIR/"

# Clean up with sudo to avoid permission issues
sudo rm -rf "$RPM_TOPDIR"

echo "✅ RPM package built:"
ls -lh "$OUTPUT_DIR"/*.rpm
