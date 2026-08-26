#!/usr/bin/env bash
# Hash the pinned tool versions so the binary cache key is stable for a given toolchain.
#
# Checkov is intentionally absent: it runs via the pinned bridgecrewio/checkov-action, whose
# Docker tag fixes the version.
set -euo pipefail

require_version() {
  local tool_name="$1" version="$2"

  if [[ -z "${version//[[:space:]]/}" ]]; then
    echo "::error::${tool_name} version must be specified." >&2
    exit 1
  fi

  if [[ "${version}" == "latest" ]]; then
    echo "::error::${tool_name} version must be pinned; 'latest' is not supported." >&2
    exit 1
  fi
}

require_version "Node.js" "${INPUT_NODE_VERSION}"

terraform_version="${INPUT_TERRAFORM_VERSION}"
tflint_version="${INPUT_TFLINT_VERSION}"
conftest_version="${INPUT_CONFTEST_VERSION}"
infracost_version="${INPUT_INFRACOST_VERSION}"
pre_commit_version="${INPUT_PRE_COMMIT_VERSION}"
commitlint_version="${INPUT_COMMITLINT_VERSION}"

if [[ "${INSTALL_TOOLS}" == "true" ]]; then
  require_version "Terraform" "${terraform_version}"
  require_version "TFLint" "${tflint_version}"
  require_version "Conftest" "${conftest_version}"
  require_version "Infracost" "${infracost_version}"
  require_version "pre-commit" "${pre_commit_version}"
  require_version "commitlint" "${commitlint_version}"
fi

versions_hash="$(
  printf '%s\n' \
    "${terraform_version}" \
    "${tflint_version}" \
    "${conftest_version}" \
    "${infracost_version}" \
    "${pre_commit_version}" \
    "${commitlint_version}" |
    sha256sum | cut -d' ' -f1
)"

{
  echo "terraform=${terraform_version}"
  echo "tflint=${tflint_version}"
  echo "conftest=${conftest_version}"
  echo "infracost=${infracost_version}"
  echo "pre-commit=${pre_commit_version}"
  echo "commitlint=${commitlint_version}"
  echo "versions-hash=${versions_hash}"
} >>"${GITHUB_OUTPUT}"

echo "Resolved toolchain:"
echo "  terraform  ${terraform_version}"
echo "  tflint     ${tflint_version}"
echo "  conftest   ${conftest_version}"
echo "  infracost  ${infracost_version}"
echo "  pre-commit ${pre_commit_version}"
echo "  commitlint ${commitlint_version}"
