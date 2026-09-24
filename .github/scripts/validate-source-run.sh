#!/usr/bin/env bash
set -euo pipefail

source_run_id=${1:?source workflow run ID is required}
output_file=${2:-${GITHUB_OUTPUT:-}}
expected_repository=${SOURCE_REPOSITORY:?SOURCE_REPOSITORY is required}
expected_workflow_path=.github/workflows/release.yml
expected_branch=main

[[ "${source_run_id}" =~ ^[1-9][0-9]*$ ]]
test -n "${output_file}"
command -v jq >/dev/null

validate_run() {
  local payload=$1
  local repository head_repository workflow_path head_branch head_sha event status conclusion run_id

  repository=$(jq -er '.repository.full_name' <<< "${payload}")
  head_repository=$(jq -er '.head_repository.full_name // .repository.full_name' <<< "${payload}")
  workflow_path=$(jq -er '.path' <<< "${payload}")
  head_branch=$(jq -er '.head_branch // empty' <<< "${payload}")
  head_sha=$(jq -er '.head_sha' <<< "${payload}")
  event=$(jq -er '.event' <<< "${payload}")
  status=$(jq -er '.status' <<< "${payload}")
  conclusion=$(jq -er '.conclusion // empty' <<< "${payload}")
  run_id=$(jq -er '.id | tostring' <<< "${payload}")

  [[ "${repository,,}" == "${expected_repository,,}" ]] || {
    echo "source run repository mismatch" >&2
    return 1
  }
  [[ "${head_repository,,}" == "${expected_repository,,}" ]] || {
    echo "source run head repository mismatch" >&2
    return 1
  }
  test "${run_id}" = "${source_run_id}" || {
    echo "source run ID mismatch" >&2
    return 1
  }
  test "${workflow_path}" = "${expected_workflow_path}" || {
    echo "source workflow path mismatch" >&2
    return 1
  }
  test "${head_branch}" = "${expected_branch}" || {
    echo "source workflow branch mismatch" >&2
    return 1
  }
  [[ "${event}" == push || "${event}" == workflow_dispatch ]] || {
    echo "source workflow event mismatch" >&2
    return 1
  }
  [[ "${head_sha}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "source workflow head SHA is invalid" >&2
    return 1
  }
  if [[ -n "${EXPECTED_SOURCE_COMMIT:-}" ]]; then
    test "${head_sha}" = "${EXPECTED_SOURCE_COMMIT}" || {
      echo "source workflow head SHA mismatch" >&2
      return 1
    }
  fi

  if [[ "${status}" == completed ]]; then
    test "${conclusion}" = success || {
      echo "source workflow did not succeed: ${conclusion}" >&2
      return 1
    }
    {
      printf 'head_sha=%s\n' "${head_sha}"
      printf 'workflow_path=%s\n' "${workflow_path}"
      printf 'head_branch=%s\n' "${head_branch}"
      printf 'conclusion=%s\n' "${conclusion}"
    } >> "${output_file}"
    return 0
  fi

  case "${status}" in
    queued|in_progress|waiting|requested|pending)
      return 2
      ;;
    *)
      echo "source workflow has unexpected status: ${status}" >&2
      return 1
      ;;
  esac
}

if [[ -n "${SOURCE_RUN_JSON_FILE:-}" ]]; then
  payload=$(<"${SOURCE_RUN_JSON_FILE}")
  validate_run "${payload}"
  exit $?
fi

: "${SOURCE_ARTIFACT_TOKEN:?SOURCE_ARTIFACT_TOKEN is required}"
poll_timeout=${POLL_TIMEOUT_SECONDS:-3600}
poll_interval=${POLL_INTERVAL_SECONDS:-15}
deadline=$(( $(date +%s) + poll_timeout ))
api_url="https://api.github.com/repos/${expected_repository}/actions/runs/${source_run_id}"

while :; do
  payload=$(curl --fail --silent --show-error \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --header "Authorization: Bearer ${SOURCE_ARTIFACT_TOKEN}" \
    "${api_url}")
  if validate_run "${payload}"; then
    exit 0
  else
    result=$?
    test "${result}" -eq 2
  fi
  if (( $(date +%s) >= deadline )); then
    echo "timed out waiting for source workflow run ${source_run_id}" >&2
    exit 1
  fi
  sleep "${poll_interval}"
done
