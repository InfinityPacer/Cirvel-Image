# syntax=docker/dockerfile:1

ARG PLEX_BASE_IMAGE=lscr.io/linuxserver/plex:1.43.4.10903-e5521bd8c-ls325@sha256:be083133dfe001b6caed5a321720e6db9d38fdde1ea8f9d29340d40057a7fa53

FROM ${PLEX_BASE_IMAGE}

ENV VERSION=docker
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

ARG CIRVEL_VERSION=0.1.4
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
ARG CIRVEL_FFPROBE_SHA256_AMD64
ARG CIRVEL_FFPROBE_SHA256_ARM64
ARG TARGETARCH

LABEL org.opencontainers.image.title="Cirvel" \
      org.opencontainers.image.description="Cirvel, built for your media library" \
      org.opencontainers.image.source="https://github.com/tidewren/Cirvel-Image" \
      org.opencontainers.image.version="${CIRVEL_VERSION}" \
      org.opencontainers.image.base.name="lscr.io/linuxserver/plex" \
      org.opencontainers.image.revision="${CIRVEL_SOURCE_REVISION}" \
      com.tidewren.cirvel.version="${CIRVEL_VERSION}" \
      com.tidewren.cirvel.plex.version="${PLEX_UPSTREAM_VERSION}" \
      com.tidewren.cirvel.plex.base-reference="${PLEX_BASE_IMAGE}" \
      com.tidewren.cirvel.release-tag="${CIRVEL_RELEASE_TAG}" \
      com.tidewren.cirvel.runtime-sha256-amd64="${CIRVEL_RUNTIME_SHA256_AMD64}" \
      com.tidewren.cirvel.runtime-sha256-arm64="${CIRVEL_RUNTIME_SHA256_ARM64}" \
      com.tidewren.cirvel.proxy-sha256-amd64="${CIRVEL_PROXY_SHA256_AMD64}" \
      com.tidewren.cirvel.proxy-sha256-arm64="${CIRVEL_PROXY_SHA256_ARM64}" \
      com.tidewren.cirvel.shim-sha256-amd64="${CIRVEL_SHIM_SHA256_AMD64}" \
      com.tidewren.cirvel.shim-sha256-arm64="${CIRVEL_SHIM_SHA256_ARM64}" \
      com.tidewren.cirvel.ffprobe-sha256-amd64="${CIRVEL_FFPROBE_SHA256_AMD64}" \
      com.tidewren.cirvel.ffprobe-sha256-arm64="${CIRVEL_FFPROBE_SHA256_ARM64}" \
      com.tidewren.cirvel.target-architecture="${TARGETARCH}"

COPY runtime/${TARGETARCH}/ffprobe /opt/cirvel/ffmpeg/bin/ffprobe
COPY runtime/${TARGETARCH}/cirvel /usr/local/bin/cirvel
COPY runtime/${TARGETARCH}/cirvel-proxy /usr/local/bin/cirvel-proxy
COPY runtime/${TARGETARCH}/cirvel-bind.so /usr/local/lib/cirvel/cirvel-bind.so

RUN set -eux; \
    export CIRVEL_LOG_PATH=/tmp/cirvel-build.log; \
    chmod 0755 /usr/local/bin/cirvel /usr/local/bin/cirvel-proxy /opt/cirvel/ffmpeg/bin/ffprobe; \
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
        expected_shim_sha256="${CIRVEL_SHIM_SHA256_AMD64}"; \
        expected_ffprobe_sha256="${CIRVEL_FFPROBE_SHA256_AMD64}" ;; \
      arm64) \
        expected_runtime_sha256="${CIRVEL_RUNTIME_SHA256_ARM64}"; \
        expected_proxy_sha256="${CIRVEL_PROXY_SHA256_ARM64}"; \
        expected_shim_sha256="${CIRVEL_SHIM_SHA256_ARM64}"; \
        expected_ffprobe_sha256="${CIRVEL_FFPROBE_SHA256_ARM64}" ;; \
      *) echo "unsupported target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    for entry in \
      "runtime:/usr/local/bin/cirvel:${expected_runtime_sha256}" \
      "proxy:/usr/local/bin/cirvel-proxy:${expected_proxy_sha256}" \
      "shim:/usr/local/lib/cirvel/cirvel-bind.so:${expected_shim_sha256}" \
      "ffprobe:/opt/cirvel/ffmpeg/bin/ffprobe:${expected_ffprobe_sha256}"; \
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
