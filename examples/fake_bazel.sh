#!/usr/bin/env bash

set -euo pipefail

if [[ "$*" != "run //:bazel_env -- update-symlink" ]]; then
  echo "Expected arguments to be 'run //:bazel_env -- update-symlink', got '$*'" >&2
  exit 1
fi

echo "Fake Bazel stdout"
echo "Fake Bazel stderr" >&2
echo "1" >> "${FAKE_BAZEL_MARKER_FILE:-/dev/null}"

# Record whether a given file existed at the time of the invocation.
if [[ -n "${FAKE_BAZEL_OBSERVED_FILE:-}" ]]; then
  if [[ -e "$FAKE_BAZEL_OBSERVED_FILE" ]]; then
    echo "present" >> "${FAKE_BAZEL_OBSERVATION_FILE:-/dev/null}"
  else
    echo "absent" >> "${FAKE_BAZEL_OBSERVATION_FILE:-/dev/null}"
  fi
fi

# Imitate the run phase of 'bazel run'.
if [[ -n "${FAKE_BAZEL_RUN_SCRIPT:-}" ]]; then
  BUILD_WORKSPACE_DIRECTORY="$PWD" "$FAKE_BAZEL_RUN_SCRIPT" update-symlink
fi

exit "${FAKE_BAZEL_EXIT_CODE:-0}"
