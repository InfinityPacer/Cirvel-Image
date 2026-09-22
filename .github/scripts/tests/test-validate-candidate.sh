#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="${script_dir}/validate-candidate.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

base_digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
base_reference="lscr.io/linuxserver/plex:1.43.4.10903-e5521bd8c-ls324@${base_digest}"
amd_base_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
arm_base_digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
source_commit=0123456789abcdef0123456789abcdef01234567
base_tag=1.43.4.10903-e5521bd8c-ls324
plex_version=1.43.4.10903
release_tag="0.1.0"

mkdir -p "${work}/bin" "${work}/incoming/amd64" "${work}/incoming/arm64" \
  "${work}/payload/amd64" "${work}/payload/arm64"
declare -A artifact_files=(
  [runtime]=cirvel
  [proxy]=cirvel-proxy
  [shim]=cirvel-bind.so
)
for arch in amd64 arm64; do
  for name in runtime proxy shim; do
    printf '%s %s\n' "${arch}" "${name}" > "${work}/payload/${arch}/${artifact_files[${name}]}"
  done
  tar -czf "${work}/incoming/${arch}/cirvel-runtime-${arch}.tar.gz" \
    -C "${work}/payload/${arch}" cirvel cirvel-proxy cirvel-bind.so
done

sha_of() { sha256sum "${work}/payload/${1}/${artifact_files[${2}]}" | awk '{print $1}'; }
size_of() { wc -c < "${work}/payload/${1}/${artifact_files[${2}]}" | tr -d '[:space:]'; }

files_json() {
  local arch=$1 name
  local entries=()
  for name in runtime proxy shim; do
    entries+=("$(jq -n --arg name "${name}" \
      --arg path "runtime/${arch}/${artifact_files[${name}]}" \
      --arg sha256 "$(sha_of "${arch}" "${name}")" \
      --argjson size "$(size_of "${arch}" "${name}")" \
      '{($name): {path: $path, sha256: $sha256, size: $size}}')")
  done
  printf '%s\n' "${entries[@]}" | jq -cs 'add'
}

amd_files=$(files_json amd64)
arm_files=$(files_json arm64)
amd_sha=$(sha_of amd64 runtime)
arm_sha=$(sha_of arm64 runtime)
amd_proxy_sha=$(sha_of amd64 proxy)
amd_shim_sha=$(sha_of amd64 shim)

jq -n \
  --arg base_reference "${base_reference}" --arg base_digest "${base_digest}" \
  --arg base_tag "${base_tag}" --arg source_commit "${source_commit}" \
  --arg release_tag "${release_tag}" --arg plex_version "${plex_version}" \
  --argjson amd_files "${amd_files}" --argjson arm_files "${arm_files}" \
  --arg amd_base_digest "${amd_base_digest}" --arg arm_base_digest "${arm_base_digest}" \
  '{schema:3,runtime:{name:"cirvel",version:"0.1.0",binary:"cirvel",commands:{version:"cirvel version",install:"cirvel install",verify:"cirvel verify",healthcheck:"cirvel healthcheck"},install_paths:{runtime:"/usr/local/bin/cirvel",proxy:"/usr/local/bin/cirvel-proxy",shim:"/usr/local/lib/cirvel/cirvel-bind.so"}},source:{repository:"example-owner/example-source",run_id:123,commit:$source_commit,ref:"refs/heads/main",workflow_path:".github/workflows/release.yml"},release:{tag:$release_tag,runtime_version:"0.1.0",plex_version:$plex_version,base_version:$base_tag},base:{image:"lscr.io/linuxserver/plex",tag:$base_tag,plex_version:$plex_version,reference:$base_reference,digest:$base_digest,platforms:{"linux/amd64":$amd_base_digest,"linux/arm64":$arm_base_digest}},artifacts:{"linux/amd64":{artifact:"cirvel-runtime-amd64",archive:"cirvel-runtime-amd64.tar.gz",files:$amd_files},"linux/arm64":{artifact:"cirvel-runtime-arm64",archive:"cirvel-runtime-arm64.tar.gz",files:$arm_files}}}' \
  > "${work}/manifest.json"

cat > "${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"{{json .Manifest}}"* ]]; then
  printf '{"digest":"%s","manifests":[{"platform":{"os":"linux","architecture":"amd64"},"digest":"%s"},{"platform":{"os":"linux","architecture":"arm64"},"digest":"%s"}]}\n' \
    "${MOCK_BASE_DIGEST}" "${MOCK_AMD_BASE_DIGEST}" "${MOCK_ARM_BASE_DIGEST}"
else
  printf '%s\n' "${MOCK_BASE_DIGEST}"
fi
EOF
chmod 0755 "${work}/bin/docker"

output="${work}/output"
PATH="${work}/bin:${PATH}" \
  MOCK_BASE_DIGEST="${base_digest}" MOCK_AMD_BASE_DIGEST="${amd_base_digest}" \
  MOCK_ARM_BASE_DIGEST="${arm_base_digest}" GITHUB_OUTPUT="${output}" \
  "${validator}" "${work}/manifest.json" example-owner/example-source 123 \
  "${source_commit}" 0.1.0 "${base_reference}" "${work}/incoming" "${work}/runtime"

grep -Fx "release_tag=${release_tag}" "${output}" >/dev/null
grep -Fx "plex_version=${plex_version}" "${output}" >/dev/null
grep -Fx "runtime_sha256_amd64=${amd_sha}" "${output}" >/dev/null
grep -Fx "runtime_sha256_arm64=${arm_sha}" "${output}" >/dev/null
grep -Fx "proxy_sha256_amd64=${amd_proxy_sha}" "${output}" >/dev/null
grep -Fx "shim_sha256_amd64=${amd_shim_sha}" "${output}" >/dev/null

jq '.release.tag = "pc0.1.0"' "${work}/manifest.json" > "${work}/bad-tag.json"
if PATH="${work}/bin:${PATH}" MOCK_BASE_DIGEST="${base_digest}" \
  MOCK_AMD_BASE_DIGEST="${amd_base_digest}" MOCK_ARM_BASE_DIGEST="${arm_base_digest}" \
  "${validator}" "${work}/bad-tag.json" example-owner/example-source 123 \
  "${source_commit}" 0.1.0 "${base_reference}" "${work}/incoming" "${work}/bad-runtime" \
  >/dev/null 2>&1; then
  echo 'legacy release tag was accepted' >&2
  exit 1
fi

jq 'del(.artifacts["linux/amd64"].files.shim)' "${work}/manifest.json" > "${work}/missing-shim.json"
if PATH="${work}/bin:${PATH}" MOCK_BASE_DIGEST="${base_digest}" \
  MOCK_AMD_BASE_DIGEST="${amd_base_digest}" MOCK_ARM_BASE_DIGEST="${arm_base_digest}" \
  "${validator}" "${work}/missing-shim.json" example-owner/example-source 123 \
  "${source_commit}" 0.1.0 "${base_reference}" "${work}/incoming" "${work}/missing-runtime" \
  >/dev/null 2>&1; then
  echo 'manifest without the bind shim was accepted' >&2
  exit 1
fi

echo 'validate-candidate focused tests: ok'
