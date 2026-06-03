FROM fedora:rawhide

RUN dnf install -y gcc make meson ninja-build pkgconfig \
    gtk4-devel libadwaita-devel libgee-devel json-glib-devel librsvg2-devel \
    systemd-devel rpm-build rpmdevtools git

WORKDIR /build
