# Terraform/OpenTofu Workflow for AWS Infrastructure

This GitHub Actions workflow template ([terraform-plan-and-apply-aws.yml](../.github/workflows/terraform-plan-and-apply-aws.yml)) can be used with Terraform/OpenTofu repositories to automate the deployment and management of AWS infrastructure. The workflow performs various steps such as authentication with AWS, formatting, initialization, validation, planning, and applying changes. It also adds the plan output as a comment to the associated pull request and triggers an apply action for pushes to the main branch.

## OpenTofu Support

This workflow supports both Terraform and OpenTofu. Use the `enable-opentofu` input to switch between tools:

```yaml
with:
  enable-opentofu: true  # Use OpenTofu instead of Terraform
```

## Workflow Steps

1. **Setup Terraform/OpenTofu:** Terraform or OpenTofu is fetched at the specified version (overridable via inputs).
2. **Terraform/OpenTofu Format:** This step runs the fmt command to check that all files are formatted correctly.
3. **Terraform/OpenTofu Lint:** This step runs lint to check for deprecated syntax, unused declarations, invalid types, and enforcing best practices.
4. **AWS Authentication:** The workflow uses Web Identity Federation to authenticate with AWS. The required AWS Role ARN must be provided as an input for successful authentication.
   - A Web Identity Token File is also generated and stored in `/tmp/web_identity_token_file`, which can be referenced in Terraform/OpenTofu Provider configuration blocks if required.
5. **Terraform/OpenTofu Init:** The backend is initialised and any necessary provider plugins are downloaded. The required inputs for AWS S3 bucket name and DynamoDB table name must be provided for storing the state.
6. **Terraform/OpenTofu Security:** The module code and dependencies are examined by a static analysis tool to identify misconfiguration or potential security issues.
7. **Terraform/OpenTofu Validate:** The workflow validates the configuration files using the validate command to check for syntax errors and other issues.
8. **Terraform/OpenTofu Plan:** A plan is generated with a specified values file (overridable via inputs) using the plan command.
9. **Get Cost Estimate:** The infracost utility is run to get a cost estimate on the Plan output. A comment will be added to the pull request with the cost estimate.
10. **Add PR Comment:** If the workflow is triggered via a Pull Request, a comment will be added to the ticket containing the results of the previous steps.
11. **Apply Changes:** If the workflow is triggered by a push to the main branch, it automatically applies the changes using the apply command. This step should be used with caution as AWS infrastructure is modified at this point. The automatic apply can be skipped by setting `enable-terraform-apply` to `false`.

## Usage

Create a new workflow file in your Terraform/OpenTofu repository (e.g. `.github/workflows/terraform.yml`) with the below contents:

```yml
name: Terraform/OpenTofu
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
      aws-account-id: 123456789012
      aws-role: <IAM_ROLE_NAME>
      enable-infracost: true
      enable-opentofu: false  # Set to true to use OpenTofu
```

## Inputs

### Required Inputs

- `aws-account-id` - AWS account ID to deploy to

### Optional Inputs

- `aws-role` - AWS role to assume (default: repository name)
- `aws-read-role-name` - Custom role name for read-only access
- `aws-write-role-name` - Custom role name for read-write access
- `aws-region` - AWS region (default: "eu-west-2")
- `environment` - Environment name (default: "production")
- `enable-opentofu` - Use OpenTofu instead of Terraform (default: false)
- `enable-private-access` - Enable private module access (default: false)
- `enable-infracost` - Enable cost estimation (default: false)
- `enable-checkov` - Enable Checkov security scanning (default: true)
- `enable-commitlint` - Enable commit message validation (default: true)
- `enable-terraform-apply` - Enable automatic apply on main branch (default: true)
- `organization-name` - GitHub organization name (default: "appvia")
- `runs-on` - GitHub runner (default: "ubuntu-latest")
- `terraform-dir` - Directory containing Terraform files (default: ".")
- `terraform-init-extra-args` - Extra arguments for terraform init
- `terraform-lock-timeout` - Lock timeout (default: "30s")
- `terraform-log-level` - Log level for terraform
- `terraform-plan-extra-args` - Extra arguments for terraform plan
- `terraform-state-key` - State file key (default: <repo-name>.tfstate)
- `terraform-values-file` - Values file (default: <environment>.tfvars)
- `terraform-parallelism` - Number of parallel operations (default: 20)
- `terraform-version` - Terraform version (default: "1.11.2")
- `trivy-version` - Trivy version for security scanning (default: "v0.60.0")
- `use-env-as-suffix` - Use environment as suffix for state file (default: false)
- `working-directory` - Working directory (default: ".")

### Required Secrets (Optional)

- `infracost-api-key` - Required if enable-infracost is true
- `gh-provider-app-id` - GitHub App ID for GitHub provider
- `gh-provider-installation-id` - GitHub App installation ID
- `gh-provider-private-key` - Base64 encoded GitHub App private key

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
