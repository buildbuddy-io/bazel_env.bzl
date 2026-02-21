#!/usr/bin/env bash
set -euo pipefail
# $1 is the rlocationpath of location_test_data.txt, expanded by the aspect from $(rlocationpath).
if [[ -f "$RUNFILES_DIR/$1" ]]; then
  echo "found: $1"
else
  echo "not found at $RUNFILES_DIR/$1" >&2
  exit 1
fi
