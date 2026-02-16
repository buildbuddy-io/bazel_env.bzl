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

if [[ "$subcommand" == "print-path" ]]; then
  echo "$BUILD_WORKSPACE_DIRECTORY/{{bin_dir}}"
  exit 0
fi
if [[ "$subcommand" != "status" ]]; then
  fail_with_usage
fi

TOOLS_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/{{name}}/bin" && pwd -P)"
BAZEL_ENV_ROOT="$(dirname "$TOOLS_BIN_DIR")"

cd "$BUILD_WORKSPACE_DIRECTORY"

cat << 'EOF'

====== {{name}} ======

EOF

SYMLINK_NAME=".{{name}}"
rm -f "$SYMLINK_NAME"
ln -s "$BAZEL_ENV_ROOT" "$SYMLINK_NAME"


if [[ {{has_tools}} == True ]]; then

if type direnv >/dev/null 2>/dev/null; then
    echo "✅ direnv is installed"
else
    echo "❌ direnv is not installed. Please follow the instructions at https://direnv.net/docs/installation.html."
fi

if type {{unique_name_tool}} >/dev/null 2>/dev/null; then
    echo "✅ direnv added ./$SYMLINK_NAME/bin to PATH"
else
    echo "❌ {{name}}'s bin directory is not in PATH. Please follow these steps:"

    step_num=1
    
    if [[ -z "${DIRENV_DIR:-}" ]]; then
      echo ""
      echo "$step_num. Enable direnv's shell hook as described in https://direnv.net/docs/hook.html."
      step_num=$((step_num + 1))
    fi

    if ! grep -qE '[[:<:]]bazel_env[[:>:]]' .envrc 2>/dev/null; then
      echo ""
      if [[ -f .envrc ]]; then
        echo "$step_num. Add the following content to your existing .envrc file:"
      else
        echo "$step_num. Create a .envrc file next to your MODULE.bazel file with this content:"
      fi
      cat << EOF

watch_file $SYMLINK_NAME/bin
PATH_add $SYMLINK_NAME/bin
if [[ ! -d $SYMLINK_NAME/bin ]]; then
  log_error "ERROR[bazel_env.bzl]: Run 'bazel run {{label}}' to regenerate $SYMLINK_NAME/bin"
fi
EOF
      step_num=$((step_num + 1))
    fi

    echo ""
    echo "$step_num. Run 'direnv allow' to allowlist your .envrc file."

    if [[ -f .gitignore ]] && ! grep -q "$SYMLINK_NAME" .gitignore; then
        echo ""
        echo "ℹ️  Recommended: Add '$SYMLINK_NAME' to your .gitignore file."
    fi
    
    exit 1
fi

cleaned=0
for f in "$TOOLS_BIN_DIR"/*;
do
  if basename "$f" | grep -q -v '{{tools_regex}}'; then
    rm -rf ./"$f"
    cleaned=1
  fi
done

if [[ $cleaned == 1 ]]; then
cat << 'EOF'
✅ Cleaned up stale tools
EOF
fi


cat << 'EOF'

Tools available in PATH:
{{tools}}

EOF
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
