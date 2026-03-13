#!/usr/bin/env bash
set -euo pipefail

# Force manifest-based runfiles resolution instead of directory-based
# We need this to resolve to actual workspace locations of files such as MODULE.bazel
# on all platforms including Windows, where directory-based runfiles are off by default
export RUNFILES_MANIFEST_ONLY=1

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
# https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: runfiles.bash initializer cannot find $f. An executable rule may have forgotten to expose it in the runfiles, or the binary may require RUNFILES_DIR to be set."; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# Check if running on Windows
is_windows=false
if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
  is_windows=true
fi

if [ "$is_windows" = true ]; then
  module_path="$(rlocation _main/MODULE.bazel)"
  build_workspace_directory="$(dirname "$module_path")"
  build_workspace_directory_plat="$build_workspace_directory"
  bazel_env_path="$(rlocation _main/bazel_env.bat)"
  # rlocation returns windows paths; convert to unix style for this bash script
  build_workspace_directory="$(echo "$build_workspace_directory" | sed -E 's|^([a-zA-Z]):|/\L\1|; s|\\|/|g')"
  build_workspace_directory_plat="$(echo "$build_workspace_directory_plat" | sed -E 's|/|\\|g')"
  windows_path_snippet=":/C/WINDOWS/System32:/C/Program Files/PowerShell/7"
  scriptext=".bat"
  exeext=".exe"
  fake_bazel="$build_workspace_directory_plat\\fake_bazel.bat"
else
  module_path="$(readlink -f MODULE.bazel)"
  build_workspace_directory="$(dirname "$module_path")"
  build_workspace_directory_plat="$build_workspace_directory"
  bazel_env_path="$(rlocation _main/bazel_env.sh)"
  windows_path_snippet=""
  scriptext=""
  exeext=""
  fake_bazel="$build_workspace_directory/fake_bazel.sh"
fi

# Run a command with a minimal PATH including the bazel_env and assert its
# output, possibly with wildcards.
function assert_cmd_output() {
  local -r cmd="$1"
  local -r expected_first_line="$2"
  local -r extra_path="${3:-}"
  local -r no_bazel_check="${4:-}"

  local -r bazel_env="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin"
  local -r fake_bazel_marker_file=$(mktemp)
  # The env var is no longer defined when the trap runs, so expand it early.
  # shellcheck disable=SC2064
  trap "rm '$fake_bazel_marker_file'" EXIT
  if ! full_output="$(env \
      -u TEST_SRCDIR \
      -u RUNFILES_DIR \
      -u RUNFILES_MANIFEST_FILE \
      FAKE_BAZEL_MARKER_FILE="$fake_bazel_marker_file" \
      BAZEL="$fake_bazel" \
      PATH="$bazel_env:/bin:/usr/bin$windows_path_snippet$extra_path" \
      $cmd 2>&1)"; then
    echo "Command $cmd failed:"
    echo "$full_output"
    exit 1
  fi

  local -r actual_first_line="$(echo "$full_output" | head -n 1)"
  # Allow for wildcard matching and print a diff if the output doesn't match.
  # shellcheck disable=SC2053
  if [[ $actual_first_line == $expected_first_line ]]; then
    return
  fi
  diff <(echo "$expected_first_line" | tr -d '\r') <(echo "$actual_first_line" | tr -d '\r') || exit 1
}

function assert_contains() {
  local -r pattern="$1"
  local -r content="$2"

  echo "$content" | grep -sqF -- "$pattern" || {
    echo "Expected to find '$pattern' in:"
    echo "$content"
    exit 1
  }
}

#### Status script ####
# Delete any lockfile from previous runs
rm -f "$build_workspace_directory/bazel_env.lock"

# Verify the print-path subcommand works even without direnv.
print_path_out=$(PATH="/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory_plat" \
  "$bazel_env_path" print-path) || {
    echo "print-path failed with output:"
    echo "$print_path_out"
    exit 1
  }
expected_path="$build_workspace_directory_plat/bazel-out/bazel_env-opt/bin/bazel_env/bin"
if [ "$is_windows" = true ]; then
  expected_path="$(echo "$expected_path" | sed -E 's|/|\\|g')"
fi
if [[ "$print_path_out" != "$expected_path" ]]; then
  echo "print-path output did not match the expected path:"
  echo "  $print_path_out"
  echo "Expected:"
  echo "  $expected_path"
  exit 1
fi

# Place a fake direnv tool on the PATH.
tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir')
trap 'rm -rf "$tmpdir"' EXIT
touch "$tmpdir/direnv$scriptext"
chmod +x "$tmpdir/direnv$scriptext"

# Imitate a bazel run environment for the status script.
status_out=$(PATH="$tmpdir:$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin:/c/windows/system32" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  $bazel_env_path) || {
    echo "Status script failed with output:"
    echo "$status_out"
    exit 1
  }

# shellcheck disable=SC2016
function expected_output {
  local -r sep="$1"
  if [ "$2" = true ]; then
    local -r toolchain_type_toolchains="  * go:                bazel-out/bazel_env-opt/bin/bazel_env/toolchains/go
"
  else
    local -r toolchain_type_toolchains=""
  fi
  local bindir="bazel-out/bazel_env-opt/bin/bazel_env/bin"
  if [[ "$is_windows" = true ]]; then
    bindir="$(echo "$bindir" | sed -E 's|/|\\|g')"
  fi
  printf '%s' "
====== bazel_env ======

✅ direnv is installed
✅ direnv added $bindir to PATH

Tools available in PATH:
  * buildifier:  @buildifier_prebuilt//:buildifier
  * buildozer:   @@buildozer${sep}${sep}buildozer_binary${sep}buildozer_binary//:buildozer.exe
  * go:          @rules_go//go
  * jar:         \$(JAVABASE)/bin/jar
  * java:        \$(JAVA)
  * jq:          :jq
  * node:        \$(NODE_PATH)
  * pnpm:        @pnpm
  * python:      \$(PYTHON3)
  * python_tool: :python_tool
  * echo_tool:   :echo_tool_bin
  * loc_tool:    :loc_tool_bin
  * ibazel:      @@rules_multitool${sep}${sep}multitool${sep}multitool//tools/ibazel:ibazel
  * terraform:   @@rules_multitool${sep}${sep}multitool${sep}multitool//tools/terraform:terraform

Toolchains available at stable relative paths:
  * jdk:               bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk
  * python:            bazel-out/bazel_env-opt/bin/bazel_env/toolchains/python
  * nodejs:            bazel-out/bazel_env-opt/bin/bazel_env/toolchains/nodejs
  * rules_python_docs: bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rules_python_docs
${toolchain_type_toolchains}
"
  if [[ "$is_windows" = true ]]; then
    printf '%s\n' "⚠️  Remember to restart your command prompt or PowerShell session to update the locations of binaries on the PATH."
  else
    printf '%s\n' "⚠️  Remember to run 'hash -r' in bash to update the locations of binaries on the PATH."
  fi
}

diff <(expected_output "$BAZEL_REPO_NAME_SEPARATOR" "$TOOLCHAIN_TYPES_SUPPORTED" | tr -d '\r') <(echo "$status_out" | tr -d '\r') || exit 1

#### Tools ####

# First call to any bazel_env tool will trigger rebuild
# assert_cmd_output "bazel-cc --version" "Detected changes in watched files, rebuilding bazel_env..."
# assert_cmd_output "bazel-cc --version" "@(*gcc*|*clang*)"
assert_cmd_output "buildifier$scriptext --version" "Detected changes in watched files, rebuilding bazel_env..."
assert_cmd_output "buildifier$scriptext --version" "buildifier version: 7.3.1 "
assert_cmd_output "buildozer$scriptext --version" "buildozer version: 7.1.2 "
case "$(arch)" in
  i386|x86_64) goarch="amd64";;
  *) goarch="$(arch)";;
esac
goplat=$(uname|tr '[:upper:]' '[:lower:]')
if [ "$is_windows" = true ]; then
  goplat="windows"
fi
assert_cmd_output "go$scriptext version" "go version go1.25.0 $goplat/$goarch"
assert_cmd_output "jar$scriptext --version" "jar 17.0.17"
assert_cmd_output "java$scriptext --version" "openjdk 17.0.17 2025-10-21 LTS"
jqversion="jq-1.7"
if [ "$is_windows" = true ]; then
  jqversion=$jqversion"-dirty"
fi
assert_cmd_output "jq$scriptext --version" "$jqversion"
assert_cmd_output "node$scriptext --version" "v16.18.1"
assert_cmd_output "pnpm$scriptext --version" "8.6.7"
assert_cmd_output "python$scriptext --version" "Python 3.11.8"
# Bazel's Python launcher requires a system installation of python3.
# python_tool has its own watch_files, so first call triggers rebuild.
# python isn't installed by default on windows, so skip this
if [ "$is_windows" != true ]; then
  assert_cmd_output "python_tool$scriptext" "Detected changes in watched files, rebuilding bazel_env..." ":$(dirname "$(which python3)")"
  assert_cmd_output "python_tool$scriptext" "python_tool version 0.0.1" ":$(dirname "$(which python3)")"
fi
# rules_rust 0.63 doesn't work on windows and can't upgrade due to bazel_env issue
# assert_cmd_output "cargo$scriptext --version" "cargo 1.80.0 (376290515 2024-07-16)"
# assert_cmd_output "rustc$scriptext --version" "rustc 1.80.0 (051478957 2024-07-21)"
# assert_cmd_output "rustfmt$scriptext --version" "rustfmt 1.7.0-stable (0514789* 2024-07-21)"
assert_cmd_output "ibazel$scriptext" "iBazel - Version v0.25.3"
assert_cmd_output "terraform$scriptext --version" "Terraform v1.9.3"

#### Binary args and env forwarding ####

if [ "$SH_BINARY_EMITS_RUN_ENVIRONMENT_INFO" = false ]; then
  echo "Skipping env var forwarding test since native sh_binary doesn't emit RunEnvironmentInfo."
else
  # Verify that the args attribute is forwarded before user args.
  assert_cmd_output "echo_tool$scriptext --user-arg" "TOOL_VAR=from_env args=--default-arg --user-arg"
  # Verify that without extra user args, only the default args are passed.
  assert_cmd_output "echo_tool$scriptext" "TOOL_VAR=from_env args=--default-arg"
fi
# Verify that $(rlocationpath) in args is expanded and the file is accessible via RUNFILES_DIR.
assert_cmd_output "loc_tool$scriptext" "found: *location_test_data*"

#### Toolchains ####

# [[ -d "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/cc_toolchain" ]]
if [ "$TOOLCHAIN_TYPES_SUPPORTED" = true ]; then
  assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/go/bin/go$exeext version" "go version go1.25.0 $goplat/$goarch"
fi
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk/bin/java$exeext --version" "openjdk 17.0.17 2025-10-21 LTS"
python_path="bin/python3"
if [ "$is_windows" = true ]; then
  python_path="python.exe"
fi
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/python/$python_path --version" "Python 3.11.8"
# rules_rust 0.63 doesn't work on windows and can't upgrade due to bazel_env issue
# assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rust/bin/cargo$scriptext --version" "cargo 1.80.0 (376290515 2024-07-16)"
# assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rust/bin/rustc$scriptext --version" "rustc 1.80.0 (051478957 2024-07-21)"
[[ -f "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rules_python_docs/extending.md" ]]

#### Running from outside workspace ####

# Test that tools work when run from a directory outside the Bazel workspace.
# This verifies that watch_dirs/watch_files are resolved relative to the source
# workspace (derived from the script path) rather than the current directory.

external_tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'external_tmpdir')
trap 'rm -rf "$external_tmpdir"' EXIT

# Run buildifier from outside the workspace - should work without errors
# Note: BAZEL must be an absolute path since we're running from a different directory
external_output=$(cd "$external_tmpdir" && env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    BAZEL="$fake_bazel" \
    PATH="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin$windows_path_snippet" \
    buildifier$scriptext --version 2>&1) || {
  echo "Running buildifier from outside workspace failed:"
  echo "$external_output"
  exit 1
}

# Verify the output contains the version (not an error about missing directories)
assert_contains "buildifier version:" "$external_output"

# Verify there's no "find:" error in the output (which would indicate watch_dirs failed)
if echo "$external_output" | grep -q "^find:"; then
  echo "Found 'find:' error when running from outside workspace:"
  echo "$external_output"
  exit 1
fi

exit 0
