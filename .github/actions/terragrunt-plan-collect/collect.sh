#!/usr/bin/env bash
#
# Builds a compact plan summary for a single matrix unit, from the plan files written
# by `terragrunt run --all --out-dir PLAN_DIR --json-out-dir JSON_DIR -- plan`.
#
# Writes OUTPUT_DIR/summary.json containing the unit metadata, the outcome of the plan
# and, for each terragrunt unit planned, the counted resource changes along with the
# human readable plan stripped of the refresh noise (only the proposed changes)
#
# Required environment variables:
#   OUTPUT_DIR       - directory to write the summary into
#   PLAN_DIR         - directory passed to --out-dir
#   JSON_DIR         - directory passed to --json-out-dir
#   UNIT_DIR         - the directory the terragrunt plan was run from
# Optional environment variables:
#   UNIT_NAME, UNIT_ACCOUNT, UNIT_REGION, UNIT_PATH - matrix unit metadata
#   OUTCOME_PLAN     - the outcome of the plan step (success, failure, ...)
#   OUTCOME_AUTH     - the outcome of the authentication step
#   TERRAGRUNT_CONFIG_FILE - the terragrunt config file (default: terragrunt.hcl)
#   SKIP_SHOW        - when "true", do not render the human readable plan (testing)

set -euo pipefail

: "${OUTPUT_DIR:?OUTPUT_DIR must be set}"
: "${PLAN_DIR:?PLAN_DIR must be set}"
: "${JSON_DIR:?JSON_DIR must be set}"
: "${UNIT_DIR:?UNIT_DIR must be set}"

TERRAGRUNT_CONFIG_FILE="${TERRAGRUNT_CONFIG_FILE:-terragrunt.hcl}"

mkdir -p "${OUTPUT_DIR}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
UNITS_FILE="${WORK_DIR}/units.json"
echo "[]" > "${UNITS_FILE}"

# Strips the plan output down to the proposed changes, i.e. removes the preamble and
# any "Objects have changed outside of Terraform" section, blank lines and the totals
simplify_plan() {
  awk '
    /will perform the following actions:/ { found = 1; next }
    !found && /^Changes to Outputs:/ { found = 1 }
    found && /^Plan: / { next }
    found && /^[[:space:]]*$/ { next }
    found { print }
  '
}

# Summarise a single plan json file, counting the resource changes by action
summarise_json() {
  jq '
    def kind:
      if . == ["create"] then "create"
      elif . == ["update"] then "update"
      elif . == ["delete"] then "delete"
      elif (. == ["delete", "create"]) or (. == ["create", "delete"]) then "replace"
      elif . == ["forget"] then "forget"
      else "no-op" end;
    [(.resource_changes // [])[] | select(.mode == "managed")
      | {address, kind: (.change.actions | kind), importing: (.change.importing != null)}
      | select(.kind != "no-op" or .importing)] as $changes
    | {
        create: ([$changes[] | select(.kind == "create")] | length),
        update: ([$changes[] | select(.kind == "update")] | length),
        replace: ([$changes[] | select(.kind == "replace")] | length),
        delete: ([$changes[] | select(.kind == "delete")] | length),
        forget: ([$changes[] | select(.kind == "forget")] | length),
        import: ([$changes[] | select(.importing)] | length),
        outputs: ([(.output_changes // {}) | to_entries[] | select(.value.actions != ["no-op"])] | length),
        changes: $changes
      }
  ' "$1"
}

if [[ -d "${JSON_DIR}" ]]; then
  while IFS= read -r -d '' json_file; do
    relative="$(dirname "${json_file#"${JSON_DIR}"/}")"
    [[ "${json_file}" == "${JSON_DIR}/tfplan.json" ]] && relative="."

    echo "Summarising plan for unit: ${UNIT_DIR}/${relative}"
    summarise_json "${json_file}" > "${WORK_DIR}/summary.json"

    # Plans can be large, so pass them to jq via files rather than arguments
    : > "${WORK_DIR}/plan.txt"
    plan_file="${PLAN_DIR}/${relative}/tfplan.tfplan"
    if [[ "${SKIP_SHOW:-false}" != "true" ]] && [[ -f "${plan_file}" ]]; then
      if ! (cd "${UNIT_DIR}/${relative}" && terragrunt run --config "${TERRAGRUNT_CONFIG_FILE}" --log-level error --tf-forward-stdout --non-interactive -- show -no-color "${plan_file}") > "${WORK_DIR}/show.txt"; then
        echo "::warning::Unable to render the plan for ${UNIT_DIR}/${relative}"
      else
        simplify_plan < "${WORK_DIR}/show.txt" > "${WORK_DIR}/plan.txt"
      fi
    fi

    jq --arg path "${relative}" \
      --rawfile plan "${WORK_DIR}/plan.txt" \
      --slurpfile summary "${WORK_DIR}/summary.json" \
      '. + [{path: $path, plan: $plan} + $summary[0]]' "${UNITS_FILE}" > "${UNITS_FILE}.tmp"
    mv "${UNITS_FILE}.tmp" "${UNITS_FILE}"
  done < <(find "${JSON_DIR}" -type f -name 'tfplan.json' -print0 | sort -z)
fi

jq -n \
  --arg account "${UNIT_ACCOUNT:-}" \
  --arg name "${UNIT_NAME:-}" \
  --arg outcome_auth "${OUTCOME_AUTH:-}" \
  --arg outcome_plan "${OUTCOME_PLAN:-}" \
  --arg path "${UNIT_PATH:-${UNIT_DIR}}" \
  --arg region "${UNIT_REGION:-}" \
  --slurpfile units "${UNITS_FILE}" \
  '{
    account: $account,
    name: $name,
    outcome_auth: $outcome_auth,
    outcome_plan: $outcome_plan,
    path: $path,
    region: $region,
    units: $units[0]
  }' > "${OUTPUT_DIR}/summary.json"

jq -r '"Collected \(.units | length) plan(s) for \(.path) (plan: \(.outcome_plan))"' "${OUTPUT_DIR}/summary.json"
