<#
.SYNOPSIS
    Creates a release in Octopus Deploy using the new Octopus CLI.

.DESCRIPTION
    Creates an Octopus Deploy release via 'octopus release create'.

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

.PARAMETER Project
    Name or ID of the Octopus project to create the release in. Case-sensitive.

.PARAMETER Version
    The version number for the new release. e.g. '1.0.42'

.PARAMETER Channel
    Name or ID of the channel to use. Uses the project default channel if omitted.

.PARAMETER PackageVersion
    Default version to use for all packages in the release.

.PARAMETER Packages
    Per-package version overrides. Accepts multiple values.
    Format: 'PackageId:Version', 'StepName:Version', or 'PackageRefName:PackageOrStep:Version'
    e.g. @('MyApp:1.0.42', 'MyApp.Database:1.0.40')

.PARAMETER GitRef
    Git reference e.g. 'refs/heads/main'. Required for Config-as-Code projects.

.PARAMETER GitCommit
    Git commit SHA to pin the release to. Use alongside -GitRef.

.PARAMETER ReleaseNotes
    Release notes string to attach (Markdown supported).

.PARAMETER ReleaseNotesFile
    Path to a file containing release notes (Markdown supported).

.PARAMETER IgnoreExisting
    If a release with the same version already exists, do nothing instead of failing.

.PARAMETER IgnoreChannelRules
    Allow creation of a release where channel rules would otherwise prevent it.

.EXAMPLE
    # Standard release
    .\New-OctopusRelease.ps1 `
        -OctopusUrl    'https://octopus.example.com' `
        -ApiKey        'API-XXXXXXXXXXXXXXXXXX' `
        -Project       'MyApp' `
        -Version       '1.0.42' `
        -PackageVersion '1.0.42'

.EXAMPLE
    # Release with per-package overrides and deploy to Dev
    .\New-OctopusRelease.ps1 `
        -OctopusUrl    'https://octopus.example.com' `
        -ApiKey        'API-XXXXXXXXXXXXXXXXXX' `
        -Project       'MyApp' `
        -Version       '1.0.42' `
        -Channel       'Release' `
        -Packages      @('MyApp:1.0.42', 'MyApp.Database:1.0.40')

.EXAMPLE
    # Config-as-Code project
    .\New-OctopusRelease.ps1 `
        -OctopusUrl    'https://octopus.example.com' `
        -ApiKey        'API-XXXXXXXXXXXXXXXXXX' `
        -Project       'MyApp' `
        -Version       '1.0.42' `
        -GitRef        'refs/heads/main' `
        -GitCommit     'abc123def456'

.EXAMPLE
    # TeamCity — using env vars for credentials
    $env:OCTOPUS_URL     = '%octopus.server.url%'
    $env:OCTOPUS_API_KEY = '%octopus.api.key%'

    .\New-OctopusRelease.ps1 `
        -Project        'MyApp' `
        -Version        '%build.number%' `
        -PackageVersion '%build.number%'
#>

[CmdletBinding()]
param (
    [string]   $OctopusUrl,
    [string]   $ApiKey,
    [string]   $Space              = 'Default',

    [Parameter(Mandatory)][string] $Project,
    [Parameter(Mandatory)][string] $Version,

    [string]   $Channel            = '',
    [string]   $PackageVersion     = '',
    [string[]] $Packages           = @(),
    [string]   $GitRef             = '',
    [string]   $GitCommit          = '',
    [string]   $ReleaseNotes       = '',
    [string]   $ReleaseNotesFile   = '',
    [switch]   $IgnoreExisting,
    [switch]   $IgnoreChannelRules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Set env vars for CLI auth if provided as parameters
# ---------------------------------------------------------------------------
if ($OctopusUrl) { $env:OCTOPUS_URL     = $OctopusUrl }
if ($ApiKey)     { $env:OCTOPUS_API_KEY = $ApiKey }
if ($Space)      { $env:OCTOPUS_SPACE   = $Space }

if (-not $env:OCTOPUS_URL)     { throw 'Octopus URL is required. Use -OctopusUrl or set $env:OCTOPUS_URL.' }
if (-not $env:OCTOPUS_API_KEY) { throw 'API key is required. Use -ApiKey or set $env:OCTOPUS_API_KEY.' }

# ---------------------------------------------------------------------------
# Build argument list
# ---------------------------------------------------------------------------
$cliArgs = [System.Collections.Generic.List[string]]@(
    'release', 'create',
    '--project',  $Project,
    '--version',  $Version,
    '--space',    $env:OCTOPUS_SPACE,
    '--no-prompt'
)

if ($Channel)          { $cliArgs.AddRange([string[]]@('--channel',              $Channel)) }
if ($PackageVersion)   { $cliArgs.AddRange([string[]]@('--package-version',      $PackageVersion)) }
if ($GitRef)           { $cliArgs.AddRange([string[]]@('--git-ref',              $GitRef)) }
if ($GitCommit)        { $cliArgs.AddRange([string[]]@('--git-commit',           $GitCommit)) }
if ($ReleaseNotes)     { $cliArgs.AddRange([string[]]@('--release-notes',        $ReleaseNotes)) }
if ($ReleaseNotesFile) { $cliArgs.AddRange([string[]]@('--release-notes-file',   $ReleaseNotesFile)) }
if ($IgnoreExisting)   { $cliArgs.Add('--ignore-existing') }
if ($IgnoreChannelRules) { $cliArgs.Add('--ignore-channel-rules') }

# Per-package version overrides (may be specified multiple times)
foreach ($pkg in $Packages) {
    $cliArgs.AddRange([string[]]@('--package', $pkg))
}

# ---------------------------------------------------------------------------
# Create the release
# ---------------------------------------------------------------------------
Write-Host "Creating Octopus release '$Version' for project '$Project'..." -ForegroundColor Cyan
Write-Verbose "Running: octopus $($cliArgs -join ' ')"

octopus @cliArgs

if ($LASTEXITCODE -ne 0) {
    throw "octopus release create failed with exit code $LASTEXITCODE."
}

Write-Host "Release '$Version' created successfully." -ForegroundColor Green
