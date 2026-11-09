#!/usr/bin/env bash
# Terraform does not reject an invalid TF_LOG — it prints a warning and falls back to TRACE, the
# loudest level. Catch a typo here so it cannot turn a targeted DEBUG run into gigabytes of output.
set -euo pipefail

# Case-insensitive: Terraform upper-cases TF_LOG itself, so rejecting "debug" here would be
# stricter than the tool we are guarding. `tr` rather than ${VAR^^} — the latter needs bash 4+,
# and `runs-on` is caller-supplied (a macOS runner still ships bash 3.2).
case "$(printf '%s' "${LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')" in
  TRACE | DEBUG | INFO | WARN | ERROR | OFF) ;;
  *)
    echo "::error::terraform-log-level must be one of TRACE, DEBUG, INFO, WARN, ERROR, OFF (got '${LOG_LEVEL}')"
    exit 1
    ;;
esac
