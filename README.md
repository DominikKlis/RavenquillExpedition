# Ravenquill Expedition

A WoW Forever (interface 16001) addon suite for the Ravenquill Expedition guild.

| Folder | What it does | Ships on CurseForge |
|---|---|---|
| `RavenquillExpedition` | Core: guild sync lane, shared helpers, the `/rq` overview with every module's options | yes |
| `RavenquillExpedition_Map` | Guildmates who run the addon on the world map and minimap | yes |
| `RavenquillExpedition_Highlights` | Logs and shares the guild's cool moments | yes |
| `RavenquillExpedition_CraftAdvisor` | Which of your crafts would be upgrades for guildmates | no (its recipe data is licensed for private/guild use only, see its `NOTICE.txt`) |

CurseForge: project 1806854 (unlisted, alpha).

## Layout

- Each addon folder is what WoW loads. Its `dev/` folder holds offline tests and tools; `dev/` never ships.
- `scripts/run-tests.sh` runs every offline test harness.
- `scripts/link-addons.ps1` links a clone into your AddOns folder.
- `RavenquillExpedition/dev/package.ps1` builds the release zip.
- `.github/workflows/` runs the tests on every push and pull request, and releases on version tags.

See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## License

GPL-3.0, see `LICENSE-GPL-3.0.txt` in each addon folder. Third-party parts are listed in the `NOTICE.txt` files.
