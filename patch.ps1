<#
RT-AI Codex Desktop RTL Patcher for Windows.

Creates a patched copy of the installed Codex Electron app, injects
the RT-AI RTL payload into the webview bundle, and disables ASAR integrity
validation on the copied executable.

Part of the RT-AI tooling suite (https://rt-ai.co.il).
#>

[CmdletBinding()]
param(
    [switch] $Install,
    [switch] $Uninstall,
    [switch] $Status,
    [switch] $Launch,
    [switch] $NoLaunch,
    [string] $SourceAppDir,
    [string] $PatchedAppDir = (Join-Path $env:LOCALAPPDATA "Programs\Codex-RT-AI")
)

$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:PayloadPath = Join-Path $Script:RepoRoot "codex-rtl-payload.js"
$Script:ShortcutName = "Codex.lnk"
$Script:LegacyShortcutNames = @("Codex RT-AI.lnk", "Codex RTL.lnk")
$Script:LegacyPatchedDirs = @("Codex-RTL")

function Write-Step {
    param([string] $Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string] $Message)
    Write-Host "  [*] $Message"
}

function Write-Ok {
    param([string] $Message)
    Write-Host "  [+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string] $Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Resolve-FullPath {
    param([string] $Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-DirectorySafeToRemove {
    param([string] $Path)

    $full = Resolve-FullPath $Path
    $root = [System.IO.Path]::GetPathRoot($full)
    $blocked = @(
        $root,
        (Resolve-FullPath $env:USERPROFILE),
        (Resolve-FullPath $env:LOCALAPPDATA),
        (Resolve-FullPath (Join-Path $env:LOCALAPPDATA "Programs")),
        (Resolve-FullPath $env:ProgramFiles)
    ) | Where-Object { $_ }

    foreach ($blockedPath in $blocked) {
        if ($full.TrimEnd("\") -ieq $blockedPath.TrimEnd("\")) {
            throw "Refusing to remove unsafe path: $full"
        }
    }

    if ($full -match "\\WindowsApps(\\|$)") {
        throw "Refusing to remove anything under WindowsApps: $full"
    }
}

function Remove-DirectorySafe {
    param(
        [string] $Path,
        [int] $MaxAttempts = 6,
        [int] $DelayMs = 750
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Assert-DirectorySafeToRemove $Path

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts) {
                Write-Info "Delete blocked (attempt $attempt/$MaxAttempts) - waiting for file handles to release..."
                Start-Sleep -Milliseconds $DelayMs
            }
        }
    }

    # Final fallback: rename out of the way so the install can proceed, even if some files
    # are still locked by the OS. Windows will clean up the renamed folder on next reboot.
    try {
        $parent = Split-Path -Parent $Path
        $leaf = Split-Path -Leaf $Path
        $stamp = (Get-Date).ToString("yyyyMMddHHmmssfff")
        $stale = Join-Path $parent (".$leaf.stale-$stamp")
        Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $stale) -ErrorAction Stop
        Write-Warn "Could not fully delete $Path; renamed to $stale and continuing."
        return
    } catch {
        throw "Failed to remove $Path after $MaxAttempts attempts and could not rename it. Original error: $($lastError.Exception.Message)"
    }
}

function Get-ToolPath {
    param([string[]] $Names)

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            return $cmd.Source
        }
        if ($cmd -and $cmd.Path) {
            return $cmd.Path
        }
    }

    return $null
}

function Invoke-Checked {
    param(
        [string] $FilePath,
        [string[]] $Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Test-CodexAppDir {
    param([string] $AppDir)

    return (Test-Path -LiteralPath (Join-Path $AppDir "Codex.exe")) -and
        (Test-Path -LiteralPath (Join-Path $AppDir "resources\app.asar"))
}

function Get-CodexPackageVersion {
    param([string] $AppDir)

    $packageDir = Split-Path -Parent $AppDir
    $packageName = Split-Path -Leaf $packageDir
    if ($packageName -match "^OpenAI\.Codex_([^_]+)_") {
        try {
            return [version] $Matches[1]
        } catch {
            return [version] "0.0.0.0"
        }
    }

    return [version] "0.0.0.0"
}

function Test-IsPatchedCopy {
    param([string] $AppDir)

    $markers = @(
        Join-Path $AppDir "resources\rt-ai-codex-rtl-patch.json",
        Join-Path $AppDir "resources\codex-rtl-patch.json"
    )
    foreach ($m in $markers) {
        if (Test-Path -LiteralPath $m) { return $true }
    }
    return $false
}

function Find-CodexAppDir {
    param([string] $ExplicitSourceAppDir)

    if ($ExplicitSourceAppDir) {
        $explicit = Resolve-FullPath $ExplicitSourceAppDir
        if (-not (Test-CodexAppDir $explicit)) {
            throw "SourceAppDir is not a Codex app directory: $explicit"
        }
        return $explicit
    }

    # Primary: use Get-AppxPackage which works without admin and finds the MSIX install reliably.
    try {
        $package = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($package -and $package.InstallLocation) {
            $appDir = Join-Path $package.InstallLocation "app"
            if (Test-CodexAppDir $appDir) {
                return (Resolve-FullPath $appDir)
            }
            if (Test-CodexAppDir $package.InstallLocation) {
                return (Resolve-FullPath $package.InstallLocation)
            }
        }
    } catch {
        Write-Warn "Get-AppxPackage lookup failed: $($_.Exception.Message)"
    }

    # Fallback: enumerate WindowsApps (requires admin to list, usually fails for normal users).
    $candidates = New-Object System.Collections.Generic.List[string]

    $windowsAppsDir = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $windowsAppsDir) {
        try {
            Get-ChildItem -LiteralPath $windowsAppsDir -Directory -Filter "OpenAI.Codex_*" -ErrorAction Stop |
                ForEach-Object {
                    $appDir = Join-Path $_.FullName "app"
                    if (Test-CodexAppDir $appDir) {
                        $candidates.Add((Resolve-FullPath $appDir))
                    }
                }
        } catch {
            # Silently fall through to LocalAppData; this typically fails without admin.
        }
    }

    # Last resort: LocalAppData\Programs, but skip ANY directory we recognize as a patched copy.
    $localPrograms = Join-Path $env:LOCALAPPDATA "Programs"
    if (Test-Path -LiteralPath $localPrograms) {
        $excludedNames = @($Script:LegacyPatchedDirs + "Codex-RT-AI")
        Get-ChildItem -LiteralPath $localPrograms -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match "Codex|OpenAI" -and
                $excludedNames -notcontains $_.Name -and
                -not (Test-IsPatchedCopy $_.FullName)
            } |
            ForEach-Object {
                if (Test-CodexAppDir $_.FullName) {
                    $candidates.Add((Resolve-FullPath $_.FullName))
                }
            }
    }

    $unique = $candidates | Select-Object -Unique
    $best = $unique |
        Sort-Object `
            @{ Expression = { Get-CodexPackageVersion $_ }; Descending = $true },
            @{ Expression = { (Get-Item -LiteralPath $_).LastWriteTimeUtc }; Descending = $true } |
        Select-Object -First 1

    if (-not $best) {
        throw "Could not find a Codex Desktop installation. Install Codex from Microsoft Store first, or pass -SourceAppDir explicitly."
    }

    return $best
}

function Stop-PatchedCodex {
    param([string] $AppDir)

    if (-not (Test-Path -LiteralPath $AppDir)) {
        return
    }

    $full = (Resolve-FullPath $AppDir).TrimEnd("\") + "\"
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($full, [System.StringComparison]::OrdinalIgnoreCase)
        }

    $stopped = 0
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped += 1
    }

    if ($stopped -gt 0) {
        Write-Info "Stopped $stopped patched Codex process(es); waiting for handles to release..."
        Start-Sleep -Milliseconds 1500
    }
}

function Get-DesktopShortcutPath {
    $desktop = [Environment]::GetFolderPath("Desktop")
    return Join-Path $desktop $Script:ShortcutName
}

function Get-StartMenuShortcutPath {
    $programs = [Environment]::GetFolderPath("Programs")
    return Join-Path $programs $Script:ShortcutName
}

function Get-LegacyShortcutPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $desktop = [Environment]::GetFolderPath("Desktop")
    $programs = [Environment]::GetFolderPath("Programs")
    foreach ($name in $Script:LegacyShortcutNames) {
        $paths.Add((Join-Path $desktop $name))
        $paths.Add((Join-Path $programs $name))
    }
    return $paths
}

function New-PatchedShortcutFile {
    param(
        [string] $ShortcutPath,
        [string] $TargetExe,
        [string] $WorkingDir
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetExe
    $shortcut.WorkingDirectory = $WorkingDir
    $shortcut.IconLocation = "$TargetExe,0"
    $shortcut.Description = "Codex Desktop with RTL patch (Hebrew/Arabic alignment) - by RT-AI"
    $shortcut.Save()
}

function New-PatchedShortcut {
    param([string] $AppDir)

    $exe = Join-Path $AppDir "Codex.exe"

    $desktopPath = Get-DesktopShortcutPath
    New-PatchedShortcutFile -ShortcutPath $desktopPath -TargetExe $exe -WorkingDir $AppDir
    Write-Ok "Created desktop shortcut: $desktopPath"

    $startMenuPath = Get-StartMenuShortcutPath
    New-PatchedShortcutFile -ShortcutPath $startMenuPath -TargetExe $exe -WorkingDir $AppDir
    Write-Ok "Created Start Menu shortcut: $startMenuPath"
}

function Remove-PatchedShortcut {
    $targets = @((Get-DesktopShortcutPath), (Get-StartMenuShortcutPath)) + (Get-LegacyShortcutPaths)
    foreach ($shortcutPath in $targets) {
        if (Test-Path -LiteralPath $shortcutPath) {
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
            Write-Ok "Removed shortcut: $shortcutPath"
        }
    }
}

function Remove-LegacyShortcuts {
    foreach ($shortcutPath in (Get-LegacyShortcutPaths)) {
        if (Test-Path -LiteralPath $shortcutPath) {
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
            Write-Info "Removed legacy shortcut: $shortcutPath"
        }
    }
}

function Remove-LegacyPatchedDirs {
    $programsDir = Join-Path $env:LOCALAPPDATA "Programs"
    foreach ($name in $Script:LegacyPatchedDirs) {
        $legacyDir = Join-Path $programsDir $name
        if (Test-Path -LiteralPath $legacyDir) {
            Write-Info "Removing legacy patched copy: $legacyDir"
            Stop-PatchedCodex $legacyDir
            try {
                Remove-DirectorySafe $legacyDir
                Write-Ok "Removed: $legacyDir"
            } catch {
                Write-Warn "Could not remove $legacyDir : $($_.Exception.Message)"
            }
        }
    }
}

function Patch-Asar {
    param(
        [string] $AppDir,
        [string] $NpxPath
    )

    if (-not (Test-Path -LiteralPath $Script:PayloadPath)) {
        throw "Missing payload: $Script:PayloadPath"
    }

    $asarPath = Join-Path $AppDir "resources\app.asar"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rt-ai-" + [guid]::NewGuid().ToString("N"))
    $extractDir = Join-Path $tempRoot "app"
    $newAsar = Join-Path $tempRoot "app.asar"

    try {
        New-Item -ItemType Directory -Path $tempRoot | Out-Null

        Write-Step "Extracting app.asar"
        Invoke-Checked $NpxPath @("--yes", "@electron/asar", "extract", $asarPath, $extractDir)

        Write-Step "Injecting RT-AI RTL payload"
        $targetGlobs = @(
            "webview\assets\index-*.js",
            "webview\assets\app-main-*.js",
            "webview\assets\composer-*.js"
        )
        $targets = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        foreach ($glob in $targetGlobs) {
            Get-ChildItem -Path (Join-Path $extractDir $glob) -File -ErrorAction SilentlyContinue |
                ForEach-Object { $targets.Add($_) }
        }

        $uniqueTargets = $targets | Sort-Object FullName -Unique
        if (-not $uniqueTargets -or $uniqueTargets.Count -eq 0) {
            throw "No Codex webview JS bundles found. The app structure may have changed."
        }

        $payload = Get-Content -LiteralPath $Script:PayloadPath -Raw
        $injected = 0
        $skipped = 0
        foreach ($target in $uniqueTargets) {
            $text = Get-Content -LiteralPath $target.FullName -Raw
            if ($text.Contains("RT-AI CODEX RTL PATCH START")) {
                $skipped += 1
                continue
            }

            Set-Content -LiteralPath $target.FullName -Value ($payload + [Environment]::NewLine + $text) -NoNewline -Encoding UTF8
            $injected += 1
            Write-Info "Injected into $($target.Name)"
        }

        if ($injected -eq 0 -and $skipped -eq 0) {
            throw "No files were injected."
        }
        if ($injected -gt 0) {
            Write-Ok "Injected RT-AI RTL payload into $injected file(s)."
        }
        if ($skipped -gt 0) {
            Write-Info "Skipped $skipped already-patched file(s)."
        }

        Write-Step "Repacking app.asar"
        Invoke-Checked $NpxPath @("--yes", "@electron/asar", "pack", $extractDir, $newAsar)
        Copy-Item -LiteralPath $newAsar -Destination $asarPath -Force
        Write-Ok "Repacked app.asar"
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Disable-AsarIntegrityFuse {
    param(
        [string] $AppDir,
        [string] $NpxPath
    )

    $exe = Join-Path $AppDir "Codex.exe"
    Write-Step "Disabling ASAR integrity validation on copied exe"
    Invoke-Checked $NpxPath @(
        "--yes",
        "@electron/fuses",
        "write",
        "--app",
        $exe,
        "EnableEmbeddedAsarIntegrityValidation=off"
    )
    Write-Ok "ASAR integrity fuse disabled on the patched copy."
}

function Write-PatchMarker {
    param(
        [string] $AppDir,
        [string] $SourceDir
    )

    $marker = [ordered]@{
        name = "rt-ai-codex-rtl-patch"
        publisher = "RT-AI"
        site = "https://rt-ai.co.il"
        sourceAppDir = $SourceDir
        installedAt = (Get-Date).ToString("o")
    }
    $markerPath = Join-Path $AppDir "resources\rt-ai-codex-rtl-patch.json"
    $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
}

function Install-Patch {
    $npx = Get-ToolPath @("npx.cmd")
    if (-not $npx) {
        throw "npx.cmd not found. Install Node.js from https://nodejs.org/ and reopen PowerShell."
    }

    $source = Find-CodexAppDir $SourceAppDir
    $destination = Resolve-FullPath $PatchedAppDir

    Write-Step "Preparing Codex RT-AI copy"
    Write-Info "Source: $source"
    Write-Info "Target: $destination"

    Stop-PatchedCodex $destination
    Remove-DirectorySafe $destination
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null

    Write-Step "Copying Codex app"
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    Write-Ok "Copied app to $destination"

    Patch-Asar $destination $npx
    Disable-AsarIntegrityFuse $destination $npx
    Write-PatchMarker $destination $source
    Remove-LegacyShortcuts
    Remove-LegacyPatchedDirs
    New-PatchedShortcut $destination

    if (-not $NoLaunch) {
        Start-PatchedCodex $destination
    } else {
        Write-Info "Skipping launch because -NoLaunch was specified."
    }

    Write-Host ""
    Write-Ok "RT-AI Codex RTL patch installed."
}

function Uninstall-Patch {
    $destination = Resolve-FullPath $PatchedAppDir
    Stop-PatchedCodex $destination
    Remove-DirectorySafe $destination
    Remove-PatchedShortcut
    Remove-LegacyPatchedDirs
    Write-Ok "RT-AI Codex RTL patch removed."
}

function Start-PatchedCodex {
    param([string] $AppDir)

    $exe = Join-Path $AppDir "Codex.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Patched Codex.exe not found at $exe. Run .\patch.ps1 -Install first."
    }

    Write-Step "Launching Codex RT-AI"
    Start-Process -FilePath $exe -WorkingDirectory $AppDir
    Write-Ok "Launched patched Codex."
}

function Show-Status {
    $destination = Resolve-FullPath $PatchedAppDir
    $npx = Get-ToolPath @("npx.cmd")

    Write-Host ""
    Write-Host "RT-AI Codex RTL Patch - Status" -ForegroundColor Cyan
    Write-Host ""

    try {
        $source = Find-CodexAppDir $SourceAppDir
        Write-Ok "Source Codex app: $source"
        Write-Info "Source package version: $(Get-CodexPackageVersion $source)"
    } catch {
        Write-Warn $_.Exception.Message
    }

    if (Test-Path -LiteralPath $destination) {
        Write-Ok "Patched copy: $destination"
        $marker = Join-Path $destination "resources\rt-ai-codex-rtl-patch.json"
        if (Test-Path -LiteralPath $marker) {
            Write-Ok "Patch marker found."
        } else {
            Write-Warn "Patch marker missing; this directory may not be managed by this patcher."
        }

        $exe = Join-Path $destination "Codex.exe"
        if ($npx -and (Test-Path -LiteralPath $exe)) {
            Write-Info "Electron fuse status:"
            & $npx --yes "@electron/fuses" read --app $exe
        }
    } else {
        Write-Info "Patched copy is not installed at $destination"
    }

    $desktopShortcut = Get-DesktopShortcutPath
    if (Test-Path -LiteralPath $desktopShortcut) {
        Write-Ok "Desktop shortcut: $desktopShortcut"
    } else {
        Write-Info "Desktop shortcut is not installed."
    }

    $startMenuShortcut = Get-StartMenuShortcutPath
    if (Test-Path -LiteralPath $startMenuShortcut) {
        Write-Ok "Start Menu shortcut: $startMenuShortcut"
    } else {
        Write-Info "Start Menu shortcut is not installed."
    }
}

$selectedActions = @()
if ($Install) { $selectedActions += "Install" }
if ($Uninstall) { $selectedActions += "Uninstall" }
if ($Status) { $selectedActions += "Status" }
if ($Launch) { $selectedActions += "Launch" }

if ($selectedActions.Count -eq 0) {
    $Install = $true
    $selectedActions = @("Install")
}

if ($selectedActions.Count -gt 1) {
    throw "Choose only one action: -Install, -Uninstall, -Status, or -Launch."
}

if ($Install) {
    Install-Patch
} elseif ($Uninstall) {
    Uninstall-Patch
} elseif ($Status) {
    Show-Status
} elseif ($Launch) {
    Start-PatchedCodex (Resolve-FullPath $PatchedAppDir)
}
