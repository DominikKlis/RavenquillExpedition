# Module template

A complete suite module (shares level-ups with guildmates who run it) and its two-client test.

1. Copy this folder to the repository root as `RavenquillExpedition_<Name>`.
2. Rename `RavenquillExpedition_Example.toc` to `RavenquillExpedition_<Name>.toc`, and in it and `Example.lua`
   replace `Example` / `EX` (the sync tag: short and unique) / `RavenquillExpeditionExampleDB`.
3. In `dev/harness.lua`, point `Kit` at `../../RavenquillExpedition/dev/testkit.lua` and the file list at your
   files, then `bash scripts/run-tests.sh`.
4. Add the folder to `.gitignore`'s allow-list and to `scripts/link-addons.ps1`; restart the game once (a new addon
   is only seen after a restart).

The API is in `docs/module-api.md`.
