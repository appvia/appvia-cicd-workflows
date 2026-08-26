#!/usr/bin/env bash
# Resolve the state key and var-files for an environment, applying the repository conventions
# (<environment>.tfstate, environments/<environment>.tfvars) when no override is supplied.
#
# Fail here rather than inside terraform: a missing var-file surfaces as a plan error (exit 1) and
# looks like real infrastructure breakage.
#
# Do not use the `[ -z "$X" ] && X=...` one-liner form below — it returns 1 when the variable is
# already set, which `set -e` treats as a step failure. Use explicit `if` blocks.
set -euo pipefail

state_key="${STATE_KEY_INPUT}"
if [[ -z ${state_key} ]]; then
  state_key="${ENVIRONMENT}.tfstate"
fi

var_file="${VAR_FILE_INPUT}"
if [[ -z ${var_file} ]]; then
  var_file="environments/${ENVIRONMENT}.tfvars"
fi
if [[ ! -f "${WORKING_DIR}/${var_file}" ]]; then
  echo "::error::Var-file '${WORKING_DIR}/${var_file}' not found for environment '${ENVIRONMENT}'."
  exit 1
fi

# The common var-file is genuinely optional — resolve it once here so callers only have to test
# whether the variable is set.
common_var_file=""
if [[ -n ${COMMON_VAR_FILE_INPUT} && -f "${WORKING_DIR}/${COMMON_VAR_FILE_INPUT}" ]]; then
  common_var_file="${COMMON_VAR_FILE_INPUT}"
fi

{
  echo "TF_STATE_KEY=${state_key}"
  echo "TF_VAR_FILE=${var_file}"
  echo "TF_COMMON_VAR_FILE=${common_var_file}"
} >>"${GITHUB_ENV}"

{
  echo "tf-state-key=${state_key}"
  echo "tf-var-file=${var_file}"
  echo "tf-common-var-file=${common_var_file}"
} >>"${GITHUB_OUTPUT}"

echo "State key:         ${state_key}"
echo "Var-file:          ${var_file}"
echo "Common var-file:   ${common_var_file:-<none>}"
