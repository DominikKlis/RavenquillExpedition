#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
WOW="${WOW_DIR:-../..}"
sv="$(ls -t "$WOW"/WTF/Account/*/SavedVariables/RavenquillExpedition_Dev.lua 2>/dev/null | head -n 1)"
if [ -z "$sv" ]; then
  echo "No RavenquillExpedition_Dev SavedVariables under $WOW/WTF/Account/*/SavedVariables (set WOW_DIR?)."
  echo "Enable the Dev addon, restart the game once, then /reload."
  exit 1
fi
svdir="$(dirname "$sv")"
if [ "${1:-}" = "--wait" ]; then
  id="$2"
  for _ in $(seq 1 72); do
    if lua scripts/read-devlog.lua --sv "$sv" --run "$id" 2>/dev/null | grep -q "^== test run $id .*passed"; then break; fi
    sleep 5
  done
  exec lua scripts/read-devlog.lua --sv "$sv" --run "$id" --bugs "$svdir/!BugGrabber.lua" --framexml "$WOW/Logs/FrameXML.log"
fi
exec lua scripts/read-devlog.lua --sv "$sv" --bugs "$svdir/!BugGrabber.lua" --framexml "$WOW/Logs/FrameXML.log" "$@"
