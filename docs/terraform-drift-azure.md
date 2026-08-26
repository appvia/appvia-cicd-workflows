# Terraform Drift Detection Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-drift-azure.yml](../.github/workflows/terraform-drift-azure.yml)) is the **scheduled drift detection** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-drift.yml](./terraform-drift.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. Behaviour is **input-driven**, while the Azure identity and state backend come from Actions variables on the GitHub Environment the job enters.

## How it works

The **caller** schedules the check (cron). The workflow logs in with the **read-only** service principal and runs `terraform plan -detailed-exitcode` against the deployed state:

- exit `0` — no drift
- exit `2` — **drift detected**
- exit `1` — plan error (the job fails)

One `environment` is checked per call — fan out with `strategy.matrix` on the calling job to cover several. On drift it **opens or updates a GitHub issue** (deduplicated per environment via a hidden marker, labelled `drift`) and, when a `slack-webhook-url` secret is supplied, posts a Slack alert.

## Workflow steps

1. **Install the pinned toolchain** (or verify Terraform when `install-tools` is `false`) and, optionally, mint a **GitHub App token** for private modules.
2. **Azure login** — OIDC (`azure/login`) with the read-only service principal.
3. **Terraform init** — initialises the `azurerm` backend for the environment's state key, with optional `terraform-init-extra-args` appended to the command.
4. **Terraform plan (drift check)** — `-detailed-exitcode`, captured to `drift_output.txt` and converted to JSON before the binary plan is deleted.
5. **Drift summary** — writes action counts and changed resource addresses to the GitHub Actions job summary without including resource values.
6. **Open or update drift issue** — only when drift is detected.
7. **Slack notification** — optional, only when a webhook is configured.

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
    strategy:
      fail-fast: false
      matrix:
        environment: [dev, tst, stg, prd]
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-drift-azure.yml@v1
    with:
      # Azure identity and state backend are NOT passed here — they come from
      # Actions variables on each leg's GitHub Environment. See below.
      # Names the Terraform environment and its GitHub Environment (dev-plan, ...)
      environment: ${{ matrix.environment }}
      terraform-version: "<pinned-version>"
      node-version: "22"
      tflint-version: "<pinned-version>"
      conftest-version: "<pinned-version>"
      infracost-version: "<pinned-version>"
      commitlint-version: "<pinned-version>"
      pre-commit-version: "<pinned-version>"
      # Optional additional arguments passed to terraform init
      # terraform-init-extra-args: '-backend-config="use_azuread_auth=true"'
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

> **Migrating from `@main`:** the `environments` JSON array is replaced by a single `environment` string. Move the fan-out to `strategy.matrix` on your calling job, as above. This workflow has never shipped in a tagged release, so only `@main` callers are affected.

## GitHub Environment

**The GitHub Environment is named after the Terraform environment.** The `environment` input does both jobs: it selects the var-file and state key, and it names the environment the job enters — `dev` runs in `dev-plan`, `prd` in `prd-plan`. These are the same environments the [plan & apply](./terraform-plan-and-apply-azure.md) workflow uses for its PR plans, so a matrix of `[dev, tst, stg, prd]` needs `dev-plan`, `tst-plan`, `stg-plan` and `prd-plan` to exist already. The workflow does not create them.

Entering one supplies that environment's Azure identity and state backend from its Actions variables, and puts the `environment` claim in the OIDC token — which is what the Entra federated credential subject for the read-only service principal is scoped to, so that SP needs a credential registered for each `<env>-plan` name it is expected to serve.

### Actions variables

Read from each `<env>-plan` environment. These are the same variables the [plan & apply](./terraform-plan-and-apply-azure.md) workflow's plan job uses, so if that workflow already runs against these environments there is nothing extra to set up:

| Variable | Purpose |
| --- | --- |
| `ALZ_AZURE_CLIENT_ID` | Read-only Entra service principal client ID |
| `ALZ_AZURE_TENANT_ID` | Entra tenant ID |
| `ALZ_AZURE_SUBSCRIPTION_ID` | Target subscription ID for that environment |
| `ALZ_BACKEND_RESOURCE_GROUP_NAME` | Resource group of the Terraform state storage account |
| `ALZ_BACKEND_STORAGE_ACCOUNT_NAME` | Terraform state storage account name |
| `ALZ_BACKEND_CONTAINER_NAME` | Blob container for state; one container per repository |

**Leave every `<env>-plan` free of protection rules.** Drift runs on a schedule with no one watching; a required reviewer on one of those environments would leave that leg queued awaiting approval instead of reporting drift.
