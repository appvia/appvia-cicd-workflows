# Terraform Destroy Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-destroy-azure.yml](../.github/workflows/terraform-destroy-azure.yml)) is the **guarded teardown** reusable workflow for Azure Terraform repositories. It mirrors the AWS [terraform-destroy.yml](./terraform-destroy.md) engine, but targets Azure: OIDC federation to Entra and an `azurerm` remote-state backend. Like the plan/apply engine, behaviour is **input-driven** while the Azure identity and state backend come from Actions variables on the GitHub Environment the job enters.

## Guard

The workflow only proceeds when the `confirmation` input **exactly equals the calling repository** (`<owner>/<repo>`). This makes accidental destruction effectively impossible — the caller must deliberately pass the repository slug. Destroy uses the **read-write** service principal.

The job also enters the `<environment>-apply` GitHub Environment, so any **required reviewers** configured on it hold the teardown until someone approves — a second, human check alongside the confirmation string.

## Workflow steps

1. **Confirmation check** — fails immediately unless `confirmation == github.repository`.
2. **Install the pinned toolchain** (or, with `install-tools: false`, verify the runner image already provides Terraform) and, optionally, mint a **GitHub App token** so private modules resolve.
3. **Azure login** — OIDC (`azure/login`) with the read-write service principal.
4. **Terraform init** — initialises the `azurerm` backend for the environment's state key, with optional `terraform-init-extra-args` appended to the command.
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
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-destroy-azure.yml@v1
    with:
      confirmation: ${{ github.event.inputs.confirmation }}
      # Azure identity and state backend are NOT passed here — they come from
      # Actions variables on the prd-apply GitHub Environment. See below.
      environment: prd
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
      github-app-private-key: ${{ secrets.ORG_LZ_ACTION_SECRET }}
```

## GitHub Environment

**The GitHub Environment is named after the Terraform environment.** The `environment` input does both jobs: it selects the var-file and state key, and it names the environment the job enters — destroying `prd` enters `prd-apply`, the same environment the [plan & apply](./terraform-plan-and-apply-azure.md) workflow applies `prd` in. It must already exist; the workflow does not create it.

Entering it supplies the Azure identity and state backend from that environment's Actions variables, puts the `environment` claim in the OIDC token — which is what the Entra federated credential subject for the read-write service principal is scoped to — and applies that environment's protection rules to the teardown.

That reuse is deliberate: whatever approval you require to *change* `prd` is the approval required to *destroy* it, and destroy uses the same credentials, without a second set of either to keep in step.

### Actions variables

Read from the `<environment>-apply` environment. These are the same variables the [plan & apply](./terraform-plan-and-apply-azure.md) workflow's apply job uses, so if that workflow already runs against this environment there is nothing extra to set up:

| Variable | Purpose |
| --- | --- |
| `ALZ_AZURE_CLIENT_ID` | Read-write Entra service principal client ID |
| `ALZ_AZURE_TENANT_ID` | Entra tenant ID |
| `ALZ_AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `ALZ_BACKEND_RESOURCE_GROUP_NAME` | Resource group of the Terraform state storage account |
| `ALZ_BACKEND_STORAGE_ACCOUNT_NAME` | Terraform state storage account name |
| `ALZ_BACKEND_CONTAINER_NAME` | Blob container for state; one container per repository |

Unlike earlier versions of the plan/apply engine, this input has always been **singular** — a teardown is one explicit environment per dispatch, never a matrix. As of v1 the plan/apply and drift engines take a singular `environment` too, and callers fan out with `strategy.matrix` where they need several.
