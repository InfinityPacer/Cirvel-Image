#!/usr/bin/env bash
set -euo pipefail

manifest=${1:?manifest path is required}
expected_source_repository=${2:?source repository is required}
expected_source_run_id=${3:?source run ID is required}
expected_source_commit=${4:?source commit is required}
expected_runtime_version=${5:?runtime version is required}
expected_base_image=${6:?base image is required}
incoming_root=${7:?incoming artifact root is required}
runtime_root=${8:?runtime output root is required}

command -v jq >/dev/null
command -v sha256sum >/dev/null
command -v tar >/dev/null

schema=$(jq -er '.schema' "${manifest}")
test "${schema}" = 3

source_repository=$(jq -er '.source.repository' "${manifest}")
source_run_id=$(jq -er '.source.run_id | tostring' "${manifest}")
source_commit=$(jq -er '.source.commit' "${manifest}")
source_ref=$(jq -er '.source.ref' "${manifest}")
source_workflow_path=$(jq -er '.source.workflow_path' "${manifest}")
runtime_name=$(jq -er '.runtime.name' "${manifest}")
runtime_binary=$(jq -er '.runtime.binary' "${manifest}")
runtime_version_command=$(jq -er '.runtime.commands.version' "${manifest}")
runtime_install_command=$(jq -er '.runtime.commands.install' "${manifest}")
runtime_verify_command=$(jq -er '.runtime.commands.verify' "${manifest}")
runtime_healthcheck_command=$(jq -er '.runtime.commands.healthcheck' "${manifest}")
runtime_version=$(jq -er '.runtime.version' "${manifest}")
runtime_install_path=$(jq -er '.runtime.install_paths.runtime' "${manifest}")
proxy_install_path=$(jq -er '.runtime.install_paths.proxy' "${manifest}")
shim_install_path=$(jq -er '.runtime.install_paths.shim' "${manifest}")
base_image=$(jq -er '.base.image' "${manifest}")
base_reference=$(jq -er '.base.reference' "${manifest}")
base_digest=$(jq -er '.base.digest' "${manifest}")
base_tag=$(jq -er '.base.tag' "${manifest}")
base_plex_version=$(jq -er '.base.plex_version' "${manifest}")
release_tag=$(jq -er '.release.tag' "${manifest}")
release_runtime_version=$(jq -er '.release.runtime_version' "${manifest}")
release_plex_version=$(jq -er '.release.plex_version' "${manifest}")
release_base_version=$(jq -er '.release.base_version' "${manifest}")

[[ "${source_repository,,}" == "${expected_source_repository,,}" ]]
test "${source_run_id}" = "${expected_source_run_id}"
test "${source_commit}" = "${expected_source_commit}"
[[ "${source_commit}" =~ ^[0-9a-f]{40}$ ]]
test "${source_ref}" = "refs/heads/main"
test "${source_workflow_path}" = ".github/workflows/release.yml"
test "${runtime_name}" = "cirvel"
test "${runtime_binary}" = "cirvel"
test "${runtime_version_command}" = "cirvel version"
test "${runtime_install_command}" = "cirvel install"
test "${runtime_verify_command}" = "cirvel verify"
test "${runtime_healthcheck_command}" = "cirvel healthcheck"
test "${runtime_version}" = "${expected_runtime_version}"
test "${runtime_install_path}" = "/usr/local/bin/cirvel"
test "${proxy_install_path}" = "/usr/local/bin/cirvel-proxy"
test "${shim_install_path}" = "/usr/local/lib/cirvel/cirvel-bind.so"
test "${release_runtime_version}" = "${runtime_version}"
[[ "${base_tag}" =~ ^[A-Za-z0-9_.-]+$ ]]
[[ "${release_plex_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "${base_plex_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
test "${release_plex_version}" = "${base_plex_version}"
test "${base_reference}" = "${expected_base_image}"
[[ "${base_reference}" =~ ^lscr\.io/linuxserver/plex:[^@[:space:]]+@sha256:[0-9a-f]{64}$ ]]
test "${base_digest}" = "${base_reference##*@}"

expected_release_tag="${runtime_version}"
test "${release_base_version}" = "${base_tag}"
test "${release_tag}" = "${expected_release_tag}"
[[ "${release_tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]
test "${base_image}" = "lscr.io/linuxserver/plex"

registry_manifest=$(docker buildx imagetools inspect --format '{{json .Manifest}}' "${base_reference}")
registry_digest=$(jq -er '.digest' <<< "${registry_manifest}")
test "${registry_digest}" = "${base_digest}"

for platform in linux/amd64 linux/arm64; do
  digest=$(jq -er --arg platform "${platform}" '.base.platforms[$platform]' "${manifest}")
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]
  registry_platform_digest=$(jq -er --arg platform "${platform}" '.manifests[] | select(.platform.os == "linux" and ("linux/" + .platform.architecture) == $platform) | .digest' <<< "${registry_manifest}")
  test "${registry_platform_digest}" = "${digest}"
  artifact=$(jq -er --arg platform "${platform}" '.artifacts[$platform].artifact' "${manifest}")
  expected_artifact="cirvel-runtime-${platform##*/}"
  test "${artifact}" = "${expected_artifact}"
  archive=$(jq -er --arg platform "${platform}" '.artifacts[$platform].archive' "${manifest}")
  test "${archive}" = "${expected_artifact}.tar.gz"
  for name in runtime proxy shim; do
    case "${name}" in
      runtime) expected_file=cirvel ;;
      proxy) expected_file=cirvel-proxy ;;
      shim) expected_file=cirvel-bind.so ;;
    esac
    artifact_path=$(jq -er --arg platform "${platform}" --arg name "${name}" '.artifacts[$platform].files[$name].path' "${manifest}")
    test "${artifact_path}" = "runtime/${platform##*/}/${expected_file}"
  done
done

rm -rf "${runtime_root}"
mkdir -p "${runtime_root}/amd64" "${runtime_root}/arm64"

for arch in amd64 arm64; do
  archive="${incoming_root}/${arch}/cirvel-runtime-${arch}.tar.gz"
  test -f "${archive}"
  mapfile -t entries < <(tar -tzf "${archive}" | LC_ALL=C sort)
  test "${#entries[@]}" -eq 3
  test "${entries[0]}" = "cirvel"
  test "${entries[1]}" = "cirvel-bind.so"
  test "${entries[2]}" = "cirvel-proxy"
  tar -xzf "${archive}" -C "${runtime_root}/${arch}"

  for name in runtime proxy shim; do
    case "${name}" in
      runtime) file=cirvel ;;
      proxy) file=cirvel-proxy ;;
      shim) file=cirvel-bind.so ;;
    esac
    binary="${runtime_root}/${arch}/${file}"
    test -f "${binary}"
    test ! -L "${binary}"
    expected_sha=$(jq -er --arg platform "linux/${arch}" --arg name "${name}" '.artifacts[$platform].files[$name].sha256' "${manifest}")
    [[ "${expected_sha}" =~ ^[0-9a-f]{64}$ ]]
    actual_sha=$(sha256sum "${binary}" | awk '{print $1}')
    test "${actual_sha}" = "${expected_sha}"
    expected_size=$(jq -er --arg platform "linux/${arch}" --arg name "${name}" '.artifacts[$platform].files[$name].size' "${manifest}")
    actual_size=$(wc -c < "${binary}" | tr -d '[:space:]')
    test "${actual_size}" = "${expected_size}"
    if [[ "${name}" = shim ]]; then
      chmod 0644 "${binary}"
    else
      chmod 0755 "${binary}"
    fi
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      printf '%s_sha256_%s=%s\n' "${name}" "${arch}" "${expected_sha}" >> "${GITHUB_OUTPUT}"
    fi
  done
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'source_commit=%s\n' "${source_commit}"
    printf 'release_tag=%s\n' "${release_tag}"
    printf 'plex_version=%s\n' "${release_plex_version}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "runtime manifest and artifacts validated"
