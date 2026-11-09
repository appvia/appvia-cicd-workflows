#!/usr/bin/env bash
# Pass Terraform input variables from secrets through to Terraform, via two mechanisms driven by
# a single serialised secrets context (toJSON(secrets)):
#
#   1. Every TF_VAR_* secret is mapped onto the job environment. Terraform reads input variables
#      from TF_VAR_<name>, so a consumer that adds TF_VAR_db_password to a GitHub Environment gets
#      it wired through without touching a workflow. Complex types work too: Terraform parses a
#      JSON-encoded value for list, map and object variables.
#   2. The TERRAFORM_VARIABLES_JSON secret, if present, is materialised as an auto-loaded
#      tfvars.json file. .auto.tfvars.json rather than an explicit -var-file so plan, apply,
#      destroy and drift all pick it up without threading another argument through
#      terraform-exec. Terraform loads auto files before explicit -var-file arguments, so a
#      committed environments/<env>.tfvars still wins.
#
# Both mechanisms are exposed side by side (rather than one replacing the other) because they
# serve different callers: TF_VAR_* lets someone add a single secret to a GitHub Environment with
# no workflow edit, while TERRAFORM_VARIABLES_JSON suits a structured bundle of variables kept as
# one secret.
#
# Nothing here is logged except variable names. Values are masked before use as belt and braces —
# GitHub already masks the exact secret string, but the mask is re-registered so a value that was
# only ever seen as part of the serialised context, or nested inside the JSON blob, is covered too.
set -euo pipefail

target="${WORKING_DIR}/workflow-variables.auto.tfvars.json"

if [[ -z ${SECRETS_JSON//[[:space:]]/} ]]; then
  echo "No secrets context supplied; nothing to export."
  echo "exported=" >>"${GITHUB_OUTPUT}"
  exit 0
fi

if ! jq -e 'type == "object"' <<<"${SECRETS_JSON}" >/dev/null 2>&1; then
  echo "::error::The secrets-json input is not a JSON object. Pass \${{ toJSON(secrets) }}."
  exit 1
fi

# GITHUB_TOKEN is always present in the secrets context and is never a Terraform variable. The
# others cannot collide with the TF_VAR_ prefix, but are listed so the intent is explicit.
is_reserved() {
  case "$1" in
  GITHUB_TOKEN | TF_PLAN_ENCRYPTION_KEY | TERRAFORM_VARIABLES_JSON) return 0 ;;
  *) return 1 ;;
  esac
}

# --- 1. Export TF_VAR_* secrets onto the job environment -------------------------------------

exported=()

emit() {
  local name="$1" value="$2" delimiter

  # A random delimiter that is verified absent from the value, so a secret containing a plausible
  # marker cannot terminate the heredoc early and inject arbitrary environment variables.
  delimiter="EOF_$(openssl rand -hex 16)"
  while [[ ${value} == *"${delimiter}"* ]]; do
    delimiter="EOF_$(openssl rand -hex 16)"
  done

  {
    printf '%s<<%s\n' "${name}" "${delimiter}"
    printf '%s\n' "${value}"
    printf '%s\n' "${delimiter}"
  } >>"${GITHUB_ENV}"

  exported+=("${name}")
}

while IFS= read -r key; do
  [[ ${key} == TF_VAR_* ]] || continue
  if is_reserved "${key}"; then
    continue
  fi

  value="$(jq -r --arg k "${key}" '.[$k]' <<<"${SECRETS_JSON}")"
  if [[ -z ${value} ]]; then
    echo "::warning::Secret '${key}' is empty and was skipped."
    continue
  fi

  echo "::add-mask::${value}"
  emit "${key}" "${value}"

  # GitHub secret names are matched case-insensitively and are conventionally uppercase, whereas
  # the suffix of TF_VAR_<name> is matched case-sensitively against the Terraform variable name,
  # which is conventionally lowercase. Export a lowercased companion so TF_VAR_DB_PASSWORD also
  # satisfies `variable "db_password"`. Skipped when the caller already supplied the exact name.
  suffix="${key#TF_VAR_}"
  if [[ ${suffix} == "${suffix^^}" ]]; then
    lowered="TF_VAR_${suffix,,}"
    if [[ ${lowered} != "${key}" ]] && ! jq -e --arg k "${lowered}" 'has($k)' <<<"${SECRETS_JSON}" >/dev/null; then
      emit "${lowered}" "${value}"
    fi
  fi
done < <(jq -r 'keys_unsorted[]' <<<"${SECRETS_JSON}")

if [[ ${#exported[@]} -eq 0 ]]; then
  echo "No TF_VAR_* secrets found."
else
  echo "Exported ${#exported[@]} Terraform variable(s) from secrets:"
  printf '  %s\n' "${exported[@]}"
fi
echo "exported=${exported[*]}" >>"${GITHUB_OUTPUT}"

# --- 2. Write TERRAFORM_VARIABLES_JSON to an auto-loaded tfvars file ------------------------

VARIABLES_JSON="$(jq -r '.TERRAFORM_VARIABLES_JSON // empty' <<<"${SECRETS_JSON}")"

if [[ -z "${VARIABLES_JSON//[[:space:]]/}" ]]; then
  echo "No Terraform variables JSON supplied; skipping tfvars file."
  exit 0
fi

# Fail here rather than inside terraform: malformed JSON surfaces as an unhelpful parse error.
if ! jq -e 'type == "object"' <<<"${VARIABLES_JSON}" >/dev/null 2>&1; then
  echo "::error::TERRAFORM_VARIABLES_JSON is not a valid JSON object."
  exit 1
fi

# Mask before anything else touches the values: a mask registered after a value has already been
# printed does not retroactively redact it. Recurse into nested objects and arrays so a password
# buried inside a map is covered too. Booleans and numbers are skipped deliberately — masking
# "true" or "0" would redact unrelated log output.
while IFS= read -r value; do
  if [[ -n ${value} ]]; then
    echo "::add-mask::${value}"
  fi
done < <(jq -r '[.. | strings] | unique[]' <<<"${VARIABLES_JSON}")

# The file holds secrets in plaintext for the rest of the job, so keep it owner-readable and make
# sure the workflow deletes it once Terraform has run.
umask 077
printf '%s' "${VARIABLES_JSON}" >"${target}"
echo "Wrote $(jq -r 'keys | join(", ")' "${target}") to ${target}"

# A TF_VAR_* env var wins silently over the auto-loaded file, which is a confusing failure mode
# when somebody has set the same variable in both places and is editing the JSON expecting an
# effect. Checked against the names exported above, in-process, rather than the environment —
# GITHUB_ENV changes only take effect in later steps, not later in this same script.
contains() {
  local needle="$1" item
  for item in "${exported[@]}"; do
    [[ ${item} == "${needle}" ]] && return 0
  done
  return 1
}

while IFS= read -r name; do
  tf_var="TF_VAR_${name}"
  if contains "${tf_var}"; then
    echo "::notice::Terraform variable '${name}' is set both in TERRAFORM_VARIABLES_JSON and as a ${tf_var} secret. The environment variable takes precedence."
  fi
done < <(jq -r 'keys_unsorted[]' <<<"${VARIABLES_JSON}")
