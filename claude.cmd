@echo off
setlocal

set "SHIM_DIR=%~dp0"

where bash >nul 2>nul
if errorlevel 1 (
    echo ERROR: bash not found. Install Git for Windows and ensure it is in PATH.
    exit /b 1
)

bash "%SHIM_DIR%claude-shim.sh" %*
