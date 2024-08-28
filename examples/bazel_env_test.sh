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

#### Status script ####

# Place a fake direnv tool on the PATH.
tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir')
trap 'rm -rf "$tmpdir"' EXIT
touch "$tmpdir/direnv"
chmod +x "$tmpdir/direnv"

# Imitate a bazel run environment for the status script.
status_out=$(PATH="$tmpdir:$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/bin:/bin:/usr/bin" \
BUILD_WORKSPACE_DIRECTORY="$build_workspace_directory" \
  ./bazel_env.sh) || {
    echo "Status script failed with output:"
    echo "$status_out"
    exit 1
  }

# shellcheck disable=SC2016
function expected_output {
  local -r sep="$1"
  printf '%s' "
====== bazel_env ======

✅ direnv is installed
✅ direnv added bazel-out/bazel_env-opt/bin/bazel_env/bin to PATH

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
  * cargo:       \$(CARGO)
  * rustfmt:     \$(RUSTFMT)
  * rustc:       \$(RUSTC)
  * rustdoc:     \$(RUSTDOC)

Toolchains available at stable relative paths:
  * cc_toolchain: bazel-out/bazel_env-opt/bin/bazel_env/toolchains/cc_toolchain
  * jdk:          bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk
  * python:       bazel-out/bazel_env-opt/bin/bazel_env/toolchains/python
  * nodejs:       bazel-out/bazel_env-opt/bin/bazel_env/toolchains/nodejs
  * rust:         bazel-out/bazel_env-opt/bin/bazel_env/toolchains/rust
"
}

diff <(expected_output "$BAZEL_REPO_NAME_SEPARATOR") <(echo "$status_out") || exit 1

#### Tools ####

assert_cmd_output "bazel-cc --version" "@(*gcc*|*clang*)"
assert_cmd_output "buildifier --version" "buildifier version: 6.4.0 "
assert_cmd_output "buildozer --version" "buildozer version: 7.1.2 "
case "$(arch)" in
  i386|x86_64) goarch="amd64";;
  *) goarch="$(arch)";;
esac
assert_cmd_output "go version" "go version go1.20.14 $(uname|tr '[:upper:]' '[:lower:]')/$goarch"
assert_cmd_output "jar --version" "jar 17.0.11"
assert_cmd_output "java --version" "openjdk 17.0.11 2024-04-16 LTS"
assert_cmd_output "jq --version" "jq-1.5"
assert_cmd_output "node --version" "v16.18.1"
assert_cmd_output "pnpm --version" "8.6.7"
assert_cmd_output "python --version" "Python 3.11.8"
# Bazel's Python launcher requires a system installation of python3.
assert_cmd_output "python_tool" "python_tool version 0.0.1" ":$(dirname "$(which python3)")"

#### Toolchains ####

[[ -d "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/cc_toolchain" ]]
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/jdk/bin/java --version" "openjdk 17.0.11 2024-04-16 LTS"
assert_cmd_output "$build_workspace_directory/bazel-out/bazel_env-opt/bin/bazel_env/toolchains/python/bin/python3 --version" "Python 3.11.8"
