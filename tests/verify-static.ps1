$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$patcherPath = Join-Path $repoRoot "patch.ps1"
$payloadPath = Join-Path $repoRoot "codex-rtl-payload.js"
$readmePath = Join-Path $repoRoot "README.md"
$installBat = Join-Path $repoRoot "install.bat"
$uninstallBat = Join-Path $repoRoot "uninstall.bat"

Assert-True (Test-Path -LiteralPath $patcherPath) "patch.ps1 is missing"
Assert-True (Test-Path -LiteralPath $payloadPath) "codex-rtl-payload.js is missing"
Assert-True (Test-Path -LiteralPath $readmePath) "README.md is missing"
Assert-True (Test-Path -LiteralPath $installBat) "install.bat is missing"
Assert-True (Test-Path -LiteralPath $uninstallBat) "uninstall.bat is missing"

$patcher = Get-Content -LiteralPath $patcherPath -Raw
$payload = Get-Content -LiteralPath $payloadPath -Raw
$readme = Get-Content -LiteralPath $readmePath -Raw
$install = Get-Content -LiteralPath $installBat -Raw

Assert-True ($patcher.Contains("OpenAI.Codex_*")) "patcher should discover the WindowsApps Codex package"
Assert-True ($patcher.Contains("Codex-RT-AI")) "patcher should create a separate Codex-RT-AI copy"
Assert-True ($patcher.Contains("npx.cmd")) "patcher should use npx.cmd to avoid PowerShell execution policy issues"
Assert-True ($patcher.Contains("@electron/asar")) "patcher should use @electron/asar"
Assert-True ($patcher.Contains("@electron/fuses")) "patcher should use @electron/fuses"
Assert-True ($patcher.Contains("EnableEmbeddedAsarIntegrityValidation=off")) "patcher should disable ASAR integrity validation on the copied exe"
Assert-True ($patcher.Contains("webview\assets\index-*.js")) "patcher should target the Codex webview entry bundle"
Assert-True ($patcher.Contains("Start-Process")) "patcher should be able to launch the patched copy"
Assert-True ($patcher.Contains("RT-AI")) "patcher should be branded as RT-AI"
Assert-True (-not $patcher.Contains("shraga100")) "patcher should not reference the previous author"
Assert-True ($patcher.Contains('$Script:ShortcutName = "Codex.lnk"')) "shortcut should be named just Codex.lnk (no RT-AI suffix)"
Assert-True ($patcher.Contains("Get-StartMenuShortcutPath")) "patcher should also create a Start Menu shortcut"
Assert-True ($patcher.Contains("Remove-LegacyShortcuts")) "patcher should remove legacy shortcuts on install"
Assert-True ($patcher.Contains("Remove-LegacyPatchedDirs")) "patcher should clean up legacy patched dirs"
Assert-True ($patcher.Contains('Get-AppxPackage -Name "OpenAI.Codex"')) "patcher should use Get-AppxPackage as the primary source lookup (works without admin)"
Assert-True ($patcher.Contains("Test-IsPatchedCopy")) "patcher should detect and skip our own patched copies as source candidates"
Assert-True ($patcher.Contains("MaxAttempts")) "Remove-DirectorySafe should retry on file-lock failures"

Assert-True ($payload.Contains("RT-AI CODEX RTL PATCH START")) "payload marker is missing"
Assert-True ($payload.Contains("__RT_AI_CODEX_RTL_PATCH__")) "payload should be idempotent and RT-AI branded"
Assert-True ($payload.Contains(".ProseMirror")) "payload should handle Codex composer ProseMirror input"
Assert-True ($payload.Contains("MutationObserver")) "payload should process streamed response changes"
Assert-True ($payload.Contains("unicode-bidi")) "payload should set bidi-safe styles"
Assert-True ($payload.Contains("RT-AI CODEX RTL PATCH END")) "payload end marker is missing"
Assert-True (-not $payload.Contains("shraga100")) "payload should not reference the previous author"

Assert-True ($readme.Contains("RT-AI")) "README should be branded as RT-AI"
Assert-True ($readme.Contains("PowerShell")) "README should include PowerShell usage"
Assert-True ($readme.Contains("WindowsApps")) "README should explain why the original package is not modified"
Assert-True ($readme.Contains("install.bat")) "README should mention the one-click installer"

Assert-True ($install.Contains("ExecutionPolicy Bypass")) "install.bat should bypass execution policy"
Assert-True ($install.Contains("patch.ps1")) "install.bat should call patch.ps1"
Assert-True ($install.Contains("%~dp0")) "install.bat must cd to its own directory to avoid the system32 cwd bug"

Write-Host "RT-AI static verification passed." -ForegroundColor Green
