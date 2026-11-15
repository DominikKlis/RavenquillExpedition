-- K15: GCA as the Ravenquill Expedition core module "Craft": registration, mod.options (contract of the core's
-- Overview.lua), Capture, OnSlash routing, command texts. Fakes _G.RavenquillExpedition before loading the addon;
-- the WoW mock below is the one of dev/harness.lua. Run: lua dev/harness_rq.lua
unpack = table.unpack
local fails, passes = 0, 0
local function check(cond, label)
  if cond then passes = passes + 1; io.write("  ok   ", label, "\n") else fails = fails + 1; io.write("  FAIL ", label, "\n") end
end
local printed = {}
local rawprint = print
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(t, " ")
  rawprint(...)
end
local function printedSince(n) return table.concat(printed, "\n", n + 1) end
function GetBuildInfo() return "1.60.1","70938","",16001 end
function UnitNameUnmodified(u) if u=="target" then return "Buddy","Stone" end return UnitName(u) end
RavenquillExpeditionCraftDB = { members = { ["Old-Timer"] = { time = 5, items = {} } } }
time = os.time
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
tinsert = table.insert
UISpecialFrames = {}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
local function runTimers() local n=0 while #timers>0 and n<200 do local t=table.remove(timers,1); t(); n=n+1 end end
-- generic object mock
local function obj()
  local o = {}
  return setmetatable(o, { __index = function(t, k) if not k:match("^%u") then return nil end
    if k == "GetChecked" or k=="IsShown" then return function(s) return rawget(s,"_shown") end end
    if k == "Show" then return function(s) s._shown = true; local sc=rawget(s,"_scripts"); if sc and sc.OnShow then sc.OnShow(s) end end end
    if k == "Hide" then return function(s) s._shown = false end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s,"_scripts") or {}; rawset(s,"_scripts",sc); sc[ev]=fn end end
    if k:match("^Create") then return function() return obj() end end
    if k == "RegisterEvent" then return function(s, ev) rawset(s,"_e",true) end end
    return function() end
  end })
end
CreateFrame = function(_, name) local o = obj(); if name then _G[name] = o end; return o end
UIParent = obj(); GameTooltip = obj(); GameTooltip_Hide = function() end
RAID_CLASS_COLORS = { DRUID = {r=1,g=.49,b=.04}, ROGUE={r=1,g=.96,b=.41}, MAGE={r=.41,g=.8,b=.94} }
ITEM_QUALITY_COLORS = { [1]={r=1,g=1,b=1}, [2]={r=.1,g=1,b=.1}, [3]={r=0,g=.4,b=1} }
LOCALIZED_CLASS_NAMES_MALE = { DRUID="Druide", ROGUE="Schurke", MAGE="Magier" }
function InCombatLockdown() return false end
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumSubgroupMembers() return 1 end
function GetNumGroupMembers() return 2 end
function GetTime() return os.time() end
function GetRealmName() return "Realm" end
function Ambiguate(n) return (n:gsub("%-Realm$","")) end
SlashCmdList = {}
local units = {
  player = { name="Me", class="ROGUE", level=30, guid="G-me", items={ [8]="item:2302::::" } },
  target = { name="Buddy", class="DRUID", level=28, guid="G-buddy", items={ [5]="item:2300::::", [8]="item:2302::::" } },
  party1 = { name="Mage", class="MAGE", level=30, guid="G-mage", items={} },
}
function UnitName(u) local x=units[u]; return x and x.name end
function UnitClass(u) local x=units[u]; return x and x.class, x and x.class end
function UnitLevel(u) local x=units[u]; return x and x.level end
function UnitGUID(u) local x=units[u]; return x and x.guid end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitIsUnit(a,b) return units[a] and units[a]==units[b] end
function UnitIsInMyGuild(u) return units[u] ~= nil end
function UnitExists(u) return units[u] ~= nil end
function CanInspect() return true end
local notified
function NotifyInspect(u) notified = u end
function GetInventoryItemLink(u, slot) local x=units[u]; return x and x.items[slot] end
function GetInventorySlotInfo(t) return 1, "tex" end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i) if i==1 then return "Buddy Stone",nil,nil,28,nil,nil,nil,nil,true,nil,"DRUID" else return "Offy-Realm",nil,nil,50,nil,nil,nil,nil,false,nil,"ROGUE" end end
function GetProfessions() return 1, nil end
function GetProfessionInfo(i) return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
-- items: derive from the recipe table after load
local itemMeta = {}
C_Item = {
  GetItemInfoInstant = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id]; if not m then return id, "Misc","Misc","",1,15,0 end return id,"Armor","x",m.loc,1,4,m.sub end,
  GetItemInfo = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id] or {loc="",sub=0,lvl=1}; return "Item"..id, "|Hitem:"..id.."|h[Item"..id.."]|h", 2, 20, m.lvl, nil,nil,nil, m.loc, 1, nil, 4, m.sub, m.bind or 2 end,
  GetItemStats = function(link) local id = tonumber(link:match("item:(%d+)")); local m = itemMeta[id]; return m and m.stats or {} end,
  RequestLoadItemDataByID = function() end,
  GetItemNameByID = function(id) return "Reagent"..id end,
  GetItemCount = function() return 3 end,
}
C_SpellBook = { IsSpellKnown = function(id) return id == 2149 or id == 2160 or id == 3762 end }
local ns = {}

---------------------------------------------------------------------------
-- K15: a fake Ravenquill Expedition core (only what Core.lua's registration uses), German client
---------------------------------------------------------------------------
function GetLocale() return "deDE" end
Minimap = obj()
local RQ = { modules = {}, moduleOrder = {} }
function RQ:NewModule(name, mod)
  mod = mod or {}
  mod.name, mod.core = name, self
  if not self.modules[name] then self.moduleOrder[#self.moduleOrder + 1] = name end
  self.modules[name] = mod
  return mod
end
RavenquillExpedition = RQ

local function load(f) local chunk = assert(loadfile("C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/RavenquillExpedition_CraftAdvisor/"..f)); chunk("RavenquillExpedition_CraftAdvisor", ns) end
load("Locales/enUS.lua"); load("Locales/deDE.lua")
load("Data/Leatherworking.lua"); load("Data/Blacksmithing.lua"); load("Data/Tailoring.lua"); load("Data/Engineering.lua")
load("Data/Enchanting.lua"); load("Data/Enchants.lua")
load("Data/Weights.lua"); load("Scoring.lua"); load("Core.lua"); load("Spec.lua"); load("UI.lua")
local okSy, errSy = pcall(load, "Sync.lua")
print("Sync.lua loaded:", okSy, okSy and "" or tostring(errSy))
local okMM, errMM = pcall(load, "Minimap.lua")
print("Minimap.lua loaded:", okMM, okMM and "" or tostring(errMM))
local GCA = ns.GCA
local h = rawget(GCA,"_scripts").OnEvent
h(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
h(GCA, "PLAYER_LOGIN"); runTimers()

io.write("== K15: module registration\n")
check(GCA.onCore == true and GCA.CMD == "/rq craft", "GCA.onCore with the fake core")
local mod = RQ.modules.Craft
check(mod and GCA.rqModule == mod and mod.addon == "RavenquillExpedition_CraftAdvisor" and mod.slash == "craft", "module \"Craft\" registered (addon, slash)")
check(SLASH_GUILDCRAFTADVISOR1 == nil and SLASH_GUILDCRAFTADVISOR2 == nil, "/gca and /guildcraft not registered on the core")
check(type(SlashCmdList.GUILDCRAFTADVISOR) == "function", "SlashCmdList.GUILDCRAFTADVISOR kept (fallback/harnesses)")
check(type(mod.Open) == "function" and type(mod.OnSlash) == "function" and type(mod.OverviewStatus) == "function", "Open, OnSlash, OverviewStatus present")

io.write("== K15: options well-formed\n")
local opts = mod.options
check(type(opts) == "table" and #opts > 0, "mod.options is a non-empty list (" .. tostring(opts and #opts) .. " entries)")
local need = { header = {}, toggle = { "get", "set" }, range = { "get", "set" }, button = { "func" }, text = { "lines" } }
local bad, counts, byLabel = {}, {}, {}
for i, o in ipairs(opts or {}) do
  local req = type(o) == "table" and need[o.type]
  if not req then bad[#bad + 1] = i .. ": type " .. tostring(o and o.type)
  else
    counts[o.type] = (counts[o.type] or 0) + 1
    if type(o.label) ~= "string" or o.label == "" or o.label:match("^OPT_") then bad[#bad + 1] = i .. ": label " .. tostring(o.label) end
    for _, f in ipairs(req) do if type(o[f]) ~= "function" then bad[#bad + 1] = i .. ": " .. f end end
    if o.tooltip ~= nil and type(o.tooltip) ~= "string" then bad[#bad + 1] = i .. ": tooltip" end
    if o.disabled ~= nil and type(o.disabled) ~= "function" then bad[#bad + 1] = i .. ": disabled" end
    if o.type == "range" and not (type(o.min) == "number" and type(o.max) == "number" and type(o.step) == "number") then bad[#bad + 1] = i .. ": range bounds" end
    byLabel[o.label] = o
  end
end
check(#bad == 0, "every entry has a known type and its fields (" .. table.concat(bad, "; ") .. ")")
check(counts.header == 5 and counts.toggle == 7 and counts.range == 1 and counts.button == 7 and counts.text == 5,
  string.format("5 headers, 7 toggles, 1 range, 7 buttons, 5 text boxes (%s/%s/%s/%s/%s)", tostring(counts.header), tostring(counts.toggle),
  tostring(counts.range), tostring(counts.button), tostring(counts.text)))
local missingOpt = {}
for k in pairs(ns.missingL) do if k:match("^OPT_") then missingOpt[#missingOpt + 1] = k end end
check(#missingOpt == 0, "no missing OPT_ locale key (" .. table.concat(missingOpt, ", ") .. ")")
check(opts[1].label == "Vorschläge" and byLabel["Ziel jetzt betrachten"] and byLabel["Gruppe jetzt einlesen"]
  and byLabel["Sync erneut versuchen"] and byLabel["Minimap-Knopf neu platzieren"] and byLabel["Gespeicherte Ausrüstung vergessen"],
  "German labels (deDE client)")
for _, o in ipairs(opts) do if o.disabled then local ok = pcall(o.disabled); check(ok, "disabled() runs: " .. o.label) end end

io.write("== K15: toggles round-trip on db.settings\n")
local s = GCA.db.settings
for _, o in ipairs(opts) do
  if o.type == "toggle" then
    local v0 = o.get()
    o.set(not v0)
    local v1 = o.get()
    o.set(v0)
    check(type(v0) == "boolean" and v1 == not v0 and o.get() == v0, "toggle round-trip: " .. o.label)
  end
end
local function toggleFor(key, label)
  local o = byLabel[label]
  local before = s[key] and true or false
  o.set(not before)
  local ok = (s[key] and true or false) == not before
  o.set(before)
  return ok and (s[key] and true or false) == before
end
check(toggleFor("showUnlearned", ns.L.FILTER_UNLEARNED) and toggleFor("lookahead", ns.L.FILTER_LOOKAHEAD)
  and toggleFor("autoInspect", ns.L.FILTER_AUTOINSPECT) and toggleFor("sync", ns.L.FILTER_SYNC)
  and toggleFor("inspectTalents", ns.L.OPT_INSPECT_TALENTS), "toggles write the right db.settings keys")
local mm = byLabel[ns.L.OPT_MINIMAP]
mm.set(false)
local hid = s.minimapHide == true and mm.get() == false
mm.set(true)
check(hid and not s.minimapHide and mm.get() == true, "minimap toggle = not minimapHide")

io.write("== K15: range = leveling bonus\n")
local range
for _, o in ipairs(opts) do if o.type == "range" then range = o end end
local inval, realInval = 0, GCA.InvalidateScores
GCA.InvalidateScores = function(self, ...) inval = inval + 1; return realInval(self, ...) end
range.set(25)
check(math.abs(s.survival - 0.25) < 1e-9 and range.get() == 25 and inval >= 1, "set(25) -> survival 0.25, get 25, scores invalidated")
range.set(150)
check(math.abs(s.survival - 1) < 1e-9 and range.get() == 100, "set clamps to 100")
range.set(50)
GCA.InvalidateScores = realInval
check(range.min == 0 and range.max == 100 and range.step == 5 and string.format(range.format, range.get()) == "50 %", "0-100 step 5, shows \"50 %\"")

io.write("== K15: text boxes\n")
local wrapper = print
for _, o in ipairs(opts) do
  if o.type == "text" then
    local ok, lines = pcall(o.lines)
    local allStr = ok and type(lines) == "table" and #lines > 0
    for _, l in ipairs(ok and type(lines) == "table" and lines or {}) do
      if type(l) ~= "string" or l:find("|c%x%x%x%x%x%x%x%x") or l:find("|r", 1, true) then allStr = false end
    end
    check(allStr and print == wrapper, "lines() -> plain strings, print restored: " .. o.label .. " (" .. tostring(ok and lines[1]) .. ")")
  end
end
local cap = GCA.Capture(function() print("|cff33ff99GuildCraft|r:", "|cffff0000red|r line\nsecond"); error("boom") end)
check(print == wrapper and cap[1] == "red line" and cap[2] == "second" and cap[3] and cap[3]:find("boom", 1, true) ~= nil,
  "Capture: colours stripped, lines split, error kept as last line, print restored after an error")
GCA.db.lastError = { where = "UI:Refresh", msg = "x.lua:1: oops\nstack", at = "2026-11-14 12:00:00" }
local le = byLabel[ns.L.OPT_DIAG_ERROR].lines()
check(le[1] == "2026-11-14 12:00:00  UI:Refresh" and le[2] == "x.lua:1: oops", "last error box shows db.lastError")

io.write("== K15: OnSlash routing\n")
local calls = {}
local realOpen, realStats, realEnch = GCA.OpenWindow, GCA.StatsDebug, GCA.EnchantDebug
GCA.OpenWindow = function() calls[#calls + 1] = "open" end
GCA.StatsDebug = function(_, l) calls[#calls + 1] = "stats " .. tostring(l) end
GCA.EnchantDebug = function(_, l) calls[#calls + 1] = "enchant " .. tostring(l) end
local link = "|cnIQ3:|Hitem:9449::::::::36:1488::1::1:28:5242:::::|h[Blade]|h|r"
for _, a in ipairs({ "stats " .. link, "Enchant Debug " .. link, "enchant debug", "", "inspect", "help", "sync retry", "minimap" }) do mod:OnSlash(a) end
check(calls[1] == "stats " .. link and calls[2] == "enchant " .. link and calls[3] == "enchant nil", "stats <link> / enchant debug [link] reach the debug commands (link case kept)")
check(#calls == 8 and calls[4] == "open" and calls[5] == "open" and calls[6] == "open" and calls[7] == "open" and calls[8] == "open", "anything else (incl. empty) opens the window")
GCA.OpenWindow, GCA.StatsDebug, GCA.EnchantDebug = realOpen, realStats, realEnch

io.write("== K15: Open shows (never closes) the window\n")
mod.Open(mod)
local shown1 = GCA.UI.frame and GCA.UI.frame:IsShown()
mod.Open(mod)
check(shown1 and GCA.UI.frame:IsShown(), "mod.Open opens the window and a second Open keeps it open")

io.write("== K15: command texts on the core\n")
local de = ns.Locales.deDE
local leftovers = {}
for _, t in pairs(ns.Locales) do for k, v in pairs(t) do if type(v) == "string" and v:find("/gca", 1, true) then leftovers[#leftovers + 1] = k end end end
check(#leftovers == 0, "no locale text names /gca (" .. table.concat(leftovers, ", ") .. ")")
check(ns.L.SYNC_STOPPED_MSG == de.SYNC_STOPPED_MSG_RQ and ns.L.MSG_RECORDED == de.MSG_RECORDED_RQ and ns.L.EMPTY_NOGEAR == de.EMPTY_NOGEAR_RQ
  and ns.L.WHISPER_DRAFT_KEPT == de.WHISPER_DRAFT_KEPT_RQ and ns.L.CMD_HELP == de.CMD_HELP_RQ and ns.L.HELP_LINES == de.HELP_LINES_RQ,
  "the six command texts use their core variants")
local removed = { "inspect", "scan", "whisper", "minimap", "reset", "verbose", "spec", "known", "sync" }
local named = {}
for _, k in ipairs({ "SYNC_STOPPED_MSG", "MSG_RECORDED", "EMPTY_NOGEAR", "WHISPER_DRAFT_KEPT", "CMD_HELP", "HELP_LINES" }) do
  for _, loc in ipairs({ "enUS", "deDE" }) do
    local v = ns.Locales[loc][k]
    for _, c in ipairs(removed) do if v:find("/rq craft " .. c, 1, true) then named[#named + 1] = loc .. "." .. k .. ":" .. c end end
  end
end
check(#named == 0, "core texts name no removed command (" .. table.concat(named, ", ") .. ")")

io.write(string.format("\n%d passed, %d failed\n", passes, fails))
os.exit(fails == 0 and 0 or 1)
