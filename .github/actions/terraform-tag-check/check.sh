#!/usr/bin/env bash
#
# Checks the resources being created or updated in one or more terraform plan JSON files
# (terraform show -json) against the tagging policy. The rules live in the policy file and
# the evaluation in check.py; this script only makes sure its dependencies are present.
#
# Required environment variables:
#   PLAN_JSON   - a plan JSON file, or a directory searched recursively for *.json files
#   POLICY_FILE - the tagging policy (YAML), see config/tagging-policy.yaml
# Optional environment variables:
#   TAG_POLICY_MODE     - enforce (default) or audit; audit reports everything as a warning
#                         and never fails
#   GITHUB_OUTPUT       - receives violations=<count> and result=<success|failure|warning>
#   GITHUB_STEP_SUMMARY - receives a markdown report
#
# Exit codes: 0 compliant (or audit mode), 1 policy violations, 2 usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG_POLICY_MODE="${TAG_POLICY_MODE:-enforce}"
export TAG_POLICY_MODE

case "${TAG_POLICY_MODE}" in
  enforce) LEVEL="error" ;;
  audit) LEVEL="warning" ;;
  *)
    echo "::error title=Tag Policy::TAG_POLICY_MODE must be enforce or audit, got: ${TAG_POLICY_MODE}"
    exit 2
    ;;
esac

# In audit mode a failure is reported as a warning, and never fails the step
finish() {
  local status="$1" result="success"
  if [[ "${status}" -ne 0 ]]; then
    if [[ "${TAG_POLICY_MODE}" == "audit" ]]; then
      result="warning"
      echo "Audit mode: the tagging policy is not enforced, so the check is not failing the job"
      status=0
    else
      result="failure"
    fi
  fi
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "result=${result}" >> "${GITHUB_OUTPUT}"
  fi
  exit "${status}"
}

if ! command -v python3 > /dev/null 2>&1; then
  echo "::${LEVEL} title=Tag Policy::python3 is required but was not found"
  finish 2
fi

# GitHub-hosted runners ship PyYAML; install it for runners that do not
if ! python3 -c 'import yaml' > /dev/null 2>&1; then
  if ! PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --quiet --disable-pip-version-check --user 'pyyaml>=6,<7'; then
    echo "::${LEVEL} title=Tag Policy::PyYAML is required and could not be installed"
    finish 2
  fi
fi

status=0
python3 "${SCRIPT_DIR}/check.py" || status=$?
finish "${status}"
