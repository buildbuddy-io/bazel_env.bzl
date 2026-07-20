#!/usr/bin/env bash

set -euo pipefail

if [[ "${*: -1}" != "//:bazel_env" ]]; then
  echo "Expected last argument to be //:bazel_env, got ${*: -1}" >&2
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

exit "${FAKE_BAZEL_EXIT_CODE:-0}"
