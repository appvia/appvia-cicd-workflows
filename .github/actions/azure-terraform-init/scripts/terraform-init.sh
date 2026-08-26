#!/usr/bin/env bash
# Run terraform init against the azurerm backend using an already-resolved state key.
set -euo pipefail

if [[ -n ${OUTPUT_FILE} ]]; then
  log_file="${GITHUB_WORKSPACE}/${OUTPUT_FILE}"
else
  log_file="${RUNNER_TEMP}/terraform-init-output.txt"
fi

args=(
  -input=false
  -reconfigure
  -no-color
  "-backend-config=resource_group_name=${BACKEND_RESOURCE_GROUP_NAME}"
  "-backend-config=storage_account_name=${BACKEND_STORAGE_ACCOUNT_NAME}"
  "-backend-config=container_name=${BACKEND_CONTAINER_NAME}"
  "-backend-config=key=${TF_STATE_KEY}"
)

if [[ -n ${EXTRA_ARGS} ]]; then
  read -ra extra_args <<<"${EXTRA_ARGS}"
  args+=("${extra_args[@]}")
fi

set +e
terraform -chdir="${WORKING_DIR}" init "${args[@]}" 2>&1 | tee "${log_file}"
init_exit=${PIPESTATUS[0]}
set -e

exit "${init_exit}"
