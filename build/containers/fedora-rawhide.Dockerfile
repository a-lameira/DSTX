FROM fedora:rawhide

# Minimal dependencies for RPM packaging
RUN dnf install -y rpm-build rpmdevtools make

WORKDIR /build
