# Makefile for GitHub Actions Workflow Validation

This repository includes a Makefile that provides various targets for validating and managing GitHub Actions workflows.

## Prerequisites

The Makefile requires the following tools to be installed:

- `yq` - YAML processor for command-line
- `actionlint` - Linter for GitHub Actions workflows (optional)
- `yamllint` - YAML linter (optional)

## Installation

To install the required tools, run:

```bash
make install-tools
```

This will automatically install:

- `yq` via brew (macOS) or apt-get (Ubuntu/Debian)
- `actionlint` via the official installation script
- `yamllint` via pip

## Available Targets

### `make help`

Shows all available targets and their descriptions.

### `make validate-yaml`

Validates the YAML syntax of all workflow files in `.github/workflows/`.

**Example:**

```bash
make validate-yaml
```

**Output:**

```
Validating YAML syntax...
Validating .github/workflows/terraform-destroy.yml...
✅ .github/workflows/terraform-destroy.yml - YAML syntax OK
Validating .github/workflows/terraform-drift.yml...
✅ .github/workflows/terraform-drift.yml - YAML syntax OK
...
✅ All YAML files are syntactically valid
```

### `make validate-workflows`

Performs comprehensive workflow validation including:

- YAML syntax validation
- Basic workflow structure validation (checks for required `name` and `on` fields)

**Example:**

```bash
make validate-workflows
```

### `make lint-workflows`

Lints workflow files using `actionlint` for GitHub Actions best practices.

**Example:**

```bash
make lint-workflows
```

**Note:** Requires `actionlint` to be installed. Run `make install-tools` first.

### `make validate-opentofu`

Checks for workflows that have OpenTofu support enabled (contain `enable-opentofu` input).

**Example:**

```bash
make validate-opentofu
```

**Output:**

```
Checking for OpenTofu-enabled workflows...
✅ .github/workflows/terraform-destroy.yml - OpenTofu-enabled
✅ .github/workflows/terraform-drift.yml - OpenTofu-enabled
✅ .github/workflows/terraform-module-validation.yml - OpenTofu-enabled
✅ .github/workflows/terraform-plan-and-apply-aws.yml - OpenTofu-enabled
```

### `make summary`

Shows a summary of all workflow files in the repository.

**Example:**

```bash
make summary
```

**Output:**

```
GitHub Actions Workflow Summary
================================
Total workflow files:        6
Reusable workflows:        5
OpenTofu-enabled workflows:        4
```

### `make clean`

Cleans up temporary files.

## Usage Examples

### Basic Validation

```bash
# Validate all workflows
make validate-workflows

# Check only YAML syntax
make validate-yaml

# Show workflow summary
make summary
```

### Advanced Validation

```bash
# Install tools first
make install-tools

# Run comprehensive validation
make validate-workflows
make lint-workflows
make validate-opentofu
```

### CI/CD Integration

You can integrate these validation targets into your CI/CD pipeline:

```yaml
- name: Validate Workflows
  run: make validate-workflows

- name: Lint Workflows
  run: make lint-workflows
```

## OpenTofu Support

This repository includes workflows that support both Terraform and OpenTofu. The `enable-opentofu` input allows users to switch between the two tools:

```yaml
jobs:
  terraform:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-aws.yml@main
    with:
      enable-opentofu: true  # Use OpenTofu instead of Terraform
      # ... other inputs
```

## Troubleshooting

### YAML Syntax Errors

If you encounter YAML syntax errors, check:

1. Proper indentation (use 2 spaces)
2. Correct YAML structure
3. Valid GitHub Actions syntax

### Missing Tools

If tools are missing, run:

```bash
make install-tools
```

### Workflow Structure Issues

The validation checks for:

- Presence of `name` field
- Presence of `on` field
- Valid workflow structure

## Contributing

When adding new workflows:

1. Ensure they pass `make validate-workflows`
2. Run `make lint-workflows` for best practices
3. Update this documentation if adding new validation targets
