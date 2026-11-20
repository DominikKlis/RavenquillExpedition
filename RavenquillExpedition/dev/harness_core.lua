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
local diagButton
for _, c in ipairs(env.RavenquillExpeditionOverview.home.options.controls) do
  if c and c:GetText() == "Diagnose kopieren" then diagButton = c end
end
check(diagButton ~= nil, "the /rq footer has a 'Diagnose kopieren' button")
check(env.RavenquillExpeditionCopyBox == nil or not env.RavenquillExpeditionCopyBox:IsShown(), "precondition: no copy box shown")
if diagButton then rawget(diagButton, "_scripts").OnClick(diagButton) end
local diagBox = env.RavenquillExpeditionCopyBox
check(diagBox and diagBox:IsShown() and diagBox.text:find("Ravenquill Expedition v", 1, true)
  and diagBox.text:find("sync: queue", 1, true) and diagBox.text:find("kaputt im Test", 1, true),
  "clicking it opens the copy box with the version, the sync state and the last error")
Kit.finish()
