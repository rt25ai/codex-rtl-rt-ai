@echo off
REM ============================================================================
REM RT-AI ChatGPT RTL Patch - One-click installer for Windows
REM https://rt-ai.co.il
REM ============================================================================
REM Double-click this file to install. No PowerShell or admin needed.
REM Targets the unified ChatGPT desktop app ("Powered by Codex & OWL").
REM Patched copy goes to %LOCALAPPDATA%\Programs\ChatGPT-RT-AI.
REM A "ChatGPT" shortcut is created on Desktop and in Start Menu.
REM The original app (under WindowsApps) is NOT modified.
REM ============================================================================

setlocal
cd /d "%~dp0"

echo.
echo ============================================================
echo   RT-AI ChatGPT RTL Patch - Installer
echo   https://rt-ai.co.il
echo ============================================================
echo.

where node.exe >nul 2>&1
if errorlevel 1 (
    echo [!] Node.js is not installed.
    echo     Install it from https://nodejs.org/ and run this again.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" -Install %*
set EXITCODE=%ERRORLEVEL%

echo.
if %EXITCODE% NEQ 0 (
    echo [X] Install failed with exit code %EXITCODE%.
) else (
    echo [+] Done. Click "ChatGPT" on your Desktop or in Start Menu.
)

echo.
pause
exit /b %EXITCODE%
