# Composite Actions

The workflows in this repository are built from the composite actions in [.github/actions](../.github/actions). They can also be used directly in your own workflows:

```yml
steps:
  - uses: appvia/appvia-cicd-workflows/.github/actions/<action-name>@main
```

When the runner resolves an action from this repository it checks out the whole repository, so actions can ship their own scripts and configuration, and work when the repository is private (see [Private repository access](./terraform-plan-and-apply-aws.md#private-repository-access)). As with the workflows, pin to a tag or commit rather than `main` in production.

| Action | Purpose | Used by |
| ------ | ------- | ------- |
| [cicd-config](#cicd-config) | Copies a centralised configuration file (e.g. `config/.tflint.hcl`) into the workspace | [helm-chart-validation.yml](../.github/workflows/helm-chart-validation.yml), [terraform-module-validation.yml](../.github/workflows/terraform-module-validation.yml), [terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml), [terraform-plan-and-apply-azure.yml](../.github/workflows/terraform-plan-and-apply-azure.yml), [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [schema-validate](#schema-validate) | Validates YAML or JSON files against a JSON Schema | Not used by a workflow in this repository; for use by other repositories |
| [terraform-bootstrap](#terraform-bootstrap) | Installs Terraform or OpenTofu, authenticates with AWS and runs `init` against the S3 backend | [terraform-destroy.yml](../.github/workflows/terraform-destroy.yml), [terraform-drift.yml](../.github/workflows/terraform-drift.yml), [terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml) |
| [terraform-bootstrap-noauth](#terraform-bootstrap-noauth) | Installs Terraform or OpenTofu and runs `init -backend=false`, with no AWS credentials | [terraform-module-validation.yml](../.github/workflows/terraform-module-validation.yml), [terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml) |
| [terraform-plan-encrypt](#terraform-plan-encrypt) | Encrypts plan artifacts with AES-256-CBC before they are uploaded | [terraform-destroy.yml](../.github/workflows/terraform-destroy.yml), [terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml) |
| [terraform-plan-decrypt](#terraform-plan-decrypt) | Decrypts plan artifacts encrypted by `terraform-plan-encrypt` | [terraform-destroy.yml](../.github/workflows/terraform-destroy.yml), [terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml) |
| [terragrunt-bootstrap](#terragrunt-bootstrap) | Installs Terraform and Terragrunt, authenticates with AWS and sets up private module access | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-bootstrap-unauth](#terragrunt-bootstrap-unauth) | Installs Terraform and Terragrunt and sets up private module access, with no AWS credentials | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-diff](#terragrunt-diff) | Diffs the rendered Terragrunt inputs between the pull request and `main` | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-matrix](#terragrunt-matrix) | Finds the Terragrunt units in a directory and returns a job matrix | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-plan-collect](#terragrunt-plan-collect) | Summarises the plan of one matrix unit and uploads it as an artifact | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-plan-summary](#terragrunt-plan-summary) | Aggregates the matrix plan summaries into one report for the job summary, job log and pull request | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [terragrunt-pr](#terragrunt-pr) | Posts or updates the Terragrunt review status comment on the pull request | [terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml) |
| [kubernetes-platform-promotion](#kubernetes-platform-promotion) | Validates that workload versions never regress when promoted between environments | [promotion.yml](../.github/workflows/promotion.yml) |
| [template-update](#template-update) | Copies an allowlist of files from a template repository and raises a pull request | - |
| [template-update-azure](#template-update-azure) | Syncs a whole template repository except an exclusion list, and raises a pull request | - |

## Shared Actions

### cicd-config

Source: [.github/actions/cicd-config](../.github/actions/cicd-config/action.yml)

Copies a file from this repository's [config/](../config) directory into the caller's workspace. When the runner resolves any action from this repository it checks out the whole repository next to it, so the file is copied from that checkout rather than downloaded. This works when the repository is private and needs no token, and the configuration is always taken from the same ref as the workflow.

```yml
- name: Retrieve TFLint Configuration
  uses: appvia/appvia-cicd-workflows/.github/actions/cicd-config@main
  with:
    source: config/.tflint.hcl
    destination: .tflint.hcl
```

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `destination` | yes | - | The path to write the file to, relative to the working directory |
| `source` | yes | - | The path of the file within the cicd-workflows repository |
| `working-directory` | no | `.` | The working directory to write the file into |

### schema-validate

Source: [.github/actions/schema-validate](../.github/actions/schema-validate/action.yml)

Validates YAML (`.yml`, `.yaml`) or JSON files against a JSON Schema (Draft 2020-12). Each violation is reported as `file: path/to/key: message`, annotated on the file, and tabulated in the job summary, and the step fails. A path or glob that matches no files, an unparseable file, or an invalid schema also fails the step, so a typo in a path cannot silently pass. An empty YAML document is validated as `{}`.

The action validates one schema per invocation; call it once per schema. Guard a step with `hashFiles(...)` if its files are legitimately optional.

```yml
- name: Validate Runner Config
  if: hashFiles('config/runners/*.yml') != ''
  uses: appvia/appvia-cicd-workflows/.github/actions/schema-validate@main
  with:
    schema-file: config/schema/runners.schema.json
    files: config/runners/*.yml
```

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `schema-file` | yes | - | The JSON Schema file, relative to `working-directory` |
| `files` | yes | - | Newline-separated file paths or globs to validate, relative to `working-directory` |
| `working-directory` | no | `.` | The directory `schema-file` and `files` are relative to |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `errors` | The number of schema violations found |

## Terraform Actions

### terraform-bootstrap

Source: [.github/actions/terraform-bootstrap](../.github/actions/terraform-bootstrap/action.yml)

Sets up a job that needs to talk to AWS:

1. Installs Terraform, or OpenTofu when `enable-opentofu` is true
2. Retrieves a GitHub OIDC token, writes it to `aws-web-identity-token-file`, and assumes an IAM role
3. Configures private module access using a GitHub App token, when `enable-private-access` is true
4. Runs `init` against the S3 backend, with the state key defaulting to `<repo-name>.tfstate`

The role is chosen from the ref: `main` and tag refs use the read-write role `<aws-role>[-<environment>]`, and every other ref uses the read-only role `<aws-role>[-<environment>]-ro`. The `-<environment>` suffix is only added when `use-env-as-suffix` is true. `aws-write-role-name` and `aws-read-role-name` override the names.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `actions-id` | no | - | The application ID for the workflow token |
| `actions-secret` | no | - | The application secret for the workflow token |
| `aws-account-id` | yes | - | The AWS account ID to deploy to |
| `aws-read-role-name` | no | - | Overrides the default behavior, and uses a custom role name for read-only access |
| `aws-region` | yes | - | The AWS region to deploy to |
| `aws-role` | yes | - | The role to assume |
| `aws-web-identity-token-file` | yes | - | The file to store the web identity token in |
| `aws-write-role-name` | no | - | Overrides the default behavior, and uses a custom role name for read-write access |
| `enable-opentofu` | no | `False` | Use OpenTofu instead of Terraform |
| `enable-private-access` | yes | - | Optional flag to state if terraform requires pulling private modules |
| `environment` | no | - | The environment to deploy to |
| `node-version` | no | `22` | The version of node to use |
| `organization-name` | no | - | The name of the Github organization; defaults to the owner of the calling repository |
| `terraform-dir` | yes | - | The directory to validate |
| `terraform-init-extra-args` | no | - | Extra arguments to pass to terraform init |
| `terraform-state-key` | no | - | The key of the terraform state (default: <repo-name>.tfstate) |
| `terraform-version` | yes | - | The version of terraform to use |
| `use-env-as-suffix` | no | - | Whether to use the environment as a suffix for the state file and iam roles |
| `working-directory` | yes | - | The working directory to run the action in |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `outcome-auth` | Outcome of the auth step |
| `outcome-init` | Outcome of the init step |

### terraform-bootstrap-noauth

Source: [.github/actions/terraform-bootstrap-noauth](../.github/actions/terraform-bootstrap-noauth/action.yml)

Installs Terraform or OpenTofu, configures private module access, and runs `init -backend=false`. Used by jobs that only need the providers and modules (linting, static analysis, module validation).

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `actions-id` | no | - | The application ID for the workflow token |
| `actions-secret` | no | - | The application secret for the workflow token |
| `enable-opentofu` | no | `False` | Use OpenTofu instead of Terraform |
| `enable-private-access` | yes | - | Optional flag to state if terraform requires pulling private modules |
| `organization-name` | no | - | The name of the Github organization; defaults to the owner of the calling repository |
| `terraform-dir` | yes | - | The directory to validate |
| `terraform-init-extra-args` | no | - | Extra arguments to pass to terraform init |
| `terraform-version` | yes | - | The version of terraform to use |
| `working-directory` | yes | - | The working directory to run the action in |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `outcome-init` | Outcome of the init step |

### terraform-plan-encrypt

Source: [.github/actions/terraform-plan-encrypt](../.github/actions/terraform-plan-encrypt/action.yml)

Encrypts each file in `files` with `openssl enc -aes-256-cbc -pbkdf2`, writing `<file>.enc` and removing the original, so plans containing sensitive values are not uploaded as plain text. The key is taken from `encryption-key`, or from `/tmp/tfplan-enc-key`, and is removed from disk afterwards.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `encryption-key` | no | - | Static encryption key. If not set, expects key at /tmp/tfplan-enc-key |
| `files` | no | `tfplan tfplan.json` | Space-separated list of files to encrypt |
| `working-directory` | no | `.` | The working directory where plan files are located |

### terraform-plan-decrypt

Source: [.github/actions/terraform-plan-decrypt](../.github/actions/terraform-plan-decrypt/action.yml)

Reverses `terraform-plan-encrypt`, turning each `<file>.enc` back into `<file>`. The key is taken from `encryption-key`, or from `/tmp/tfplan-enc-key` if that is not set.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `encryption-key` | no | - | Static encryption key. If not set, expects key at /tmp/tfplan-enc-key |
| `files` | no | `tfplan tfplan.json` | Space-separated list of files to decrypt (without .enc suffix) |
| `working-directory` | no | `.` | The working directory where encrypted plan files are located |

## Terragrunt Actions

### terragrunt-bootstrap

Source: [.github/actions/terragrunt-bootstrap](../.github/actions/terragrunt-bootstrap/action.yml)

The Terragrunt equivalent of `terraform-bootstrap`. Installs Terraform and Terragrunt, assumes an IAM role via OIDC, and configures private module access. It does not run `init`; Terragrunt does that on demand.

AWS authentication only happens when both `aws-account-id` and `aws-role` are set. The role is chosen from the branch: a branch named `main` uses the read-write role `<aws-role>[-<environment>]`, and anything else uses the read-only role `<aws-role>[-<environment>]-ro`. As with `terraform-bootstrap`, `use-env-as-suffix`, `aws-write-role-name` and `aws-read-role-name` adjust the names.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `actions-id` | no | - | The application ID for the workflow token |
| `actions-secret` | no | - | The application secret for the workflow token |
| `aws-account-id` | no | - | The AWS account ID to deploy to |
| `aws-read-role-name` | no | - | Overrides the default behavior, and uses a custom role name for read-only access |
| `aws-region` | no | - | The AWS region to deploy to |
| `aws-role` | no | - | The role to assume |
| `aws-web-identity-token-file` | yes | - | The file to store the web identity token in |
| `aws-write-role-name` | no | - | Overrides the default behavior, and uses a custom role name for read-write access |
| `enable-private-access` | no | - | Optional flag to state if terragrunt requires pulling private modules |
| `environment` | no | - | The environment to deploy to |
| `node-version` | no | `22` | The version of node to use |
| `organization-name` | no | - | The name of the Github organization; defaults to the owner of the calling repository |
| `terraform-version` | yes | - | The version of terraform or opentofu to use |
| `terragrunt-dir` | yes | - | The directory to validate |
| `terragrunt-version` | yes | - | The version of terragrunt to use |
| `use-env-as-suffix` | no | - | Whether to use the environment as a suffix for the state file and iam roles |
| `working-directory` | yes | - | The working directory to run the action in |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `outcome-auth` | Outcome of the auth step |
| `outcome-init` | Outcome of the init step |

### terragrunt-bootstrap-unauth

Source: [.github/actions/terragrunt-bootstrap-unauth](../.github/actions/terragrunt-bootstrap-unauth/action.yml)

Installs Terraform and Terragrunt and configures private module access, without AWS credentials. Used by the lint and security jobs.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `actions-id` | no | - | The application ID for the workflow token |
| `actions-secret` | no | - | The application secret for the workflow token |
| `enable-private-access` | no | - | Optional flag to state if terragrunt requires pulling private modules |
| `node-version` | no | `22` | The version of node to use |
| `organization-name` | no | - | The name of the Github organization; defaults to the owner of the calling repository |
| `terraform-version` | yes | - | The version of terraform or opentofu to use |
| `terragrunt-dir` | yes | - | The directory to validate |
| `terragrunt-version` | yes | - | The version of terragrunt to use |
| `working-directory` | yes | - | The working directory to run the action in |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `outcome-auth` | Outcome of the auth step |
| `outcome-init` | Outcome of the init step |

### terragrunt-diff

Source: [.github/actions/terragrunt-diff](../.github/actions/terragrunt-diff/action.yml)

Renders the Terragrunt inputs on the pull request branch and on `main`, and diffs them so reviewers can see which units' inputs changed. The diff is posted to the pull request and returned as `result-comment`. The same diff can be run locally with `make render-diff`.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `terraform-version` | yes | - | The version of terraform or opentofu to use |
| `terragrunt-config-file` | yes | `terragrunt.hcl` | The terragrunt config file to use |
| `terragrunt-version` | yes | - | The version of terragrunt to use |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `result` | The result of the diff |
| `result-comment` | The result of the diff for the pull request |

### terragrunt-matrix

Source: [.github/actions/terragrunt-matrix](../.github/actions/terragrunt-matrix/action.yml)

Finds every Terragrunt unit beneath `terragrunt-dir` and returns a matrix for `strategy.matrix`. With `group-by-parent` (the default), each directory matching `parent-pattern` (e.g. `accounts/<region>/<account>`) is a unit, and each nested unit beneath it gets its own entry. The parent's entry lists the nested units in `modules`, so they can be excluded from its `run --all` with `--queue-exclude-dir`.

Each entry looks like:

```json
{
  "file": "./accounts/eu-west-2/prod/terragrunt.hcl",
  "path": "accounts/eu-west-2/prod",
  "relative_path": "accounts/eu-west-2/prod/terragrunt.hcl",
  "unit_name": "prod",
  "region": "eu-west-2",
  "account": "prod",
  "modules": ["oam"],
  "module_count": 1
}
```

```yml
jobs:
  matrix:
    runs-on: ubuntu-latest
    outputs:
      count: ${{ steps.matrix.outputs.count }}
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v7
      - id: matrix
        uses: appvia/appvia-cicd-workflows/.github/actions/terragrunt-matrix@main

  plan:
    needs: matrix
    if: needs.matrix.outputs.count > 0
    strategy:
      matrix: ${{ fromJson(needs.matrix.outputs.matrix) }}
    runs-on: ubuntu-latest
    steps:
      - run: echo "Planning ${{ matrix.unit.path }}"
```

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `account-files` | no | `terragrunt.hcl` | Comma-separated list of Terragrunt configuration files to look for |
| `exclude-patterns` | no | `.terragrunt-cache,node_modules,.git` | Comma-separated list of patterns to exclude from search |
| `group-by-parent` | no | `true` | Group nested modules under parent unit (assumes parent-pattern structure) |
| `include-account` | no | `true` | Extract and include account from path (assumes accounts/REGION/ACCOUNT structure) |
| `include-path` | no | `true` | Include the unit directory (relative to terragrunt-dir) as 'path' in the matrix output |
| `include-region` | no | `true` | Extract and include region from path (assumes accounts/REGION/ACCOUNT structure) |
| `include-relative-path` | no | `true` | Include the relative path in the matrix output |
| `include-unit-name` | no | `true` | Include a clean unit name in the matrix output |
| `matrix-key` | no | `unit` | Key name for the matrix output |
| `parent-pattern` | no | `accounts/[^/]+/[^/]+` | Regex pattern to identify parent units (relative path, e.g., 'accounts/[^/]+/[^/]+') |
| `terragrunt-dir` | no | `.` | Directory to search for Terragrunt units |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `count` | Number of units found |
| `matrix` | JSON matrix of Terragrunt units |
| `units` | Comma-separated list of unit names |

### terragrunt-plan-collect

Source: [.github/actions/terragrunt-plan-collect](../.github/actions/terragrunt-plan-collect/action.yml)

Runs in each matrix job after `terragrunt run --all --out-dir <plan-dir> --json-out-dir <json-dir> -- plan`. For every unit planned it counts the resource changes (create, update, replace, delete, import, forget and output changes) from the JSON plan, and renders the human readable plan with `terragrunt show`, keeping only the proposed changes. The result is uploaded as a compact `summary.json` in the artifact `plan-summary-<environment>--<unit-path>`. The raw JSON plan is not uploaded.

Run it with `if: always()` so failed plans are still reported.

```yml
- name: Terragrunt Plan
  id: plan
  working-directory: ${{ matrix.unit.path }}
  run: |
    terragrunt run --all --out-dir "${{ runner.temp }}/tfplan" --json-out-dir "${{ runner.temp }}/tfplan-json" -- plan

- name: Collect Plan Summary
  if: always()
  uses: appvia/appvia-cicd-workflows/.github/actions/terragrunt-plan-collect@main
  with:
    environment: production
    json-dir: ${{ runner.temp }}/tfplan-json
    outcome-plan: ${{ steps.plan.outcome }}
    plan-dir: ${{ runner.temp }}/tfplan
    unit-account: ${{ matrix.unit.account }}
    unit-name: ${{ matrix.unit.unit_name }}
    unit-path: ${{ matrix.unit.path }}
    unit-region: ${{ matrix.unit.region }}
    working-directory: ${{ matrix.unit.path }}
```

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `environment` | yes | - | The environment being planned, used to scope the artifact name |
| `json-dir` | yes | - | The directory passed to terragrunt --json-out-dir |
| `outcome-auth` | no | - | The outcome of the authentication step |
| `outcome-plan` | yes | - | The outcome of the terragrunt plan step |
| `plan-dir` | yes | - | The directory passed to terragrunt --out-dir |
| `terragrunt-config-file` | no | `terragrunt.hcl` | The configuration file to use for terragrunt |
| `unit-account` | no | - | The account of the matrix unit |
| `unit-name` | yes | - | The name of the matrix unit |
| `unit-path` | yes | - | The path of the matrix unit |
| `unit-region` | no | - | The region of the matrix unit |
| `working-directory` | yes | - | The directory terragrunt plan was run from |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `artifact-name` | The name of the uploaded summary artifact |

### terragrunt-plan-summary

Source: [.github/actions/terragrunt-plan-summary](../.github/actions/terragrunt-plan-summary/action.yml)

Runs once after the matrix. It downloads every `plan-summary-<environment>--*` artifact and builds a single report: totals, a table of changed and failed units, every resource that will be destroyed or replaced, and a collapsible plan per unit. The report is written to the job summary and to the job log (with collapsible groups and warning annotations), and, when `comment` is true on a pull request, to a comment that is updated in place.

It also outputs the overall plan and authentication outcome across the matrix. Pass the number of matrix entries as `expected`, so a job that never reported is counted as a failure. See [Plan Summary](./terragrunt-plan-and-apply-aws.md#plan-summary-matrix-mode) for an overview.

```yml
plan-summary:
  needs: [matrix, plan]
  if: ${{ !cancelled() && needs.plan.result != 'skipped' }}
  runs-on: ubuntu-latest
  steps:
    - uses: appvia/appvia-cicd-workflows/.github/actions/terragrunt-plan-summary@main
      with:
        comment: ${{ github.event_name == 'pull_request' }}
        environment: production
        expected: ${{ needs.matrix.outputs.count }}
```

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `comment` | no | `true` | Whether to post the report as a comment on the pull request |
| `environment` | yes | - | The environment being planned, must match the value given to terragrunt-plan-collect |
| `expected` | no | `0` | The number of matrix units expected to report, any missing are treated as a failure |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `changes` | Whether any unit has changes (true or false) |
| `result-auth` | The aggregated outcome of authentication across the matrix |
| `result-plan` | The aggregated outcome of the plan across the matrix |

### terragrunt-pr

Source: [.github/actions/terragrunt-pr](../.github/actions/terragrunt-pr/action.yml)

Posts the "Pull Request Review Status" comment listing the outcome of each check (format, lint, security, authentication, plan, commitlint, inputs diff and render), updating the existing comment for the environment rather than adding a new one each push.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `status-auth` | yes | - | The authentication of the status comment |
| `status-commitlint` | yes | - | The commitlint of the status comment |
| `status-format` | yes | - | The format of the status comment |
| `status-hcl-format` | yes | - | The HCL format of the status comment |
| `status-inputs-diff` | yes | - | The inputs diff of the status comment |
| `status-inputs-render` | yes | - | The inputs render of the status comment |
| `status-linting` | yes | - | The linting of the status comment |
| `status-plan` | yes | - | The plan of the status comment |
| `status-security` | yes | - | The security of the status comment |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `result` | The result of the update |

## Kubernetes Actions

### kubernetes-platform-promotion

Source: [.github/actions/kubernetes-platform-promotion](../.github/actions/kubernetes-platform-promotion/action.yml)

Enforces a pull-based promotion order (by default `dev → qa → staging → uat → prod`): when a pull request changes an environment file, the version in the target environment must be greater than or equal to its nearest predecessor's. Results are posted to the pull request. See the action's [README](../.github/actions/kubernetes-platform-promotion/README.md) for the file layout it expects.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `github-token` | no | `${{ github.token }}` | GitHub token for PR comments |
| `promotion-order` | no | `dev,qa,staging,uat,prod` | Comma-separated promotion order |
| `workloads-dir` | no | `workloads/applications` | Path to the workloads applications directory |

**Outputs**

| Name | Description |
| ---- | ----------- |
| `result` | The result of the validation (success/failure) |
| `summary` | Summary of validation results |

## Template Actions

### template-update

Source: [.github/actions/template-update](../.github/actions/template-update/action.yml)

Checks out a template repository, copies an allowlist of files into the repository (optionally as `source:destination` pairs), and raises a pull request if anything changed. See the action's [README](../.github/actions/template-update/README.md) for examples.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `base-directory` | yes | `.` | The base directory to update |
| `branch-name` | no | - | The name of the branch to update |
| `enable-pull-request` | no | `true` | Whether to create a pull request |
| `pull-request-title` | no | - | The title of the pull request |
| `template-branch` | no | `main` | The branch to update |
| `template-files` | yes | - | The template files to update (optionally source:destination format) |
| `template-repository` | yes | - | The template repository to update |
| `upstream-token` | no | - | The token to used to authenticate with the upstream repository (optional, defaults to github.token) |

### template-update-azure

Source: [.github/actions/template-update-azure](../.github/actions/template-update-azure/action.yml)

The inverse of `template-update`: syncs the whole template repository into `base-directory` with rsync, protecting only the paths listed in `exclude-files` (rsync filter syntax, e.g. `terraform/*.auto.tfvars`). New upstream files are adopted automatically. `.git` is always excluded.

**Inputs**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `base-directory` | yes | `.` | The base directory to sync the upstream template into |
| `branch-name` | no | - | The name of the branch to update |
| `enable-pull-request` | no | `true` | Whether to create a pull request |
| `exclude-files` | no | - | Newline-separated list of paths (relative to base-directory) to protect from the sync. rsync filter syntax is honoured, so trailing-slash directory rules and '*' globs work (e.g. "terraform/*.auto.tfvars"). '.git' is always excluded regardless of this list. |
| `pull-request-title` | no | - | The title of the pull request |
| `template-branch` | no | `main` | The upstream branch to sync from |
| `template-repository` | yes | - | The template repository to sync from |
| `upstream-token` | no | - | Token to authenticate with the upstream repository (defaults to github.token) |
