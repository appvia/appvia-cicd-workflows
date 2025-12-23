# Terraform Destroy Workflow for AWS Infrastructure

This workflow is used to manually run terraform destroy on AWS infrastructure. In order to trigger the workflow, firstly the workflow must be referenced from the calling workflow flow, see below. The user can then issue a workflow_dispatch event from the Actions tab in the repository, confirming the repository name within a `confirmation` field to ensure no accidental deletion occurs.

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
name: Terraform Destroy
on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: 'Enter the repository name to confirm deletion'
        required: true
        type: string

jobs:
  terraform-destroy:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-destroy.yml@main
    name: Destroy
    with:
      confirmation: ${{ github.event.inputs.confirmation }}
      aws-account-id: 123456789012
      aws-role: <IAM_ROLE_NAME>
```

**IMPORTANT:** The `confirmation` input is required and must match the repository name (`owner/repo`) to prevent accidental deletion.

OPTIONAL INPUTS:
- `aws-role` - Defaults to the repository name
- `aws-region` - Default: "eu-west-2"
- `environment` - Default: "production"
- `terraform-version` - Default: "1.11.2"
- `terraform-dir` - Default: "."
- `terraform-values-file` - Default: "values/<environment>.tfvars"
- `terraform-lock-timeout` - Default: "30s"
- `working-directory` - Default: "."
- `use-env-as-suffix` - Default: false
- `runs-on` - Default: "ubuntu-latest"
- `enable-private-access` - Default: false
- `organization-name` - Default: "appvia"
- `aws-read-role-name` - Custom role name for read-only access
- `aws-write-role-name` - Custom role name for read-write access
- `additional-dir` - Upload additional directory as artifact
- `additional-dir-optional` - Default: false
- `terraform-init-extra-args` - Extra arguments to pass to terraform init
- `terraform-plan-extra-args` - Extra arguments to pass to terraform plan
- `terraform-apply-extra-args` - Extra arguments to pass to terraform apply
- `terraform-state-key` - Default: "<repo-name>.tfstate"
- `terraform-log-level` - The log level of terraform
- `cicd-repository` - Default: "appvia/appvia-cicd-workflows"
- `cicd-branch` - Default: "main"

OPTIONAL SECRETS:
- `actions-id` - The GitHub App ID for the Actions App
- `actions-secret` - The GitHub App secret for the Actions App

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
