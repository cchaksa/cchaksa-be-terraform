#!/usr/bin/env bash

set -euo pipefail

state_json="$(mktemp)"
trap 'rm -f "${state_json}"' EXIT

terraform state pull > "${state_json}"

artifact_bucket="$(jq -er '
  .resources[]
  | select(.module == "module.backend_serverless[0]")
  | select(.type == "aws_s3_object" and .name == "lambda_package")
  | .instances[0].attributes.bucket
' "${state_json}")"
artifact_key="$(jq -er '
  .resources[]
  | select(.module == "module.backend_serverless[0]")
  | select(.type == "aws_s3_object" and .name == "lambda_package")
  | .instances[0].attributes.key
' "${state_json}")"
artifact_version="$(jq -r '
  .resources[]
  | select(.module == "module.backend_serverless[0]")
  | select(.type == "aws_s3_object" and .name == "lambda_package")
  | .instances[0].attributes.version_id // empty
' "${state_json}")"
package_path="$(jq -er '
  .resources[]
  | select(.module == "module.backend_serverless[0]")
  | select(.type == "aws_s3_object" and .name == "lambda_package")
  | .instances[0].attributes.source
' "${state_json}")"
if realpath -m / >/dev/null 2>&1; then
  package_path="$(realpath -m "${package_path}")"
  workspace_parent="$(realpath -m "${GITHUB_WORKSPACE:-$(pwd)}/..")"
else
  mkdir -p "$(dirname "${package_path}")"
  package_path="$(cd "$(dirname "${package_path}")" && pwd -P)/$(basename "${package_path}")"
  workspace_parent="$(cd "${GITHUB_WORKSPACE:-$(pwd)}/.." && pwd -P)"
fi

case "${package_path}" in
  "${workspace_parent}"/*) ;;
  *)
    echo "Lambda package path must stay inside the Actions workspace." >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "${package_path}")"
get_object_args=(
  --bucket "${artifact_bucket}"
  --key "${artifact_key}"
)
if [ -n "${artifact_version}" ]; then
  get_object_args+=(--version-id "${artifact_version}")
fi

aws s3api get-object "${get_object_args[@]}" "${package_path}" >/dev/null
test -s "${package_path}"
printf '%s\n' "${package_path}" > /tmp/prod-lambda-package-path
