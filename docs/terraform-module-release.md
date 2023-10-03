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

jobs:
  release:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terraform-module-release.yml@main
    name: GitHub Release
```

**Note:** This template may change over time, so it is recommended that you point to a tagged version rather than the main branch.
