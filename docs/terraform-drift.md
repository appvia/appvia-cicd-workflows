# Terraform Draft Workflow for AWS Infrastructure

This workflow is used to run an scheduled or manually triggered drift detection on AWS infrastructure. In order to trigger the workflow, firstly the workflow must be referenced from the calling workflow flow, see below.

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
      aws-account: <AWS_ACCOUNT>
      aws-role: <IAM_ROLE_NAME>
```

And we can create another workflow file in your Terraform repository (e.g. `.github/workflows/terraform-drift.yml`) with the below contents:

```yml
name: Terraform
on:
  workflow_dispatch:
  scheduled:
    - cron: "0 0 * * *"

jobs:
  terraform-drift:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-drift.yml@main
    name: Drift Detection
    with:
      aws-account: <AWS_ACCOUNT>
      aws-role: <IAM_ROLE_NAME>
```

- `aws-account` is the AWS account number where the infrastructure is deployed.
- `aws-role` inputs are optional and will default to the repository name.

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
