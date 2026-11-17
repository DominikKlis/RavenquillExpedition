unpack = table.unpack
local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local ADDONS = DEV .. "../../"
local RECORD = arg[1] == "--record"
local Golden = dofile(ADDONS .. "RavenquillExpedition/dev/golden.lua")
local gold = Golden.open(DEV .. "fixtures/compat_golden.lua", RECORD)
math.random = Golden.Random(99)

local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end

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
print_ = print
function geterrorhandler() return function(msg) print_("  ERROR " .. tostring(msg)) end end
function debugstack() return "" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
local frames = {}
local function obj()
  return setmetatable({}, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s, "_scripts") or {}; rawset(s, "_scripts", sc); sc[ev] = fn end end
    if k == "RegisterEvent" then return function(s, ev) local e = rawget(s, "_ev") or {}; rawset(s, "_ev", e); e[ev] = true end end
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
RAID_CLASS_COLORS = {}
function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function GetLocale() return "enUS" end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
Enum = { QuestTag = {} }
function UnitNameUnmodified(u) if u == "player" then return "Me", "Smith" end end
UnitName = UnitNameUnmodified
function UnitClass() return "Rogue", "ROGUE" end
function UnitLevel() return 30 end
function GetMaxPlayerLevel() return 60 end
function Ambiguate(n) return n end
function GetGuildInfo() return "Die Gilde" end
function GetNormalizedRealmName() return "Forever" end
function GetRealmName() return "Forever" end
function IsInGuild() return true end
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
function GetNumGuildMembers() return 1 end
function GetGuildRosterInfo() return "Me Smith-Forever", nil, nil, 30, nil, nil, nil, nil, true, nil, "ROGUE" end
C_GuildInfo = { GuildRoster = function() end }
function GetNumGroupMembers() return 0 end
function IsInRaid() return false end
local sent = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, chan)
    sent[#sent + 1] = prefix .. "|" .. chan .. "|" .. msg
    C_Timer.After(1, function() fire("CHAT_MSG_ADDON", prefix, msg, chan, "Me Smith-Forever") end)
    return 0
  end,
}
function hooksecurefunc(tbl, name, post)
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
end
C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER = 4, 4, 6, -1
C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end }
function GetInventoryItemLink() end
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
LOOT_ITEM, LOOT_ITEM_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d."

local function load(addon, file, ns) assert(loadfile(ADDONS .. addon .. "/" .. file))(addon, ns) end
local coreNS, hlNS = {}, {}
for _, f in ipairs(dofile(ADDONS .. "RavenquillExpedition/dev/toc.lua")(ADDONS .. "RavenquillExpedition")) do load("RavenquillExpedition", f, coreNS) end
for _, f in ipairs({ "Locale.lua", "Highlights.lua", "Wire.lua", "Detectors.lua", "LogWindow.lua" }) do
  load("RavenquillExpedition_Highlights", f, hlNS)
end
local GS, H = RavenquillExpedition, hlNS.H
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Highlights")
fire("PLAYER_LOGIN")
advance(5)

local ME = "Me Smith"
local T = BASE - 5000
local ENTRIES = {
  { k = "gear", t = T, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. T .. "#1", item = 12345, il = 33, q = 3, oil = 20, slot = 1 },
  { k = "loot", t = T + 1, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 1) .. "#2", item = 19019, q = 5, src = "bag" },
  { k = "loot", t = T + 2, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 2) .. "#3", item = 2000, q = 4 },
  { k = "loot", t = T + 3, who = "Bud Stone", lvl = 28, cls = "DRUID", by = ME, item = 3000, q = 4 },
  { k = "boss", t = T + 4, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 4) .. "#4", enc = 1084, first = true, raid = true,
    boss = "Onyxia", inst = "Onyxias Hort", grp = true, n = 12 },
  { k = "boss", t = T + 5, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 5) .. "#5", enc = 227, boss = "Taragaman der Hungerleider",
    inst = "Der Flammenschlund" },
  { k = "quest", t = T + 6, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 6) .. "#6", qid = 4321, ql = 32, tag = "elite",
    title = "Die Prüfung der Schädel – Grünäugige Gnolle" },
  { k = "quest", t = T + 7, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 7) .. "#7", qid = 4322, ql = 60, tag = "nonsense",
    title = string.rep("Überlange Questbeschreibung ", 6) },
  { k = "boss", t = T + 8, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 8) .. "#8", enc = 9, boss = string.rep("Ä", 60),
    inst = string.rep("Ö", 60), grp = true, n = 3 },
  { k = "level", t = T + 9, who = ME, lvl = 40, cls = "ROGUE", id = ME .. "#" .. (T + 9) .. "#9" },
  { k = "gear", t = T + 10, who = ME, lvl = 30, cls = "SHAMAN", id = ME .. "#" .. (T + 10) .. "#10", item = 1 },
}

print("== Encoder layer")
local bodies = {}
for i, e in ipairs(ENTRIES) do bodies[i] = H.Encode(e) or "<nil>" end
gold:compare("hl.encode", bodies, check)

print("== Lane layer")
sent = {}
for i, b in ipairs(bodies) do if b ~= "<nil>" then H.channel:Send(H.ToMessage(ENTRIES[i])) end end
advance(600)
gold:compare("hl.lane", sent, check)

print("== Decoder layer")
local goldBodies = RECORD and bodies or (gold.data["hl.encode"] or {})
local okDec, total = 0, 0
for i, e in ipairs(ENTRIES) do
  local b = goldBodies[i]
  if b and b ~= "<nil>" then
    total = total + 1
    local sender = e.by or e.who
    local d = H.Decode(sender, b)
    local same = d and d.k == e.k and d.t == e.t and d.who == e.who and d.lvl == e.lvl and d.cls == e.cls
      and (d.item == e.item or e.item == nil) and (d.enc == e.enc) and (d.qid == e.qid)
      and ((e.id and d.id == e.id) or (e.by and d.by == e.by))
    if same then okDec = okDec + 1 else print("    mismatch for entry " .. i) end
  end
end
check(okDec == total and total >= 10, ("%d/%d golden bodies decode to their entries"):format(okDec, total))

print("== SavedVariables layer: old shapes load into the same tables as before")
local function lines(s) local out = {} for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end return out end
local SV_CASES = {
  fresh = { nil, nil },
  v2 = { { v = 2, settings = { share = false, questRedLevels = 4, migratedV2 = true }, guilds = { ["G@R"] = { events = { { k = "level", t = 1 } } } } },
    { seq = 7, installedAt = 1700000000, outbox = { x = { t = 1 } } } },
  noVersionRed4 = { { settings = { questRedLevels = 4 } }, { seq = "3" } },
  junk = { { settings = "broken", guilds = 5 }, { outbox = "x", seq = "abc" } },
}
local names = {}
for name in pairs(SV_CASES) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local c = SV_CASES[name]
  RavenquillExpeditionHighlightsDB, RavenquillExpeditionHighlightsCharDB = c[1], c[2]
  RavenquillExpedition.SetupModuleDB(H)
  H:OnLoad()
  local cdb = RavenquillExpeditionHighlightsCharDB
  if cdb.installedAt == time() then cdb.installedAt = "<now>" end
  gold:compare("sv." .. name, lines(Golden.Serialize({ db = RavenquillExpeditionHighlightsDB, cdb = cdb })), check)
end

gold:finish()
print_(("%d passed, %d failed, 0 skipped"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
