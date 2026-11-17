#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
id="run-$(date +%Y%m%d-%H%M%S)"
if [ "$#" -eq 0 ]; then
  run='"all"'
else
  run="{"
  for t in "$@"; do run="$run \"$t\","; done
  run="$run }"
fi
cat > RavenquillExpedition_Dev/Inbox.lua <<EOF
RQDevInbox = { id = "$id", run = $run }
EOF
echo "$id"
