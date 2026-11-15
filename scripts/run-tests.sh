#!/usr/bin/env bash
# Runs every offline test harness (*/dev/harness*.lua), then luacheck (when installed), then the architecture
# scorecard (scripts/check-architecture.lua). Exit 1 if any part fails.
# Usage: scripts/run-tests.sh [lua-binary]   (default: lua)
#   RQ_SKIP: space-separated addon folders to skip.
#   RQ_VERBOSE=1: print every harness's full output.
#   RQ_UPDATE=1: tighten scripts/arch-baseline.lua for every metric that improved (end of a rework stage).
set -u
LUA="${1:-lua}"
cd "$(dirname "$0")/.."
status=0
total_pass=0; total_fail=0; total_skip=0; skipnames=""
printf '%-55s %6s %6s %6s\n' "harness" "passed" "failed" "skipped"
for h in */dev/harness*.lua; do
  skip=""
  for s in ${RQ_SKIP:-}; do [ "${h%%/*}" = "$s" ] && skip=1; done
  if [ -n "$skip" ]; then printf '%-55s skipped (RQ_SKIP)\n' "$h"; continue; fi
  out="$("$LUA" "$h" 2>&1)"; code=$?
  counts="$(printf '%s\n' "$out" | grep -oE '[0-9]+ passed, [0-9]+ failed(, [0-9]+ skipped)?' | tail -n 1)"
  p="$(printf '%s' "$counts" | sed -nE 's/^([0-9]+) passed.*/\1/p')"; p="${p:-0}"
  f="$(printf '%s' "$counts" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"; f="${f:-0}"
  k="$(printf '%s' "$counts" | sed -nE 's/.* ([0-9]+) skipped/\1/p')"; k="${k:-0}"
  printf '%-55s %6s %6s %6s%s\n' "$h" "$p" "$f" "$k" "$([ "$code" -ne 0 ] && echo "  (exit $code)")"
  [ -n "${RQ_VERBOSE:-}" ] && printf '%s\n' "$out"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '    %s\n' "$line"
    name="$(printf '%s\n' "$line" | awk '{ sub(/^SKIP /, ""); i = index($0, ": "); print (i > 0 ? substr($0, 1, i - 1) : $0) }' | tr ' ' '-')"
    skipnames="${skipnames:+$skipnames,}$name"
  done <<< "$(printf '%s\n' "$out" | grep -E '^SKIP ')"
  if [ "$code" -ne 0 ] || [ -z "$counts" ] || [ "$f" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E 'FAIL|ERROR|error' | head -n 20
    [ -z "$counts" ] && echo "    (no 'N passed, N failed' line found)"
    status=1
  fi
  total_pass=$((total_pass + p)); total_fail=$((total_fail + f)); total_skip=$((total_skip + k))
done
printf '%-55s %6s %6s %6s\n' "TOTAL" "$total_pass" "$total_fail" "$total_skip"
echo

lc_args=()
if command -v luacheck >/dev/null 2>&1; then
  lc_dirs=(RavenquillExpedition*/ scripts)
  [ -d templates ] && lc_dirs+=(templates)
  lc_out="$(luacheck "${lc_dirs[@]}" --codes --formatter plain --no-color 2>&1)"
  warnings="$(printf '%s\n' "$lc_out" | grep -cE ':[0-9]+:[0-9]+: \(W')"
  errors="$(printf '%s\n' "$lc_out" | grep -cE ':[0-9]+:[0-9]+: \((E|W0[0-9][0-9]|W1[0-9][0-9])\)')"
  echo "luacheck: $warnings warnings, $errors errors (syntax / undefined globals)"
  if [ "$errors" -ne 0 ]; then
    printf '%s\n' "$lc_out" | grep -E ':[0-9]+:[0-9]+: \((E|W0[0-9][0-9]|W1[0-9][0-9])\)' | head -n 30
    status=1
  fi
  lc_args=(--luacheck "$warnings")
else
  echo "luacheck: not installed (n/a)"
fi
echo

"$LUA" scripts/check-architecture.lua ${RQ_UPDATE:+--update} --checks "$total_pass" --skips "$total_skip" --skipnames "$skipnames" "${lc_args[@]}" || status=1
exit "$status"
