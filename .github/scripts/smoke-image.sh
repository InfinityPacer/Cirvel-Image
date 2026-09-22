#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE:?IMAGE is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"

for platform in linux/amd64 linux/arm64; do
  container="cirvel-smoke-${platform##*/}"
  cleanup() {
    docker rm -f "${container}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  echo "checking ${IMAGE} on ${platform}"
  docker run -d \
    --name "${container}" \
    --platform "${platform}" \
    --tmpfs /config:rw,exec \
    --tmpfs /transcode:rw,exec \
    "${IMAGE}" >/dev/null

  healthy=false
  for _ in $(seq 1 72); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "${container}")
    case "${status}" in
      healthy)
        healthy=true
        break
        ;;
      unhealthy)
        docker logs "${container}" >&2 || true
        exit 1
        ;;
      missing)
        echo "image did not define a healthcheck" >&2
        exit 1
        ;;
    esac
    if [[ "$(docker inspect --format '{{.State.Status}}' "${container}")" == "exited" ]]; then
      docker logs "${container}" >&2 || true
      exit 1
    fi
    sleep 5
  done
  test "${healthy}" = true

  version=$(docker exec "${container}" /usr/local/bin/cirvel version)
  test "${version}" = "${EXPECTED_VERSION}" || {
    echo "runtime version mismatch on ${platform}: ${version}" >&2
    exit 1
  }
  docker exec "${container}" /usr/local/bin/cirvel verify
  docker exec "${container}" /usr/local/bin/cirvel healthcheck
  docker exec "${container}" /bin/sh -ec '
    set -eu
    nc -z 127.0.0.1 32400
    nc -z 127.0.0.1 32460
  '
  loopback_owner=$(docker exec "${container}" /bin/sh -ec '
    curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:32400/cirvel/health
  ')
  if [[ "${loopback_owner}" == "200" ]]; then
    echo "the proxy took 127.0.0.1:32400 on ${platform}; Plex must own its own loopback" >&2
    exit 1
  fi
  container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container}")
  test -n "${container_ip}"
  external_owner=$(curl -s -o /dev/null -w '%{http_code}' "http://${container_ip}:32400/cirvel/health")
  if [[ "${external_owner}" != "200" ]]; then
    docker logs "${container}" >&2 || true
    echo "the proxy does not own ${container_ip}:32400 on ${platform} (answered ${external_owner})" >&2
    exit 1
  fi

  if docker logs "${container}" 2>&1 | grep -q 'Error relocating'; then
    docker logs "${container}" >&2 || true
    echo "the bind shim was rejected by the Plex-bundled loader on ${platform}" >&2
    exit 1
  fi

  identity=$(docker exec "${container}" /bin/sh -ec '
    set -eu
    plex_binary="/usr/lib/plexmediaserver/Plex Media Server"
    test -x "${plex_binary}"
    "${plex_binary}" --version 2>&1
  ')
  printf 'Plex identity (%s): %s\n' "${platform}" "${identity}"
  grep -Eq 'Plex Media Server|[0-9]+\.[0-9]+' <<< "${identity}"

  cleanup
  trap - EXIT
done
