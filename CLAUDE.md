# Ravenquill Expedition: notes for Claude

A WoW Forever (interface 16001) addon suite; the repository may be the user's `Interface\AddOns` folder itself.
Read `README.md` and `CONTRIBUTING.md` before changing anything; they are the rules for this repo.

- **Never run `git clean -x`/`-X`** and never delete untracked folders in the repo root: they are the user's
  other addons (the root `.gitignore` tracks only the suite).
- **Pushing changes to `.github/workflows/` needs the `workflow` permission** on the gh login. If a push is
  rejected with "without `workflow` scope", ask the user to run
  `gh auth refresh -h github.com -s workflow` themselves (it is interactive), then push again.
- Releases happen by pushing a `v*` tag (see CONTRIBUTING.md, "Releasing"). Only push a tag when the user asks:
  it publishes to CurseForge.
- `RavenquillExpedition_CraftAdvisor` must never go into a public zip (its `NOTICE.txt`).
- Tests: `bash scripts/run-tests.sh` (Lua 5.4): harnesses, luacheck (if installed), architecture scorecard. A metric
  that gets worse than `scripts/arch-baseline.lua` fails the run; after an improvement run it with `RQ_UPDATE=1`.
  Never re-record a `harness_compat.lua` golden to make a test pass: it guards wire bytes and SavedVariables.
  Fix bugs with a test that fails without the fix.
- Shipped code is Lua 5.1 (the game); tests run on 5.4. No `//`, `goto`, bit operators, `table.unpack` in addons.
- A new file in a `.toc` (or a new addon folder) needs a full game restart, not just `/reload`.
- New modules: start from `templates/Module/`, API in `docs/module-api.md`, sync rules in `docs/sync.md`. Modules never
  call `SendAddonMessage`; they use `mod:NewChannel` (the core paces all modules together).
- In-game checks (`docs/dev-bridge.md`): `bash scripts/dev-run.sh [tests]` queues in-game tests; ask the user to
  `/reload` (twice: the run, then saving - `ReloadUI()` is protected on Forever), then `bash scripts/devlog.sh --wait <id>`
  shows results, the log, BugGrabber errors and FrameXML.log. Don't edit addon files while the user is logging in.
- Options go into the `/rq` overview, not chat commands. Player-facing text in English and German locale files.
- Say what you verified (with file:line or test output) and what you could not test, e.g. anything in game.
