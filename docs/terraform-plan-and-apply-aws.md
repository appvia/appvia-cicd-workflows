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
      environment-variables: ${{ secrets.TERRAFORM_ENVIRONMENT_VARIABLES }}
    with:
      aws-account-id: 123456789012
      aws-role: <IAM_ROLE_NAME>
      enable-infracost: true
```

## Inputs

### Required Inputs

- `aws-account-id` - The AWS account ID to deploy to

### Optional Inputs

- `additional-dir` - Upload additional directory as artifact from plan stage
- `additional-dir-optional` - Default: false. Uploads additional directory as artifact from plan stage
- `aws-role` - Default: Repository Name. The AWS role to assume
- `aws-read-role-name` - Overrides the default behavior, and uses a custom role name for read-only access
- `aws-write-role-name` - Overrides the default behavior, and uses a custom role name for read-write access
- `aws-region` - Default: "eu-west-2". The AWS region to deploy to
- `cicd-repository` - Default: "appvia/appvia-cicd-workflows". The repository to pull the CI/CD workflows from
- `cicd-branch` - Default: "main". The branch to pull the CI/CD workflows from
- `enable-infracost` - Default: false. Whether to run infracost on the Terraform Plan (requires `infracost-api-key` secret)
- `enable-checkov` - Default: true. Whether to run Checkov security scanning
- `enable-commitlint` - Default: true. Whether to run commitlint on the commit message
- `enable-terraform-apply` - Default: true. Whether to run terraform apply on merge to main
- `enable-private-access` - Default: false. Flag to state if terraform requires pulling private modules
- `organization-name` - Default: "appvia". The name of the GitHub organization
- `environment` - Default: "production". The environment to deploy to
- `runs-on` - Default: "ubuntu-latest". Single label value for the GitHub runner to use
- `terraform-apply-extra-args` - Extra arguments to pass to terraform apply
- `terraform-dir` - Default: ".". The directory to validate
- `terraform-init-extra-args` - Extra arguments to pass to terraform init
- `terraform-lock-timeout` - Default: "30s". The time to wait for a lock
- `terraform-log-level` - The log level of terraform
- `terraform-plan-extra-args` - Extra arguments to pass to terraform plan
- `terraform-state-key` - Default: "<repo-name>.tfstate". The key of the terraform state
- `terraform-values-file` - Default: "values/<environment>.tfvars". The values file to use
- `terraform-parallelism` - Default: 20. The number of parallel operations to run
- `terraform-version` - Default: "1.11.2". The version of terraform to use
- `trivy-version` - Default: "v0.60.0". The version of trivy to use
- `working-directory` - Default: ".". The working directory to run terraform commands in
- `use-env-as-suffix` - Default: false. Whether to use the environment as a suffix for the state file and iam roles

### Optional Secrets

- `infracost-api-key` - The API key for infracost (required if `enable-infracost` is true)
- `actions-id` - The GitHub App ID for the Actions App
- `actions-secret` - The GitHub App secret for the Actions App
- `gh-provider-app-id` - GitHub provider app ID
- `gh-provider-installation-id` - GitHub provider installation ID
- `gh-provider-private-key` - Base64 encoded private key for GitHub provider app
- `environment-variables` - A JSON object of environment variables to be made available to Terraform (e.g. `{"TF_VAR_my_var": "my_value"}`)

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

### GitHub Provider Support

The workflow supports the Terraform GitHub provider through GitHub App authentication. To use this feature, you need to:

1. Create a GitHub App with the necessary permissions for your Terraform resources
2. Generate a private key for the GitHub App
3. Base64 encode the private key file:
   ```bash
   # macOS
   base64 -i github-app-private-key.pem | pbcopy
   
   # Linux
   base64 github-app-private-key.pem | xclip -selection clipboard
   
   # Or save to a file
   base64 github-app-private-key.pem > github-app-private-key-base64.txt
   ```
4. Store the following as GitHub secrets in your repository:
   - `GH_PROVIDER_APP_ID` - The GitHub App ID
   - `GH_PROVIDER_INSTALLATION_ID` - The GitHub App installation ID
   - `GH_PROVIDER_PRIVATE_KEY` - The base64 encoded private key from step 3

5. Pass these secrets to the workflow:
   ```yml
   jobs:
     terraform:
       uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-aws.yml@main
       name: Plan and Apply
       secrets:
         gh-provider-app-id: ${{ secrets.GH_PROVIDER_APP_ID }}
         gh-provider-installation-id: ${{ secrets.GH_PROVIDER_INSTALLATION_ID }}
         gh-provider-private-key: ${{ secrets.GH_PROVIDER_PRIVATE_KEY }}
       with:
         aws-account: 123456789012
         # ... other inputs
   ```

6. Configure the GitHub provider in your Terraform code:
   ```hcl
   provider "github" {
     owner = "my-organization"
     app_auth {
       pem_file = file("/tmp/github_provider.pem")
     } 
   }
   ```

The workflow automatically sets the required environment variables (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`) and exports the decoded private key in `/tmp/github_provider.pem`. The private key is cleaned up at the end of the workflow.
