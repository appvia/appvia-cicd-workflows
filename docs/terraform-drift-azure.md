# Terraform Drift Detection Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-drift-azure.yml](../.github/workflows/terraform-drift-azure.yml)) is the **scheduled drift detection** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-drift.yml](./terraform-drift.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. It is **input-driven**.

## How it works

The **caller** schedules the check (cron). The workflow logs in with the **read-only** service principal and runs `terraform plan -detailed-exitcode` against the deployed state:

- exit `0` — no drift
- exit `2` — **drift detected**
- exit `1` — plan error (the job fails)

On drift it **opens or updates a GitHub issue** (deduplicated per environment via a hidden marker, labelled `drift`) and, when a `slack-webhook-url` secret is supplied, posts a Slack alert.

## Workflow steps

1. **Install Terraform** and, optionally, mint a **GitHub App token** for private modules.
2. **Azure login** — OIDC (`azure/login`) with the read-only service principal.
3. **Terraform init** — initialises the `azurerm` backend for the environment's state key.
4. **Terraform plan (drift check)** — `-detailed-exitcode`, captured to `drift_output.txt`.
5. **Open or update drift issue** — only when drift is detected.
6. **Slack notification** — optional, only when a webhook is configured.

## Usage

Add a scheduled caller in your Azure Terraform repository:

```yml
name: Terraform Drift
on:
  schedule:
    - cron: "0 6 * * *"   # daily 06:00 UTC
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
  issues: write

jobs:
  drift:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-drift-azure.yml@main
    with:
      azure-client-id: "<CUSTOMER_TENANT_ID_PLAN_CLIENT_ID>"
      azure-tenant-id: "<CUSTOMER_TENANT_ID>"
      azure-subscription-id: "<CUSTOMER_MANAGEMENT_SUBSCRIPTION_ID>"
      backend-resource-group-name: ${{ vars.AZURE_TFSTATE_RESOURCE_GROUP }}
      backend-storage-account-name: ${{ vars.AZURE_TFSTATE_STORAGE_ACCOUNT }}
      environment: prd
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```
