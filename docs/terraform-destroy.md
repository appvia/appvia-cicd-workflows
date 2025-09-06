# Terraform/OpenTofu Destroy Workflow for AWS Infrastructure

This workflow is used to manually run terraform/opentofu destroy on AWS infrastructure. In order to trigger the workflow, firstly the workflow must be referenced from the calling workflow flow, see below. The user can then issue a workflow_dispatch event from the Actions tab in the repository, confirming the repository name within a `confirmation` field to ensure no accidental deletion occurs.

## OpenTofu Support

This workflow supports both Terraform and OpenTofu. Use the `enable-opentofu` input to switch between tools:

```yaml
with:
  enable-opentofu: true  # Use OpenTofu instead of Terraform
```

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
  workflow_dispatch:

jobs:
  terraform:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-plan-and-apply-aws.yml@main
    name: Plan and Apply
    with:
      aws-account: 123456789012
      aws-role: <IAM_ROLE_NAME>
```

And we can create another workflow file in your Terraform repository (e.g. `.github/workflows/terraform-destroy.yml`) with the below contents:

```yml
name: Terraform/OpenTofu Destroy
on:
  workflow_dispatch:

jobs:
  terraform-destroy:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-destroy.yml@main
    name: Destroy
    with:
      aws-account-id: 123456789012
      aws-role: <IAM_ROLE_NAME>
      enable-opentofu: false  # Set to true to use OpenTofu
```

## Inputs

### Required Inputs

- `confirmation` - Repository name confirmation for safety
- `aws-account-id` - AWS account ID to deploy to

### Optional Inputs

- `aws-role` - AWS role to assume (default: repository name)
- `aws-read-role-name` - Custom role name for read-only access
- `aws-write-role-name` - Custom role name for read-write access
- `aws-region` - AWS region (default: "eu-west-2")
- `environment` - Environment name (default: "production")
- `enable-opentofu` - Use OpenTofu instead of Terraform (default: false)
- `enable-private-access` - Enable private module access (default: false)
- `organization-name` - GitHub organization name (default: "appvia")
- `use-env-as-suffix` - Use environment as suffix for state file (default: false)
- `runs-on` - GitHub runner (default: "ubuntu-latest")
- `terraform-dir` - Directory containing Terraform files (default: ".")
- `terraform-init-extra-args` - Extra arguments for terraform init
- `terraform-lock-timeout` - Lock timeout (default: "30s")
- `terraform-log-level` - Log level for terraform
- `terraform-plan-extra-args` - Extra arguments for terraform plan
- `terraform-state-key` - State file key (default: <repo-name>.tfstate)
- `terraform-values-file` - Values file (default: <environment>.tfvars)
- `terraform-version` - Terraform version (default: "1.11.2")
- `working-directory` - Working directory (default: ".")

The `aws-role` inputs are optional and will default to the repository name.

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
