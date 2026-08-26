#!/usr/bin/env bash
# Install the complete toolchain with checksum verification. All-or-nothing: there are no per-tool
# toggles, because the binary cache is keyed on the whole version set.
#
# Everything lands under ~/.local so a single cache entry covers binaries, the commitlint npm tree
# and the pip --user tree:
#   ~/.local/tools      terraform, tflint, conftest, infracost
#   ~/.local/commitlint node_modules for @commitlint/cli
#   ~/.local/bin        pre-commit (pip --user)
set -euo pipefail

TOOLS_DIR="${HOME}/.local/tools"
COMMITLINT_DIR="${HOME}/.local/commitlint"
mkdir -p "${TOOLS_DIR}" "${COMMITLINT_DIR}"

download() {
  curl --fail --silent --show-error --location "$1" --output "$2"
}

# sha256sum -c resolves filenames relative to cwd, so each archive must be downloaded using the
# exact filename that appears in the checksum file.
verify_against_checksums() {
  local checksum_file="$1" archive="$2"
  (cd "${RUNNER_TEMP}" && grep "${archive}" "${checksum_file}" | sha256sum -c -)
}

install_terraform() {
  local archive="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  local base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"

  download "${base}/${archive}" "${RUNNER_TEMP}/${archive}"
  download "${base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" "${RUNNER_TEMP}/terraform_SHA256SUMS"
  verify_against_checksums "terraform_SHA256SUMS" "${archive}"
  unzip -q -o "${RUNNER_TEMP}/${archive}" -d "${TOOLS_DIR}" terraform
}

install_tflint() {
  local archive="tflint_linux_amd64.zip"
  local base="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}"

  download "${base}/${archive}" "${RUNNER_TEMP}/${archive}"
  download "${base}/checksums.txt" "${RUNNER_TEMP}/tflint_checksums.txt"
  verify_against_checksums "tflint_checksums.txt" "${archive}"
  unzip -q -o "${RUNNER_TEMP}/${archive}" -d "${TOOLS_DIR}" tflint
}

install_conftest() {
  local archive="conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz"
  local base="https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}"

  download "${base}/${archive}" "${RUNNER_TEMP}/${archive}"
  download "${base}/checksums.txt" "${RUNNER_TEMP}/conftest_checksums.txt"
  verify_against_checksums "conftest_checksums.txt" "${archive}"
  tar -xz -C "${TOOLS_DIR}" -f "${RUNNER_TEMP}/${archive}" conftest
}

# Infracost publishes a per-asset .sha256 file carrying both hash and original filename.
install_infracost() {
  local archive="infracost-linux-amd64.tar.gz"
  local base="https://github.com/infracost/infracost/releases/download/v${INFRACOST_VERSION}"

  download "${base}/${archive}" "${RUNNER_TEMP}/${archive}"
  download "${base}/${archive}.sha256" "${RUNNER_TEMP}/${archive}.sha256"
  (cd "${RUNNER_TEMP}" && sha256sum -c "${archive}.sha256")
  tar -xz -C "${RUNNER_TEMP}" -f "${RUNNER_TEMP}/${archive}"
  mv "${RUNNER_TEMP}/infracost-linux-amd64" "${TOOLS_DIR}/infracost"
  chmod +x "${TOOLS_DIR}/infracost"
}

install_commitlint() {
  npm install --prefix "${COMMITLINT_DIR}" --no-fund --no-audit \
    "@commitlint/cli@${COMMITLINT_VERSION}" \
    "@commitlint/config-conventional@${COMMITLINT_VERSION}"
}

# --break-system-packages is the documented escape hatch for PEP 668 images; it is only reached
# when the plain --user install is refused.
install_pre_commit() {
  python3 -m pip install --quiet --user "pre-commit==${PRE_COMMIT_VERSION}" ||
    python3 -m pip install --quiet --user --break-system-packages "pre-commit==${PRE_COMMIT_VERSION}"
}

install_terraform
install_tflint
install_conftest
install_infracost
install_commitlint
install_pre_commit

echo "Installed toolchain into ${HOME}/.local"
