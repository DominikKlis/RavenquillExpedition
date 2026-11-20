# Ravenquill Expedition

A WoW Forever (interface 16001) addon suite for the Ravenquill Expedition guild.

| Folder | What it does | Ships on CurseForge |
|---|---|---|
| `RavenquillExpedition` | Core: the module API, one guild-sync scheduler for all modules, the `/rq` overview with every module's options | yes |
| `RavenquillExpedition_Map` | Guildmates who run the addon on the world map and minimap | yes |
| `RavenquillExpedition_Highlights` | Logs and shares the guild's cool moments | yes |
| `RavenquillExpedition_CraftAdvisor` | Which of your crafts would be upgrades for guildmates, and which guildmates can craft yours | yes |
| `RavenquillExpedition_Dev` | Developer tools: a log in SavedVariables and in-game tests | never |

CurseForge: project 1806854 (unlisted, alpha).

WowUp: Get Addons → Install from URL → `https://github.com/DominikKlis/RavenquillExpedition`, with the WoW Forever
install selected. Each GitHub release carries a `release.json` (flavor `forever`) that points WowUp at the zip, and
WowUp then updates the suite like any other addon.

## Layout

- Each addon folder is what WoW loads. Its `dev/` folder holds offline tests and tools; `dev/` never ships.
- `templates/Module/`: a complete example module (under 40 code lines) with a two-client test; start new modules from it.
- `RavenquillExpedition/dev/testkit.lua`: many simulated clients with the real core on one virtual guild channel.
- `scripts/run-tests.sh` runs every offline test harness, luacheck and the architecture scorecard (`scripts/check-architecture.lua`).
- `scripts/link-addons.ps1` links a clone into your AddOns folder.
- `scripts/switch-addons.ps1 dev|curseforge` switches the game between this clone and the CurseForge install: `dev`
  parks the CurseForge folders in `Interface\RavenquillExpedition-CurseForge` and links the clone in, `curseforge`
  removes the links and moves them back. Close the game first, and pause CurseForge updates for the suite while `dev`
  is active, or the app writes through the links into the clone. `WOW_DIR` or `-AddOns` overrides the game folder.
- `scripts/package.ps1` builds the release zip (`dist/`), stamping one suite version into every `.toc`.
- `.github/workflows/` runs the tests on every push and pull request, and releases on version tags.
