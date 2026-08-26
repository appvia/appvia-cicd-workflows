#!/usr/bin/env bash
# bridgecrewio/checkov-action takes newline-separated var_file paths, each relative to the scanned
# directory. Include the common and environment var-files only when they actually exist.
set -euo pipefail

var_files=()
if [[ -n ${COMMON_VAR_FILE} && -f "${WORKING_DIR}/${COMMON_VAR_FILE}" ]]; then
  var_files+=("${COMMON_VAR_FILE}")
fi
if [[ -n ${VAR_FILE} && -f "${WORKING_DIR}/${VAR_FILE}" ]]; then
  var_files+=("${VAR_FILE}")
fi

{
  echo "var-file<<EOF_VAR_FILE"
  if [[ ${#var_files[@]} -gt 0 ]]; then
    printf '%s\n' "${var_files[@]}"
  fi
  echo "EOF_VAR_FILE"
} >>"${GITHUB_OUTPUT}"

echo "Checkov var-files: ${var_files[*]:-<none>}"
