#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$PROJECT_ROOT/VERSION")
CORE_BIN="$PROJECT_ROOT/build/core-static"
GUI_SRC="$PROJECT_ROOT/dstx-gui"
OUTPUT_DIR="$PROJECT_ROOT/build/rpm"

echo "📦 Building RPM package for version $VERSION"

# 1. Copiar binários estáticos para dentro do source da GUI
mkdir -p "$GUI_SRC/src/bin"
cp "$CORE_BIN/dstx" "$CORE_BIN/dstx-dbus" "$GUI_SRC/src/bin/"

# 2. Criar tarball fonte para o RPM (opcional, mas recomendado)
#    O rpmbuild pode usar o diretório diretamente, mas vamos copiar o spec
cp "$SCRIPT_DIR/rpm/dstx.spec" "$GUI_SRC/dstx.spec"
sed -i "s/@VERSION@/$VERSION/g" "$GUI_SRC/dstx.spec"

# 3. Construir container Fedora
docker build -t dstx-fedora-builder -f "$SCRIPT_DIR/containers/fedora-rawhide.Dockerfile" .

# 4. Executar o build dentro do container
#    Montamos o diretório da GUI como /build, e dentro dele rodamos rpmbuild
docker run --rm -v "$GUI_SRC:/build" dstx-fedora-builder sh -c '
    cd /build
    # Criar estrutura de rpmbuild
    mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    # Construir o RPM
    rpmbuild -bb --define "_topdir $PWD/rpmbuild" dstx.spec
'

# 5. Mover os RPMs gerados para o diretório de saída
mkdir -p "$OUTPUT_DIR"
# O RPM é gerado em rpmbuild/RPMS/x86_64/ (ou a arquitetura do container)
cp "$GUI_Src/rpmbuild/RPMS/"*/*.rpm "$OUTPUT_DIR/" 2>/dev/null || true

echo "✅ RPM packages:"
ls -lh "$OUTPUT_DIR"
