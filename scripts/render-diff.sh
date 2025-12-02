#!/usr/bin/env bash

# render-diff.sh - Compare Terragrunt inputs between pull request and main branch
# Usage: ./scripts/render-diff.sh [PR_BRANCH] [MAIN_BRANCH]
# Default: PR_BRANCH=current branch, MAIN_BRANCH=main
#
# Environment Variables:
#   NO_COLOR=true    Disable colored output (useful for CI/CD environments)

set -eo pipefail

# Colors for output (disabled if NO_COLOR is set)
if [[ "${NO_COLOR:-}" == "true" ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Function to get current branch name (works in GitHub Actions)
get_current_branch() {
    # In GitHub Actions, use context variables first
    if [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
        echo "$GITHUB_HEAD_REF"  # PR branch
    elif [[ -n "${GITHUB_REF_NAME:-}" ]]; then
        echo "$GITHUB_REF_NAME"  # Push branch
    else
        # Fallback to git command
        git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
    fi
}

# Default values
PR_BRANCH="${1:-$(get_current_branch)}"
MAIN_BRANCH="${2:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ACCOUNT_FILES="${ACCOUNT_FILES:-terragrunt.hcl}"
TEMP_DIR=$(mktemp -d)


# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Function to print colored output
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command_exists terragrunt; then
        missing_deps+=("terragrunt")
    fi
    
    if ! command_exists jq; then
        missing_deps+=("jq")
    fi
    
    if ! command_exists git; then
        missing_deps+=("git")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_color $RED "Error: Missing required dependencies: ${missing_deps[*]}"
        print_color $YELLOW "Please install the missing tools:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                "terragrunt")
                    echo "  - Terragrunt: https://terragrunt.gruntwork.io/docs/getting-started/install/"
                    ;;
                "jq")
                    echo "  - jq: https://stedolan.github.io/jq/download/"
                    ;;
                "git")
                    echo "  - git: https://git-scm.com/downloads"
                    ;;
            esac
        done
        exit 1
    fi
}

# Function to find all Terragrunt units
find_terragrunt_units() {
    local base_dir="$1"
    find "$base_dir/accounts" -not -path "*/.terragrunt-cache/*" -name "${ACCOUNT_FILES}" -type f | sort
}

# Function to render Terragrunt inputs for a specific unit
render_terragrunt_inputs() {
    local unit_file="$1"
    local branch="$2"
    local output_file="$3"
    
    print_color $BLUE "Rendering inputs for unit: ${unit_file} on $branch..."
    
    # Checkout the specified branch
    git checkout "$branch" >/dev/null 2>&1 || {
        print_color $RED "Error: Could not checkout branch $branch"
        return 1
    }
    
    # Render the Terragrunt configuration and extract inputs
    if terragrunt render --config "$unit_file" -json 2>/dev/null | jq -r '.inputs // {}' > "$output_file" 2>/dev/null; then
        print_color $GREEN "✓ Successfully rendered inputs for $(basename "$(dirname "$unit_file")")"
        return 0
    else
        print_color $YELLOW "⚠ Warning: Could not render inputs for $(basename "$(dirname "$unit_file")") on $branch"
        echo '{}' > "$output_file"
        return 1
    fi
}

# Function to compare two JSON files and show differences
compare_inputs() {
    local pr_file="$1"
    local main_file="$2"
    local unit_name="$3"
    
    print_color $BLUE "Comparing inputs for $unit_name..."
    
    # Check if both files exist and are valid JSON
    if [[ ! -f "$pr_file" ]] || [[ ! -f "$main_file" ]]; then
        print_color $YELLOW "⚠ Skipping $unit_name - missing input files"
        return 0
    fi
    
    # Check if files are valid JSON
    if ! jq empty "$pr_file" 2>/dev/null || ! jq empty "$main_file" 2>/dev/null; then
        print_color $YELLOW "⚠ Skipping $unit_name - invalid JSON in input files"
        return 0
    fi
    
    # Sort and format JSON files for better diff comparison
    local pr_sorted="$TEMP_DIR/pr_$(basename "$pr_file" .json)_sorted.json"
    local main_sorted="$TEMP_DIR/main_$(basename "$main_file" .json)_sorted.json"
    
    # Sort JSON keys for consistent comparison
    jq -S '.' "$pr_file" > "$pr_sorted" 2>/dev/null || {
        print_color $YELLOW "⚠ Could not sort PR inputs for $unit_name"
        return 0
    }
    
    jq -S '.' "$main_file" > "$main_sorted" 2>/dev/null || {
        print_color $YELLOW "⚠ Could not sort main inputs for $unit_name"
        return 0
    }
    
    # Use diff to compare the sorted JSON files
    if diff -u "$main_sorted" "$pr_sorted" >/dev/null 2>&1; then
        print_color $GREEN "✓ No changes detected in $unit_name"
    else
        print_color $YELLOW "📋 Changes detected in $unit_name:"
        echo
        print_color $BLUE "--- Main branch ($MAIN_BRANCH)"
        print_color $BLUE "+++ PR branch ($PR_BRANCH)"
        echo
        diff -u "$main_sorted" "$pr_sorted" | sed '1,2d' || true
        echo
    fi
}

# Function to generate summary
generate_summary() {
    local summary_file="$TEMP_DIR/summary.txt"
    local changes_count=0
    local total_units=0
    
    print_color $BLUE "Generating summary..."
    
    for unit in $(find_terragrunt_units "$PROJECT_ROOT"); do
        local unit_name="$(basename "$(dirname "$unit")")/$(basename "$(dirname "$(dirname "$unit")")")"
        local pr_file="$TEMP_DIR/pr_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        local main_file="$TEMP_DIR/main_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        
        total_units=$((total_units + 1))
        
        if [[ -f "$pr_file" ]] && [[ -f "$main_file" ]]; then
            # Sort JSON files for comparison
            local pr_sorted="$TEMP_DIR/pr_$(basename "$pr_file" .json)_sorted.json"
            local main_sorted="$TEMP_DIR/main_$(basename "$main_file" .json)_sorted.json"
            
            if jq -S '.' "$pr_file" > "$pr_sorted" 2>/dev/null && jq -S '.' "$main_file" > "$main_sorted" 2>/dev/null; then
                # Use diff to check if files are different
                if ! diff -q "$main_sorted" "$pr_sorted" >/dev/null 2>&1; then
                    changes_count=$((changes_count + 1))
                fi
            fi
        fi
    done
    
    print_color $BLUE "=== SUMMARY ==="
    print_color $GREEN "Total Terragrunt units: $total_units"
    print_color $YELLOW "Units with changes: $changes_count"
    print_color $BLUE "PR Branch: $PR_BRANCH"
    print_color $BLUE "Main Branch: $MAIN_BRANCH"
    
    if [[ $changes_count -eq 0 ]]; then
        print_color $GREEN "✓ No changes detected across all units"
    else
        print_color $YELLOW "📋 $changes_count unit(s) have changes"
    fi
}

# Main function
main() {
    print_color $BLUE "=== Terragrunt Input Diff Tool ==="
    print_color $BLUE "Comparing inputs between $PR_BRANCH and $MAIN_BRANCH"
    
    # Debug information for GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        print_color $YELLOW "GitHub Actions detected:"
        print_color $YELLOW "  GITHUB_HEAD_REF: ${GITHUB_HEAD_REF:-not set}"
        print_color $YELLOW "  GITHUB_REF_NAME: ${GITHUB_REF_NAME:-not set}"
        print_color $YELLOW "  GITHUB_REF: ${GITHUB_REF:-not set}"
        print_color $YELLOW "  Git HEAD: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'detached')"
    fi
    echo
    
    # Check dependencies
    check_dependencies
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Ensure we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_color $RED "Error: Not in a git repository"
        exit 1
    fi
    
    # Ensure we have a remote origin configured
    if ! git remote get-url origin >/dev/null 2>&1; then
        print_color $YELLOW "No origin remote found, attempting to add GitHub remote..."
        if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
            git remote add origin "https://github.com/${GITHUB_REPOSITORY}.git"
            print_color $GREEN "✓ Added origin remote: https://github.com/${GITHUB_REPOSITORY}.git"
        else
            print_color $RED "Error: No origin remote and GITHUB_REPOSITORY not set"
            exit 1
        fi
    fi
    
    # Check if branches exist locally, if not try to fetch them
    if ! git show-ref --verify --quiet "refs/heads/$PR_BRANCH" 2>/dev/null; then
        print_color $YELLOW "Branch '$PR_BRANCH' not found locally, attempting to fetch..."
        if git fetch origin "$PR_BRANCH:$PR_BRANCH" 2>/dev/null; then
            print_color $GREEN "✓ Successfully fetched branch '$PR_BRANCH'"
        else
            print_color $RED "Error: Could not fetch branch '$PR_BRANCH' from origin"
            print_color $YELLOW "Available branches:"
            git branch -r | head -10
            exit 1
        fi
    fi
    
    if ! git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH" 2>/dev/null; then
        print_color $YELLOW "Branch '$MAIN_BRANCH' not found locally, attempting to fetch..."
        if git fetch origin "$MAIN_BRANCH:$MAIN_BRANCH" 2>/dev/null; then
            print_color $GREEN "✓ Successfully fetched branch '$MAIN_BRANCH'"
        else
            print_color $RED "Error: Could not fetch branch '$MAIN_BRANCH' from origin"
            print_color $YELLOW "Available branches:"
            git branch -r | head -10
            exit 1
        fi
    fi
    
    # Find all Terragrunt units
    local units
    mapfile -t units < <(find_terragrunt_units "$PROJECT_ROOT")
    
    if [[ ${#units[@]} -eq 0 ]]; then
        print_color $YELLOW "No Terragrunt units found in accounts directory"
        exit 0
    fi
    
    print_color $BLUE "Found ${#units[@]} Terragrunt units"
    echo
    
    # Render inputs for each unit on both branches
    for unit in "${units[@]}"; do
        local unit_name="$(basename "$(dirname "$unit")")/$(basename "$(dirname "$(dirname "$unit")")")"
        local pr_file="$TEMP_DIR/pr_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        local main_file="$TEMP_DIR/main_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        
        # Render PR branch inputs
        render_terragrunt_inputs "$unit" "$PR_BRANCH" "$pr_file"
        
        # Render main branch inputs
        render_terragrunt_inputs "$unit" "$MAIN_BRANCH" "$main_file"
        
        echo
    done
    
    # Compare inputs for each unit
    print_color $BLUE "=== COMPARING INPUTS ==="
    echo
    
    for unit in "${units[@]}"; do
        local unit_name="$(basename "$(dirname "$unit")")/$(basename "$(dirname "$(dirname "$unit")")")"
        local pr_file="$TEMP_DIR/pr_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        local main_file="$TEMP_DIR/main_$(basename "$(dirname "$unit")")_$(basename "$(dirname "$(dirname "$unit")")").json"
        
        compare_inputs "$pr_file" "$main_file" "$unit_name"
        echo
    done
    
    # Generate summary
    generate_summary
    
    print_color $BLUE "=== DIFF COMPLETE ==="
}

# Run main function
main "$@"