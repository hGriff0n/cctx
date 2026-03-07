@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

where bash >nul 2>nul
if errorlevel 1 (
    echo ERROR: bash not found. Install Git for Windows and ensure it is in PATH.
    exit /b 1
)

bash "%SCRIPT_DIR%cctx.sh" %*
