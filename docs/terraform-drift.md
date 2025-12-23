# Terraform Drift Workflow for AWS Infrastructure

This workflow is used to run an scheduled or manually triggered drift detection on AWS infrastructure and alert in Slack if a change is detected, using GitHub Actions workflow template ([terraform-drift.yml](../.github/workflows/terraform-drift.yml))
In order to trigger the workflow, firstly the workflow must be referenced from the calling workflow flow, see below.

## Workflow Steps

1. **Setup Terraform:** Terraform is fetched at the specified version (overridable via inputs).
2. **AWS Authentication:** The workflow uses Web Identity Federation to authenticate with AWS. The required AWS Role ARN must be provided as an input for successful authentication.
    - A Web Identity Token File is also generated and stored in `/tmp/web_identity_token_file`, which can be referenced in Terraform Provider configuration blocks if required.
3. **Terraform Init:** The Terraform backend is initialised and any necessary provider plugins are downloaded. The required inputs for AWS S3 bucket name and DynamoDB table name must be provided for storing the Terraform state.
4. **Terraform Plan:** A Terraform plan is generated with a specified values file (overridable via inputs) using the terraform plan command.
5. **Change Detection Status:** Plan is checked for any changes and status is set as to drift status, "No drift detected." or "Drift detected!"
6. **Alerting:** If drift is detected from the Terraform Plan, an alert is sent to a configured Slack Channel alerting users. Otherwise where there is no change, this step is skipped.

## Usage

Create a workflow file in your Terraform repository (e.g. `.github/workflows/terraform-drift.yml`) with the below contents:

```yml
---
name: Terraform Drift
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
```

REQUIRED INPUTS:
- `aws-account-id` - AWS account number where the infrastructure is deployed, and consequently planned against

OPTIONAL INPUTS:
- `aws-region` - Default: "eu-west-2"
- `aws-role` - Default: Repository Name
- `aws-read-role-name` - Extra role for read only access
- `aws-write-role-name` - Extra role for read-write access
- `environment` - Default: "production"
- `use-env-as-suffix` - Default: false, Whether to use the environment as a suffix for the state file and iam roles
- `runs-on` - Default: "ubuntu-latest"
- `terraform-dir` - Default: "."
- `terraform-init-extra-args` - Extra arguments to pass to terraform init
- `terraform-lock-timeout` - Default: "30s"
- `terraform-state-key` - Default: <repo-name>.tfstate
- `terraform-values-file` - Default: <environment>.tfvars
- `terraform-version` - Default: "1.11.2"
- `working-directory` - Default: "."
- `enable-private-access` - Default: false
- `organization-name` - Default: "appvia"

OPTIONAL SECRETS:
- `slack-webhook-url` - Slack Webhook to a channel/app, stored as a secret in your Github Actions Secrets
- `actions-id` - The GitHub App ID for the Actions App
- `actions-secret` - The GitHub App secret for the Actions App

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
