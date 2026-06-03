#!/bin/bash
# ==============================================================================
# DSTX - Centralized Build Orchestrator
# ==============================================================================
# This script builds all distribution packages for DSTX:
#   - Static core binaries (dstx, dstx-dbus)
#   - Flatpak bundle
#   - Debian (.deb) package
#   - Fedora (.rpm) package
#   - Portable tarball (.tar.gz)
#
# Usage: ./build-all.sh
# ==============================================================================

set -e  # Exit on any error

# ----------------------------------------------
# Color definitions
# ----------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----------------------------------------------
# Helper functions
# ----------------------------------------------
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

# ----------------------------------------------
# Get the absolute path of the script directory
# ----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# ----------------------------------------------
# Verify that all required subdirectories exist
# ----------------------------------------------
print_header "DSTX - Centralized Build System"

if [ ! -d "$PROJECT_ROOT/dstx" ]; then
    print_error "DSTX core source directory not found: $PROJECT_ROOT/dstx"
    exit 1
fi

if [ ! -d "$PROJECT_ROOT/dstx-gui" ]; then
    print_error "DSTX GUI source directory not found: $PROJECT_ROOT/dstx-gui"
    exit 1
fi

# ----------------------------------------------
# Create output directories
# ----------------------------------------------
mkdir -p "$PROJECT_ROOT/build/core-static"
mkdir -p "$PROJECT_ROOT/build/flatpak-repo"
mkdir -p "$PROJECT_ROOT/build/flatpak-bundle"
mkdir -p "$PROJECT_ROOT/build/deb"
mkdir -p "$PROJECT_ROOT/build/rpm"
mkdir -p "$PROJECT_ROOT/build/tar"

# ----------------------------------------------
# Ensure VERSION file exists (will be overwritten by CI if using tags)
# ----------------------------------------------
if [ ! -f "$PROJECT_ROOT/VERSION" ]; then
    echo "0.1.0" > "$PROJECT_ROOT/VERSION"
    print_step "Created default VERSION file (0.1.0)"
fi

VERSION=$(cat "$PROJECT_ROOT/VERSION")
print_step "Building version: $VERSION"

# ==============================================================================
# 1. Build static core binaries (using Alpine Linux container)
# ==============================================================================
print_header "1. Building static core binaries (dstx, dstx-dbus)"

if [ -f "$PROJECT_ROOT/build/build-core-static.sh" ]; then
    print_step "Executing build-core-static.sh..."
    "$PROJECT_ROOT/build/build-core-static.sh"
else
    print_error "build-core-static.sh not found in build/"
    exit 1
fi

# Verify that static binaries were created
if [ ! -f "$PROJECT_ROOT/build/core-static/dstx" ] || [ ! -f "$PROJECT_ROOT/build/core-static/dstx-dbus" ]; then
    print_error "Static core binaries not generated correctly"
    exit 1
fi
print_success "Static core binaries ready"

# ==============================================================================
# 2. Build Flatpak bundle
# ==============================================================================
print_header "2. Building Flatpak bundle"

if [ -f "$PROJECT_ROOT/build/build-flatpak.sh" ]; then
    print_step "Executing build-flatpak.sh..."
    "$PROJECT_ROOT/build/build-flatpak.sh"
else
    print_error "build-flatpak.sh not found in build/"
    exit 1
fi

# Verify Flatpak bundle
if [ -f "$PROJECT_ROOT/build/flatpak-bundle/dstx-gui.flatpak" ]; then
    print_success "Flatpak bundle created"
else
    print_error "Flatpak bundle not generated"
    exit 1
fi

# ==============================================================================
# 3. Build Debian (.deb) package
# ==============================================================================
print_header "3. Building Debian package"

if [ -f "$PROJECT_ROOT/build/build-deb.sh" ]; then
    print_step "Executing build-deb.sh..."
    "$PROJECT_ROOT/build/build-deb.sh"
else
    print_error "build-deb.sh not found in build/"
    exit 1
fi

# Verify .deb files
if ls "$PROJECT_ROOT/build/deb/"*.deb 1> /dev/null 2>&1; then
    print_success "Debian package(s) created"
else
    print_error "No .deb files generated"
    exit 1
fi

# ==============================================================================
# 4. Build Fedora (.rpm) package
# ==============================================================================
print_header "4. Building RPM package"

if [ -f "$PROJECT_ROOT/build/build-rpm.sh" ]; then
    print_step "Executing build-rpm.sh..."
    "$PROJECT_ROOT/build/build-rpm.sh"
else
    print_error "build-rpm.sh not found in build/"
    exit 1
fi

# Verify .rpm files
if ls "$PROJECT_ROOT/build/rpm/"*.rpm 1> /dev/null 2>&1; then
    print_success "RPM package(s) created"
else
    print_error "No .rpm files generated"
    exit 1
fi

# ==============================================================================
# 5. Build portable tarball
# ==============================================================================
print_header "5. Building portable tarball"

if [ -f "$PROJECT_ROOT/build/build-tar.sh" ]; then
    print_step "Executing build-tar.sh..."
    "$PROJECT_ROOT/build/build-tar.sh"
else
    print_error "build-tar.sh not found in build/"
    exit 1
fi

# Verify tarball
if [ -f "$PROJECT_ROOT/build/tar/dstx-$VERSION.tar.gz" ]; then
    print_success "Tarball created"
else
    print_error "Tarball not generated"
    exit 1
fi

# ==============================================================================
# Summary
# ==============================================================================
print_header "BUILD COMPLETED SUCCESSFULLY"
echo ""
echo -e "${GREEN}All packages have been generated in the 'build/' directory:${NC}"
echo ""
echo "  📦 Static core:        build/core-static/"
echo "  🧩 Flatpak bundle:     build/flatpak-bundle/dstx-gui.flatpak"
echo "  📀 Debian packages:    build/deb/"
echo "  📀 RPM packages:       build/rpm/"
echo "  📁 Portable tarball:   build/tar/dstx-$VERSION.tar.gz"
echo ""
echo -e "${BLUE}Use these files for distribution or testing.${NC}"
echo ""

# Optional: show file sizes
ls -lh "$PROJECT_ROOT/build/core-static/" 2>/dev/null | tail -n +2 || true
ls -lh "$PROJECT_ROOT/build/flatpak-bundle/" 2>/dev/null | tail -n +2 || true
ls -lh "$PROJECT_ROOT/build/deb/" 2>/dev/null | tail -n +2 || true
ls -lh "$PROJECT_ROOT/build/rpm/" 2>/dev/null | tail -n +2 || true
ls -lh "$PROJECT_ROOT/build/tar/" 2>/dev/null | tail -n +2 || true
