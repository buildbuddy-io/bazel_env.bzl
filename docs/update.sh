#!/usr/bin/env bash

set -euo pipefail

cd "$BUILD_WORKSPACE_DIRECTORY"

bazel build $(bazel query 'kind(stardoc, //docs:all)')

cp -fv bazel-bin/docs/bazel_env.md docs-gen/bazel_env.md
