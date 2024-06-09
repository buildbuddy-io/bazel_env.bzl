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

# Set up an environment similar to 'bazel run' to support tools designed to be
# run with it.
# Since tools may cd into BUILD_WORKSPACE_DIRECTORY, ensure that RUNFILES_DIR
# is absolute.
export RUNFILES_DIR="${own_path}.runfiles"

BUILD_WORKING_DIRECTORY="$(pwd)"
export BUILD_WORKING_DIRECTORY

BUILD_WORKSPACE_DIRECTORY="$(_bazel__get_workspace_path)"
export BUILD_WORKSPACE_DIRECTORY

case "{{rlocation_path}}" in
  /*) bin_path="{{rlocation_path}}" ;;
  *) bin_path="$RUNFILES_DIR/{{rlocation_path}}" ;;
esac
exec "$bin_path" "$@"
