@echo off
setlocal enabledelayedexpansion

if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
    @rem echo WARNING: %%RUNFILES_MANIFEST_ONLY%% is not set; bazel issue? Forcing to 1
    set RUNFILES_MANIFEST_ONLY=1
)

rem MODIFIED VERSION OF RLOCATION THAT LOOKS FOR RUNFILE ALSO WITH .EXE EXTENSION
rem Usage of rlocation function:
rem        call :rlocation <runfile_path> <abs_path>
rem        The rlocation function maps the given <runfile_path> to its absolute
rem        path and stores the result in a variable named <abs_path>.
rem        This function fails if the <runfile_path> doesn't exist in mainifest
rem        file.
:: Start of rlocation
goto :rlocation_end
:rlocation
if "%~2" equ "" (
  echo>&2 ERROR: Expected two arguments for rlocation function.
  exit 1
)
if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
  set %~2=%~1
  exit /b 0
)
if exist "%RUNFILES_DIR%" (
  set RUNFILES_MANIFEST_FILE=%RUNFILES_DIR%_manifest
)
if "%RUNFILES_MANIFEST_FILE%" equ "" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles\MANIFEST
)
if not exist "%RUNFILES_MANIFEST_FILE%" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest
)
set MF=%RUNFILES_MANIFEST_FILE:/=\%
if not exist "%MF%" (
  echo>&2 ERROR: Manifest file %MF% does not exist.
  exit 1
)
set runfile_path=%~1
for /F "tokens=2* usebackq" %%i in (`%SYSTEMROOT%\system32\findstr.exe /l /c:"!runfile_path! " "%MF%"`) do (
  set abs_path=%%i
)
if "!abs_path!" equ "" (
  set runfile_path=%runfile_path%.exe
  for /F "tokens=2* usebackq" %%i in (`%SYSTEMROOT%\system32\findstr.exe /l /c:"!runfile_path! " "%MF%"`) do (
    set abs_path=%%i
  )
)
if "!abs_path!" equ "" (
  echo>&2 ERROR: !runfile_path! not found in runfiles manifest
  exit /b 1
)
set %~2=!abs_path!
exit /b 0
:rlocation_end
:: End of rlocation

REM Determine bin_path based on rlocation_path
call :rlocation {{rlocation_path}} bin_path
set bin_path=%bin_path:/=\%

REM Use PowerShell one-liner to resolve symlink
for /f "usebackq delims=" %%A in (`pwsh -NoProfile -Command "($info = Get-Item '%bin_path%' -Force) ; if ($info.LinkType -eq 'SymbolicLink' -or $info.LinkType -eq 'Junction') { $info.Target } else { $info.FullName }"`) do (
    set resolved_bin_path=%%A
)

REM Use delayed expansion for resolved_bin_path!
set "bin_path=!resolved_bin_path!"

REM Get own path and directory
set "own_path=%~f0"
set "own_dir=%~dp0"
set "own_name=%~nx0"
set "own_name=%own_name:.bat=%"

REM Remove trailing backslash from own_dir if present
if "%own_dir:~-1%"=="\" set "own_dir=%own_dir:~0,-1%"

REM Derive source workspace path from script's own path
set "source_workspace_path="
set "script_path=%own_path:\=/%"
echo !script_path! | findstr /c:"/bazel-out/" >nul
if !errorlevel! equ 0 (
    for /f "tokens=1" %%a in ("!script_path:/bazel-out/= !") do (
        set "temp_path=%%a"
    )
    set "source_workspace_path=!temp_path:/=\!"
)

call :_bazel__get_workspace_path
set BUILD_WORKSPACE_DIRECTORY=%workspace_path%

REM Use source_workspace_path if available, otherwise use workspace_path
if "!source_workspace_path!"=="" (
    set "watch_base=%workspace_path%"
) else (
    set "watch_base=!source_workspace_path!"
)

REM Build list of files to watch
set "files_to_watch_count=0"
set "watch_files_list=%TEMP%\bazel_env_watch_files_%RANDOM%.txt"
if exist "%watch_files_list%" del "%watch_files_list%"

REM Process common watch dirs
if exist "%own_dir%\__common_watch_dirs.txt" (
    for /f "usebackq delims=" %%d in ("%own_dir%\__common_watch_dirs.txt") do (
        if exist "!watch_base!\%%d" (
            for /f "delims=" %%f in ('dir /b /s /a-d "!watch_base!\%%d" 2^>nul') do (
                echo %%f>> "%watch_files_list%"
                set /a files_to_watch_count+=1
            )
        )
    )
)

REM Process common watch files
if exist "%own_dir%\__common_watch_files.txt" (
    for /f "usebackq delims=" %%f in ("%own_dir%\__common_watch_files.txt") do (
        if exist "!watch_base!\%%f" (
            echo !watch_base!\%%f>> "%watch_files_list%"
            set /a files_to_watch_count+=1
        )
    )
)

REM Process tool-specific watch dirs
if exist "%own_dir%\_%own_name%_watch_dirs.txt" (
    for /f "usebackq delims=" %%d in ("%own_dir%\_%own_name%_watch_dirs.txt") do (
        if exist "!watch_base!\%%d" (
            for /f "delims=" %%f in ('dir /b /s /a-d "!watch_base!\%%d" 2^>nul') do (
                echo %%f>> "%watch_files_list%"
                set /a files_to_watch_count+=1
            )
        )
    )
)

REM Process tool-specific watch files
if exist "%own_dir%\_%own_name%_watch_files.txt" (
    for /f "usebackq delims=" %%f in ("%own_dir%\_%own_name%_watch_files.txt") do (
        if exist "!watch_base!\%%f" (
            echo !watch_base!\%%f>> "%watch_files_list%"
            set /a files_to_watch_count+=1
        )
    )
)

set "rebuild_env=False"
set "lock_file=!watch_base!\bazel_env.lock"

if %files_to_watch_count% gtr 0 (
    if not exist "!lock_file!" (
        type nul > "!lock_file!"
    )

    REM Check if files have changed using PowerShell
    pwsh -NoProfile -Command "function Get-Hash($f) { $sha256=[System.Security.Cryptography.SHA256]::Create(); $stream=[System.IO.File]::OpenRead($f); $hash=[BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-','').ToLower(); $stream.Close(); $sha256.Dispose(); return $hash }; $lockFile='!lock_file!'; $watchFiles=Get-Content '%watch_files_list%'; $lockContent=@{}; if (Test-Path $lockFile) { Get-Content $lockFile | ForEach-Object { if ($_ -match '^(\S+)\s+(.+)$') { $lockContent[$matches[2]]=$matches[1] } } }; $changed=$false; foreach ($file in $watchFiles) { if (Test-Path $file) { $hash=Get-Hash $file; if ($lockContent[$file] -ne $hash) { $changed=$true; break } } else { $changed=$true; break } }; if (($watchFiles.Count -ne $lockContent.Count) -or $changed) { exit 1 } else { exit 0 }"
    if !errorlevel! neq 0 (
        set "rebuild_env=True"
    )
)

if "!rebuild_env!"=="True" (
    if not defined BAZEL_ENV_INTERNAL_EXEC (
        echo>&2 Detected changes in watched files, rebuilding bazel_env...
        
        REM Run bazel build from watch_base
        pushd "!watch_base!"
        popd
        
        REM Update lock file with new hashes
        if %files_to_watch_count% gtr 0 (
            pwsh -NoProfile -Command "$watchFiles=Get-Content '%watch_files_list%'; $output=@(); foreach ($file in $watchFiles) { if (Test-Path $file) { $hash=(Get-FileHash -Algorithm SHA256 $file).Hash.ToLower(); $output+=\"$hash  $file\" } }; $output | Set-Content '!lock_file!'"
        )
        
        REM Clean up temp file
        if exist "%watch_files_list%" del "%watch_files_list%"
        
        REM Re-execute this script
        set "BAZEL_ENV_INTERNAL_EXEC=True"
        "%own_path%" %*
        exit /b !errorlevel!
    )
)

REM Clean up temp file
if exist "%watch_files_list%" del "%watch_files_list%"

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

REM If bin_ext is empty, assume it's an exe and create a .exe symlink
for %%F in ("!bin_path!") do (
    set "bin_filename=%%~nxF"
    set "bin_ext=%%~xF"
)
if "!bin_ext!"=="" (
    set "exe_symlink=!bin_path!.exe"
    if not exist "!exe_symlink!" (
        mklink "!exe_symlink!" "!bin_path!" >nul 2>&1
    )
    set "bin_path=!exe_symlink!"
)

REM Execute the target binary with all arguments
!bin_path! {{extra_args}} %*
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
cd "%workspace%"
goto :workspace_loop

:workspace_not_found
set "workspace=%CD%"

:workspace_found
set "workspace_path=%workspace%"
exit /b 0
