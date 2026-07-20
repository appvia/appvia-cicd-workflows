# Terraform Plan Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-plan-azure.yml](../.github/workflows/terraform-plan-azure.yml)) is the **Flow A (plan & review)** reusable workflow for Azure Terraform repositories. It is modelled on the AWS [terraform-plan-and-apply-aws.yml](./terraform-plan-and-apply-aws.md) engine, but targets Azure: OIDC federation to Entra, an `azurerm` remote-state backend, and a per-environment plan whose JSON feeds the security / policy / cost checks before a single update-in-place PR comment and a merge gate.

Unlike the env-var-driven Azure engines elsewhere in the org, this workflow is **input-driven** — every value arrives as a `workflow_call` input (rendered from `customer-install.sh` in the calling repo). Only true secrets come via `secrets:`. This keeps it compatible with the render-factory model used by the landing-zone accelerator.

## Workflow Steps

The workflow runs one `validate-and-plan` job per environment, then a `comment` job and a `final-result` merge gate.

1. **Resolve tool versions** — translates `latest` into concrete versions for Terraform, TFLint, Checkov, Conftest, Infracost and commitlint, and produces a hash used as the tool-cache key.
2. **Install tool binaries** — downloads each tool and **verifies its SHA256 checksum** before use, then caches the binaries (blank-runner caching — no prebuilt image needed).
3. **Commitlint** (optional) — validates PR commit messages against the central commitlint config.
4. **Terraform Format** — `terraform fmt -check -recursive`.
5. **TFLint** — using the centralised `.tflint.hcl`.
6. **GitHub App token** (optional) — mints a token and rewrites `https://github.com/` via `git insteadOf` so **private modules and central policies** resolve.
7. **Azure login** — OIDC (`azure/login`) using the **read-only** plan service principal.
8. **Terraform Init / Validate** — initialises the `azurerm` backend and validates.
9. **Terraform Plan** — runs with `-detailed-exitcode`, so the status distinguishes **No changes (0) / Changes detected (2) / Error (1)**.
10. **Convert plan to JSON and delete the binary plan** — the binary `tfplan` embeds state, so it is removed before any third-party tool touches the workspace. Downstream checks read `tfplan_<env>.json`.
11. **HTML plan report** — a human-readable report generated for long plans and uploaded as an artifact.
12. **Checkov** (optional) — scans the directory (so inline skip-comments apply), uploaded as SARIF.
13. **OPA / Conftest** (optional) — **central** policies pulled via `conftest pull` plus **local** `policies/opa`, each `conftest verify`-checked before `conftest test`.
14. **Infracost** (optional) — cost estimate (requires `infracost-api-key`).
15. **Post PR comment** — one comment per environment with a status table and per-section, character-budgeted detail blocks (65k-safe), linking the HTML report artifact.
16. **Final result** — blocks merge if the plan job did not succeed.

## Usage

Create a new workflow file in your Azure Terraform repository (e.g. `.github/workflows/terraform-plan.yml`). The matrix drives one plan per environment (`dev`/`tst`/`stg`/`prd`):

```yml
name: Terraform Plan
on:
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read
  pull-requests: write
  security-events: write

jobs:
  plan:
    strategy:
      fail-fast: false
      matrix:
        environment: [dev, tst, stg, prd]
    name: Plan (${{ matrix.environment }})
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-azure.yml@main
    with:
      # Read-only plan identity (federated per environment during vending)
      azure-client-id: <PLAN_CLIENT_ID>
      azure-tenant-id: <TENANT_ID>
      azure-subscription-id: <SUBSCRIPTION_ID>
      # Remote state backend (from lz-azure-bootstrap)
      backend-resource-group-name: <STATE_RESOURCE_GROUP>
      backend-storage-account-name: <STATE_STORAGE_ACCOUNT>
      backend-container-name: tfstate
      terraform-state-key: <REPO>-${{ matrix.environment }}.tfstate
      # Terraform
      environment: ${{ matrix.environment }}
      working-directory: terraform
      enable-checkov: true
      enable-opa: true
      enable-infracost: false
      # Optional: central OPA policies + private module access
      opa-policies-repo-and-path: github.com/appvia/policies//policies/terraform
      github-app-id: <MODULE_ACCESS_APP_ID>
    secrets:
      infracost-api-key: ${{ secrets.INFRACOST_API_KEY }}
      github-app-private-key: ${{ secrets.MODULE_ACCESS_PRIVATE_KEY }}
```

## Inputs

### Required Inputs

- `azure-client-id` - Client ID of the plan (read-only) Entra service principal
- `azure-tenant-id` - Entra tenant ID
- `azure-subscription-id` - Target subscription ID
- `backend-resource-group-name` - Resource group of the Terraform state storage account
- `backend-storage-account-name` - Terraform state storage account name
- `environment` - The environment being planned (dev/tst/stg/prd)

### Optional Inputs

- `backend-container-name` - Default: "tfstate". Blob container for state
- `terraform-state-key` - Default: "<environment>.tfstate". State blob key
- `working-directory` - Default: "terraform". Directory holding the root module
- `terraform-version` - Default: "1.14.0". Terraform version (`latest` resolves newest)
- `tflint-version` / `checkov-version` / `conftest-version` / `infracost-version` / `commitlint-version` - Default: "latest". Tool versions; concrete values are checksum-verified and cached
- `terraform-values-file` - Default: "environments/<environment>/terraform.tfvars". Env var-file
- `terraform-common-values-file` - Default: "environments/common/terraform.tfvars". Shared var-file applied to every environment
- `terraform-plan-extra-args` - Extra args appended to terraform plan
- `terraform-parallelism` - Default: 10. Parallelism for plan
- `runs-on` - Default: "ubuntu-latest". Runner label
- `enable-commitlint` - Default: false. Run commitlint on the PR commits
- `enable-checkov` - Default: true. Run Checkov static analysis
- `enable-opa` - Default: true. Run OPA/Conftest policy checks
- `enable-infracost` - Default: false. Run Infracost cost estimation (requires `infracost-api-key`)
- `github-app-id` - GitHub App ID for pulling private modules and central policies (blank disables)
- `github-app-owner` - Default: "appvia". Owner the GitHub App token is scoped to
- `opa-policies-repo-and-path` - Conftest pull source for central OPA policies (e.g. `github.com/appvia/policies//policies/terraform`). Blank skips central checks
- `opa-policies-version` - Default: "main". Git ref for the central OPA policies
- `cicd-repository` - Default: "appvia/appvia-cicd-workflows". Repo hosting centralised config (tflint, commitlint)
- `cicd-branch` - Default: "main". Ref of the centralised config repo

### Optional Secrets

- `infracost-api-key` - The API key for infracost (required if `enable-infracost` is true)
- `github-app-private-key` - Private key for the GitHub App (required if `github-app-id` is set)

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

## Related Flows

- **Flow B (merge → gated apply)** — to follow.
- **Flow C (drift / manual / unlock)** — out of scope for now (deferred).
