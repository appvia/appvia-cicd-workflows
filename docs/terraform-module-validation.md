# Terraform/OpenTofu Module Validation

This GitHub Actions workflow template ([terraform-module-validation.yml](../.github/workflows/terraform-module-validation.yml)) can be used with Terraform/OpenTofu repositories to validate best practices around Terraform/OpenTofu modules. The workflow performs various steps such as formatting, linting, initialization, validation, and docs generation checks. It also adds a comment to the associated pull request containing results of the run.

## OpenTofu Support

This workflow supports both Terraform and OpenTofu. Use the `enable-opentofu` input to switch between tools:

```yaml
with:
  enable-opentofu: true  # Use OpenTofu instead of Terraform
```

## Workflow Jobs

- terraform-docs
- terraform-format
- terraform-init
- terraform-lint
- terraform-security
- terraform-validate
- terraform-validate-examples
- terraform-infracost
- commitlint

1. **Terraform/OpenTofu Format:** Runs the fmt command to check that all files are formatted correctly.
2. **Terraform/OpenTofu Lint:** Runs a lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
3. **Terraform/OpenTofu Init:** Provider plugins and modules are installed.
4. **Terraform/OpenTofu Security:** The module code and dependencies are examined by a static analysis tool to identify misconfiguration or potential security issues.
5. **Terraform/OpenTofu Validate:** The configuration files are run through validation to check for syntax errors and other issues.
6. **Terraform/OpenTofu Validate Examples:** Any examples found under the ./examples are validated to ensure against `validate`
7. **Terraform Docs:** The terraform-docs utility is run to check that the documentation for the module is up to date.
8. **Get Cost Estimate:** The infracost utility is run to get a cost estimate for the module. A comment will be added to the pull request with the cost estimate.
9. **Commitlint:** Validates commit messages follow conventional commit format.
10. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.

## Usage

Create a new workflow file in your Terraform/OpenTofu repository (e.g. `.github/workflows/terraform.yml`) with the below contents:

```yml
name: Terraform/OpenTofu Module Validation
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  terraform:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-module-validation.yml@main
    name: Module Validation
    secrets:
      # Required if you want to run infracost
      infracost-api-key: ${{ secrets.ORG_INFRACOST_API_KEY }}
    with:
      aws-account-id: <ACCOUNT_ID>
      aws-region: <AWS_REGION>
      # Optional toggle to enable infracost
      enable-infracost: true
      # Optional toggle to use OpenTofu instead of Terraform
      enable-opentofu: false
```

## Inputs

### Required Inputs

- `aws-account-id` - AWS account ID for authentication

### Optional Inputs

- `aws-region` - AWS region (default: "eu-west-2")
- `aws-role` - AWS role to assume (default: repository name)
- `aws-read-role-name` - Custom role name for read-only access
- `aws-write-role-name` - Custom role name for read-write access
- `enable-opentofu` - Use OpenTofu instead of Terraform (default: false)
- `enable-private-access` - Enable private module access (default: false)
- `enable-infracost` - Enable cost estimation (default: false)
- `enable-commitlint` - Enable commit message validation (default: true)
- `enable-checkov` - Enable Checkov security scanning (default: true)
- `enable-terraform-tests` - Enable Terraform/OpenTofu tests (default: true)
- `organization-name` - GitHub organization name (default: "appvia")
- `terraform-dir` - Directory containing Terraform files (default: ".")
- `terraform-init-extra-args` - Extra arguments for terraform init
- `terraform-tests-dir` - Directory containing tests (default: ".")
- `terraform-version` - Terraform version (default: "1.11.2")
- `trivy-version` - Trivy version for security scanning (default: "v0.56.2")
- `working-directory` - Working directory (default: ".")

### Required Secrets (Optional)

- `infracost-api-key` - Required if enable-infracost is true
