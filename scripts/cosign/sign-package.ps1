#Requires -Version 7.0
<#
.SYNOPSIS
    Signs any deliverable (nupkg, zip, exe, etc.) with Cosign and produces
    a SHA-256 checksum. Can be used standalone or called from publish-to-cloudsmith.ps1.

.DESCRIPTION
    Accepts a path to any file, computes its SHA-256 checksum, signs both
    the artifact and the checksum with Cosign (key-based or keyless OIDC),
    and verifies the signature locally before exiting.

    Outputs a hashtable of produced files so callers can consume them:
        $result.Artifact      – original file (resolved absolute path)
        $result.Checksum      – <artifact>.sha256
        $result.Signature     – <artifact>.sig          (key-based only)
        $result.ChecksumSig   – <artifact>.sha256.sig   (key-based only)
        $result.Bundle        – <artifact>.bundle       (keyless only)
        $result.PublicKey     – resolved path to cosign.pub (key-based only)
        $result.Mode          – "key-based" | "keyless"

.PARAMETER DeliverablePath
    Path to the file to sign. Accepts any file type: .nupkg, .zip, .exe, .msi, etc.

.PARAMETER CosignPrivateKeyPath
    Path to cosign.key. Defaults to ./cosign.key.
    Ignored when -KeylessSign is used.

.PARAMETER CosignPublicKeyPath
    Path to cosign.pub. Defaults to ./cosign.pub.
    Used for local verification after signing. Ignored when -KeylessSign is used.

.PARAMETER KeylessSign
    Use Cosign keyless signing via ambient OIDC token (GitHub Actions, GCP, Azure, etc.).
    No private key file is needed. The Rekor transparency log entry is embedded in the bundle.

.PARAMETER GenerateKeys
    Generate a new Cosign key pair and exit. Run once during initial setup.
    Reads passphrase from COSIGN_PASSWORD env var, or prompts interactively.

.PARAMETER OutputDir
    Directory to write signing artefacts (.sig, .sha256, .bundle) into.
    Defaults to the same directory as the deliverable.

.EXAMPLE
    # One-time: generate key pair
    .\sign-artifact.ps1 -GenerateKeys

.EXAMPLE
    # Sign a nupkg (key-based)
    $env:COSIGN_PASSWORD = "..."
    .\sign-artifact.ps1 -DeliverablePath "./dist/MyPackage.1.2.3.nupkg"

.EXAMPLE
    # Sign a nupkg (keyless, e.g. inside GitHub Actions)
    .\sign-artifact.ps1 -DeliverablePath "./dist/MyPackage.1.2.3.nupkg" -KeylessSign

.EXAMPLE
    # Use from another script and capture output paths
    $signed = .\sign-artifact.ps1 -DeliverablePath $nupkgPath
    Write-Host "Signature at: $($signed.Signature)"
#>

[CmdletBinding(DefaultParameterSetName = "KeyBased")]
param(
    [Parameter(Mandatory, ParameterSetName = "KeyBased", Position = 0)]
    [Parameter(Mandatory, ParameterSetName = "Keyless",  Position = 0)]
    [string] $DeliverablePath,

    [Parameter(ParameterSetName = "KeyBased")]
    [string] $CosignPrivateKeyPath = "./cosign.key",

    [string] $CosignPublicKeyPath  = "./cosign.pub",

    [Parameter(Mandatory, ParameterSetName = "Keyless")]
    [switch] $KeylessSign,

    [Parameter(Mandatory, ParameterSetName = "GenerateKeys")]
    [switch] $GenerateKeys,

    [string] $OutputDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n▶  $msg" -ForegroundColor Cyan
}

function Assert-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool '$name' not found. Please install it and ensure it is on PATH."
    }
}

# ─────────────────────────────────────────────────────────────
# Dependency check
# ─────────────────────────────────────────────────────────────

Assert-Command "cosign"

# ─────────────────────────────────────────────────────────────
# MODE: Generate keys (one-time setup)
# ─────────────────────────────────────────────────────────────

if ($GenerateKeys) {
    Write-Step "Generating Cosign key pair"

    $privateKeyPath = Resolve-Path -LiteralPath (Split-Path $CosignPrivateKeyPath -Parent) |
        ForEach-Object { Join-Path $_.Path (Split-Path $CosignPrivateKeyPath -Leaf) }

    if (Test-Path $privateKeyPath) {
        Write-Warning "Key '$privateKeyPath' already exists. Remove it first to regenerate."
        exit 1
    }

    if (-not $env:COSIGN_PASSWORD) {
        $secPwd = Read-Host "Enter passphrase for cosign.key" -AsSecureString
        $env:COSIGN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
        )
    }

    $prefix = [System.IO.Path]::GetFileNameWithoutExtension($CosignPrivateKeyPath)
    cosign generate-key-pair --output-key-prefix $prefix

    Write-Host ""
    Write-Host "✅  Key pair generated:" -ForegroundColor Green
    Write-Host "    Private : $CosignPrivateKeyPath"
    Write-Host "              ^ Add to your CI secrets / secrets manager. Never commit." -ForegroundColor Yellow
    Write-Host "    Public  : $CosignPublicKeyPath"
    Write-Host "              ^ Commit to your repo or publish to a trust store." -ForegroundColor Gray
    exit 0
}

# ─────────────────────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────────────────────

Write-Step "Pre-flight checks"

if (-not (Test-Path $DeliverablePath)) {
    throw "Deliverable not found: $DeliverablePath"
}

$resolvedDeliverable = (Resolve-Path $DeliverablePath).Path
$deliverableName     = Split-Path $resolvedDeliverable -Leaf
$deliverableDir      = Split-Path $resolvedDeliverable -Parent

# Where to write signing artefacts
$sigDir = if ($OutputDir) {
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
    (Resolve-Path $OutputDir).Path
} else {
    $deliverableDir
}

$stem         = Join-Path $sigDir $deliverableName
$checksumFile = "$stem.sha256"
$sigFile      = "$stem.sig"
$checksumSig  = "$checksumFile.sig"
$bundleFile   = "$stem.bundle"

if (-not $KeylessSign) {
    if (-not (Test-Path $CosignPrivateKeyPath)) {
        throw "Cosign private key not found: $CosignPrivateKeyPath. Run with -GenerateKeys first."
    }
    if (-not $env:COSIGN_PASSWORD) {
        throw "COSIGN_PASSWORD environment variable must be set for key-based signing."
    }
    $resolvedPubKey = (Resolve-Path $CosignPublicKeyPath).Path
}

Write-Host "  Deliverable : $resolvedDeliverable"
Write-Host "  Output dir  : $sigDir"
Write-Host "  Sign mode   : $(if ($KeylessSign) { 'keyless (OIDC / Sigstore)' } else { 'key-based' })"

# ─────────────────────────────────────────────────────────────
# Step 1 – SHA-256 checksum
# ─────────────────────────────────────────────────────────────

Write-Step "Computing SHA-256 checksum"

$hash = (Get-FileHash -Algorithm SHA256 $resolvedDeliverable).Hash.ToLower()
"$hash  $deliverableName" | Set-Content $checksumFile -Encoding ascii

Write-Host "  $hash"
Write-Host "  Written to: $checksumFile"

# ─────────────────────────────────────────────────────────────
# Step 2 – Sign
# ─────────────────────────────────────────────────────────────

Write-Step "Signing with Cosign"

if ($KeylessSign) {
    # Keyless: ambient OIDC token (GitHub Actions / GCP / Azure) → Rekor log
    cosign sign-blob `
        --yes `
        --bundle $bundleFile `
        $resolvedDeliverable

    Write-Host "  Bundle (sig + Rekor entry): $bundleFile"
} else {
    # Key-based: use --bundle output (cosign v2 modern path — no legacy warning).
    # The bundle embeds the signature and the public key certificate so consumers
    # only need cosign.pub to verify; no separate .sig file required.
    cosign sign-blob `
        --key                $CosignPrivateKeyPath `
        --bundle             $bundleFile `
        --tlog-upload=false `
        $resolvedDeliverable

    Write-Host "  Bundle : $bundleFile"

    # Sign the checksum with the same approach
    cosign sign-blob `
        --key                $CosignPrivateKeyPath `
        --bundle             "$checksumFile.bundle" `
        --tlog-upload=false `
        $checksumFile

    Write-Host "  Checksum bundle: $checksumFile.bundle"
}

# ─────────────────────────────────────────────────────────────
# Step 3 – Local verification (catch key/config mistakes early)
# ─────────────────────────────────────────────────────────────

Write-Step "Verifying signature (local sanity check)"

if ($KeylessSign) {
    cosign verify-blob `
        --bundle $bundleFile `
        $resolvedDeliverable
} else {
    # --insecure-ignore-tlog because we deliberately skipped the transparency log
    # (--tlog-upload=false above). This is correct for air-gapped / private CI.
    cosign verify-blob `
        --key                 $resolvedPubKey `
        --bundle              $bundleFile `
        --insecure-ignore-tlog `
        $resolvedDeliverable

    Write-Host "  ✅ Signature verified against $resolvedPubKey"
}

# ─────────────────────────────────────────────────────────────
# Return result hashtable (for use when dot-sourced or called
# from publish-to-cloudsmith.ps1 via & operator + capture)
# ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "✅  Signing complete." -ForegroundColor Green

$result = [ordered]@{
    Artifact = $resolvedDeliverable
    Checksum = $checksumFile
    Bundle   = $bundleFile
    Mode     = if ($KeylessSign) { "keyless" } else { "key-based" }
}

if (-not $KeylessSign) {
    $result.ChecksumBundle = "$checksumFile.bundle"
    $result.PublicKey      = $resolvedPubKey
}

Write-Host ""
Write-Host "Files produced:"
foreach ($k in $result.Keys) {
    Write-Host ("  {0,-16} {1}" -f "${k}:", $result[$k]) -ForegroundColor Gray
}

Write-Host ""
Write-Host "Verify on another machine with:"
if ($KeylessSign) {
    Write-Host "  cosign verify-blob --bundle $bundleFile $resolvedDeliverable"
} else {
    Write-Host "  cosign verify-blob --key cosign.pub --bundle $bundleFile --insecure-ignore-tlog $resolvedDeliverable"
}

return $result
