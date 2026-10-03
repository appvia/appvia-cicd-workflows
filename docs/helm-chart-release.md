# Helm Chart Release

This GitHub Actions workflow template ([helm-chart-release.yml](../.github/workflows/helm-chart-release.yml)) can be used with Helm chart repositories to automatically release charts when they are merged to the main branch. It is designed for repositories containing multiple charts under a common directory (by default `charts/`).

## How Releases Work

Bumping the `version` in a chart's `Chart.yaml` is the release trigger. On each run, any chart whose version does not yet have a `<name>-v<version>` tag (where `<name>` is the chart `name` in `Chart.yaml`) is packaged and released; all other charts are left untouched. By default, a release:

- creates the `<name>-v<version>` tag on the commit being built, and
- creates a GitHub release for that tag, with generated release notes and the packaged chart attached.

Publishing to AWS ECR (OCI) is optional and disabled by default; set `enable-ecr-publish: true` to also push the chart to the registry.

**Note:** When first adopting the workflow in a repository with existing charts, every chart without a matching tag will be released on the first run.

## Workflow Jobs

1. **Detect Releases:** Finds the charts whose `Chart.yaml` version has not yet been tagged.
2. **Release:** For each chart detected (in parallel):
   1. **Package Chart:** Builds chart dependencies, runs `helm lint --strict` and packages the chart.
   2. **Publish to ECR:** When `enable-ecr-publish` is `true`, assumes the IAM role via OIDC and pushes the chart to `oci://<account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<chart-name>`. With `enable-create-repository`, the ECR repository is created (with immutable tags) if it does not already exist.
   3. **Create Release:** Creates the release tag and, when `enable-github-release` is `true` (the default), a GitHub release with the packaged chart attached.

The release tag is created last, so a failed run can safely be re-run. Releases of the same chart are serialised, and a chart already released by a concurrent run is skipped.

## Prerequisites

- The calling workflow must grant `contents: write`, to create the release tag and GitHub release.
- When `enable-ecr-publish` is `true`:
  - The calling workflow must also grant `id-token: write`.
  - An IAM role trusted for GitHub OIDC from the calling repository, with permission to push to the ECR repositories: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` and `ecr:PutImage`.
  - Either the ECR repository `<prefix>/<chart-name>` must already exist, or `enable-create-repository` must be `true` and the role granted `ecr:DescribeRepositories` and `ecr:CreateRepository`.

## Usage

Create a new workflow file in your chart repository (e.g. `.github/workflows/release.yml`) with the below contents. Running the [Helm Chart Validation](./helm-chart-validation.md) workflow first ensures charts are only released when they pass validation:

```yml
name: Release

on:
  push:
    branches:
      - main

permissions:
  contents: write
  # Only required when enable-ecr-publish is true
  id-token: write
  pull-requests: write

jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/helm-chart-validation.yml@main
    name: Chart Validation

  release:
    uses: appvia/appvia-cicd-workflows/.github/workflows/helm-chart-release.yml@main
    name: Chart Release
    needs: validate
    with:
      # Optional: publish the charts to ECR
      enable-ecr-publish: true
      aws-account-id: <ACCOUNT_ID>
      aws-role: <ROLE_NAME>
      # Optional: defaults shown
      aws-region: eu-west-2
      charts-dir: charts
      ecr-repository-prefix: charts
      enable-create-repository: false
      enable-github-release: true
```

When published to ECR, charts can be consumed with, for example:

```shell
helm install my-app oci://<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/charts/my-app --version 1.2.3
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
