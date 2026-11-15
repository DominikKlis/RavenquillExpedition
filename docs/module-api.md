# Writing a module (core API 2)

A module is its own addon folder `RavenquillExpedition_<Name>` that depends on the core. The core gives it
SavedVariables with defaults and migrations, texts in English and German, events, timers, options in the `/rq`
window, and guild sync with pacing, delivery checks and validation. A module never creates its own sync code, event
frame for login/loading, or locale lookup.

Start from `templates/Module/` (see its README): a complete module in under 40 code lines (it keeps a level-up
from combat until it is delivered, and stores one entry per guildmate) plus a two-client test.

## Registering

```lua
local ADDON = ...
local RQ = RavenquillExpedition
local mod = RQ:NewModule("Name", {
  addon = ADDON,                -- required for sv / defaults / OnLoad: they run at this folder's ADDON_LOADED
                                -- (a missing or misspelled one is named in chat at login)
  api = 2,                      -- minimum core API; a too-old core says so once and doesn't load the module
  title = "Shown title", slash = "name", icon = "Interface\\Icons\\...",  -- the /rq row, "/rq name"
  sv = "RavenquillExpeditionNameDB",            -- account SavedVariables (also in the .toc)   -> mod.db
  svChar = "RavenquillExpeditionNameCharDB",    -- per character (also in the .toc)            -> mod.cdb
  defaults = { share = true },                  -- -> mod.settings (= db.settings); missing / wrong type -> default
  charDefaults = { outbox = {} },               -- filled into mod.cdb the same way
  dbVersion = 2, migrations = { [2] = function(db, cdb, mod) end },  -- numbered, in order, each once
  loginMigrations = { [1] = function(db, cdb, mod) end },            -- the same at login (realm / player known)
  locale = { enUS = { KEY = "Text" }, deDE = { KEY = "Text" } },     -- -> mod.L (client language, English, the key)
})
```

Migrations run from `db.v + 1` up to `dbVersion` (or the highest number listed), each under `RQ:Call`; a failing one
stops the chain and `db.v` stays at the last good step, so it runs again next time. Never change the meaning of an
existing number; add a new one.

Callbacks (all optional, all run under `RQ:Call`, so errors reach BugSack): `mod:OnLoad()`, `mod:OnLogin()`,
`mod:OnGuildChanged(newKey, oldKey)` (a real change or leaving the guild), `mod:OnSlash(rest)`, `mod:Open()` (the
row's Open button), `mod:OverviewStatus()` (one status line), `mod:OverviewRecent(n)`, `mod:OnOptionChanged(key, v)`.

## Module methods

| Call | What it does |
|---|---|
| `mod:Print(...)` | a chat line with the module's title |
| `mod:RegisterEvent(event, handler)` | `handler(mod, ...)`, or the method `mod[event]`; false for an event this client lacks |
| `mod:UnregisterEvent(event)` | |
| `mod:After(seconds, fn)` / `mod:Every(seconds, fn)` | timers; `Every` returns a handle with `:Cancel()` |
| `mod:GuildStore(name)` | a table in `db.guilds[<guild>@<realm>][name]`: one guild's data never shows in another |
| `mod:SetOptions(list)` / `mod:Option(id)` | options for `/rq` (types below) |
| `mod:NewChannel{ tag, version }` | a schema sync channel (below) |
| `mod:NewRawChannel{ prefix, lane }` | own prefix and own bytes (only for formats that already exist on the wire) |

Option entries: `header`, `toggle`, `range` (`min`, `max`, `step`, `format`), `button` (`func`), `text` (`lines` =
a read-only copy box for diagnostics). `{ type = "toggle", key = "share", label = ... }` reads and writes
`mod.settings.share`. Every entry may have `tooltip` and `disabled = fn()`. Player-facing text goes into `locale`,
English and German.

## Guild sync

```lua
local ch = mod:NewChannel({ tag = "EX", version = 1 })   -- tag: unique, short; messages "EX;1;<type>;<fields>"
ch:Define("lvl", { from = "self", fields = { { "who", "key" }, { "level", "int", 1, 200 } } })
ch:On("lvl", function(sender, msg) ... end)              -- sender = the guildmate's key, msg = checked fields
ch:Send("lvl", { who = RQ:PlayerKey(), level = 31 }, { onResult = function(status) end })
```

- **Field kinds:** `{ name, "int", lo, hi }`, `{ name, "b36", lo, hi }`, `{ name, "text", maxBytes }`,
  `{ name, "word", maxLen }` (letters and digits), `{ name, "class" }`, `{ name, "time" }`, `{ name, "flag" }`,
  `{ name, "enum", { "a", "b" } }`, `{ name, "key" }` (a player). `opt = true` allows an empty field (nil).
  The sender checks the same rules: a value out of range, infinite or NaN, or an unknown class is never sent
  (`onResult` "dropped", counted under `encode: field <name>`).
- **Checked before your handler:** prefix, guild channel only, secret values, the sender's name, the per-sender
  rate limit, the version, the type, every field and its range. `from = "self"`: every `key` field must be the
  sender (nobody can send data about someone else). A rejected message is counted in `ch:Status().rejected`.
- **Sending:** `ch:Send` queues (event lane) and returns nothing; the result comes through `onResult`:
  `"delivered"` (our echo came back), `"lost"` or `"dropped"` (never sent: in an instance or combat, before login,
  too long, waited too long). Nothing is resent for you: keep what you wanted to send until "delivered" and try
  again later (the template does this on `PLAYER_REGEN_ENABLED`). `ch:TrySend(type, msg)` sends now or not at all
  and returns `ok, reason`.
- **Lanes:** schema types (`Define`) are always event traffic; `lane` there may only be `"event"`. For "the latest
  value or nothing" (a position) use a raw channel with `lane = "state"`, as Map does; `raw:Send` returns ok.
- **Pacing is the core's:** one budget for the whole suite per client: tokens refill at 1 per 5 s (at most 3 saved),
  and the pump sends at most one message per 5 s, so queued events go out 5 s apart. While nothing echoes for
  120 s after a loss: 1 per 5 min until an echo comes back. Nothing in instances or combat; other addons' guild
  messages use our tokens too. Design for that: send rarely, keep messages short (250 bytes including the tag and
  type), let the receiver ask instead of broadcasting everything.
- **Changing a format:** append fields at the end **with `opt = true`**: older clients ignore extra fields, and new
  clients read an old client's message with the field missing as nil. A new required field would make new clients
  reject every message from old ones. Or define a new type. Bump `version` only for an incompatible change: old
  clients then ignore the new messages.
- **Your store:** received data goes into `mod:GuildStore(name)`. Key it by sender (or cap it): it is saved, and a
  list that only grows grows forever.

## Helpers on `RavenquillExpedition`

`RQ:Call(fn, ...)` (own code; errors reach BugSack), `RQ.SafeCall(fn, ...)` (only for probing client APIs),
`RQ.Plain(v, type)`, `RQ.IsSecret(v)`, `RQ.Bool(v)`, `RQ:Trace(cat, msg, data)` (the Dev addon's log; call it as
`RQ:Trace`, never cache it), `RQ:Now()`, `RQ:InInstance()`, `RQ:MaxLevel()`, `RQ.Cut(s, n)`.
Names: `RQ:PlayerKey()`, `RQ:UnitKey(unit)`, `RQ:NormName(name)`, `RQ:StripRealm(key)`, `RQ:IsMe(key)`, `RQ:GuildKey()`.
Roster: `RQ:RequestRoster()` (ask the client for a fresh roster; throttled), `RQ:IsGuildMember(key)` (true / false / nil while unknown), `RQ:RosterEntry(key)` (`class`, `level`, `online`),
`RQ:EachMember()`, `RQ:OnlineCount()`, `RQ:RosterComplete()`, `RQ:RosterReadAt()`, `RQ:GroupGuildies()`.
Peers (guildmates heard running the suite): `RQ:IsPeer(key)`, `RQ:PeerCount(window)`, `RQ:ElectionRank(keys)`.
Wire: `RQ.Wire.b36 / b36s / n36 / Split / Clean / CLASSES / CLASS_IDX / MAX_MSG`.
Sync state: `RQ:CanSend()` (ok, reason), `RQ:CommState()`, `RQ:CommStatus()`.

## Testing

- **Offline, many clients:** `RavenquillExpedition/dev/testkit.lua` runs the real core and your module in several
  simulated clients on one guild channel with a virtual clock. See `templates/Module/dev/harness.lua`. Name your test
  `<YourAddon>/dev/harness*.lua` and `scripts/run-tests.sh` runs it.
- **In game:** `docs/dev-bridge.md` (the Dev addon logs what happens and runs in-game tests).
- Never change bytes another version sends without a compatibility test (`dev/harness_compat.lua` in each module).
