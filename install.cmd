@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

where python >nul 2>nul
if errorlevel 1 (
    echo ERROR: python not found. Install Python and ensure it is in PATH.
    exit /b 1
)

python "%SCRIPT_DIR%install.py" %*
