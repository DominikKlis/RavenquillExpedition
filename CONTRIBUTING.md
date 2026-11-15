# Contributing

Contributions are licensed under GPL-3.0, like the rest of the suite (`LICENSE-GPL-3.0.txt` in each addon folder).

## Setup

You need git, [Lua 5.4](https://www.lua.org/) for the offline tests, and PowerShell 7 (`pwsh`) for the scripts.
Optional: [luacheck](https://github.com/lunarmodules/luacheck) (`luarocks install luacheck`); the test run uses it when
it is installed, and CI always runs it.

Clone anywhere and link the suite into your AddOns folder:

```powershell
git clone https://github.com/DominikKlis/RavenquillExpedition.git
cd RavenquillExpedition
pwsh -File scripts\link-addons.ps1 -AddOns "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
```

This creates junctions in your AddOns folder that point at the clone. Remove any old copies of the
`RavenquillExpedition*` folders first. (The maintainer's repository is the AddOns folder itself; the root
`.gitignore` tracks only the suite. If you do the same, never run `git clean -x` there: it would delete your other
addons.)

Optional for the CraftAdvisor score tests: unzip SimGear Forever (CurseForge project 1754471) into
`.cache/simgear/` in the repository, or set `RQ_SIMGEAR` to its folder. Without it the SimGear score harnesses (`harness_score_golden.lua`, `harness_score_weapons.lua`, ...) show a
named SKIP; everything else runs.

## GitHub login

Use the GitHub CLI (`gh`). Changing anything in `.github/workflows/` needs the extra `workflow` permission;
without it GitHub rejects the push ("refusing to allow an OAuth App to create or update workflow ... without
`workflow` scope"). Log in with it from the start:

```bash
gh auth login --web --git-protocol https --scopes workflow
gh auth setup-git
```

Already logged in without it: `gh auth refresh -h github.com -s workflow`. Workflow files can run code with the
repository's secrets, which is why GitHub asks for this separately; it can be revoked under GitHub, Settings,
Applications.

## Workflow

1. Create a branch from `main`.
2. Make the change. Run the tests: `bash scripts/run-tests.sh` (CI runs the same on every pull request). It runs:
   - every offline harness (`*/dev/harness*.lua`), with a passed / failed / skipped count each;
   - luacheck, when installed;
   - the architecture scorecard (`scripts/check-architecture.lua`), which fails when a metric gets worse than
     `scripts/arch-baseline.lua`. When your change improves one, run `RQ_UPDATE=1 bash scripts/run-tests.sh`
     and commit the tightened baseline.
3. Test in game (`/reload`). Say in the pull request what you tested in game and what you couldn't.
4. Open a pull request against `main`.

## Compatibility tests: don't break guildmates on older versions

Each module has a `dev/harness_compat.lua` with golden fixtures (`dev/fixtures/compat_golden.lua`): the exact bytes
it sends, and how old SavedVariables load. If one fails, your change alters what goes over the wire or into
saved data. Fix the change, not the fixture. Only re-record (`lua <module>/dev/harness_compat.lua --record`) for a
deliberate format change that old clients still understand, and say so in the pull request.

## Conventions

- **Options live in the `/rq` overview.** No new chat commands unless they are really needed; modules hand their
  options to the core (see `mod.options` in `RavenquillExpedition_Map/Map.lua`).
- **Guild traffic is shared.** All modules together must stay well within the addon message limits of a guild of
  40. Every module sends through the core's scheduler. Add a test to the module's sync harness for anything that
  changes what or how often we send.
- **Text in both locales.** Player-facing strings go into the module's locale file, English and German.
- **Fix a bug with a test** that fails without the fix.
- **One suite version.** Don't bump `## Version` by hand: the release stamps the tag's version into every `.toc`.
- Never add someone else's code or data without checking its license; note it in the addon's `NOTICE.txt`.

## Writing a module

Start from `templates/Module/`: a complete module (under 40 code lines) with a two-client test. The API (SavedVariables,
migrations, locale, events, options, guild sync channels, test kit) is in `docs/module-api.md`. In short:
`RavenquillExpedition:NewModule(name, spec)`, `mod:NewChannel{ tag, version }`, `ch:Define` / `ch:On` / `ch:Send`.
The core paces every module's guild messages together, so a module never sends addon messages itself.

## Open decisions (maintainer)

- TODO(user): CraftAdvisor's recipe data is generated from CraftersJournal, which has no license. Publishing the
  repository publishes that data. Get permission, regenerate from another source, or keep the repository private.
- TODO(user): HereBeDragons (Map) has no license text upstream; ask before a public release (see
  `RavenquillExpedition_Map/NOTICE.txt`).

## Releasing (maintainers)

Releases are built and uploaded by `.github/workflows/release.yml` when a version tag is pushed:

```bash
git tag -a v0.2.1-alpha -m "- Map: fixed ...
- Highlights: ..."
git push origin v0.2.1-alpha
```

- `-alpha` / `-beta` in the tag set the CurseForge release type; no suffix means a full release.
- The tag message becomes the changelog (Markdown).
- `scripts/package.ps1` builds `dist/RavenquillExpedition-<version>.zip` with the core, Map and Highlights, without
  `dev/` folders, and writes the version into every `.toc`. CraftAdvisor and the Dev addon are never included.
- The workflow needs the repository secret `CF_API_KEY`.
