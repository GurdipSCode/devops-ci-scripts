<#
.SYNOPSIS
    Pushes build information to Octopus Deploy using the new Octopus CLI.

.DESCRIPTION
    Constructs a build information JSON payload and uploads it to Octopus
    Deploy via the 'octopus build-information upload' command.

    Requires the new Octopus CLI (octopus) — NOT the deprecated octo CLI.
    Install: choco install octopus-cli
             https://octopus.com/downloads/octopuscli

.PARAMETER OctopusUrl
    Base URL of your Octopus Deploy instance. e.g. https://octopus.example.com
    Can also be set via the OCTOPUS_URL environment variable.

.PARAMETER ApiKey
    Octopus Deploy API key.
    Can also be set via the OCTOPUS_API_KEY environment variable.

.PARAMETER Space
    Octopus space name or ID. Defaults to 'Default'.
    Can also be set via the OCTOPUS_SPACE environment variable.

.PARAMETER PackageId
    The package ID to associate build information with. e.g. 'MyCompany.MyApp'

.PARAMETER Version
    The package version. Must match the version of the package in Octopus.

.PARAMETER BuildNumber
    The CI build number.

.PARAMETER BuildUrl
    URL linking back to the CI build. e.g. https://teamcity.example.com/build/123

.PARAMETER VcsRoot
    URL of the source repository. e.g. https://github.com/org/repo

.PARAMETER Branch
    Branch the build was triggered from. Auto-detected from git if not provided.

.PARAMETER CommitSha
    The git commit SHA. Auto-detected from git if not provided.

.PARAMETER BuildEnvironment
    The name of the build environment. Defaults to 'TeamCity'.

.PARAMETER OverwriteMode
    Behaviour if build information already exists for this package+version.
    Valid values: FailIfExists | OverwriteExisting | IgnoreIfExists
    Defaults to OverwriteExisting.

.EXAMPLE
    # Explicit parameters
    .\Push-OctopusBuildInfo.ps1 `
        -OctopusUrl      'https://octopus.example.com' `
        -ApiKey          'API-XXXXXXXXXXXXXXXXXX' `
        -PackageId       'MyCompany.MyApp' `
        -Version         '1.0.42' `
        -BuildNumber     '42' `
        -BuildUrl        'https://teamcity.example.com/viewLog.html?buildId=42' `
        -VcsRoot         'https://github.com/org/repo'

.EXAMPLE
    # Using environment variables for credentials (recommended for CI)
    $env:OCTOPUS_URL     = 'https://octopus.example.com'
    $env:OCTOPUS_API_KEY = 'API-XXXXXXXXXXXXXXXXXX'
    $env:OCTOPUS_SPACE   = 'Default'

    .\Push-OctopusBuildInfo.ps1 `
        -PackageId   'MyCompany.MyApp' `
        -Version     '%build.number%' `
        -BuildNumber '%build.number%' `
        -BuildUrl    '%teamcity.serverUrl%/viewLog.html?buildId=%teamcity.build.id%' `
        -VcsRoot     'https://github.com/org/repo'
#>

[CmdletBinding()]
param (
    [string] $OctopusUrl,
    [string] $ApiKey,
    [string] $Space            = 'Default',

    [Parameter(Mandatory)][string] $PackageId,
    [Parameter(Mandatory)][string] $Version,
    [Parameter(Mandatory)][string] $BuildNumber,
    [Parameter(Mandatory)][string] $BuildUrl,
    [Parameter(Mandatory)][string] $VcsRoot,

    [string] $Branch           = '',
    [string] $CommitSha        = '',
    [string] $BuildEnvironment = 'TeamCity',

    [ValidateSet('FailIfExists', 'OverwriteExisting', 'IgnoreIfExists')]
    [string] $OverwriteMode    = 'OverwriteExisting'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Set env vars for CLI auth if provided as parameters
# ---------------------------------------------------------------------------
if ($OctopusUrl) { $env:OCTOPUS_URL     = $OctopusUrl }
if ($ApiKey)     { $env:OCTOPUS_API_KEY = $ApiKey }
if ($Space)      { $env:OCTOPUS_SPACE   = $Space }

# Validate that credentials are available one way or another
if (-not $env:OCTOPUS_URL)     { throw 'Octopus URL is required. Use -OctopusUrl or set $env:OCTOPUS_URL.' }
if (-not $env:OCTOPUS_API_KEY) { throw 'API key is required. Use -ApiKey or set $env:OCTOPUS_API_KEY.' }

# ---------------------------------------------------------------------------
# Auto-detect git metadata if not provided
# ---------------------------------------------------------------------------
if (-not $Branch) {
    $Branch = (git rev-parse --abbrev-ref HEAD 2>$null) ?? 'unknown'
    Write-Verbose "Auto-detected branch: $Branch"
}

if (-not $CommitSha) {
    $CommitSha = (git rev-parse HEAD 2>$null) ?? 'unknown'
    Write-Verbose "Auto-detected commit: $CommitSha"
}

# ---------------------------------------------------------------------------
# Build commit list from git log (last 20 commits)
# ---------------------------------------------------------------------------
$commits = [System.Collections.Generic.List[hashtable]]::new()

try {
    $logLines = git log --pretty=format:'%H|%s' -20 2>$null
    foreach ($line in $logLines) {
        $parts = $line -split '\|', 2
        if ($parts.Count -eq 2) {
            $commits.Add(@{
                Id      = $parts[0].Trim()
                LinkUrl = "$VcsRoot/commit/$($parts[0].Trim())"
                Comment = $parts[1].Trim()
            })
        }
    }
    Write-Verbose "Collected $($commits.Count) commits from git log."
} catch {
    Write-Warning "Could not read git log. Commits will be empty. Error: $_"
}

# ---------------------------------------------------------------------------
# Construct the build information JSON payload
# ---------------------------------------------------------------------------
$payload = [ordered]@{
    PackageId        = $PackageId
    Version          = $Version
    Branch           = $Branch
    BuildEnvironment = $BuildEnvironment
    BuildNumber      = $BuildNumber
    BuildUrl         = $BuildUrl
    VcsType          = 'Git'
    VcsRoot          = $VcsRoot
    VcsCommitNumber  = $CommitSha
    Commits          = $commits.ToArray()
}

$jsonPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "octopus-buildinfo-$PackageId-$Version.json")
$payload | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Verbose "Build information JSON written to: $jsonPath"
if ($VerbosePreference -eq 'Continue') {
    Get-Content $jsonPath | Write-Verbose
}

# ---------------------------------------------------------------------------
# Upload using the new Octopus CLI
# ---------------------------------------------------------------------------
Write-Host "Uploading build information for '$PackageId' v$Version to Octopus..." -ForegroundColor Cyan

octopus build-information upload `
    --package-id     $PackageId `
    --version        $Version `
    --file           $jsonPath `
    --overwrite-mode $OverwriteMode `
    --space          $env:OCTOPUS_SPACE `
    --no-prompt

if ($LASTEXITCODE -ne 0) {
    throw "octopus build-information upload failed with exit code $LASTEXITCODE."
}

Write-Host "Build information uploaded successfully." -ForegroundColor Green

# Cleanup
Remove-Item -Path $jsonPath -ErrorAction SilentlyContinue
