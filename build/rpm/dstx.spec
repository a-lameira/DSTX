Name:           dstx
Version:        @VERSION@
Release:        1%{?dist}
Summary:        Driver for PlayStation DualSense, DS4 and Nintendo Switch Pro controllers

License:        GPL-3.0-only
URL:            https://dstx.org
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson ninja-build gcc gcc-c++ pkgconfig
BuildRequires:  pkgconfig(gtk4) pkgconfig(libadwaita-1) pkgconfig(gee-0.8)
BuildRequires:  pkgconfig(json-glib-1.0) pkgconfig(librsvg-2.0) pkgconfig(libsystemd)
Requires:       systemd udev dbus

%description
DSTX is a driver that provides advanced configuration (LED, rumble, macros)
for PlayStation DualSense, DualShock 4 and Nintendo Switch Pro controllers.
This package includes the core daemon, D-Bus bridge and graphical interface.

%prep
%setup -q

%build
%meson
%meson_build

%install
%meson_install
# Install static binaries (copied manually before build)
install -Dm755 %{_builddir}/src/bin/dstx %{buildroot}%{_bindir}/dstx
install -Dm755 %{_builddir}/src/bin/dstx-dbus %{buildroot}%{_bindir}/dstx-dbus

# Install systemd units, udev rules, dbus config (adjust paths as needed)
install -Dm644 data/dstx.service %{buildroot}%{_unitdir}/dstx.service
install -Dm644 data/dstx-dbus.service %{buildroot}%{_unitdir}/dstx-dbus.service
install -Dm644 data/99-dstx.rules %{buildroot}%{_udevrulesdir}/99-dstx.rules
install -Dm644 data/org.dstx.Bridge.conf %{buildroot}%{_sysconfdir}/dbus-1/system.d/org.dstx.Bridge.conf

%post
%systemd_post dstx.service dstx-dbus.service
udevadm control --reload-rules

%preun
%systemd_preun dstx.service dstx-dbus.service

%postun
%systemd_postun_with_restart dstx.service dstx-dbus.service

%files
%{_bindir}/dstx
%{_bindir}/dstx-dbus
%{_bindir}/dstx-gui
%{_datadir}/applications/dstx-gui.desktop
%{_datadir}/icons/hicolor/*/apps/*
%{_datadir}/metainfo/org.dstx.gui.appdata.xml
%{_unitdir}/dstx.service
%{_unitdir}/dstx-dbus.service
%{_udevrulesdir}/99-dstx.rules
%{_sysconfdir}/dbus-1/system.d/org.dstx.Bridge.conf
%{_datadir}/dstx-gui/themes.json

%changelog
* %(date +"%a %b %d %Y") André Lameira <alameira@dstx.org> - @VERSION@-1
- New upstream release
