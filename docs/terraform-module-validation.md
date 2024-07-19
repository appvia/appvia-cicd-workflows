# Terraform Module Validation

This GitHub Actions workflow template ([terraform-module-validation.yml](../.github/workflows/terraform-module-validation.yml)) can be used with Terraform repositories to validate best practices around Terraform modules. The workflow performs various steps such as Terraform formatting, linting, initialization, validation, and docs generation checks. It also adds a comment to the associated pull request containing results of the run.

## Workflow Jobs

- terraform-docs
- terraform-format
- terraform-init
- terraform-lint
- terraform-security
- terraform-validate
- terraform-validate-examples
- terraform-infracost

1. **Terraform Format:** Runs the terraform fmt command to check that all Terraform files are formatted correctly.
2. **Terraform Lint:** Runs a terraform lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
3. **Terraform Init:** Provider plugins and modules are installed.
4. **Terraform Security:** The module code and dependencies are examined by a static analysis tool to identify and misconfiguration or potential security issues.
5. **Terraform Validate:** The Terraform configuration files are run through validation to check for syntax errors and other issues.
6. **Terraform Validate Examples:** Any examples found under the ./examples are validated to ensure against `terraform validate`
7. **Terraform Docs:** The terraform-docs utility is run to check that the documentation for the module is up to date.
8. **Get Cost Estimate:** The infracost utility is run to get a cost estimate for the module. A comment will be added to the pull request with the cost estimate.
9. **Terraform Infracost:** the module is run through infracost to gauge an idea of the associated cloud costs.
10. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.

## Usage

Create a new workflow file in your Terraform repository (e.g. `.github/workflows/terraform.yml`) with the below contents:

```yml
name: Terraform
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
```
