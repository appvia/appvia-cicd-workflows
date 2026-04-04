#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# run-tests.sh — Fixture-based test runner for promotion validation
#
# Usage:
#   ./run-tests.sh                          # Run all fixtures
#   ./run-tests.sh valid-promotion          # Run single fixture
#   ./run-tests.sh valid-promotion regression  # Run multiple fixtures
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_SCRIPT="$ROOT_DIR/scripts/validate-promotion.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASSED=0
FAILED=0
SKIPPED=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Helpers
# =============================================================================

print_header() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Promotion Validation Test Suite${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_footer() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Results: ${GREEN}${PASSED} passed${NC} | ${RED}${FAILED} failed${NC} | ${YELLOW}${SKIPPED} skipped${NC} | ${TOTAL} total"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# Run a single test fixture
# =============================================================================

run_fixture() {
  local fixture_name="$1"
  local fixture_path="$FIXTURES_DIR/$fixture_name"

  if [[ ! -d "$fixture_path" ]]; then
    echo -e "${YELLOW}⚠ ${fixture_name}: fixture directory not found, skipping${NC}"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if [[ ! -f "$fixture_path/expected.json" ]]; then
    echo -e "${YELLOW}⚠ ${fixture_name}: expected.json not found, skipping${NC}"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  if [[ ! -f "$fixture_path/changed.txt" ]]; then
    echo -e "${YELLOW}⚠ ${fixture_name}: changed.txt not found, skipping${NC}"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  TOTAL=$((TOTAL + 1))

  # Create temp workspace
  local tmpdir
  tmpdir=$(mktemp -d)

  # Copy fixture files to temp workspace (excluding metadata files)
  find "$fixture_path" -type f \
    ! -name "expected.json" \
    ! -name "changed.txt" \
    -exec bash -c '
      src="$1"
      fixture_path="$2"
      tmpdir="$3"
      rel="${src#$fixture_path/}"
      dest="$tmpdir/$rel"
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
    ' _ {} "$fixture_path" "$tmpdir" \;

  # Read changed files
  local changed_files=()
  while IFS= read -r line; do
    line=$(echo "$line" | xargs) # trim whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue
    changed_files+=("$tmpdir/$line")
  done <"$fixture_path/changed.txt"

  # Read expectations
  local expected_exit
  expected_exit=$(jq -r '.exit_code' "$fixture_path/expected.json")
  local message_contains
  message_contains=$(jq -r '.message_contains // empty' "$fixture_path/expected.json")

  # Read promotion order (optional, defaults to dev,qa,staging,uat,prod)
  local promotion_order="dev,qa,staging,uat,prod"
  if [[ -f "$fixture_path/promotion-order.txt" ]]; then
    promotion_order=$(cat "$fixture_path/promotion-order.txt" | xargs)
  fi

  # Run validation
  local output
  local actual_exit=0
  output=$("$VALIDATE_SCRIPT" "$tmpdir" "$promotion_order" "${changed_files[@]}" 2>&1) || actual_exit=$?

  # Validate exit code
  local test_passed=true
  local errors=()

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    test_passed=false
    errors+=("Exit code: expected ${expected_exit}, got ${actual_exit}")
  fi

  # Validate per-file results
  local result_keys
  result_keys=$(jq -r '.results // {} | keys[]' "$fixture_path/expected.json" 2>/dev/null)

  while IFS= read -r file_key; do
    [[ -z "$file_key" ]] && continue
    local expected_result
    expected_result=$(jq -r ".results[\"$file_key\"]" "$fixture_path/expected.json")

    case "$expected_result" in
    pass)
      if ! echo "$output" | grep -q "PASS.*${file_key}"; then
        test_passed=false
        errors+=("Expected PASS for ${file_key}")
      fi
      ;;
    fail)
      if ! echo "$output" | grep -q "FAIL.*${file_key}"; then
        test_passed=false
        errors+=("Expected FAIL for ${file_key}")
      fi
      ;;
    skip)
      if ! echo "$output" | grep -q "${file_key}.*SKIPPED"; then
        test_passed=false
        errors+=("Expected SKIP for ${file_key}")
      fi
      ;;
    warn)
      if ! echo "$output" | grep -q "${file_key}.*WARNING"; then
        test_passed=false
        errors+=("Expected WARNING for ${file_key}")
      fi
      ;;
    esac
  done <<<"$result_keys"

  # Validate message contains (optional)
  if [[ -n "$message_contains" ]]; then
    if ! echo "$output" | grep -q "$message_contains"; then
      test_passed=false
      errors+=("Expected output to contain '${message_contains}'")
    fi
  fi

  # Print result
  if $test_passed; then
    echo -e "${GREEN}✅ PASS${NC}: ${fixture_name}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}❌ FAIL${NC}: ${fixture_name}"
    for err in "${errors[@]}"; do
      echo -e "   ${RED}⚠ ${err}${NC}"
    done
    echo -e "   ${CYAN}Output:${NC}"
    echo "$output" | sed 's/^/      /'
    FAILED=$((FAILED + 1))
  fi

  # Cleanup
  rm -rf "$tmpdir"
}

# =============================================================================
# Main
# =============================================================================

print_header

# Determine which fixtures to run
if [[ $# -gt 0 ]]; then
  fixtures=("$@")
else
  fixtures=()
  for d in "$FIXTURES_DIR"/*/; do
    [[ -d "$d" ]] && fixtures+=("$(basename "$d")")
  done
fi

# Sort fixtures for consistent ordering
IFS=$'\n' sorted_fixtures=($(sort <<<"${fixtures[*]}"))
unset IFS

for fixture in "${sorted_fixtures[@]}"; do
  run_fixture "$fixture"
done

print_footer

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
