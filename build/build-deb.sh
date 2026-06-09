#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Adjust PROJECT_ROOT according to your directory structure.
# This script expects to be placed in the 'build/' subdirectory of the project root.
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=$(cat "$PROJECT_ROOT/VERSION")
DATE=$(date -R)

echo "📦 Building Debian package for dstx-core version $VERSION"

# Ensure static binaries are ready
if [ ! -f "$PROJECT_ROOT/build/core-static/dstx" ] || [ ! -f "$PROJECT_ROOT/build/core-static/dstx-dbus" ]; then
    echo "❌ Static binaries not found. Run build-core-static.sh first."
    exit 1
fi

# Generate changelog from template if available
if [ -f "$PROJECT_ROOT/debian/changelog.in" ]; then
    sed -e "s/@VERSION@/$VERSION/g" -e "s/@DATE@/$DATE/g" \
        "$PROJECT_ROOT/debian/changelog.in" > "$PROJECT_ROOT/debian/changelog"
else
    echo "WARNING: debian/changelog.in not found. Creating minimal changelog."
    cat > "$PROJECT_ROOT/debian/changelog" << EOF
dstx-core ($VERSION-1) unstable; urgency=medium

  * New release

 -- André Lameira <alameira@dstx.org>  $DATE
EOF
fi

# Build the package
cd "$PROJECT_ROOT"
dpkg-buildpackage -us -uc -b -d

# Move generated .deb files to build/deb/
mkdir -p "$PROJECT_ROOT/build/deb"
mv "$PROJECT_ROOT/../"*.deb "$PROJECT_ROOT/build/deb/" 2>/dev/null || true

echo "✅ Debian package built: $(ls $PROJECT_ROOT/build/deb/*.deb)"
