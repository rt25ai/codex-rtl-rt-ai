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

Assert-True ($patcher.Contains("OpenAI.Codex_*")) "patcher should discover the WindowsApps package (the unified ChatGPT app kept the OpenAI.Codex identity)"
Assert-True ($patcher.Contains("ChatGPT-RT-AI")) "patcher should create a separate ChatGPT-RT-AI copy"
Assert-True ($patcher.Contains('"ChatGPT.exe", "Codex.exe"')) "patcher should prefer ChatGPT.exe and fall back to Codex.exe"
Assert-True ($patcher.Contains("npx.cmd")) "patcher should use npx.cmd to avoid PowerShell execution policy issues"
Assert-True ($patcher.Contains("@electron/asar")) "patcher should use @electron/asar"
Assert-True ($patcher.Contains("@electron/fuses")) "patcher should use @electron/fuses"
Assert-True ($patcher.Contains("EnableEmbeddedAsarIntegrityValidation=off")) "patcher should best-effort disable ASAR integrity validation on the copied exe"
Assert-True ($patcher.Contains("webview\assets\index-*.js")) "patcher should target the webview entry bundle"
Assert-True ($patcher.Contains("Start-Process")) "patcher should be able to launch the patched copy"
Assert-True ($patcher.Contains("RT-AI")) "patcher should be branded as RT-AI"
Assert-True (-not $patcher.Contains("shraga100")) "patcher should not reference the previous author"
Assert-True ($patcher.Contains('$Script:ShortcutName = "ChatGPT.lnk"')) "shortcut should be named just ChatGPT.lnk (no RT-AI suffix)"
Assert-True ($patcher.Contains('"Codex.lnk"')) "patcher should clean up the legacy Codex.lnk shortcut"
Assert-True ($patcher.Contains('"Codex-RT-AI"')) "patcher should clean up the legacy Codex-RT-AI patched dir"
Assert-True ($patcher.Contains("Codex RT-AI RTL Auto-Update")) "patcher should unregister the legacy auto-update task"
Assert-True ($patcher.Contains('PackageDisplayName"]="ChatGPT"')) "auto-update event trigger should match the ChatGPT display name"
Assert-True ($patcher.Contains("rt-ai-chatgpt-rtl-patch.json")) "patcher should write the rt-ai-chatgpt-rtl-patch.json marker"
Assert-True ($patcher.Contains("rt-ai-codex-rtl-patch.json")) "patcher should still recognize the legacy marker for migration"
Assert-True ($patcher.Contains("Get-StartMenuShortcutPath")) "patcher should also create a Start Menu shortcut"
Assert-True ($patcher.Contains("Remove-LegacyShortcuts")) "patcher should remove legacy shortcuts on install"
Assert-True ($patcher.Contains("Remove-LegacyPatchedDirs")) "patcher should clean up legacy patched dirs"
Assert-True ($patcher.Contains('Get-AppxPackage -Name "OpenAI.Codex"')) "patcher should use Get-AppxPackage as the primary source lookup (works without admin)"
Assert-True ($patcher.Contains("Test-IsPatchedCopy")) "patcher should detect and skip our own patched copies as source candidates"
Assert-True ($patcher.Contains("MaxAttempts")) "Remove-DirectorySafe should retry on file-lock failures"

Assert-True ($payload.Contains("RT-AI CODEX RTL PATCH START")) "payload marker is missing (kept CODEX name for idempotent re-patching)"
Assert-True ($payload.Contains("__RT_AI_CODEX_RTL_PATCH__")) "payload should be idempotent"
Assert-True ($payload.Contains(".ProseMirror")) "payload should handle the composer ProseMirror input"
Assert-True ($payload.Contains("MutationObserver")) "payload should process streamed response changes"
Assert-True ($payload.Contains("unicode-bidi")) "payload should set bidi-safe styles"
Assert-True ($payload.Contains("RT-AI CODEX RTL PATCH END")) "payload end marker is missing"
Assert-True (-not $payload.Contains("shraga100")) "payload should not reference the previous author"

Assert-True ($readme.Contains("RT-AI")) "README should be branded as RT-AI"
Assert-True ($readme.Contains("ChatGPT")) "README should describe the unified ChatGPT app"
Assert-True ($readme.Contains("PowerShell")) "README should include PowerShell usage"
Assert-True ($readme.Contains("WindowsApps")) "README should explain why the original package is not modified"
Assert-True ($readme.Contains("install.bat")) "README should mention the one-click installer"

Assert-True ($install.Contains("ExecutionPolicy Bypass")) "install.bat should bypass execution policy"
Assert-True ($install.Contains("patch.ps1")) "install.bat should call patch.ps1"
Assert-True ($install.Contains("%~dp0")) "install.bat must cd to its own directory to avoid the system32 cwd bug"

# Release pins: the published one-liners must all point at the same tag.
$pinFiles = @(
    (Join-Path $repoRoot "install-online.ps1"),
    (Join-Path $repoRoot "uninstall-online.ps1"),
    (Join-Path $repoRoot "install-online.sh"),
    (Join-Path $repoRoot "uninstall-online.sh")
)
$pins = @()
foreach ($pinFile in $pinFiles) {
    $content = Get-Content -LiteralPath $pinFile -Raw
    if ($content -match '\$Branch = "(v[\d.]+)"') { $pins += $Matches[1] }
    if ($content -match 'BRANCH="\$\{RT_AI_CODEX_BRANCH:-(v[\d.]+)\}"') { $pins += $Matches[1] }
}
Assert-True ($pins.Count -eq 4) "all four online scripts should carry a release pin (found $($pins.Count))"
Assert-True (($pins | Select-Object -Unique).Count -eq 1) "all release pins must match (found: $($pins -join ', '))"
Assert-True ($readme.Contains(($pins | Select-Object -First 1))) "README install commands should use the pinned release tag $($pins | Select-Object -First 1)"

# macOS scripts
$macPatcher = Join-Path $repoRoot "patch.sh"
$macInstall = Join-Path $repoRoot "install-online.sh"
$macUninstall = Join-Path $repoRoot "uninstall-online.sh"
Assert-True (Test-Path -LiteralPath $macPatcher) "patch.sh (macOS) is missing"
Assert-True (Test-Path -LiteralPath $macInstall) "install-online.sh (macOS) is missing"
Assert-True (Test-Path -LiteralPath $macUninstall) "uninstall-online.sh (macOS) is missing"

$macP = Get-Content -LiteralPath $macPatcher -Raw
Assert-True ($macP.Contains("ChatGPT-RT-AI.app")) "macOS patcher should target ChatGPT-RT-AI.app"
Assert-True ($macP.Contains("/Applications/ChatGPT.app")) "macOS patcher should detect the unified /Applications/ChatGPT.app"
Assert-True ($macP.Contains("/Applications/Codex.app")) "macOS patcher should fall back to the legacy Codex.app"
Assert-True ($macP.Contains("Codex-RT-AI.app")) "macOS patcher should migrate away the legacy Codex-RT-AI.app copy"
Assert-True ($macP.Contains("app.asar")) "macOS patcher should validate the Electron app by its app.asar (excludes ChatGPT Classic)"
Assert-True ($macP.Contains("codex-rtl-payload.js")) "macOS patcher should reference the shared payload"
Assert-True ($macP.Contains("EnableEmbeddedAsarIntegrityValidation=off")) "macOS patcher should best-effort disable the ASAR fuse"
Assert-True ($macP.Contains("codesign --force --deep --sign -")) "macOS patcher should re-sign ad-hoc"
Assert-True ($macP.Contains("RT-AI CODEX RTL PATCH START")) "macOS patcher should detect the RT-AI payload marker"
Assert-True ($macP.Contains("co.il.rt-ai.chatgpt-rtl.autoupdate")) "macOS patcher should register the chatgpt-rtl launchd agent"
Assert-True ($macP.Contains("co.il.rt-ai.codex-rtl.autoupdate")) "macOS patcher should unload the legacy codex-rtl launchd agent"
Assert-True (-not $macP.Contains("Claude")) "macOS patcher should have no leftover Claude references"

# The Windows fuse step must never hard-fail: OWL builds have no fuse sentinel.
Assert-True ($patcher.Contains('*> $null')) "fuse write must discard all streams so a missing sentinel cannot abort the install"

Write-Host "RT-AI static verification passed." -ForegroundColor Green
