#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="${script_dir}/validate-source-run.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

valid_sha=0123456789abcdef0123456789abcdef01234567
cat > "${work}/valid.json" <<EOF
{
  "id": 123,
  "path": ".github/workflows/release.yml",
  "event": "workflow_dispatch",
  "status": "completed",
  "conclusion": "success",
  "head_branch": "main",
  "head_sha": "${valid_sha}",
  "repository": {"full_name": "example-owner/example-source"},
  "head_repository": {"full_name": "example-owner/example-source"}
}
EOF

SOURCE_RUN_JSON_FILE="${work}/valid.json" \
  SOURCE_REPOSITORY=example-owner/example-source \
  EXPECTED_SOURCE_COMMIT="${valid_sha}" \
  "${validator}" 123 "${work}/valid.out"
test "$(awk -F= '$1 == "head_sha" {print $2}' "${work}/valid.out")" = "${valid_sha}"

jq '.head_branch = "feature/malicious"' "${work}/valid.json" > "${work}/branch.json"
if SOURCE_RUN_JSON_FILE="${work}/branch.json" \
  SOURCE_REPOSITORY=example-owner/example-source \
  "${validator}" 123 "${work}/branch.out"; then
  echo 'malicious branch was accepted' >&2
  exit 1
fi

jq '.head_sha = "fedcba9876543210fedcba9876543210fedcba98"' "${work}/valid.json" > "${work}/head.json"
if SOURCE_RUN_JSON_FILE="${work}/head.json" \
  SOURCE_REPOSITORY=example-owner/example-source \
  EXPECTED_SOURCE_COMMIT="${valid_sha}" \
  "${validator}" 123 "${work}/head.out"; then
  echo 'head SHA mismatch was accepted' >&2
  exit 1
fi

jq '.repository.full_name = "attacker/fork" | .head_repository.full_name = "attacker/fork"' \
  "${work}/valid.json" > "${work}/foreign.json"
if SOURCE_RUN_JSON_FILE="${work}/foreign.json" \
  SOURCE_REPOSITORY=example-owner/example-source \
  "${validator}" 123 "${work}/foreign.out"; then
  echo 'run from a foreign repository was accepted' >&2
  exit 1
fi

echo 'validate-source-run focused tests: ok'
