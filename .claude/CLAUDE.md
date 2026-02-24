# CLAUDE.md — appvia-cicd-workflows

## Project Overview

Reusable GitHub Actions workflows and composite actions for Terraform, Terragrunt, and Docker CI/CD pipelines. AWS-focused. Used across Appvia repositories via `workflow_call`.

Licensed under Apache 2.0.

## Repository Structure

```
.github/
  workflows/       # Reusable workflow files (workflow_call triggers)
  actions/         # Composite actions (used by workflows)
  dependabot.yml   # Weekly GitHub Actions dependency updates
config/
  .tflint.hcl      # TFLint config (AWS plugin, required tags: Product, Environment, Owner)
  commitlint.config.js
scripts/
  render-diff.sh          # Terragrunt input diff between branches
  update-documetation.sh  # Batch terraform-docs PR creation (note: filename has typo, preserved intentionally)
docs/              # Markdown docs for each workflow
```

## Workflows

### Terraform

| Workflow | Purpose |
|---|---|
| `terraform-plan-and-apply-aws.yml` | Full plan/apply pipeline with lint, security scan, cost estimation, PR comments |
| `terraform-module-validation.yml` | Module validation: format, lint, security, tests, docs generation |
| `terraform-module-release.yml` | Tag-based release with optional git-cliff changelog |
| `terraform-destroy.yml` | Destroy pipeline with repository-name confirmation safety check |
| `terraform-drift.yml` | Drift detection with Slack notifications |

### Terragrunt

| Workflow | Purpose |
|---|---|
| `terragrunt-plan-and-apply-aws.yml` | Full plan/apply with matrix execution across units |
| `terragrunt-dispatch.yml` | Manual trigger wrapper for terragrunt-plan-and-apply-aws |

### Docker

| Workflow | Purpose |
|---|---|
| `docker-build.yml` | Build, scan (Trivy/Hadolint), push to ECR/Docker Hub, multi-platform |

### Utility

| Workflow | Purpose |
|---|---|
| `template-update.yml` | Sync files from template repositories via PR |
| `github-workflow-validation.yml` | Validate workflow syntax with actionlint |
| `validate.yml` | Repo validation: commitlint, actionlint, yamllint |

## Composite Actions

| Action | Purpose |
|---|---|
| `terraform-bootstrap` | Setup Terraform + AWS OIDC auth + S3 backend init |
| `terraform-bootstrap-noauth` | Setup Terraform without AWS auth (for lint/validate jobs) |
| `terragrunt-bootstrap` | Setup Terragrunt + Terraform + AWS OIDC auth |
| `terragrunt-bootstrap-unauth` | Setup Terragrunt without AWS auth |
| `terragrunt-diff` | Compare Terragrunt inputs between PR and main, post PR comment |
| `terragrunt-matrix` | Discover Terragrunt units, build job matrix for parallel execution |
| `terragrunt-pr` | Aggregate and post workflow status as PR comment |
| `template-update` | Pull files from template repos, create update PRs |

## Key Patterns and Conventions

### Naming

- Workflows: `{tool}-{operation}[-{platform}].yml` (e.g., `terraform-plan-and-apply-aws.yml`)
- Actions: `{tool}-{operation}` with `-noauth`/`-unauth` suffix for unauthenticated variants
- Inputs: kebab-case. Boolean flags use `enable-*` prefix. Versions use `{tool}-version`
- Secrets: `{service}-{credential-type}` (e.g., `actions-id`, `actions-secret`, `infracost-api-key`)

### AWS Authentication

- Uses GitHub OIDC tokens written to `/tmp/web_identity_token_file`
- Role determination by branch:
  - `main` branch: write role — `{aws-role}` or `{aws-role}-{env}`
  - PR branches: read-only role — `{aws-role}-ro` or `{aws-role}-{env}-ro`
- Custom role names via `aws-read-role-name` and `aws-write-role-name` inputs override default behavior
- `use-env-as-suffix` appends environment name to role and state key

### Terraform State

- S3 backend bucket pattern: `{account-id}-{region}-tfstate`
- State key: `{repo-name}.tfstate` or `{repo-name}-{environment}.tfstate` when `use-env-as-suffix` is true
- Encryption enabled, lockfile support enabled

### Private Module Access

- Controlled by `enable-private-access` input
- Uses GitHub App token (`actions-id` + `actions-secret`) via `actions/create-github-app-token`
- Rewrites git URLs: `https://github.com/` → `https://x-access-token:{token}@github.com/`

### PR Comments

- Workflows find and update existing bot comments (avoid duplicates)
- Comments include workflow run links, actor, and per-job status with emoji indicators
- Terragrunt workflows aggregate matrix job results into a single comment

### Job Structure

- Debug mode job: determines `TF_LOG` level from runner debug mode
- Bootstrap jobs: use composite actions, capture step outcomes as outputs
- Plan jobs: upload `tfplan` as artifact with SHA256 checksums
- Apply jobs: validate checksums, use GitHub environment protection (`environment: ${{ inputs.environment }}`)
- Security scanning: Trivy and Checkov (both toggleable via `enable-*` inputs)
- Cost estimation: Infracost (optional, requires API key)

### Terragrunt Matrix Execution

- `terragrunt-matrix` action discovers units from directory structure (`accounts/` tree)
- Extracts region and account from path hierarchy
- Outputs a JSON matrix for `strategy.matrix` in downstream jobs

### Action Pinning

- All third-party actions are pinned to full SHA with version comment (e.g., `actions/checkout@<sha> # v4`)
- Renovate and Dependabot both configured for automated updates
- Renovate uses digest pinning for GitHub Actions

## Commit Conventions

Conventional commits enforced via commitlint:

- Types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`
- Header max 100 chars, body lines max 100 chars
- Subject must not be empty, no sentence-case/start-case/pascal-case/upper-case
- No trailing period on subject

## Linting and Validation

- **Terraform**: `terraform fmt`, TFLint (with AWS plugin), `terraform validate`
- **Terragrunt**: `terragrunt hclfmt`
- **Security**: Trivy (config + container), Checkov
- **Docker**: Hadolint
- **YAML**: yamllint (config in `.yamllint.yaml`, line-length disabled)
- **Workflows**: actionlint
- **Commits**: commitlint (config in `.commitlintrc.yaml` and `config/commitlint.config.js`)

## Adding or Modifying Workflows

1. All workflows use `workflow_call` trigger — they are invoked from other repositories
2. Keep the common input interface: `aws-account-id`, `aws-region`, `aws-role`, `cicd-repository`, `cicd-branch`, `enable-*` flags, `runs-on`, `working-directory`
3. Pin all third-party actions to full SHA with a `# vN` comment
4. Use composite actions from `.github/actions/` for bootstrap/setup logic
5. Update corresponding docs in `docs/` when changing workflow inputs or behavior
6. Sensitive values go through `secrets:` block, not `inputs:`
7. Shell steps must set `shell: bash` explicitly in composite actions

## Scripts

- `scripts/render-diff.sh`: Requires `terragrunt`, `jq`, `git`. Compares Terragrunt rendered inputs between two branches. Supports `NO_COLOR=true` for CI. Used by the `terragrunt-diff` action.
- `scripts/update-documetation.sh`: Batch utility to regenerate and PR terraform-docs across multiple module repos.
