# Terraform Module Validation

This GitHub Actions workflow template ([terraform-module-validation.yml](../.github/workflows/terraform-module-validation.yml)) can be used with Terraform repositories to validate best practices around Terraform modules. The workflow performs various steps such as Terraform formatting, linting, initialization, validation, and docs generation checks. It also adds a comment to the associated pull request containing results of the run.

## Workflow Jobs

      - terraform-format
      - terraform-lint
      - terraform-init
      - terraform-validate
      - terraform-docs


1. **Terraform Format:** Runs the terraform fmt command to check that all Terraform files are formatted correctly.
2. **Terraform Lint:** Runs a terraform lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
3. **Terraform Init:** Provider plugins and modules are installed.
4. **Terraform Validate:** The Terraform configuration files are run through validation to check for syntax errors and other issues.
5. **Terraform Docs:** The terraform-docs utility is run to check that the documentation for the module is up to date.
6. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.

## Inputs

| Input | Required? | Default Value | Description |
|-------|-------------|-----------|---------------|
| terraform-version | No | 1.5.2 | The version of Terraform to use |

## Usage

Create a new workflow file in your Terraform repository (e.g. `.github/workflows/terraform.yml`) with the below contents:
```yml
name: Terraform Module Validation
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
      name: Terraform Module Validation
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
