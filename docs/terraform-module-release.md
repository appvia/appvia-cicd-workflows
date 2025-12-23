# Terraform Module Release

This GitHub Actions workflow template ([terraform-module-release.yml](../.github/workflows/terraform-module-release.yml)) can be used with Terraform repositories to automatically create a GitHub release when a version has been tagged.

The workflow supports two modes for release notes generation:
1. **Default Mode**: Uses GitHub's automatic release notes generation
2. **Git Cliff Mode**: Uses [git-cliff](https://github.com/orhun/git-cliff) for customizable changelog generation

## Usage

### Basic Usage (Default Release Notes)

Create a new workflow file in your Terraform repository (e.g. `.github/workflows/release.yml`) with the below contents:

```yml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-module-release.yml@main
    name: GitHub Release
```

### Advanced Usage (Git Cliff Changelog)

To use git-cliff for changelog generation, set `enable-cliff: true` and ensure you have a `.cliff/cliff.toml` configuration file in your repository:

```yml
name: Release

on:
  push:
    tags:
      - "v*"

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

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
