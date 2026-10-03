# Terraform Module Release

This GitHub Actions workflow template ([terraform-module-release.yml](../.github/workflows/terraform-module-release.yml)) can be used with Terraform repositories to automatically create a GitHub release when a version has been tagged.

## Usage

Create a new workflow file in your Terraform repository (e.g. `.github/workflows/release.yml`) with the below contents:

```yml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  release:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-module-release.yml@main
    name: GitHub Release
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.

## Changelog generation

Set `enable-cliff: true` to build the release notes with [git-cliff](https://git-cliff.org/) from a `.cliff/cliff.toml` in your repository, instead of the GitHub-generated notes:

```yml
permissions:
  contents: write
  ## Required by git-cliff to resolve pull requests and contributors
  pull-requests: read

jobs:
  release:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-module-release.yml@main
    name: GitHub Release
    with:
      enable-cliff: true
```

## Inputs

### Optional Inputs

- `enable-cliff` - Default: false. Indicates if the repository uses cliff for changelog generation. Requires a `.cliff/cliff.toml` configuration file in your repository.

## Permissions

| Scope | When | Why |
| --- | --- | --- |
| `contents: write` | Always | Creates the GitHub release |
| `pull-requests: read` | `enable-cliff: true` | git-cliff lists closed pull requests to attribute commits and contributors |

Declare the scopes explicitly. A caller that declares a `permissions:` block sets every scope it omits to `none`, and a caller that declares none inherits the repository or organisation default, which under the restricted default (`contents: read`) grants neither scope.

The `permissions:` block belongs in your calling workflow, not here: a reusable workflow can only narrow the permissions its caller granted, never widen them.

Omitting `pull-requests: read` with `enable-cliff: true` fails in the `Generate Cliff Changelog` step, where git-cliff panics on the 403 rather than reporting it:

```text
thread 'main' panicked at git-cliff-core/src/changelog.rs:493:18:
Could not get github metadata: HttpClientError(reqwest::Error { kind: Status(403, None),
url: "https://api.github.com/repos/<owner>/<repo>/pulls?per_page=100&page=0&state=closed" })
```
