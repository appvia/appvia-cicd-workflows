SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.PHONY: help tools lint-yaml lint-actions lint-shell lint-commits lint validate \
	audit-sha-pinning render-diff validate-promotion

WORKFLOWS_DIR      := .github/workflows
YAMLLINT_CONFIG    := .yamllint.yaml
COMMITLINT_CONFIG  := .commitlintrc.yaml
BASE_BRANCH        ?= main
ORG                ?= appvia

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

tools: ## Check that the tools used by these targets are installed
	@command -v actionlint >/dev/null || { echo "actionlint not found: brew install actionlint"; exit 1; }
	@command -v yamllint >/dev/null || { echo "yamllint not found: brew install yamllint"; exit 1; }
	@command -v shellcheck >/dev/null || { echo "shellcheck not found: brew install shellcheck"; exit 1; }
	@command -v npx >/dev/null || { echo "npx not found: install Node.js"; exit 1; }
	@echo "All required tools are installed"

lint-yaml: ## Lint the GitHub workflow YAML (mirrors the yamllint CI job)
	yamllint -c $(YAMLLINT_CONFIG) $(WORKFLOWS_DIR)

lint-actions: ## Lint GitHub workflows with actionlint, including embedded shellcheck (mirrors the actionlint CI job)
	actionlint -ignore SC2086 $(WORKFLOWS_DIR)/*.yml

lint-shell: ## Shellcheck the helper scripts
	shellcheck scripts/*.sh

lint-commits: ## Lint commit messages on this branch against $(BASE_BRANCH) (mirrors the commitlint CI job)
	npx --yes commitlint --config $(COMMITLINT_CONFIG) --from $(BASE_BRANCH) --to HEAD

lint: lint-yaml lint-actions lint-shell lint-commits ## Run all linters

validate: lint ## Run everything expected to pass before raising a pull request

audit-sha-pinning: ## Audit org repos for SHA-pinned reusable workflow references (requires gh CLI); usage: make audit-sha-pinning ORG=my-org
	./scripts/audit_sha_pinning.sh $(ORG)

render-diff: ## Render the Terragrunt input diff between a PR branch and main; usage: make render-diff ARGS="pr-branch main"
	./scripts/render-diff.sh $(ARGS)

validate-promotion: ## Validate Helm workload version promotions; usage: make validate-promotion ARGS="workloads/applications file1 file2"
	./scripts/validate-promotion.sh $(ARGS)
