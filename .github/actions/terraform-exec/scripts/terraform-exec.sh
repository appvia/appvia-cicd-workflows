#!/usr/bin/env bash
# Run a single terraform plan/apply/destroy, capture its real exit code through the tee pipeline,
# and optionally convert the plan to JSON and delete or retain the binary.
#
# The binary plan embeds state, so callers choose whether it is removed after JSON conversion.
set -euo pipefail

args=(-input=false)

# Colour is on by default; opt out when the output is consumed as plain text (log shipping,
# PR comments) rather than read in the Actions UI.
if [[ ${DISABLE_COLOR} == "true" ]]; then
  args+=(-no-color)
fi

# export GITHUB_TOKEN if GH_APP_TOKEN is defined as an environment variable for GitHub App authentication
if [[ -n ${GH_APP_TOKEN:-} ]]; then
  export GITHUB_TOKEN="${GH_APP_TOKEN}"
fi

if [[ -n ${PARALLELISM} ]] && [[ ${COMMAND} != "apply" || -z ${PLAN_FILE} ]]; then
  args+=("-parallelism=${PARALLELISM}")
fi

# Arrays, not a string: an unquoted "-var-file=x" expansion would word-split (SC2086).
if [[ -n ${COMMON_VAR_FILE} ]] && [[ ${COMMAND} != "apply" || -z ${PLAN_FILE} ]]; then
  args+=("-var-file=${COMMON_VAR_FILE}")
fi
if [[ -n ${VAR_FILE} ]] && [[ ${COMMAND} != "apply" || -z ${PLAN_FILE} ]]; then
  args+=("-var-file=${VAR_FILE}")
fi

case "${COMMAND}" in
  plan)
    if [[ -n ${OUT_FILE} ]]; then
      args+=("-out=${OUT_FILE}")
    fi
    if [[ ${DETAILED_EXITCODE} == "true" ]]; then
      args+=(-detailed-exitcode)
    fi
    ;;
  apply | destroy)
    args+=(-auto-approve)
    if [[ ${COMMAND} == "apply" && -n ${PLAN_FILE} ]]; then
      args+=("${PLAN_FILE}")
    fi
    ;;
  *)
    echo "::error::command must be one of plan, apply, destroy (got '${COMMAND}')"
    exit 1
    ;;
esac

if [[ -n ${OUTPUT_FILE} ]]; then
  log_file="${GITHUB_WORKSPACE}/${OUTPUT_FILE}"
else
  log_file="${RUNNER_TEMP}/terraform-${COMMAND}.log"
fi

set +e
terraform -chdir="${WORKING_DIR}" "${COMMAND}" "${args[@]}" 2>&1 | tee "${log_file}"
exit_code=${PIPESTATUS[0]}
set -e

# With -detailed-exitcode, 2 means "changes present" and is not an error; without it, any non-zero
# exit is a failure.
if [[ ${DETAILED_EXITCODE} == "true" ]]; then
  [[ ${exit_code} -eq 0 || ${exit_code} -eq 2 ]] && failed=false || failed=true
else
  [[ ${exit_code} -ne 0 ]] && failed=true || failed=false
fi

json_outcome="skipped"
json_path=""
if [[ ${CONVERT_TO_JSON} == "true" && -n ${OUT_FILE} && ${failed} == "false" ]]; then
  json_path="${WORKING_DIR}/${JSON_FILE}"
  if terraform -chdir="${WORKING_DIR}" show -json "${OUT_FILE}" >"${json_path}"; then
    json_outcome="success"
  else
    json_outcome="failure"
    json_path=""
  fi
  if [[ ${DELETE_PLAN} == "true" ]]; then
    rm -f "${WORKING_DIR}/${OUT_FILE}"
  fi
fi

{
  echo "exit-code=${exit_code}"
  echo "failed=${failed}"
  echo "json-outcome=${json_outcome}"
  echo "json-path=${json_path}"
} >>"${GITHUB_OUTPUT}"

echo "terraform ${COMMAND} exited ${exit_code} (failed=${failed}, json=${json_outcome})"

if [[ ${FAIL_ON_ERROR} == "true" && ${failed} == "true" ]]; then
  exit "${exit_code}"
fi
exit 0
