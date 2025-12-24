# Terragrunt Workflow for AWS Infrastructure

This GitHub Actions workflow template ([terragrunt-plan-and-apply-aws.yml](../.github/workflows/terragrunt-plan-and-apply-aws.yml)) can be used with Terragrunt repositories to automate the deployment and management of AWS infrastructure. The workflow performs various steps such as authentication with AWS, Terragrunt formatting, HCL validation, linting, planning, and applying changes. It also adds the Terragrunt plan output as a comment to the associated pull request and triggers an apply action for pushes to the main branch.

## Introduction

Terragrunt is a thin wrapper for Terraform that provides extra tools for keeping your configurations DRY, working with multiple Terraform modules, and managing remote state. This workflow provides a complete CI/CD pipeline for Terragrunt-based infrastructure, with support for:

- Multiple deployment units with matrix execution
- HCL formatting and validation
- Static security analysis
- Cost estimation with Infracost
- Automated PR comments with plan results
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
9. **Terragrunt Inputs Diff:** Detects which Terragrunt units have changed inputs
10. **Terragrunt Matrix:** Generates a matrix of Terragrunt units for parallel execution (optional)
11. **Terragrunt Plan:** Runs `terragrunt plan` for all or specific units, either in parallel (matrix mode) or sequentially
12. **Get Cost Estimate:** Runs Infracost to estimate infrastructure costs (PR only, optional)
13. **Add PR Comment:** Posts a comprehensive comment to the PR with all validation and plan results
14. **Terragrunt Apply:** Automatically applies changes when merged to main (if enabled)

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

#### CI/CD Configuration
- `cicd-repository` - Default: "appvia/appvia-cicd-workflows". The repository to pull the CI/CD workflows from
- `cicd-branch` - Default: "main". The branch to pull the CI/CD workflows from

#### Feature Flags
- `enable-infracost` - Default: false. Whether to run Infracost on the Terragrunt Plan (requires `infracost-api-key` secret)
- `enable-commitlint` - Default: true. Whether to run commitlint on the commit message
- `enable-terragrunt-apply` - Default: true. Whether to run terragrunt apply on merge to main
- `enable-terragrunt-plan` - Default: false. Whether to run terragrunt plan on merge to main (useful for scheduled drift detection)
- `enable-matrix` - Default: false. Whether to run the terragrunt plan in matrix mode (parallel execution per unit)
- `enable-private-access` - Default: false. Flag to indicate if Terraform requires pulling private modules

#### Environment Configuration
- `environment` - Default: "production". The environment to deploy to
- `runs-on` - Default: "ubuntu-latest". Single label value for the GitHub runner to use
- `use-env-as-suffix` - Default: false. Whether to use the environment as a suffix for the state file and IAM roles

#### Terragrunt Configuration
- `terragrunt-dir` - Default: ".". The directory to validate
- `terragrunt-version` - Default: "0.88.1". The version of Terragrunt to use
- `terragrunt-config-file` - Default: "terragrunt.hcl". The configuration file to use for Terragrunt
- `terragrunt-apply-extra-args` - Default: "-parallelism=10". Extra arguments to pass to terragrunt apply
- `terragrunt-plan-extra-args` - Default: "-parallelism=10". Extra arguments to pass to terragrunt plan

#### Terraform Configuration
- `terraform-version` - Default: "1.13.3". The version of Terraform to use
- `terraform-apply-extra-args` - Extra arguments to pass to terraform apply
- `terraform-plan-extra-args` - Extra arguments to pass to terraform plan
- `terraform-lock-timeout` - Default: "30s". The time to wait for a state lock
- `terraform-log-level` - The log level of Terraform (DEBUG, TRACE, etc.)
- `terraform-parallelism` - Default: 20. The number of parallel operations to run

#### Security Configuration
- `trivy-version` - Default: "v0.60.0". The version of Trivy to use

### Optional Secrets

- `infracost-api-key` - The API key for Infracost (required if `enable-infracost` is true)
- `actions-id` - The GitHub App ID for accessing private repositories
- `actions-secret` - The GitHub App secret for accessing private repositories
- `github-token` - The GitHub token to use for repository operations

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

Enable parallel execution for faster planning:

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
    - cron: '0 0 * * *'  # Daily at midnight

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
- Runs all Terragrunt units sequentially in a single job
- Simpler logs and easier debugging
- Better for smaller infrastructures
- Use when: You have few Terragrunt units or prefer sequential execution

### Matrix Mode (`enable-matrix: true`)
- Detects all Terragrunt units and executes them in parallel
- Significantly faster for large infrastructures
- Each unit runs in its own job
- Use when: You have many Terragrunt units and want faster feedback

## Pull Request Comments

When the workflow runs on a pull request, it posts a comprehensive comment containing:

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

## Best Practices

1. **Enable Matrix Mode for Large Repos:** Use `enable-matrix: true` for faster feedback on repositories with many Terragrunt units
2. **Use Infracost:** Enable cost estimation to understand the financial impact of changes
3. **Pin Versions:** Specify exact versions for Terraform and Terragrunt for reproducibility
4. **Environment Protection:** Use GitHub environment protection rules to require manual approval for production deploys
5. **Scheduled Drift Detection:** Run the workflow on a schedule to detect configuration drift
6. **Commitlint:** Keep `enable-commitlint: true` to maintain clean commit history
7. **Security Scanning:** The workflow includes Trivy for security scanning (currently placeholder - implement as needed)
8. **Review PR Comments:** Always review the automated PR comments before merging

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

### Formatting Failures
- Run `terragrunt hclfmt` locally to fix HCL formatting
- Run `terraform fmt -recursive` to fix Terraform formatting
- Commit and push the formatted files

## Comparison with Terraform Workflow

| Feature | Terragrunt Workflow | Terraform Workflow |
|---------|-------------------|-------------------|
| Tool | Terragrunt + Terraform | Terraform only |
| DRY Config | Yes (Terragrunt) | No |
| Matrix Execution | Yes (optional) | No |
| HCL Formatting | Yes | N/A |
| Multi-module | Native support | Manual management |
| State Management | Terragrunt-managed | Manual configuration |

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

## Related Documentation

- [Terragrunt Manual Dispatch](./terragrunt-dispatch.md) - Manually trigger Terragrunt operations
- [Terraform Plan & Apply (AWS)](./terraform-plan-and-apply-aws.md) - Similar workflow for plain Terraform
