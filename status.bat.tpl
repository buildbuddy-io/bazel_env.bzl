@echo off
setlocal enabledelayedexpansion

rem Check argument count
set arg_count=0
for %%x in (%*) do set /a arg_count+=1

if !arg_count! neq 1 goto fail_with_usage

rem Set subcommand
if !arg_count! equ 1 (
    set "subcommand=%~1"
) else (
    set "subcommand=status"
)

set "direnv_bin_dir=%BUILD_WORKSPACE_DIRECTORY%\{{bin_dir}}"
set "direnv_bin_dir=!direnv_bin_dir:/=\!"

rem Handle print-path subcommand
if "!subcommand!"=="print-path" (
    echo !direnv_bin_dir!
    exit /b 0
)

rem Validate subcommand
if not "!subcommand!"=="status" goto fail_with_usage

rem Change to workspace directory
cd /d "%BUILD_WORKSPACE_DIRECTORY%"

echo.
echo ====== {{name}} ======
echo.

@================================================================================
rem Check if tools are available
if "{{has_tools}}"=="False" goto :has_toolchains

rem Check if direnv is installed
where direnv >nul 2>&1
set have_direnv=0
if !errorlevel! equ 0 (
    echo ✅ direnv is installed
    set have_direnv=1
) else (
    echo ⚠️ direnv is not installed. Not currently supported on Windows. Contributions welcome.
)

rem Check if unique tool is in PATH
where {{unique_name_tool}} >nul 2>&1
if !errorlevel! equ 0 (
    if !have_direnv! equ 1 (
        echo ✅ direnv added {{bin_dir}} to PATH
    ) else (
        echo ✅ found {{bin_dir}} on PATH
    )
) else (
    echo ❌ {{name}}'s bin directory is not in PATH. Please follow these steps:
    echo.
    
    set step_num=1
    
    rem Check if DIRENV_DIR is set
    if not defined DIRENV_DIR (
        echo !step_num!. Enable direnv's shell hook as described in https://direnv.net/docs/hook.html.
        set /a step_num+=1
    )
    
    rem Check if .envrc contains bazel_env
    findstr /r /c:"bazel_env" .envrc >nul 2>&1
    if !errorlevel! neq 0 (
        echo.
        if exist .envrc (
            echo !step_num!. Add the following content to your existing .envrc file:
        ) else (
            echo !step_num!. Create a .envrc file next to your MODULE.bazel file with this content:
        )
        echo.
        echo watch_file {{bin_dir}}
        echo PATH_add {{bin_dir}}
        echo if [[ ! -d {{bin_dir}} ]]; then
        echo   log_error "ERROR[bazel_env.bzl]: Run 'bazel run {{label}}' to regenerate {{bin_dir}}"
        echo fi
        set /a step_num+=1
    )
    
    echo !step_num!. Run 'direnv allow' to allowlist your .envrc file.

    set /a step_num+=1
    echo !step_num!. Or: set "PATH=!direnv_bin_dir!;%%PATH%%"
    exit /b 1
)

rem Clean up stale tools
set cleaned=0
for %%f in ("{{bin_dir}}\*") do (
    set "filename=%%~nxf"
    set "filename=!filename:.bat=!"
    set "filename=!filename:.runfiles_manifest=!"
    echo !filename! | findstr /v /r "{{tools_regex}}" >nul
    if !errorlevel! equ 0 (
        del /f /q "%%f" >nul 2>&1
        rmdir /s /q "%%f" >nul 2>&1
        set cleaned=1
    )
)

if !cleaned! equ 1 (
    echo ✅ Cleaned up stale tools
)

echo.
echo Tools available in PATH:
{{tools}}

@================================================================================
:has_toolchains
rem Check if toolchains are available
if "{{has_toolchains}}"=="True" (
    echo.
    echo Toolchains available at stable relative paths:
    {{toolchains}}
)

rem Get parent process info (simplified for Windows)
if !have_direnv! equ 1 (
    echo ⚠️ Remember to restart your command prompt or PowerShell session to update the locations of binaries on the PATH.
)

endlocal
exit /b 0

rem Function to display usage and exit
:fail_with_usage
echo Usage: bazel run {{label}} [status^|print-path] >&2
exit /b 1
