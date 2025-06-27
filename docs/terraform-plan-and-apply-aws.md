# Terraform Workflow for AWS Infrastructure

This GitHub Actions workflow template ([terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml)) can be used with Terraform repositories to automate the deployment and management of AWS infrastructure. The workflow performs various steps such as authentication with AWS, Terraform formatting, initialization, validation, planning, and applying changes. It also adds the Terraform plan output as a comment to the associated pull request and triggers an apply action for pushes to the main branch.

## Workflow Steps

1. **Setup Terraform:** Terraform is fetched at the specified version (overridable via inputs).
2. **Terraform Format:** This step runs the terraform fmt command to check that all Terraform files are formatted correctly.
3. **Terraform Lint:** This step runs terraform lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
4. **AWS Authentication:** The workflow uses Web Identity Federation to authenticate with AWS. The required AWS Role ARN must be provided as an input for successful authentication.
   - A Web Identity Token File is also generated and stored in `/tmp/web_identity_token_file`, which can be referenced in Terraform Provider configuration blocks if required.
5. **Terraform Init:** The Terraform backend is initialised and any necessary provider plugins are downloaded. The required inputs for AWS S3 bucket name and DynamoDB table name must be provided for storing the Terraform state.
6. **Terraform Security:** The module code and dependencies are examined by a static analysis tool to identify and misconfiguration or potential security issues.
7. **Terraform Validate:** The workflow validates the Terraform configuration files using the terraform validate command to check for syntax errors and other issues.
8. **Terraform Plan:** A Terraform plan is generated with a specified values file (overridable via inputs) using the terraform plan command.
9. **Get Cost Estimate:** The infracost utility is run to get a cost estimate on the Terraform Plan output. A comment will be added to the pull request with the cost estimate.
10. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.
11. **Apply Changes:** If the workflow is triggered by a push to the main branch, it automatically applies the changes using the terraform apply command. This step should be used with caution as AWS infrastructure is modified at this point. The automatic apply can be skipped by setting `enable-terraform-apply` to `false`.

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
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-aws.yml@main
    name: Plan and Apply
    secrets:
      infracost-api-key: ${{ secrets.ORG_INFRACOST_API_KEY }}
    with:
      aws-account: 123456789012
      aws-role: <IAM_ROLE_NAME>
      enable-infracost: true
```

The `aws-role` inputs are optional and will default to the repository name.

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
