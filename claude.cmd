@echo off
setlocal enabledelayedexpansion

set "CLAUDE_DIR=%USERPROFILE%\.claude"
set "PROFILES_DIR=%CLAUDE_DIR%\profiles"
set "SETTINGS_FILE=%PROFILES_DIR%\settings.json"

:: TODO: https://github.com/hGriff0n/cctx/issues/1
set "REAL_CLAUDE=%USERPROFILE%\.local\bin\claude.exe"

if not exist "%REAL_CLAUDE%" (
    set "REAL_CLAUDE=%USERPROFILE%\.local\bin\claude.cmd"
    if not exist "!REAL_CLAUDE!" (
        echo ERROR: Real claude binary not found at %USERPROFILE%\.local\bin\claude-real 1>&2
        exit /b 1
    )
)

:: Determine which profile to load
set "profile=default"
set "local_settings=%cd%\.claude\settings.local.json"

if exist "%local_settings%" (
    where jq >nul 2>nul
    if not errorlevel 1 (
        for /f "delims=" %%p in ('jq -r ".profile // empty" "%local_settings%" 2^>nul') do (
            if not "%%p"=="" set "profile=%%p"
        )
    )
)

set "profile_dir=%PROFILES_DIR%\%profile%"
if not exist "%profile_dir%\" (
    echo ERROR: Profile '%profile%' not found at %profile_dir% 1>&2
    echo Available profiles: 1>&2
    for /d %%d in ("%PROFILES_DIR%\*") do (
        if not "%%~nxd"=="settings.json" echo %%~nxd 1>&2
    )
    exit /b 1
)

:: Load profile by updating symlinks
call cctx set "%profile%"

:: Transfer to real claude
"%REAL_CLAUDE%" %*