# GitHub CI/CD Workflows

This repository contains a collection of GitHub Actions workflow templates that can be used with various types of repositories to automate the build, test, and deployment of applications and infrastructure.

## Workflows

Please refer to the following documentation for more information on the workflows:

### Terraform Workflows
- [Terraform Plan & Apply (AWS)](./docs/terraform-plan-and-apply-aws.md) - Automated Terraform deployment pipeline for AWS
- [Terraform Module Validation](./docs/terraform-module-validation.md) - Validate Terraform modules
- [Terraform Module Release](./docs/terraform-module-release.md) - Release and publish Terraform modules
- [Terraform Destroy (AWS)](./docs/terraform-destroy.md) - Safely destroy Terraform-managed infrastructure
- [Terraform Drift Detection](./docs/terraform-drift.md) - Detect configuration drift in deployed infrastructure

### Terragrunt Workflows
- [Terragrunt Plan & Apply (AWS)](./docs/terragrunt-plan-and-apply-aws.md) - Automated Terragrunt deployment pipeline for AWS
- [Terragrunt Manual Dispatch](./docs/terragrunt-dispatch.md) - Manually trigger Terragrunt operations

### Docker Workflows
- [Docker Build, Push & Security Scan](./docs/docker-build.md) - Build, scan, and push Docker images

### Utility Workflows
- [GitHub Workflow Validation](./docs/github-workflow-validation.md) - Validate GitHub Actions workflow files
- [Template Update](./docs/template-update.md) - Keep repository files in sync with templates

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
