FROM alpine:edge

RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    meson \
    ninja \
    pkgconfig \
    zlib-static \
    zlib-dev \
    cjson-static \
    cjson-dev

WORKDIR /work
