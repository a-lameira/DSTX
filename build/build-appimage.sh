#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/appimage"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building AppImage (GUI only) using Ubuntu rolling"

docker run --rm -v "$PROJECT_ROOT:/work" ubuntu:rolling /bin/bash -c '
set -ex

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y meson ninja-build valac pkg-config wget gettext desktop-file-utils \
    libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libjson-glib-dev librsvg2-dev

cd /work/dstx-gui
meson setup builddir --prefix=/usr
ninja -C builddir
DESTDIR=/work/AppDir ninja -C builddir install

# Verifica se o arquivo .desktop foi criado
cat /work/AppDir/usr/share/applications/dstx-gui.desktop
desktop-file-validate /work/AppDir/usr/share/applications/dstx-gui.desktop

# Baixa o linuxdeploy (AppImage) e o script do plugin GTK
wget --no-verbose https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget --no-verbose https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh

chmod +x linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-plugin-gtk.sh

# Extrai o linuxdeploy para evitar problemas com FUSE
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root linuxdeploy-extracted

# Executa o linuxdeploy usando o script do plugin GTK
./linuxdeploy-extracted/AppRun \
    --appdir /work/AppDir \
    --plugin /work/linuxdeploy-plugin-gtk.sh \
    --output appimage \
    --verbose

# Move o AppImage gerado para o diretório de saída
mv DSTX_GUI-*.AppImage /work/build/appimage/dstx-gui.AppImage
'

echo "✅ AppImage created: $OUTPUT_DIR/dstx-gui.AppImage"
