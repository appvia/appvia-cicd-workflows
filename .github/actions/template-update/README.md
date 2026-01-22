# Template Update Action

A composite GitHub Action that synchronizes files from a template repository to your current repository and optionally creates a pull request with the changes.

## Description

This action helps maintain consistency across multiple repositories by:
1. Checking out a specified upstream template repository
2. Copying designated files from the template to your repository
3. Detecting changes and optionally creating a pull request with those changes

This is particularly useful for:
- Keeping shared workflows, configurations, or documentation in sync across multiple repositories
- Maintaining standardized CI/CD pipelines
- Propagating security policy updates
- Distributing common configuration files

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `base-directory` | The base directory where files will be copied | Yes | `.` |
| `enable-pull-request` | Whether to create a pull request when changes are detected | Yes | - |
| `pull-request-title` | The title prefix for the pull request | No | `""` |
| `branch-name` | Custom branch name for the update (if not set, uses run ID) | No | `""` |
| `template-repository` | The upstream template repository (format: `owner/repo`) | Yes | - |
| `template-branch` | The branch of the template repository to sync from | No | `main` |
| `template-files` | Newline or space-separated list of files to copy (supports `source:destination` mapping) | Yes | - |
| `upstream-token` | GitHub token for authenticating with the upstream repository | No | `github.token` |

### File Mapping Format

The `template-files` input supports two formats:

1. **Simple format**: `path/to/file.yml` - copies to the same path in the destination
2. **Mapped format**: `source/path:destination/path` - copies from source to a different destination path

## Usage Examples

### Example 1: Basic Usage - Sync Single File

Synchronize a single workflow file from a template repository:

```yaml
name: Update Templates
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  workflow_dispatch:

jobs:
  update-templates:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Update GitHub Workflow
        uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
        with:
          base-directory: "."
          enable-pull-request: true
          template-repository: "appvia/template-repo"
          template-files: ".github/workflows/ci.yml"
```

### Example 2: Multiple Files with Custom PR Title

Sync multiple configuration files and create a PR with a custom title:

```yaml
- name: Sync Multiple Configuration Files
  uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
  with:
    base-directory: "."
    enable-pull-request: true
    pull-request-title: "[Config Update]"
    branch-name: "config-sync"
    template-repository: "my-org/config-templates"
    template-branch: "stable"
    template-files: |
      .editorconfig
      .gitignore
      .pre-commit-config.yaml
      LICENSE
```

### Example 3: File Remapping

Copy files from the template to different locations in your repository:

```yaml
- name: Update Templates with Custom Paths
  uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
  with:
    base-directory: "."
    enable-pull-request: true
    template-repository: "appvia/terraform-templates"
    template-files: |
      workflows/terraform-ci.yml:.github/workflows/ci.yml
      docs/CONTRIBUTING.md:CONTRIBUTING.md
      configs/renovate.json:.github/renovate.json
```

### Example 4: Private Template Repository

Use a custom token to access a private template repository:

```yaml
- name: Update from Private Template
  uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
  with:
    base-directory: "."
    enable-pull-request: true
    template-repository: "my-org/private-templates"
    template-files: ".github/workflows/security-scan.yml"
    upstream-token: ${{ secrets.TEMPLATE_ACCESS_TOKEN }}
```

### Example 5: Disable Pull Request Creation

Copy files without creating a pull request (useful for testing):

```yaml
- name: Test Template Sync
  uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
  with:
    base-directory: "."
    enable-pull-request: false
    template-repository: "appvia/templates"
    template-files: ".github/workflows/test.yml"
```

### Example 6: Complete Workflow Sync

A comprehensive example syncing multiple workflow files:

```yaml
name: Sync CI/CD Templates
on:
  schedule:
    - cron: '0 2 * * 1'  # Monday at 2 AM
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  sync-workflows:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync CI/CD Templates
        uses: appvia/appvia-cicd-workflows/.github/actions/template-update@main
        with:
          base-directory: "."
          enable-pull-request: true
          pull-request-title: "CI/CD Templates"
          branch-name: "template-sync-${{ github.run_number }}"
          template-repository: "appvia/appvia-cicd-workflows"
          template-branch: "main"
          template-files: |
            .github/workflows/terraform-plan.yml
            .github/workflows/terraform-apply.yml
            .github/workflows/release.yml
            .github/workflows/security-scan.yml
```

## Behavior

### Change Detection

The action automatically detects if any files were modified during the sync process. If no changes are detected, no pull request will be created (even if `enable-pull-request: true`).

### Pull Request Details

When changes are detected and `enable-pull-request: true`, the action creates a PR with:
- **Branch name**: `update/<branch-name>` or `update/<run-id>` if no branch name specified
- **Title**: `<pull-request-title> | [UPDATE] - Updating Templates inline with <template-repository>`
- **Body**: Auto-generated description referencing the template repository
- **Base**: `main` branch
- **Auto-delete**: Branch is deleted after merge

### File Not Found

If a specified template file doesn't exist in the upstream repository, the action logs a warning but continues processing other files.

## Permissions Required

The workflow using this action needs the following permissions:

```yaml
permissions:
  contents: write      # To create commits and branches
  pull-requests: write # To create pull requests
```

## Best Practices

1. **Schedule Regular Syncs**: Use cron schedules to automatically check for template updates
2. **Use Semantic Versioning**: Pin the action to a specific version or tag rather than `@main`
3. **Review PRs Before Merging**: Always review auto-generated PRs to ensure changes are appropriate
4. **Organize Template Files**: Keep template files well-organized in the source repository
5. **Document Customizations**: If you customize synced files, document changes that shouldn't be overwritten

## Troubleshooting

### No Pull Request Created

- Verify `enable-pull-request: true` is set
- Check that files actually changed (action only creates PR if changes detected)
- Ensure workflow has `pull-requests: write` permission

### Authentication Errors

- For private repositories, provide `upstream-token` with appropriate access
- Ensure the token has `repo` scope for private repositories

### Files Not Copied

- Verify file paths are correct relative to template repository root
- Check action logs for "File not found" messages
- Ensure `base-directory` is set correctly

## Related Actions

- [peter-evans/create-pull-request](https://github.com/peter-evans/create-pull-request) - Used internally for PR creation
- [actions/checkout](https://github.com/actions/checkout) - Used internally for repository checkout

## License

This action is part of the appvia-cicd-workflows repository. See the repository LICENSE for details.
