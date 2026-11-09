#!/usr/bin/env bash
# Validate the pinned version of every requested tool and hash the result, so the binary cache key
# is stable for a given tool set and toolchain.
#
# Only the requested tools are validated. That is the whole point of the `tools` input: a workflow
# that needs the Terraform binary alone must not be forced to pin Checkov, Conftest and Infracost
# versions it will never use.
#
# Do not use the `wants x && require_version ...` one-liner form below. When `wants` returns 1 the
# whole list returns 1, and because it is the final command of the statement `set -e` treats that
# as a step failure. Use explicit `if` blocks.
set -euo pipefail

SUPPORTED="terraform tflint terraform-docs checkov conftest infracost commitlint pre-commit node"

read -ra requested <<<"${TOOLS:-}"
if [[ ${#requested[@]} -eq 0 ]]; then
  echo "::error::No tools requested. Set the 'tools' input to at least one of: ${SUPPORTED}." >&2
  exit 1
fi

# Deduplicate while preserving the caller's order, so listing a tool twice does not change the
# resolved set.
tools=()
for tool in "${requested[@]}"; do
  if [[ " ${SUPPORTED} " != *" ${tool} "* ]]; then
    echo "::error::Unsupported tool '${tool}'. Supported tools are: ${SUPPORTED}." >&2
    exit 1
  fi
  if [[ " ${tools[*]-} " != *" ${tool} "* ]]; then
    tools+=("${tool}")
  fi
done

wants() {
  [[ " ${tools[*]} " == *" $1 "* ]]
}

# commitlint is an npm package, so asking for it implies Node even when the caller did not say so.
if wants commitlint && ! wants node; then
  tools+=("node")
fi

# Sorted for the cache key only, so a cosmetic reordering of the list is not a cache miss.
sorted_tools="$(printf '%s\n' "${tools[@]}" | sort | tr '\n' ' ')"
sorted_tools="${sorted_tools% }"

require_version() {
  local tool_name="$1" version="$2"

  if [[ -z "${version//[[:space:]]/}" ]]; then
    echo "::error::${tool_name} version must be specified when ${tool_name} is requested." >&2
    exit 1
  fi

  if [[ ${version} == "latest" ]]; then
    echo "::error::${tool_name} version must be pinned; 'latest' is not supported." >&2
    exit 1
  fi
}

# Versions of tools that were not requested are blanked, so an unrelated default changing cannot
# invalidate the cache key.
version_for() {
  local tool="$1" value="$2"
  if wants "${tool}"; then
    printf '%s' "${value}"
  fi
}

node_version="$(version_for node "${INPUT_NODE_VERSION}")"
terraform_version="$(version_for terraform "${INPUT_TERRAFORM_VERSION}")"
tflint_version="$(version_for tflint "${INPUT_TFLINT_VERSION}")"
terraform_docs_version="$(version_for terraform-docs "${INPUT_TERRAFORM_DOCS_VERSION}")"
checkov_version="$(version_for checkov "${INPUT_CHECKOV_VERSION}")"
conftest_version="$(version_for conftest "${INPUT_CONFTEST_VERSION}")"
infracost_version="$(version_for infracost "${INPUT_INFRACOST_VERSION}")"
commitlint_version="$(version_for commitlint "${INPUT_COMMITLINT_VERSION}")"
pre_commit_version="$(version_for pre-commit "${INPUT_PRE_COMMIT_VERSION}")"

# install-terraform-tools only runs actions/setup-node when install-tools is true, so in
# bring-your-own-runner mode Node is verified on PATH instead and does not need a pinned version.
if [[ ${INSTALL_TOOLS} == "true" ]]; then
  if wants node; then require_version "Node.js" "${node_version}"; fi
  if wants terraform; then require_version "Terraform" "${terraform_version}"; fi
  if wants tflint; then require_version "TFLint" "${tflint_version}"; fi
  if wants terraform-docs; then require_version "terraform-docs" "${terraform_docs_version}"; fi
  if wants checkov; then require_version "Checkov" "${checkov_version}"; fi
  if wants conftest; then require_version "Conftest" "${conftest_version}"; fi
  if wants infracost; then require_version "Infracost" "${infracost_version}"; fi
  if wants commitlint; then require_version "commitlint" "${commitlint_version}"; fi
  if wants pre-commit; then require_version "pre-commit" "${pre_commit_version}"; fi
fi

versions_hash="$(
  printf '%s\n' \
    "${sorted_tools}" \
    "${node_version}" \
    "${terraform_version}" \
    "${tflint_version}" \
    "${terraform_docs_version}" \
    "${checkov_version}" \
    "${conftest_version}" \
    "${infracost_version}" \
    "${commitlint_version}" \
    "${pre_commit_version}" |
    sha256sum | cut -d' ' -f1
)"

needs_node="false"
if wants node; then
  needs_node="true"
fi

{
  echo "tools=${tools[*]}"
  echo "needs-node=${needs_node}"
  echo "node=${node_version}"
  echo "terraform=${terraform_version}"
  echo "tflint=${tflint_version}"
  echo "terraform-docs=${terraform_docs_version}"
  echo "checkov=${checkov_version}"
  echo "conftest=${conftest_version}"
  echo "infracost=${infracost_version}"
  echo "commitlint=${commitlint_version}"
  echo "pre-commit=${pre_commit_version}"
  echo "versions-hash=${versions_hash}"
} >>"${GITHUB_OUTPUT}"

echo "Requested toolchain:"
for tool in "${tools[@]}"; do
  case "${tool}" in
  node) printf '  %-15s %s\n' "${tool}" "${node_version}" ;;
  terraform) printf '  %-15s %s\n' "${tool}" "${terraform_version}" ;;
  tflint) printf '  %-15s %s\n' "${tool}" "${tflint_version}" ;;
  terraform-docs) printf '  %-15s %s\n' "${tool}" "${terraform_docs_version}" ;;
  checkov) printf '  %-15s %s\n' "${tool}" "${checkov_version}" ;;
  conftest) printf '  %-15s %s\n' "${tool}" "${conftest_version}" ;;
  infracost) printf '  %-15s %s\n' "${tool}" "${infracost_version}" ;;
  commitlint) printf '  %-15s %s\n' "${tool}" "${commitlint_version}" ;;
  pre-commit) printf '  %-15s %s\n' "${tool}" "${pre_commit_version}" ;;
  esac
done
