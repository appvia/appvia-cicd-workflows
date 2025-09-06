# Makefile for GitHub CI/CD Workflows
# This Makefile provides targets for validating and managing GitHub Actions workflows

.DEFAULT_GOAL := all

.PHONY: help validate-workflows validate-yaml lint-workflows clean install-tools summary


# Default target
help:
	@echo "Available targets:"
	@echo "  validate-workflows  - Validate all GitHub Actions workflow files"
	@echo "  validate-yaml       - Validate YAML syntax of all workflow files"
	@echo "  lint-workflows      - Lint workflow files using actionlint"
	@echo "  install-tools       - Install required validation tools"
	@echo "  summary             - Show workflow summary"
	@echo "  clean               - Clean up temporary files"

# Install required tools
install-tools:
	@echo "Installing validation tools..."
	@if ! command -v actionlint >/dev/null 2>&1; then \
		echo "Installing actionlint..."; \
		curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash; \
		sudo mv actionlint /usr/local/bin/; \
	fi
	@if ! command -v yamllint >/dev/null 2>&1; then \
		echo "Installing yamllint..."; \
		pip install yamllint; \
	fi
	@if ! command -v yq >/dev/null 2>&1; then \
		echo "Installing yq..."; \
		if command -v brew >/dev/null 2>&1; then \
			brew install yq; \
		elif command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y yq; \
		else \
			echo "Please install yq manually: https://github.com/mikefarah/yq"; \
		fi; \
	fi

# Validate YAML syntax
validate-yaml:
	@echo "Validating YAML syntax..."
	@for file in .github/workflows/*.yml; do \
		if [ -f "$$file" ]; then \
			echo "Validating $$file..."; \
			if ! yq eval '.' "$$file" >/dev/null 2>&1; then \
				echo "❌ YAML syntax error in $$file"; \
				exit 1; \
			else \
				echo "✅ $$file - YAML syntax OK"; \
			fi; \
		fi; \
	done
	@echo "✅ All YAML files are syntactically valid"

# Lint workflows using actionlint
lint-workflows:
	@echo "Linting GitHub Actions workflows..."
	@if command -v actionlint >/dev/null 2>&1; then \
		actionlint .github/workflows/*.yml; \
	else \
		echo "❌ actionlint not found. Run 'make install-tools' first"; \
		exit 1; \
	fi

# Basic workflow validation
validate-workflows: validate-yaml
	@echo "Validating workflow structure..."
	@for file in .github/workflows/*.yml; do \
		if [ -f "$$file" ]; then \
			echo "Validating $$file..."; \
			if ! yq eval 'has("name")' "$$file" | grep -q "true"; then \
				echo "❌ $$file: Missing 'name' field"; \
				exit 1; \
			fi; \
			if ! yq eval 'has("on")' "$$file" | grep -q "true"; then \
				echo "❌ $$file: Missing 'on' field"; \
				exit 1; \
			fi; \
			echo "✅ $$file - Basic structure OK"; \
		fi; \
	done
	@echo "✅ All workflows passed basic validation"

# Check for OpenTofu workflows
validate-opentofu:
	@echo "Checking for OpenTofu-enabled workflows..."
	@for file in .github/workflows/*.yml; do \
		if [ -f "$$file" ] && grep -q "enable-opentofu" "$$file"; then \
			echo "✅ $$file - OpenTofu-enabled"; \
		fi; \
	done

all: validate-workflows validate-yaml lint-workflows validate-opentofu summary

# Show workflow summary
summary:
	@echo "GitHub Actions Workflow Summary"
	@echo "================================"
	@echo "Total workflow files: $$(find .github/workflows -name "*.yml" | wc -l)"
	@echo "Reusable workflows: $$(grep -l "workflow_call" .github/workflows/*.yml 2>/dev/null | wc -l)"
	@echo "OpenTofu-enabled workflows: $$(grep -l "enable-opentofu" .github/workflows/*.yml 2>/dev/null | wc -l)"

# Clean up temporary files
clean:
	@echo "Cleaning up temporary files..."
	@rm -f *.tmp
	@echo "✅ Cleanup complete"