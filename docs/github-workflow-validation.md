# GitHub Workflow Validation

This GitHub Actions workflow template ([github-workflow-validation.yml](../.github/workflows/github-workflow-validation.yml)) validates GitHub Actions workflow files using actionlint to ensure they follow best practices and are free from common errors.

## Introduction

The workflow validation template helps maintain high-quality GitHub Actions workflows by automatically checking them for syntax errors, deprecated features, invalid step configurations, and other common issues. It uses [actionlint](https://github.com/rhysd/actionlint), a popular linting tool specifically designed for GitHub Actions workflows.

## Workflow Steps

1. **Checkout:** The repository code is checked out to access workflow files
2. **Install Go:** Sets up the Go programming language environment (required for actionlint)
3. **Install Actionlint:** Downloads and installs the actionlint tool
4. **Run Actionlint:** Validates all workflow files in the specified directory

## Usage

Create a new workflow file in your repository (e.g. `.github/workflows/validate.yml`) with the below contents:

```yml
name: Validate Workflows
on:
  push:
    branches:
      - main
    paths:
      - '.github/workflows/**'
  pull_request:
    branches:
      - main
    paths:
      - '.github/workflows/**'

jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/github-workflow-validation.yml@main
    name: Validate GitHub Workflows
```

## Inputs

### Optional Inputs

- `workflows-path` - Default: ".github/workflows". The path to the GitHub workflows directory to validate

## Examples

### Basic Usage

Validate workflows using the default path:

```yml
jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/github-workflow-validation.yml@main
```

### Custom Workflows Path

Validate workflows in a custom directory:

```yml
jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/github-workflow-validation.yml@main
    with:
      workflows-path: ".github/custom-workflows"
```

### Trigger on Workflow Changes Only

Only run validation when workflow files are modified:

```yml
name: Validate Workflows
on:
  pull_request:
    paths:
      - '.github/workflows/**'

jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/github-workflow-validation.yml@main
```

## What It Checks

Actionlint validates workflows for:

- Syntax errors in YAML
- Invalid workflow syntax and structure
- Undefined or misused contexts (e.g., `github`, `env`, `secrets`)
- Type mismatches in expressions
- Invalid action inputs and outputs
- Deprecated GitHub Actions features
- Common security issues
- Shell script problems using shellcheck

## Best Practices

1. **Run on Pull Requests:** Enable this workflow on pull requests to catch issues before merging
2. **Pin to a Version:** Consider pinning to a specific tagged version instead of `@main` for stability
3. **Combine with Other Checks:** Use alongside other validation workflows for comprehensive CI/CD pipeline quality

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
