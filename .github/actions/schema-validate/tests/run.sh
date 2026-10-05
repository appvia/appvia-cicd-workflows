#!/usr/bin/env bash
#
# Runs validate.py against each fixture, asserting the exit code, the number of violations
# and, optionally, a pattern expected in the output.
#
# Set PYTHON to an interpreter with pyyaml and jsonschema installed to skip building a venv.
#
# Usage: run.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="${TESTS_DIR}/.."
VALIDATE="${ACTION_DIR}/validate.py"
FIXTURES="${TESTS_DIR}/fixtures"
FAILED=0

if [[ -z "${PYTHON:-}" ]]; then
  VENV="$(mktemp -d)"
  trap 'rm -rf "${VENV}"' EXIT
  python3 -m venv "${VENV}"
  "${VENV}/bin/pip" install --quiet --disable-pip-version-check -r "${ACTION_DIR}/requirements.txt"
  PYTHON="${VENV}/bin/python"
fi

# expect <name> <schema> <files> <exit code> <errors or "-"> [pattern] [GITHUB_WORKSPACE]
expect() {
  local name="$1" schema="$2" files="$3" want_exit="$4" want_errors="$5" pattern="${6:-}" workspace="${7:-}"
  local work output got_exit got_errors
  work="$(mktemp -d)"
  set +e
  output="$(cd "${FIXTURES}" && SCHEMA_FILE="${schema}" FILES="${files}" GITHUB_WORKSPACE="${workspace}" GITHUB_OUTPUT="${work}/output" \
    GITHUB_STEP_SUMMARY="${work}/summary" "${PYTHON}" "${VALIDATE}" 2>&1)"
  got_exit=$?
  set -e
  if [[ -f "${work}/summary" ]]; then
    output+=$'\n'"$(cat "${work}/summary")"
  fi
  got_errors="$(sed -n 's/^errors=//p' "${work}/output" 2> /dev/null || true)"
  rm -rf "${work}"

  if [[ "${got_exit}" != "${want_exit}" ]]; then
    echo "FAIL ${name}: exit ${got_exit}, want ${want_exit}"
  elif [[ "${want_errors}" != "-" && "${got_errors}" != "${want_errors}" ]]; then
    echo "FAIL ${name}: errors '${got_errors}', want ${want_errors}"
  elif [[ -n "${pattern}" ]] && ! grep -qF -- "${pattern}" <<< "${output}"; then
    echo "FAIL ${name}: output missing '${pattern}'"
  else
    echo "ok   ${name}"
    return 0
  fi
  while IFS= read -r line; do echo "     | ${line}"; done <<< "${output}"
  FAILED=1
}

expect "valid yaml passes" schema.json valid.yml 0 0
expect "valid json passes" schema.json valid.json 0 0
expect "invalid yaml reports every violation" schema.json invalid.yml 1 3 "invalid.yml: name: 5 is not of type 'string'"
expect "minimum violation reported" schema.json invalid.yml 1 3 "invalid.yml: count: 0 is less than the minimum of 1"
expect "root violation uses <root>" schema.json invalid.yml 1 3 "invalid.yml: <root>: Additional properties are not allowed ('extra' was unexpected)"
expect "nested path reported" schema.json invalid-nested.yml 1 1 "invalid-nested.yml: tags/1: 1 is not of type 'string'"
expect "invalid json fails" schema.json invalid.json 1 1 "invalid.json: count: 0 is less than the minimum of 1"
expect "violations are annotated" schema.json invalid.yml 1 3 "::error file=invalid.yml"
expect "summary counts violations" schema.json invalid.yml 1 3 "3 violation(s)"
expect "violations are counted across files" schema.json $'valid.yml\ninvalid*.yml' 1 4
expect "empty document is validated as {}" schema.json empty.yml 1 2 "empty.yml: <root>: 'name' is a required property"
expect "falsy document is not coerced to {}" schema.json falsy.yml 1 1 "falsy.yml: <root>: 0 is not of type 'object'"
expect "mixed index and key paths sort" schema.json mixed-paths.yml 1 2 "mixed-paths.yml: tags/0: 1 is not of type 'string'"
expect "annotation data is escaped" schema.json percent.yml 1 1 "::error file=percent.yml,title=Schema Validate::<root>: Additional properties are not allowed ('100%25' was unexpected)"
expect "glob matching nothing is a usage error" schema.json "missing*.yml" 2 - "no files match: missing*.yml"
expect "malformed yaml is a usage error" schema.json malformed.yml 2 - "malformed.yml: cannot parse"
expect "missing schema is a usage error" nope.json valid.yml 2 - "schema file not found: nope.json"
expect "invalid schema is a usage error" bad-schema.json valid.yml 2 - "invalid schema: bad-schema.json"
expect "non-utf8 file is a usage error" schema.json non-utf8.yml 2 - "non-utf8.yml: cannot parse"
expect "unresolvable ref is a usage error" schema-ref.json valid.yml 2 - "cannot resolve"
expect "annotation path is relative to the workspace" schema.json invalid.json 1 1 "::error file=fixtures/invalid.json" "${TESTS_DIR}"

exit "${FAILED}"
