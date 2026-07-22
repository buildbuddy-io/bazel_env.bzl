#!/usr/bin/env bash

set -euo pipefail

function fail_with_usage() {
  echo "Usage: bazel run {{label}} [status|print-path]" >&2
  exit 1
}

if [[ $# -gt 1 ]]; then
  fail_with_usage
fi

if [[ $# -eq 1 ]]; then
  subcommand="$1"
else
  subcommand="status"
fi

if [[ "$subcommand" != "status" && "$subcommand" != "print-path" ]]; then
  fail_with_usage
fi

# Resolve the physical location of the bin directory relative to this script
# and expose it through a symlink in the package of the bazel_env target. The
# symlink provides a stable path that works with any --symlink_prefix setting,
# including one that suppresses the bazel-* convenience symlinks.
TOOLS_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/{{name}}/bin" && pwd -P)"
BAZEL_ENV_ROOT="$(dirname "$TOOLS_BIN_DIR")"

cd "$BUILD_WORKSPACE_DIRECTORY/{{package_path}}"

SYMLINK_NAME="{{symlink_name}}"

if [[ -e "$SYMLINK_NAME" && ! -L "$SYMLINK_NAME" ]]; then
  echo "Error: '$SYMLINK_NAME' exists and is not a symlink. Aborting to prevent data loss." >&2
  exit 1
fi

# Only touch the symlink when its target is out of date so that repeated runs
# do not update its timestamp.
if [[ "$(readlink "$SYMLINK_NAME" 2>/dev/null)" != "$BAZEL_ENV_ROOT" ]]; then
  rm -f "$SYMLINK_NAME"
  ln -s "$BAZEL_ENV_ROOT" "$SYMLINK_NAME"
fi

if [[ "$subcommand" == "print-path" ]]; then
  echo "$PWD/$SYMLINK_NAME/bin"
  exit 0
fi

cat << 'EOF'

====== {{name}} ======

EOF

if [[ {{has_tools}} == True ]]; then

if type direnv >/dev/null 2>/dev/null; then
    echo "✅ direnv is installed"
else
    echo "❌ direnv is not installed. Please follow the instructions at https://direnv.net/docs/installation.html."
fi

if type {{unique_name_tool}} >/dev/null 2>/dev/null; then
    echo "✅ direnv added ./{{symlink_path}}/bin to PATH"
else
    echo "❌ {{name}}'s bin directory is not in PATH. Please follow these steps:"

    step_num=1

    if [[ -z "${DIRENV_DIR:-}" ]]; then
      echo ""
      echo "$step_num. Enable direnv's shell hook as described in https://direnv.net/docs/hook.html."
      step_num=$((step_num + 1))
    fi

    # The .envrc file lives in the workspace root so that direnv activates the
    # environment in the entire workspace; the paths in it are relative to the
    # workspace root and thus include the package path.
    if ! grep -qE '[[:<:]]bazel_env[[:>:]]' "$BUILD_WORKSPACE_DIRECTORY/.envrc" 2>/dev/null; then
      echo ""
      if [[ -f "$BUILD_WORKSPACE_DIRECTORY/.envrc" ]]; then
        echo "$step_num. Add the following content to your existing .envrc file:"
      else
        echo "$step_num. Create a .envrc file next to your MODULE.bazel file with this content:"
      fi
      cat << 'EOF'

watch_file {{symlink_path}}/bin
PATH_add {{symlink_path}}/bin
if [[ ! -d {{symlink_path}}/bin ]]; then
  log_error "ERROR[bazel_env.bzl]: Run 'bazel run {{label}}' to regenerate {{symlink_path}}/bin"
fi
EOF
      step_num=$((step_num + 1))
    fi

    echo ""
    echo "$step_num. Run 'direnv allow' to allowlist your .envrc file."

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if ! git check-ignore -q "$SYMLINK_NAME" 2>/dev/null; then
          echo ""
          echo "ℹ️  Recommended: Add '$SYMLINK_NAME' to your .gitignore file."
      fi
    fi

    exit 1
fi

cat << 'EOF'

Tools available in PATH:
{{tools}}

EOF

# The bazel-out path only exists if convenience symlinks are enabled via
# --symlink_prefix.
if [[ -d "$BUILD_WORKSPACE_DIRECTORY/{{bin_dir}}" ]]; then
  echo "ℹ️  The bin directory is also reachable at {{bin_dir}} relative to the workspace root."
  echo ""
fi
fi

if [[ {{has_toolchains}} == True ]]; then
cat << 'EOF'
Toolchains available at stable relative paths:
{{toolchains}}

EOF
fi

set +e
# $$ is bash's PID, $PPID is whatever called bazel
# this might be bazelisk or the user's interactive shell
parent_name=$(ps -p $PPID -o comm= | tr -d ' ')
if [[ "$parent_name" == *bazel* ]]; then
  great_parent_pid=$(ps -o ppid= -p $PPID | tr -d ' ')
  parent_name=$(ps -p "$great_parent_pid" -o comm= | tr -d ' ')
fi
set -e
if [[ "$parent_name" == *zsh* ]]; then
  echo "⚠️  Remember to run 'rehash' in zsh to update the locations of binaries on the PATH."
elif [[ "$parent_name" == *bash* ]]; then
  echo "⚠️  Remember to run 'hash -r' in bash to update the locations of binaries on the PATH."
fi
