#!/usr/bin/env bash

set -euo pipefail

cd "$BUILD_WORKSPACE_DIRECTORY"

cat << 'EOF'

====== {{name}} ======

EOF

if [[ {{has_tools}} == True ]]; then

if type direnv >/dev/null 2>/dev/null; then
    echo "✔ direnv is installed"
else
    echo "⚠️ direnv is not installed. Please follow the setup instructions at https://direnv.net."
    exit 1
fi

if type {{unique_name_tool}} >/dev/null 2>/dev/null; then
    echo "✔ direnv added {{bin_dir}} to PATH"
else
    cat << 'EOF'
⚠️ {{name}}'s bin directory is not in PATH. Please add the following snippet to a .envrc file next to your MODULE.bazel file:

    PATH_add {{bin_dir}}

Then allowlist it with 'direnv allow .envrc'.
EOF
    exit 1
fi

cleaned=0
for f in '{{bin_dir}}'/*;
do
  if basename "$f" | grep -q -v '{{tools_regex}}'; then
    rm -rf ./"$f"
    cleaned=1
  fi
done

if [[ $cleaned == 1 ]]; then
cat << 'EOF'
✔ Cleaned up stale tools
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
