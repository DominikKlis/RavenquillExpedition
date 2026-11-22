local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local sched = Kit.Scheduler({ start = 100 })
local bus = Kit.Bus(sched)
local me = Kit.Client(sched, bus, "Me Smith", { guild = "Die Gilde", realm = "Forever", locale = "deDE", class = "ROGUE",
  level = 30, epoch = 1800000000 })
bus:member("Bud Stone", "DRUID", 28, true, "Dämmerwald")
bus:member("Cara Moss", "MAGE", 31, false)
bus:member("Anna Muller-Lee", "PRIEST", 20, true, "")
local env, coreNS, RQ, fire = me.env, me.coreNs, me.RQ, me.fire
fire("ADDON_LOADED", "RavenquillExpedition")

section("Module: SavedVariables, defaults, migrations")
check(RQ.API == 2, "core API is 2")
local order = {}
env.TestModDB = { v = 1, settings = { share = "yes", keep = 5 }, old = true }
env.TestModCharDB = { seq = "x" }
local mod = RQ:NewModule("Test", {
  addon = "TestAddon", api = 2, sv = "TestModDB", svChar = "TestModCharDB", dbVersion = 4,
  defaults = { share = true, size = 1, list = { 1, 2 } },
  charDefaults = { seq = 0, outbox = {} },
  migrations = {
    [1] = function() order[#order + 1] = 1 end,
    [2] = function(db) order[#order + 1] = 2; db.old = nil; db.renamed = true end,
    [3] = function(db, cdb, m) order[#order + 1] = 3; db.who = m.name end,
  },
  loginMigrations = { [1] = function(db) db.loginRan = (db.loginRan or 0) + 1 end },
  locale = { enUS = { HELLO = "Hello", ONLY_EN = "only english" }, deDE = { HELLO = "Hallo" } },
})
function mod:OnLoad() order[#order + 1] = "OnLoad:" .. tostring(self.db and self.db.v) end
check(getmetatable(mod) and mod.Print and mod.RegisterEvent and mod.GuildStore, "the module gets the module methods")
fire("ADDON_LOADED", "TestAddon")
local db = env.TestModDB
check(table.concat(order, ",") == "2,3,OnLoad:4", "migrations 2 and 3 ran in order from v+1, then OnLoad (" .. table.concat(order, ",") .. ")")
check(db.v == 4 and db.renamed and db.old == nil and db.who == "Test", "db.v = dbVersion; migrations got db, cdb, mod")
check(mod.db == db and mod.settings == db.settings, "mod.db and mod.settings ready in OnLoad")
check(db.settings.share == true and db.settings.keep == 5 and db.settings.size == 1, "wrong-typed setting replaced, unknown kept, missing filled")
db.settings.list[1] = 9
check(mod.defaults.list[1] == 1, "table defaults are copied, not shared")
check(mod.cdb == env.TestModCharDB and mod.cdb.seq == 0 and type(mod.cdb.outbox) == "table", "per-character table with its defaults")
check(mod.L.HELLO == "Hallo" and mod.L.ONLY_EN == "only english" and mod.L.NOPE == "NOPE", "locale: client language, then English, then the key")

env.FailDB = { v = 0 }
local ran3 = false
local fm = RQ:NewModule("Failing", { addon = "FailAddon", sv = "FailDB", dbVersion = 3,
  migrations = { [1] = function() end, [2] = function() error("broken migration") end, [3] = function() ran3 = true end } })
local errBefore = #me.errors
fire("ADDON_LOADED", "FailAddon")
check(env.FailDB.v == 1 and not ran3 and #me.errors == errBefore + 1, "a failing migration stops the chain (v stays 1) and reaches BugSack")
check(fm.db == env.FailDB, "the module still gets its db")

check(env.FreshDB == nil, "precondition: no FreshDB")
RQ:NewModule("Fresh", { addon = "FreshAddon", sv = "FreshDB", dbVersion = 2, defaults = { a = 1 } })
fire("ADDON_LOADED", "FreshAddon")
check(type(env.FreshDB) == "table" and env.FreshDB.v == 2 and env.FreshDB.settings.a == 1, "fresh install: table created at the current version")

section("Module: API check, login, guild changes")
local future = RQ:NewModule("Future", { addon = "FutureAddon", api = 99 })
check(RQ:GetModule("Future") == nil and future.Print, "a module needing API 99 is not registered (but gets a usable table)")
check(me.printed[#me.printed].text:find("API 99", 1, true) ~= nil, "and the player is told once: " .. tostring(me.printed[#me.printed].text))
local logins, guildChanges = 0, {}
function mod:OnLogin() logins = logins + 1 end
function mod:OnGuildChanged(new, old) guildChanges[#guildChanges + 1] = tostring(old) .. ">" .. tostring(new) end
local fullName = env.UnitNameUnmodified
env.UnitNameUnmodified, me.realm = function(u) if u == "player" then return "Me" end end, "Elsewhere"
local beforeLogin = RQ:PlayerKey() .. "|" .. tostring(RQ:StripRealm("Bud Stone-Elsewhere"))
env.UnitNameUnmodified, me.realm = fullName, "Forever"
fire("PLAYER_LOGIN")
check(beforeLogin == "Me|Bud Stone" and RQ:PlayerKey() == "Me Smith" and RQ:StripRealm("Bud Stone-Elsewhere") == nil,
  "PLAYER_LOGIN forgets the player name and realm read before it (" .. beforeLogin .. ")")
check(logins == 1 and db.loginRan == 1 and db.vLogin == 1, "PLAYER_LOGIN: login migrations, then OnLogin")
fire("PLAYER_GUILD_UPDATE")
check(#guildChanges == 0, "guild update with the same guild: no OnGuildChanged")
me.guild = "Neue Gilde"
fire("PLAYER_GUILD_UPDATE")
me.guild = nil
fire("PLAYER_GUILD_UPDATE")
check(guildChanges[1] == "Die Gilde@Forever>Neue Gilde@Forever" and guildChanges[2] == "Neue Gilde@Forever>nil",
  "OnGuildChanged on a real change and on leaving: " .. table.concat(guildChanges, " | "))
me.guild = "Die Gilde"
fire("PLAYER_GUILD_UPDATE")

section("Module: events, timers, guild store, options")
local got = {}
mod:RegisterEvent("BAG_UPDATE", function(m, bag) got[#got + 1] = (m == mod) and bag end)
function mod:PLAYER_LEVEL_UP(level) got[#got + 1] = "lvl" .. level end
mod:RegisterEvent("PLAYER_LEVEL_UP")
fire("BAG_UPDATE", 3); fire("PLAYER_LEVEL_UP", 31)
check(got[1] == 3 and got[2] == "lvl31", "RegisterEvent: handler(mod, ...) or the method of the same name")
mod:RegisterEvent("PLAYER_MONEY", function() error("handler bug") end)
errBefore = #me.errors
fire("PLAYER_MONEY")
check(#me.errors == errBefore + 1, "an error in a handler reaches BugSack (RQ:Call), the next event still works")
mod:UnregisterEvent("BAG_UPDATE")
fire("BAG_UPDATE", 4)
check(#got == 2, "UnregisterEvent")
local ticks, after = 0, false
mod:After(5, function(m) after = (m == mod) end)
local h = mod:Every(10, function() ticks = ticks + 1 end)
sched:advance(35)
h:Cancel()
sched:advance(50)
check(after and ticks == 3, "After(5) ran; Every(10) ran 3 times in 35 s and stopped after Cancel (" .. ticks .. ")")
local store = mod:GuildStore("events")
store[1] = "x"
check(db.guilds["Die Gilde@Forever"].events[1] == "x" and mod:GuildStore("events") == store, "GuildStore: db.guilds[guildKey][name]")
local changed = {}
function mod:OnOptionChanged(key, v) changed[#changed + 1] = key .. "=" .. tostring(v) end
mod:SetOptions({ { type = "toggle", key = "share", label = "Share" }, { type = "button", id = "go", label = "Go", func = function() end } })
local o = mod:Option("share")
check(o and o.get() == true, "SetOptions key shorthand: get reads mod.settings")
o.set(false)
check(db.settings.share == false and changed[1] == "share=false", "set writes mod.settings and calls OnOptionChanged")
check(mod:Option("go") and mod:Option("nope") == nil, "Option(id)")
do
  local methods, tops, white = me.frameMethods, {}, {}
  methods.GetStringHeight = function(s) return s._text == "Drei Zeilen Erklärung" and 40 or 12 end
  methods.SetPoint = function(s, point, _, y) if point == "TOPLEFT" then tops[s] = y end end
  methods.SetTextColor = function(s, r) white[s] = r == 1 end
  local sharing = true
  local p = coreNS.BuildPanel(nil, {
    { type = "note", label = "Drei Zeilen Erklärung", disabled = function() return not sharing end },
    { type = "toggle", label = "Danach", get = function() return true end, set = function() end },
  })
  p.refreshAll()
  local note, toggle = p.controls[1], p.controls[2]
  check(note:GetText() == "Drei Zeilen Erklärung" and white[note] and tops[toggle] <= -40,
    "a note shows its text and the next option starts below all its wrapped lines")
  sharing = false
  p.refreshAll()
  check(white[note] == false, "a note greys out while its disabled function says so")
  methods.GetStringHeight, methods.SetPoint, methods.SetTextColor = nil, nil, nil
end

section("Names and roster")
fire("GUILD_ROSTER_UPDATE")
check(RQ:PlayerKey() == "Me Smith" and RQ:IsMe("Me Smith-Forever") and not RQ:IsMe("Bud Stone"), "PlayerKey / IsMe with the realm suffix")
check(RQ:NormName("Anna Muller-Lee-Forever") == "Anna Muller-Lee" and RQ:StripRealm("Anna Muller-Lee") == nil,
  "only our own realm is stripped; hyphenated surnames stay")
check(RQ:RosterEntry("Bud Stone").class == "DRUID" and RQ:RosterEntry("Bud Stone-Forever") ~= nil, "RosterEntry, also with the realm suffix")
check(RQ:RosterEntry("Bud Stone").zone == "Dämmerwald" and RQ:RosterEntry("Cara Moss").zone == nil
  and RQ:RosterEntry("Anna Muller-Lee").zone == nil, "RosterEntry carries the roster's zone, nil when it names none or an empty one")
check(RQ:IsGuildMember("Cara Moss") == true and RQ:IsGuildMember("Nobody") == false, "IsGuildMember")
local loaded, count, offline = RQ:RosterComplete()
check(loaded and count == 4 and offline == 1 and RQ:OnlineCount() == 3, "RosterComplete / OnlineCount")
local n = 0
for _ in RQ:EachMember() do n = n + 1 end
check(n == 4 and RQ:RosterReadAt() == sched.t, "EachMember / RosterReadAt")
env.RavenquillExpeditionDB.peersByGuild = nil
env.RavenquillExpeditionDB.peers = { ["Bud Stone"] = RQ:Now() - 100, ["Cara Moss"] = RQ:Now() - 5000 }
check(coreNS.PeerCount(3600) == 1 and coreNS.PeerCount() == 2, "PeerCount(window)")
check(env.RavenquillExpeditionDB.peers == nil and env.RavenquillExpeditionDB.peersByGuild["Die Gilde@Forever"]["Bud Stone"],
  "the old peers table moved into the current guild")
local peersHere = env.RavenquillExpeditionDB.peersByGuild["Die Gilde@Forever"]
peersHere["Anna Muller-Lee"] = RQ:Now() - RQ.PEER_MAX_AGE - 5
check(RQ:OverviewPeersLine() == "Mit Ravenquill: 2 in der Gilde, 1 online",
  "overview peers line: fresh peers on the roster, then the online ones (" .. RQ:OverviewPeersLine() .. ")")
peersHere["Anna Muller-Lee"] = nil
local caraSeen = peersHere["Cara Moss"]
peersHere["Cara Moss"] = "soon"
local peerOk, caraIsPeer = pcall(RQ.IsPeer, RQ, "Cara Moss")
local lineOk, peersLine = pcall(RQ.OverviewPeersLine, RQ)
check(peerOk and caraIsPeer == false and lineOk and peersLine == "Mit Ravenquill: 1 in der Gilde, 1 online",
  "a peer time that is not a number (broken SavedVariables): not a peer, no Lua error (" .. tostring(caraIsPeer) .. ", "
  .. tostring(peersLine) .. ")")
peersHere["Cara Moss"] = caraSeen
me.guild = "Andere Gilde"
check(coreNS.PeerCount() == 0 and not RQ:IsPeer("Bud Stone"), "another guild: none of the first guild's peers count")
RQ:NotePeer("Zed Other")
me.guild = "Die Gilde"
check(coreNS.PeerCount() == 2 and not RQ:IsPeer("Zed Other") and RQ:IsPeer("Bud Stone"), "back: the first guild's peers again, not the other's")
env.RavenquillExpeditionDB.peersByGuild["Andere Gilde@Forever"]["Zed Other"] = RQ:Now() - RQ.PEER_MAX_AGE - 5
RQ:PrunePeers()
check(env.RavenquillExpeditionDB.peersByGuild["Andere Gilde@Forever"] == nil, "PrunePeers drops old peers and empty guilds")
local guildInfo = env.GetGuildInfo
env.GetGuildInfo = function() end
check(RQ:Peers() ~= nil, "guild unknown for a moment: the last known guild is used")
env.GetGuildInfo = guildInfo
me.guild = nil
fire("PLAYER_GUILD_UPDATE")
local left = 0
for _ in RQ:EachMember() do left = left + 1 end
check(left == 0 and not RQ:RosterComplete() and RQ:RosterEntry("Bud Stone") == nil and RQ:OnlineCount() == 0
  and coreNS.PeerCount() == 0 and not RQ:IsPeer("Bud Stone") and RQ:OverviewPeersLine() == "Mit Ravenquill: 0 in der Gilde, 0 online",
  "leaving the guild: the old guild's roster and peers are gone (" .. left .. " roster members left)")
me.guild = "Die Gilde"
fire("PLAYER_GUILD_UPDATE")
fire("GUILD_ROSTER_UPDATE")
check(RQ:RosterEntry("Bud Stone") and RQ:IsPeer("Bud Stone"), "precondition: back in the first guild with its roster and peers")
me.guild = "Andere Gilde"
fire("PLAYER_GUILD_UPDATE")
local carried = 0
for _ in RQ:EachMember() do carried = carried + 1 end
check(carried == 0 and not RQ:RosterComplete() and RQ:RosterEntry("Bud Stone") == nil and RQ:OnlineCount() == 0
  and not RQ:IsPeer("Bud Stone") and RQ:IsGuildMember("Bud Stone") == nil,
  "switching straight to another guild: the old guild's roster and peers are gone (" .. carried .. " roster members left)")
me.guild = "Die Gilde"
fire("PLAYER_GUILD_UPDATE")
fire("GUILD_ROSTER_UPDATE")
check(RQ:MaxLevel() == 60, "MaxLevel")

section("Wire helpers (byte-compatible with Map's and CraftAdvisor's own)")
local W = RQ.Wire
check(W.b36(0) == "0" and W.b36(46655) == "zzz" and W.b36(-5) == "0" and W.b36(1800000000) == "tro8w0", "b36 (Map's form, negatives -> 0)")
check(W.b36s(-37) == "-11" and W.b36s(35) == "z", "b36s (CraftAdvisor's form, '-' for negatives)")
check(W.n36("zzz") == 46655 and W.n36("ZZ") == nil and W.n36("ZZ", true) == 1295 and W.n36("123456789") == nil and W.n36("") == nil,
  "n36 strict / loose, max 8 digits")
local parts = W.Split("a;;b;")
check(#parts == 4 and parts[2] == "" and parts[4] == "", "Split keeps empty fields")
check(W.Clean("|cffff0000Rot|r;x|y\n", 50) == "Rotxy" and W.Clean("ÄÄÄ", 3) == "Ä", "Clean strips codes / separators and cuts on UTF-8")
check(W.CLASSES[9] == "DRUID" and W.CLASS_IDX.SHAMAN == 6 and #W.CLASSES == 13, "class index table (1-9 = the wire contract)")

check(#me.errors == 2, "no other Lua errors (" .. #me.errors .. ")")

section("Overview footer: copy diagnostics")
RQ:Call(function() error("kaputt im Test") end)
RQ:ToggleOverview()
local footerHome = env.RavenquillExpeditionOverview.home
local diagButton
for _, c in ipairs(footerHome.options.controls) do
  if c and c:GetText() == "Diagnose kopieren" then diagButton = c end
end
local diagLink = footerHome.diagLink
check(diagButton == nil and diagLink ~= nil and diagLink.text:GetText() == "Diagnose kopieren",
  "the /rq footer offers 'Diagnose kopieren' as a quiet text link, not as a button among the options")
check(env.RavenquillExpeditionCopyBox == nil or not env.RavenquillExpeditionCopyBox:IsShown(), "precondition: no copy box shown")
if diagLink then rawget(diagLink, "_scripts").OnClick(diagLink) end
local diagBox = env.RavenquillExpeditionCopyBox
check(diagBox and diagBox:IsShown() and diagBox.text:find("Ravenquill Expedition v", 1, true)
  and diagBox.text:find("sync: queue", 1, true) and diagBox.text:find("kaputt im Test", 1, true),
  "clicking the link opens the copy box with the version, the sync state and the last error")

section("Overview home: one clickable row per module, its headline or its status")
do
  local ov = env.RavenquillExpeditionOverview
  local news, opened = 4, {}
  local board = RQ:NewModule("Board", { addon = "BoardAddon", title = "Anschlagbrett" })
  function board:OverviewStatus() return "12 Aushänge · Teilen an" end
  function board:OverviewHeadline()
    return { line = news .. " neue Aushänge · zuletzt Bud Stone", open = function() opened[#opened + 1] = "Brett" end }
  end
  function board:Open() opened[#opened + 1] = "Fenster" end
  local quiet = RQ:NewModule("Quiet", { addon = "QuietAddon", title = "Stille Post" })
  function quiet:BuildPage() end
  function quiet:OverviewStatus() return "3 Briefe" end
  function quiet:OverviewHeadline() return { line = "Keine neuen Briefe" } end
  local ledger = RQ:NewModule("Ledger", { addon = "LedgerAddon", title = "Kassenbuch",
    options = { { type = "toggle", label = "Buchen", get = function() return true end, set = function() end } } })
  function ledger:OverviewStatus() return "7 Buchungen" end
  local function HomeRow(title)
    for _, row in ipairs(ov.home.list and ov.home.list.items or {}) do
      if rawget(row, "_shown") and row.title:GetText() == title then return row end
    end
  end
  local function Line(title) local row = HomeRow(title); return row and row.line:GetText() end
  local function More(title) local row = HomeRow(title); return row ~= nil and rawget(row.more, "_shown") == true end
  local function Click(title)
    RQ:ShowHome()
    local row = HomeRow(title)
    if row then rawget(row, "_scripts").OnClick(row) end
  end
  RQ:ShowHome()
  check(Line("Anschlagbrett") == "4 neue Aushänge · zuletzt Bud Stone" and More("Anschlagbrett"),
    "a module's home row shows its headline instead of its status, with a '›' to open it: " .. tostring(Line("Anschlagbrett")))
  news = 6
  RQ:RefreshOverview()
  check(Line("Anschlagbrett") == "6 neue Aushänge · zuletzt Bud Stone",
    "the home reads the headline anew on each refresh: " .. tostring(Line("Anschlagbrett")))
  local row = HomeRow("Anschlagbrett")
  if row then rawget(row, "_scripts").OnEnter(row) end
  check(table.concat(env.GameTooltip.lines, " | ") == "12 Aushänge · Teilen an | Chatbefehl: /rq board",
    "hovering the row still shows the status and the chat command: " .. table.concat(env.GameTooltip.lines, " | "))
  Click("Anschlagbrett")
  check(table.concat(opened, ",") == "Brett" and RQ.optionsModule == nil,
    "clicking the row runs the headline's open, not the window and not the module page: " .. table.concat(opened, ","))
  Click("Stille Post")
  check(RQ.optionsModule == "Quiet" and not RQ.moduleSettings, "a headline without its own open: the row opens the module's page")
  RQ:ShowHome()
  check(Line("Stille Post") == "Keine neuen Briefe" and Line("Kassenbuch") == "7 Buchungen" and More("Kassenbuch"),
    "a module without the hook shows its status line on the home: " .. tostring(Line("Kassenbuch")))
  Click("Kassenbuch")
  check(RQ.optionsModule == "Ledger", "and its row opens the module in /rq")
  local broken = RQ:NewModule("Broken", { addon = "BrokenAddon", title = "Kaputt" })
  function broken:BuildPage() end
  function broken:OverviewStatus() return "läuft" end
  function broken:OverviewHeadline() error("Schlagzeile kaputt") end
  local errorsBefore = #me.errors
  RQ:ShowHome()
  check(Line("Kaputt") == "läuft" and #me.errors == errorsBefore + 1,
    "a failing headline hook reaches BugSack and the row falls back to the status: " .. tostring(Line("Kaputt")))
  Click("Kaputt")
  check(RQ.optionsModule == "Broken", "and the row still opens the module's page")
  broken.OverviewHeadline = nil
  while #me.errors > errorsBefore do table.remove(me.errors) end
  RQ:ShowHome()
end

section("Overview: a module page with entry cards")
do
  local ov = env.RavenquillExpeditionOverview
  me.frameMethods.SetTexture = function(s, v) s._texture = v end
  local needed, withCrafters, opened = 3, true, {}
  local cardsMod = RQ:NewModule("Cards", { addon = "CardsAddon", title = "Kartenmodul", icon = "Interface\\Icons\\INV_Misc_Note_01" })
  cardsMod.openHint = "Was dieses Modul zeigt."
  function cardsMod:OverviewEntries()
    local out = {
      { icon = "Interface\\Icons\\INV_Chest_Leather_09", title = "Bedarf", line = needed .. " Herstellungen lohnen sich",
        open = function() opened[#opened + 1] = "Bedarf" end },
      "kein Eintrag",
      { line = "ohne Titel" },
    }
    if withCrafters then
      out[#out + 1] = { title = "Handwerker", line = "Noch hat niemand Rezepte geteilt", open = function() opened[#opened + 1] = "Handwerker" end }
    end
    return out
  end
  local function CardTexts(page)
    local out = {}
    for _, card in ipairs(page and page.entries and page.entries.items or {}) do
      if rawget(card, "_shown") then out[#out + 1] = card.title:GetText() .. ": " .. card.line:GetText() end
    end
    return table.concat(out, " | ")
  end
  RQ:ShowHome()
  local tab
  for _, t in ipairs(ov.tabs) do if rawget(t, "_shown") and t.page == "Cards" then tab = t end end
  check(tab ~= nil, "a module that offers only entries gets a side tab in /rq")
  if tab then rawget(tab, "_scripts").OnClick(tab) end
  local page = ov.optView.pages.Cards
  local cards = page and page.entries and page.entries.items or {}
  check(RQ.optionsModule == "Cards" and page and page:IsShown() and page.hint:GetText() == "Was dieses Modul zeigt." and page.open == nil
    and CardTexts(page) == "Bedarf: 3 Herstellungen lohnen sich | Handwerker: Noch hat niemand Rezepte geteilt",
    "its page shows the hint, then one card per entry (title, line), no open button; broken entries are left out: " .. CardTexts(page))
  local first, second = cards[1] or {}, cards[2] or {}
  check(first.icon and first.icon._texture == "Interface\\Icons\\INV_Chest_Leather_09" and second.icon._texture == "Interface\\Icons\\INV_Misc_Note_01"
    and first.open:GetText() == "Öffnen" and rawget(first.open, "_shown") and rawget(second.open, "_shown"),
    "each card shows its icon (the module's when it names none) and an 'Öffnen' button")
  if second.open then rawget(second.open, "_scripts").OnClick(second.open) end
  check(table.concat(opened, ",") == "Handwerker", "'Öffnen' runs that card's open: " .. table.concat(opened, ","))
  needed, withCrafters = 8, false
  RQ:ShowHome()
  if tab then rawget(tab, "_scripts").OnClick(tab) end
  check(CardTexts(page) == "Bedarf: 8 Herstellungen lohnen sich", "showing the page again reads the entries anew, a dropped entry's card hides: " .. CardTexts(page))
  function cardsMod:OverviewEntries() error("Einträge kaputt") end
  local errorsBefore = #me.errors
  RQ:ShowHome()
  RQ:ShowModulePage("Cards")
  check(#me.errors == errorsBefore + 1 and CardTexts(page) == "" and page.hint:GetText() == "Was dieses Modul zeigt.",
    "a failing entries hook reaches BugSack and leaves no stale card, the hint stays: " .. CardTexts(page))
  local plain = RQ:NewModule("Plain", { addon = "PlainAddon", title = "Ohne Karten" })
  plain.openLabel, plain.openHint = "Fenster", "Ein Fenster mit allem."
  local plainOpened = false
  function plain:Open() plainOpened = true end
  RQ:ShowModulePage("Plain")
  local pp = ov.optView.pages.Plain
  if pp and pp.open then rawget(pp.open, "_scripts").OnClick(pp.open) end
  check(pp and pp:IsShown() and pp.entries == nil and pp.open:GetText() == "Fenster öffnen" and pp.hint:GetText() == "Ein Fenster mit allem."
    and plainOpened, "a module without entries keeps its page: the 'Fenster öffnen' button (it opens the window) and the hint")
  me.frameMethods.SetTexture = nil
end

section("Overview: a long options page shows a scrollbar and a fade at the bottom")
do
  local ov = env.RavenquillExpeditionOverview
  local methods, cursorY = me.frameMethods, 0
  local geometry = {
    SetPoint = function(s, point, ...) s._points = s._points or {}; s._points[point] = { ... } end,
    GetTop = function(s) return s._top end,
    GetEffectiveScale = function() return 1 end,
  }
  for k, fn in pairs(geometry) do methods[k] = fn end
  env.GetCursorPosition = function() return 0, cursorY end
  local function Toggles(size)
    local list = { { type = "header", label = "Kopf" } }
    for i = 1, size do list[#list + 1] = { type = "toggle", key = "t" .. i, label = "Schalter " .. i } end
    return list
  end
  RQ:NewModule("Short", { addon = "ShortAddon", title = "Kurz", options = Toggles(3) })
  local long = RQ:NewModule("Long", { addon = "LongAddon", title = "Lang", options = Toggles(30) })
  function long:Open() end
  local opt = ov.optView
  local sf = opt.scroll
  sf._h = 300
  local bar, fade = sf.scrollBar, sf.scrollFade
  local function Shown(f) return f ~= nil and rawget(f, "_shown") == true end
  local function ThumbTop() return -(bar.thumb._points.TOP[4]) end
  local function ThumbBottom() return ThumbTop() + bar.thumb._h end
  local function Wheel(delta) rawget(sf, "_scripts").OnMouseWheel(sf, delta) end
  local function Press(y) cursorY = 1000 - y; rawget(bar, "_scripts").OnMouseDown(bar, "LeftButton") end
  local function Release() rawget(bar, "_scripts").OnMouseUp(bar, "LeftButton") end

  RQ:ShowModuleOptions("Short")
  check(bar ~= nil and fade ~= nil and not Shown(bar) and not Shown(fade),
    "a page that fits shows neither a scrollbar nor a fade")

  RQ:ShowModuleOptions("Long")
  local content = opt.panels.Long:GetHeight()
  local max = content - 300
  check(content > 300 and Shown(bar) and Shown(fade) and sf:GetVerticalScroll() == 0,
    "a page taller than its view shows the scrollbar and the fade at the top (content " .. content .. ")")
  local thumbH = bar.thumb._h
  check(math.abs(thumbH - 300 * 300 / content) < 0.5 and ThumbTop() == 0,
    "the thumb is as tall as the visible share of the page and starts at the top: " .. tostring(thumbH))

  Wheel(-1)
  local afterWheel = sf:GetVerticalScroll()
  check(afterWheel == 40 and math.abs(ThumbTop() - (300 - thumbH) * 40 / max) < 0.5 and Shown(fade),
    "the wheel scrolls one step down and the thumb follows: " .. afterWheel .. ", thumb at " .. ThumbTop())

  bar._top = 1000
  Press(299)
  Release()
  check(sf:GetVerticalScroll() == max and math.abs(ThumbBottom() - 300) < 0.5 and not Shown(fade) and Shown(bar),
    "clicking the bottom of the track scrolls to the end: the thumb reaches the bottom, the fade goes away")

  rawget(bar, "_scripts").OnMouseWheel(bar, 1)
  check(sf:GetVerticalScroll() == max - 40 and Shown(fade) and ThumbBottom() < 300,
    "the wheel, here over the scrollbar, goes on from where the scrollbar left the page, the fade comes back: " .. sf:GetVerticalScroll())

  local grabbed = ThumbTop() + 5
  Press(grabbed)
  local before = sf:GetVerticalScroll()
  cursorY = cursorY + 50
  rawget(bar, "_scripts").OnUpdate(bar, 0.01)
  Release()
  check(math.abs(sf:GetVerticalScroll() - (before - 50 * max / (300 - thumbH))) < 0.5 and math.abs(ThumbTop() - (grabbed - 5 - 50)) < 0.5,
    "dragging the thumb 50 up scrolls the page by the same share and the thumb stays under the cursor: " .. sf:GetVerticalScroll())

  RQ:ShowModuleOptions("Short")
  check(sf:GetVerticalScroll() == 0 and not Shown(bar) and not Shown(fade), "switching to a page that fits hides both again")
  RQ:ShowModuleOptions("Long")
  RQ:ShowModulePage("Long")
  check(not Shown(bar) and not Shown(fade), "the module's own page (no settings list) shows neither")

  for k in pairs(geometry) do methods[k] = nil end
  env.GetCursorPosition = nil
end
Kit.finish()
