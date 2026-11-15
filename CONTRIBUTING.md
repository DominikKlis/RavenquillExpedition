# Contributing

## Setup

You need git, [Lua 5.4](https://www.lua.org/) for the offline tests, and PowerShell 7 (`pwsh`) for the scripts.

**Option A: clone anywhere and link (recommended)**

```powershell
git clone https://github.com/DominikKlis/RavenquillExpedition.git
cd RavenquillExpedition
pwsh -File scripts\link-addons.ps1 -AddOns "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
```

This creates junctions in your AddOns folder that point at the clone. Remove any old copies of the
`RavenquillExpedition*` folders first.

**Option B: the repository is the AddOns folder.** The root `.gitignore` tracks only the suite's folders, so the
repository can live directly in `Interface\AddOns`. Never run `git clean -x` there: it would delete your other addons.

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
2. Make the change. Run the tests: `bash scripts/run-tests.sh` (CI runs the same on every pull request).
   CI skips CraftAdvisor for now: its harnesses still use absolute Windows paths and a local SimGear download,
   so they only run on the maintainer's machine until they are made portable.
3. Test in game (`/reload`). Say in the pull request what you tested in game and what you couldn't.
4. Open a pull request against `main`.

## Conventions

- **Options live in the `/rq` overview.** No new chat commands unless they are really needed; modules hand their
  options to the core (see `mod.options` in `RavenquillExpedition_Map/Map.lua`).
- **Guild traffic is shared.** Modules send through the core's sync lane and keep their message rate low; a guild
  of 40 must stay well within the addon message limits. Add a test to the module's sync harness for anything that
  changes what or how often we send.
- **Text in both locales.** Player-facing strings go into the module's locale file, English and German.
- **Fix a bug with a test** that fails without the fix.
- **Bump `## Version`** in the `.toc` of every addon you change.
- Never add someone else's code or data without checking its license; note it in the addon's `NOTICE.txt`.

## Releasing (maintainers)

Releases are built and uploaded by `.github/workflows/release.yml` when a version tag is pushed:

```bash
git tag -a v0.2.1-alpha -m "- Map: fixed ...
- Highlights: ..."
git push origin v0.2.1-alpha
```

- `-alpha` / `-beta` in the tag set the CurseForge release type; no suffix means a full release.
- The tag message becomes the changelog (Markdown).
- The zip contains the core, Map and Highlights, without `dev/` folders. CraftAdvisor is never included.
- The workflow needs the repository secret `CF_API_KEY`.
