#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-promotion.sh
#
# Validates environment promotions for Helm workloads by ensuring that
# semantic versions never regress when promoted through environments.
#
# Promotion order: dev → qa → staging → uat → prod
#
# Usage:
#   validate-promotion.sh [WORKLOADS_DIR] [CHANGED_FILE1] [CHANGED_FILE2] ...
#
# Exit codes:
#   0 - All validations passed
#   1 - One or more validations failed
# =============================================================================

PROMOTION_ORDER=("dev" "qa" "staging" "uat" "prod")
WORKLOADS_DIR="${1:-workloads/applications}"
shift || true
CHANGED_FILES=("$@")

# Track overall result
OVERALL_RESULT=0
RESULTS=()

# =============================================================================
# Utility Functions
# =============================================================================

log_pass() {
  echo "✅ PASS: $1"
  RESULTS+=("✅ **$1**: PASS — $2")
}

log_fail() {
  echo "❌ FAIL: $1"
  RESULTS+=("❌ **$1**: FAIL — $2")
  OVERALL_RESULT=1
}

log_info() {
  echo "ℹ️  INFO: $1"
  RESULTS+=("ℹ️  **$1**: SKIPPED — $2")
}

log_warn() {
  echo "⚠️  WARN: $1"
  RESULTS+=("⚠️  **$1**: WARNING — $2")
}

# =============================================================================
# Semver Comparison
#
# Compares two semantic versions.
# Returns:
#   0 if v1 == v2
#   1 if v1 > v2
#   2 if v1 < v2
# =============================================================================

compare_semver() {
  local v1="$1"
  local v2="$2"

  if [[ "$v1" == "$v2" ]]; then
    echo 0
    return
  fi

  # Parse major.minor.patch for v1
  local v1_major v1_minor v1_patch
  IFS='.' read -r v1_major v1_minor v1_patch <<<"$v1"
  v1_major=${v1_major:-0}
  v1_minor=${v1_minor:-0}
  v1_patch=${v1_patch:-0}

  # Parse major.minor.patch for v2
  local v2_major v2_minor v2_patch
  IFS='.' read -r v2_major v2_minor v2_patch <<<"$v2"
  v2_major=${v2_major:-0}
  v2_minor=${v2_minor:-0}
  v2_patch=${v2_patch:-0}

  if ((v1_major > v2_major)); then
    echo 1
    return
  fi
  if ((v1_major < v2_major)); then
    echo 2
    return
  fi
  if ((v1_minor > v2_minor)); then
    echo 1
    return
  fi
  if ((v1_minor < v2_minor)); then
    echo 2
    return
  fi
  if ((v1_patch > v2_patch)); then
    echo 1
    return
  fi
  if ((v1_patch < v2_patch)); then
    echo 2
    return
  fi

  echo 0
}

# =============================================================================
# YAML Value Extraction
#
# Extracts a simple scalar value from YAML without requiring a parser.
# Handles quoted and unquoted values.
# =============================================================================

get_yaml_value() {
  local file="$1"
  local key="$2"

  # Use grep to find the line with the key, then extract the value
  local line
  line=$(grep -E "^\s*${key}:" "$file" | head -1) || true

  if [[ -z "$line" ]]; then
    echo ""
    return
  fi

  # Extract value after the colon
  local value
  value=$(echo "$line" | sed "s/^[^:]*:\s*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" | xargs)
  echo "$value"
}

# =============================================================================
# Check if file is a Helm workload
# =============================================================================

is_helm_workload() {
  local file="$1"
  [[ -f "$file" ]] && grep -q "helm:" "$file" 2>/dev/null
}

# =============================================================================
# Check if file is a Kustomize workload
# =============================================================================

is_kustomize_workload() {
  local file="$1"
  [[ -f "$file" ]] && (grep -q "kustomize:" "$file" 2>/dev/null || grep -q "kustomize\." "$file" 2>/dev/null)
}

# =============================================================================
# Check if Kustomize workload pins to a branch (non-semver ref)
#
# Kustomize files may pin to a branch name (e.g. kustomize.ref: main)
# instead of a semantic version. When this is the case, version validation
# is not possible and a warning is emitted.
# =============================================================================

is_kustomize_branch_pinned() {
  local file="$1"

  # Check for kustomize.ref or kustomize.branch fields
  local ref_value
  ref_value=$(get_yaml_value "$file" "ref")
  if [[ -n "$ref_value" ]]; then
    # If ref exists but isn't a semver, it's branch-pinned
    if ! [[ "$ref_value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ref_value"
      return 0
    fi
  fi

  local branch_value
  branch_value=$(get_yaml_value "$file" "branch")
  if [[ -n "$branch_value" ]]; then
    if ! [[ "$branch_value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$branch_value"
      return 0
    fi
  fi

  echo ""
  return 1
}

# =============================================================================
# Find nearest predecessor environment
# =============================================================================

find_predecessor() {
  local env_name="$1"
  local app_dir="$2"
  local position=-1

  # Find position of current environment in promotion order
  for i in "${!PROMOTION_ORDER[@]}"; do
    if [[ "${PROMOTION_ORDER[$i]}" == "$env_name" ]]; then
      position=$i
      break
    fi
  done

  # If not found in promotion order, return empty
  if [[ $position -eq -1 ]]; then
    echo ""
    return
  fi

  # Walk backwards through promotion order
  for ((i = position - 1; i >= 0; i--)); do
    local predecessor_env="${PROMOTION_ORDER[$i]}"
    local predecessor_file="${app_dir}/${predecessor_env}.yaml"
    if [[ -f "$predecessor_file" ]]; then
      echo "$predecessor_file"
      return
    fi
  done

  echo ""
}

# =============================================================================
# Validate a single changed file
# =============================================================================

validate_file() {
  local changed_file="$1"

  # Handle both absolute and relative paths
  local relative_path
  if [[ "$changed_file" == /* ]]; then
    # Absolute path - extract relative to WORKLOADS_DIR
    relative_path="${changed_file#${WORKLOADS_DIR}/}"
  else
    relative_path="${changed_file#workloads/applications/}"
  fi

  # Extract app name (parent directory) and env name (filename without .yaml)
  local app_name env_name app_dir
  app_name=$(dirname "$relative_path")
  env_name=$(basename "$relative_path" .yaml)
  app_dir="${WORKLOADS_DIR}/${app_name}"

  # Skip if not a .yaml file at the app directory level
  if [[ "$app_name" == "." ]] || [[ "$app_name" == *"values"* ]] || [[ "$app_name" == *"overlays"* ]]; then
    log_info "${changed_file}" "Not an environment file (in values/ or overlays/ directory)"
    return
  fi

  # Check if file exists in PR branch
  if [[ ! -f "$changed_file" ]]; then
    log_info "${changed_file}" "File does not exist in PR branch (possibly deleted)"
    return
  fi

  # Check if it's a Kustomize workload
  if is_kustomize_workload "$changed_file"; then
    local branch_ref
    if branch_ref=$(is_kustomize_branch_pinned "$changed_file"); then
      log_warn "${app_name}/${env_name}.yaml" "Kustomize pinned to branch '${branch_ref}' — version validation not possible"
    else
      log_info "${app_name}/${env_name}.yaml" "Not a Helm workload (kustomize detected), skipping validation"
    fi
    return
  fi

  # Check if it's a Helm workload
  if ! is_helm_workload "$changed_file"; then
    log_info "${app_name}/${env_name}.yaml" "Not a Helm workload (no helm: block), skipping validation"
    return
  fi

  # Extract version from the changed file
  local target_version
  target_version=$(get_yaml_value "$changed_file" "version")

  if [[ -z "$target_version" ]]; then
    log_fail "${app_name}/${env_name}.yaml" "Helm workload missing 'helm.version' field"
    return
  fi

  # Validate semver format (basic check: X.Y.Z where X, Y, Z are numbers)
  if ! [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_fail "${app_name}/${env_name}.yaml" "Invalid semver format: '${target_version}' (expected X.Y.Z)"
    return
  fi

  # Find nearest predecessor
  local predecessor_file
  predecessor_file=$(find_predecessor "$env_name" "$app_dir")

  if [[ -z "$predecessor_file" ]]; then
    log_pass "${app_name}/${env_name}.yaml" "No predecessor environment found (first-time environment or dev)"
    return
  fi

  # Check if predecessor is also a Helm workload
  if ! is_helm_workload "$predecessor_file"; then
    log_info "${app_name}/${env_name}.yaml" "Predecessor is not a Helm workload, skipping validation"
    return
  fi

  # Extract version from predecessor
  local predecessor_version
  predecessor_version=$(get_yaml_value "$predecessor_file" "version")

  if [[ -z "$predecessor_version" ]]; then
    log_fail "${app_name}/${env_name}.yaml" "Predecessor (${predecessor_file#workloads/applications/}) missing 'helm.version' field"
    return
  fi

  # Validate predecessor semver format
  if ! [[ "$predecessor_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_fail "${app_name}/${env_name}.yaml" "Invalid semver in predecessor: '${predecessor_version}' (expected X.Y.Z)"
    return
  fi

  # Compare versions
  local cmp_result
  cmp_result=$(compare_semver "$target_version" "$predecessor_version")

  local predecessor_env_name
  predecessor_env_name=$(basename "$predecessor_file" .yaml)

  if [[ "$cmp_result" -eq 2 ]]; then
    log_fail "${app_name}/${env_name}.yaml" "Version regression: ${env_name} (${target_version}) < ${predecessor_env_name} (${predecessor_version})"
  else
    log_pass "${app_name}/${env_name}.yaml" "${env_name} (${target_version}) >= ${predecessor_env_name} (${predecessor_version})"
  fi
}

# =============================================================================
# Main
# =============================================================================

echo "========================================="
echo "  Promotion Validation"
echo "========================================="
echo ""
echo "Workloads directory: ${WORKLOADS_DIR}"
echo "Changed files: ${#CHANGED_FILES[@]}"
echo ""

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  echo "No changed files to validate."
  exit 0
fi

for file in "${CHANGED_FILES[@]}"; do
  validate_file "$file"
done

echo ""
echo "========================================="
echo "  Summary"
echo "========================================="

for result in "${RESULTS[@]}"; do
  echo "$result"
done

if [[ $OVERALL_RESULT -eq 0 ]]; then
  echo ""
  echo "All promotion validations passed!"
else
  echo ""
  echo "Some promotion validations failed. Please fix the issues above."
fi

exit $OVERALL_RESULT
