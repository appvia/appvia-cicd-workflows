#!/usr/bin/env bash

set -euo pipefail

ORG="${1:-appvia}"

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found. Install from https://cli.github.com" >&2
  exit 1
fi

REPOS=$(gh repo list "$ORG" --limit 500 --json name,isArchived \
  | jq -r '.[] | select(.isArchived == false) | select(.name | startswith("terraform-aws-")) | .name')

printf "%-50s %-10s %-12s %-10s\n" "REPO" "RENOVATE" "PIN_DIGESTS" "SHA_REFS"
printf "%-50s %-10s %-12s %-10s\n" "----" "--------" "-----------" "--------"

while IFS= read -r repo; do
    if ! gh api "repos/$ORG/$repo/contents/.github/workflows/terraform.yml" > /dev/null 2>&1; then
        continue
    fi

# Check Renovate Config
renovate_file=""
for config in "renovate.json" "renovate.json5" ".renovaterc" ".github/renovate.json" ".github/renovate.json5"; do
    if gh api "repos/$ORG/$repo/contents/$config" > /dev/null 2>&1; then
        renovate_file="$config"
        break
    fi
done

if [ -n "$renovate_file" ]; then
    renovate_status="PASS"
    content=$(gh api "repos/$ORG/$repo/contents/$renovate_file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    if echo "$content" | grep -q '"pinDigests".*true'; then
        pin_status="PASS"
    else
        pin_status="FAIL"
    fi
else
    renovate_status="FAIL"
    pin_status="N/A"
fi

# Check SHA refs in terraform.yml
tf_content=$(gh api "repos/$ORG/$repo/contents/.github/workflows/terraform.yml" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    cicd_refs=$(echo "$tf_content" | grep -E 'uses:.*appvia/appvia-cicd-workflows' || true)

if [ -z "$cicd_refs" ]; then
    sha_status="NO_REFS"
else
    non_sha=$(echo "$cicd_refs" | grep -vE '@[0-9a-f]{40}' || true)
    if [ -n "$non_sha" ]; then
        sha_status="FAIL"
    else
        sha_status="PASS"
    fi 
fi 

printf "%-50s %-10s %-12s %-10s\n" "$repo" "$renovate_status" "$pin_status" "$sha_status"
done <<< "$REPOS"