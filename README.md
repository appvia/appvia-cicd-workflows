# GitHub CI/CD Workflows

This repository contains a collection of GitHub Actions workflow templates that can be used with various types of repositories to automate the build, test, and deployment of applications and infrastructure.

## OpenTofu Support

The AWS Terraform workflows (plan & apply, module validation, destroy and drift) support both **Terraform** and **OpenTofu** through the `enable-opentofu` input. This allows you to use OpenTofu as a drop-in replacement for Terraform while keeping the same workflow functionality.

```yaml
with:
  enable-opentofu: true  # Use OpenTofu instead of Terraform
```

## Workflows

Please refer to the following documentation for more information on the workflows:

### Terraform Workflows
- [Terraform Plan & Apply (AWS)](./docs/terraform-plan-and-apply-aws.md) - Automated Terraform deployment pipeline for AWS
- [Terraform Plan & Apply (Azure)](./docs/terraform-plan-and-apply-azure.md) - Input-driven plan, review & apply pipeline for Azure
- [Terraform Module Validation](./docs/terraform-module-validation.md) - Validate Terraform modules
- [Terraform Module Release](./docs/terraform-module-release.md) - Release and publish Terraform modules
- [Terraform Destroy (AWS)](./docs/terraform-destroy.md) - Safely destroy Terraform-managed infrastructure
- [Terraform Destroy (Azure)](./docs/terraform-destroy-azure.md) - Guarded, input-driven teardown for Azure
- [Terraform Drift Detection](./docs/terraform-drift.md) - Detect configuration drift in deployed infrastructure
- [Terraform Drift Detection (Azure)](./docs/terraform-drift-azure.md) - Scheduled drift detection for Azure (issue + optional Slack)

### Terragrunt Workflows
- [Terragrunt Plan & Apply (AWS)](./docs/terragrunt-plan-and-apply-aws.md) - Automated Terragrunt deployment pipeline for AWS (optional per-unit matrix for plan and apply on `main`)
- [Terragrunt Manual Dispatch](./docs/terragrunt-dispatch.md) - Manually trigger Terragrunt operations

### Helm Workflows
- [Helm Chart Validation](./docs/helm-chart-validation.md) - Lint, template and schema-validate Helm charts
- [Helm Chart Release](./docs/helm-chart-release.md) - Package and publish Helm charts

### Docker Workflows
- [Docker Build, Push & Security Scan](./docs/docker-build.md) - Build, scan, and push Docker images

### Utility Workflows
- [GitHub Workflow Validation](./docs/github-workflow-validation.md) - Validate GitHub Actions workflow files
- [Template Update](./docs/template-update.md) - Keep repository files in sync with templates

## Terragrunt Matrix and Plan Summary

The Terragrunt workflow can run in matrix mode (`enable-matrix: true`), with one job per Terragrunt unit for plan and apply. That keeps large estates fast, but splits the plan across many jobs. To keep the change reviewable, the per-unit plans are aggregated into a single **plan summary**: totals, a table of changed units per account and region, a list of every resource to be destroyed or replaced, and the trimmed plan for each unit with the refresh output removed. The summary is posted to the pull request, the workflow run's job summary and the job log, so scheduled and manually dispatched plans get it too.

The summary is built by two composite actions, [terragrunt-plan-collect](./docs/actions.md#terragrunt-plan-collect) (per unit) and [terragrunt-plan-summary](./docs/actions.md#terragrunt-plan-summary) (aggregation). See [Plan Summary](./docs/terragrunt-plan-and-apply-aws.md#plan-summary-matrix-mode) for details.

## Composite Actions

The workflows are built from composite actions in [.github/actions](./.github/actions), which can also be used directly in your own workflows (`uses: appvia/appvia-cicd-workflows/.github/actions/<action-name>@<ref>`). See [Composite Actions](./docs/actions.md) for the inputs, outputs and examples of each.

- **Shared:** [cicd-config](./docs/actions.md#cicd-config) - Copies centralised configuration (e.g. `.tflint.hcl`) into the workspace; [schema-validate](./docs/actions.md#schema-validate) - Validates YAML or JSON files against a JSON Schema
- **Terraform:** [terraform-bootstrap](./docs/actions.md#terraform-bootstrap), [terraform-bootstrap-noauth](./docs/actions.md#terraform-bootstrap-noauth) - Install Terraform or OpenTofu, authenticate with AWS and run `init`; [terraform-plan-encrypt](./docs/actions.md#terraform-plan-encrypt), [terraform-plan-decrypt](./docs/actions.md#terraform-plan-decrypt) - Encrypt and decrypt plan artifacts
- **Terragrunt:** [terragrunt-bootstrap](./docs/actions.md#terragrunt-bootstrap), [terragrunt-bootstrap-unauth](./docs/actions.md#terragrunt-bootstrap-unauth) - Install Terraform and Terragrunt and authenticate with AWS; [terragrunt-diff](./docs/actions.md#terragrunt-diff) - Diff rendered inputs against `main`; [terragrunt-matrix](./docs/actions.md#terragrunt-matrix) - Build the per-unit job matrix; [terragrunt-plan-collect](./docs/actions.md#terragrunt-plan-collect), [terragrunt-plan-summary](./docs/actions.md#terragrunt-plan-summary) - Aggregate matrix plans into one summary; [terragrunt-pr](./docs/actions.md#terragrunt-pr) - Post the review status comment
- **Kubernetes:** [kubernetes-platform-promotion](./docs/actions.md#kubernetes-platform-promotion) - Validate that environment promotions never regress versions
- **Template:** [template-update](./docs/actions.md#template-update) - Sync an allowlist of files from a template repository via pull request; [template-update-azure](./docs/actions.md#template-update-azure) - Sync a whole template repository except an exclusion list

## Local Development

Before raising a pull request, run the same checks CI runs, locally:

```shell
make validate
```

Run `make help` to see all available targets (individual linters, the SHA-pinning audit, and other helper scripts). Requires `actionlint`, `yamllint`, `shellcheck`, and Node.js (`npx`) to be installed locally, e.g. via `brew install actionlint yamllint shellcheck node`. You can also use the reusable [GitHub Workflow Validation](./docs/github-workflow-validation.md) workflow in CI.

## Using these workflows from a private repository

Centralised configuration (`config/`) and helper scripts (`scripts/`) ship with the composite actions in this repository, rather than being downloaded from `raw.githubusercontent.com`, so nothing here depends on this repository being public. Calling repositories do need permission to resolve the workflows and actions: under **Settings → Actions → General → Access**, set this repository to be accessible from repositories in the organisation. See [Private repository access](./docs/terraform-plan-and-apply-aws.md#private-repository-access) for detail.

## How to setup Deployment Protection & Approval

The workflow templates in this repository are designed to be used with GitHub's deployment protection and approval feature. This feature allows you to require manual approval before a deployment can be executed. When merging to main branch we automatically use a 'production' environment, this can be configured with the repository setting to ensure all changes to this environment must be manually approved before applying the change.

### Steps to setup Deployment Protection & Approval

1. Go to the repository settings
2. Click on the `Branches` tab
3. Click on the `Add rule` button
4. In the `Branch name pattern` field, enter the branch name you want to protect (e.g. `main`)
5. Check the `Require pull request reviews before merging` checkbox
6. Check the `Require status checks to pass before merging` checkbox
7. Check the `Require branches to be up to date before merging` checkbox
8. Check the `Include administrators` checkbox
9. Click on `Environments` and choose the environment you want to protect (e.g. `production`)
10. Check the `Require reviewers` checkbox and select the reviewers you want to require approval from
11. Check the `Prevent self-review` checkbox

## License

This project is distributed under the [Apache License, Version 2.0](./LICENSE).
