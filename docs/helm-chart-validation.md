# Helm Chart Validation

This GitHub Actions workflow template ([helm-chart-validation.yml](../.github/workflows/helm-chart-validation.yml)) can be used with Helm chart repositories to validate charts against best practices. It is designed for repositories containing multiple charts under a common directory (by default `charts/`). The workflow lints and renders the charts, validates the rendered manifests against the Kubernetes schemas, runs static security analysis and checks the chart documentation is up to date. It also adds a comment to the associated pull request containing results of the run.

## Workflow Jobs

1. **Detect Charts:** On a pull request, only the charts with changes are validated; on a push, all charts under `charts-dir` are validated.
2. **Helm Lint:** For each chart, builds the dependencies, then runs `helm lint --strict` and `helm template` once for each [chart-testing](https://github.com/helm/chart-testing) style `ci/*-values.yaml` file. As with `ct lint`, a chart without any is linted and rendered with its default values, so a chart with a required value that has no default must provide at least one `ci/*-values.yaml` file. Kubeconform renders the charts the same way.
3. **Kubeconform:** The rendered manifests for each chart are validated against the Kubernetes schemas for `kubernetes-version`. Custom resources are validated using the [CRDs catalog](https://github.com/datreeio/CRDs-catalog); resources without a known schema are skipped.
4. **Static Security Analysis:** The charts are scanned by Trivy for misconfigurations; `CRITICAL` and `HIGH` findings fail the build. Exceptions can be added to a `.trivyignore` file.
5. **Static Security Analysis - Checkov:** The charts are scanned by Checkov (reported only, the job does not fail). Configuration can be provided via a `.checkov.yml` file.
6. **Helm Docs:** Runs [helm-docs](https://github.com/norwoodj/helm-docs) and fails if the generated documentation differs from what is committed.
7. **Commitlint:** On a pull request, checks the commit messages follow the conventional commit format.
8. **Add PR Comment:** If the workflow is triggered via a pull request, a comment will be added containing the results of the previous jobs.

Library charts are linted but not rendered or schema validated, as they cannot be installed on their own.

## Usage

Create a new workflow file in your chart repository (e.g. `.github/workflows/validate.yml`) with the below contents:

```yml
name: Validate
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  contents: read
  pull-requests: write

jobs:
  validate:
    uses: appvia/appvia-cicd-workflows/.github/workflows/helm-chart-validation.yml@main
    name: Chart Validation
    with:
      # Optional: defaults shown
      charts-dir: charts
      enable-checkov: true
      enable-helm-docs: true
      enable-kubeconform: true
      kubernetes-version: "1.36.0"
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
