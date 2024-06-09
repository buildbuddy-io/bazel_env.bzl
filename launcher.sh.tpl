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

log_colored() {
  if [[ -t 2 ]]; then
    local -r colored="$1"
    local -r normal="\e[m"
  else
    local -r colored=""
    local -r normal=""
  fi
  printf "${colored}%s${normal}\n" "$2" >&2
}

error_color="\e[38;5;1m"
warning_color="\e[38;5;3m"

log_error() {
  log_colored "$error_color" "ERROR[bazel_env.bzl]: $1"
}

log_warning() {
  log_colored "$warning_color" "WARNING[bazel_env.bzl]: $1"
}

case "${BASH_SOURCE[0]}" in
  /*) own_path="${BASH_SOURCE[0]}" ;;
  *) own_path="$PWD/${BASH_SOURCE[0]}" ;;
esac
own_dir="$(dirname "$own_path")"
own_name="$(basename "$own_path")"
if ! grep -q -F "$own_name" "$own_dir/_all_tools.txt"; then
  log_error "'$own_name' has been removed from '{{bazel_env_label}}', run 'bazel run {{bazel_env_label}}' to remove it from PATH."
  exit 1
fi

if [[ {{update_when_run}} != no && "${BAZEL_ENV_INTERNAL_EXEC:-False}" != True ]]; then
  if [[ -t 2 ]]; then
    color=yes
    warning_prefix="\e[38;5;3m>\e[m "
  else
    color=no
    warning_prefix="> "
  fi
  # Minimize latency (this tool may be run by another tool or even an IDE) by
  # not waiting for concurrent Bazel commands and also avoid thrashing the
  # analysis cache, which could silently slow down subsequent Bazel commands.
  if ! bazel_output=$(\
         "${BAZEL:-bazel}" \
           --noblock_for_lock \
         build \
           --color=$color \
           --noallow_analysis_cache_discard \
           {{bazel_env_label}} 2>&1); then
    msg="Failed to keep '$own_name' up-to-date with 'bazel build {{bazel_env_label}}':"
    if [[ {{update_when_run}} == auto ]]; then
      log_warning "$msg"
    else
      log_error "$msg"
    fi
    echo "$bazel_output" | while IFS= read -r line; do printf "$warning_prefix%s\n" "$line" >&2; done
    if [[ {{update_when_run}} == yes ]]; then
      # Use an abnormal exit code (SIGABRT) that can't be confused with a
      # legitimate exit code of the wrapped tool.
      exit 134
    fi
  fi
  # Re-exec the script, which might have been replaced by Bazel.
  BAZEL_ENV_INTERNAL_EXEC=True exec "$own_path" "$@"
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
