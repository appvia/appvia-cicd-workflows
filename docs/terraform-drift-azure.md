# Terraform Drift Detection Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-drift-azure.yml](../.github/workflows/terraform-drift-azure.yml)) is the **scheduled drift detection** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-drift.yml](./terraform-drift.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. It is **input-driven**.

## How it works

The **caller** schedules the check (cron). The workflow logs in with the **read-only** service principal and runs `terraform plan -detailed-exitcode` against the deployed state:

- exit `0` — no drift
- exit `2` — **drift detected**
- exit `1` — plan error (the job fails)

One matrix leg runs per entry in `environments`, so a single scheduled call covers every Terraform environment. On drift it **opens or updates a GitHub issue** (deduplicated per environment via a hidden marker, labelled `drift`) and, when a `slack-webhook-url` secret is supplied, posts a Slack alert.

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
      backend-container-name: tfstate
      # GitHub Environment the job enters: prod-plan
      github-environment-prefix: prod
      # Terraform environments to check — one matrix leg each
      environments: '["dev", "tst", "stg", "prd"]'
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## GitHub Environment

The job runs in the `<prefix>-plan` GitHub Environment, where `<prefix>` is the required `github-environment-prefix` input — the same environment the [plan & apply](./terraform-plan-and-apply-azure.md) workflow uses for its PR plans. It must already exist; the workflow does not create it.

It holds no configuration. Entering it puts the `environment` claim in the OIDC token, which is what the Entra federated credential subject for the read-only service principal is scoped to.

**Leave `<prefix>-plan` free of protection rules.** Drift runs on a schedule with no one watching; a required reviewer on that environment would leave the run queued awaiting approval instead of reporting drift.

**Note the two senses of "environment" in the inputs.** `github-environment-prefix` names the GitHub Environment (the identity claim). `environments` is the JSON array of *Terraform* environments to check — `dev`/`tst`/`stg`/`prd` — one matrix leg each, selecting a var-file and a state key. They are unrelated.
