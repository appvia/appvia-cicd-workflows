# Terraform Plan & Apply Workflow for Azure Infrastructure

This GitHub Actions workflow template ([terraform-plan-and-apply-azure.yml](../.github/workflows/terraform-plan-and-apply-azure.yml)) is the **plan & apply** reusable workflow for Azure Terraform repositories. It is modelled on the AWS [terraform-plan-and-apply-aws.yml](./terraform-plan-and-apply-aws.md) engine, but targets Azure: OIDC federation to Entra, an `azurerm` remote-state backend, and a per-environment plan whose JSON feeds the security / policy / cost checks before a single update-in-place PR comment and a merge gate. On push to the default branch (i.e. after a PR merges) it skips that job entirely and runs an **apply** job using the read-write service principal.

Behaviour is **input-driven** — tool versions, toggles, paths and the like arrive as `workflow_call` inputs provided by the calling repo, keeping it compatible with the render-factory model used by the landing-zone accelerator. The Azure identity and state backend are the exception: those come from Actions variables on each job's GitHub Environment, so environments in different subscriptions each supply their own. Only true secrets come via `secrets:`.

**One environment per call.** The workflow plans and applies a single `environment`. Covering several is the caller's job — fan out with `strategy.matrix` over the `uses:` that calls it, which keeps sequencing, `fail-fast` and inter-environment dependencies under your control. See [Migrating from @main](#migrating-from-main) if you are moving off the `environments` array.

## Workflow Steps

The workflow runs a single `validate-and-plan` job, which also posts the PR comment and carries the merge gate as its final step, plus an `apply` job on push to the default branch.

The two are mutually exclusive: `validate-and-plan` is skipped exactly when `apply` will run. Every check it performs — pre-commit, format, TFLint, Checkov, OPA, plan — already passed on the PR that produced the merge commit, so repeating them on the way to apply would cost runner time for no extra signal. Setting `enable-apply` to `false` therefore leaves the plan job running on pushes to the default branch as well.

1. **Resolve tool versions** — hashes the caller's pinned versions for Terraform, TFLint, Conftest, Infracost, commitlint and pre-commit to produce the tool-cache key. Skipped when `install-tools` is `false`, which instead verifies the runner image already provides them.
2. **Install tool binaries** — downloads each tool and **verifies its SHA256 checksum** before use, then caches the binaries (blank-runner caching — no prebuilt image needed).
3. **Commitlint** (optional) — validates PR commit messages against `config/commitlint.config.js` in the calling repository.
4. **Pre-commit** — always runs the repository's own hooks. Deliberately overlaps the standalone checks below: pre-commit proves the hooks still run, the standalone steps prove they still cover what they claim to and are what the merge gate blocks on.
5. **Terraform Format** — `terraform fmt -check -recursive`.
6. **TFLint** — using `config/.tflint.hcl` from the calling repository, or a repository-root `.tflint.hcl`.
7. **GitHub App token** (optional) — mints a token and rewrites `https://github.com/` via `git insteadOf` so **private modules** resolve.
8. **Azure login** — OIDC (`azure/login`) using the **read-only** plan service principal.
9. **Terraform Init / Validate** — initialises the `azurerm` backend and validates.
10. **Terraform Plan** — runs with `-detailed-exitcode`, so the status distinguishes **No changes (0) / Changes detected (2) / Error (1)**.
11. **Convert plan to JSON and delete the binary plan** — the binary `tfplan` embeds state, so it is removed before any third-party tool touches the workspace. Downstream checks read `tfplan_<env>.json`.
12. **Plan summary** — writes add/change/destroy/replace counts and changed resource addresses to the GitHub Actions job summary. It deliberately excludes Terraform resource values.
13. **HTML plan report** — a human-readable report generated for long plans and uploaded as an artifact.
14. **Checkov** — always scans the directory (so inline skip-comments apply), uploaded as SARIF.
15. **OPA / Conftest** (optional) — policies checked into the calling repository under `policies/opa`, `conftest verify`-checked before `conftest test`. Skips cleanly when the directory holds no `*.rego`.
16. **Post PR comment** — a status table plus per-section, character-budgeted detail blocks (65k-safe), linking the HTML report artifact. Scoped to the environment by a hidden marker, so a matrix caller gets one comment per leg.
17. **Final result** — the last step of the plan job, and the status check to require under branch protection.
18. **Apply** — on push to the default branch only (`enable-apply`, default `true`), and the only job that runs then. Logs in with the **read-write** service principal — the `ALZ_AZURE_CLIENT_ID` variable on the `<env>-apply` environment — re-initialises the backend, and runs `terraform apply` (re-plan + apply model — the PR plan binary is intentionally not persisted).

## Usage

Create a new workflow file in your Azure Terraform repository (e.g. `.github/workflows/terraform-plan.yml`). Fan out with `strategy.matrix` to cover `dev`/`tst`/`stg`/`prd`:

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
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-azure.yml@v1
    with:
      # Azure identity and state backend are NOT passed here — they come from
      # Actions variables on each job's GitHub Environment. See below.
      # Names the Terraform environment and its two GitHub Environments,
      # e.g. "dev" plans in dev-plan and applies in dev-apply
      environment: ${{ matrix.environment }}
      working-directory: terraform
      terraform-version: "<pinned-version>"
      node-version: "22"
      tflint-version: "<pinned-version>"
      conftest-version: "<pinned-version>"
      infracost-version: "<pinned-version>"
      commitlint-version: "<pinned-version>"
      pre-commit-version: "<pinned-version>"
      enable-checkov: true
      enable-infracost: false
      # Optional: private module access
      github-app-id: <MODULE_ACCESS_APP_ID>
    secrets:
      infracost-api-key: ${{ secrets.INFRACOST_API_KEY }}
      github-app-private-key: ${{ secrets.MODULE_ACCESS_PRIVATE_KEY }}
```

## Inputs

The Azure identity and the state backend are **not** inputs. They are read from Actions variables on the GitHub Environment each job enters — see [Environment configuration](#environment-configuration) below.

### Required Inputs

- `environment` - The Terraform environment to plan/apply, e.g. `dev`. Also names the two GitHub Environments the jobs enter, `<environment>-plan` and `<environment>-apply`

### Optional Inputs

- `terraform-state-key` - Default: "<environment>.tfstate". State blob key
- `working-directory` - Default: "terraform". Directory holding the root module
- `terraform-version` - Default: blank. A pinned Terraform version, required when `install-tools` is true
- `node-version` - Default: "22". A pinned Node.js version; blank and `latest` are not supported
- `install-tools` - Default: true. **All or nothing.** `true` installs the complete checksum-verified toolchain and requires every `*-version` input to be pinned; `false` installs nothing and instead verifies a bring-your-own runner image already provides every tool the job needs. When `false`, every `*-version` input is ignored
- `tflint-version` / `conftest-version` / `infracost-version` / `commitlint-version` / `pre-commit-version` - Default: blank. Pinned tool versions, each required when `install-tools` is true. `latest` is not supported
- `terraform-var-file` - Default: "environments/<environment>.tfvars". Env var-file. **The run fails if it does not exist**
- `terraform-common-var-file` - Default: "environments/common.tfvars". Shared var-file, applied when present
- `terraform-init-extra-args` - Additional arguments passed to `terraform init`
- `terraform-plan-extra-args` / `terraform-apply-extra-args` - Extra args appended to plan / apply
- `terraform-parallelism` - Default: 10. Parallelism for plan
- `runs-on` - Default: "ubuntu-latest". Runner label
- `job-timeout-minutes` - Default: 90. Timeout applied to both jobs
- `enable-apply` - Default: true. Run terraform apply on push to the default branch
- `enable-commitlint` - Default: false. Run commitlint on the PR commits
- `pre-commit-config-file` - Default: ".pre-commit-config.yaml". Pre-commit always runs and the workflow fails when the file does not exist — start from [config/.pre-commit-config.yaml](../config/.pre-commit-config.yaml)
- Checkov configuration - The workflow always requires a repository-root `.checkov.yml`; it fails before scanning when the file does not exist
- `upload-sarif` - Default: true. Upload Checkov SARIF results to GitHub Security. Set to false when GitHub Advanced Security is not available
- `enable-infracost` - Default: false. Run Infracost cost estimation (requires `infracost-api-key`)
- OPA policies - Mandatory: OPA/Conftest policy checks always run. Store repository-local Rego policies under `policies/opa`. The check reports `skipped` when the directory is absent or holds no `*.rego`
- `terraform-log-level` - `TF_LOG` value for plan and apply. Blank (default) disables Terraform debug logging
- `github-app-id` - GitHub App ID for pulling private modules (blank disables)
- `github-app-owner` - Default: "appvia". Owner the GitHub App token is scoped to

### Optional Secrets

- `infracost-api-key` - The API key for infracost (required if `enable-infracost` is true)
- `github-app-private-key` - Private key for the GitHub App (required if `github-app-id` is set)

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

## Migrating from @main

The Azure engines have never shipped in a tagged release — `v1.0.0` is their first. If you are pinned to a tag, nothing changes for you. **Only callers pinned to `@main` are affected**, and for them the input contract below is a breaking change. Pin to a SHA if you need time.

| Before (`@main`, pre-v1.0.0) | v1 |
| --- | --- |
| `environments: '["dev", "tst", "stg", "prd"]'` | `environment: ${{ matrix.environment }}` with `strategy.matrix` on the calling job |
| `opa-policies-repo-and-path` | Removed — central policies are no longer pulled |
| `opa-policies-version` | Removed |
| — | `install-tools`, `pre-commit-config-file`, `pre-commit-version` |

Three further changes to be aware of:

1. **Required status checks change.** The `comment` and `Final Result` jobs are gone — both are now steps of the plan job. Under branch protection, require **`Validate and Plan (<environment>)`** (one per matrix leg) and remove the old `Final Result` entry.
2. **A missing var-file now fails fast.** Previously plan and apply surfaced this as a confusing `terraform plan` error; they now fail on the resolution step, matching drift and destroy.
3. **A broken Rego policy now blocks.** A syntax error in a local policy previously caused `conftest test` to be skipped and the gate to pass. `verify` and `test` are now one check, so broken policies report `failure`.

The consumer-side matrix:

```yml
jobs:
  terraform:
    strategy:
      fail-fast: false
      matrix:
        environment: [dev, tst, stg, prd]
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-azure.yml@v1
    with:
      environment: ${{ matrix.environment }}
    secrets: inherit
```

A matrix fan-out produces **one** workflow run shared by every leg, so artifact names (`plan-<env>`) and PR-comment markers stay environment-scoped.

## Environment configuration

**The GitHub Environment is named after the Terraform environment.** Each environment you call the workflow for needs two of them — one per phase — so a matrix of `[dev, tst, stg, prd]` needs eight:

| Terraform environment | Plan job enters | Apply job enters |
| --- | --- | --- |
| `dev` | `dev-plan` | `dev-apply` |
| `tst` | `tst-plan` | `tst-apply` |
| `stg` | `stg-plan` | `stg-apply` |
| `prd` | `prd-plan` | `prd-apply` |

All of them must already exist in the calling repository — the workflow does not create them, and a job naming an environment that does not exist fails.

Entering an environment does three things:

1. **Supplies the configuration.** The Azure identity and state backend come from that environment's Actions variables (below), so each environment can point at its own subscription, service principal and storage account.
2. **Scopes the OIDC token.** The environment name becomes the `environment` claim, which is what the Entra federated credential subjects are scoped to. Because the claim differs per environment *and* per phase, each service principal needs a federated credential registered for **every** name it is expected to serve — e.g. subjects for `dev-plan` through `prd-plan` on the read-only SPs.
3. **Gates each apply independently.** Required-reviewer and wait-timer rules live on the individual `<env>-apply` environments, so `prd-apply` can require approval while `dev-apply` runs unattended. Leave every `<env>-plan` unprotected so PR plans are never blocked.

### Actions variables

Set these on **every** environment in the table above (Settings → Environments → *environment* → Variables):

| Variable | Purpose |
| --- | --- |
| `ALZ_AZURE_CLIENT_ID` | Entra service principal client ID — the **read-only** SP on each `<env>-plan`, the **read-write** SP on each `<env>-apply` |
| `ALZ_AZURE_TENANT_ID` | Entra tenant ID |
| `ALZ_AZURE_SUBSCRIPTION_ID` | Target subscription ID for that environment |
| `ALZ_BACKEND_RESOURCE_GROUP_NAME` | Resource group of the Terraform state storage account |
| `ALZ_BACKEND_STORAGE_ACCOUNT_NAME` | Terraform state storage account name |
| `ALZ_BACKEND_CONTAINER_NAME` | Blob container for state; one container per repository |

The plan/apply split is entirely a property of *which* environment the job entered — the workflow reads the same `ALZ_AZURE_CLIENT_ID` name in both jobs.

These cannot be passed as inputs instead. A caller job that invokes a reusable workflow may not declare an `environment:`, so environment-scoped variables are only resolvable inside this workflow, where the plan and apply jobs declare theirs.

## Related workflows

- [Terraform Drift Detection (Azure)](./terraform-drift-azure.md) — scheduled `plan -detailed-exitcode` against deployed state, raising a GitHub issue on drift. Reuses the same `<env>-plan` environments.
- [Terraform Destroy (Azure)](./terraform-destroy-azure.md) — guarded teardown, one explicit environment per dispatch. Reuses the same `<env>-apply` environments.
