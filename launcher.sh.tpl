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

# Derive the source workspace from the script's own path.
# The script lives in the output base (which can be anywhere), but is invoked
# through the convenience symlink at <workspace>/bazel-out/..., so we can
# extract the workspace by finding the parent of 'bazel-out' in the invocation path.
# This is used for watch_dirs to ensure we watch the correct source files
# regardless of where the tool is run from.
_bazel__get_source_workspace_path() {
  local script_path="$1"
  # Extract everything before /bazel-out/
  if [[ "$script_path" == */bazel-out/* ]]; then
    local workspace="${script_path%%/bazel-out/*}"
    # Remove trailing /. or / if present (can occur with ./bazel-out/...)
    workspace="${workspace%/.}"
    workspace="${workspace%/}"
    echo "$workspace"
  else
    # Fallback: not in a bazel-out directory (shouldn't happen)
    echo ""
  fi
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
source_workspace_path="$(_bazel__get_source_workspace_path "$own_path")"
files_to_watch=()

# Use source_workspace_path for watch_dirs to ensure we watch the correct
# source files regardless of where the tool is run from.
# Fall back to workspace_path if source_workspace_path is empty.
watch_base="${source_workspace_path:-$workspace_path}"

if [[ -f "${own_dir}/__common_watch_dirs.txt" ]]; then
  for dir in $(cat "${own_dir}/__common_watch_dirs.txt"); do
    if [[ -d "$watch_base/$dir" ]]; then
      for file in $(find "$watch_base/$dir" -type f); do
        files_to_watch+=("$file")
      done
    fi
  done
fi

if [[ -f "${own_dir}/__common_watch_files.txt" ]]; then
  for file in $(cat "${own_dir}/__common_watch_files.txt"); do
    if [[ -f "$watch_base/$file" ]]; then
      files_to_watch+=("$watch_base/$file")
    fi
  done
fi

if [[ -f "${own_dir}/_${own_name}_watch_dirs.txt" ]]; then
  for dir in $(cat "${own_dir}/_${own_name}_watch_dirs.txt"); do
    if [[ -d "$watch_base/$dir" ]]; then
      for file in $(find "$watch_base/$dir" -type f); do
        files_to_watch+=("$file")
      done
    fi
  done
fi

if [[ -f "${own_dir}/_${own_name}_watch_files.txt" ]]; then
  for file in $(cat "${own_dir}/_${own_name}_watch_files.txt"); do
    if [[ -f "$watch_base/$file" ]]; then
      files_to_watch+=("$watch_base/$file")
    fi
  done
fi

rebuild_env=False
sha256_cmd="${own_path}.runfiles/{{sha256sum_rlocation_path}}"

if [[ ${#files_to_watch[@]} -gt 0 ]]; then
  lock_file="$watch_base/bazel_env.lock"

  if [[ ! -f "$lock_file" ]]; then
    touch "$lock_file"
  fi

  matched_lines=$(awk '
    NR==FNR { files[$0]=1; next }
    {
      match($0, /^[^ ]+ +/)
      filepath = substr($0, RSTART + RLENGTH)
      if (filepath in files) print
    }
  ' <(printf "%s\n" "${files_to_watch[@]}") "$lock_file" 2>/dev/null || true)

  if [[ -n "$matched_lines" ]]; then
    matched_count=$(echo "$matched_lines" | wc -l)
  else
    matched_count=0
  fi

  if [[ $matched_count -eq ${#files_to_watch[@]} ]]; then
    if echo "$matched_lines" | "$sha256_cmd" -c --status - 2>/dev/null; then
      rebuild_env=False
    else
      rebuild_env=True
    fi
  else
    rebuild_env=True
  fi
fi

if [[ $rebuild_env == True && "${BAZEL_ENV_INTERNAL_EXEC:-False}" != True ]]; then
  echo "Detected changes in watched files, rebuilding bazel_env..." >&2
  if [[ ${#files_to_watch[@]} -gt 0 ]]; then
    echo "Changed files:" >&2
    for file in "${files_to_watch[@]}"; do
      if [[ -f "$file" ]]; then
        matched_line=$(awk -v file="$file" '
          {
            match($0, /^[^ ]+ +/)
            filepath = substr($0, RSTART + RLENGTH)
            if (filepath == file) print
          }
        ' "$lock_file" 2>/dev/null || true)

        if [[ -n "$matched_line" ]]; then
          if ! echo "$matched_line" | "$sha256_cmd" -c --status - 2>/dev/null; then
            echo "  - $file (modified)" >&2
          fi
        else
          echo "  - $file (new)" >&2
        fi
      fi
    done
  fi
  # Run bazel from the source workspace to ensure it can find the WORKSPACE/MODULE file.
  (cd "$watch_base" && "${BAZEL:-bazel}" build {{bazel_env_label}})
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT INT TERM
  awk '
    NR==FNR { files[$0]=1; next }
    {
      match($0, /^[^ ]+ +/)
      filepath = substr($0, RSTART + RLENGTH)
      if (!(filepath in files)) print
    }
  ' <(printf "%s\n" "${files_to_watch[@]}") "$lock_file" > "$tmp" 2>/dev/null || true
  "$sha256_cmd" "${files_to_watch[@]}" >> "$tmp"
  mv "$tmp" "$lock_file"
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
