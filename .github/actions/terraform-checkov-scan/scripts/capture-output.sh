#!/usr/bin/env bash
# Flatten Checkov's text and SARIF outputs into the fixed filenames the PR comment and upload expect.
# Checkov's exact filenames vary by version, so resolve them by glob rather than hard-coding.
set -euo pipefail

text_file="$(find "${TEXT_DIR}" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | head -n1 || true)"
if [[ -n ${text_file} ]]; then
  cp "${text_file}" "${TEXT_OUTPUT}"
else
  echo "Checkov text output not found; see workflow logs." >"${TEXT_OUTPUT}"
fi

sarif_file="$(find "${SARIF_DIR}" -maxdepth 1 -type f -name '*.sarif' 2>/dev/null | head -n1 || true)"
if [[ -n ${sarif_file} ]]; then
  cp "${sarif_file}" "${SARIF_OUTPUT}"
  echo "sarif-present=true" >>"${GITHUB_OUTPUT}"
else
  echo "sarif-present=false" >>"${GITHUB_OUTPUT}"
fi
