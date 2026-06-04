FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base build tools and all dependencies needed for GTK4 and libadwaita
RUN apt-get update && apt-get install -y \
    build-essential meson ninja-build pkg-config wget gettext desktop-file-utils file \
    libglib2.0-dev libcairo2-dev libpango1.0-dev libgdk-pixbuf-2.0-dev \
    libffi-dev libxml2-dev libepoxy-dev libwayland-dev libx11-dev \
    libxrandr-dev libxext-dev libxrender-dev libxcomposite-dev \
    libxdamage-dev libxcb-shm0-dev libxcb-render0-dev libxkbcommon-dev \
    libjpeg-dev libpng-dev libtiff-dev librsvg2-dev \
    libxi-dev libxtst-dev libxfixes-dev libxinerama-dev libgl1-mesa-dev \
    libgles2-mesa-dev libvulkan-dev wayland-protocols \
    git python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Upgrade meson to a recent version (GTK 4.20 requires meson >= 0.64, we use latest)
RUN pip3 install --upgrade meson

# Set working directory for source builds
WORKDIR /tmp

# ========== Build GTK 4.20.1 ==========
RUN wget -q https://download.gnome.org/sources/gtk/4.20/gtk-4.20.1.tar.xz \
    && tar -xf gtk-4.20.1.tar.xz \
    && cd gtk-4.20.1 \
    && meson setup _build --prefix=/usr/local --libdir=lib/x86_64-linux-gnu \
    && ninja -C _build \
    && ninja -C _build install \
    && cd /tmp && rm -rf gtk-4.20.1*

# ========== Build libadwaita 1.8.0 ==========
RUN wget -q https://download.gnome.org/sources/libadwaita/1.8/libadwaita-1.8.0.tar.xz \
    && tar -xf libadwaita-1.8.0.tar.xz \
    && cd libadwaita-1.8.0 \
    && meson setup _build --prefix=/usr/local --libdir=lib/x86_64-linux-gnu \
    && ninja -C _build \
    && ninja -C _build install \
    && cd /tmp && rm -rf libadwaita-1.8.0*

RUN ldconfig

WORKDIR /work
