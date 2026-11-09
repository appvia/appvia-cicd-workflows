#!/usr/bin/env bash
set -euo pipefail

# Verify the text file was generated, provide a fallback if it crashed before writing
if [[ ! -f "${TEXT_OUTPUT}" ]]; then
  echo "Checkov text output not found; see workflow logs." >"${TEXT_OUTPUT}"
fi

# Check for SARIF and set the required GitHub output for the next step
if [[ -f "${SARIF_OUTPUT}" ]]; then
  echo "sarif-present=true" >>"${GITHUB_OUTPUT}"
else
  echo "sarif-present=false" >>"${GITHUB_OUTPUT}"
fi
