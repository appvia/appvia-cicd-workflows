# Docker Build, Push & Security Scan Workflow

This GitHub Actions workflow template ([docker-build.yml](../.github/workflows/docker-build.yml)) provides a comprehensive solution for building, pushing, and securing Docker images. The workflow includes Dockerfile linting, multi-architecture builds, security scanning, and supports both OIDC and traditional AWS authentication methods for ECR.

## Features

- **Dockerfile Linting**: Uses Hadolint to check Dockerfile best practices and catch common mistakes
- **Multi-Architecture Builds**: Supports both AMD64 and ARM64 architectures using Docker Buildx
- **Security Scanning**: Integrates Trivy for container vulnerability scanning with SARIF upload to GitHub Security
- **ECR Integration**: Seamless integration with Amazon ECR for image storage
- **OIDC Authentication**: Secure authentication using OpenID Connect (recommended)
- **Build Caching**: Leverages Docker layer caching for faster builds
- **BuildKit Support**: Optional BuildKit support for improved build performance

## Workflow Steps

1. **Dockerfile Linting**: Runs Hadolint to validate Dockerfile syntax and best practices
2. **Docker Build**: Builds the Docker image using Buildx with multi-architecture support
3. **ECR Authentication**: Authenticates with AWS ECR using either OIDC or access keys
4. **Image Push**: Pushes the built image to ECR with appropriate tags
5. **Security Scanning**: Scans the built image for vulnerabilities using Trivy
6. **Results Upload**: Uploads security scan results to GitHub Security tab
7. **Build Summary**: Generates a comprehensive summary of the build process

## Usage

Create a new workflow file in your repository (e.g., `.github/workflows/docker.yml`) with the following contents:

### Basic Usage (OIDC Authentication - Recommended)

```yml
name: Build and Push Docker Image
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  docker:
    uses: appvia/appvia-cicd-workflows/.github/workflows/docker-build.yml@main
    with:
      registry: docker.io
      image-name: myimage
      image-tag: v0.0.1
      aws-account-id: 123456789012
      aws-role: my-docker-build-role
      enable-oidc: true
```

### Using Access Keys (Legacy)

```yml
name: Build and Push Docker Image
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  docker:
    uses: appvia/appvia-cicd-workflows/.github/workflows/docker-build.yml@main
    secrets:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    with:
      registry: 123456789012.dkr.ecr.eu-west-2.amazonaws.com
      image-name: myapplication
      enable-oidc: false
```

### Advanced Configuration

```yml
name: Build and Push Docker Image
on:
  push:
    branches:
      - main
      tags:
        - 'v*'
  pull_request:
    branches:
      - main

jobs:
  docker:
    uses: appvia/appvia-cicd-workflows/.github/workflows/docker-build.yml@main
    with:
      aws-account-id: 123456789012
      aws-region: eu-west-2
      aws-role: my-docker-build-role
      build-args: "NODE_ENV=production,BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      context-path: .
      dockerfile-path: ./docker/Dockerfile
      enable-buildkit: true
      enable-oidc: true
      enable-push: true
      fail-on-vulnerabilities: true
      registry: 123456789012.dkr.ecr.eu-west-2.amazonaws.com
      image-name: myapplication
      image-tag: v0.0.1
      trivy-severity: "CRITICAL,HIGH"
```

## Inputs

### Required Inputs

- `registry`: Name of the registry (e.g., `123456789012.dkr.ecr.eu-west-2.amazonaws.com`)
- `image-name`: The name of the image (e.g., `myapplication`)

### Optional Inputs

- `image-tag`: Docker image name (defaults to the gitsha)

#### Build Configuration

- `dockerfile-path`: Path to Dockerfile (default: `Dockerfile`)
- `context-path`: Build context path (default: `.`)
- `build-args`: Docker build arguments as comma-separated `key=value` pairs
- `cache-from`: Cache from image tag (e.g., `latest` or previous build tag)
- `working-directory`: Working directory for build (default: `.`)
- `image-platforms`: Platforms to build the image for (default: `linux/amd64,linux/arm64`)

#### AWS Configuration

- `aws-region`: AWS region for ECR (default: `eu-west-2`)
- `aws-account-id`: AWS account ID (required if `enable-oidc` is `true`)
- `aws-role`: AWS IAM role name to assume (required if `enable-oidc` is `true`)
- `enable-oidc`: Use OIDC authentication (default: `false`)

#### Feature Flags

- `enable-buildkit`: Enable Docker BuildKit (default: `true`)
- `enable-push`: Push image to registry (default: `true`; automatically disabled for pull requests)

#### Security Configuration

- `trivy-severity`: Severity levels to fail on (default: `CRITICAL,HIGH`)
- `trivy-version`: Trivy version to use (default: `latest`)
- `fail-on-vulnerabilities`: Fail build if vulnerabilities found (default: `true`)

#### Runner Configuration

- `runs-on`: GitHub runner to use (default: `ubuntu-latest`)

## Secrets

### OIDC Authentication (Recommended)

When using OIDC authentication (`enable-oidc: true`), no secrets are required. The workflow uses GitHub's OIDC provider to authenticate with AWS.

**Prerequisites:**

1. AWS OIDC provider configured in your AWS account
2. IAM role with trust policy allowing GitHub Actions to assume it
3. IAM role with permissions to push/pull from ECR

Example IAM trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:*"
        }
      }
    }
  ]
}
```

### Access Key Authentication (Legacy)

When using access keys (`use-oidc: false`), provide the following secrets:

- `aws-access-key-id`: AWS Access Key ID
- `aws-secret-access-key`: AWS Secret Access Key

### Registry Credentials

When not using OIDC or AWS credentials, you can also pass docker username and password credentials

- `docker-username`: The username to use to login
- `docker-password`: The password to use to authenticate to the registry

## Image Tagging

The workflow automatically generates tags based on:

- Branch name (for branch builds)
- Pull request number (for PR builds)
- Semantic version (for tag pushes matching `v*` pattern)
- Commit SHA (for default branch)
- Custom tag (if provided via `image-tag` input)

Example tags:

- `main-abc1234` (branch + SHA)
- `pr-123` (pull request)
- `v1.2.3` (semantic version)
- `1.2` (major.minor)

## Security Scanning

The workflow uses Trivy to scan built images for vulnerabilities. Results are:

- Displayed in the workflow summary
- Uploaded to GitHub Security tab as SARIF
- Can fail the build if critical/high vulnerabilities are found (configurable)

### Ignoring Vulnerabilities

Create a `.trivyignore` file in your repository root to ignore specific vulnerabilities:

```
CVE-2021-12345
CVE-2021-67890
```

## Dockerfile Linting

The workflow uses Hadolint to lint Dockerfiles. Common rules are automatically ignored:

- `DL3008`: Pin versions in apt-get install
- `DL3009`: Delete the apt-get lists after installing

To customize ignored rules, you can create a `.hadolint.yaml` file in your repository.

## Build Caching

The workflow supports Docker layer caching to speed up builds:

- Uses ECR as the cache backend
- Caches from a specified tag (via `cache-from` input)
- Defaults to `latest` tag if not specified

## Best Practices

1. **Use OIDC Authentication**: Prefer OIDC over access keys for better security
2. **Enable Security Scanning**: Always enable security scanning in production
3. **Pin Versions**: Use specific Trivy versions in production
4. **Review Vulnerabilities**: Regularly review and address security findings
5. **Use Build Caching**: Leverage caching for faster builds
6. **Multi-Architecture**: The workflow builds for both AMD64 and ARM64 by default

## Troubleshooting

### Authentication Failures

**OIDC Authentication:**

- Verify the IAM role trust policy allows your repository
- Check that the OIDC provider is correctly configured
- Ensure the role has ECR permissions

**Access Key Authentication:**

- Verify secrets are correctly set in repository settings
- Check that the access key has ECR permissions

### Build Failures

- Check Dockerfile syntax with Hadolint locally
- Verify build context includes all necessary files
- Review build logs for specific error messages

### Security Scan Failures

- Review vulnerabilities in the GitHub Security tab
- Add false positives to `.trivyignore` if needed
- Update base images to resolve vulnerabilities

## Example IAM Policy for ECR

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

## License

This workflow is distributed under the [Apache License, Version 2.0](../LICENSE).
