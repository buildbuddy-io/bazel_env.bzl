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

# Simulate a 'bazel run' environment. Since tools may cd into
case "${BASH_SOURCE[0]}" in
  /*) own_path="${BASH_SOURCE[0]}" ;;
  *) own_path="$PWD/${BASH_SOURCE[0]}" ;;
esac
export RUNFILES_DIR="${own_path}.runfiles"

# Set up an environment similar to 'bazel run' to support tools designed to be
# run with it.
BUILD_WORKING_DIRECTORY="$(pwd)"
export BUILD_WORKING_DIRECTORY

BUILD_WORKSPACE_DIRECTORY="$(_bazel__get_workspace_path)"
export BUILD_WORKSPACE_DIRECTORY

case "{{rlocation_path}}" in
  /*) bin_path="{{rlocation_path}}" ;;
  *) bin_path="$RUNFILES_DIR/{{rlocation_path}}" ;;
esac
exec "$bin_path" "$@"
