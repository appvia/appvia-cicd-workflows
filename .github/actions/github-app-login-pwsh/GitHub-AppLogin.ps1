#!/usr/bin/env pwsh
param(
  [Parameter(Mandatory = $true)]
  [string]$AppId,

  [Parameter(Mandatory = $true)]
  [string]$AppInstallationId,

  [Parameter(Mandatory = $true)]
  [string]$AppPrivateKey,

  [string]$EncryptionSecret,

  [String]$Repositories = "",

  [string]$Permissions = "{}",
  # All permissions app has been granted:
  #   actions - The level of permission to grant the access token for GitHub Actions workflows, workflow runs, and artifacts.
  #   actions_variables - The level of permission to grant the access token for GitHub Actions variables.
  #   administration - The level of permission to grant the access token for repository creation, deletion, settings, teams, and collaborators creation.
  #   contents - The level of permission to grant the access token for repository contents, commits, branches, downloads, releases, and merges.
  #   environments - The level of permission to grant the access token for repository environments.
  #   members - The level of permission to grant the access token for organization teams and members.
  #   metadata - The level of permission to grant the access token to search repositories, list collaborators, and access repository metadata.
  #   organization_administration - Organization administration, including hosted-runner image discovery.
  #   organization_network_configurations - Organization network configurations used by hosted runners.
  #   organization_self_hosted_runners - Organization runner groups and hosted runners.
  #   secrets - The level of permission to grant the access token to manage repository secrets.
  #   workflows - The level of permission to grant the access token to update GitHub Actions workflow files.

  # Shorthand for specifying read-only access to all permissions. If specified, overrides the $Permissions parameter.
  [switch]$Readonly
)

$header = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
        alg = "RS256"
        typ = "JWT"
      }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

$jwtPayload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
        iat = [System.DateTimeOffset]::UtcNow.AddSeconds(-10).ToUnixTimeSeconds()
        exp = [System.DateTimeOffset]::UtcNow.AddMinutes(10).ToUnixTimeSeconds()
        iss = $AppId
      }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');


$requestBody = @{}

if (-not [string]::IsNullOrWhiteSpace($Repositories)) {
  $requestBody.repositories = @(
    $Repositories.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries).ForEach({ $_.Trim() }) |
    Where-Object { $_ }
  )
}

if ($Readonly) {
  $requestBody.permissions = @{
    actions                             = "read"
    administration                      = "read"
    contents                            = "read"
    environments                        = "read"
    members                             = "read"
    metadata                            = "read"
    organization_administration         = "read"
    organization_network_configurations = "read"
    organization_self_hosted_runners    = "read"
    secrets                             = "read"
    workflows                           = "read"
  }
}
elseif (-not [string]::IsNullOrWhiteSpace($Permissions)) {
  $requestedPermissions = ConvertFrom-Json -InputObject $Permissions -ErrorAction Stop
  if ($requestedPermissions -isnot [System.Management.Automation.PSCustomObject]) {
    throw "Permissions must be a JSON object mapping permission names to access levels."
  }
  # Omit an empty permissions object so GitHub inherits the installation's approved permissions.
  if (@($requestedPermissions.PSObject.Properties).Count -gt 0) {
    $requestBody.permissions = $requestedPermissions
  }
}

$rsa = [System.Security.Cryptography.RSA]::Create()
$rsa.ImportFromPem($AppPrivateKey)

$signature = [Convert]::ToBase64String($rsa.SignData([System.Text.Encoding]::UTF8.GetBytes("$header.$jwtPayload"), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$jwt = "$header.$jwtPayload.$signature"

$response = Invoke-RestMethod `
  -Uri "https://api.github.com/app/installations/$AppInstallationId/access_tokens" `
  -Method POST `
  -Headers @{
  Authorization                  = "Bearer $jwt";
  Accept                         = "application/vnd.github+json";
  "X-GitHub-Api-Version"         = "2026-03-10";
  # https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
  "X-GitHub-Stateless-S2S-Token" = "enabled";
} `
  -ContentType "application/json" `
  -Body ($requestBody | ConvertTo-Json -Depth 5 -Compress)

$token = $response.token

Write-Host "GitHub App token generated successfully"
Write-Host "::add-mask::$token"
Write-Host "::add-mask::$jwt"
# The JWT authenticates as the App itself (GET /app, GET /app/installations) - the
# installation token above cannot call those endpoints. Short-lived (~10 min), so
# expose it too rather than making callers re-derive it.

# Token will be masked by the GitHub Actions runnner using ::add-mask"
Write-Host "Response: $($response | ConvertTo-Json -Depth 3)"

Add-Content -Path $env:GITHUB_OUTPUT -Value "token=$token"
Add-Content -Path $env:GITHUB_OUTPUT -Value "jwt=$jwt"
