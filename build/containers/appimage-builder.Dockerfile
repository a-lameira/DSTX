FROM ghcr.io/flatpak/gnome-sdk:49

RUN apt-get update && apt-get install -y \
    wget \
    desktop-file-utils \
    file \
    gettext \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
