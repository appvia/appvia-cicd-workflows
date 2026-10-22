# Terraform Drift Detection Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-drift-azure.yml](../.github/workflows/terraform-drift-azure.yml)) is the **scheduled drift detection** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-drift.yml](./terraform-drift.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. Behaviour is **input-driven**, while the Azure identity and state backend come from Actions variables on the GitHub Environment each leg enters.

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
      # Azure identity and state backend are NOT passed here — they come from
      # Actions variables on each leg's GitHub Environment. See below.
      backend-container-name: tfstate
      # Terraform environments to check — one matrix leg each, and each
      # also names its GitHub Environment (dev-plan, tst-plan, ...)
      environments: '["dev", "tst", "stg", "prd"]'
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

## GitHub Environment

**The GitHub Environment is named after the Terraform environment.** Each entry in `environments` does both jobs: it selects that leg's var-file and state key, and it names the environment the leg enters — `dev` runs in `dev-plan`, `prd` in `prd-plan`. These are the same environments the [plan & apply](./terraform-plan-and-apply-azure.md) workflow uses for its PR plans, so a matrix of `["dev", "tst", "stg", "prd"]` needs `dev-plan`, `tst-plan`, `stg-plan` and `prd-plan` to exist already. The workflow does not create them.

Entering one supplies that leg's Azure identity and state backend from the environment's Actions variables, and puts the `environment` claim in the OIDC token — which is what the Entra federated credential subject for the read-only service principal is scoped to, so that SP needs a credential registered for each `<env>-plan` name it is expected to serve.

### Actions variables

Read from each `<env>-plan` environment. These are the same variables the [plan & apply](./terraform-plan-and-apply-azure.md) workflow's plan job uses, so if that workflow already runs against these environments there is nothing extra to set up:

| Variable | Purpose |
| --- | --- |
| `ALZ_AZURE_CLIENT_ID` | Read-only Entra service principal client ID |
| `ALZ_AZURE_TENANT_ID` | Entra tenant ID |
| `ALZ_AZURE_SUBSCRIPTION_ID` | Target subscription ID for that environment |
| `ALZ_BACKEND_RESOURCE_GROUP_NAME` | Resource group of the Terraform state storage account |
| `ALZ_BACKEND_STORAGE_ACCOUNT_NAME` | Terraform state storage account name |

**Leave every `<env>-plan` free of protection rules.** Drift runs on a schedule with no one watching; a required reviewer on one of those environments would leave that leg queued awaiting approval instead of reporting drift.
