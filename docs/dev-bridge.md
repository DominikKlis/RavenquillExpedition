# Dev bridge: seeing what happened in game without copying anything out

`RavenquillExpedition_Dev` is a developer-only addon (never released; `scripts/package.ps1` refuses it). It writes
what the suite does into its SavedVariables, which the game saves to disk on every `/reload` and logout. The
scripts in `scripts/` read that file, so a developer (or Claude Code) can see the log, test results and errors
without anyone pasting chat output.

## Setup

1. Have the folder in your AddOns (`scripts/link-addons.ps1 -Dev` when you work from a clone).
2. **Restart the game once** (a new addon folder or a new `.toc` file is only seen after a full restart, not after `/reload`).
3. Enable "Ravenquill Expedition: Dev" in the character's AddOns list.

## What it records

- `RavenquillExpedition:Trace(cat, msg, data)` calls. The core traces its sync lane (`comm.tx`, `comm.echo`,
  `comm.lost`, `comm.rx`, `comm.slow`, `comm.foreign`, `comm.drop`) and every error that goes through `GS:Call`
  (`err`). Without the Dev addon, `Trace` is a no-op.
- Every suite addon message sent or heard (`wire.tx` / `wire.rx`, prefixes RQE1, RQEMap1, GCAdv1).
- The suite's own chat lines (`chat`: lines that start with "Ravenquill Expedition"), so existing diagnostic output lands on disk unchanged. Other chat lines (whispers, guild chat) only with the switch "Also log all other chat lines" in `/rq dev`, off by default.
- One session header per load: client build, core and module versions, character and guild.

The log is a ring of the newest 2000 entries; messages are cut to 120 bytes and secret values are never stored.
Turn it off or clear it in `/rq dev`.

## Reading it

```bash
bash scripts/devlog.sh              # session, last 80 entries, last test run, BugGrabber errors, FrameXML.log lines
bash scripts/devlog.sh --cat comm   # only sync entries
bash scripts/devlog.sh --runs       # every saved test run
```

Errors come from BugGrabber's own SavedVariables (`!BugGrabber.lua`, filtered to Ravenquill) and load errors from
`Logs/FrameXML.log`. The account folder is found at run time (the newest Dev SavedVariables); no account name is
stored in the repository.

## In-game tests through the inbox

`RavenquillExpedition_Dev/Tests.lua` holds tests that need the real client: the guild echo of a sync message, the
`/rq` window, each module's options, map test pins, the Craft Advisor window, SavedVariables shapes.

```bash
id=$(bash scripts/dev-run.sh)           # or: bash scripts/dev-run.sh comm ui.overview
# in game: /reload, wait for the chat line "inbox <id>: n/m passed", then /reload again to save the results
bash scripts/devlog.sh --wait "$id"
```

`dev-run.sh` writes `RavenquillExpedition_Dev/Inbox.lua` with a new id. On login the Dev addon stores that id
first, then runs the tests; the same id never runs twice. `ReloadUI()` is protected on Forever (an addon calling
it from a timer gets ADDON_ACTION_BLOCKED, verified in game), so the second `/reload` is the player's. Tests can also be
started by hand from `/rq dev` ("Run all tests"), followed by a `/reload` to save.

Writing a test (`Dev:Register(name, fn, timeoutSeconds)`):

```lua
Dev:Register("mymodule.window", function(t)
  MyModule:Open()
  t:after(1, function()                 -- wait for the client
    t:ok(MyModuleFrame:IsShown(), "window shown")
    t:done()
  end)
end, 10)
```

Keep in-game tests to what the offline harnesses (`*/dev/harness*.lua`) can't prove. Each test that sends a guild
message costs one of the client's sync tokens (3, then 1 per 5 s).
