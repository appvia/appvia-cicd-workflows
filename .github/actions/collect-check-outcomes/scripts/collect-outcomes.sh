#!/usr/bin/env bash
# Write the outcome of every validate-and-plan check to a JSON file.
set -euo pipefail

target="$GITHUB_WORKSPACE/$OUTPUT_FILE"

# Built with jq --arg rather than a heredoc so every value is JSON-encoded; an unescaped value
# (e.g. a root directory name containing a quote or backslash) would otherwise produce malformed
# JSON that downstream consumers (such as loadEnvironments) silently discard.
jq -n \
  --arg environment "${ENV}" \
  --arg var_file "${VAR_FILE:-}" \
  --arg root "${ROOT}" \
  --arg commitlint "${RESULT_COMMITLINT}" \
  --arg pre_commit "${RESULT_PRE_COMMIT}" \
  --arg fmt_check "${RESULT_FMT_CHECK}" \
  --arg tflint "${RESULT_TFLINT}" \
  --arg init "${RESULT_INIT}" \
  --arg plan "${RESULT_PLAN}" \
  --arg plan_json "${RESULT_PLAN_JSON}" \
  --arg plan_exit "${RESULT_PLAN_EXIT}" \
  --arg plan_skip_reason "${PLAN_SKIP_REASON:-}" \
  --arg checkov "${RESULT_CHECKOV}" \
  --arg opa_local "${RESULT_OPA_LOCAL}" \
  --arg infracost "${RESULT_INFRACOST}" \
  '{
    environment: $environment,
    root: $root,
    commitlint: $commitlint,
    pre_commit: $pre_commit,
    fmt_check: $fmt_check,
    tflint: $tflint,
    init: $init,
    plan: $plan,
    plan_json: $plan_json,
    plan_exit: $plan_exit,
    plan_skip_reason: $plan_skip_reason,
    checkov: $checkov,
    opa_local: $opa_local,
    infracost: $infracost
  } + if $var_file == "" then {} else {var_file: $var_file} end' >"${target}"
