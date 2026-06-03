FROM debian:bookworm

# Instala dependências de build e empacotamento para Debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential meson ninja-build pkg-config \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev \
    libglib2.0-dev libsystemd-dev \
    dpkg-dev devscripts debhelper \
    git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
