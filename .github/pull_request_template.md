## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Checks

- [ ] `bash scripts/run-tests.sh` is green (harnesses, luacheck, architecture scorecard). If a metric improved:
      `RQ_UPDATE=1 bash scripts/run-tests.sh` and the tightened `scripts/arch-baseline.lua` is in this PR.
- [ ] No `dev/fixtures/compat_golden.lua` was re-recorded, or the PR says why the wire / SavedVariables format
      changed on purpose and how older versions still understand it.
- [ ] New player-facing text is in English and German.
- [ ] New or changed sync messages go through a core channel (`mod:NewChannel`), with a test for what and how often
      we send.

## Tested in game

<!-- What you checked in game (or with scripts/dev-run.sh + scripts/devlog.sh), and what you could not test.
     New files in a .toc need a full game restart. -->
