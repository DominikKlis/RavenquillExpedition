unpack = table.unpack
local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local ADDONS = DEV .. "../../"
local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1; io.write("  ok   ", what, "\n") else fail = fail + 1; io.write("  FAIL ", what, "\n") end
end
local function section(s) io.write("== ", s, "\n") end

local now, BASE = 100, 1800000000
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function advance(sec)
  local stop = now + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1); now = math.max(now, t.at); t.fn()
  end
  now = stop
end
function GetTime() return now end
function GetServerTime() return BASE + math.floor(now) end
time = function() return BASE + math.floor(now) end
date = os.date
local errors, printed = {}, {}
function geterrorhandler() return function(msg) errors[#errors + 1] = msg end end
function debugstack() return "" end
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
local frames = {}
local function obj()
  return setmetatable({}, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s, "_scripts") or {}; rawset(s, "_scripts", sc); sc[ev] = fn end end
    if k == "RegisterEvent" then return function(s, ev) local e = rawget(s, "_ev") or {}; rawset(s, "_ev", e); e[ev] = true end end
    if k == "UnregisterEvent" then return function(s, ev) local e = rawget(s, "_ev") or {}; e[ev] = nil end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return obj() end end
    return function() end
  end })
end
function CreateFrame() local o = obj(); frames[#frames + 1] = o; return o end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    local ev, sc = rawget(f, "_ev"), rawget(f, "_scripts")
    if ev and ev[event] and sc and sc.OnEvent then sc.OnEvent(f, event, ...) end
  end
end
UIParent, GameTooltip = obj(), obj()
UISpecialFrames, SlashCmdList = {}, {}
local G = { locale = "deDE", guild = "Die Gilde", realm = "Forever", inGuild = true,
  roster = { { "Me Smith-Forever", 30, "ROGUE", true }, { "Bud Stone-Forever", 28, "DRUID", true },
             { "Cara Moss-Forever", 31, "MAGE", false }, { "Anna Muller-Lee-Forever", 20, "PRIEST", true } } }
function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function GetLocale() return G.locale end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function UnitNameUnmodified(u) if u == "player" then return "Me", "Smith" end end
UnitName = UnitNameUnmodified
function Ambiguate(n) return n end
function GetGuildInfo() return G.guild end
function GetNormalizedRealmName() return G.realm end
function GetRealmName() return G.realm end
function IsInGuild() return G.inGuild end
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
function GetMaxPlayerLevel() return 60 end
function GetNumGuildMembers() return #G.roster end
function GetGuildRosterInfo(i) local r = G.roster[i]; return r[1], nil, nil, r[2], nil, nil, nil, nil, r[4], nil, r[3] end
C_GuildInfo = { GuildRoster = function() end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end }
function hooksecurefunc(tbl, name, post)
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
end

local coreNS = {}
for _, f in ipairs(dofile(DEV .. "toc.lua")(ADDONS .. "RavenquillExpedition")) do
  assert(loadfile(ADDONS .. "RavenquillExpedition/" .. f))("RavenquillExpedition", coreNS)
end
local RQ = RavenquillExpedition
fire("ADDON_LOADED", "RavenquillExpedition")

section("Module: SavedVariables, defaults, migrations")
check(RQ.API == 2, "core API is 2")
local order = {}
TestModDB = { v = 1, settings = { share = "yes", keep = 5 }, old = true }
TestModCharDB = { seq = "x" }
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
local db = TestModDB
check(table.concat(order, ",") == "2,3,OnLoad:4", "migrations 2 and 3 ran in order from v+1, then OnLoad (" .. table.concat(order, ",") .. ")")
check(db.v == 4 and db.renamed and db.old == nil and db.who == "Test", "db.v = dbVersion; migrations got db, cdb, mod")
check(mod.db == db and mod.settings == db.settings, "mod.db and mod.settings ready in OnLoad")
check(db.settings.share == true and db.settings.keep == 5 and db.settings.size == 1, "wrong-typed setting replaced, unknown kept, missing filled")
db.settings.list[1] = 9
check(mod.defaults.list[1] == 1, "table defaults are copied, not shared")
check(mod.cdb == TestModCharDB and mod.cdb.seq == 0 and type(mod.cdb.outbox) == "table", "per-character table with its defaults")
check(mod.L.HELLO == "Hallo" and mod.L.ONLY_EN == "only english" and mod.L.NOPE == "NOPE", "locale: client language, then English, then the key")

FailDB = { v = 0 }
local ran3 = false
local fm = RQ:NewModule("Failing", { addon = "FailAddon", sv = "FailDB", dbVersion = 3,
  migrations = { [1] = function() end, [2] = function() error("broken migration") end, [3] = function() ran3 = true end } })
local errBefore = #errors
fire("ADDON_LOADED", "FailAddon")
check(FailDB.v == 1 and not ran3 and #errors == errBefore + 1, "a failing migration stops the chain (v stays 1) and reaches BugSack")
check(fm.db == FailDB, "the module still gets its db")

check(FreshDB == nil, "precondition: no FreshDB")
RQ:NewModule("Fresh", { addon = "FreshAddon", sv = "FreshDB", dbVersion = 2, defaults = { a = 1 } })
fire("ADDON_LOADED", "FreshAddon")
check(type(FreshDB) == "table" and FreshDB.v == 2 and FreshDB.settings.a == 1, "fresh install: table created at the current version")

section("Module: API check, login, guild changes")
local future = RQ:NewModule("Future", { addon = "FutureAddon", api = 99 })
check(RQ:GetModule("Future") == nil and future.Print, "a module needing API 99 is not registered (but gets a usable table)")
check(printed[#printed]:find("API 99", 1, true) ~= nil, "and the player is told once: " .. tostring(printed[#printed]))
local logins, guildChanges = 0, {}
function mod:OnLogin() logins = logins + 1 end
function mod:OnGuildChanged(new, old) guildChanges[#guildChanges + 1] = tostring(old) .. ">" .. tostring(new) end
fire("PLAYER_LOGIN")
check(logins == 1 and db.loginRan == 1 and db.vLogin == 1, "PLAYER_LOGIN: login migrations, then OnLogin")
fire("PLAYER_GUILD_UPDATE")
check(#guildChanges == 0, "guild update with the same guild: no OnGuildChanged")
G.guild = "Neue Gilde"
fire("PLAYER_GUILD_UPDATE")
G.guild, G.inGuild = nil, false
fire("PLAYER_GUILD_UPDATE")
check(guildChanges[1] == "Die Gilde@Forever>Neue Gilde@Forever" and guildChanges[2] == "Neue Gilde@Forever>nil",
  "OnGuildChanged on a real change and on leaving: " .. table.concat(guildChanges, " | "))
G.guild, G.inGuild = "Die Gilde", true
fire("PLAYER_GUILD_UPDATE")

section("Module: events, timers, guild store, options")
local got = {}
mod:RegisterEvent("BAG_UPDATE", function(m, bag) got[#got + 1] = (m == mod) and bag end)
function mod:PLAYER_LEVEL_UP(level) got[#got + 1] = "lvl" .. level end
mod:RegisterEvent("PLAYER_LEVEL_UP")
fire("BAG_UPDATE", 3); fire("PLAYER_LEVEL_UP", 31)
check(got[1] == 3 and got[2] == "lvl31", "RegisterEvent: handler(mod, ...) or the method of the same name")
mod:RegisterEvent("PLAYER_MONEY", function() error("handler bug") end)
errBefore = #errors
fire("PLAYER_MONEY")
check(#errors == errBefore + 1, "an error in a handler reaches BugSack (RQ:Call), the next event still works")
mod:UnregisterEvent("BAG_UPDATE")
fire("BAG_UPDATE", 4)
check(#got == 2, "UnregisterEvent")
local ticks, after = 0, false
mod:After(5, function(m) after = (m == mod) end)
local h = mod:Every(10, function() ticks = ticks + 1 end)
advance(35)
h:Cancel()
advance(50)
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

section("Names and roster")
fire("GUILD_ROSTER_UPDATE")
check(RQ:PlayerKey() == "Me Smith" and RQ:IsMe("Me Smith-Forever") and not RQ:IsMe("Bud Stone"), "PlayerKey / IsMe with the realm suffix")
check(RQ:NormName("Anna Muller-Lee-Forever") == "Anna Muller-Lee" and RQ:StripRealm("Anna Muller-Lee") == nil,
  "only our own realm is stripped; hyphenated surnames stay")
check(RQ:RosterEntry("Bud Stone").class == "DRUID" and RQ:RosterEntry("Bud Stone-Forever") ~= nil, "RosterEntry, also with the realm suffix")
check(RQ:IsGuildMember("Cara Moss") == true and RQ:IsGuildMember("Nobody") == false, "IsGuildMember")
local loaded, count, offline = RQ:RosterComplete()
check(loaded and count == 4 and offline == 1 and RQ:OnlineCount() == 3, "RosterComplete / OnlineCount")
local n = 0
for _ in RQ:EachMember() do n = n + 1 end
check(n == 4 and RQ:RosterReadAt() == now, "EachMember / RosterReadAt")
RavenquillExpeditionDB.peersByGuild = nil
RavenquillExpeditionDB.peers = { ["Bud Stone"] = RQ:Now() - 100, ["Cara Moss"] = RQ:Now() - 5000 }
check(coreNS.PeerCount(3600) == 1 and coreNS.PeerCount() == 2, "PeerCount(window)")
check(RavenquillExpeditionDB.peers == nil and RavenquillExpeditionDB.peersByGuild["Die Gilde@Forever"]["Bud Stone"],
  "the old peers table moved into the current guild")
local peersHere = RavenquillExpeditionDB.peersByGuild["Die Gilde@Forever"]
peersHere["Anna Muller-Lee"] = RQ:Now() - RQ.PEER_MAX_AGE - 5
check(RQ:OverviewPeersLine() == "2 Gildenmitglieder mit Ravenquill (1 online)",
  "overview peers line: fresh peers on the roster, then the online ones (" .. RQ:OverviewPeersLine() .. ")")
peersHere["Anna Muller-Lee"] = nil
G.guild = "Andere Gilde"
check(coreNS.PeerCount() == 0 and not RQ:IsPeer("Bud Stone"), "another guild: none of the first guild's peers count")
RQ:NotePeer("Zed Other")
G.guild = "Die Gilde"
check(coreNS.PeerCount() == 2 and not RQ:IsPeer("Zed Other") and RQ:IsPeer("Bud Stone"), "back: the first guild's peers again, not the other's")
RavenquillExpeditionDB.peersByGuild["Andere Gilde@Forever"]["Zed Other"] = RQ:Now() - RQ.PEER_MAX_AGE - 5
RQ:PrunePeers()
check(RavenquillExpeditionDB.peersByGuild["Andere Gilde@Forever"] == nil, "PrunePeers drops old peers and empty guilds")
G.guild = nil
check(RQ:Peers() ~= nil, "guild unknown for a moment: the last known guild is used")
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

check(#errors == 2, "no other Lua errors (" .. #errors .. ")")
io.write(("%d passed, %d failed, 0 skipped\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
