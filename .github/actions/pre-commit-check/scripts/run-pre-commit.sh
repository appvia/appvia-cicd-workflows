#!/usr/bin/env bash
# Run every hook configured by the consumer and capture its output for the workflow summary.
# The caller marks this step continue-on-error so a non-zero exit here surfaces as a failed step
# in the UI without stopping later checks. Hook failures are also exposed through the `outcome`
# output so the caller can report them alongside the standalone checks in the pull-request comment;
# a missing configuration is likewise fatal.
set -euo pipefail

if [[ ! -f ${CONFIG_FILE} ]]; then
  echo "::error::Pre-commit configuration '${CONFIG_FILE}' was not found."
  echo "outcome=failure" >>"${GITHUB_OUTPUT}"
  exit 1
fi

target="${GITHUB_WORKSPACE}/${OUTPUT_FILE}"

if [[ ${INSTALL_ONLY:-false} == "true" ]]; then
  # Only sets up each hook's environment (pip/npm/etc. install) — no hook command is ever
  # executed, so neither a context-dependent hook (e.g. no-commit-to-branch, which fails off a
  # feature branch) nor a modifying hook (terraform_fmt, terraform_docs, ...) can run at all.
  set +e
  pre-commit install-hooks --color never --config "${CONFIG_FILE}" 2>&1 | tee "${target}"
  exit_code=${PIPESTATUS[0]}
  set -e
else
  set +e
  pre-commit run --all-files --show-diff-on-failure --color never --config "${CONFIG_FILE}" 2>&1 |
    tee "${target}"
  exit_code=${PIPESTATUS[0]}
  set -e
fi

if [[ ${exit_code} -eq 0 ]]; then
  echo "outcome=success" >>"${GITHUB_OUTPUT}"
else
  echo "::error::pre-commit reported failures"
  echo "outcome=failure" >>"${GITHUB_OUTPUT}"
  exit 1
fi
