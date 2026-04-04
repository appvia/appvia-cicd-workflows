# Kubernetes Platform Promotion Validation

A composite GitHub Action that validates environment promotions for Kubernetes platform workloads by ensuring semantic versions never regress when promoted through environments.

For more details on the platform see https://github.com/appvia/kubernetes-platform

## Description

This action enforces a pull-based promotion model across environments (`dev → qa → staging → uat → prod`). When a PR changes an environment file, the action validates that the target environment's version is greater than or equal to its nearest predecessor's version.

This is particularly useful for:

- Preventing accidental version regressions during environment promotions
- Enforcing promotion order in GitOps workflows (ArgoCD, Flux)
- Providing clear, auditable validation results on pull requests
- Supporting teams that use a subset of environments (e.g., `dev → prod` only)

## How It Works

1. **Detects changed files** — identifies which environment YAML files were modified in the PR
2. **Finds the nearest predecessor** — walks backwards through the promotion order to find the closest environment that exists
3. **Compares semantic versions** — validates `target_version >= predecessor_version` using semver comparison
4. **Posts PR comment** — updates the pull request with validation results (idempotent — no duplicate comments)

### Promotion Order

```
dev → qa → staging → uat → prod
```

Teams are not required to use all five environments. The validation walks **backwards** through the promotion order to find the nearest predecessor:

| Environments defined                                           | Valid promotion path            |
| -------------------------------------------------------------- | ------------------------------- |
| `dev.yaml`, `qa.yaml`, `staging.yaml`, `uat.yaml`, `prod.yaml` | dev → qa → staging → uat → prod |
| `dev.yaml`, `prod.yaml`                                        | dev → prod                      |
| `dev.yaml`, `qa.yaml`, `prod.yaml`                             | dev → qa → prod                 |
| `qa.yaml` only                                                 | No predecessor — always passes  |

## Inputs

| Input             | Description                                  | Required | Default                   |
| ----------------- | -------------------------------------------- | -------- | ------------------------- |
| `cicd-repository` | The repository for the cicd workflows        | Yes      | -                         |
| `cicd-branch`     | The branch for the cicd workflows            | Yes      | -                         |
| `workloads-dir`   | Path to the workloads applications directory | No       | `workloads/applications`  |
| `promotion-order` | Comma-separated promotion order              | No       | `dev,qa,staging,uat,prod` |
| `github-token`    | GitHub token for PR comments                 | No       | `${{ github.token }}`     |

## Outputs

| Output    | Description                                          |
| --------- | ---------------------------------------------------- |
| `result`  | The outcome of the validation step (success/failure) |
| `summary` | Full text output from the validation script          |

## Validation Rules

### Rule 1: Semantic Version Gate

The target environment version must be >= the nearest predecessor version. Both are read from the `helm.version` field.

```yaml
# qa.yaml — must be >= dev.yaml version
helm:
  version: "0.2.0"
```

### Rule 2: Helm Workloads Only

Only files containing a `helm:` block are validated. Kustomize workloads (containing `kustomize:` or `kustomize.`) are skipped.

### Rule 3: Branch-Pinned Kustomize Warning

If a Kustomize file pins to a branch name (via `kustomize.ref` or `kustomize.branch` with a non-semver value), a warning is emitted instead of a plain skip, since version validation is not possible.

### Rule 4: First-Time Environments

If no predecessor environment file exists, validation passes. This allows onboarding new environments without a predecessor to compare against.

### Rule 5: Escape Hatch — Hotfix Label

Add the `promotion/skip-validation` label to a PR to bypass all validation checks entirely. This enables hotfixes and rollbacks where a lower version must be deployed.

## Usage Examples

### Example 1: Basic Usage in a Workflow

```yaml
name: Validate Promotion Order

on:
  pull_request:
    branches:
      - main
    paths:
      - "workloads/applications/**/*.yaml"

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

### Example 2: Custom Promotion Order

For teams that only use `dev` and `prod`:

```yaml
- name: Validate Promotion
  uses: appvia/appvia-cicd-workflows/.github/actions/kubernetes-platform-promotion@main
  with:
    workloads-dir: workloads/applications
    promotion-order: dev,prod
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Example 3: Custom Workloads Directory

```yaml
- name: Validate Promotion
  uses: appvia/appvia-cicd-workflows/.github/actions/kubernetes-platform-promotion@main
  with:
    workloads-dir: clusters/production/workloads
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## File Structure

Workload environment files live under the workloads directory:

```
workloads/applications/
├── hello-helm/
│   ├── dev.yaml              # Helm workload — has helm.version
│   ├── qa.yaml               # Helm workload — has helm.version
│   └── values/
│       ├── all.yaml          # Global defaults (excluded from validation)
│       └── dev.yaml          # Dev-specific overrides (excluded from validation)
├── hello-kustomize/
│   └── prod.yaml             # Kustomize workload — skipped
└── hello-branch-pinned/
    └── staging.yaml          # Kustomize with branch ref — warning
```

### Helm Environment File

```yaml
---
helm:
  repository: https://helm.github.io/examples
  chart: hello-world
  version: "0.1.1"

sync:
  phase: primary
  duration: 60s
```

### Kustomize Environment File (Skipped)

```yaml
---
kustomize:
  path: overlays/base
```

### Kustomize with Branch Pin (Warning)

```yaml
---
kustomize:
  path: overlays/base
  ref: main
```

## Edge Cases

| Scenario                                         | Expected Behavior                                                |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| New env file created (no predecessor exists)     | Pass — no version to compare against                             |
| `dev.yaml` changed (first in promotion order)    | Pass — no predecessor                                            |
| `prod.yaml` changed but only `dev.yaml` exists   | Validate prod version >= dev version                             |
| Both `dev.yaml` and `qa.yaml` changed in same PR | Validate each independently; qa checks against dev's new version |
| Only `values/qa.yaml` changed (no env file)      | Workflow does not trigger (path filter excludes `values/`)       |
| Kustomize file changed                           | Skip with informational message                                  |
| Kustomize with branch ref                        | Warning — version validation not possible                        |
| PR has `promotion/skip-validation` label         | Job is skipped entirely                                          |
| Version field missing from a Helm file           | Fail — a Helm workload must have a version                       |
| Invalid semver in version field                  | Fail — report the parsing error                                  |

## Testing

The action includes a fixture-based test suite:

```bash
# Run all tests
./tests/promotion/run-tests.sh

# Run a single test
./tests/promotion/run-tests.sh valid-promotion

# Run multiple tests
./tests/promotion/run-tests.sh valid-promotion version-regression multi-app
```

### Adding a New Test Fixture

```bash
mkdir -p tests/promotion/fixtures/my-scenario/hello-helm
# Add YAML files
echo "hello-helm/qa.yaml" > tests/promotion/fixtures/my-scenario/changed.txt
cat > tests/promotion/fixtures/my-scenario/expected.json << 'EOF'
{ "exit_code": 0, "results": { "hello-helm/qa.yaml": "pass" } }
EOF
```

## Permissions Required

The workflow using this action needs:

```yaml
permissions:
  contents: read # To checkout and read files
  pull-requests: write # To post validation comments
```

## Branch Protection

To enforce this check on the `main` branch, configure:

- **Require a pull request before merging**: enabled
- **Require status checks to pass**: enabled
  - Required check: `Validate Promotion Order`
- **Require approvals**: enabled (2 required)
- **Include administrators**: enabled
- **Do not allow bypassing the above settings**: enabled

## License

This action is part of the appvia-cicd-workflows repository. See the repository LICENSE for details.
