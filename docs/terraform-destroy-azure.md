# Terraform Destroy Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-destroy-azure.yml](../.github/workflows/terraform-destroy-azure.yml)) is the **guarded teardown** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-destroy.yml](./terraform-destroy.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. Like the plan/apply engine it is **input-driven**.

## Guard

The workflow only proceeds when the `confirmation` input **exactly equals the calling repository** (`<owner>/<repo>`). This makes accidental destruction effectively impossible — the caller must deliberately pass the repository slug. Destroy uses the **read-write** service principal.

The job also enters the `<prefix>-apply` GitHub Environment, so any **required reviewers** configured on it hold the teardown until someone approves — a second, human check alongside the confirmation string.

## Workflow steps

1. **Confirmation check** — fails immediately unless `confirmation == github.repository`.
2. **Install Terraform** and, optionally, mint a **GitHub App token** so private modules resolve.
3. **Azure login** — OIDC (`azure/login`) with the read-write service principal.
4. **Terraform init** — initialises the `azurerm` backend for the environment's state key.
5. **Terraform destroy** — `terraform destroy -auto-approve` with the environment var-file (and optional common var-file).

## Usage

Add a manually-triggered caller in your Azure Terraform repository:

```yml
name: Terraform Destroy
on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: "Type <owner>/<repo> to confirm destruction"
        required: true

permissions:
  id-token: write
  contents: read

jobs:
  destroy:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-destroy-azure.yml@main
    with:
      confirmation: ${{ github.event.inputs.confirmation }}
      azure-client-id: ${{ vars.AZURE_APPLY_CLIENT_ID }}
      azure-tenant-id: "<CUSTOMER_TENANT_ID>"
      azure-subscription-id: "<CUSTOMER_MANAGEMENT_SUBSCRIPTION_ID>"
      backend-resource-group-name: ${{ vars.AZURE_TFSTATE_RESOURCE_GROUP }}
      backend-storage-account-name: ${{ vars.AZURE_TFSTATE_STORAGE_ACCOUNT }}
      backend-container-name: tfstate
      # GitHub Environment the job enters: prod-apply
      github-environment-prefix: prod
      # Terraform environment being torn down
      environment: prd
    secrets:
      github-app-private-key: ${{ secrets.ORG_LZ_ACTION_SECRET }}
```

## GitHub Environment

The job runs in the `<prefix>-apply` GitHub Environment, where `<prefix>` is the required `github-environment-prefix` input — the same environment the [plan & apply](./terraform-plan-and-apply-azure.md) workflow uses for its apply. It must already exist; the workflow does not create it.

It holds no configuration. Entering it puts the `environment` claim in the OIDC token, which is what the Entra federated credential subject for the read-write service principal is scoped to, and it applies that environment's protection rules to the teardown.

**Note the two senses of "environment" in the inputs.** `github-environment-prefix` names the GitHub Environment (identity claim and approval gate). `environment` names the *Terraform* environment being destroyed — `dev`/`tst`/`stg`/`prd` — which selects the var-file and the state key. They are unrelated, and unlike the plan/apply engine this one is deliberately **singular**: a teardown is one explicit environment per dispatch, never a matrix.
