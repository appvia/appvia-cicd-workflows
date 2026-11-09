#!/usr/bin/env bash
# Run terraform init against the azurerm backend using an already-resolved state key.
set -euo pipefail

# Fail with a named message rather than letting terraform report a confusing backend error. A blank
# value almost always means the secret was never created on the GitHub Environment the job entered.
missing=()
if [[ -z ${AZURE_STORAGE_RESOURCE_GROUP_NAME//[[:space:]]/} ]]; then missing+=("AZURE_STORAGE_RESOURCE_GROUP_NAME"); fi
if [[ -z ${AZURE_STORAGE_ACCOUNT_NAME//[[:space:]]/} ]]; then missing+=("AZURE_STORAGE_ACCOUNT_NAME"); fi
if [[ -z ${AZURE_STORAGE_CONTAINER_NAME//[[:space:]]/} ]]; then missing+=("AZURE_STORAGE_CONTAINER_NAME"); fi
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::Terraform backend configuration is missing: ${missing[*]}. Check the calling workflow passes secrets: inherit and that the secrets exist on the GitHub Environment the job entered."
  exit 1
fi

if [[ -n ${OUTPUT_FILE} ]]; then
  log_file="${GITHUB_WORKSPACE}/${OUTPUT_FILE}"
else
  log_file="${RUNNER_TEMP}/terraform-init-output.txt"
fi

args=(
  -input=false
  -reconfigure
  "-backend-config=resource_group_name=${AZURE_STORAGE_RESOURCE_GROUP_NAME}"
  "-backend-config=storage_account_name=${AZURE_STORAGE_ACCOUNT_NAME}"
  "-backend-config=container_name=${AZURE_STORAGE_CONTAINER_NAME}"
  "-backend-config=key=${TF_STATE_KEY}"
)

if [[ -n ${AZURE_STORAGE_SUBSCRIPTION_ID:-} ]]; then
  args+=("-backend-config=subscription_id=${AZURE_STORAGE_SUBSCRIPTION_ID}")
fi

# export GITHUB_TOKEN if GH_APP_TOKEN is defined as an environment variable for GitHub App authentication
if [[ -n ${GH_APP_TOKEN:-} ]]; then
  export GITHUB_TOKEN="${GH_APP_TOKEN}"
fi

# Terraform 1.15 evaluates variables marked `const = true` while loading configuration, so a module
# `source` or `version` can reference one — but only when the values are supplied at init time.
# OpenTofu 1.8 does the same for ordinary variables and locals. Older versions reject the flags
# outright, so probe the binary rather than assuming, and carry on quietly when unsupported.
supports_init_var_files() {
  local banner product major minor

  banner="$(terraform -chdir="${WORKING_DIR}" version 2>/dev/null | head -n1)" || return 1

  if [[ ${banner} =~ ^OpenTofu\ v([0-9]+)\.([0-9]+) ]]; then
    product="OpenTofu"
  elif [[ ${banner} =~ ^Terraform\ v([0-9]+)\.([0-9]+) ]]; then
    product="Terraform"
  else
    return 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"

  if [[ ${product} == "OpenTofu" ]]; then
    ((major > 1 || (major == 1 && minor >= 8)))
  else
    ((major > 1 || (major == 1 && minor >= 15)))
  fi
}

if supports_init_var_files; then
  # Common first so the environment file wins on any overlapping key, matching the argument order
  # used for plan and apply.
  if [[ -n ${TF_COMMON_VAR_FILE:-} ]]; then
    args+=("-var-file=${TF_COMMON_VAR_FILE}")
  fi
  if [[ -n ${TF_VAR_FILE:-} ]]; then
    args+=("-var-file=${TF_VAR_FILE}")
  fi
else
  echo "::notice::This Terraform version does not accept -var-file during init, so var-files were not passed. Upgrade to Terraform 1.15 or OpenTofu 1.8 to reference variables from module sources."
fi

# Colour is on by default; opt out when the output is consumed as plain text.
if [[ ${DISABLE_COLOR} == "true" ]]; then
  args+=(-no-color)
fi

set +e
terraform -chdir="${WORKING_DIR}" init "${args[@]}" 2>&1 | tee "${log_file}"
init_exit=${PIPESTATUS[0]}
set -e

exit "${init_exit}"
