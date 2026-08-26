#!/usr/bin/env bash
# Run every hook configured by the consumer and capture its output for the workflow summary.
# The caller uses the outcome output to report hook failures without stopping later checks.
#
# Hook failures are exposed through the `outcome` output so the caller can report them alongside
# the standalone checks in the pull-request comment; a missing configuration remains fatal.
set -euo pipefail

if [[ ! -f ${CONFIG_FILE} ]]; then
  echo "::error::Pre-commit configuration '${CONFIG_FILE}' was not found."
  echo "outcome=failure" >>"${GITHUB_OUTPUT}"
  exit 1
fi

set +e
pre-commit run --all-files --show-diff-on-failure --color never --config "${CONFIG_FILE}" 2>&1 |
  tee "${GITHUB_WORKSPACE}/${OUTPUT_FILE}"
exit_code=${PIPESTATUS[0]}
set -e

if [[ ${exit_code} -eq 0 ]]; then
  echo "outcome=success" >>"${GITHUB_OUTPUT}"
else
  echo "::error::pre-commit reported failures"
  echo "outcome=failure" >>"${GITHUB_OUTPUT}"
fi
