#!/usr/bin/env bash

# Based on
# https://github.com/bazel-contrib/rules-template/blob/a71e0a7624aa6e6fcde3d6623d3cb135fffbe28a/.github/workflows/release_prep.sh#L1

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="bazel_env.bzl-${TAG:1}"
ARCHIVE="bazel_env.bzl-$TAG.tar.gz"
git archive --prefix=${PREFIX}/ ${TAG} -o $ARCHIVE

cat << 'EOF'
Add to your \`MODULE.bazel\` file:

```starlark
bazel_dep(name = "bazel_env.bzl", version = "${TAG:1}")
```
EOF
