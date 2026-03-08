@echo off
setlocal enabledelayedexpansion

set "CLAUDE_DIR=%USERPROFILE%\.claude"
set "PROFILES_DIR=%CLAUDE_DIR%\profiles"
set "SETTINGS_FILE=%PROFILES_DIR%\settings.json"
set "DEFAULT_PROFILE=%PROFILES_DIR%\default"
set "SHIM_SOURCE=%~dp0claude-shim.sh"
set "CCTX_SOURCE=%~dp0cctx.py"
set "LOCAL_BIN=%USERPROFILE%\.local\bin"

echo === cctx install ===

:: Verify claude exists
set "REAL_CLAUDE="
for /f "delims=" %%c in ('where claude 2^>nul') do (
    if not defined REAL_CLAUDE set "REAL_CLAUDE=%%c"
)
if not defined REAL_CLAUDE (
    echo ERROR: 'claude' not found in PATH
    exit /b 1
)

:: Verify jq exists
where jq >nul 2>nul
if errorlevel 1 (
    echo ERROR: 'jq' is required but not found
    exit /b 1
)

:: Verify python exists
set "HAVE_PYTHON=0"
where python >nul 2>nul
if not errorlevel 1 set "HAVE_PYTHON=1"
where python3 >nul 2>nul
if not errorlevel 1 set "HAVE_PYTHON=1"
if "%HAVE_PYTHON%"=="0" (
    echo ERROR: 'python' is required but not found
    exit /b 1
)

:: 1. Create profiles directory
echo Creating profiles directory...
if not exist "%PROFILES_DIR%\" mkdir "%PROFILES_DIR%"

:: 2. Create profiles settings.json (if not exists)
if not exist "%SETTINGS_FILE%" (
    (echo {"managed_files":["CLAUDE.md","settings.json"]}) | jq . > "%SETTINGS_FILE%"
    echo   Created %SETTINGS_FILE%
) else (
    echo   %SETTINGS_FILE% already exists, skipping
)

:: 3. Create default profile by moving managed files
echo Creating default profile...
if not exist "%DEFAULT_PROFILE%\" mkdir "%DEFAULT_PROFILE%"

for /f "delims=" %%f in ('jq -r ".managed_files[]" "%SETTINGS_FILE%"') do call :process_managed_file "%%f"

:: 4. Install the claude shim
echo Installing claude shim...

:: TODO: https://github.com/hGriff0n/cctx/issues/1
:: Claude seems to have validation that forces "claude.exe" to exist
:: Specific error is "Install method is native but claude command not found"
:: In the meantime I'm just changing the shim to `cclaude`
@REM set "REAL_EXT="
@REM if /i "%REAL_CLAUDE:~-4%"==".exe" set "REAL_EXT=.exe"
@REM if /i "%REAL_CLAUDE:~-4%"==".cmd" set "REAL_EXT=.cmd"

@REM set "BACKUP=%LOCAL_BIN%\claude-real%REAL_EXT%"

@REM fsutil reparsepoint query "%REAL_CLAUDE%" >nul 2>nul
@REM if not errorlevel 1 (
@REM     echo   claude is already a symlink, removing
@REM     del /f "%REAL_CLAUDE%" >nul 2>nul
@REM ) else if exist "%REAL_CLAUDE%" (
@REM     if not exist "%BACKUP%" (
@REM         move "%REAL_CLAUDE%" "%BACKUP%" >nul
@REM         echo   Backed up claude -^> %BACKUP%
@REM     ) else (
@REM         echo   Backup already exists at %BACKUP%
@REM         del /f "%REAL_CLAUDE%" >nul 2>nul
@REM     )
@REM )

if not exist "%LOCAL_BIN%\" mkdir "%LOCAL_BIN%"
copy /y "%~dp0claude.cmd" "%LOCAL_BIN%\cclaude.cmd" >nul
echo   Installed claude.cmd

:: 5. Install cctx command
copy /y "%CCTX_SOURCE%" "%LOCAL_BIN%\cctx.py" >nul
copy /y "%~dp0cctx.cmd" "%LOCAL_BIN%\cctx.cmd" >nul
echo   Installed cctx.cmd + cctx.py

echo.
echo === Installation complete ===
echo   Shim (CMD):         %LOCAL_BIN%\claude.cmd
echo   Config manager:     %LOCAL_BIN%\cctx.cmd
echo   Default profile:    %DEFAULT_PROFILE%
echo.
echo Set a profile for a project:
echo   cd \path\to\project
echo   cctx create myprofile
echo   jq ".profile = \"myprofile\"" .claude\settings.local.json ^> tmp ^&^& move tmp .claude\settings.local.json
exit /b 0

:process_managed_file
set "file=%~1"
set "src=%CLAUDE_DIR%\%file%"
set "dst=%DEFAULT_PROFILE%\%file%"

if not exist "%src%" (
    echo   WARN: %src% does not exist, skipping
    exit /b 0
)

:: Check if already a symlink pointing into profiles
fsutil reparsepoint query "%src%" >nul 2>nul
if not errorlevel 1 (
    set "skip_file=0"
    for /f "delims=" %%t in ('powershell -NoProfile -Command "(Get-Item '%src%').Target" 2^>nul') do (
        echo %%t | findstr /i "profiles" >nul 2>nul
        if not errorlevel 1 set "skip_file=1"
    )
    if "!skip_file!"=="1" (
        echo   %file% already symlinked, skipping
        exit /b 0
    )
)

if not exist "%dst%" (
    copy /y "%src%" "%dst%" >nul
    echo   Copied %file% -^> default profile
)
del /f "%src%" >nul 2>nul
mklink "%src%" "%dst%" >nul
echo   Symlinked %src% -^> %dst%
exit /b 0
