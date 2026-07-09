#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a tar.gz from the dist folder with 'package' as the top-level directory.

.PARAMETER DistPath
    Path to the dist folder. Defaults to the dist folder relative to this script.

.PARAMETER OutputPath
    Where to write the .tar.gz. Defaults to dist/../package.tar.gz

.EXAMPLE
    .\create-package-tar.ps1

.EXAMPLE
    .\create-package-tar.ps1 `
        -DistPath  "D:\devops-gurdip-portfolio-main\devops-gurdip-portfolio-main\dist" `
        -OutputPath "C:\Users\Gurdip\Desktop\package.tar.gz"
#>

param(
    [string] $DistPath   = (Join-Path $PSScriptRoot "dist"),
    [string] $OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host "`n▶  $msg" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────────────────────

if (-not (Test-Path $DistPath)) {
    throw "dist folder not found: $DistPath"
}

$resolvedDist = (Resolve-Path $DistPath).Path
$parentDir    = Split-Path $resolvedDist -Parent

if (-not $OutputPath) {
    $OutputPath = Join-Path $parentDir "package.tar.gz"
}

Write-Step "Pre-flight checks"
Write-Host "  Source  : $resolvedDist"
Write-Host "  Output  : $OutputPath"

# ─────────────────────────────────────────────────────────────
# Stage into a temp 'package' folder so tar picks up the
# correct top-level name without any extra nesting
# ─────────────────────────────────────────────────────────────

Write-Step "Staging files under 'package' folder"

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "tar-staging-$([System.Guid]::NewGuid().ToString('N'))"
$packageDir  = Join-Path $stagingRoot "package"

New-Item -ItemType Directory -Path $packageDir | Out-Null

# Copy everything inside dist → staging/package/
# (excludes any existing dist.tar to avoid re-packing old archives)
Get-ChildItem -Path $resolvedDist -Exclude "*.tar","*.tar.gz","*.tgz" |
    ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $packageDir -Recurse -Force
    }

Write-Host "  Staged to: $stagingRoot"

# ─────────────────────────────────────────────────────────────
# Create tar.gz
# ─────────────────────────────────────────────────────────────

Write-Step "Creating tar.gz"

# Remove existing output if present
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

# tar is built into Windows 10/11 and PowerShell 7
# -C changes into the staging root so the archive root is 'package/'
tar -czf $OutputPath -C $stagingRoot "package"

if ($LASTEXITCODE -ne 0) {
    throw "tar failed with exit code $LASTEXITCODE"
}

# ─────────────────────────────────────────────────────────────
# Verify contents
# ─────────────────────────────────────────────────────────────

Write-Step "Verifying archive contents"
tar -tzf $OutputPath

# ─────────────────────────────────────────────────────────────
# Cleanup staging
# ─────────────────────────────────────────────────────────────

Remove-Item $stagingRoot -Recurse -Force

# ─────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────

$sizeMB = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)

Write-Host ""
Write-Host "✅  Done." -ForegroundColor Green
Write-Host "    $OutputPath  ($sizeMB MB)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Top-level folder inside archive: package/"
Write-Host "Sign it next with:"
Write-Host "  .\sign-artifact.ps1 -DeliverablePath `"$OutputPath`"" -ForegroundColor Gray
