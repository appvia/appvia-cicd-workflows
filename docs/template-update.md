# Template Update Workflow

This GitHub Actions workflow template ([template-update.yml](../.github/workflows/template-update.yml)) automates the synchronization of files from a template repository to your repository. This is useful for keeping common files (like CI/CD configurations, linting rules, or documentation) in sync across multiple repositories.

## Introduction

The template update workflow helps maintain consistency across multiple repositories by automatically copying specified files from a central template repository. When changes are detected, it can automatically create a pull request with the updates, making it easy to review and apply template changes to your repository.

## Workflow Steps

1. **Checkout Repository:** Checks out the current repository
2. **Checkout Template Repository:** Checks out the specified template repository
3. **Update Files:** Copies the specified files from the template repository to the current repository
4. **Check for Changes:** Detects if any files were actually modified
5. **Create Pull Request:** If changes were detected and enabled, creates a pull request with the updates

## Usage

Create a new workflow file in your repository (e.g. `.github/workflows/sync-template.yml`) with the below contents:

```yml
name: Sync with Template
on:
  schedule:
    - cron: '0 0 * * 0'  # Run weekly on Sunday at midnight
  workflow_dispatch:  # Allow manual triggering

jobs:
  update:
    uses: appvia/appvia-cicd-workflows/.github/workflows/template-update.yml@main
    name: Update from Template
    with:
      template-repository: myorg/template-repo
      template-branch: main
      template-files: |
        .github/workflows/lint.yml
        .github/workflows/test.yml
        .commitlintrc.yaml
        .yamllint.yaml
```

## Inputs

### Required Inputs

- `template-repository` - The repository to keep files in sync with (format: `owner/repo`)
- `template-files` - Newline-separated list of file paths to sync from the template repository

### Optional Inputs

- `enable-pull-request` - Default: true. Whether to create a pull request with the changes
- `pull-request-title` - Custom prefix for the pull request title
- `template-branch` - Default: "main". The branch to sync files from in the template repository

## Examples

### Basic Usage with Weekly Sync

Automatically sync configuration files weekly:

```yml
name: Sync with Template
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  update:
    uses: appvia/appvia-cicd-workflows/.github/workflows/template-update.yml@main
    with:
      template-repository: myorg/central-template
      template-files: |
        .github/workflows/ci.yml
        .github/workflows/release.yml
        .commitlintrc.yaml
```

### Manual Sync Without Pull Request

Directly commit changes without creating a PR:

```yml
name: Manual Template Sync
on:
  workflow_dispatch:

jobs:
  update:
    uses: appvia/appvia-cicd-workflows/.github/workflows/template-update.yml@main
    with:
      template-repository: myorg/template-repo
      template-branch: main
      enable-pull-request: false
      template-files: |
        renovate.json
        .editorconfig
```

### Sync from Development Branch

Sync files from a development branch of the template:

```yml
jobs:
  update:
    uses: appvia/appvia-cicd-workflows/.github/workflows/template-update.yml@main
    with:
      template-repository: myorg/template-repo
      template-branch: develop
      pull-request-title: "[DEV TEMPLATE]"
      template-files: |
        .github/workflows/experimental.yml
```

### Multiple File Types

Sync various configuration and documentation files:

```yml
jobs:
  update:
    uses: appvia/appvia-cicd-workflows/.github/workflows/template-update.yml@main
    with:
      template-repository: myorg/standards-repo
      template-files: |
        .github/workflows/lint.yml
        .github/workflows/security-scan.yml
        .commitlintrc.yaml
        .yamllint.yaml
        .editorconfig
        .gitignore
        CODE_OF_CONDUCT.md
        CONTRIBUTING.md
```

## How It Works

1. The workflow checks out both your repository and the template repository
2. For each file listed in `template-files`:
   - If the file exists in your repository, it copies the version from the template
   - If the file doesn't exist in your repository, it skips that file
3. If changes are detected:
   - When `enable-pull-request` is true: Creates a PR with descriptive title and body
   - When `enable-pull-request` is false: Changes remain in the working directory
4. The pull request includes:
   - Clear title indicating it's a template update
   - Body describing the source template repository
   - All file changes for review

## Best Practices

1. **Schedule Regular Syncs:** Use cron scheduling to automatically check for template updates regularly
2. **Review Changes:** Always use pull requests (default behavior) so changes can be reviewed before merging
3. **Selective Syncing:** Only sync files that should be identical across repositories; avoid syncing files with repository-specific content
4. **Version Pinning:** Consider pinning to a specific tagged version instead of `@main` for stability
5. **Manual Trigger:** Include `workflow_dispatch` to allow manual syncing when needed
6. **Branch Protection:** Ensure template files don't override critical repository-specific configurations

## Common Use Cases

- **CI/CD Pipeline Standardization:** Keep workflow files consistent across an organization
- **Linting Configuration:** Sync linting rules and configuration files
- **Security Policies:** Distribute security scanning configurations
- **Documentation Templates:** Keep contribution guidelines and code of conduct up to date
- **Development Standards:** Synchronize editor configurations and formatting rules

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
