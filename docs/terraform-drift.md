# Terraform/OpenTofu Drift Detection Workflow for AWS Infrastructure

This workflow is used to run a scheduled or manually triggered drift detection on AWS infrastructure and alert in Slack if a change is detected, using GitHub Actions workflow template ([terraform-drift.yml](../.github/workflows/terraform-drift.yml))
In order to trigger the workflow, firstly the workflow must be referenced from the calling workflow flow, see below.

## OpenTofu Support

This workflow supports both Terraform and OpenTofu. Use the `enable-opentofu` input to switch between tools:

```yaml
with:
  enable-opentofu: true  # Use OpenTofu instead of Terraform
```

## Workflow Steps

1. **Setup Terraform/OpenTofu:** Terraform or OpenTofu is fetched at the specified version (overridable via inputs).
2. **AWS Authentication:** The workflow uses Web Identity Federation to authenticate with AWS. The required AWS Role ARN must be provided as an input for successful authentication.
    - A Web Identity Token File is also generated and stored in `/tmp/web_identity_token_file`, which can be referenced in Terraform/OpenTofu Provider configuration blocks if required.
3. **Terraform/OpenTofu Init:** The backend is initialised and any necessary provider plugins are downloaded. The required inputs for AWS S3 bucket name and DynamoDB table name must be provided for storing the state.
4. **Terraform/OpenTofu Plan:** A plan is generated with a specified values file (overridable via inputs) using the plan command.
5. **Change Detection Status:** Plan is checked for any changes and status is set as to drift status, "No drift detected." or "Drift detected!"
6. **Alerting:** If drift is detected from the Plan, an alert is sent to a configured Slack Channel alerting users. Otherwise where there is no change, this step is skipped.

## Usage

Create a workflow file in your Terraform repository (e.g. `.github/workflows/terraform-drift.yml`) with the below contents:

```yml
---
name: Terraform/OpenTofu Drift Detection
on:
  workflow_dispatch:
  schedule:
    - cron: "56 10 * * *"

permissions:
  contents: read
  id-token: write

jobs:
  terraform-drift:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-drift.yml@main
    name: Drift Detection
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
    with:
      aws-account-id: <aws-account-id-value>
      enable-opentofu: false  # Set to true to use OpenTofu
```

## Inputs

### Required Inputs

- `aws-account-id` - AWS account number where the infrastructure is deployed, and consequently planned against

### Required Secrets

- `slack-webhook-url` - Slack Webhook to a channel/app, stored as a secret in your GitHub Actions Secrets

### Optional Inputs

- `aws-region` - AWS region (default: "eu-west-2")
- `aws-role` - AWS role to assume (default: Repository Name)
- `aws-read-role-name` - Custom role name for read-only access
- `aws-write-role-name` - Custom role name for read-write access
- `environment` - Environment name (default: "production")
- `enable-opentofu` - Use OpenTofu instead of Terraform (default: false)
- `enable-private-access` - Enable private module access (default: false)
- `organization-name` - GitHub organization name (default: "appvia")
- `use-env-as-suffix` - Use environment as suffix for state file (default: false)
- `runs-on` - GitHub runner (default: "ubuntu-latest")
- `terraform-dir` - Directory containing Terraform files (default: ".")
- `terraform-init-extra-args` - Extra arguments for terraform init
- `terraform-lock-timeout` - Lock timeout (default: "30s")
- `terraform-state-key` - State file key (default: <repo-name>.tfstate)
- `terraform-values-file` - Values file (default: <environment>.tfvars)
- `terraform-version` - Terraform version (default: "1.11.2")
- `working-directory` - Working directory (default: ".")

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
