#!/usr/bin/env bash
# Runs every offline test harness (*/dev/harness*.lua) from the repository root.
# Usage: scripts/run-tests.sh [lua-binary]   (default: lua)
set -u
LUA="${1:-lua}"
cd "$(dirname "$0")/.."
status=0
for h in */dev/harness*.lua; do
  out="$("$LUA" "$h" 2>&1)"; code=$?
  printf '%-55s exit %d  %s\n' "$h" "$code" "$(printf '%s\n' "$out" | tail -n 1)"
  if [ "$code" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E 'FAIL|ERROR' | head -n 20
    status=1
  fi
done
exit "$status"
