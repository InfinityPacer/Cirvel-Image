# syntax=docker/dockerfile:1

ARG PLEX_BASE_IMAGE=lscr.io/linuxserver/plex:1.43.4.10903-e5521bd8c-ls324@sha256:1f6f97d76e7bdb013789e94c838f2d9133b01ee4b2d4194148e492c4e4f12d90
ARG FFPROBE_BUILD_IMAGE=alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1
ARG FFMPEG_VERSION=6.1.2
ARG FFMPEG_SHA256=3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38

FROM ${FFPROBE_BUILD_IMAGE} AS ffprobe-build
ARG FFMPEG_VERSION
ARG FFMPEG_SHA256
RUN apk add --no-cache \
        build-base ca-certificates curl linux-headers openssl-dev openssl-libs-static \
        nasm pkgconf xz zlib-dev zlib-static
WORKDIR /tmp/ffmpeg
RUN curl -fsSLo ffmpeg.tar.xz "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && echo "${FFMPEG_SHA256}  ffmpeg.tar.xz" | sha256sum -c - \
    && tar -xJf ffmpeg.tar.xz --strip-components=1 \
    && ./configure \
        --disable-shared \
        --enable-static \
        --pkg-config-flags=--static \
        --extra-ldflags=-static \
        --disable-doc \
        --disable-debug \
        --disable-ffmpeg \
        --disable-ffplay \
        --disable-avdevice \
        --disable-avfilter \
        --disable-postproc \
        --disable-swscale \
        --disable-swresample \
        --disable-encoders \
        --disable-muxers \
        --disable-filters \
        --disable-devices \
        --disable-autodetect \
        --enable-network \
        --enable-openssl \
        --enable-zlib \
    && make -j"$(getconf _NPROCESSORS_ONLN)" ffprobe \
    && strip ./ffprobe \
    && ./ffprobe -version | grep -F "ffprobe version ${FFMPEG_VERSION}" \
    && ! readelf -l ./ffprobe | grep -F 'Requesting program interpreter'

FROM ${PLEX_BASE_IMAGE}

ENV VERSION=docker
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

ARG CIRVEL_VERSION=0.1.0
ARG PLEX_BASE_IMAGE
ARG CIRVEL_SOURCE_REVISION
ARG CIRVEL_RELEASE_TAG
ARG PLEX_UPSTREAM_VERSION
ARG CIRVEL_RUNTIME_SHA256_AMD64
ARG CIRVEL_RUNTIME_SHA256_ARM64
ARG CIRVEL_PROXY_SHA256_AMD64
ARG CIRVEL_PROXY_SHA256_ARM64
ARG CIRVEL_SHIM_SHA256_AMD64
ARG CIRVEL_SHIM_SHA256_ARM64
ARG TARGETARCH

LABEL org.opencontainers.image.title="Cirvel" \
      org.opencontainers.image.description="Plex Media Server image with the Cirvel runtime" \
      org.opencontainers.image.source="https://github.com/InfinityPacer/Cirvel-Image" \
      org.opencontainers.image.version="${CIRVEL_VERSION}" \
      org.opencontainers.image.base.name="lscr.io/linuxserver/plex" \
      org.opencontainers.image.revision="${CIRVEL_SOURCE_REVISION}" \
      io.infinitypacer.cirvel.version="${CIRVEL_VERSION}" \
      io.infinitypacer.cirvel.plex.version="${PLEX_UPSTREAM_VERSION}" \
      io.infinitypacer.cirvel.plex.base-reference="${PLEX_BASE_IMAGE}" \
      io.infinitypacer.cirvel.release-tag="${CIRVEL_RELEASE_TAG}" \
      io.infinitypacer.cirvel.runtime-sha256-amd64="${CIRVEL_RUNTIME_SHA256_AMD64}" \
      io.infinitypacer.cirvel.runtime-sha256-arm64="${CIRVEL_RUNTIME_SHA256_ARM64}" \
      io.infinitypacer.cirvel.proxy-sha256-amd64="${CIRVEL_PROXY_SHA256_AMD64}" \
      io.infinitypacer.cirvel.proxy-sha256-arm64="${CIRVEL_PROXY_SHA256_ARM64}" \
      io.infinitypacer.cirvel.shim-sha256-amd64="${CIRVEL_SHIM_SHA256_AMD64}" \
      io.infinitypacer.cirvel.shim-sha256-arm64="${CIRVEL_SHIM_SHA256_ARM64}" \
      io.infinitypacer.cirvel.target-architecture="${TARGETARCH}"

COPY --from=ffprobe-build /tmp/ffmpeg/ffprobe /opt/cirvel/ffmpeg/bin/ffprobe
COPY runtime/${TARGETARCH}/cirvel /usr/local/bin/cirvel
COPY runtime/${TARGETARCH}/cirvel-proxy /usr/local/bin/cirvel-proxy
COPY runtime/${TARGETARCH}/cirvel-bind.so /usr/local/lib/cirvel/cirvel-bind.so

RUN set -eux; \
    export CIRVEL_LOG_PATH=/tmp/cirvel-build.log; \
    chmod 0755 /usr/local/bin/cirvel /usr/local/bin/cirvel-proxy; \
    chmod 0644 /usr/local/lib/cirvel/cirvel-bind.so; \
    test "$(cirvel version)" = "${CIRVEL_VERSION}"; \
    cirvel install; \
    cirvel verify; \
    install -d /opt/cirvel; \
    command -v sha256sum >/dev/null; \
    case "${TARGETARCH}" in \
      amd64) \
        expected_runtime_sha256="${CIRVEL_RUNTIME_SHA256_AMD64}"; \
        expected_proxy_sha256="${CIRVEL_PROXY_SHA256_AMD64}"; \
        expected_shim_sha256="${CIRVEL_SHIM_SHA256_AMD64}" ;; \
      arm64) \
        expected_runtime_sha256="${CIRVEL_RUNTIME_SHA256_ARM64}"; \
        expected_proxy_sha256="${CIRVEL_PROXY_SHA256_ARM64}"; \
        expected_shim_sha256="${CIRVEL_SHIM_SHA256_ARM64}" ;; \
      *) echo "unsupported target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    for entry in \
      "runtime:/usr/local/bin/cirvel:${expected_runtime_sha256}" \
      "proxy:/usr/local/bin/cirvel-proxy:${expected_proxy_sha256}" \
      "shim:/usr/local/lib/cirvel/cirvel-bind.so:${expected_shim_sha256}"; \
    do \
      name="${entry%%:*}"; rest="${entry#*:}"; path="${rest%%:*}"; expected="${rest#*:}"; \
      printf '%s\n' "${expected}" | grep -Eq '^[0-9a-f]{64}$'; \
      actual="$(sha256sum "${path}" | awk '{print $1}')"; \
      test "${actual}" = "${expected}"; \
      printf '%s\n' "${actual}" > "/opt/cirvel/${name}.sha256"; \
    done; \
    printf '%s\n' "${CIRVEL_VERSION}" > /opt/cirvel/VERSION

RUN CIRVEL_LOG_PATH=/tmp/cirvel-build.log \
    LD_PRELOAD=/usr/local/lib/cirvel/cirvel-bind.so \
    CIRVEL_SHIM_PUBLIC_PORT=32499 \
    cirvel shim-selftest --port 32499 \
    && rm -rf /tmp/cirvel-build.log "/config/Library/Application Support/Plex Media Server/Logs"

EXPOSE 32400

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["cirvel", "healthcheck"]
