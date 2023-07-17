# Terraform Workflow for AWS Infrastructure

This GitHub Actions workflow template ([terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml)) can be used with Terraform repositories to automate the deployment and management of AWS infrastructure. The workflow performs various steps such as authentication with AWS, Terraform formatting, initialization, validation, planning, and applying changes. It also adds the Terraform plan output as a comment to the associated pull request and triggers an apply action for pushes to the main branch.

## Workflow Steps

1. **Setup Terraform:** Terraform is fetched at the specified version (overridable via inputs).
2. **Terraform Format:** This step runs the terraform fmt command to check that all Terraform files are formatted correctly.
3. **Terraform Lint:** This step runs terraform lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
4. **AWS Authentication:** The workflow uses Web Identity Federation to authenticate with AWS. The required AWS Role ARN must be provided as an input for successful authentication.
   * A Web Identity Token File is also generated and stored in `/tmp/web_identity_token_file`, which can be referenced in Terraform Provider configuration blocks if required.
5. **Terraform Init:** The Terraform backend is initialised and any necessary provider plugins are downloaded. The required inputs for AWS S3 bucket name and DynamoDB table name must be provided for storing the Terraform state.
6. **Terraform Validate:** The workflow validates the Terraform configuration files using the terraform validate command to check for syntax errors and other issues.
7. **Terraform Plan:** A Terraform plan is generated with a specified values file (overridable via inputs) using the terraform plan command.
8. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.
9. **Apply Changes:** If the workflow is triggered by a push to the main branch, it automatically applies the changes using the terraform apply command. This step should be used with caution as AWS infrastructure is modified at this point.

## Inputs

| Input | Required? | Default Value | Description |
|-------|-------------|-----------|---------------|
| aws-role-arn | Yes | | The ARN of the AWS role to assume for authentication |
| aws-s3-bucket-name | Yes | | The name of the AWS S3 bucket to store the Terraform state |
| aws-dynamodb-table-name | Yes | | The name of the AWS DynamoDB table to use for locking |
| aws-region | No | eu-west-2 | The AWS region to deploy the infrastructure to |
| terraform-log-level | No | INFO | The log level of Terraform |
| terraform-state-key | No | ${{ github.event.repository.name }}.tfstate | The name of the Terraform state file to store in S3 |
| terraform-values-file | No | values/production.tfvars | The path to the values file to use |
| terraform-version | No | 1.5.2 | The version of Terraform to use |

## Usage

Create a new workflow file in your Terraform repository (e.g. `.github/workflows/terraform.yml`) with the below contents:
```yml
name: Terraform Plan and Apply
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
      name: Terraform Plan and Apply
      with:
        aws-role-arn: ${{ vars.AWS_ROLE_ARN }}
        aws-s3-bucket-name: ${{ vars.AWS_TERRAFORM_STATE_S3_BUCKET_NAME }}
        aws-dynamodb-table-name: ${{ vars.AWS_TERRAFORM_STATE_DYNAMODB_TABLE_NAME }}
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
