unpack = table.unpack
local DIR = (arg[0]:gsub("[^/\\]*$", "")) .. "../.."
local fails, passes = 0, 0
local function check(cond, label)
  if cond then passes = passes + 1 else fails = fails + 1; io.write("  FAIL ", label, "\n") end
end

local now = 1000
local BASE = 1800000000
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function advance(sec)
  local stop = now + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1)
    now = math.max(now, t.at)
    t.fn()
  end
  now = stop
end
function GetTime() return now end
function GetServerTime() return BASE + math.floor(now) end
time = function() return BASE + math.floor(now) end
date = os.date
local printed = {}
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(t, " ")
end
local function lastPrinted() return printed[#printed] or "" end
local function printedSince(n) return table.concat(printed, "\n", n + 1) end
local errors = {}
function geterrorhandler() return function(msg) errors[#errors + 1] = msg; io.write("  ERROR ", tostring(msg), "\n") end end
function debugstack() return "" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
math.random = function() return 0.5 end
local SECRET = setmetatable({}, { __eq = function() error("compared a secret") end,
  __tostring = function() error("used a secret") end, __index = function() error("indexed a secret") end })
function issecretvalue(v) return rawequal(v, SECRET) end

local frames = {}
local lines = {}
local function obj()
  return setmetatable({}, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "IsShown" then return function(s) return rawget(s, "_shown") end end
    if k == "SetChecked" then return function(s, v) rawset(s, "_checked", v and true or false) end end
    if k == "GetChecked" then return function(s) return rawget(s, "_checked") end end
    if k == "Disable" then return function(s) rawset(s, "_disabled", true) end end
    if k == "Enable" then return function(s) rawset(s, "_disabled", false) end end
    if k == "IsEnabled" then return function(s) return not rawget(s, "_disabled") end end
    if k == "SetText" then return function(s, v) rawset(s, "_text", v) end end
    if k == "GetText" then return function(s) return rawget(s, "_text") end end
    if k == "GetVerticalScroll" or k == "GetHeight" then return function() return 0 end end
    if k == "Show" then return function(s) s._shown = true; local sc = rawget(s, "_scripts"); if sc and sc.OnShow then sc.OnShow(s) end end end
    if k == "Hide" then return function(s) s._shown = false end end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s, "_scripts") or {}; rawset(s, "_scripts", sc); sc[ev] = fn end end
    if k == "RegisterEvent" then return function(s, ev) local e = rawget(s, "_ev") or {}; rawset(s, "_ev", e); e[ev] = true end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return obj() end end
    if k == "AddMessage" then return function(_, m) lines[#lines + 1] = m end end
    if k == "Clear" then return function() wipe(lines) end end
    return function() end
  end })
end
function CreateFrame(_, name, _, template)
  if template == "ButtonFrameTemplate" then error("no template in mock") end
  local o = obj()
  frames[#frames + 1] = o
  if name then _G[name] = o end
  return o
end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    local ev, sc = rawget(f, "_ev"), rawget(f, "_scripts")
    if ev and ev[event] and sc and sc.OnEvent then sc.OnEvent(f, event, ...) end
  end
end
UIParent, GameTooltip = obj(), obj()
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = { ROGUE = { colorStr = "fffff569" }, DRUID = { colorStr = "ffff7d0a" }, MAGE = { colorStr = "ff3fc7eb" } }

local G = {
  inInstance = false, itype = "none", instName = "Elwynn",
  level = 30, inCombat = false, guild = "Die Gilde",
  equipped = {}, items = {}, bags = { [0] = {} }, bank = { [-1] = {} },
  quests = {}, tags = {},
  group = {}, raid = false, sent = {}, sendResult = 0,
  roster = { { "Me Smith-Forever", 30, "ROGUE" }, { "Bud Stone-Forever", 28, "DRUID" }, { "Cara Moss-Forever", 31, "MAGE" },
             { "Abe Ash-Forever", 60, "WARRIOR" }, { "Dora Dunn-Forever", 33, "PRIEST" } },
}
function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function GetLocale() return "deDE" end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
Enum = { QuestTag = { Group = 1, Raid = 62, Dungeon = 81, Heroic = 85, Raid10 = 88, Raid25 = 89 } }
function UnitNameUnmodified(u)
  if u == "player" then return "Me", "Smith" end
  local g = G.group[u]
  if g then return g[1], g[2] end
end
UnitName = UnitNameUnmodified
function UnitClass() return "Schurke", "ROGUE" end
function UnitLevel() return G.level end
function GetMaxPlayerLevel() return 60 end
function Ambiguate(n) return n end
function GetGuildInfo() return G.guild end
function GetNormalizedRealmName() return "Forever" end
function GetRealmName() return "Forever" end
function IsInGuild() return true end
function IsInInstance() return G.inInstance, G.itype end
function GetInstanceInfo() return G.instName, G.itype end
function GetRealZoneText() return G.instName end
function InCombatLockdown() return G.inCombat end
function IsShiftKeyDown() return false end
function GetNumGuildMembers() return #G.roster end
function GetGuildRosterInfo(i) local r = G.roster[i]; return r[1], nil, nil, r[2], nil, nil, nil, nil, true, nil, r[3] end
C_GuildInfo = { GuildRoster = function() fire("GUILD_ROSTER_UPDATE") end }
function GetNumGroupMembers() local n = 0; for _ in pairs(G.group) do n = n + 1 end; return n end
function IsInRaid() return G.raid end
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, chan)
    if G.sendResult == 0 then G.sent[#G.sent + 1] = { prefix = prefix, msg = msg, chan = chan, t = now } end
    return G.sendResult
  end,
}
function hooksecurefunc(tbl, name, post)
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
end
local function link(id) local it = G.items[id]; return ("|cnIQ%d:|Hitem:%d::::::::30:::::|h[%s]|h|r"):format(it.q, id, it.name) end
local function idOf(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
C_Item = {
  GetItemInfo = function(x) local id = idOf(x); local it = G.items[id]; if not it or it.unloaded then return end; return it.name, link(id), it.q, it.il end,
  GetDetailedItemLevelInfo = function(x) local it = G.items[idOf(x)]; if not it or it.unloaded then return end; return it.il end,
  RequestLoadItemDataByID = function() end,
}
local function container(bag) if bag == -1 then return G.bank[-1] end; if bag >= 0 and bag <= 4 then return G.bags[bag] end; return G.bank[bag] end
C_Container = {
  GetContainerNumSlots = function(bag) return container(bag) and 16 or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local c = container(bag); local id = c and c[slot]
    if not id then return nil end
    return { itemID = id, quality = G.items[id].q, hyperlink = link(id) }
  end,
}
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER = 4, 4, 6, -1
C_AddOns = {
  IsAddOnLoaded = function(name) return name == "RavenquillExpedition" or name == "RavenquillExpedition_Highlights" end,
  GetAddOnInfo = function(name)
    if name == "RavenquillExpedition_CraftAdvisor" then return name, "Guild Craft Advisor", "", false, "DISABLED" end
    return name, nil, nil, false, "MISSING"
  end,
}
function GetInventoryItemLink(_, slot) local id = G.equipped[slot]; return id and link(id) end
C_QuestLog = {
  GetNumQuestLogEntries = function() return #G.quests end,
  GetInfo = function(i) local q = G.quests[i]; return { title = q.title, level = q.level, suggestedGroup = q.group or 0, isHeader = q.header or false, questID = q.id } end,
  GetQuestTagInfo = function(id) return G.tags[id] end,
  IsEliteQuest = function() return false end,
}
LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
LOOT_ITEM = "%1$s bekommt Beute: %2$s."
LOOT_ITEM_MULTIPLE = "%1$s bekommt Beute: %2$sx%3$d."

G.items = {
  [100] = { name = "Alter Helm", q = 2, il = 20 }, [101] = { name = "Neuer Helm", q = 3, il = 30 },
  [102] = { name = "Kleiner Helm", q = 3, il = 23 }, [103] = { name = "Epischer Helm", q = 4, il = 24 },
  [104] = { name = "Grüner Riesenhelm", q = 2, il = 45 }, [105] = { name = "Taschenschwert", q = 3, il = 60 },
  [106] = { name = "Angel", q = 1, il = 5 },
  [200] = { name = "Ring A", q = 2, il = 25 }, [201] = { name = "Ring B", q = 2, il = 26 },
  [300] = { name = "Grünes Ding", q = 2, il = 28 }, [301] = { name = "Lila Schwert", q = 4, il = 33 },
  [302] = { name = "Lila Stab", q = 4, il = 33 }, [303] = { name = "Lila Kette", q = 4, il = 33 },
  [304] = { name = "Lila Umhang", q = 4, il = 40 }, [305] = { name = "Lila Gürtel", q = 4, il = 40 },
  [306] = { name = "Lila Bankding", q = 4, il = 40 }, [307] = { name = "Altes Lila", q = 4, il = 40 },
}
G.equipped = { [1] = 100, [11] = 200, [12] = 201, [16] = 106 }
G.bags[0] = { [1] = 105, [2] = 307 }

local function load(addon, file, ns)
  local chunk, err = loadfile(DIR .. "/" .. addon .. "/" .. file)
  if not chunk then error(err) end
  chunk(addon, ns)
end
local coreNS, hlNS = {}, {}
for _, f in ipairs(dofile(DIR .. "/RavenquillExpedition/dev/toc.lua")(DIR .. "/RavenquillExpedition")) do load("RavenquillExpedition", f, coreNS) end
for _, f in ipairs({ "Locale.lua", "Highlights.lua", "Wire.lua", "Detectors.lua", "LogWindow.lua" }) do load("RavenquillExpedition_Highlights", f, hlNS) end
local GS, H = RavenquillExpedition, hlNS.H

fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Highlights")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
advance(5)

local function events() return (H:Log()) end
local function last() local e = events(); return e[#e] end
local function count() return #events() end
local function equip(slot, id) G.equipped[slot] = id; fire("PLAYER_EQUIPMENT_CHANGED", slot, id ~= nil) end
local function sendsOf(pattern)
  local c = 0
  for _, x in ipairs(G.sent) do if x.msg:find(pattern, 1, true) then c = c + 1 end end
  return c
end
local function sentKind(kind) return sendsOf("H;1;" .. kind .. ";") end
local function echoAll()
  for _, s in ipairs(G.sent) do if not s.echoed then s.echoed = true; fire("CHAT_MSG_ADDON", s.prefix, s.msg, "GUILD", "Me Smith") end end
end
local function recv(sender, body) fire("CHAT_MSG_ADDON", "RQE1", "H;" .. body, "GUILD", sender) end
local function T() return BASE + math.floor(now) end
local function outboxSize() local n = 0; for _ in pairs(H.cdb.outbox) do n = n + 1 end; return n end

check(GS:PlayerKey() == "Me Smith", "player key is 'First Surname'")
check(GS:GuildKey() == "Die Gilde@Forever", "guild key")
check(GS:NormName("Bud Stone-Forever") == "Bud Stone", "realm suffix stripped")
check(GS:NormName("Anna Muller-Lee") == "Anna Muller-Lee", "hyphenated surname kept")
check(GS:IsGuildMember("Bud Stone") == true and GS:IsGuildMember("Stranger X") == false, "roster read (names with -Realm)")

equip(1, 101); advance(2)
check(count() == 1 and last().k == "gear" and last().il == 30 and last().oil == 20, "big rare upgrade logged (+10)")
check(not lastPrinted():find("Neuer Helm", 1, true), "gear upgrades stay out of chat by default")
equip(1, 100); advance(2)
check(count() == 1, "re-equipping an old item is not logged")
equip(1, 102); advance(2)
check(count() == 1, "small upgrade (+3) not logged")
equip(1, 104); advance(2)
check(count() == 1, "green upgrade (+22) not logged (rare or better only)")
equip(11, 201); equip(12, 200); advance(2)
check(count() == 1, "ring swap not logged")
equip(16, 105); advance(2)
check(count() == 1, "a sword that was in the bags at install is not logged (review #4)")
equip(1, 103); advance(2)
check(count() == 2 and last().q == 4, "first epic in a slot logged even with a tiny gain")
check(lastPrinted():find("Epischer Helm", 1, true), "epic gear is printed in chat")
local chatHead = "|cff33ff99Ravenquill Expedition|r |cffbbbbbbGilden-Highlights|r: "
check(lastPrinted():sub(1, #chatHead) == chatHead, "highlight chat lines start with the suite and module title")
G.items[301].unloaded = true
equip(17, 301); advance(1)
check(count() == 2, "unloaded item waits")
G.items[301].unloaded = nil; advance(2)
check(count() == 3 and last().item == 301, "logged after the item data arrives (empty slot + epic)")
advance(3)
local CC = GS.CommConst
local gTimes = {}
for _, x in ipairs(G.sent) do if x.msg:find("H;1;g;", 1, true) then gTimes[#gTimes + 1] = x.t end end
check(CC.BURST >= 3 and #gTimes == 3, "three highlights sent within the burst (" .. #gTimes .. ")")
check(gTimes[3] and gTimes[3] - gTimes[2] < 1 / CC.RATE, ("the third without waiting for a refill (%s s after the second)"):format(
  gTimes[3] and tostring(gTimes[3] - gTimes[2]) or "-"))
advance(40)
check(sentKind("g") == 3, "nothing sent twice while waiting for the echo")
check(G.sent[1].prefix == "RQE1" and G.sent[1].chan == "GUILD", "shared prefix on GUILD")
echoAll(); advance(20)
check(outboxSize() == 0, "echo clears the outbox")
advance(120)
C_ChatInfo.SendAddonMessage("RQEMap1", "x", "GUILD")
C_ChatInfo.SendAddonMessage("GCAdv1", "y", "WHISPER")
check(GS.Comm.foreign == 1 and math.abs(GS.Comm.tokens - (CC.BURST - 1)) < 0.01,
  ("a foreign GUILD send costs a token, a whisper doesn't (%.2f of %d)"):format(GS.Comm.tokens, CC.BURST))

local n = count()
G.bags[0][3] = 304; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 1 and last().k == "loot" and last().src == "bag" and last().item == 304, "new epic in the bags logged")
fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 1, "the same epic is not logged twice")
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(305) .. ".", "Me Smith")
G.bags[0][4] = 305; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 2 and last().src == nil, "loot line + bag update = one entry")
G.items[308] = { name = "Lila ohne Punkt", q = 4, il = 41 }
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(308), "Me Smith")
check(count() == n + 3 and last().item == 308 and last().src == nil, "own loot line without the final period matches")
n = n + 1
fire("BANKFRAME_OPENED"); G.bags[0][5] = 306; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 2, "taking an epic out of the bank is not logged")
fire("BANKFRAME_CLOSED"); advance(2)
G.bags[0][6] = 307; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 2, "an epic owned at install is not logged")
fire("CHAT_MSG_LOOT", SECRET, SECRET)
check(H.db.diag.secretLoot == 1, "secret loot line counted, no error")
advance(60); echoAll(); advance(60); echoAll()

G.inInstance, G.itype, G.instName = true, "party", "Die Todesminen"
fire("PLAYER_ENTERING_WORLD")
local sentBefore = #G.sent
n = count()
fire("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 0)
fire("BOSS_KILL", 1144, "Edwin VanCleef")
fire("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 1)
check(count() == n + 1 and last().k == "boss" and last().first and last().inst == "Die Todesminen", "first dungeon kill logged once")
advance(120)
fire("BOSS_KILL", 1144, "Edwin VanCleef")
check(count() == n + 1, "repeat dungeon kill not logged")
check(#G.sent == sentBefore and next(GS.Comm.q) == nil, "nothing queued inside an instance")
GS:NotePeer("Cara Moss")
G.itype, G.instName, G.raid = "raid", "Geschmolzener Kern", true
G.group = { raid1 = { "Me", "Smith" }, raid2 = { "Cara", "Moss" }, raid3 = { "Bud", "Stone" }, raid4 = { "Rando", "Pug" } }
fire("PLAYER_ENTERING_WORLD")
fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
local luci = last()
check(luci.k == "boss" and luci.grp and luci.n == 3 and H.cdb.outbox[luci.id] and H.cdb.outbox[luci.id].rank == 1,
  "raid kill = group report, 3 guildies, my rank 1")
advance(4 * 3600)
fire("ENCOUNTER_END", 664, "Magmadar", 9, 40, 1)
local mag = last()
check(lastPrinted():find("2 Gildenmitglieder", 1, true), "group kill line names the guildie count")
G.inInstance, G.itype, G.raid, G.group, G.instName = false, "none", false, {}, "Burgschmied"
fire("PLAYER_ENTERING_WORLD")
advance(20)
recv("Cara Moss", ("1;b;%d;9;Cara Moss;31;7;663;0;1;Lucifron;Geschmolzener Kern;3"):format(luci.t + 30))
advance(200)
check(sentKind("b") == 2, "after a 4 h raid: the dungeon kill and Magmadar sent, Lucifron left to Cara")
local _, idx = H:Log()
check(idx[luci.id] == nil and H.cdb.outbox[luci.id] == nil and idx[mag.id] ~= nil, "my Lucifron replaced by Cara's report, Magmadar kept")
echoAll(); advance(5)
G.level = 60
G.inInstance, G.itype, G.instName = true, "party", "Stratholme"
n = count()
fire("BOSS_KILL", 456, "Baron Rivendare")
check(count() == n, "first dungeon kill at max level not logged")
G.level = 30
G.inInstance, G.itype, G.instName = false, "none", "Westfall"
fire("PLAYER_ENTERING_WORLD"); advance(5)

G.quests = {
  { title = "Westfall", header = true, id = 0 },
  { title = "Die Bruderschaft der Defias", level = 22, group = 5, id = 166 },
  { title = "Gemüse sammeln", level = 12, id = 9 },
  { title = "Der Elitekampf", level = 30, id = 77 },
  { title = "Zu schwer", level = 35, id = 78 },
  { title = "Ins Verlies", level = 28, id = 79 },
}
G.tags[77] = { tagID = 1 }
G.tags[79] = { tagID = 81 }
fire("QUEST_LOG_UPDATE"); advance(2)
fire("QUEST_TURNED_IN", 166, 1000, 500)
check(last().k == "quest" and last().tag == "group" and last().title == "Die Bruderschaft der Defias", "group quest logged")
n = count()
fire("QUEST_TURNED_IN", 166, 1000, 500)
check(count() == n, "the same quest is logged once per character (repeatables)")
fire("QUEST_TURNED_IN", 9, 100, 10)
check(count() == n, "normal quest not logged")
fire("QUEST_TURNED_IN", 77, 100, 10)
check(last().tag == "elite", "tag 1 = elite")
fire("QUEST_TURNED_IN", 79, 100, 10)
check(last().tag == "dungeon", "dungeon tag")
n = count()
fire("QUEST_TURNED_IN", 78, 100, 10)
check(count() == n, "quest 5 levels above: off by default")

n = count()
G.level = 39; fire("PLAYER_LEVEL_UP", 39)
check(count() == n, "level 39 not logged")
G.level = 40; fire("PLAYER_LEVEL_UP", 40)
check(last().k == "level" and last().lvl == 40, "level 40 logged")
G.level = 30
for _ = 1, 30 do advance(10); echoAll() end
advance(5)

n = count()
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(300) .. ".", "Me Smith")
check(count() == n, "own green loot not logged")
G.group = { party1 = { "Bud", "Stone" }, party2 = { "Dora", "Dunn" } }
local sentLoot = sentKind("l")
fire("CHAT_MSG_LOOT", "Bud Stone bekommt Beute: " .. link(302) .. ".", "Bud Stone")
check(last().who == "Bud Stone" and last().by == "Me Smith" and last().item == 302, "guildie's epic loot logged as seen by me")
recv("Bud Stone", ("1;l;%d;5;Bud Stone;28;9;302;4;"):format(T()))
advance(200)
check(sentKind("l") == sentLoot, "witness report suppressed by the looter's own report")
n = count()
fire("CHAT_MSG_LOOT", "Bud Stone bekommt Beute: " .. link(303) .. ".", "Bud Stone")
check(count() == n, "loot of a known suite user is left to them")
fire("CHAT_MSG_LOOT", "Dora Dunn bekommt Beute: " .. link(303) .. ".", "Dora Dunn")
for _ = 1, 20 do advance(10); echoAll() end
check(sentKind("l") == sentLoot + 1 and sendsOf(";w;Dora Dunn;") == 1, "unreported guildie loot sent as a witness report")
G.group = { party1 = { "Rando", "Pug" } }
n = count()
fire("CHAT_MSG_LOOT", "Rando Pug bekommt Beute: " .. link(303) .. ".", "Rando Pug")
check(count() == n, "non-guildie loot ignored")
G.group = {}
echoAll(); advance(5)

local act = H.cdb.activity
local function actOf(k, pred)
  local c = 0
  for _, a in ipairs(act) do if a.k == k and (not pred or pred(a)) then c = c + 1 end end
  return c
end
check(actOf("gear", function(a) return a.item == 102 end) == 1 and actOf("gear", function(a) return a.item == 104 end) == 1,
  "small and green upgrades go to the activity log")
check(actOf("loot", function(a) return a.item == 300 and a.q == 2 end) == 1, "own green loot goes to the activity log")
check(actOf("loot", function(a) return a.item == 303 end) == 0, "others' loot is not my activity")
check(actOf("quest", function(a) return a.qid == 9 and a.title == "Gemüse sammeln" end) == 1, "a normal quest goes to the activity log")
check(actOf("quest", function(a) return a.qid == 166 and a.tag == "group" end) == 1, "a repeated group quest goes to the activity log")
check(actOf("level", function(a) return a.lvl == 39 end) == 1, "a level that isn't a milestone goes to the activity log")
check(actOf("boss", function(a) return a.boss == "Edwin VanCleef" and not a.first end) == 1, "a repeat dungeon kill goes to the activity log")
check(actOf("boss", function(a) return a.boss == "Baron Rivendare" and a.first end) == 1, "a first kill at max level goes to the activity log")
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(300) .. "x3", "Me Smith")
advance(200)
check(act[#act].k == "loot" and act[#act].n == 3 and sendsOf(";300;") == 0, "stacked loot counted, activity never sent")
check(H:Format(act[#act]):find("x3", 1, true) and H:Format(act[#act]):find("erbeutet", 1, true), "activity line text")
local merged, nHL, nAct = H:LogLines()
check(#merged == nHL + nAct and nAct == #act, "log = highlights + activity")
local sorted = true
for k = 2, #merged do if merged[k].t < merged[k - 1].t then sorted = false end end
check(sorted, "merged by time")
H:Settings().logOnlyHighlights = true
merged = H:LogLines()
check(#merged == count(), "'only highlights' hides the activity")
H:Settings().logOnlyHighlights = false

n = count()
local t0 = T()
local mark = #printed
recv("Cara Moss", ("1;b;%d;7;Cara Moss;31;7;1150;1;0;Mutanus;Höhlen des Wehklagens"):format(t0))
check(count() == n + 1 and last().who == "Cara Moss" and last().first and last().cls == "MAGE", "guildie's boss kill received")
check(printedSince(mark):find("zum ersten Mal", 1, true) ~= nil, "received boss kill printed in chat")
recv("Cara Moss", ("1;b;%d;7;Cara Moss;31;7;1150;1;0;Mutanus;Höhlen des Wehklagens"):format(t0))
check(count() == n + 1, "duplicate ignored")
recv("Cara Moss", ("1;v;%d;8;Bud Stone;60;9"):format(t0))
check(count() == n + 1, "highlight about someone else rejected (only loot may be witnessed)")
recv("Cara Moss", ("1;v;%d;9;Cara Moss;60;7"):format(t0 + 9999))
check(count() == n + 1, "future timestamp rejected")
recv("Cara Moss", ("2;v;%d;9;Cara Moss;60;7"):format(t0))
check(count() == n + 1, "unknown version ignored")
recv("Cara Moss", ("1;l;%d;w;Stranger X;60;1;303;4;"):format(t0))
check(count() == n + 1, "witnessed loot of a non-guildie rejected")
recv("Cara Moss", ("1;q;%d;10;Cara Moss;31;7;166;22;dungeon;Böse|nZeile|cffff0000rot"):format(t0))
check(last().k == "quest" and last().title == "BösenZeilerot", "escape codes stripped from received texts")
G.inInstance = true
n = count()
recv("Cara Moss", ("1;v;%d;11;Cara Moss;40;7"):format(t0))
check(count() == n + 1, "messages are read inside an instance")
G.inInstance = false
G.guild = nil
n = count()
recv("Cara Moss", ("1;v;%d;12;Cara Moss;50;7"):format(t0))
local filed = H.db.guilds["Die Gilde@Forever"].events
G.guild = "Die Gilde"
check(count() == n + 1 and filed[#filed].lvl == 50, "entry filed under the cached guild key while GetGuildInfo is empty")

local long = string.rep("ä", 80)
local body = H.Encode({ k = "quest", t = t0, id = "Me Smith#" .. t0 .. "#3", who = "Me Smith", lvl = 30, cls = "ROGUE",
  qid = 5, ql = 30, tag = "elite", title = long })
check(body and #body + 2 <= 250, "long German title fits in one message")
local d = H.Decode("Me Smith", body)
check(d and d.title and d.title:match("^[ä]+$") and #d.title % 2 == 0, "title cut on a UTF-8 boundary")
body = H.Encode({ k = "boss", t = t0, id = "Me Smith#" .. t0 .. "#4", who = "Me Smith", boss = "A;B|c", inst = "X" })
d = H.Decode("Me Smith", body)
check(d and d.boss == "ABc", "separators stripped from texts")
for _, k in ipairs({ "gear", "loot", "boss", "quest", "level" }) do
  local e = { k = k, t = t0, id = "Me Smith#" .. t0 .. "#42", who = "Me Smith", lvl = 30, cls = "ROGUE", item = 101, il = 30, oil = 20, q = 3,
    slot = 1, enc = 5, boss = "B", inst = "I", first = true, qid = 9, ql = 12, tag = "group", title = "T", grp = true, n = 7, src = "bag" }
  local x = H.Decode("Me Smith", H.Encode(e))
  check(x and x.id == e.id and x.k == k and x.cls == "ROGUE", "round trip " .. k)
  if k == "boss" then check(x and x.grp and x.n == 7, "group report count survives") end
  if k == "loot" then check(x and x.src == "bag", "loot source survives") end
end

echoAll(); advance(130)
wipe(H.cdb.outbox)
equip(2, 303); advance(2)
local id = last().id
local mine = ";" .. id:match("#(%d+)$") .. ";Me Smith;"
advance(40)
check(sendsOf(mine) == 1 and H.cdb.outbox[id] ~= nil, "sent but not echoed yet")
advance(900)
check(sendsOf(mine) == 2, "lost message retried once")
for _, x in ipairs(G.sent) do x.echoed = true end
advance(1300)
check(sendsOf(mine) == 3 and H.cdb.outbox[id] and H.cdb.outbox[id].hold, "after 3 tries it rests until the next login")
fire("PLAYER_LOGIN"); advance(100)
check(sendsOf(mine) == 4, "outbox retried after login")
for _, x in ipairs(G.sent) do if x.msg:find(mine, 1, true) then x.echoed = false end end
echoAll(); advance(20)
check(H.cdb.outbox[id] == nil, "outbox empty after echo")
advance(3700)
wipe(H.cdb.shareLog); wipe(H.cdb.outbox)
H:Settings().shareCap = 2
for _, lvl in ipairs({ 10, 20, 30 }) do fire("PLAYER_LEVEL_UP", lvl) end
check(outboxSize() == 2, "only shareCap highlights per hour are shared, the rest stay local")
H:Settings().shareCap = 8
advance(200); echoAll(); advance(5)

do
  local before, chatBefore = count(), #printed
  local fromCara = 0
  for _, e in ipairs(events()) do if e.who == "Cara Moss" then fromCara = fromCara + 1 end end
  for i = 1, 100 do
    recv("Cara Moss", ("1;v;%d;%d;Cara Moss;%d;7"):format(T(), 900 + i, 2 + (i % 50)))
    advance(30)
  end
  local nowCara = 0
  for _, e in ipairs(events()) do if e.who == "Cara Moss" then nowCara = nowCara + 1 end end
  check(nowCara - fromCara <= H.RECV_PER_HOUR, ("at most %d per sender per hour stored (%d)"):format(H.RECV_PER_HOUR, nowCara - fromCara))
  check(count() - before <= H.RECV_PER_HOUR and #printed - chatBefore <= H.RECV_PER_HOUR,
    "and at most that many chat lines (" .. (#printed - chatBefore) .. ")")
  check((H.db.diag.recvCapped or 0) >= 70, "the rest is counted, not stored")
end

check(H.db.diag.seen.ENCOUNTER_END and H.db.diag.last.QUEST_TURNED_IN, "event diagnostics recorded")
check(GS:Peers()["Cara Moss"] and RavenquillExpeditionDB.diagSender == nil, "peers recorded; no guildmate name stored for diagnosis")
local function opt(label)
  for i, o in ipairs(H.options) do if o.label == label then return i, o end end
end
SlashCmdList.RAVENQUILL("hl")
local ov = _G.RavenquillExpeditionOverview
check(ov and ov:IsShown() and GS.optionsModule == "Highlights", "/rq hl opens the Highlights options")
local panel = ov.optView.panels.Highlights
check(panel and #panel.controls == #H.options, "one control per option entry")
local L = hlNS.L
local iShare = opt(L.OPT_SHARE)
local iCap = opt(L.OPT_CAP)
local share = panel.controls[iShare]
check(share:GetChecked() == true, "share checkbox shows the setting")
share:SetChecked(false); rawget(share, "_scripts").OnClick(share)
check(H:Settings().share == false, "unticking 'send my highlights' turns sharing off")
check(panel.controls[iCap].plus:IsEnabled() == false, "the hourly cap is greyed out while sharing is off")
G.level = 50; fire("PLAYER_LEVEL_UP", 50); advance(100)
check(sendsOf(";Me Smith;50;") == 0 and last().lvl == 50, "logged but not sent while sharing is off")
share:SetChecked(true); rawget(share, "_scripts").OnClick(share)
check(H:Settings().share and panel.controls[iCap].plus:IsEnabled(), "sharing back on, cap enabled again")
local iRed = opt(L.OPT_RED)
for _ = 1, 4 do rawget(panel.controls[iRed].plus, "_scripts").OnClick() end
check(H:Settings().questRedLevels == 4, "the + button raises a range setting")
for _ = 1, 9 do rawget(panel.controls[iRed].plus, "_scripts").OnClick() end
check(H:Settings().questRedLevels == 10 and not panel.controls[iRed].plus:IsEnabled(), "a range stops at its maximum")
for _ = 1, 10 do rawget(panel.controls[iRed].minus, "_scripts").OnClick() end
check(H:Settings().questRedLevels == 0 and not panel.controls[iRed].minus:IsEnabled(), "and at its minimum")
local iChat, iAll = opt(L.OPT_CHAT), opt(L.OPT_CHAT_ALL)
local chat = panel.controls[iChat]
chat:SetChecked(false); rawget(chat, "_scripts").OnClick(chat)
check(not panel.controls[iAll]:IsEnabled(), "'also gear and quests' is greyed out while chat is off")
chat:SetChecked(true); rawget(chat, "_scripts").OnClick(chat)
local all = panel.controls[iAll]
all:SetChecked(true); rawget(all, "_scripts").OnClick(all)
check(H:Settings().chatAll and all:IsEnabled(), "chat all")
rawget(panel.controls[opt(L.OPT_TEST)], "_scripts").OnClick()
check(lastPrinted():find("6 Testeinträge", 1, true), "test button adds 6 test entries")
rawget(panel.controls[opt(L.OPT_OPEN_LOG)], "_scripts").OnClick()
check(_G.RavenquillExpeditionHighlightsFrame:IsShown() and lines[#lines]:find("Höchststufe 60", 1, true), "log button opens the window, test entry last")
rawget(panel.controls[opt(L.OPT_CLEARTEST)], "_scripts").OnClick()
check(lastPrinted():find("6 Testeinträge entfernt", 1, true), "test entries removed")
rawget(panel.controls[opt(L.OPT_DIAG)], "_scripts").OnClick()
local box = _G.RavenquillExpeditionCopyBox
check(box and box:IsShown() and box.text:find("events seen", 1, true) and box.text:find("last QUEST_TURNED_IN", 1, true),
  "diagnostics open in the copy box")
local text = box.text
box.eb:SetText("typed over")
rawget(box.eb, "_scripts").OnTextChanged(box.eb, true)
check(box.eb:GetText() == text, "the copy box is read-only")
local core = GS:DiagLines()
check(table.concat(core, "\n"):find("sync: queue", 1, true) and table.concat(core, "\n"):find("Cara Moss", 1, true), "core diagnostics (sync, peers)")
SlashCmdList.RAVENQUILL("hl share off")
check(H:Settings().share and GS.optionsModule == "Highlights", "old chat subcommands do nothing but open the options")

SlashCmdList.RAVENQUILL("")
check(ov:IsShown() and GS.optionsModule == nil, "/rq from the options view goes to the overview")
local rows = GS:OverviewRows()
check(rows[1].title == H.title and rows[1].state == "loaded" and rows[1].open and rows[1].options
  and rows[1].status:find("Einträge", 1, true), "Highlights row: loaded, status, Open, Options")
check(rows[2].state == "missing" and rows[2].slash == "/rq map", "Map row: not installed")
check(rows[3].state == "disabled" and rows[3].slash == "/rq craft" and rows[3].title == "Guild Craft Advisor", "Craft row: disabled")
check(#rows == 3, "three known rows, no duplicates")
_G.RavenquillExpeditionHighlightsFrame:Hide()
rawget(ov.home.rows[1].button, "_scripts").OnClick()
check(_G.RavenquillExpeditionHighlightsFrame:IsShown(), "Open button shows the Highlights window")
rawget(ov.home.rows[1].opt, "_scripts").OnClick()
check(GS.optionsModule == "Highlights" and ov.optView:IsShown() and not ov.home:IsShown(), "Options button switches to the options view")
GS:ShowHome()
check(rawget(ov.home.rows[2].button, "_shown") == false and rawget(ov.home.rows[2].opt, "_shown") == false, "no buttons for a missing module")
local recent = H:OverviewRecent(8)
check(type(recent) == "table" and #recent == 8 and recent[8]:find("Stufe 50", 1, true), "recent highlights for the overview")
local craft = GS:NewModule("Craft", { addon = "GuildCraftAdvisor", slash = "craft", title = "Guild Craft Advisor", icon = "Interface\\Icons\\Trade_LeatherWorking" })
local crafted = false
function craft:Open() crafted = true end
function craft:OverviewStatus() return "Gilden-Sync · 4 erfasst" end
rows = GS:OverviewRows()
check(#rows == 3 and rows[3].state == "loaded" and rows[3].status == "Gilden-Sync · 4 erfasst" and rows[3].open, "Craft module replaces the GCA row")
SlashCmdList.RAVENQUILL("craft")
check(crafted, "/rq craft without options opens its window")
local extra = GS:NewModule("Extra", { addon = "RavenquillExpedition_Extra", slash = "ex", title = "Extra" })
local helped = false
function extra:OnSlash(rest) helped = (rest == "") end
rows = GS:OverviewRows()
check(rows[4] and rows[4].title == "Extra" and not rows[4].open and not rows[4].options, "unknown module listed")
SlashCmdList.RAVENQUILL("ex")
check(helped, "/rq ex runs the module's OnSlash with no arguments")
local opened = false
local map = GS:NewModule("Map", { addon = "RavenquillExpedition_Map", slash = "map", title = "Karte", icon = "Interface\\Icons\\INV_Misc_Map_01" })
function map:Open() opened = true end
function map:OverviewStatus() return "Auf der Karte: 2 · Teilen an" end
local mapSize = 1
map.options = { { type = "toggle", label = "Teilen", get = function() return true end, set = function() end },
  { type = "range", label = "Größe", min = 0.5, max = 2, step = 0.1, format = "%.1f",
    get = function() return mapSize end, set = function(v) mapSize = v end } }
rows = GS:OverviewRows()
check(rows[2].title == "Karte" and rows[2].state == "loaded" and rows[2].status == "Auf der Karte: 2 · Teilen an" and rows[2].open and rows[2].options,
  "Map row uses the module's title, status, Open and options")
check(#rows == 4, "a registered Map is not listed twice")
GS:ShowHome()
rawget(ov.home.rows[2].button, "_scripts").OnClick()
check(opened, "Map's Open button calls mod:Open()")
SlashCmdList.RAVENQUILL("map")
check(GS.optionsModule == "Map" and ov.optView.panels.Map, "/rq map opens the map's options")
local sizePlus = ov.optView.panels.Map.controls[2].plus
for _ = 1, 10 do rawget(sizePlus, "_scripts").OnClick() end
check(math.abs(mapSize - 2) < 1e-9 and not sizePlus:IsEnabled(), "0.1 steps reach exactly the maximum and stop there")
for _ = 1, 3 do rawget(ov.optView.panels.Map.controls[2].minus, "_scripts").OnClick() end
check(("%.1f"):format(mapSize) == "1.7" and math.abs(mapSize - 1.7) < 1e-9, "0.1 steps down without drift")
function map:OverviewStatus() error("map not ready") end
local errBefore = #errors
rows = GS:OverviewRows()
check(rows[2].status == GS.OverviewL.LOADED and rows[2].open, "a failing status hook falls back to 'loaded', the row still works")
check(#errors == errBefore + 1, "the hook's error goes to BugSack")
table.remove(errors)
function map:OverviewStatus() return "Auf der Karte: 2 · Teilen an" end
SlashCmdList.RAVENQUILL("")
SlashCmdList.RAVENQUILL("")
check(not ov:IsShown(), "/rq on the overview closes it")
check(#errors == 0, "no Lua errors (" .. #errors .. ")")

local probe = GS:NewModule("Probe", { addon = "Probe" })
local okDup, errDup = pcall(probe.NewChannel, probe, { tag = "H" })
check(not okDup and tostring(errDup):find("already taken", 1, true), "a channel on Highlights' tag raises")
check(pcall(probe.NewChannel, probe, { tag = "ZZ" }), "a channel on a free tag works")
check(not pcall(probe.NewChannel, probe, { tag = "a;b" }), "a tag with ';' is rejected")
check(GS.TakeSendToken == nil, "the unused TakeSendToken is gone")
local peers = GS:Peers()
peers.Old, peers.Fresh, peers.Broken = GS:Now() - GS.PEER_MAX_AGE - 1, GS:Now() - 60, "x"
GS:PrunePeers()
check(peers.Old == nil and peers.Broken == nil and peers.Fresh,
  "PrunePeers drops peers older than PEER_MAX_AGE and broken entries")
check(type(GS.version) == "string" and GS.version ~= "", "core version comes from the .toc metadata (or 'dev')")

io.write(("%d passed, %d failed\n"):format(passes, fails))
if fails > 0 then os.exit(1) end
