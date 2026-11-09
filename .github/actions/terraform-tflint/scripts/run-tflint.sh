#!/usr/bin/env bash
# Initialise and run TFLint, resolving the config path and forwarding any var-files.
set -euo pipefail

# --chdir resolves a relative --config path against the chdir target rather than the invocation
# directory, so make the path absolute against the repo root to keep it pointing at the intended
# file regardless of WORKING_DIR.
case "$TFLINT_CONFIG" in
/*) TFLINT_CONFIG_PATH="$TFLINT_CONFIG" ;;
*) TFLINT_CONFIG_PATH="$GITHUB_WORKSPACE/$TFLINT_CONFIG" ;;
esac

tflint --chdir="$WORKING_DIR" --config="$TFLINT_CONFIG_PATH" --init

args=()
if [ -n "$TF_COMMON_VAR_FILE" ]; then args+=(--var-file="$TF_COMMON_VAR_FILE"); fi
if [ -n "$TF_VAR_FILE" ]; then args+=(--var-file="$TF_VAR_FILE"); fi

tflint --chdir="$WORKING_DIR" --config="$TFLINT_CONFIG_PATH" -f compact "${args[@]+"${args[@]}"}" 2>&1 | tee "$GITHUB_WORKSPACE/$OUTPUT_FILE"
