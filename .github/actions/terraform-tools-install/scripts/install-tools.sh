#!/usr/bin/env bash
# Install the requested tools that are not fetched as a checksummed binary download: commitlint
# (npm) and checkov/pre-commit (pip), both of which already have their own package-manager-level
# integrity verification, so there is no separate checksum to fetch and verify here. Checksummed
# binary tools (terraform, tflint, terraform-docs, conftest, infracost) are installed by the
# "Install checksummed binary tools" step, which delegates to install-checksummed-tools.
#
# Everything still lands under ~/.local so the single cache entry in action.yaml covers it all:
#   ~/.local/checksummed-tools  terraform, tflint, terraform-docs, conftest, infracost
#   ~/.local/commitlint         node_modules for @commitlint/cli
#   ~/.local/bin                checkov and pre-commit (pip --user)
set -euo pipefail

COMMITLINT_DIR="${HOME}/.local/commitlint"

read -ra tools <<<"${TOOLS:-}"

CURRENT_TOOL="unknown"

on_error() {
  local exit_code=$?
  echo "::error::Failed installing '${CURRENT_TOOL}' (exit code ${exit_code}) at line ${BASH_LINENO[0]}: ${BASH_COMMAND}" >&2
  exit "${exit_code}"
}
trap on_error ERR

wants() {
  [[ " ${tools[*]} " == *" $1 "* ]]
}

install_commitlint() {
  mkdir -p "${COMMITLINT_DIR}"
  npm install --prefix "${COMMITLINT_DIR}" --no-fund --no-audit \
    "@commitlint/cli@${COMMITLINT_VERSION}" \
    "@commitlint/config-conventional@${COMMITLINT_VERSION}"
}

install_checkov() {
  python3 -m pip install --quiet --user "checkov==${CHECKOV_VERSION}" ||
    python3 -m pip install --quiet --user --break-system-packages "checkov==${CHECKOV_VERSION}"
}

# --break-system-packages is the documented escape hatch for PEP 668 images; it is only reached
# when the plain --user install is refused.
install_pre_commit() {
  python3 -m pip install --quiet --user "pre-commit==${PRE_COMMIT_VERSION}" ||
    python3 -m pip install --quiet --user --break-system-packages "pre-commit==${PRE_COMMIT_VERSION}"
}

run_install() {
  local name="$1" fn="$2"
  CURRENT_TOOL="${name}"
  echo "==> Installing ${name}"
  "${fn}"
}

if wants commitlint; then run_install commitlint install_commitlint; fi
if wants checkov; then run_install checkov install_checkov; fi
if wants pre-commit; then run_install pre-commit install_pre_commit; fi
