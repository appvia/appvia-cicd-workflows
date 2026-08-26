#!/usr/bin/env bash
# Put the installed toolchain on PATH and export the Terraform/Azure settings that are invariant
# across every job in every Azure workflow, so the callers only declare what actually varies.
set -euo pipefail

{
  echo "${HOME}/.local/bin"
  echo "${HOME}/.local/tools"
  echo "${HOME}/.local/commitlint/node_modules/.bin"
} >>"${GITHUB_PATH}"

{
  echo "NODE_PATH=${HOME}/.local/commitlint/node_modules"
  echo "TF_PLUGIN_CACHE_DIR=${HOME}/.terraform.d/plugin-cache"
  echo "ARM_USE_OIDC=true"
  echo "ARM_USE_AZUREAD=true"
  echo "TF_INPUT=0"
  echo "TF_IN_AUTOMATION=true"
} >>"${GITHUB_ENV}"

# Only export TF_LOG when a level was requested: an empty TF_LOG is not the same as an unset one
# for some Terraform versions.
if [[ -n ${TERRAFORM_LOG_LEVEL:-} ]]; then
  echo "TF_LOG=${TERRAFORM_LOG_LEVEL}" >>"${GITHUB_ENV}"
fi

mkdir -p "${HOME}/.terraform.d/plugin-cache"
