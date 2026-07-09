#Requires -Version 7.0
<#
.SYNOPSIS
    Stages files and pushes to GitHub with a Conventional Commit message.

.PARAMETER RepoPath
    Path to the local git repository. Defaults to the current directory.

.PARAMETER Type
    Conventional commit type: feat, fix, chore, ci, docs, refactor, test, perf, build.

.PARAMETER Scope
    Optional scope in parentheses e.g. "signing" → "chore(signing): …"

.PARAMETER Message
    Short description (the commit subject line).

.PARAMETER Body
    Optional longer description added to the commit body.

.PARAMETER BreakingChange
    Marks the commit as a breaking change (appends ! and BREAKING CHANGE footer).

.PARAMETER Files
    Specific files or globs to stage. Defaults to all changes (git add .).

.PARAMETER Branch
    Branch to push to. Defaults to the current branch.

.PARAMETER DryRun
    Shows what would happen without actually committing or pushing.

.EXAMPLE
    # Stage everything and push
    .\git-conventional-push.ps1 `
        -RepoPath "D:\devops-gurdip-portfolio-main\devops-gurdip-portfolio-main" `
        -Type     "chore" `
        -Scope    "signing" `
        -Message  "add cosign signing and cloudsmith publish scripts"

.EXAMPLE
    # Stage specific files only
    .\git-conventional-push.ps1 `
        -RepoPath "D:\devops-gurdip-portfolio-main\devops-gurdip-portfolio-main" `
        -Type     "ci" `
        -Scope    "release" `
        -Message  "add tar packaging and cosign pipeline" `
        -Files    "sign-artifact.ps1","publish-to-cloudsmith.ps1","create-package-tar.ps1"

.EXAMPLE
    # Dry run to preview commit message
    .\git-conventional-push.ps1 `
        -RepoPath "D:\devops-gurdip-portfolio-main\devops-gurdip-portfolio-main" `
        -Type     "feat" `
        -Message  "add release pipeline" `
        -DryRun
#>

param(
    [string]   $RepoPath       = (Get-Location).Path,

    [ValidateSet("feat","fix","chore","ci","docs","refactor","test","perf","build","style","revert")]
    [string]   $Type           = "chore",

    [string]   $Scope          = "",
    [string]   $Message        = "",
    [string]   $Body           = "",
    [switch]   $BreakingChange,
    [string[]] $Files          = @(),
    [string]   $Branch         = "",
    [switch]   $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host "`n▶  $msg" -ForegroundColor Cyan
}

function Assert-Command([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool '$name' not found on PATH."
    }
}

# ─────────────────────────────────────────────────────────────
# Validate
# ─────────────────────────────────────────────────────────────

Assert-Command "git"

if (-not (Test-Path $RepoPath)) {
    throw "Repo path not found: $RepoPath"
}

Push-Location $RepoPath

try {

if (-not (Test-Path ".git")) {
    throw "$RepoPath is not a git repository."
}

if (-not $Message) {
    throw "-Message is required."
}

# ─────────────────────────────────────────────────────────────
# Build conventional commit subject
# e.g.  chore(signing)!: add cosign scripts
# ─────────────────────────────────────────────────────────────

$scopePart   = if ($Scope) { "($Scope)" } else { "" }
$breakPart   = if ($BreakingChange) { "!" } else { "" }
$subject     = "${Type}${scopePart}${breakPart}: ${Message}"

# Full commit message
$fullMessage = $subject
if ($Body) {
    $fullMessage += "`n`n$Body"
}
if ($BreakingChange) {
    $fullMessage += "`n`nBREAKING CHANGE: $Message"
}

# ─────────────────────────────────────────────────────────────
# Resolve branch
# ─────────────────────────────────────────────────────────────

if (-not $Branch) {
    $Branch = git rev-parse --abbrev-ref HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not determine current branch." }
}

# ─────────────────────────────────────────────────────────────
# Preview
# ─────────────────────────────────────────────────────────────

Write-Step "Conventional commit preview"
Write-Host ""
Write-Host "  Subject : $subject" -ForegroundColor Yellow
if ($Body)           { Write-Host "  Body    : $Body" -ForegroundColor Gray }
if ($BreakingChange) { Write-Host "  ⚠️  BREAKING CHANGE" -ForegroundColor Red }
Write-Host "  Branch  : $Branch" -ForegroundColor Gray
Write-Host "  Repo    : $RepoPath" -ForegroundColor Gray
if ($Files) {
    Write-Host "  Files   :" -ForegroundColor Gray
    $Files | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "  Files   : all changes (git add .)" -ForegroundColor Gray
}

if ($DryRun) {
    Write-Host ""
    Write-Host "  DRY RUN — nothing was committed or pushed." -ForegroundColor Magenta
    exit 0
}

# ─────────────────────────────────────────────────────────────
# Stage
# ─────────────────────────────────────────────────────────────

Write-Step "Staging files"

if ($Files.Count -gt 0) {
    foreach ($f in $Files) {
        git add $f
        if ($LASTEXITCODE -ne 0) { throw "git add failed for: $f" }
        Write-Host "  + $f" -ForegroundColor Gray
    }
} else {
    git add .
    if ($LASTEXITCODE -ne 0) { throw "git add . failed" }
    Write-Host "  + all changes" -ForegroundColor Gray
}

# Check there is actually something to commit
$status = git status --porcelain
if (-not $status) {
    Write-Host ""
    Write-Host "  Nothing to commit — working tree clean." -ForegroundColor Yellow
    exit 0
}

# ─────────────────────────────────────────────────────────────
# Commit
# ─────────────────────────────────────────────────────────────

Write-Step "Committing"

git commit -m $fullMessage
if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

# ─────────────────────────────────────────────────────────────
# Push
# ─────────────────────────────────────────────────────────────

Write-Step "Pushing to origin/$Branch"

git push origin $Branch
if ($LASTEXITCODE -ne 0) { throw "git push failed." }

# ─────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────

$sha = git rev-parse --short HEAD
Write-Host ""
Write-Host "✅  Pushed $sha → origin/$Branch" -ForegroundColor Green
Write-Host "    $subject" -ForegroundColor Cyan

} finally {
    Pop-Location
}
