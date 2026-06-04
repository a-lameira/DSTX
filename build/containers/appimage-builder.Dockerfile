FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential meson ninja-build pkg-config wget gettext desktop-file-utils file \
    libglib2.0-dev libcairo2-dev libpango1.0-dev libgdk-pixbuf-2.0-dev \
    libffi-dev libxml2-dev libepoxy-dev libwayland-dev libx11-dev \
    libxrandr-dev libxext-dev libxrender-dev libxcomposite-dev \
    libxdamage-dev libxcb-shm0-dev libxcb-render0-dev libxkbcommon-dev \
    libjpeg-dev libpng-dev libtiff-dev librsvg2-dev \
    git python3 \
    && rm -rf /var/lib/apt/lists/*

# Compile GTK 4.14.5 (or newer)
WORKDIR /tmp
RUN wget -q https://download.gnome.org/sources/gtk/4.14/gtk-4.14.5.tar.xz \
    && tar -xf gtk-4.14.5.tar.xz \
    && cd gtk-4.14.5 \
    && meson setup _build --prefix=/usr/local --libdir=lib/x86_64-linux-gnu \
    && ninja -C _build \
    && ninja -C _build install \
    && cd /tmp && rm -rf gtk-4.14.5*

# Compile libadwaita 1.5.0 (or newer)
RUN wget -q https://download.gnome.org/sources/libadwaita/1.5/libadwaita-1.5.0.tar.xz \
    && tar -xf libadwaita-1.5.0.tar.xz \
    && cd libadwaita-1.5.0 \
    && meson setup _build --prefix=/usr/local --libdir=lib/x86_64-linux-gnu \
    && ninja -C _build \
    && ninja -C _build install \
    && cd /tmp && rm -rf libadwaita-1.5.0*

RUN ldconfig

# The container will run the build script; just need the environment
WORKDIR /work
