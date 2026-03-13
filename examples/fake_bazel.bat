@echo off
setlocal enabledelayedexpansion

REM Get the last argument
set "last_arg="
for %%a in (%*) do set "last_arg=%%a"

if not "!last_arg!"=="//:bazel_env" (
  echo Expected last argument to be //:bazel_env, got !last_arg! >&2
  exit /b 1
)

echo Fake Bazel stdout
echo Fake Bazel stderr >&2

if defined FAKE_BAZEL_MARKER_FILE (
  echo 1 >> "!FAKE_BAZEL_MARKER_FILE!"
)

if defined FAKE_BAZEL_EXIT_CODE (
  exit /b !FAKE_BAZEL_EXIT_CODE!
) else (
  exit /b 0
)
