# Terraform Plan & Apply Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-plan-and-apply-azure.yml](../.github/workflows/terraform-plan-and-apply-azure.yml)) is the **plan & apply** reusable workflow for Azure Terraform repositories. It is modelled on the AWS [terraform-plan-and-apply-aws.yml](./terraform-plan-and-apply-aws.md) engine, but targets Azure: OIDC federation to Entra, an `azurerm` remote-state backend, and a per-environment plan whose JSON feeds the security / policy / cost checks before a single update-in-place PR comment and a merge gate. On push to the default branch (i.e. after a PR merges) it runs an **apply** job using the read-write service principal.

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
17. **Apply** — on push to the default branch only (`enable-apply`, default `true`). Logs in with the **read-write** service principal (the `ALZ_AZURE_CLIENT_ID` variable on the `<prefix>-apply` environment, or the `azure-apply-client-id` input when set), re-initialises the backend, and runs `terraform apply` (re-plan + apply model — the PR plan binary is intentionally not persisted).

## Usage

Create a new workflow file in your Azure Terraform repository (e.g. `.github/workflows/terraform-plan.yml`). The `environments` array drives one plan per environment (`dev`/`tst`/`stg`/`prd`):

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
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-azure.yml@main
    with:
      # Remote state backend (from lz-azure-bootstrap)
      backend-container-name: tfstate
      # Terraform
      environments: '["dev", "tst", "stg", "prd"]'
      github-environment-prefix: prod
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

The Azure identity and the state backend are **not** inputs. They are read from Actions variables on the GitHub Environment each job enters — see [Environment configuration](#environment-configuration) below.

### Required Inputs

- `environments` - JSON array of environments to plan/apply, e.g. `'["dev", "tst", "stg", "prd"]'`. One matrix leg runs per entry
- `backend-container-name` - Blob container for state; one container per repository

### Optional Inputs

- `github-environment-prefix` - Default: "prod". Prefix of the GitHub Environments the jobs run in — the plan job runs in `<prefix>-plan`, the apply job in `<prefix>-apply`
- `azure-apply-client-id` - Client ID of the apply (read-write) Entra service principal. Overrides `ALZ_AZURE_CLIENT_ID` on the apply environment
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

## Environment configuration

The plan job runs in the `<prefix>-plan` GitHub Environment and the apply job in `<prefix>-apply`, where `<prefix>` is `github-environment-prefix` (default `prod`). Both environments must already exist in the calling repository — entering an environment is what makes its Actions variables readable and what puts the `environment` claim in the OIDC token that the federated credential subjects are scoped to. The apply environment is also where required-reviewer rules belong, since entering it is what gates the apply.

Set the following **Actions variables** (Settings → Environments → *environment* → Variables) on each environment:

| Variable | Purpose |
| --- | --- |
| `ALZ_AZURE_CLIENT_ID` | Entra service principal client ID — the read-only SP on `<prefix>-plan`, the read-write SP on `<prefix>-apply` |
| `ALZ_AZURE_TENANT_ID` | Entra tenant ID |
| `ALZ_AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `ALZ_BACKEND_RESOURCE_GROUP_NAME` | Resource group of the Terraform state storage account |
| `ALZ_BACKEND_STORAGE_ACCOUNT_NAME` | Terraform state storage account name |

These cannot be passed as workflow inputs: a caller job that invokes a reusable workflow may not declare an `environment:`, so environment-scoped variables are only readable inside this workflow, where the plan and apply jobs declare theirs.

## Related Flows

- **Flow B (merge → gated apply)** — to follow.
- **Flow C (drift / manual / unlock)** — out of scope for now (deferred).
