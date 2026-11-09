#!/usr/bin/env bash
# Export the Terraform CLI settings that are invariant across every job in every Terraform
# workflow, regardless of whether the tools on PATH were installed by install-terraform-tools or
# already provided by the runner image.
#
# PATH and NODE_PATH are deliberately not exported here: those describe where
# install-terraform-tools put its binaries, which is an installation detail, not a generic
# Terraform environment setting. A bring-your-own-runner caller that never runs
# install-terraform-tools still wants TF_IN_AUTOMATION and the plugin cache directory.
#
# Azure settings deliberately live in the azure-login action instead: this action must remain
# usable by a workflow that never touches Azure.
set -euo pipefail

{
  echo "TF_PLUGIN_CACHE_DIR=${HOME}/.terraform.d/plugin-cache"
  echo "TF_INPUT=0"
  echo "TF_IN_AUTOMATION=true"
} >>"${GITHUB_ENV}"

# Only export TF_LOG when a level was requested: an empty TF_LOG is not the same as an unset one
# for some Terraform versions.
if [[ -n ${TERRAFORM_LOG_LEVEL:-} ]]; then
  echo "TF_LOG=${TERRAFORM_LOG_LEVEL}" >>"${GITHUB_ENV}"
fi

mkdir -p "${HOME}/.terraform.d/plugin-cache"
