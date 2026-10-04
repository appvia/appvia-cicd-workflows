# Terragrunt Workflow for AWS Infrastructure

This GitHub Actions workflow template ([terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml)) can be used with Terragrunt repositories to automate the deployment and management of AWS infrastructure. The workflow performs various steps such as authentication with AWS, Terragrunt formatting, HCL validation, linting, planning, and applying changes. It also adds the Terragrunt plan output as a comment to the associated pull request and triggers an apply action for pushes to the main branch.

## Introduction

Terragrunt is a thin wrapper for Terraform that provides extra tools for keeping your configurations DRY, working with multiple Terraform modules, and managing remote state. This workflow provides a complete CI/CD pipeline for Terragrunt-based infrastructure, with support for:

- Multiple deployment units with matrix execution for plan and, on pushes to `main`, for apply
- HCL formatting and validation
- Static security analysis
- Cost estimation with Infracost
- Automated PR comments with plan results
- An aggregated plan summary across all units in matrix mode, focused on the changes rather than the refresh output
- Conditional apply on merge to main

## Workflow Steps

1. **Debug Mode:** Configures Terraform/Terragrunt logging levels based on runner debug mode
2. **Commitlint:** Validates commit messages follow conventional commit format (PR only)
3. **Terragrunt HCL Format:** Checks that all `.hcl` files are properly formatted
4. **Terragrunt Inputs Render:** Validates that Terragrunt can render all input configurations
5. **Terragrunt Format:** Runs `terraform fmt` on all Terraform code within Terragrunt modules
6. **Terragrunt Lint:** Runs TFLint to check for deprecated syntax, unused declarations, and best practices
7. **AWS Authentication:** Uses Web Identity Federation to authenticate with AWS via OIDC
8. **Static Security Analysis:** Runs Trivy to scan for security misconfigurations (placeholder implementation)
9. **Terragrunt Inputs Diff:** Detects which Terragrunt units have changed inputs (pull requests only)
10. **Terragrunt Matrix:** Generates a matrix of Terragrunt units for parallel execution (optional)
11. **Terragrunt Plan:** Runs `terragrunt plan` for all or specific units, either in parallel (matrix mode, one job per unit) or sequentially in a single job
12. **Get Cost Estimate:** Runs Infracost to estimate infrastructure costs (PR only, optional, standard mode only)
13. **Terragrunt Plan Summary:** In matrix mode, aggregates the per-unit plans into one report on the job summary, the job log and the PR (see [Plan Summary](#plan-summary-matrix-mode))
14. **Add PR Comment:** Posts a comprehensive comment to the PR with all validation and plan results
15. **Terragrunt Apply:** Automatically applies changes when merged to `main` (if enabled), using the same per-unit matrix as plan when `enable-matrix` is true, or a single `terragrunt run --all apply` job otherwise

## Usage

Create a new workflow file in your Terragrunt repository (e.g. `.github/workflows/terragrunt.yml`) with the below contents:

```yml
name: Terragrunt
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  contents: read
  id-token: write
  pull-requests: write

jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    name: Plan and Apply
    secrets:
      infracost-api-key: ${{ secrets.ORG_INFRACOST_API_KEY }}
    with:
      aws-account-id: 123456789012
      aws-role: terraform-deployer
      enable-infracost: true
```

## Inputs

### Required Inputs

- `aws-account-id` - The AWS account ID to deploy to

### Optional Inputs

#### AWS Configuration

- `aws-role` - Default: Repository Name. The AWS role to assume
- `aws-read-role-name` - Overrides the default behavior, and uses a custom role name for read-only access
- `aws-write-role-name` - Overrides the default behavior, and uses a custom role name for read-write access
- `aws-region` - Default: "eu-west-2". The AWS region to deploy to
- `aws-web-identity-token-file` - Default: "/tmp/web_identity_token_file". The file containing the AWS web identity token

#### Feature Flags

- `enable-infracost` - Default: false. Whether to run Infracost on the Terragrunt Plan (requires `infracost-api-key` secret)
- `enable-commitlint` - Default: true. Whether to run commitlint on the commit message
- `enable-terragrunt-apply` - Default: true. Whether to run terragrunt apply on merge to main
- `enable-terragrunt-plan` - Default: false. Whether to run terragrunt plan on merge to main (useful for scheduled drift detection)
- `enable-matrix` - Default: false. Whether to run terragrunt plan and apply in matrix mode (one parallel GitHub Actions job per Terragrunt unit)
- `enable-plan-summary` - Default: true. In matrix mode, whether to aggregate the per-unit plans into a single summary on the job summary, job log and pull request (see [Plan Summary](#plan-summary-matrix-mode))
- `enable-private-access` - Default: false. Flag to indicate if Terraform requires pulling private modules
- `organization-name` - The GitHub organization for private module access; defaults to the owner of the calling repository

#### Environment Configuration

- `environment` - Default: "production". The environment to deploy to
- `runs-on` - Default: "ubuntu-latest". Single label value for the GitHub runner to use
- `node-version` - Default: 22. The version of Node.js to use (commitlint)
- `use-env-as-suffix` - Default: false. Whether to use the environment as a suffix for the state file and IAM roles

#### Terragrunt Configuration

- `terragrunt-dir` - Default: ".". The directory to validate
- `terragrunt-version` - Default: "1.0.5". The version of Terragrunt to use
- `terragrunt-config-file` - Default: "terragrunt.hcl". The configuration file to use for Terragrunt
- `terragrunt-apply-extra-args` - Default: "-parallelism=10". Extra arguments to pass to terragrunt apply
- `terragrunt-plan-extra-args` - Default: "-parallelism=10". Extra arguments to pass to terragrunt plan

#### Terraform Configuration

- `terraform-version` - Default: "1.14.5". The version of Terraform to use
- `terraform-apply-extra-args` - Extra arguments to pass to terraform apply
- `terraform-plan-extra-args` - Extra arguments to pass to terraform plan
- `terraform-lock-timeout` - Default: "30s". The time to wait for a state lock
- `terraform-log-level` - The log level of Terraform (DEBUG, TRACE, etc.)
- `terraform-parallelism` - Default: 20. The number of parallel operations to run

#### Security Configuration

- `trivy-version` - Default: "v0.69.3". The version of Trivy to use

### Optional Secrets

- `infracost-api-key` - The API key for Infracost (required if `enable-infracost` is true)
- `actions-id` - The GitHub App ID for accessing private repositories
- `actions-secret` - The GitHub App secret for accessing private repositories
- `environment-variables` - A JSON object of environment variables made available to Terraform, e.g. `{"TF_VAR_name": "value"}`

## Examples

### Basic Usage

Minimal configuration for a Terragrunt repository:

```yml
name: Terragrunt
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  id-token: write
  pull-requests: write

jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
```

### With Infracost

Enable cost estimation for pull requests:

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    secrets:
      infracost-api-key: ${{ secrets.INFRACOST_API_KEY }}
    with:
      aws-account-id: 123456789012
      aws-role: terraform-deployer
      enable-infracost: true
```

### Matrix Mode (Parallel Execution)

Enable parallel execution for faster planning and, on pushes to `main`, parallel apply (one job per unit):

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
      enable-matrix: true
      terragrunt-dir: environments/production
```

### Private Module Access

For repositories that pull private Terraform modules:

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    secrets:
      actions-id: ${{ secrets.GH_APP_ID }}
      actions-secret: ${{ secrets.GH_APP_SECRET }}
    with:
      aws-account-id: 123456789012
      enable-private-access: true
```

### Custom Regions and Roles

Deploy to a specific region with custom IAM roles:

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
      aws-region: us-east-1
      aws-read-role-name: terragrunt-reader
      aws-write-role-name: terragrunt-writer
      environment: staging
```

### Specific Terragrunt Directory

Target a specific directory containing Terragrunt configurations:

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
      terragrunt-dir: infrastructure/aws/prod
      terragrunt-config-file: terragrunt.hcl
```

### Scheduled Drift Detection

Run plan operations on a schedule to detect infrastructure drift:

```yml
name: Drift Detection
on:
  schedule:
    - cron: "0 0 * * *" # Daily at midnight

permissions:
  contents: read
  id-token: write
  pull-requests: write

jobs:
  detect-drift:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
      enable-terragrunt-plan: true
      enable-terragrunt-apply: false
```

### Disable Automatic Apply

Require manual approval for infrastructure changes:

```yml
jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 123456789012
      enable-terragrunt-apply: false
```

Then use the [manual dispatch workflow](./terragrunt-dispatch.md) to apply changes when ready.

### Multiple Environments

Deploy to different environments with environment-specific configuration:

```yml
jobs:
  staging:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    with:
      aws-account-id: 111111111111
      environment: staging
      terragrunt-dir: environments/staging
      use-env-as-suffix: true

  production:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    needs: staging
    with:
      aws-account-id: 222222222222
      environment: production
      terragrunt-dir: environments/production
      use-env-as-suffix: true
```

## Matrix Mode vs. Standard Mode

The workflow supports two execution modes:

### Standard Mode (default)

- Runs all Terragrunt units in a single plan job and a single apply job (`terragrunt run --all`)
- Simpler logs and easier debugging
- Better for smaller infrastructures
- Use when: You have few Terragrunt units or prefer sequential execution

### Matrix Mode (`enable-matrix: true`)

- Detects all Terragrunt units and executes **plan** in parallel: one GitHub Actions job per unit
- On `main`, **apply** uses the same matrix (parallel per unit) instead of a single `terragrunt run --all apply` job
- Significantly faster for large infrastructures
- The per-unit plans are aggregated into a single [plan summary](#plan-summary-matrix-mode), so the change across every account can be reviewed in one place
- Use when: You have many Terragrunt units and want faster feedback and deploys

**Note:** Parallel applies run independently per unit. Ensure your stacks do not rely on a strict apply order across units unless dependencies are modeled in Terragrunt (or accept that GitHub will schedule matrix jobs concurrently).

## Plan Summary (Matrix Mode)

Matrix mode is fast, but it splits the plan across one job per unit, which makes it hard to see what a change does across many accounts. When `enable-matrix` is true, the workflow therefore aggregates the plans from every matrix job into a single report, controlled by `enable-plan-summary` (default: true).

The report contains:

- **Totals** of the resources to add, change, replace and destroy across all units
- **A table** of the units with changes or failures, grouped by account and region; units with no changes are listed in a collapsed section
- **Destructive changes**, always listed: every resource that will be destroyed or replaced, and the unit it belongs to
- **A collapsible plan per unit**, showing only the proposed changes. The refresh output, the "Objects have changed outside of Terraform" section and the `Plan:` totals line are removed, and the plan is rendered as a diff so GitHub highlights it

The report is published to three places:

| Where | When |
| ----- | ---- |
| The workflow run's job summary | Every run that plans, including `schedule` and `workflow_dispatch` |
| The `Terragrunt Plan Summary` job log | Every run that plans. Each unit's plan is a collapsible log group, coloured like Terraform's own output, and destroys or replacements are raised as warning annotations on the run |
| A pull request comment | Pull requests only. A separate comment from the review status comment, updated in place on each push (one per `environment`) |

### How it works

1. Each matrix plan job passes `--out-dir` and `--json-out-dir` to `terragrunt run --all -- plan`, so a plan file is written for every unit
2. The [terragrunt-plan-collect](../.github/actions/terragrunt-plan-collect/action.yml) action counts the changes from each unit's JSON plan, renders the human readable plan with `terragrunt show`, and uploads a compact `summary.json` as the artifact `plan-summary-<environment>--<unit-path>`. It runs even when the plan fails, so failures still appear in the report
3. The `Terragrunt Plan Summary` job runs the [terragrunt-plan-summary](../.github/actions/terragrunt-plan-summary/action.yml) action, which downloads every summary, builds the report and publishes it

Only the counts, the changed resource addresses and the trimmed plan text are uploaded; the raw JSON plan never leaves the matrix job. Sensitive values remain masked, as they are in `terraform show`.

The summary job also works out the overall plan and authentication outcome across the matrix and passes them to the review status comment. Without it, that comment would show the outcome of whichever matrix job finished last. A matrix job that never reports a summary counts as a failure.

### Size limits

GitHub limits pull request comments to 65,536 characters. Each unit's plan is capped at 20,000 characters, and once the comment nears the limit the remaining unit plans are left out with a note. The job summary allows 1MB, so it keeps the full report.

### Running a plan on demand

The plan matrix runs for pull requests, and on `main` for `schedule` events or when `enable-terragrunt-plan` is true. A `workflow_dispatch` run therefore only produces a summary when it runs on `main` with `enable-terragrunt-plan: true`. With the defaults (`enable-terragrunt-plan: false`, `enable-terragrunt-apply: true`) a dispatch runs the apply instead. See the [manual dispatch workflow](./terragrunt-dispatch.md) for a caller that exposes both flags.

To turn the summary off:

```yml
with:
  enable-matrix: true
  enable-plan-summary: false
```

## Pull Request Comments

When the workflow runs on a pull request, it posts a review status comment containing:

- **Commitlint Status:** Whether commit messages follow conventional format
- **HCL Format Status:** Whether all `.hcl` files are properly formatted
- **Terraform Format Status:** Whether all `.tf` files are properly formatted
- **Inputs Render Status:** Whether Terragrunt can render all configurations
- **Inputs Diff Status:** Which Terragrunt units have changed
- **Linting Status:** Results from TFLint
- **Security Status:** Results from Trivy security scan
- **Authentication Status:** Whether AWS authentication succeeded
- **Plan Status:** Whether the plan succeeded
- **Cost Estimate:** Infrastructure cost changes (if Infracost is enabled)

In matrix mode a second comment, the [plan summary](#plan-summary-matrix-mode), shows the changes for every unit.

## AWS Authentication

The workflow uses OpenID Connect (OIDC) to authenticate with AWS, which is more secure than using long-lived access keys. You need to:

1. Configure an OIDC identity provider in your AWS account
2. Create an IAM role with a trust policy for GitHub Actions
3. Grant the role necessary permissions for Terraform/Terragrunt operations

The workflow generates a web identity token file at `/tmp/web_identity_token_file` that can be referenced in Terraform provider configurations if needed.

## Terragrunt Structure Requirements

The workflow expects a standard Terragrunt structure:

```
repository/
├── terragrunt.hcl              # Root Terragrunt configuration
├── environments/
│   ├── production/
│   │   ├── terragrunt.hcl     # Environment-level config
│   │   ├── vpc/
│   │   │   └── terragrunt.hcl # Unit-level config
│   │   └── eks/
│   │       └── terragrunt.hcl # Unit-level config
│   └── staging/
│       └── ...
```

In matrix mode the `terragrunt-matrix` action treats each directory matching the parent pattern (e.g. `accounts/<region>/<account>`) as a unit. Nested units beneath it (e.g. `accounts/<region>/<account>/oam/terragrunt.hcl`) get their own matrix entry and are excluded from the parent's `run --all` via `--queue-exclude-dir`, so each unit is planned and applied exactly once. An account directory with no `terragrunt.hcl` of its own is still picked up: its nested units are included and only they run. Each matrix entry exposes the unit directory as `path`.

## Composite Actions

The workflow is assembled from the following composite actions, which can also be used on their own. See [Composite Actions](./actions.md) for their inputs, outputs and examples.

| Action | Purpose |
| ------ | ------- |
| [terragrunt-bootstrap](./actions.md#terragrunt-bootstrap) | Installs Terraform and Terragrunt, authenticates with AWS and sets up private module access |
| [terragrunt-bootstrap-unauth](./actions.md#terragrunt-bootstrap-unauth) | As above, without AWS authentication (lint and security jobs) |
| [terragrunt-diff](./actions.md#terragrunt-diff) | Diffs the rendered Terragrunt inputs between the pull request and `main` |
| [terragrunt-matrix](./actions.md#terragrunt-matrix) | Finds the Terragrunt units and returns the job matrix used by matrix mode |
| [terragrunt-plan-collect](./actions.md#terragrunt-plan-collect) | Summarises the plan of a single matrix unit and uploads it as an artifact |
| [terragrunt-plan-summary](./actions.md#terragrunt-plan-summary) | Aggregates the matrix summaries into one report for the job summary, job log and pull request |
| [terragrunt-pr](./actions.md#terragrunt-pr) | Posts the review status comment on the pull request |

## Best Practices

1. **Enable Matrix Mode for Large Repos:** Use `enable-matrix: true` for faster plans on pull requests and faster parallel applies on `main` when you have many Terragrunt units
2. **Use Infracost:** Enable cost estimation to understand the financial impact of changes
3. **Pin Versions:** Specify exact versions for Terraform and Terragrunt for reproducibility
4. **Environment Protection:** Use GitHub environment protection rules to require manual approval for production deploys
5. **Scheduled Drift Detection:** Run the workflow on a schedule to detect configuration drift
6. **Commitlint:** Keep `enable-commitlint: true` to maintain clean commit history
7. **Security Scanning:** The workflow includes Trivy for security scanning (currently placeholder - implement as needed)
8. **Review PR Comments:** Always review the automated PR comments before merging, paying particular attention to the destructive changes listed in the plan summary

## Troubleshooting

### Authentication Failures

- Verify your AWS OIDC configuration is correct
- Ensure the IAM role has the necessary permissions
- Check that the role trust policy includes your repository

### Plan Failures

- Review the plan output in the GitHub Actions logs
- Check for syntax errors or invalid configurations
- Ensure all required variables are provided
- Verify network connectivity to AWS

### Matrix Mode Issues

- Ensure your Terragrunt structure follows the expected format
- Check that `terragrunt.hcl` files are in the correct locations
- Review the matrix generation step output for debugging
- For failures during matrix apply on `main`, inspect the per-unit job that failed; jobs run concurrently, so cross-unit ordering is not guaranteed unless modeled in Terragrunt

### Plan Summary Issues

- **No summary:** check that `enable-matrix` and `enable-plan-summary` are both true, and that the run actually planned (see [Running a plan on demand](#running-a-plan-on-demand))
- **A unit shows as failed with no plan:** the matrix job failed before or during the plan; open that unit's job for the logs
- **"matrix job(s) did not report a plan summary":** a matrix job failed before the collect step ran, e.g. during checkout or bootstrap
- **Plans missing from the PR comment:** the comment hit GitHub's size limit; the full report is on the workflow run's job summary

### Formatting Failures

- Run `terragrunt hclfmt` locally to fix HCL formatting
- Run `terraform fmt -recursive` to fix Terraform formatting
- Commit and push the formatted files

## Comparison with Terraform Workflow

| Feature          | Terragrunt Workflow    | Terraform Workflow   |
| ---------------- | ---------------------- | -------------------- |
| Tool             | Terragrunt + Terraform | Terraform only       |
| DRY Config       | Yes (Terragrunt)       | No                   |
| Matrix Execution | Yes (optional)         | No                   |
| Plan Summary     | Yes (matrix mode)      | Plan in PR comment   |
| HCL Formatting   | Yes                    | N/A                  |
| Multi-module     | Native support         | Manual management    |
| State Management | Terragrunt-managed     | Manual configuration |

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

## Related Documentation

- [Terragrunt Manual Dispatch](./terragrunt-dispatch.md) - Manually trigger Terragrunt operations
- [Terraform Plan & Apply (AWS)](./terraform-plan-and-apply-aws.md) - Similar workflow for plain Terraform
