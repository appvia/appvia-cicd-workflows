#!/usr/bin/env bash
# Filters a Terraform plan JSON down to the resources that are *not* on the consumer's
# drift-exclusions list, then recomputes whether real (non-excluded) drift remains. Exact
# address match only, by design — globs are a much easier way to silently exclude more drift
# than intended on a shared, high-blast-radius estate.
#
# "Changed" mirrors the classifier in terraform-plan-report/scripts/plan-report.js
# (changedResources: any resource whose actions are not exactly ["no-op"]). Kept in sync by hand
# since this script can't share that JS function directly — if one definition changes, check the
# other.
set -euo pipefail

CHANGED_FILTER='.change.actions != ["no-op"]'

# These uppercase variables are supplied by action.yaml's env block.
# shellcheck disable=SC2153
plan_json="${PLAN_JSON}"
# shellcheck disable=SC2153
working_dir="${WORKING_DIR}"
# shellcheck disable=SC2153
exclusions_file_input="${EXCLUSIONS_FILE}"
# shellcheck disable=SC2153
filtered_json_file="${FILTERED_JSON_FILE}"

before_count=$(jq "[.resource_changes[]? | select(${CHANGED_FILTER})] | length" "${plan_json}")

exclusions_file=""
if [[ -n ${exclusions_file_input} ]]; then
  exclusions_file="${exclusions_file_input}"
fi

if [[ -z ${exclusions_file} ]]; then
  echo "Drift filter: no drift-exclusions-file configured; every detected change is treated as drift."
elif [[ ! -f ${exclusions_file} ]]; then
  echo "Drift filter: exclusions file '${exclusions_file}' not found (relative to GITHUB_WORKSPACE); every detected change is treated as drift."
fi

# Strip trailing '#' comments and surrounding whitespace, drop blank lines, then hand the result
# to jq as a JSON array so address matching happens inside a single jq filter.
exclusions_json="[]"
if [[ -n ${exclusions_file} && -f ${exclusions_file} ]]; then
  exclusions_json=$(sed -E 's/#.*$//' "${exclusions_file}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | awk 'NF' | jq -R -s -c 'split("\n") | map(select(length > 0))')
  exclusions_total=$(jq 'length' <<<"${exclusions_json}")
  echo "Drift filter: loaded ${exclusions_total} exclusion address(es) from '${exclusions_file}'."
fi

filtered_json_path="${working_dir}/${filtered_json_file}"

if [[ ${exclusions_json} == "[]" ]]; then
  cp "${plan_json}" "${filtered_json_path}"
else
  jq --argjson exclusions "${exclusions_json}" \
    '.resource_changes |= map(select(.address as $a | ($exclusions | index($a)) | not))' \
    "${plan_json}" >"${filtered_json_path}"

  # Flag exclusion entries that didn't match any resource address in this plan. This is the
  # single most common misconfiguration (typo, missing module prefix, stale address after a
  # refactor/move) and previously produced zero output anywhere, silently leaving every
  # detected change treated as drift with no clue why.
  unmatched_json=$(jq --argjson exclusions "${exclusions_json}" \
    '$exclusions - [.resource_changes[]?.address]' \
    "${plan_json}")
  unmatched_count=$(jq 'length' <<<"${unmatched_json}")
  if [[ ${unmatched_count} -gt 0 ]]; then
    echo "::warning::Drift filter: ${unmatched_count} of ${exclusions_total} exclusion address(es) did not match any resource in the plan (typo, missing module prefix, or stale address?): $(jq -r 'join(", ")' <<<"${unmatched_json}")"
  fi
fi

after_count=$(jq "[.resource_changes[]? | select(${CHANGED_FILTER})] | length" "${filtered_json_path}")
excluded_count=$((before_count - after_count))

echo "Drift filter: ${before_count} changed resource(s) before exclusions, ${excluded_count} excluded, ${after_count} remaining."

has_drift=false
if [[ ${after_count} -gt 0 ]]; then
  has_drift=true
fi

{
  echo "has-drift=${has_drift}"
  echo "excluded-count=${excluded_count}"
  echo "remaining-count=${after_count}"
  echo "filtered-json-path=${filtered_json_path}"
} >>"${GITHUB_OUTPUT}"

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  if [[ ${excluded_count} -gt 0 ]]; then
    echo "ℹ️ ${excluded_count} resource(s) excluded from drift detection via \`${exclusions_file_input}\`." >>"${GITHUB_STEP_SUMMARY}"
  fi
  if [[ ${unmatched_count:-0} -gt 0 ]]; then
    echo "⚠️ ${unmatched_count} exclusion address(es) in \`${exclusions_file_input}\` did not match any resource in this plan: $(jq -r 'join(", ")' <<<"${unmatched_json}")" >>"${GITHUB_STEP_SUMMARY}"
  fi
fi
