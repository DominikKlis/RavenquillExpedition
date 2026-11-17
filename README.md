# Ravenquill Expedition

A WoW Forever (interface 16001) addon suite for the Ravenquill Expedition guild.

| Folder | What it does | Ships on CurseForge |
|---|---|---|
| `RavenquillExpedition` | Core: the module API, one guild-sync scheduler for all modules, the `/rq` overview with every module's options | yes |
| `RavenquillExpedition_Map` | Guildmates who run the addon on the world map and minimap | yes |
| `RavenquillExpedition_Highlights` | Logs and shares the guild's cool moments | yes |
| `RavenquillExpedition_CraftAdvisor` | Which of your crafts would be upgrades for guildmates | yes |
| `RavenquillExpedition_Dev` | Developer tools: a log in SavedVariables and in-game tests | never |

CurseForge: project 1806854 (unlisted, alpha).

## Layout

- Each addon folder is what WoW loads. Its `dev/` folder holds offline tests and tools; `dev/` never ships.
- `templates/Module/`: a complete example module (under 40 code lines) with a two-client test; start new modules from it.
- `RavenquillExpedition/dev/testkit.lua`: many simulated clients with the real core on one virtual guild channel.
- `scripts/run-tests.sh` runs every offline test harness, luacheck and the architecture scorecard (`scripts/check-architecture.lua`).
- `scripts/link-addons.ps1` links a clone into your AddOns folder.
- `scripts/package.ps1` builds the release zip (`dist/`), stamping one suite version into every `.toc`.
- `.github/workflows/` runs the tests on every push and pull request, and releases on version tags.
