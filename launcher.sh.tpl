#!/usr/bin/env bash

set -euo pipefail

# Taken from
# https://github.com/bazelbuild/bazel/blob/73b0faff39ed435b3cbeb09c93185b155fbd3e09/scripts/bazel-complete-template.bash#L84C1-L99C2.
_bazel__get_workspace_path() {
  local workspace=$PWD
  while true; do
    if [ -f "${workspace}/WORKSPACE" ] || \
       [ -f "${workspace}/WORKSPACE.bazel" ] || \
       [ -f "${workspace}/MODULE.bazel" ] || \
       [ -f "${workspace}/REPO.bazel" ]; then
      break
    elif [ -z "$workspace" ] || [ "$workspace" = "/" ]; then
      workspace=$PWD
      break;
    fi
    workspace=${workspace%/*}
  done
  echo "$workspace"
}

case "${BASH_SOURCE[0]}" in
  /*) own_path="${BASH_SOURCE[0]}" ;;
  *) own_path="$PWD/${BASH_SOURCE[0]}" ;;
esac
own_dir="$(dirname "$own_path")"
own_name="$(basename "$own_path")"
if ! grep -q -F "$own_name" "$own_dir/_all_tools.txt"; then
  echo "ERROR: $own_name has been removed from bazel_env, run 'bazel run {{bazel_env_label}}' to remove it from PATH." >&2
  exit 1
fi

workspace_path="$(_bazel__get_workspace_path)"
lock_file="$workspace_path/bazel_env.lock"

if [[ ! -f "$lock_file" ]]; then
  touch "$lock_file"
fi

files_to_watch=()

if [[ -f "${own_dir}/__common_watch_dirs.txt" ]]; then
  for dir in $(cat "${own_dir}/__common_watch_dirs.txt"); do
    for file in $(find "$workspace_path/$dir" -type f); do
      files_to_watch+=("$file")
    done
  done
fi

if [[ -f "${own_dir}/__common_watch_files.txt" ]]; then
  for file in $(cat "${own_dir}/__common_watch_files.txt"); do
    files_to_watch+=("$workspace_path/$file")
  done
fi

if [[ -f "${own_dir}/_${own_name}_watch_dirs.txt" ]]; then
  for dir in $(cat "${own_dir}/_${own_name}_watch_dirs.txt"); do
    for file in $(find "$workspace_path/$dir" -type f); do
      files_to_watch+=("$file")
    done
  done
fi

if [[ -f "${own_dir}/_${own_name}_watch_files.txt" ]]; then
  for file in $(cat "${own_dir}/_${own_name}_watch_files.txt"); do
    files_to_watch+=("$workspace_path/$file")
  done
fi

if grep -F -f <(printf "%s\n" "${files_to_watch[@]}") "$lock_file" | sha256sum -c --status -; then
  rebuild_env=False
else
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT INT TERM
  grep -vF -f <(printf "%s\n" "${files_to_watch[@]}") "$lock_file" > "$tmp" || true
  sha256sum "${files_to_watch[@]}" >> "$tmp"
  mv "$tmp" "$lock_file"
  rebuild_env=True
fi

if [[ $rebuild_env == True && "${BAZEL_ENV_INTERNAL_EXEC:-False}" != True ]]; then
  "${BAZEL:-bazel}" build {{bazel_env_label}}
  BAZEL_ENV_INTERNAL_EXEC=True exec "$own_path" "$@"
fi

# Set up an environment similar to 'bazel run' to support tools designed to be
# run with it.
# Since tools may cd into BUILD_WORKSPACE_DIRECTORY, ensure that RUNFILES_DIR
# is absolute.
export RUNFILES_DIR="${own_path}.runfiles"
# Also set legacy RUNFILES variables for compatibility with runfiles logic that
# predates the runfiles library (e.g. in rules_js).
export RUNFILES="${RUNFILES_DIR}"
export JAVA_RUNFILES="${RUNFILES_DIR}"
export PYTHON_RUNFILES="${RUNFILES_DIR}"
# Let rules_js' js_binary work by not having it try to cd into BINDIR.
export JS_BINARY__NO_CD_BINDIR=1
# Environment of the executable target.
{{extra_env}}

BUILD_WORKING_DIRECTORY="$(pwd)"
export BUILD_WORKING_DIRECTORY

BUILD_WORKSPACE_DIRECTORY="$workspace_path"
export BUILD_WORKSPACE_DIRECTORY

case "{{rlocation_path}}" in
  /*) bin_path="{{rlocation_path}}" ;;
  *) bin_path="$RUNFILES_DIR/{{rlocation_path}}" ;;
esac
exec "$bin_path" "$@"
