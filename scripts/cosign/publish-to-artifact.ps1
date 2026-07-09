#Requires -Version 7.0
<#
.SYNOPSIS
    Signs one or more deliverables (nupkg, zip, exe, …) with Cosign and
    publishes them plus all signing artefacts to Cloudsmith.

.DESCRIPTION
    CI-ready pipeline that:
      1. Calls sign-artifact.ps1 for each deliverable
      2. Uploads the deliverable + .sha256 + .sig/.bundle (+ cosign.pub) to Cloudsmith

    sign-artifact.ps1 must live in the same directory as this script,
    or be on PATH.

.PARAMETER DeliverablePaths
    One or more paths to sign and publish (nupkg, zip, exe, msi, …).
    Accepts wildcards: e.g. "./dist/*.nupkg"

.PARAMETER CloudsmithOrg
    Cloudsmith organisation slug (e.g. "acme-corp").

.PARAMETER CloudsmithRepo
    Cloudsmith repository slug (e.g. "releases").

.PARAMETER CloudsmithApiKey
    Cloudsmith API key. Prefer the CLOUDSMITH_API_KEY env var.

.PARAMETER ArtifactVersion
    Version string attached to all uploads (e.g. "1.2.3"). Defaults to "unversioned".

.PARAMETER CosignPrivateKeyPath
    Path to cosign.key. Defaults to ./cosign.key.
    Ignored when -KeylessSign is used.

.PARAMETER CosignPublicKeyPath
    Path to cosign.pub. Defaults to ./cosign.pub.

.PARAMETER KeylessSign
    Use Cosign keyless OIDC signing (GitHub Actions, GCP, Azure).
    No private key file is needed.

.PARAMETER GenerateKeys
    Generate a Cosign key pair and exit. Delegates to sign-artifact.ps1.

.EXAMPLE
    # One-time key generation
    .\publish-to-cloudsmith.ps1 -GenerateKeys

.EXAMPLE
    # Publish a single nupkg (key-based)
    $env:CLOUDSMITH_API_KEY = "..."
    $env:COSIGN_PASSWORD    = "..."
    .\publish-to-cloudsmith.ps1 `
        -DeliverablePaths "./dist/MyPackage.1.2.3.nupkg" `
        -CloudsmithOrg    "acme-corp" `
        -CloudsmithRepo   "releases" `
        -ArtifactVersion  "1.2.3"

.EXAMPLE
    # Publish multiple deliverables (zip + nupkg) with keyless signing
    .\publish-to-cloudsmith.ps1 `
        -DeliverablePaths "./dist/*.nupkg", "./dist/myapp-1.2.3.zip" `
        -CloudsmithOrg    "acme-corp" `
        -CloudsmithRepo   "releases" `
        -ArtifactVersion  "1.2.3" `
        -KeylessSign
#>

[CmdletBinding(DefaultParameterSetName = "KeyBased")]
param(
    [Parameter(Mandatory, ParameterSetName = "KeyBased")]
    [Parameter(Mandatory, ParameterSetName = "Keyless")]
    [string[]] $DeliverablePaths,

    [Parameter(Mandatory, ParameterSetName = "KeyBased")]
    [Parameter(Mandatory, ParameterSetName = "Keyless")]
    [string] $CloudsmithOrg,

    [Parameter(Mandatory, ParameterSetName = "KeyBased")]
    [Parameter(Mandatory, ParameterSetName = "Keyless")]
    [string] $CloudsmithRepo,

    [string] $CloudsmithApiKey = $env:CLOUDSMITH_API_KEY,

    [string] $ArtifactVersion  = "unversioned",

    [Parameter(ParameterSetName = "KeyBased")]
    [string] $CosignPrivateKeyPath = "./cosign.key",

    [string] $CosignPublicKeyPath  = "./cosign.pub",

    [Parameter(Mandatory, ParameterSetName = "Keyless")]
    [switch] $KeylessSign,

    [Parameter(Mandatory, ParameterSetName = "GenerateKeys")]
    [switch] $GenerateKeys
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────
# Locate sign-artifact.ps1
# ─────────────────────────────────────────────────────────────

$signScript = Join-Path $PSScriptRoot "sign-artifact.ps1"
if (-not (Test-Path $signScript)) {
    # Fall back to PATH
    $signScript = (Get-Command "sign-artifact.ps1" -ErrorAction SilentlyContinue)?.Source
}
if (-not $signScript) {
    throw "sign-artifact.ps1 not found next to this script or on PATH."
}

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n▶  $msg" -ForegroundColor Cyan
}

function Invoke-CloudsmithUpload {
    param(
        [string] $FilePath,
        [string] $Org,
        [string] $Repo,
        [string] $ApiKey,
        [string] $Version,
        [string] $Summary = ""
    )

    $fileName = Split-Path $FilePath -Leaf
    $uri      = "https://upload.cloudsmith.io/$Org/$Repo/"

    $headers = @{
        "Authorization" = "token $ApiKey"
        "X-Api-Version" = "1"
    }

    $form = @{ version = $Version; name = $fileName }
    if ($Summary) { $form["summary"] = $Summary }

    Write-Host "  → $fileName" -ForegroundColor Gray

    Invoke-RestMethod `
        -Uri         $uri `
        -Method      POST `
        -Headers     $headers `
        -Form        $form `
        -InFile      $FilePath `
        -ContentType "multipart/form-data" | Out-Null
}

# ─────────────────────────────────────────────────────────────
# Delegate key generation to sign-artifact.ps1
# ─────────────────────────────────────────────────────────────

if ($GenerateKeys) {
    & $signScript -GenerateKeys `
        -CosignPrivateKeyPath $CosignPrivateKeyPath `
        -CosignPublicKeyPath  $CosignPublicKeyPath
    exit $LASTEXITCODE
}

# ─────────────────────────────────────────────────────────────
# Validate common args
# ─────────────────────────────────────────────────────────────

if (-not $CloudsmithApiKey) {
    throw "Cloudsmith API key required. Set CLOUDSMITH_API_KEY or pass -CloudsmithApiKey."
}

# Expand wildcards → concrete file list
$resolvedFiles = $DeliverablePaths | ForEach-Object {
    $expanded = Resolve-Path $_ -ErrorAction SilentlyContinue
    if (-not $expanded) { throw "No files matched: $_" }
    $expanded.Path
} | Select-Object -Unique

Write-Host "`nDeliverables to sign and publish:"
$resolvedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host "Cloudsmith : $CloudsmithOrg/$CloudsmithRepo  (v$ArtifactVersion)"
Write-Host "Sign mode  : $(if ($KeylessSign) { 'keyless (OIDC)' } else { 'key-based' })"

# ─────────────────────────────────────────────────────────────
# Process each deliverable
# ─────────────────────────────────────────────────────────────

$pubKeyUploaded = $false   # upload cosign.pub only once per run

foreach ($deliverable in $resolvedFiles) {
    $name = Split-Path $deliverable -Leaf
    Write-Step "Processing: $name"

    # ── Sign ──────────────────────────────────────────────────
    $signArgs = @{
        DeliverablePath = $deliverable
    }
    if ($KeylessSign) {
        $signArgs["KeylessSign"]        = $true
    } else {
        $signArgs["CosignPrivateKeyPath"] = $CosignPrivateKeyPath
        $signArgs["CosignPublicKeyPath"]  = $CosignPublicKeyPath
    }

    # Call sign-artifact.ps1; capture returned hashtable
    $signed = & $signScript @signArgs
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "sign-artifact.ps1 failed for $name (exit $LASTEXITCODE)"
    }

    # ── Upload ────────────────────────────────────────────────
    Write-Step "Uploading to Cloudsmith"

    $toUpload = [System.Collections.Generic.List[hashtable]]::new()
    $toUpload.Add(@{ Path = $signed.Artifact; Summary = "$name v$ArtifactVersion" })
    $toUpload.Add(@{ Path = $signed.Checksum; Summary = "SHA-256 checksum for $name" })

    # Bundle is produced for both key-based and keyless modes
    $toUpload.Add(@{ Path = $signed.Bundle; Summary = "Cosign bundle for $name" })

    if ($signed.Mode -eq "key-based") {
        $toUpload.Add(@{ Path = $signed.ChecksumBundle; Summary = "Cosign bundle for $name checksum" })

        # cosign.pub once per run — consumers need it to verify any artifact
        if (-not $pubKeyUploaded) {
            $toUpload.Add(@{ Path = $signed.PublicKey; Summary = "Cosign public verification key" })
            $pubKeyUploaded = $true
        }
    }

    foreach ($item in $toUpload) {
        Invoke-CloudsmithUpload `
            -FilePath $item.Path `
            -Org      $CloudsmithOrg `
            -Repo     $CloudsmithRepo `
            -ApiKey   $CloudsmithApiKey `
            -Version  $ArtifactVersion `
            -Summary  $item.Summary
    }
}

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "✅  All deliverables published." -ForegroundColor Green
Write-Host "    https://cloudsmith.io/~$CloudsmithOrg/repos/$CloudsmithRepo/packages/" -ForegroundColor Cyan
