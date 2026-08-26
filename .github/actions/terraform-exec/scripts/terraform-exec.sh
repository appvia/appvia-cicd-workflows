#!/usr/bin/env bash
# Run a single terraform plan/apply/destroy, capture its real exit code through the tee pipeline,
# and optionally convert the plan to JSON and delete the binary.
#
# The binary plan embeds state, so it is removed as soon as the JSON exists — before any
# third-party tool touches the workspace and before any artifact is uploaded.
set -euo pipefail

args=(-no-color -input=false)

if [[ -n ${PARALLELISM} ]]; then
  args+=("-parallelism=${PARALLELISM}")
fi

# Arrays, not a string: an unquoted "-var-file=x" expansion would word-split (SC2086).
if [[ -n ${COMMON_VAR_FILE} ]]; then
  args+=("-var-file=${COMMON_VAR_FILE}")
fi
if [[ -n ${VAR_FILE} ]]; then
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
    ;;
  *)
    echo "::error::command must be one of plan, apply, destroy (got '${COMMAND}')"
    exit 1
    ;;
esac

# Deliberate word splitting: extra-args is an operator-supplied argument string, not data.
if [[ -n ${EXTRA_ARGS} ]]; then
  read -ra extra_args <<<"${EXTRA_ARGS}"
  args+=("${extra_args[@]}")
fi

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
  rm -f "${WORKING_DIR}/${OUT_FILE}"
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
