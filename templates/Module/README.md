# Module template

A complete suite module (shares level-ups with guildmates who run it) and its two-client test.

1. Copy this folder to the repository root as `RavenquillExpedition_<Name>`.
2. Rename `RavenquillExpedition_Example.toc` to `RavenquillExpedition_<Name>.toc`, and in it and `Example.lua`
   replace `Example` / `EX` (the sync tag: short and unique) / `RavenquillExpeditionExampleDB`.
3. In `dev/harness.lua`, point `Kit` at `../../RavenquillExpedition/dev/testkit.lua` and the file list at your
   files, then `bash scripts/run-tests.sh`.
4. Add the folder to `.gitignore`'s allow-list and to `scripts/link-addons.ps1`; restart the game once (a new addon
   is only seen after a restart).
5. Once its messages are in use by guildmates, add `dev/harness_compat.lua` with a golden of the wire bytes and the
   SavedVariables (copy one from `RavenquillExpedition_Highlights/dev/`; `--record` writes the golden once).
6. To ship it: add it to `$addons` in `scripts/package.ps1` and to the README's table; the package needs a licence
   file in the folder (`LICENSE-GPL-3.0.txt`, as in the other shipped addons).

Two habits the template shows on purpose: nothing goes out in combat or an instance, so it keeps the value until
`onResult` says "delivered" and tries again later; and its store is keyed by sender, so it never grows past the
guild. `scripts/run-tests.sh` runs this template's own test too.

The API is in `docs/module-api.md`.
