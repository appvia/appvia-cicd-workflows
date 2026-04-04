# Kubernetes Platform Promotion Validation

This GitHub Actions workflow validates environment promotions for Kubernetes platform workloads by ensuring semantic versions never regress when promoted through environments.

## Introduction

The promotion validation workflow enforces a pull-based promotion model across environments (`dev → qa → staging → uat → prod`). When a PR changes an environment file, it validates that the target environment's version is greater than or equal to its nearest predecessor's version.

See the [action README](../.github/actions/kubernetes-platform-promotion/README.md) for full documentation, including inputs, outputs, validation rules, and usage examples.

## Usage

Create a workflow file in your repository (e.g. `.github/workflows/promotion.yml`) with the below contents:

```yml
name: Validate Promotion Order

on:
  pull_request:
    branches:
      - main
    paths:
      - 'workloads/applications/**/*.yaml'

permissions:
  contents: read
  pull-requests: write

jobs:
  validate-promotion:
    name: Validate Promotion Order
    runs-on: ubuntu-latest
    if: ${{ !contains(github.event.pull_request.labels.*.name, 'promotion/skip-validation') }}
    steps:
      - name: Checkout PR Branch
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.event.pull_request.head.sha }}

      - name: Validate Promotion
        uses: appvia/appvia-cicd-workflows/.github/actions/kubernetes-platform-promotion@main
        with:
          workloads-dir: workloads/applications
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Validation Rules

- **Semantic Version Gate** — target version must be >= predecessor version
- **Helm Workloads Only** — Kustomize files are skipped
- **Branch-Pinned Warning** — Kustomize files pinned to a branch name emit a warning
- **First-Time Environments** — no predecessor means automatic pass
- **Hotfix Bypass** — label PR with `promotion/skip-validation` to skip all checks

## Testing

The action includes a fixture-based test suite:

```bash
# Run all tests
./tests/promotion/run-tests.sh

# Run a single test
./tests/promotion/run-tests.sh valid-promotion
```

**Note:** The workflow and action may change over time, so it is recommended that you point to a tagged version rather than the main branch.
