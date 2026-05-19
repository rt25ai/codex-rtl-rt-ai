<#
RT-AI Codex RTL Patch - Online uninstaller
Run via:
  irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/uninstall-online.ps1 | iex

Downloads patch.ps1 and runs it with -Uninstall. No admin required.
#>

[CmdletBinding()]
param(
    [string] $Repo = "rt25ai/codex-rtl-rt-ai",
    [string] $Branch = "v0.1.1"
)

$ErrorActionPreference = "Stop"

function Write-Info { param([string] $Message) Write-Host "  [*] $Message" }
function Write-Ok   { param([string] $Message) Write-Host "  [+] $Message" -ForegroundColor Green }
function Write-Step { param([string] $Message) Write-Host ""; Write-Host "==> $Message" -ForegroundColor Cyan }

Write-Host ""
Write-Host "============================================================"
Write-Host "  RT-AI Codex RTL Patch - Online Uninstaller"
Write-Host "  https://rt-ai.co.il"
Write-Host "============================================================"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rtl-rt-ai-uninst-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "source.zip"
$extractDir = Join-Path $tempRoot "extract"

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Path $extractDir | Out-Null

    if ($Branch -match '^v\d+\.') {
        $zipUrl = "https://codeload.github.com/$Repo/zip/refs/tags/$Branch"
    } else {
        $zipUrl = "https://codeload.github.com/$Repo/zip/refs/heads/$Branch"
    }
    Write-Step "Downloading $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Write-Ok "Downloaded."

    Write-Step "Extracting"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
    $sourceDir = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
    if (-not $sourceDir) { throw "Could not locate extracted source directory." }

    $patcher = Join-Path $sourceDir.FullName "patch.ps1"
    if (-not (Test-Path -LiteralPath $patcher)) {
        throw "patch.ps1 not found in the downloaded source."
    }

    Write-Step "Running uninstaller"
    # Spawn a child PowerShell with explicit -ExecutionPolicy Bypass so we
    # work even when the user's session policy is Restricted.
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = "powershell.exe" }
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $patcher -Uninstall
    if ($LASTEXITCODE -ne 0) {
        throw "Uninstaller exited with code $LASTEXITCODE."
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
