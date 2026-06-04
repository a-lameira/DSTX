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
cat > "$RPM_TOPDIR/SPECS/dstx-core.spec" << EOF
Name:           dstx-core
Version:        $VERSION
Release:        1%{?dist}
Summary:        DSTX Core (daemon and D-Bus bridge)
License:        GPL-3.0-only
URL:            https://dstx.org
BuildArch:      x86_64
Requires:       systemd udev dbus

%description
Advanced controller driver for PlayStation DualSense, DS4 and Nintendo Switch Pro.
This package contains only the core daemon and D-Bus bridge, not the graphical interface.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/lib/systemd/system
mkdir -p %{buildroot}/lib/udev/rules.d
mkdir -p %{buildroot}/etc/dbus-1/system.d

install -Dm755 %{_sourcedir}/dstx %{buildroot}/usr/bin/dstx
install -Dm755 %{_sourcedir}/dstx-dbus %{buildroot}/usr/bin/dstx-dbus
install -Dm644 %{_sourcedir}/dstx.service %{buildroot}/lib/systemd/system/dstx.service
install -Dm644 %{_sourcedir}/dstx-dbus.service %{buildroot}/lib/systemd/system/dstx-dbus.service
install -Dm644 %{_sourcedir}/99-dstx.rules %{buildroot}/lib/udev/rules.d/99-dstx.rules
install -Dm644 %{_sourcedir}/org.dstx.Bridge.conf %{buildroot}/etc/dbus-1/system.d/org.dstx.Bridge.conf

%post
systemctl enable dstx.service dstx-dbus.service
systemctl start dstx.service dstx-dbus.service
udevadm control --reload-rules

%preun
systemctl stop dstx.service dstx-dbus.service || true

%files
/usr/bin/dstx
/usr/bin/dstx-dbus
/lib/systemd/system/dstx.service
/lib/systemd/system/dstx-dbus.service
/lib/udev/rules.d/99-dstx.rules
/etc/dbus-1/system.d/org.dstx.Bridge.conf

%changelog
* $CHANGELOG_DATE André Lameira <alameira@dstx.org> - $VERSION-1
- Core-only package
EOF

# Copy static binaries
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$RPM_TOPDIR/SOURCES/"

# Copy system files from dstx/data/
cp "$CORE_SRC/data/dstx.service" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/dstx-dbus.service" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/99-dstx.rules" "$RPM_TOPDIR/SOURCES/"
cp "$CORE_SRC/data/org.dstx.Bridge.conf" "$RPM_TOPDIR/SOURCES/"

# Build using minimal Fedora container
docker build -t dstx-fedora-builder -f "$SCRIPT_DIR/containers/fedora-rawhide.Dockerfile" .
docker run --rm -v "$RPM_TOPDIR:/build" dstx-fedora-builder sh -c '
    cd /build
    rpmbuild -bb --define "_topdir $PWD" SPECS/dstx-core.spec
'

mkdir -p "$OUTPUT_DIR"
cp "$RPM_TOPDIR/RPMS/x86_64/"*.rpm "$OUTPUT_DIR/"
echo "✅ RPM package built:"
ls -lh "$OUTPUT_DIR"

# Clean up temporary directory (files are root-owned, use sudo)
sudo rm -rf "$RPM_TOPDIR"
