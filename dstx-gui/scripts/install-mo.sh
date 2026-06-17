#!/bin/bash
# scripts/install-mo.sh
set -e

MO_DIR="$MESON_BUILD_ROOT/po"
DESTDIR="${MESON_INSTALL_DESTDIR_PREFIX:-$MESON_INSTALL_PREFIX}"

for lang in pt_BR es_ES fr de it ru; do
    src="$MO_DIR/$lang.mo"
    dest_dir="$DESTDIR/share/locale/$lang/LC_MESSAGES"
    mkdir -p "$dest_dir"
    cp "$src" "$dest_dir/dstx-gui.mo"
done
