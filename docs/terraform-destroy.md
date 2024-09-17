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
name: Terraform
on:
  workflow_dispatch:

jobs:
  terraform-destroy:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-destroy.yml@main
    name: Destroy
    with:
      aws-account: 123456789012
      aws-role: <IAM_ROLE_NAME>
```

The `aws-role` inputs are optional and will default to the repository name.

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
