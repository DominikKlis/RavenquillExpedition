#!/usr/bin/env bash
# Asks the game to run in-game tests on the next /reload: writes RavenquillExpedition_Dev/Inbox.lua with a new id.
#   bash scripts/dev-run.sh                 all tests
#   bash scripts/dev-run.sh comm ui.overview   tests by name or name prefix
# Prints the id. In game: /reload (the tests run ~5 s after login), then /reload again when the chat says so
# (ReloadUI() is protected on Forever: an addon can't save its results itself). Then: bash scripts/devlog.sh --wait <id>
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
-- Written by the developer's tools (Claude Code): what to run on the next login. Read by Test.lua.
-- RQDevInbox = { id = "<unique>", run = "all" | { "test name", ... } }
-- A run happens once per id (the id is stored before the run). ReloadUI() is protected on Forever, so the
-- player types /reload afterwards to save the results.
RQDevInbox = { id = "$id", run = $run }
EOF
echo "$id"
