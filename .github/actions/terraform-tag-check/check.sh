#!/usr/bin/env bash
#
# Checks the resources being created or updated in one or more terraform plan JSON files
# (terraform show -json) against the tagging policy. The rules live in the policy file and
# the evaluation in check.py; this script only makes sure its dependencies are present.
#
# Required environment variables:
#   PLAN_JSON   - a plan JSON file, or a directory searched recursively for *.json files
#   POLICY_FILE - the tagging policy (YAML), see config/tagging-policy.yaml
# Optional environment variables (set by the runner):
#   GITHUB_OUTPUT       - receives violations=<count>
#   GITHUB_STEP_SUMMARY - receives a markdown report
#
# Exit codes: 0 compliant, 1 policy violations, 2 usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 > /dev/null 2>&1; then
  echo "::error title=Tag Policy::python3 is required but was not found"
  exit 2
fi

# GitHub-hosted runners ship PyYAML; install it for runners that do not
if ! python3 -c 'import yaml' > /dev/null 2>&1; then
  PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --quiet --disable-pip-version-check --user 'pyyaml>=6,<7' \
    || { echo "::error title=Tag Policy::PyYAML is required and could not be installed"; exit 2; }
fi

exec python3 "${SCRIPT_DIR}/check.py"
