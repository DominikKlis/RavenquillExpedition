# WoW Forever: client facts the suite relies on

Interface 16001 (client 1.60.x), a Classic-era game on a modern client: Lua 5.1, a modern API surface (`C_*`
namespaces, secret values), Classic data. `[U]` = unverified on Forever, still assumed from other clients.

## Names

- The second value of `UnitName` is a **surname**, not a realm. Units read "First Surname"; roster entries and
  addon-message senders read "First Surname-Realm" (own realm included). `RQ:UnitKey` and `RQ:NormName` give the same
  key for all three; only our own realm's spellings are stripped, so hyphenated surnames survive.
- The separator comes from `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` (a space).

## Secret values

- Some API results are "secret" in protected contexts: comparing, concatenating or indexing them raises.
  `RQ.IsSecret(v)` (via `issecretvalue` / `canaccessvalue`) before any use; `RQ.Plain(v, type)` does both checks.

## Addon messages

- Measured (Dev test `comm.rate`): 30 GUILD addon messages per minute from one client for a full minute all echoed
  (average 0.6 s), with another addon sending at the same time. The suite uses 12 per minute.

- Only GUILD delivers between guildmates; 255 bytes; silent drops for heavy senders; our own messages echo back
  (see `docs/sync.md`). `SendAddonMessage` returns `0`/`true`/`nil` for ok, `3`/`8` for throttled `[U]`.
- `RegisterAddonMessagePrefix` returns `0` (ok) or `1` (already registered) `[U]`.
- `hooksecurefunc(C_ChatInfo, "SendAddonMessage", ...)` sees other addons' sends `[U]` (the overview's diagnostics
  show "foreign n" when it works).

## Protected functions (verified in game)

- `ReloadUI()` called from addon code outside a hardware event (e.g. a timer) is blocked (`ADDON_ACTION_BLOCKED`).
- Work done inside Blizzard's world-map show path taints it: Blizzard's own quest pins then call the protected
  `SetPassThroughButtons` and the block is blamed on our addon. Map therefore draws on its own canvas layer and the
  embedded HereBeDragons-Pins registers with the world map only on first use (`RavenquillExpedition_Map/NOTICE.txt`).
- Opening the world map from addon code in combat is refused by Map for the same reason.

## Files the game writes

- SavedVariables: `WTF/Account/<account>/SavedVariables/<Addon>.lua`, written on `/reload`, logout and a clean exit
  (a crash loses the session). A new addon folder or a new `.toc` file needs a full restart, not `/reload`.
- `Logs/FrameXML.log`: load and syntax errors. BugGrabber keeps Lua errors in its own SavedVariables
  (`!BugGrabber.lua`). `scripts/devlog.sh` reads all three.
