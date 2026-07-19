@echo off
REM ============================================================================
REM RT-AI ChatGPT RTL Patch - One-click uninstaller for Windows
REM ============================================================================

setlocal
cd /d "%~dp0"

echo.
echo ============================================================
echo   RT-AI ChatGPT RTL Patch - Uninstaller
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" -Uninstall
set EXITCODE=%ERRORLEVEL%

echo.
pause
exit /b %EXITCODE%
