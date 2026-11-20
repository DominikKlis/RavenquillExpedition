# Ravenquill Expedition: notes for Claude

A WoW Forever (interface 16001) addon suite. The clone lives outside the game folder; the game loads either the
CurseForge install or this clone, chosen with `scripts/switch-addons.ps1 dev|curseforge` (game closed).
`README.md` lists the addons and the repo layout. These notes are the rules for this repo.

- **Never run `git clean -x`/`-X`** and never delete untracked folders in the repo root: they are the user's
  other addons (the root `.gitignore` tracks only the suite).
- **Pushing changes to `.github/workflows/` needs the `workflow` permission** on the gh login. If a push is
  rejected with "without `workflow` scope", ask the user to run
  `gh auth refresh -h github.com -s workflow` themselves (it is interactive), then push again.
- Releases happen by pushing an annotated `v*` tag (`-alpha` / `-beta` suffix sets the CurseForge release type, the
  tag message is the changelog; the workflow needs the `CF_API_KEY` secret). Only push a tag when the user asks: it
  publishes to CurseForge.
- `RavenquillExpedition_CraftAdvisor` ships. Its recipe data in `Data/` is maintained by hand: no generator, and no
  addon other than Auctionator may be needed at runtime or to build or test it (SimGear only for the optional score
  tests). `dev/harness_data.lua` checks the data.
- Tests: `bash scripts/run-tests.sh [lua-binary]` (Lua 5.4): harnesses, luacheck (if installed), architecture
  scorecard. `RQ_SKIP` skips addon folders, `RQ_VERBOSE=1` prints full harness output. A metric that gets worse than
  `scripts/arch-baseline.lua` fails the run; after an improvement run it with `RQ_UPDATE=1`.
  Never re-record a `harness_compat.lua` golden to make a test pass: it guards wire bytes and SavedVariables.
  Fix bugs with a test that fails without the fix.
- Code health: `lua scripts/health.lua [N]` prints the share of clean functions (cyclomatic complexity <= 10,
  <= 60 lines, nesting <= 4), the maintenance debt (excess over those limits plus files over 500 lines) and the top N
  hotspots. The scorecard ratchets `health_clean_pct`, `health_debt` and `max_fn_complexity`.
- **No comments in the codebase**, anywhere: Lua, shell, PowerShell, YAML, config files, tests and dev tools. Don't
  add any, and don't leave any in code you touch; use clear names instead. The scorecard's `comments` metric enforces
  it. Exempt: `*/libs/` (vendored), `dev/fixtures/compat_*` (frozen), shebangs, `.toc` `##` metadata. Generators
  (`dev/gen_weights.lua`) must not emit comments either.
- **No docs, license or notice files.** No `docs/`, `CONTRIBUTING.md`, `LICENSE*`, `NOTICE*`, `X-License` lines or
  license fields; `README.md` and this file are the only prose.
- Shipped code is Lua 5.1 (the game); tests run on 5.4. No `//`, `goto`, bit operators, `table.unpack` in addons.
- A new file in a `.toc` (or a new addon folder) needs a full game restart, not just `/reload`.
- New modules: start from `templates/Module/`. Modules never call `SendAddonMessage`; they use `mod:NewChannel`
  (the core paces all modules together), with a test for what and how often they send.
- In-game checks: `bash scripts/dev-run.sh [tests]` queues in-game tests; ask the user to `/reload` (twice: the run,
  then saving - `ReloadUI()` is protected on Forever), then `bash scripts/devlog.sh --wait <id>` shows results, the
  log, BugGrabber errors and FrameXML.log (`--runs`, `--cat <prefix>`; `WOW_DIR` overrides the game folder). Don't
  edit addon files while the user is logging in.
- Options go into the `/rq` overview, not chat commands. Player-facing text in English and German locale files.
- Say what you verified (with file:line or test output) and what you could not test, e.g. anything in game.
