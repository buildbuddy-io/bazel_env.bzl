#!/usr/bin/env bash

set -euo pipefail

build_workspace_directory="$(dirname "$(readlink -f MODULE.bazel)")"

# Run a command with a minimal PATH including the bazel_env and assert its
# output, possibly with wildcards.
function assert_cmd_output() {
  local -r cmd="$1"
  local -r expected_first_line="$2"
  local -r extra_path="${3:-}"
  local -r no_bazel_check="${4:-}"

  local -r bazel_env="${BAZEL_ENV_BIN_DIR:-$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin}"
  local -r fake_bazel_marker_file=$(mktemp)
  # The env var is no longer defined when the trap runs, so expand it early.
  # shellcheck disable=SC2064
  trap "rm '$fake_bazel_marker_file'" EXIT
  if ! full_output="$(env \
      -u TEST_SRCDIR \
      -u RUNFILES_DIR \
      -u RUNFILES_MANIFEST_FILE \
      FAKE_BAZEL_MARKER_FILE="$fake_bazel_marker_file" \
      BAZEL=./fake_bazel.sh \
      PATH="$bazel_env:/bin:/usr/bin$extra_path" \
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
  diff <(echo "$expected_first_line") <(echo "$actual_first_line") || exit 1
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

# Assert an exact path entry in the lock.
function assert_lock_has_path() {
  local -r lock="$1"
  local -r path="$2"
  awk -v f="$path" '
    { match($0, /^[^ ]+ +/); if (substr($0, RSTART + RLENGTH) == f) found = 1 }
    END { exit !found }
  ' "$lock" || {
    echo "Expected an entry for '$path' in $lock:"
    cat "$lock"
    exit 1
  }
}

#### Status script ####

# print-path seeds the lock too (used by CI).
rm -f "$build_workspace_directory/bazel_env.lock"

# Verify the print-path subcommand works even without direnv.
print_path_out=$(PATH="/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  ./bazel_env.sh print-path) || {
    echo "print-path failed with output:"
    echo "$print_path_out"
    exit 1
  }
if [[ "$print_path_out" != "$build_workspace_directory/.bazel_env/bin" ]]; then
  echo "print-path output did not match the expected path:"
  echo "  $print_path_out"
  echo "Expected:"
  echo "  $build_workspace_directory/.bazel_env/bin"
  exit 1
fi
# print-path creates the symlink itself, so the printed path always exists.
if [[ ! -d "$print_path_out" ]]; then
  echo "print-path output is not a directory: $print_path_out"
  exit 1
fi

# Verify the update-symlink subcommand prints nothing.
update_symlink_out=$(PATH="/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  ./bazel_env.sh update-symlink 2>&1) || {
    echo "update-symlink failed with output:"
    echo "$update_symlink_out"
    exit 1
  }
if [[ -n "$update_symlink_out" ]]; then
  echo "update-symlink printed unexpected output: $update_symlink_out"
  exit 1
fi

assert_lock_has_path "$build_workspace_directory/bazel_env.lock" "$build_workspace_directory/MODULE.bazel"

# Place a fake direnv tool on the PATH.
tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir')
trap 'rm -rf "$tmpdir"' EXIT
touch "$tmpdir/direnv"
chmod +x "$tmpdir/direnv"

# Start without a lock so the seeding checks below test the status script.
rm -f "$build_workspace_directory/bazel_env.lock"

# Imitate a bazel run environment for the status script.
status_out=$(PATH="$tmpdir:$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  ./bazel_env.sh) || {
    echo "Status script failed with output:"
    echo "$status_out"
    exit 1
  }

# Verify that the symlink exists in the package of the bazel_env target and
# resolves to the physical location of the bazel_env output directory.
if [[ ! -L "$build_workspace_directory/.bazel_env" ]]; then
  echo "Error: .bazel_env symlink was not created in the package directory"
  exit 1
fi
actual_target="$(cd "$build_workspace_directory/.bazel_env" && pwd -P)"
expected_target="$(cd "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env" && pwd -P)"
if [[ "$actual_target" != "$expected_target" ]]; then
  echo "Error: .bazel_env symlink resolves to '$actual_target', expected '$expected_target'"
  exit 1
fi

# shellcheck disable=SC2016
function expected_output {
  local -r sep="$1"
  if [ "$2" = true ]; then
    local -r toolchain_type_toolchains="  * go:                .bazel_env/toolchains/go
"
  else
    local -r toolchain_type_toolchains=""
  fi
  printf '%s' "
====== bazel_env ======

✅ Refreshed bazel_env.lock
✅ direnv is installed
✅ direnv added ./.bazel_env/bin to PATH

Tools available in PATH:
  * bazel-cc:    \$(CC)
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
  * cargo:       @rules_rust//tools/upstream_wrapper:cargo
  * echo_tool:   :echo_tool_bin
  * loc_tool:    :loc_tool_bin
  * rustc:       @rules_rust//tools/upstream_wrapper:rustc
  * rustfmt:     @rules_rust//tools/upstream_wrapper:rustfmt
  * ibazel:      @@rules_multitool${sep}${sep}multitool${sep}multitool//tools/ibazel:ibazel
  * terraform:   @@rules_multitool${sep}${sep}multitool${sep}multitool//tools/terraform:terraform

ℹ️  The bin directory is also reachable at bazel-out/bazel_env-opt/bin/bazel_env/bin relative to the workspace root.

Toolchains available at stable relative paths:
  * cc_toolchain:      .bazel_env/toolchains/cc_toolchain
  * jdk:               .bazel_env/toolchains/jdk
  * python:            .bazel_env/toolchains/python
  * nodejs:            .bazel_env/toolchains/nodejs
  * rust:              .bazel_env/toolchains/rust
  * rules_python_docs: .bazel_env/toolchains/rules_python_docs
${toolchain_type_toolchains}
⚠️  Remember to run 'hash -r' in bash to update the locations of binaries on the PATH.
"
}

diff <(expected_output "$BAZEL_REPO_NAME_SEPARATOR" "$TOOLCHAIN_TYPES_SUPPORTED") <(echo "$status_out") || exit 1

#### Non-root package instructions ####

# The setup instructions anchor at the workspace-root .envrc file and prefix
# all paths with the package of the bazel_env target. An empty temporary
# workspace serves as BUILD_WORKSPACE_DIRECTORY so that the check for an
# existing .envrc file does not suppress the instructions.
nested_ws=$(mktemp -d 2>/dev/null || mktemp -d -t 'nested_ws')
trap 'rm -rf "$nested_ws"' EXIT
mkdir -p "$nested_ws/nested"
if nested_out=$(PATH="$tmpdir:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$nested_ws" \
  ./nested/nested_env.sh 2>&1); then
  echo "Expected the nested status script to fail without the marker tool on PATH:"
  echo "$nested_out"
  exit 1
fi
assert_contains "Create a .envrc file next to your MODULE.bazel file" "$nested_out"
assert_contains "watch_file nested/.nested_env/bin" "$nested_out"
assert_contains "PATH_add nested/.nested_env/bin" "$nested_out"
if [[ ! -L "$nested_ws/nested/.nested_env" ]]; then
  echo "Error: .nested_env symlink was not created in the nested package directory"
  exit 1
fi

#### .envrc consistency ####

# The checked-in .envrc file matches the snippet the status script emits for
# the root-package target, so the two cannot drift apart. An empty temporary
# workspace serves as BUILD_WORKSPACE_DIRECTORY so that the instructions are
# printed.
envrc_ws=$(mktemp -d 2>/dev/null || mktemp -d -t 'envrc_ws')
trap 'rm -rf "$envrc_ws"' EXIT
if envrc_instructions=$(PATH="$tmpdir:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$envrc_ws" \
  ./bazel_env.sh 2>&1); then
  echo "Expected the status script to fail without the marker tool on PATH:"
  echo "$envrc_instructions"
  exit 1
fi
while IFS= read -r envrc_line; do
  [[ -z "$envrc_line" ]] && continue
  assert_contains "$envrc_line" "$envrc_instructions"
done < "$build_workspace_directory/.envrc"

#### Lock seeding ####

# The status script seeds the lock with the _common watch files.
lock_file="$build_workspace_directory/bazel_env.lock"
[[ -s "$lock_file" ]] || { echo "bazel_env.lock was not created or is empty"; exit 1; }
assert_contains "$build_workspace_directory/MODULE.bazel" "$(cat "$lock_file")"
assert_contains "$build_workspace_directory/BUILD.bazel" "$(cat "$lock_file")"

#### Lock merge ####

# Re-seeding keeps other targets' entries.
foreign_path="$build_workspace_directory/other-bazel-env-entry.txt"
printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$foreign_path" >> "$lock_file"

PATH="$tmpdir:$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  ./bazel_env.sh >/dev/null || { echo "Status re-run failed"; exit 1; }

if ! grep -qF -- "$foreign_path" "$lock_file"; then
  echo "Re-seed clobbered an unrelated entry in bazel_env.lock:"
  cat "$lock_file"
  exit 1
fi
assert_contains "$build_workspace_directory/MODULE.bazel" "$(cat "$lock_file")"

#### Lock seeding for a non-root package ####

# A non-root package target seeds the workspace-root lock.
nested_lock_ws=$(mktemp -d 2>/dev/null || mktemp -d -t 'nested_lock_ws')
trap 'rm -rf "$nested_lock_ws"' EXIT
# The lock stores physical paths.
nested_lock_ws_real="$(cd "$nested_lock_ws" && pwd -P)"
mkdir -p "$nested_lock_ws/nested"
cp "$build_workspace_directory/nested/hello.sh" "$nested_lock_ws/nested/hello.sh"

# Fresh clone: seeds even though the PATH check fails.
if fresh_out=$(PATH="$tmpdir:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$nested_lock_ws" \
  ./nested/nested_watched_env.sh 2>&1); then
  echo "Expected the nested status script to fail without the marker tool on PATH:"
  echo "$fresh_out"
  exit 1
fi
assert_contains "✅ Refreshed bazel_env.lock" "$fresh_out"
assert_lock_has_path "$nested_lock_ws/bazel_env.lock" "$nested_lock_ws_real/nested/hello.sh"
rm -f "$nested_lock_ws/bazel_env.lock"

nested_lock_out=$(PATH="$tmpdir:$nested_lock_ws/nested/.nested_watched_env/bin:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$nested_lock_ws" \
  ./nested/nested_watched_env.sh 2>&1) || {
    echo "Nested status script failed with output:"
    echo "$nested_lock_out"
    exit 1
  }
assert_contains "✅ Refreshed bazel_env.lock" "$nested_lock_out"
[[ -s "$nested_lock_ws/bazel_env.lock" ]] || { echo "Nested target did not seed the workspace-root bazel_env.lock"; exit 1; }
assert_contains "$nested_lock_ws/nested/hello.sh" "$(cat "$nested_lock_ws/bazel_env.lock")"
if [[ -e "$nested_lock_ws/nested/bazel_env.lock" ]]; then
  echo "Nested target wrote bazel_env.lock into its package directory"
  exit 1
fi

#### No watch files ####

# Without watch files, status neither touches the lock nor warns, and tools
# run without a rebuild.
no_watch_ws=$(mktemp -d 2>/dev/null || mktemp -d -t 'no_watch_ws')
trap 'rm -rf "$no_watch_ws"' EXIT
mkdir -p "$no_watch_ws/nested"
no_watch_out=$(PATH="$tmpdir:$no_watch_ws/nested/.nested_env/bin:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$no_watch_ws" \
  ./nested/nested_env.sh 2>&1) || {
    echo "Status script without watch files failed with output:"
    echo "$no_watch_out"
    exit 1
  }
if [[ "$no_watch_out" == *bazel_env.lock* ]]; then
  echo "Status script without watch files mentioned bazel_env.lock:"
  echo "$no_watch_out"
  exit 1
fi
if [[ -e "$no_watch_ws/bazel_env.lock" ]]; then
  echo "Status script without watch files wrote bazel_env.lock"
  exit 1
fi
BAZEL_ENV_BIN_DIR="$build_workspace_directory/bazel-out/bazel_env-opt/bin/nested/nested_env/bin" \
  assert_cmd_output "hello" "hello"

#### Seed suppresses the first-use rebuild ####

# Launchers ignore stale watch lists left in bazel-out.
stale_watch_list="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/tools/__common_watch_dirs.txt"
[[ ! -e "$stale_watch_list" ]] || { echo "Unexpected $stale_watch_list"; exit 1; }
echo " nested " > "$stale_watch_list"
stale_rc=0
(assert_cmd_output "buildifier --version" "buildifier version: 7.3.1 ") || stale_rc=$?
rm -f "$stale_watch_list"
[[ $stale_rc -eq 0 ]] || exit 1

#### A watched-file change after seeding still rebuilds ####

corrupt=$(mktemp)
awk -v f="$build_workspace_directory/MODULE.bazel" '
  { match($0, /^[^ ]+ +/); p = substr($0, RSTART + RLENGTH); if (p == f) $0 = "0000000000000000000000000000000000000000000000000000000000000000  " f; print }
' "$lock_file" > "$corrupt" && mv "$corrupt" "$lock_file"
assert_cmd_output "buildifier --version" "Detected changes in watched files, rebuilding bazel_env..."

#### Tools ####

# Ensure repeated test configurations begin with the same auto-rebuild state.
rm -f "$build_workspace_directory/bazel_env.lock"

# The assertions in this section invoke tools through the bazel-out path style
# of the bin directory; together with the "Tools via the package-scoped
# symlink" section, both supported path styles are exercised.

# First call to any bazel_env tool will trigger rebuild
assert_cmd_output "bazel-cc --version" "Detected changes in watched files, rebuilding bazel_env..."
assert_cmd_output "bazel-cc --version" "@(*gcc*|*clang*)"
assert_cmd_output "buildifier --version" "buildifier version: 7.3.1 "
assert_cmd_output "buildozer --version" "buildozer version: 7.1.2 "
case "$(arch)" in
  i386|x86_64) goarch="amd64";;
  *) goarch="$(arch)";;
esac
assert_cmd_output "go version" "go version go1.21.13 $(uname|tr '[:upper:]' '[:lower:]')/$goarch"
assert_cmd_output "jar --version" "jar 17.0.20"
assert_cmd_output "java --version" "openjdk 17.0.20 2026-07-21 LTS"
assert_cmd_output "jq --version" "jq-1.7"
assert_cmd_output "node --version" "v16.18.1"
assert_cmd_output "pnpm --version" "8.6.7"
assert_cmd_output "python --version" "Python 3.11.8"
# Bazel's Python launcher requires a system installation of python3.
# python_tool has its own watch_files, so first call triggers rebuild.
assert_cmd_output "python_tool" "Detected changes in watched files, rebuilding bazel_env..." ":$(dirname "$(which python3)")"
assert_cmd_output "python_tool" "python_tool version 0.0.1" ":$(dirname "$(which python3)")"
assert_cmd_output "cargo --version" "cargo 1.80.0 (376290515 2024-07-16)"
assert_cmd_output "rustc --version" "rustc 1.80.0 (051478957 2024-07-21)"
assert_cmd_output "rustfmt --version" "rustfmt 1.7.0-stable (0514789* 2024-07-21)"
assert_cmd_output "ibazel" "iBazel - Version v0.25.3"
assert_cmd_output "terraform --version" "Terraform v1.9.3"

#### Tools via the package-scoped symlink ####

# The launchers are also reachable through the package-scoped symlink and
# behave identically to the bazel-out path style. Together with the section
# above, both supported path styles are exercised.
BAZEL_ENV_BIN_DIR="$build_workspace_directory/.bazel_env/bin"
assert_cmd_output "buildifier --version" "buildifier version: 7.3.1 "
assert_cmd_output "loc_tool" "found: *location_test_data*"
assert_cmd_output "python_tool" "python_tool version 0.0.1" ":$(dirname "$(which python3)")"
unset BAZEL_ENV_BIN_DIR

#### Binary args and env forwarding ####

if [ "$SH_BINARY_EMITS_RUN_ENVIRONMENT_INFO" = false ]; then
  echo "Skipping env var forwarding test since native sh_binary doesn't emit RunEnvironmentInfo."
else
  # Verify that the args attribute is forwarded before user args.
  assert_cmd_output "echo_tool --user-arg" "TOOL_VAR=from_env args=--default-arg --user-arg"
  # Verify that without extra user args, only the default args are passed.
  assert_cmd_output "echo_tool" "TOOL_VAR=from_env args=--default-arg"
fi
# Verify that $(rlocationpath) in args is expanded and the file is accessible via RUNFILES_DIR.
assert_cmd_output "loc_tool" "found: *location_test_data*"

#### Toolchains ####

[[ -d "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/cc_toolchain" ]]
if [ "$TOOLCHAIN_TYPES_SUPPORTED" = true ]; then
  assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/go/bin/go version" "go version go1.21.13 $(uname|tr '[:upper:]' '[:lower:]')/$goarch"
fi
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk/bin/java --version" "openjdk 17.0.20 2026-07-21 LTS"
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/python/bin/python3 --version" "Python 3.11.8"
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rust/bin/cargo --version" "cargo 1.80.0 (376290515 2024-07-16)"
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rust/bin/rustc --version" "rustc 1.80.0 (051478957 2024-07-21)"
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
    BAZEL="$build_workspace_directory/fake_bazel.sh" \
    PATH="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || {
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

# The launcher derives the source workspace from the invocation path also when
# a tool is invoked through the package-scoped symlink, so the auto-rebuild
# triggers from any working directory. With a missing lock file, exactly one
# rebuild must happen.
rm -f "$build_workspace_directory/bazel_env.lock"
symlink_rebuild_marker=$(mktemp)
trap 'rm -f "$symlink_rebuild_marker"' EXIT
symlink_external_output=$(cd "$external_tmpdir" && env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    FAKE_BAZEL_MARKER_FILE="$symlink_rebuild_marker" \
    BAZEL="$build_workspace_directory/fake_bazel.sh" \
    PATH="$build_workspace_directory/.bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || {
  echo "Running buildifier through the package-scoped symlink from outside the workspace failed:"
  echo "$symlink_external_output"
  exit 1
}
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$symlink_external_output"
assert_contains "buildifier version:" "$symlink_external_output"
rebuild_count=$(wc -l < "$symlink_rebuild_marker" | tr -d ' ')
if [[ "$rebuild_count" != 1 ]]; then
  echo "Expected exactly one rebuild through the package-scoped symlink, got $rebuild_count"
  exit 1
fi

# The workspace derivation matches the symlink-based launcher path as an exact
# suffix, so a directory elsewhere in the path that shares the symlink's name
# does not change the derived workspace. The workspace is reached through a
# symlink inside a directory literally named like the package-scoped symlink,
# and the rebuild still fires exactly once.
hostile_base=$(mktemp -d 2>/dev/null || mktemp -d -t 'hostile_base')
trap 'rm -rf "$hostile_base"' EXIT
mkdir -p "$hostile_base/.bazel_env"
ln -s "$build_workspace_directory" "$hostile_base/.bazel_env/ws"
rm -f "$build_workspace_directory/bazel_env.lock"
hostile_marker=$(mktemp)
trap 'rm -f "$hostile_marker"' EXIT
hostile_output=$(cd "$external_tmpdir" && env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    FAKE_BAZEL_MARKER_FILE="$hostile_marker" \
    BAZEL="$build_workspace_directory/fake_bazel.sh" \
    PATH="$hostile_base/.bazel_env/ws/.bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || {
  echo "Running buildifier through a path containing a hostile directory name failed:"
  echo "$hostile_output"
  exit 1
}
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$hostile_output"
assert_contains "buildifier version:" "$hostile_output"
hostile_rebuild_count=$(wc -l < "$hostile_marker" | tr -d ' ')
if [[ "$hostile_rebuild_count" != 1 ]]; then
  echo "Expected exactly one rebuild through the hostile path, got $hostile_rebuild_count"
  exit 1
fi

#### Auto-rebuild logs go to stderr, not stdout ####

# When watched files change, the launcher runs a bazel build to rebuild
# bazel_env. Those build logs must go to stderr so they don't pollute the
# wrapped tool's stdout and break piping. fake_bazel.sh emits "Fake Bazel
# stdout" on stdout and "Fake Bazel stderr" on stderr; after the redirect both
# should end up on the launcher's stderr.

# Remove the lock file to force a rebuild on the next tool invocation.
rm -f "$build_workspace_directory/bazel_env.lock"

rebuild_stdout=$(mktemp)
rebuild_stderr=$(mktemp)
rebuild_marker=$(mktemp)
trap 'rm -f "$rebuild_stdout" "$rebuild_stderr" "$rebuild_marker"' EXIT

env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    FAKE_BAZEL_MARKER_FILE="$rebuild_marker" \
    BAZEL=./fake_bazel.sh \
    PATH="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
    buildifier --version >"$rebuild_stdout" 2>"$rebuild_stderr" || {
  echo "buildifier --version failed during rebuild:"
  cat "$rebuild_stderr"
  exit 1
}

# Sanity check: a rebuild actually happened (otherwise this test is vacuous).
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$(cat "$rebuild_stderr")"

# The bazel build's stdout must have been redirected to stderr.
assert_contains "Fake Bazel stdout" "$(cat "$rebuild_stderr")"

# stdout must contain only the wrapped tool's output, not the build logs.
if grep -qF "Fake Bazel stdout" "$rebuild_stdout"; then
  echo "Bazel build logs leaked onto the tool's stdout:"
  cat "$rebuild_stdout"
  exit 1
fi
assert_contains "buildifier version:" "$(cat "$rebuild_stdout")"

#### Auto-rebuild re-materializes runfiles trees ####

# The runfiles trees of the tools are only (re-)created when the bazel_env
# target's helper action actually executes. On a fully cached build, Bazel
# skips the action and never re-verifies the trees, so externally corrupted
# runfiles (e.g. after a cache cleaner ran over the output base) would stay
# broken forever. The launcher must therefore delete the helper action's
# output before invoking bazel so that the action re-executes and Bazel
# itself repairs the runfiles trees of all tools.

all_tools_out="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env_all_tools"
# The rebuilds triggered earlier in this test already deleted the helper
# action's output and the fake bazel doesn't recreate it. Recreate it here to
# verify that the launcher deletes it before invoking bazel.
rm -f "$all_tools_out"
: > "$all_tools_out"

# Remove the lock file to force a rebuild on the next tool invocation.
rm -f "$build_workspace_directory/bazel_env.lock"

observation_file=$(mktemp)
repair_marker=$(mktemp)
trap 'rm -f "$rebuild_stdout" "$rebuild_stderr" "$rebuild_marker" "$observation_file" "$repair_marker"' EXIT

repair_output=$(env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    FAKE_BAZEL_MARKER_FILE="$repair_marker" \
    FAKE_BAZEL_OBSERVED_FILE="$all_tools_out" \
    FAKE_BAZEL_OBSERVATION_FILE="$observation_file" \
    BAZEL=./fake_bazel.sh \
    PATH="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || {
  echo "buildifier --version failed during rebuild:"
  echo "$repair_output"
  exit 1
}

# Sanity check: a rebuild actually happened (otherwise this test is vacuous).
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$repair_output"

# The launcher must have deleted the helper action's output before invoking
# bazel so that the action re-executes even on an otherwise fully cached build.
if [[ "$(cat "$observation_file")" != "absent" ]]; then
  echo "Expected the launcher to delete $all_tools_out before invoking bazel, but it still existed"
  exit 1
fi

#### Missing lock_lib.sh triggers a rebuild ####

# A cache cleaner may delete lock_lib.sh from a tool's runfiles.
lock_lib_link="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/tools/buildifier.runfiles/bazel_env.bzl${BAZEL_REPO_NAME_SEPARATOR}/lock_lib.sh"
[[ -e "$lock_lib_link" ]] || { echo "lock_lib.sh not found in buildifier's runfiles"; exit 1; }
mv "$lock_lib_link" "$lock_lib_link.bak"
missing_lib_output=$(env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    BAZEL=./fake_bazel.sh \
    PATH="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || missing_lib_rc=$?
# Restore before asserting so that a failure doesn't break the output base.
mv "$lock_lib_link.bak" "$lock_lib_link"
[[ -z "${missing_lib_rc:-}" ]] || { echo "buildifier failed without lock_lib.sh:"; echo "$missing_lib_output"; exit 1; }
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$missing_lib_output"
assert_contains "buildifier version: 7.3.1" "$missing_lib_output"

#### Auto-rebuild repoints the package-scoped symlink ####

# A stale symlink that still resolves, as left behind by a moved output directory.
stale_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'stale_dir')
trap 'rm -rf "$rebuild_stdout" "$rebuild_stderr" "$rebuild_marker" "$observation_file" "$repair_marker" "$stale_dir"; ln -sfn "$expected_target" "$build_workspace_directory/.bazel_env"' EXIT
ln -s "$expected_target" "$stale_dir/bazel_env"
ln -sfn "$stale_dir/bazel_env" "$build_workspace_directory/.bazel_env"

# Remove the lock file to force a rebuild on the next tool invocation.
rm -f "$build_workspace_directory/bazel_env.lock"

repoint_output=$(env \
    -u TEST_SRCDIR \
    -u RUNFILES_DIR \
    -u RUNFILES_MANIFEST_FILE \
    FAKE_BAZEL_RUN_SCRIPT="$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env.sh" \
    BAZEL="$build_workspace_directory/fake_bazel.sh" \
    PATH="$build_workspace_directory/.bazel_env/bin:/bin:/usr/bin" \
    buildifier --version 2>&1) || {
  echo "buildifier --version failed during rebuild through a stale symlink:"
  echo "$repoint_output"
  exit 1
}

# Sanity check: a rebuild actually happened (otherwise this test is vacuous).
assert_contains "Detected changes in watched files, rebuilding bazel_env..." "$repoint_output"
assert_contains "buildifier version:" "$repoint_output"

actual_link="$(readlink "$build_workspace_directory/.bazel_env")"
if [[ "$actual_link" != "$expected_target" ]]; then
  echo "Error: auto-rebuild left .bazel_env pointing at '$actual_link', expected '$expected_target'"
  exit 1
fi
