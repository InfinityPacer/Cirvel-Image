#!/usr/bin/env bash
set -euo pipefail

registry=${1:?registry is required}
image=${2:?image is required}
tag=${3:?tag is required}
shift 3

if (( $# == 0 )); then
  echo "no replaced digests recorded for ${image}"
  exit 0
fi

current="$(docker buildx imagetools inspect "${image}:${tag}" --format '{{json .Manifest}}' \
  | jq -r '[.digest] + [.manifests[]?.digest] | .[]')"
test -n "${current}"

stale=()
for digest in "$@"; do
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "invalid digest: ${digest}" >&2
    exit 1
  }
  if grep -qxF "${digest}" <<< "${current}"; then
    echo "${digest} is part of the published image, kept"
  else
    stale+=("${digest}")
  fi
done

if (( ${#stale[@]} == 0 )); then
  echo "nothing to prune for ${image}"
  exit 0
fi

prune_ghcr() {
  local package="${image##*/}"
  local owner="/users/${GITHUB_REPOSITORY_OWNER}"
  local versions line id tags
  if [[ "$(gh api "/users/${GITHUB_REPOSITORY_OWNER}" --jq .type)" == "Organization" ]]; then
    owner="/orgs/${GITHUB_REPOSITORY_OWNER}"
  fi
  versions="$(gh api --paginate "${owner}/packages/container/${package}/versions" \
    --jq '.[] | [.id, .name, (.metadata.container.tags | length)] | @tsv')"
  for digest in "${stale[@]}"; do
    line="$(awk -F '\t' -v digest="${digest}" '$2 == digest' <<< "${versions}")"
    if [[ -z "${line}" ]]; then
      echo "${image}@${digest} already gone"
      continue
    fi
    IFS=$'\t' read -r id _ tags <<< "${line}"
    if (( tags > 0 )); then
      echo "${image}@${digest} is still tagged, kept"
      continue
    fi
    gh api --silent --method DELETE "${owner}/packages/container/${package}/versions/${id}"
    echo "deleted ${image}@${digest}"
  done
}

prune_dockerhub() {
  local repository="${image#docker.io/}"
  local token claims status failed=0
  token="$(printf 'user = "%s:%s"\n' "${DOCKERHUB_USERNAME}" "${DOCKERHUB_TOKEN}" \
    | curl -fsS -K - "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repository}:pull,push,delete" \
    | jq -er .token)"
  echo "::add-mask::${token}"
  claims="$(cut -d. -f2 <<< "${token}" | tr '_-' '/+')"
  while (( ${#claims} % 4 )); do claims+="="; done
  if ! base64 -d <<< "${claims}" 2>/dev/null \
    | jq -e --arg repository "${repository}" \
      '.access[] | select(.name == $repository) | .actions | index("delete")' >/dev/null 2>&1; then
    echo "DOCKERHUB_TOKEN lacks the delete permission; replace it with a Read, Write, Delete access token" >&2
    return 1
  fi
  for digest in "${stale[@]}"; do
    status="$(printf 'header = "Authorization: Bearer %s"\n' "${token}" \
      | curl -sS -K - -o /dev/null -w '%{http_code}' -X DELETE \
        "https://registry-1.docker.io/v2/${repository}/manifests/${digest}")"
    case "${status}" in
      202) echo "deleted ${image}@${digest}" ;;
      404) echo "${image}@${digest} already gone" ;;
      500) echo "::warning::Docker Hub queued the deletion of ${image}@${digest}" ;;
      *)
        echo "failed to delete ${image}@${digest}: HTTP ${status}" >&2
        failed=1
        ;;
    esac
  done
  return "${failed}"
}

case "${registry}" in
  ghcr) prune_ghcr ;;
  dockerhub) prune_dockerhub ;;
  *)
    echo "unknown registry: ${registry}" >&2
    exit 1
    ;;
esac
