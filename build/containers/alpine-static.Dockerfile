FROM alpine:edge

# Install build dependencies
RUN apk add --no-cache \
    gcc musl-dev make linux-headers \
    git meson ninja pkgconfig \
    zlib-static cjson-static

WORKDIR /work
