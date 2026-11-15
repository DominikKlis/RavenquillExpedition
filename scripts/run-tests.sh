#!/usr/bin/env bash
# Runs every offline test harness (*/dev/harness*.lua) from the repository root.
# Usage: scripts/run-tests.sh [lua-binary]   (default: lua)
# RQ_SKIP: space-separated addon folders to skip (CI skips CraftAdvisor, whose harnesses still use
# machine-specific absolute paths and a local SimGear download).
set -u
LUA="${1:-lua}"
cd "$(dirname "$0")/.."
status=0
for h in */dev/harness*.lua; do
  skip=""
  for s in ${RQ_SKIP:-}; do [ "${h%%/*}" = "$s" ] && skip=1; done
  if [ -n "$skip" ]; then printf '%-55s skipped (RQ_SKIP)
' "$h"; continue; fi
  out="$("$LUA" "$h" 2>&1)"; code=$?
  printf '%-55s exit %d  %s\n' "$h" "$code" "$(printf '%s\n' "$out" | tail -n 1)"
  if [ "$code" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E 'FAIL|ERROR|error' | head -n 20
    status=1
  fi
done
exit "$status"
