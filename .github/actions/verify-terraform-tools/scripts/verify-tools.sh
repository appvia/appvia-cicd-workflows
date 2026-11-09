#!/usr/bin/env bash
# Bring-your-own-runner mode (install-tools: false). Nothing is installed, so fail fast with one
# message naming every missing tool rather than letting a gap surface mid-run as a "command not
# found" inside a Terraform step.
set -euo pipefail

read -ra tools <<<"${REQUIRED_TOOLS}"

missing=()
for tool in "${tools[@]}"; do
  if command -v "${tool}" >/dev/null 2>&1; then
    printf 'found   %-12s %s\n' "${tool}" "$(command -v "${tool}")"
  else
    missing+=("${tool}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::install-tools is false but these tools are not on PATH: ${missing[*]}. Either install them in the runner image or set install-tools to true."
  exit 1
fi

echo "All required tools are present."
