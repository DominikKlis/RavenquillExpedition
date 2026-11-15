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
- Tests: `bash scripts/run-tests.sh` (Lua 5.4). CI sets `RQ_SKIP=RavenquillExpedition_CraftAdvisor` because those
  harnesses are not portable yet (absolute paths, local SimGear download); making them portable is open work. Fix bugs with a test that fails without the fix.
- Options go into the `/rq` overview, not chat commands. Player-facing text in English and German locale files.
- Say what you verified (with file:line or test output) and what you could not test, e.g. anything in game.
