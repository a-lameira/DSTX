#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Debian Sid (libadwaita 1.9+, GTK 4.20+)"

docker run --rm -v "$PROJECT_ROOT:/work" debian:sid /bin/bash -c '
set -ex

# Instalar CA certificates e dpkg-dev (necessário para o plugin)
apt-get update
apt-get install -y --no-install-recommends ca-certificates dpkg-dev
update-ca-certificates

# Instalar dependências de build e bibliotecas de desenvolvimento
apt-get install -y --no-install-recommends \
    meson ninja-build gcc g++ valac pkg-config wget gettext desktop-file-utils file \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev \
    libglib2.0-dev libcairo2-dev libpango1.0-dev libgdk-pixbuf-2.0-dev \
    libwayland-dev libx11-dev libxrandr-dev libxrender-dev libxi-dev \
    libgl1-mesa-dev libgles2-mesa-dev libvulkan-dev \
    flex bison gperf

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Corrigir nome do ícone no arquivo .desktop
sed -i "s/Icon=org.dstx.gui/Icon=dstx/" /work/AppDir/usr/share/applications/dstx-gui.desktop

desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Baixar linuxdeploy e o plugin GTK
wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-x86_64.AppImage linuxdeploy-plugin-gtk.sh

# Extrair linuxdeploy (evitar FUSE)
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

export LINUXDEPLOY=/work/dstx-gui/linuxdeploy-extracted/AppRun

# Primeira passagem: bibliotecas básicas
$LINUXDEPLOY --appdir /work/AppDir --verbosity=1

# Correção para o plugin: criar diretório que ele espera mas que não existe no Debian Sid
mkdir -p /work/AppDir/usr/lib/x86_64-linux-gnu/gtk-4.0

# Segunda passagem: plugin GTK
./linuxdeploy-plugin-gtk.sh --appdir /work/AppDir

# Criar AppImage final
$LINUXDEPLOY --appdir /work/AppDir --output appimage --verbosity=1

# Mover o AppImage gerado
mv DSTX-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
