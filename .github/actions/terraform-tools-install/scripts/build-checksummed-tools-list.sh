#!/usr/bin/env bash
# Build the JSON tool list consumed by install-checksummed-tools, one entry per
# checksummed-binary tool actually requested in $TOOLS. commitlint (npm) and checkov/pre-commit
# (pip) are not binary downloads and are installed separately by the caller - see
# install-tools.sh.
#
# Each entry is built as JSON via jq -n, safe against any character *_VERSION might contain.
set -euo pipefail

read -ra tools <<<"${TOOLS:-}"

wants() {
  [[ " ${tools[*]} " == *" $1 "* ]]
}

entries=()

json_entry() {
  jq -n \
    --arg name "$1" --arg version "$2" --arg url "$3" --arg archive "$4" --arg binary "$5" \
    --arg checksum_url "${6:-}" --arg archive_member "${7:-}" \
    --arg checksum_order_url "${8:-}" --arg checksum_algorithm "${9:-}" \
    '{name: $name, version: $version, url: $url, archive: $archive, binary: $binary}
     + (if $checksum_url != "" then {"checksum-url": $checksum_url} else {} end)
     + (if $archive_member != "" then {"archive-member": $archive_member} else {} end)
     + (if $checksum_order_url != "" then {"checksum-order-url": $checksum_order_url} else {} end)
     + (if $checksum_algorithm != "" then {"checksum-algorithm": $checksum_algorithm} else {} end)'
}

if wants terraform; then
  entries+=("$(json_entry terraform "${TERRAFORM_VERSION}" \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    zip terraform \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS")")
fi

if wants tflint; then
  entries+=("$(json_entry tflint "${TFLINT_VERSION}" \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    zip tflint \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt")")
fi

if wants terraform-docs; then
  entries+=("$(json_entry terraform-docs "${TERRAFORM_DOCS_VERSION}" \
    "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-amd64.tar.gz" \
    tar.gz terraform-docs \
    "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}.sha256sum")")
fi

if wants conftest; then
  entries+=("$(json_entry conftest "${CONFTEST_VERSION}" \
    "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" \
    tar.gz conftest \
    "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/checksums.txt")")
fi

# Infracost's release asset is named infracost-linux-amd64 inside the archive; install it as
# "infracost" so callers don't need to know that detail.
if wants infracost; then
  entries+=("$(json_entry infracost "${INFRACOST_VERSION}" \
    "https://github.com/infracost/infracost/releases/download/v${INFRACOST_VERSION}/infracost-linux-amd64.tar.gz" \
    tar.gz infracost \
    "https://github.com/infracost/infracost/releases/download/v${INFRACOST_VERSION}/infracost-linux-amd64.tar.gz.sha256" \
    infracost-linux-amd64)")
fi

if wants yq; then
  if [[ -z ${YQ_VERSION:-} ]]; then
    echo "::error::yq requires yq-version." >&2
    exit 1
  fi
  yq_release_url="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}"
  entries+=("$(json_entry yq "${YQ_VERSION}" \
    "${yq_release_url}/yq_linux_amd64" \
    none yq \
    "${yq_release_url}/checksums" \
    "" \
    "${yq_release_url}/checksums_hashes_order" \
    "SHA-256")")
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  tools_json="[]"
else
  tools_json="$(printf '%s\n' "${entries[@]}" | jq -s '.')"
fi

{
  echo "tools<<TOOLS_EOF"
  echo "${tools_json}"
  echo "TOOLS_EOF"
} >>"${GITHUB_OUTPUT}"
