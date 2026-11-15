#!/usr/bin/env bash
# Reads what the game saved for the suite: the RavenquillExpedition_Dev log and test runs, BugGrabber's errors and
# FrameXML.log, for the account whose Dev SavedVariables changed last. No account name is stored anywhere.
#   bash scripts/devlog.sh                 sessions, last 80 log entries, last test run, errors
#   bash scripts/devlog.sh --runs          every saved test run
#   bash scripts/devlog.sh --cat comm      only log entries whose category starts with "comm"
#   bash scripts/devlog.sh --wait <id>     wait (up to 6 min) until the run <id> is in the file, then print it
# WOW_DIR: the game's _forever_ folder (default: two levels above the AddOns folder this repository lives in or is
# linked into).
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
