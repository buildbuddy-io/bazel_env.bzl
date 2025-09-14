@echo off
setlocal enabledelayedexpansion

if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
    echo WARNING: %%RUNFILES_MANIFEST_ONLY%% is not set; bazel issue? Forcing to 1
    set RUNFILES_MANIFEST_ONLY=1
)

{{batch_rlocation_function}}

REM Determine bin_path based on rlocation_path
call :rlocation {{rlocation_path}} bin_path
echo !bin_path!

call :_bazel__get_workspace_path
set BUILD_WORKSPACE_DIRECTORY=%workspace_path%

REM Get own path and directory
set "own_path=%~f0"
set "own_dir=%~dp0"
set "own_name=%~nx0"
set "own_name=%own_name:.bat=%"

REM Remove trailing backslash from own_dir if present
if "%own_dir:~-1%"=="\" set "own_dir=%own_dir:~0,-1%"

REM Check if tool is still valid
findstr /l /c:"%own_name%" "%own_dir%\_all_tools.txt" >nul
if errorlevel 1 (
    echo ERROR: %own_name% has been removed from bazel_env, run 'bazel run {{bazel_env_label}}' to remove it from PATH. >&2
    exit /b 1
)

REM Set up an environment similar to 'bazel run' to support tools designed to be
REM run with it.
REM Since tools may cd into BUILD_WORKSPACE_DIRECTORY, ensure that RUNFILES_DIR
REM is absolute.
set "RUNFILES_DIR=%own_path%.runfiles"
REM Also set legacy RUNFILES variables for compatibility with runfiles logic that
REM predates the runfiles library (e.g. in rules_js).
set "RUNFILES=%RUNFILES_DIR%"
set "JAVA_RUNFILES=%RUNFILES_DIR%"
set "PYTHON_RUNFILES=%RUNFILES_DIR%"
REM Let rules_js' js_binary work by not having it try to cd into BINDIR.
set "JS_BINARY__NO_CD_BINDIR=1"
REM Environment of the executable target.
{{extra_env}}

set "BUILD_WORKING_DIRECTORY=%CD%"

REM Execute the target binary with all arguments
exit /b %errorlevel%

:_bazel__get_workspace_path
set "workspace=%CD%"
:workspace_loop
if exist "%workspace%\WORKSPACE" goto :workspace_found
if exist "%workspace%\WORKSPACE.bazel" goto :workspace_found
if exist "%workspace%\MODULE.bazel" goto :workspace_found
if exist "%workspace%\REPO.bazel" goto :workspace_found

REM Get parent directory
for %%I in ("%workspace%") do set "parent=%%~dpI"
REM Remove trailing backslash
if "%parent:~-1%"=="\" set "parent=%parent:~0,-1%"

REM Check if we've reached the root or if parent is same as current (no more parents)
if "%parent%"=="" goto :workspace_not_found
if "%parent%"=="%workspace%" goto :workspace_not_found

set "workspace=%parent%"
goto :workspace_loop

:workspace_not_found
set "workspace=%CD%"

:workspace_found
set "workspace_path=%workspace%"
exit /b 0
