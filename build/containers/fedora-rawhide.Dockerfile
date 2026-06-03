FROM fedora:rawhide

# Instala dependências de build e empacotamento para Fedora/RPM
RUN dnf install -y \
    gcc make meson ninja-build pkgconfig \
    gtk4-devel libadwaita-devel gee-devel json-glib-devel librsvg2-devel \
    systemd-devel rpm-build rpmdevtools git \
    && dnf clean all

WORKDIR /build
