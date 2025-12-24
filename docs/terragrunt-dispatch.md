# Terragrunt Manual Dispatch Workflow

This GitHub Actions workflow template ([terragrunt-dispatch.yml](../.github/workflows/terragrunt-dispatch.yml)) provides a manually triggered workflow for running Terragrunt operations on-demand. This is useful for running plan or apply operations outside of the normal CI/CD pipeline.

## Introduction

The Terragrunt dispatch workflow allows you to manually trigger Terragrunt plan and apply operations through the GitHub Actions UI. This is particularly useful for:

- Testing infrastructure changes in specific environments
- Running one-off infrastructure updates
- Executing operations on specific Terragrunt directories
- Controlling when apply operations run, rather than relying on automatic triggers

This workflow serves as a convenience wrapper around the main [terragrunt-plan-and-apply-aws](./terragrunt-plan-and-apply-aws.md) workflow, allowing you to invoke it manually with custom parameters.

## Workflow Steps

This workflow dispatches to the main Terragrunt workflow with the parameters you specify:

1. **Manual Trigger:** You initiate the workflow through GitHub's UI with your chosen parameters
2. **Invokes Main Workflow:** Calls the `terragrunt-plan-and-apply-aws.yml` workflow with your parameters
3. **Executes Operations:** Runs the plan and/or apply operations based on your selections

## Usage

Add this workflow file to your Terragrunt repository as `.github/workflows/terragrunt-manual.yml`:

```yml
name: Manual Terragrunt Trigger
on:
  workflow_dispatch:
    inputs:
      aws-account-id:
        description: "The AWS account ID to deploy to"
        required: true
        type: string

      aws-role:
        description: "The AWS role to assume"
        required: true
        type: string

      enable_plan:
        description: "Whether to run the plan step"
        required: false
        type: boolean
        default: true

      enable_apply:
        description: "Whether to run the apply step"
        required: false
        type: boolean
        default: false

      terragrunt-dir:
        description: "The directory to deploy to"
        required: false
        type: string
        default: "."

permissions:
  contents: read
  id-token: write
  pull-requests: write

jobs:
  terragrunt:
    uses: appvia/appvia-cicd-workflows/.github/workflows/terragrunt-plan-and-apply-aws.yml@main
    name: "Terragrunt (Plan: ${{ inputs.enable_plan }}, Apply: ${{ inputs.enable_apply }})"
    secrets:
      actions-id: "${{ secrets.ORG_ACTIONS_APP_ID }}"
      actions-secret: "${{ secrets.ORG_ACTIONS_APP_SECRET }}"
      github-token: ${{ secrets.REPO_GITHUB_TOKEN }}
      infracost-api-key: ${{ secrets.ORG_INFRACOST_API_KEY }}
    with:
      aws-account-id: ${{ inputs.aws-account-id }}
      aws-role: ${{ inputs.aws-role }}
      enable-private-access: true
      enable-terragrunt-apply: ${{ inputs.enable_apply }}
      enable-terragrunt-plan: ${{ inputs.enable_plan }}
      terragrunt-dir: ${{ inputs.terragrunt-dir }}
```

## How to Trigger

Once the workflow is added to your repository:

1. Navigate to your repository on GitHub
2. Click on the **Actions** tab
3. Select the **Manual Terragrunt Trigger** workflow from the left sidebar
4. Click the **Run workflow** dropdown button
5. Fill in the required parameters:
   - **Enable Plan:** Check to run a Terragrunt plan
   - **Enable Apply:** Check to run a Terragrunt apply (use with caution!)
   - **Terragrunt Directory:** The directory containing your Terragrunt configuration
6. Click **Run workflow**

## Inputs

The workflow accepts the following inputs when manually triggered:

### Optional Inputs

- `aws-account-id` - The AWS account ID to deploy to
- `aws-role` - The AWS IAM role to assume for deployment
- `enable_apply` - Default: false. Whether to run the Terragrunt apply step (use with caution!)
- `enable_plan` - Default: false. Whether to run the Terragrunt plan step
- `terragrunt-dir` - Default: ".". The directory containing the Terragrunt configuration to execute

## Examples

### Plan Only (Safe Operation)

The safest way to use this workflow is to enable only the plan operation:

1. Set `enable_plan` to **true**
2. Set `enable_apply` to **false**
3. Specify the AWS account and role
4. Optionally specify a specific Terragrunt directory

This will show you what changes would be made without actually applying them.

### Plan and Apply (Dangerous Operation)

For actually deploying infrastructure changes:

1. Set `enable_plan` to **true**
2. Set `enable_apply` to **true**
3. Ensure you have the correct AWS account and role
4. Verify the Terragrunt directory is correct

**Warning:** This will make real changes to your infrastructure. Use with extreme caution!

### Specific Directory Deployment

To work with a specific Terragrunt module:

```
aws-account-id: 123456789012
aws-role: terraform-deployer
enable_plan: true
enable_apply: false
terragrunt-dir: environments/production/networking
```

## Required Secrets

The workflow requires the following secrets to be configured in your repository:

- `ORG_ACTIONS_APP_ID` - GitHub App ID for accessing private modules
- `ORG_ACTIONS_APP_SECRET` - GitHub App secret for accessing private modules
- `REPO_GITHUB_TOKEN` - GitHub token for repository operations
- `ORG_INFRACOST_API_KEY` - API key for Infracost cost estimation (optional)

## Permissions

The workflow requires the following permissions:

- `contents: read` - To read repository contents
- `id-token: write` - To authenticate with AWS using OIDC
- `pull-requests: write` - To add comments to pull requests (if applicable)

## Best Practices

1. **Plan First:** Always run with `enable_plan: true` and `enable_apply: false` first to review changes
2. **Review Output:** Carefully review the plan output before running apply
3. **Specific Directories:** Use the `terragrunt-dir` parameter to target specific modules
4. **Environment Protection:** Consider using GitHub environment protection rules for production accounts
5. **Audit Trail:** GitHub Actions provides an audit trail of who triggered manual workflows and with what parameters
6. **Notifications:** Configure Slack or email notifications for manual workflow executions
7. **Limited Access:** Restrict who can trigger manual workflows using branch protection and environment protection rules

## Use Cases

- **Emergency Hotfixes:** Deploy urgent infrastructure fixes outside normal release cycles
- **Testing:** Test Terragrunt configurations in non-production environments
- **Selective Deployment:** Deploy specific modules without running the entire pipeline
- **Troubleshooting:** Run plan operations to investigate drift or issues
- **Maintenance Windows:** Execute infrastructure changes during planned maintenance windows

## Comparison with Automatic Workflows

| Feature | Manual Dispatch | Automatic (PR/Push) |
|---------|----------------|---------------------|
| Trigger | Manual via UI | Automatic on PR/push to main |
| Control | Full control over timing | Automated on code changes |
| Safety | Explicit action required | Automatic on merge |
| Use Case | One-off operations, testing | Regular CI/CD pipeline |

For regular infrastructure deployments, use the automatic workflow triggered by pull requests and merges. Use the manual dispatch workflow for exceptional cases requiring explicit control.

**Note:** For full details on all available parameters and features, see the [Terragrunt Plan & Apply (AWS)](./terragrunt-plan-and-apply-aws.md) documentation.
