#!/usr/bin/env bash
# Verify a Rego policy directory, then test the Terraform plan JSON against it.
#
# The step never exits non-zero: the caller reads the `outcome` output instead, so a policy failure
# is reported in the pull-request comment rather than aborting the remaining checks.
set -euo pipefail

report() {
  echo "outcome=$1" >>"${GITHUB_OUTPUT}"
  exit 0
}

if [[ ! -d ${POLICIES_DIR} ]] || [[ -z "$(find "${POLICIES_DIR}" -type f -name '*.rego' -print -quit)" ]]; then
  echo "No .rego policies under '${POLICIES_DIR}'; skipping."
  report "skipped"
fi

set +e
conftest verify --policy "${POLICIES_DIR}" 2>&1 | tee "${GITHUB_WORKSPACE}/${VERIFY_OUTPUT}"
verify_exit=${PIPESTATUS[0]}
set -e

# A syntax error or failing policy unit test means the policies cannot be trusted, so do not go on
# to report a misleading pass from `conftest test`.
if [[ ${verify_exit} -ne 0 ]]; then
  echo "::error::conftest verify failed for '${POLICIES_DIR}'"
  report "failure"
fi

test_output_path="${GITHUB_WORKSPACE}/${TEST_OUTPUT}"
set +e
conftest test --policy "${POLICIES_DIR}" --all-namespaces --no-color --output json "${PLAN_JSON}" >"${test_output_path}"
set -e
cat "${test_output_path}"

failures="$(jq '[.[] | select(.failures != null) | .failures[]] | length' "${test_output_path}" 2>/dev/null || echo "-1")"
if [[ ${failures} == "-1" ]]; then
  echo "::error::conftest test produced no parseable JSON for '${POLICIES_DIR}'"
  report "failure"
fi

if [[ ${failures} -gt 0 ]]; then
  echo "::error::${failures} policy failure(s) from '${POLICIES_DIR}'"
  report "failure"
fi

echo "No policy failures from '${POLICIES_DIR}'."
report "success"
