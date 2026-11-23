local Kit = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check

local SECRET = setmetatable({}, { __eq = function() error("compared a secret") end,
  __tostring = function() error("used a secret") end, __index = function() error("indexed a secret") end })
local lines = {}
local G = {
  inInstance = false, itype = "none", instName = "Elwynn",
  level = 30, inCombat = false, guild = "Die Gilde",
  equipped = {}, items = {}, bags = { [0] = {} }, bank = { [-1] = {} },
  quests = {}, tags = {}, factions = {}, mounted = false, runSpeed = 0,
  group = {}, raid = false, sent = {}, sendResult = 0,
  roster = { { "Me Smith-Forever", 30, "ROGUE" }, { "Bud Stone-Forever", 28, "DRUID" }, { "Cara Moss-Forever", 31, "MAGE" },
             { "Abe Ash-Forever", 60, "WARRIOR" }, { "Dora Dunn-Forever", 33, "PRIEST" } },
}
local function link(id) local it = G.items[id]; return ("|cnIQ%d:|Hitem:%d::::::::30:::::|h[%s]|h|r"):format(it.q, id, it.name) end
local function idOf(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
local function container(bag) if bag == -1 then return G.bank[-1] end; if bag >= 0 and bag <= 4 then return G.bags[bag] end; return G.bank[bag] end
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

local sched = Kit.Scheduler({ start = 1000 })
local meOpts = { guild = "Die Gilde", realm = "Forever", locale = "deDE", class = "ROGUE",
  epoch = 1800000000, random = function() return 0.5 end, addons = { "RavenquillExpedition_Highlights" },
  setup = function(env, c)
    c.frameMethods.AddMessage = function(_, m) lines[#lines + 1] = m end
    c.frameMethods.Clear = function() env.wipe(lines) end
    c.frameMethods.Disable = function(s) s._disabled = true end
    c.frameMethods.Enable = function(s) s._disabled = false end
    c.frameMethods.IsEnabled = function(s) return not s._disabled end
    c.frameMethods.GetVerticalScroll = function() return 0 end
    c.frameMethods.GetHeight = function() return 0 end
    c.frameMethods.SetTextColor = function(s, r) s._red = r end
    env.ITEM_QUALITY3_DESC, env.ITEM_QUALITY4_DESC = "Selten", "Episch"
    local create = env.CreateFrame
    function env.CreateFrame(otype, name, parent, template)
      if template == "ButtonFrameTemplate" then error("no template in mock") end
      return create(otype, name, parent, template)
    end
    function env.issecretvalue(v) return rawequal(v, SECRET) end
    env.RAID_CLASS_COLORS = { ROGUE = { colorStr = "fffff569" }, DRUID = { colorStr = "ffff7d0a" }, MAGE = { colorStr = "ff3fc7eb" } }
    env.Enum = { QuestTag = { Group = 1, Raid = 62, Dungeon = 81, Heroic = 85, Raid10 = 88, Raid25 = 89 } }
    function env.UnitNameUnmodified(u)
      if u == "player" then return "Me", "Smith" end
      local g = G.group[u]
      if g then return g[1], g[2] end
    end
    env.UnitName = env.UnitNameUnmodified
    function env.UnitClass() return "Schurke", "ROGUE" end
    function env.UnitLevel() return G.level end
    function env.GetGuildInfo() return G.guild end
    function env.IsInGuild() return true end
    function env.IsInInstance() return G.inInstance, G.itype end
    function env.GetInstanceInfo() return G.instName, G.itype, nil, nil, nil, nil, nil, G.instID end
    function env.GetRealZoneText() return G.instName end
    function env.InCombatLockdown() return G.inCombat end
    function env.IsShiftKeyDown() return false end
    function env.GetNumGuildMembers() return #G.roster end
    function env.GetGuildRosterInfo(i) local r = G.roster[i]; return r[1], nil, nil, r[2], nil, nil, nil, nil, true, nil, r[3] end
    env.C_GuildInfo = { GuildRoster = function() c.fire("GUILD_ROSTER_UPDATE") end }
    function env.GetNumGroupMembers() local n = 0; for _ in pairs(G.group) do n = n + 1 end; return n end
    function env.IsInRaid() return G.raid end
    env.C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, chan)
        if G.sendResult == 0 then G.sent[#G.sent + 1] = { prefix = prefix, msg = msg, chan = chan, t = sched.t } end
        return G.sendResult
      end,
    }
    env.C_Item = {
      GetItemInfo = function(x) local id = idOf(x); local it = G.items[id]; if not it or it.unloaded then return end; return it.name, link(id), it.q, it.il end,
      GetDetailedItemLevelInfo = function(x) local it = G.items[idOf(x)]; if not it or it.unloaded then return end; return it.il end,
      RequestLoadItemDataByID = function() end,
    }
    env.C_Container = {
      GetContainerNumSlots = function(bag) return container(bag) and 16 or 0 end,
      GetContainerItemInfo = function(bag, slot)
        local ct = container(bag); local id = ct and ct[slot]
        if not id then return nil end
        return { itemID = id, quality = G.items[id].q, hyperlink = link(id) }
      end,
    }
    env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
    env.C_AddOns = {
      IsAddOnLoaded = function(name) return name == "RavenquillExpedition" or name == "RavenquillExpedition_Highlights" end,
      GetAddOnInfo = function(name)
        if name == "RavenquillExpedition_CraftAdvisor" then return name, "Guild Craft Advisor", "", false, "DISABLED" end
        return name, nil, nil, false, "MISSING"
      end,
    }
    function env.GetInventoryItemLink(_, slot) local id = G.equipped[slot]; return id and link(id) end
    env.C_QuestLog = {
      GetNumQuestLogEntries = function() return #G.quests end,
      GetInfo = function(i) local q = G.quests[i]; return { title = q.title, level = q.level, suggestedGroup = q.group or 0, isHeader = q.header or false, questID = q.id } end,
      GetQuestTagInfo = function(id) return G.tags[id] end,
      IsEliteQuest = function() return false end,
    }
    env.LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
    env.LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
    env.LOOT_ITEM = "%1$s bekommt Beute: %2$s."
    env.LOOT_ITEM_MULTIPLE = "%1$s bekommt Beute: %2$sx%3$d."
    env.LOOT_ITEM_CREATED_SELF = "Ihr stellt her: %s."
    env.FACTION_STANDING_CHANGED = "Ihr seid jetzt %s bei %s."
    env.FACTION_STANDING_LABEL6, env.FACTION_STANDING_LABEL7, env.FACTION_STANDING_LABEL8 = "Wohlwollend", "Respektvoll", "Ehrfürchtig"
    env.DUEL_WINNER_KNOCKOUT = "%1$s hat %2$s in einem Duell besiegt."
    env.DUEL_WINNER_RETREAT = "%2$s ist vor %1$s aus einem Duell geflohen."
    env.SKILL_RANK_UP = "Eure Fertigkeit in %s hat sich auf %d erhöht."
    env.C_Reputation = {
      GetNumFactions = function() return #G.factions end,
      GetFactionDataByIndex = function(i)
        local f = G.factions[i]
        if f then return { name = f[1], reaction = f[2], isHeader = f.header or false } end
      end,
    }
    function env.IsMounted() return G.mounted end
    function env.UnitOnTaxi() return false end
    function env.GetUnitSpeed() return 0, G.runSpeed end
  end }
local me = Kit.Client(sched, nil, "Me Smith", meOpts)
local env, fire, printed, errors = me.env, me.fire, me.printed, me.errors
local function advance(sec) sched:advance(sec) end
local function lastPrinted() local p = printed[#printed]; return p and p.text or "" end
local printedSince = me.printedSince
local hlNS = me.ns.RavenquillExpedition_Highlights
local GS, H = me.RQ, hlNS.H
local function LogPage(e) return e.RavenquillExpeditionOverview.optView.pages.Highlights end
local function OpenLog(e)
  e.RavenquillExpedition:ShowModulePage("Highlights")
  return LogPage(e)
end
local function CloseLog(e) LogPage(e):Hide() end

fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Highlights")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
advance(5)

Kit.section("Chat is off by default and the v3 update turns it off for everyone")
check(H:Settings().chat == false, "fresh install: highlights are not printed in chat")
do
  local keep = H.db
  env.RavenquillExpeditionHighlightsDB = { v = 2, settings = { chat = true, share = true } }
  me.coreNs.SetupModuleDB(H)
  check(H.db.v == 3 and H:Settings().chat == false, "v2 SavedVariables with chat on: the update switches chat off")
  H.db.settings.chat = true
  me.coreNs.SetupModuleDB(H)
  check(H:Settings().chat == true, "after the update the player can switch chat back on and it stays on")
  env.RavenquillExpeditionHighlightsDB = keep
  me.coreNs.SetupModuleDB(H)
end
H.db.settings.chat = true

local function events() return (H:Log()) end
local function last() local e = events(); return e[#e] end
local function lastOf(k)
  local list = events()
  for i = #list, 1, -1 do if list[i].k == k then return list[i] end end
end
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
local function T() return env.time() end
local function outboxSize() local n = 0; for _ in pairs(H.cdb.outbox) do n = n + 1 end; return n end

check(GS:PlayerKey() == "Me Smith", "player key is 'First Surname'")
check(GS:GuildKey() == "Die Gilde@Forever", "guild key")
check(GS:NormName("Bud Stone-Forever") == "Bud Stone", "realm suffix stripped")
check(GS:NormName("Anna Muller-Lee") == "Anna Muller-Lee", "hyphenated surname kept")
check(GS:IsGuildMember("Bud Stone") == true and GS:IsGuildMember("Stranger X") == false, "roster read (names with -Realm)")

for _, worn in ipairs({ { 1, 101 }, { 1, 102 }, { 1, 104 }, { 1, 103 }, { 16, 105 }, { 17, 301 } }) do equip(worn[1], worn[2]) end
advance(10)
check(count() == 0 and #H.cdb.activity == 0 and sentKind("g") == 0,
  "putting on gear, a rare upgrade or an epic, is no highlight, no activity and never sent")
fire("PLAYER_LEVEL_UP", 10); advance(1)
check(count() == 1 and last().k == "level" and lastPrinted():find("Stufe 10", 1, true), "a level highlight is printed in chat")
local chatHead = "|cff33ff99Ravenquill Expedition|r |cffbbbbbbGilden-Highlights|r: "
check(lastPrinted():sub(1, #chatHead) == chatHead, "highlight chat lines start with the suite and module title")
fire("PLAYER_LEVEL_UP", 20); advance(3)
fire("PLAYER_LEVEL_UP", 30); advance(3)
local CC = GS.CommConst
local vTimes = {}
for _, x in ipairs(G.sent) do if x.msg:find("H;1;v;", 1, true) then vTimes[#vTimes + 1] = x.t end end
check(CC.BURST >= 3 and #vTimes == 3, "three highlights sent within the burst (" .. #vTimes .. ")")
check(vTimes[3] and vTimes[3] - vTimes[2] < 1 / CC.RATE, ("the third without waiting for a refill (%s s after the second)"):format(
  vTimes[3] and tostring(vTimes[3] - vTimes[2]) or "-"))
advance(40)
check(sentKind("v") == 3, "nothing sent twice while waiting for the echo")
check(G.sent[1].prefix == "RQE1" and G.sent[1].chan == "GUILD", "shared prefix on GUILD")
echoAll(); advance(20)
check(outboxSize() == 0, "echo clears the outbox")
advance(120)
env.C_ChatInfo.SendAddonMessage("RQEMap1", "x", "GUILD")
env.C_ChatInfo.SendAddonMessage("GCAdv1", "y", "WHISPER")
check(GS.Comm.foreign == 1 and math.abs(GS.Comm.tokens - (CC.BURST - 1)) < 0.01,
  ("a foreign GUILD send costs a token, a whisper doesn't (%.2f of %d)"):format(GS.Comm.tokens, CC.BURST))

local n = count()
G.bags[0][3] = 304; fire("BAG_UPDATE_DELAYED"); advance(2)
local mailed = H.cdb.activity[#H.cdb.activity]
check(count() == n and mailed and mailed.k == "loot" and mailed.item == 304 and mailed.src == "bag",
  "an epic that arrives by mail, trade or auction is only an activity, not a highlight")
G.items[311] = { name = "Lila Belohnung", q = 4, il = 45 }
fire("QUEST_TURNED_IN", 5000, 100, 10)
G.bags[0][7] = 311; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 1 and last().k == "loot" and last().src == "quest" and last().item == 311
  and H:Format(last()):find("(Questbelohnung)", 1, true), "an epic quest reward is a loot highlight, marked as quest reward")
local reward = H.Decode("Me Smith", H.Encode(last()))
check(reward and reward.src == "quest", "the quest reward source survives the wire")
fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 1, "the same epic is not logged twice")
G.items[312] = { name = "Lila Spätpost", q = 4, il = 45 }
advance(H.QUEST_REWARD_WINDOW)
G.bags[0][8] = 312; fire("BAG_UPDATE_DELAYED"); advance(2)
check(count() == n + 1, "an epic that arrives later than the quest window is mail again, no highlight")
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
G.group = { party1 = { "Bud", "Stone" } }
fire("PLAYER_ENTERING_WORLD")
local sentBefore = #G.sent
n = count()
fire("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 0)
fire("BOSS_KILL", 1144, "Edwin VanCleef")
fire("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 1)
advance(120)
fire("BOSS_KILL", 1143, "Rhahk'Zor")
check(count() == n, "a dungeon run waits for its end")
check(H.cdb.run and H.cdb.run.with["Bud Stone"], "the run remembers the guildmate in the group")
G.inInstance, G.itype, G.instName = false, "none", "Westfall"
fire("PLAYER_ENTERING_WORLD"); advance(120)
G.inInstance, G.itype, G.instName = true, "party", "Die Todesminen"
fire("PLAYER_ENTERING_WORLD"); advance(H.RUN_GRACE + 60)
check(count() == n and H.cdb.run and H.cdb.run.left == nil, "a corpse run back in does not end the run")
check(#G.sent == sentBefore and next(GS.Comm.q) == nil, "nothing queued inside an instance")
GS:NotePeer("Cara Moss")
G.itype, G.instName, G.raid = "raid", "Geschmolzener Kern", true
G.group = { raid1 = { "Me", "Smith" }, raid2 = { "Cara", "Moss" }, raid3 = { "Bud", "Stone" }, raid4 = { "Rando", "Pug" } }
local runMark = #printed
fire("PLAYER_ENTERING_WORLD")
local run = last()
check(count() == n + 1 and run.k == "group" and run.inst == "Die Todesminen" and #run.with == 1 and run.with[1] == "Bud Stone"
  and H.cdb.run == nil, "entering another instance ends the run: one guild group line for the dungeon")
check(printedSince(runMark):find("|cfffff569Me Smith|r und |cffff7d0aBud Stone|r  ·  |cffffd100Die Todesminen|r geschafft", 1, true)
  ~= nil and not printedSince(runMark):find("Boss", 1, true), "its chat line names everyone in class colours, without a boss count")
local raidMark = #printed
fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
local luci = lastOf("boss")
local luciFirst = lastOf("first")
check(luci.k == "boss" and luci.grp and luci.n == 3 and H.cdb.outbox[luci.id] and H.cdb.outbox[luci.id].rank == 1,
  "raid kill = group report, 3 guildies, my rank 1")
advance(4 * 3600)
fire("ENCOUNTER_END", 664, "Magmadar", 9, 40, 1)
local mag = lastOf("boss")
check(not printedSince(raidMark):find("– mit 2 aus der Gilde", 1, true) and not H:Shown(luci) and not H:Shown(mag),
  "raid boss kills are records for the weekly goal: no chat line, no chronicle line")
check(luciFirst and luciFirst.what == "boss" and luciFirst.enc == 663 and luciFirst.grp and H:Shown(luciFirst)
  and printedSince(raidMark):find("Erster Kill der Gilde|r: |cffffd100Lucifron|r (Geschmolzener Kern)!", 1, true),
  "the guild's first Lucifron is a 'first in the guild' line of its own, reported for the raid")
G.inInstance, G.itype, G.raid, G.group, G.instName = false, "none", false, {}, "Burgschmied"
fire("PLAYER_ENTERING_WORLD")
advance(20)
recv("Cara Moss", ("1;b;%d;9;Cara Moss;31;7;663;0;1;Lucifron;Geschmolzener Kern;3"):format(luci.t + 30))
advance(200)
check(sentKind("b") == 1 and sentKind("o") == 1 and sentKind("d") == 0,
  "after a 4 h raid: the guild group and Magmadar sent, Lucifron left to Cara, no old run message")
local _, idx = H:Log()
check(idx[luci.id] == nil and H.cdb.outbox[luci.id] == nil and idx[mag.id] ~= nil, "my Lucifron replaced by Cara's report, Magmadar kept")
echoAll(); advance(5)
G.inInstance, G.itype, G.instName = true, "party", "Stratholme"
G.group = { party1 = { "Rando", "Pug" } }
fire("PLAYER_ENTERING_WORLD")
n = count()
fire("BOSS_KILL", 456, "Baron Rivendare")
G.inInstance, G.itype, G.instName, G.group = false, "none", "Westfall", {}
fire("PLAYER_ENTERING_WORLD"); advance(H.RUN_GRACE + 5)
check(count() == n and H.cdb.run == nil, "a run without guildmates is no line")
G.inInstance, G.itype, G.instName = true, "party", "Die Todesminen"
G.group = { party1 = { "Dora", "Dunn" } }
fire("PLAYER_ENTERING_WORLD")
fire("BOSS_KILL", 1144, "Edwin VanCleef")
fire("BOSS_KILL", 1145, "Mr. Smite")
G.inInstance, G.itype, G.instName, G.group = false, "none", "Westfall", {}
fire("PLAYER_ENTERING_WORLD"); advance(H.RUN_GRACE - 10)
check(count() == n, "the run stays open for a while after leaving")
advance(20)
run = last()
check(count() == n + 1 and run.k == "group" and run.with[1] == "Dora Dunn", "a later run with a guildmate is its own line")
check(H:Format({ k = "run", who = "Me Smith", first = true, n = 1, inst = "Die Todesminen" }):find("geschafft: ein Boss", 1, true),
  "an old run entry still reads as before")
local runBack = H.Decode("Me Smith", H.Encode(run))
check(runBack and runBack.k == "group" and runBack.inst == "Die Todesminen" and #runBack.with == 1 and runBack.with[1] == "Dora Dunn"
  and runBack.grp and runBack.id == run.id, "guild group round trip")
echoAll(); advance(200); echoAll(); advance(5)

G.quests = {
  { title = "Westfall", header = true, id = 0 },
  { title = "Die Bruderschaft der Defias", level = 22, group = 5, id = 166 },
  { title = "Gemüse sammeln", level = 12, id = 9 },
  { title = "Der Elitekampf", level = 30, id = 77 },
  { title = "Zu schwer", level = 35, id = 78 },
  { title = "Ins Verlies", level = 28, id = 79 },
  { title = "Einstimmung auf den Kern", level = 60, id = 7848 },
  { title = "Der Segen des Windsuchers", level = 60, id = 90 },
  { title = "Der Kopf von Onyxia", level = 60, id = 91 },
}
G.tags[77] = { tagID = 1 }
G.tags[79] = { tagID = 81 }
G.tags[90] = { tagID = 83 }
G.tags[91] = { tagID = 62 }
fire("QUEST_LOG_UPDATE"); advance(2)
n = count()
local actsBefore = #H.cdb.activity
for _, qid in ipairs({ 166, 9, 77, 78, 79, 90, 91 }) do fire("QUEST_TURNED_IN", qid, 100, 10) end
check(count() == n and #H.cdb.activity == actsBefore, "no quest is a highlight or an activity, legendary and raid quests included")
fire("QUEST_TURNED_IN", 7848, 1000, 500)
local step, ready
for _, e in ipairs(events()) do
  if e.k == "quest" and e.qid == 7848 then step = e end
  if e.k == "ready" then ready = e end
end
check(count() == n + 2 and step and step.tag == "special" and step.title == "Einstimmung auf den Kern" and not H:Shown(step),
  "an attunement step is kept for raid readiness, without a chronicle line")
check(ready and ready.raid == "mc" and H:Shown(ready) and H:Format(ready):find("raidbereit für |cffffd100Geschmolzener Kern|r", 1, true),
  "the last step for Molten Core makes the character raid ready, with a line of its own")
local readyBack = ready and H.Decode("Me Smith", H.Encode(ready))
check(readyBack and readyBack.k == "ready" and readyBack.raid == "mc" and readyBack.id == ready.id, "raid ready round trip")
fire("QUEST_TURNED_IN", 7848, 1000, 500)
check(count() == n + 2, "the same step is kept once per character, and ready is said once")

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
env.wipe(H.cdb.shareLog)
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
check(actOf("gear") == 0, "gear changes leave no activity either")
check(actOf("loot", function(a) return a.item == 300 and a.q == 2 end) == 1, "own green loot goes to the activity log")
check(actOf("loot", function(a) return a.item == 303 end) == 0, "others' loot is not my activity")
check(actOf("quest") == 0, "quests leave no activity")
check(actOf("level", function(a) return a.lvl == 39 end) == 1, "a level that isn't a milestone goes to the activity log")
check(actOf("boss", function(a) return a.boss == "Edwin VanCleef" and not a.first end) == 1, "a repeat dungeon kill goes to the activity log")
check(actOf("boss", function(a) return a.boss == "Baron Rivendare" and a.first end) == 1, "a first kill at max level goes to the activity log")
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(300) .. "x3", "Me Smith")
advance(200)
check(act[#act].k == "loot" and act[#act].n == 3 and sendsOf(";300;") == 0, "stacked loot counted, activity never sent")
check(H:Format(act[#act]):find("x3", 1, true) and H:Format(act[#act]):find("INV_Misc_Bag_08", 1, true), "activity line text")
local merged, nHL, nAct = H:LogLines()
check(#merged == nHL + nAct and nAct == #act, "log = highlights + activity")
local sorted = true
for k = 2, #merged do if merged[k].t < merged[k - 1].t then sorted = false end end
check(sorted, "merged by time")
H:Settings().logOnlyHighlights = true
merged = H:LogLines()
check(#merged == #H:ShownLog(), "'only highlights' hides the activity")
H:Settings().logOnlyHighlights = false

n = count()
local t0 = T()
local mark = #printed
recv("Cara Moss", ("1;b;%d;7;Cara Moss;31;7;1150;1;0;Mutanus;Höhlen des Wehklagens"):format(t0))
check(count() == n + 1 and last().who == "Cara Moss" and last().first and last().cls == "MAGE", "guildie's boss kill received")
check(printedSince(mark):find("erster Kill", 1, true) ~= nil, "received boss kill printed in chat")
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
recv("Cara Moss", ("1;q;%d;10;Cara Moss;31;7;166;22;special;Böse|nZeile|cffff0000rot"):format(t0))
check(last().k == "quest" and last().title == "BösenZeilerot", "escape codes stripped from received texts")
n = count()
recv("Cara Moss", ("1;q;%d;14;Cara Moss;31;7;79;28;dungeon;Ins Verlies"):format(t0))
check(count() == n, "a dungeon quest sent by an older version is not stored")
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
env.wipe(H.cdb.outbox); env.wipe(H.cdb.shareLog)
fire("PLAYER_LEVEL_UP", 100); advance(2)
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
env.wipe(H.cdb.shareLog); env.wipe(H.cdb.outbox)
local levelSends = sentKind("v")
for lvl = 110, 200, 10 do fire("PLAYER_LEVEL_UP", lvl) end
for _ = 1, 30 do advance(10); echoAll() end
check(sentKind("v") - levelSends == 8 and outboxSize() == 2,
  ("of 10 highlights in an hour 8 go to the guild, 2 wait (%d sent)"):format(sentKind("v") - levelSends))
advance(3300)
for _ = 1, 30 do advance(10); echoAll() end
check(sentKind("v") - levelSends == 10 and outboxSize() == 0,
  ("the 2 that waited go out in the next hour (%d sent)"):format(sentKind("v") - levelSends))
advance(5)

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
check(GS:Peers()["Cara Moss"] and env.RavenquillExpeditionDB.diagSender == nil, "peers recorded; no guildmate name stored for diagnosis")
local function opt(label)
  for i, o in ipairs(H.options) do if o.label == label then return i, o end end
end
env.SlashCmdList.RAVENQUILL("hl")
local paperFrame = env.RavenquillExpeditionHighlightsFrame
check(paperFrame and paperFrame:IsShown() and paperFrame.paper:IsShown(), "/rq hl opens the newspaper")
paperFrame:Hide()
GS:OpenModule("Highlights")
local ov = env.RavenquillExpeditionOverview
check(ov and ov:IsShown() and GS.optionsModule == "Highlights", "the Highlights settings still open in /rq")
local panel = ov.optView.panels.Highlights
check(panel and #panel.controls == #H.options, "one control per option entry")
local L = hlNS.L
local iShare = opt(L.OPT_SHARE)
local capNote = panel.controls[opt("Höchstens 8 Highlights pro Stunde gehen an die Gilde, der Rest wartet und folgt in der nächsten Stunde.")]
local share = panel.controls[iShare]
check(share:GetChecked() == true, "share checkbox shows the setting")
check(capNote and capNote._red == 1, "under the share box the page says how many highlights an hour go to the guild")
share:SetChecked(false); rawget(share, "_scripts").OnClick(share)
check(H:Settings().share == false, "unticking 'send my highlights' turns sharing off")
check(capNote._red < 1, "the hourly cap note is greyed out while sharing is off")
G.level = 50; fire("PLAYER_LEVEL_UP", 50); advance(100)
check(sendsOf(";Me Smith;50;") == 0 and last().lvl == 50, "logged but not sent while sharing is off")
share:SetChecked(true); rawget(share, "_scripts").OnClick(share)
check(H:Settings().share and capNote._red == 1, "sharing back on, cap note no longer greyed")
local sliders = {}
for _, o in ipairs(H.options) do if o.type == "range" then sliders[#sliders + 1] = o.label end end
check(#sliders == 0, "no rule sliders: everyone in the guild runs the same rules (" .. table.concat(sliders, ", ") .. ")")
check(H:Option("questRedLevels") == nil, "the hard-quest option is gone: only notable quests count")
local iChat, iAll = opt(L.OPT_CHAT), opt(L.OPT_CHAT_ALL)
local chat = panel.controls[iChat]
chat:SetChecked(false); rawget(chat, "_scripts").OnClick(chat)
check(not panel.controls[iAll]:IsEnabled(), "'also gear and quests' is greyed out while chat is off")
chat:SetChecked(true); rawget(chat, "_scripts").OnClick(chat)
local all = panel.controls[iAll]
all:SetChecked(true); rawget(all, "_scripts").OnClick(all)
check(H:Settings().chatAll and all:IsEnabled(), "chat all")
rawget(panel.controls[opt(L.OPT_TEST)], "_scripts").OnClick()
check(lastPrinted():find("11 Testeinträge", 1, true), "test button adds 11 test entries")
H:Open()
local hlFrame = env.RavenquillExpeditionHighlightsFrame
check(H.openLabel == "Zeitung" and hlFrame:IsShown() and hlFrame.paper:IsShown() and hlFrame.msg == nil
  and hlFrame.mode == nil, "the card's 'Zeitung' entry opens the sheet: the newspaper only, no log mode")
rawget(hlFrame.chronicle, "_scripts").OnClick(hlFrame.chronicle)
check(not hlFrame:IsShown() and GS.optionsModule == "Highlights" and not GS.moduleSettings and LogPage(env):IsShown()
  and lines[#lines]:find("Stufe 60 – Höchststufe!", 1, true),
  "its CHRONIK link closes the sheet and opens the /rq Highlights tab on the log, test entry last")
local noClutter = true
for _, o in ipairs(H.options) do
  if o.type == "text" or o.key == "logOnlyHighlights" or o.label == "Protokoll öffnen" then noClutter = false end
end
check(noClutter, "the options hold no log-window duplicates and no diagnostics")
rawget(panel.controls[opt(L.OPT_CLEARTEST)], "_scripts").OnClick()
check(lastPrinted():find("11 Testeinträge entfernt", 1, true), "test entries removed")
GS:ShowCopyBox("Diagnose", GS:DiagLines())
local box = env.RavenquillExpeditionCopyBox
check(box and box:IsShown() and box.text:find("== " .. H.title, 1, true) and box.text:find("events seen", 1, true)
  and box.text:find("last QUEST_TURNED_IN", 1, true) and box.text:find("== minimap button", 1, true),
  "the overview's one Diagnose text holds every module's section, Highlights included")
local text = box.text
box.eb:SetText("typed over")
rawget(box.eb, "_scripts").OnTextChanged(box.eb, true)
check(box.eb:GetText() == text, "the copy box is read-only")
local core = GS:DiagLines()
check(table.concat(core, "\n"):find("sync: queue", 1, true) and table.concat(core, "\n"):find("Cara Moss", 1, true), "core diagnostics (sync, peers)")
env.SlashCmdList.RAVENQUILL("hl share off")
check(H:Settings().share and GS.optionsModule == "Highlights", "old chat subcommands do nothing but open the options")

env.SlashCmdList.RAVENQUILL("")
check(ov:IsShown() and GS.optionsModule == nil, "/rq from the options view goes to the overview")
local rows = GS:OverviewRows()
check(rows[1].title == H.title and rows[1].state == "loaded" and rows[1].open and rows[1].options
  and rows[1].status:find("Einträge", 1, true), "Highlights row: loaded, status, Open, Options")
check(rows[2].state == "missing" and rows[2].slash == "/rq map", "Map row: not installed")
check(rows[3].state == "disabled" and rows[3].slash == "/rq craft" and rows[3].title == "Gildenwerkstatt",
  "Craft row: disabled, under the workshop name")
check(#rows == 3, "three known rows, no duplicates")
GS:ShowHome()
local missingRow = ov.home.list.items[2]
check(rawget(missingRow, "_shown") and missingRow.title:GetText() == "Map" and missingRow.line:GetText() == GS.OverviewL.MISSING
  and missingRow:GetAlpha() < 1 and not rawget(missingRow.more, "_shown") and ov.home.list.items[1]:GetAlpha() == 1,
  "a module that is not installed stays in the overview's list, greyed, with the reason and nothing to open")
GS:ShowModulePage("Highlights")
local hlPage = ov.optView.pages.Highlights
check(GS.optionsModule == "Highlights" and not GS.moduleSettings and hlPage and hlPage:IsShown() and not ov.optView.scroll:IsShown()
  and hlPage.msg ~= nil and hlPage.paper == nil and hlPage.prev == nil and not hlPage.footer:IsShown()
  and hlPage.onlyHL ~= nil, "the Highlights tab is the Chronik: the log with its checkbox, no footer while nothing is hidden, no newspaper, not its settings")
local gear = ov.optView.gear
check(rawget(gear, "_shown") and gear:GetText() == "Einstellungen" and gear:IsEnabled() and hlPage.open == nil,
  "a module page shows a labelled settings button and its own page, no open page")
local openPaper = ov.optView.openWindow
hlFrame:Hide()
check(rawget(openPaper, "_shown") and openPaper:GetText() == "Zeitung öffnen" and not hlFrame:IsShown(),
  "the Highlights tab's header row offers 'Zeitung öffnen' next to the settings button")
rawget(openPaper, "_scripts").OnClick(openPaper)
check(hlFrame:IsShown() and hlFrame.paper:IsShown() and hlPage:IsShown(),
  "'Zeitung öffnen' opens the paper sheet on the newspaper and leaves the tab shown")
hlFrame:Hide()
rawget(gear, "_scripts").OnClick(gear)
check(GS.moduleSettings and ov.optView.panels.Highlights:IsShown() and not hlPage:IsShown(), "the settings button shows the settings")
check(gear:GetText() == "« Zurück" and gear:IsEnabled(), "in the settings the same button reads '« Zurück'")
rawget(gear, "_scripts").OnClick(gear)
check(not GS.moduleSettings and hlPage:IsShown() and hlPage.msg ~= nil and gear:GetText() == "Einstellungen",
  "'« Zurück' goes back to the Chronik")
GS:ShowModuleOptions("Highlights")
local hlSideTab
for _, tab in ipairs(ov.tabs) do if tab.page == "Highlights" then hlSideTab = tab end end
rawget(hlSideTab, "_scripts").OnClick(hlSideTab)
check(not GS.moduleSettings and hlPage:IsShown() and hlPage.msg ~= nil, "the module's side tab goes back to the Chronik")
GS:ShowHome()
local mapTab = false
for _, tab in ipairs(ov.tabs) do if rawget(tab, "_shown") and tab.page == "Map" then mapTab = true end end
check(not mapTab, "no tab for a module that is not installed")
local craft = GS:NewModule("Craft", { addon = "GuildCraftAdvisor", slash = "craft", title = "Guild Craft Advisor", icon = "Interface\\Icons\\Trade_LeatherWorking" })
local crafted = false
function craft:Open() crafted = true end
function craft:OverviewStatus() return "Gilden-Sync · 4 erfasst" end
rows = GS:OverviewRows()
check(#rows == 3 and rows[3].state == "loaded" and rows[3].status == "Gilden-Sync · 4 erfasst" and rows[3].open, "Craft module replaces the GCA row")
env.SlashCmdList.RAVENQUILL("craft")
check(crafted, "/rq craft without options opens its window")
local extra = GS:NewModule("Extra", { addon = "RavenquillExpedition_Extra", slash = "ex", title = "Extra" })
local helped = false
function extra:OnSlash(rest) helped = (rest == "") end
rows = GS:OverviewRows()
check(rows[4] and rows[4].title == "Extra" and not rows[4].open and not rows[4].options, "unknown module listed")
env.SlashCmdList.RAVENQUILL("ex")
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
map.openLabel = "Karte"
GS:ShowModulePage("Map")
local mapOpen = ov.optView.pages.Map and ov.optView.pages.Map.open
check(not GS.moduleSettings and ov.optView.pages.Map:IsShown() and not ov.optView.scroll:IsShown() and mapOpen,
  "a module with a window but no page of its own opens on a page with its open button")
check(mapOpen:GetText() == "Karte öffnen", "the open button names the module's window (" .. tostring(mapOpen:GetText()) .. ")")
check(rawget(ov.optView.gear, "_shown") and ov.optView.gear:GetText() == "Einstellungen" and not ov.optView.openWindow:IsShown(),
  "its settings sit behind the settings button at the top right, no header open button for other modules")
rawget(mapOpen, "_scripts").OnClick(mapOpen)
check(opened and not GS.moduleSettings, "the open button calls mod:Open() and leaves the page shown")
rawget(ov.optView.gear, "_scripts").OnClick(ov.optView.gear)
check(GS.moduleSettings and ov.optView.panels.Map:IsShown() and not ov.optView.pages.Map:IsShown(), "the settings button shows its settings")
rawget(ov.optView.gear, "_scripts").OnClick(ov.optView.gear)
check(not GS.moduleSettings and ov.optView.pages.Map:IsShown(), "'« Zurück' goes back to the page with the open button")
map.openLabel = nil
GS:ShowHome()
env.SlashCmdList.RAVENQUILL("map")
check(GS.optionsModule == "Map" and ov.optView.panels.Map, "/rq map opens the map's options")
local sizePlus = ov.optView.panels.Map.controls[2].plus
for _ = 1, 10 do rawget(sizePlus, "_scripts").OnClick() end
check(math.abs(mapSize - 2) < 1e-9 and not sizePlus:IsEnabled(), "0.1 steps reach exactly the maximum and stop there")
for _ = 1, 3 do rawget(ov.optView.panels.Map.controls[2].minus, "_scripts").OnClick() end
check(("%.1f"):format(mapSize) == "1.7" and math.abs(mapSize - 1.7) < 1e-9, "0.1 steps down without drift")
local sizeMinus = ov.optView.panels.Map.controls[2].minus
for _ = 1, 20 do rawget(sizeMinus, "_scripts").OnClick() end
check(math.abs(mapSize - 0.5) < 1e-9 and not sizeMinus:IsEnabled(), "and stop at the minimum")
function map:OverviewStatus() error("map not ready") end
local errBefore = #errors
rows = GS:OverviewRows()
check(rows[2].status == GS.OverviewL.LOADED and rows[2].open, "a failing status hook falls back to 'loaded', the row still works")
check(#errors == errBefore + 1, "the hook's error goes to BugSack")
table.remove(errors)
function map:OverviewStatus() return "Auf der Karte: 2 · Teilen an" end
env.SlashCmdList.RAVENQUILL("")
env.SlashCmdList.RAVENQUILL("")
check(not ov:IsShown(), "/rq on the overview closes it")
check(#errors == 0, "no Lua errors (" .. #errors .. ")")

do
  local s = H:Settings()
  local chatAll = s.chatAll
  s.chatAll = false
  local shown = {}
  for _, e in ipairs({ { k = "gear", q = 3 }, { k = "gear", q = 4 }, { k = "loot", q = 3 }, { k = "boss" }, { k = "quest" },
    { k = "level" }, { k = "other" } }) do
    shown[#shown + 1] = e.k .. (e.q or "") .. "=" .. tostring(H:ShouldPrint(e))
  end
  s.chatAll = chatAll
  check(table.concat(shown, " ") == "gear3=false gear4=true loot3=true boss=true quest=false level=true other=false",
    "chat by default: epic gear, loot, boss kills and levels, no quests (" .. table.concat(shown, " ") .. ")")
end

do
  local shareOpt = H:Option("share")
  check(shareOpt and shareOpt.get() == true and H:Option("chat"), "options are found by their settings key")
  fire("PLAYER_LEVEL_UP", 90)
  shareOpt.set(false)
  advance(30)
  check(H:Settings().share == false and sendsOf(";Me Smith;90;") == 0, "a highlight queued before sharing went off stays unsent")
  shareOpt.set(true)
  advance(2)
  check(sendsOf(";Me Smith;90;") == 1, "turning sharing back on sends the waiting highlight right away")
end

do
  OpenLog(env)
  G.items[309] = { name = "Spätes Schwert", q = 4, il = 50, unloaded = true }
  recv("Dora Dunn", ("1;g;%d;951;Dora Dunn;33;5;309;50;4;40;16"):format(T()))
  advance(1)
  local waiting = lines[#lines] or ""
  G.items[309].unloaded = nil
  advance(5)
  local quiet = lines[#lines] or ""
  fire("GET_ITEM_INFO_RECEIVED", 309, true)
  advance(1)
  local arrived = lines[#lines] or ""
  check(waiting:find("[item:309]", 1, true) and quiet == waiting and arrived:find("[Spätes Schwert]", 1, true),
    "a received item without data shows its id, and its name once the item data arrives (" .. arrived .. ")")
  local footer = LogPage(env).footer
  G.guild = nil
  H:Refresh()
  local cachedLast, cachedFooter = lines[#lines], footer._text
  G.guild = "Die Gilde"
  H:Refresh()
  check(cachedLast == arrived, "GetGuildInfo empty for a moment: the window keeps showing the cached guild's log")
  check(not cachedFooter:find("Forever", 1, true) and not cachedFooter:find("Gilde@", 1, true),
    "the footer leaves out the guild and realm (" .. cachedFooter .. ")")
end

do
  local fm = me.frameMethods
  fm.SetTitle = function(f, title) f._title = title end
  fm.SetPortraitToAsset = function(f, icon) f._portrait = icon end
  env.SlashCmdList.RAVENQUILL("")
  local tabs, shownTitles, hlTab = ov.tabs, {}, nil
  for _, tab in ipairs(tabs) do
    if rawget(tab, "_shown") then shownTitles[#shownTitles + 1] = tab.title end
    if tab.page == "Highlights" then hlTab = tab end
  end
  local titles = table.concat(shownTitles, ",")
  check(shownTitles[1] == "Übersicht" and titles:find(H.title, 1, true) and titles:find("Karte", 1, true),
    "the side tabs are the overview and every module with options, in order (" .. titles .. ")")
  check(rawget(tabs[1].selected, "_shown") and hlTab and not rawget(hlTab.selected, "_shown")
    and ov._title == "Ravenquill Expedition", "the overview tab is selected and the window carries the suite's title")
  rawget(hlTab, "_scripts").OnClick(hlTab)
  check(GS.optionsModule == "Highlights" and ov.optView:IsShown() and rawget(hlTab.selected, "_shown")
    and not rawget(tabs[1].selected, "_shown") and ov._title == H.title and ov._portrait == H.icon
    and ov.optView.title == nil and ov.optView.status:GetText() == H:OverviewStatus(),
    "a module's side tab opens that module, the window takes its title and portrait, and the page shows its status, not the title again")
  rawget(tabs[1], "_scripts").OnClick(tabs[1])
  check(GS.optionsModule == nil and ov.home:IsShown() and ov._title == "Ravenquill Expedition",
    "the overview tab goes back to the overview")
  local homeRows, listed, hlRow = GS:OverviewRows(), 0, nil
  for _, row in ipairs(ov.home.list.items) do
    if rawget(row, "_shown") then
      listed = listed + 1
      if row.title:GetText() == H.title then hlRow = row end
    end
  end
  check(listed == #homeRows and hlRow and hlRow.line:GetText() == "Nichts Neues · zuletzt Dora Dunn",
    "the overview lists every module; the Highlights row, just read in the Chronik, names Dora's sword as the latest entry ("
    .. listed .. ", " .. tostring(hlRow and hlRow.line:GetText()) .. ")")
  H:ShowWindow()
  env.RavenquillExpeditionHighlightsFrame:Hide()
  rawget(tabs[1], "_scripts").OnClick(tabs[1])
  local cards = 0
  for _, card in ipairs(ov.home.now.items) do if rawget(card, "_shown") then cards = cards + 1 end end
  check(ov.home.recent == nil and ov.home.teaser == nil and cards == 0 and rawget(ov.home.list, "_shown"),
    "with the paper read there is no Rabenblatt card and no teaser line; the module rows stay the list")
  rawget(hlRow, "_scripts").OnClick(hlRow)
  check(GS.optionsModule == "Highlights" and not GS.moduleSettings and LogPage(env):IsShown(),
    "clicking the Highlights line opens its chronicle in /rq")
  rawget(tabs[1], "_scripts").OnClick(tabs[1])
  local syncLine = GS:OverviewSyncLine():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  check(ov.home.peers:GetText() == GS:OverviewPeersLine() and ov.home.peersBar == nil
    and table.concat(GS:DiagLines(), "\n"):find(syncLine, 1, true),
    "the header states the peers as text, without a progress bar; the sync state is in the diagnostics")
  check(hlTab.status == H:OverviewStatus(), "a side tab's tooltip carries the module's status line")
  fm.SetTitle, fm.SetPortraitToAsset = nil, nil
  env.SlashCmdList.RAVENQUILL("")
end

Kit.section("The settings page explains the fixed rules")
do
  env.SlashCmdList.RAVENQUILL("hl")
  local notes = {}
  for i, o in ipairs(H.options) do if o.type == "note" then notes[#notes + 1] = panel.controls[i]:GetText() end end
  local page = table.concat(notes, "\n")
  check(not page:find("Ausrüstung:", 1, true) and not page:find(H.KINDS.gear.icon, 1, true),
    "gear has no line any more: putting an item on is no highlight")
  check(page:find("Beute:|r Gegenstände ab Qualität |cffa335eeEpisch|r", 1, true) and page:find("Stufen:|r alle 10 Stufen und die Höchststufe", 1, true)
    and page:find("„Nur Highlights“ im Protokollfenster", 1, true), "the loot, level and activity lines carry the fixed numbers")
  local unexplained, retired = {}, {}
  for k, kind in pairs(H.KINDS) do
    if not kind.legacy and not page:find(kind.icon, 1, true) then unexplained[#unexplained + 1] = k end
  end
  for _, rule in ipairs(H.RULES) do if H.KINDS[rule.k].legacy then retired[#retired + 1] = rule.k end end
  check(#unexplained == 0, "every kind of highlight has a line on the page (" .. table.concat(unexplained, ", ") .. ")")
  check(#retired == 0, "no line explains a retired kind (" .. table.concat(retired, ", ") .. ")")
  local untranslated = {}
  for _, rule in ipairs(H.RULES) do
    for locale, t in pairs(H.locale) do
      local how = t[rule.text]
      local slots = type(how) == "string" and select(2, how:gsub("%%[ds]", ""))
      if type(t[rule.title]) ~= "string" or slots ~= #(rule.args or {}) then untranslated[#untranslated + 1] = locale .. ":" .. rule.text end
    end
  end
  check(#untranslated == 0, "every explanation exists in English and German with the same numbers to fill in ("
    .. table.concat(untranslated, ", ") .. ")")
  env.SlashCmdList.RAVENQUILL("")
  env.SlashCmdList.RAVENQUILL("")
  check(H.locale.enUS.TEST_DEADMINES == "The Deadmines" and L.TEST_DEADMINES == "Die Todesminen",
    "test entries name their dungeon in the player's language")
end

do
  local fm = me.frameMethods
  fm.ScrollToBottom = function(f) f._offset = 0 end
  fm.GetScrollOffset = function(f) return f._offset or 0 end
  fm.SetScrollOffset = function(f, v) f._offset = v end
  local s = H:Settings()
  local onlyHL = s.logOnlyHighlights
  s.logOnlyHighlights = false
  OpenLog(env)
  H:Refresh()
  local msg = LogPage(env).msg
  msg._offset = 5
  local reading = lines[#lines - 5]
  H:Activity({ k = "loot", item = 300, q = 2 })
  advance(1)
  check(msg._offset > 5 and lines[#lines - msg._offset] == reading,
    "scrolled up in the log, a new entry keeps the lines being read in place (offset " .. tostring(msg._offset) .. ")")
  msg._offset = 0
  H:Activity({ k = "loot", item = 300, q = 2 })
  advance(1)
  check(msg._offset == 0 and lines[#lines]:find("Grünes Ding", 1, true), "at the bottom the log follows new entries")
  s.logOnlyHighlights = onlyHL
  fm.ScrollToBottom, fm.GetScrollOffset, fm.SetScrollOffset = nil, nil, nil
  CloseLog(env)
end

do
  local fm, coreNS = me.frameMethods, me.ns.RavenquillExpedition
  local slices = {}
  fm.SetTexCoord = function(t, l, r, top, b) t._tc = { l, r, top, b }; slices[#slices + 1] = t end
  env.C_Texture = { GetAtlasInfo = function()
    return { file = 42, width = 664, height = 142, leftTexCoord = 0.1, rightTexCoord = 0.6, topTexCoord = 0.2, bottomTexCoord = 0.5 }
  end }
  coreNS.SlicedCard(ov, "Profession-overview-Card", 24)
  env.C_Texture, fm.SetTexCoord = nil, nil
  local function near(a, b) return math.abs(a - b) < 1e-9 end
  local corner, farCorner = slices[1] and slices[1]._tc, slices[9] and slices[9]._tc
  check(#slices == 9 and near(corner[1], 0.1) and near(corner[2], 0.1 + 24 * 0.5 / 664) and near(corner[3], 0.2)
    and near(corner[4], 0.2 + 24 * 0.3 / 142) and near(farCorner[2], 0.6) and near(farCorner[4], 0.5),
    "a stretched card keeps the atlas corners pixel for pixel, so its border looks like Blizzard's at any size")
end

do
  local coreNS, ran = me.ns.RavenquillExpedition, 0
  local p = coreNS.BuildPanel(ov, { { type = "button", label = "Vergessen", confirm = GS.OverviewL.CONFIRM, func = function() ran = ran + 1 end } })
  local b = p.controls[1]
  rawget(b, "_scripts").OnClick()
  check(ran == 0 and b:GetText() == "Zum Bestätigen erneut klicken", "a destructive button only arms on the first click and says so")
  rawget(b, "_scripts").OnClick()
  check(ran == 1 and b:GetText() == "Vergessen", "the second click runs it")
  rawget(b, "_scripts").OnClick()
  advance(6)
  rawget(b, "_scripts").OnClick()
  check(ran == 1 and b:GetText() == "Zum Bestätigen erneut klicken", "an armed button disarms after 5 seconds, so a late click only re-arms it")
end

do
  env.SlashCmdList.RAVENQUILL("")
  local home = ov.home
  GS:ShowModulePage("Highlights")
  check(ov.optView.open == nil and ov.optView.switch == nil and ov.optView.pageEntry == nil and ov.optView.settingsEntry == nil,
    "a module's header has no labelled Open / switch entries")
  GS:ShowModuleOptions("Highlights")
  check(GS.moduleSettings and ov.optView.panels.Highlights:IsShown(), "/rq hl and friends still open the settings directly")
  GS:ShowHome()
  check(home.replace == nil and home.diag == nil and GS.OverviewL.DIAG == "DIAG",
    "the overview has no re-place and no diagnostics button: those are dev tools now")
  env.SlashCmdList.RAVENQUILL("")
end

local probe = me.newModule("Probe")
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

Kit.section("Crafted epics and world bosses")
do
  local before = count()
  G.items[310] = { name = "Lila Robe", q = 4, il = 45 }
  fire("CHAT_MSG_LOOT", "Ihr stellt her: " .. link(310) .. ".", "Me Smith")
  local craftedEntry = last()
  check(count() == before + 1 and craftedEntry.item == 310 and craftedEntry.src == "craft"
    and H:Format(craftedEntry):find("(hergestellt)", 1, true), "a crafted epic is logged as crafted, not as received")
  local back = H.Decode("Me Smith", H.Encode(craftedEntry))
  check(back and back.src == "craft", "the crafted source survives the wire")
  G.level, G.instName = 60, "Azshara"
  fire("ENCOUNTER_END", 1100, "Azuregos", 0, 40, 1)
  check(count() == before + 2 and last().k == "first" and last().what == "boss" and last().boss == "Azuregos",
    "the guild's first kill of a world boss is a 'first in the guild' line instead of the boss line")
  H.db.guilds[H:GuildKey()].firsts.e1101 = T() - 86400
  fire("ENCOUNTER_END", 1101, "Lord Kazzak", 0, 40, 1)
  check(count() == before + 3 and last().k == "boss" and last().first and last().boss == "Lord Kazzak",
    "a world boss the guild has killed before is the usual first-kill line for this character")
  G.level = 30
end

Kit.section("Mounts, reputation, professions, PvP and duels")
local function newest() return events()[count()] end
do
  local mounted, runSpeed = false, 7
  env.IsMounted = function() return mounted end
  env.UnitOnTaxi = function() return false end
  env.GetUnitSpeed = function() return 0, runSpeed end
  local before = count()
  check(H.cdb.mount and H.cdb.mount.tier == 0 and H.cdb.mount.base == 30, "the mount record starts at the login level")
  mounted, runSpeed = true, 11.2
  fire("UNIT_AURA", "player"); advance(2)
  check(count() == before + 1 and newest().k == "mount" and not newest().epic, "the first mount is a highlight")
  fire("UNIT_AURA", "player"); advance(2)
  check(count() == before + 1, "mounting again is not news")
  runSpeed = 14
  fire("UNIT_AURA", "target"); advance(2)
  check(count() == before + 1, "auras on other units are ignored")
  fire("UNIT_AURA", "player"); advance(2)
  check(count() == before + 2 and newest().epic, "the first epic mount is a highlight")
  H.cdb.mount = { tier = 0, base = 60 }
  runSpeed = 11.2
  fire("UNIT_AURA", "player"); advance(2)
  check(count() == before + 2 and H.cdb.mount.tier == 1, "a mount the character had before the addon was installed is not news")
  runSpeed = 14
  fire("UNIT_AURA", "player"); advance(2)
  check(count() == before + 3 and newest().epic, "the epic mount bought after the install is")
  mounted = false
end

do
  local before = count()
  fire("CHAT_MSG_SYSTEM", "Ihr seid jetzt Wohlwollend bei Argentumdämmerung.")
  check(count() == before, "honored is no reputation highlight")
  fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Respektvoll bei Argentumdämmerung.")
  check(count() == before, "revered is no reputation highlight any more")
  fire("CHAT_MSG_SYSTEM", "Ihr seid jetzt Ehrfürchtig bei Argentumdämmerung.")
  local rep = newest()
  check(count() == before + 1 and rep.k == "rep" and rep.st == 8 and rep.fac == "Argentumdämmerung", "exalted is a highlight")
  check(H:Format(rep):find("Ehrfürchtig bei", 1, true), "the reputation line names the standing and the faction")
  fire("CHAT_MSG_SYSTEM", "Ihr seid jetzt Respektvoll bei Argentumdämmerung.")
  fire("CHAT_MSG_SYSTEM", "Ihr seid jetzt Ehrfürchtig bei Argentumdämmerung.")
  check(count() == before + 1, "exalted counts once per faction, also after dropping and coming back")
end

do
  local professions = { [1] = "Schmiedekunst", [4] = "Angeln", [5] = "Kochkunst", [6] = "Erste Hilfe" }
  env.GetProfessions = function() return 1, nil, nil, 4, 5, 6 end
  env.GetProfessionInfo = function(i) return professions[i], "", 150, 300 end
  local before = count()
  for _, rank in ipairs({ 149, 150, 225, 299 }) do
    fire("CHAT_MSG_SKILL", ("Eure Fertigkeit in Schmiedekunst hat sich auf %d erhöht."):format(rank))
  end
  check(count() == before, "150 and 225 are no milestones any more, nor is any other step below 300")
  fire("CHAT_MSG_SKILL", "Eure Fertigkeit in Schmiedekunst hat sich auf 300 erhöht.")
  check(count() == before + 1 and newest().k == "skill" and newest().skill == "Schmiedekunst" and newest().rank == 300,
    "a profession at 300 is a highlight")
  fire("CHAT_MSG_SKILL", "Eure Fertigkeit in Schwerter hat sich auf 300 erhöht.")
  check(count() == before + 1, "weapon skills are no professions")
  fire("CHAT_MSG_SKILL", "Eure Fertigkeit in Kochkunst hat sich auf 300 erhöht.")
  check(count() == before + 2 and newest().skill == "Kochkunst", "secondary skills count too")
end

do
  local index = 0
  local RANKS = { [5] = "Gefreiter", [6] = "Fußknecht", [7] = "Landsknecht" }
  env.UnitPVPRank = function() return index end
  env.GetPVPRankInfo = function(i) return RANKS[i], i - 4 end
  env.UnitFactionGroup = function() return "Alliance" end
  env.GetBattlefieldWinner = function() return 1 end
  local before = count()
  G.instName = "Kriegshymnenschlucht"
  fire("UPDATE_BATTLEFIELD_SCORE"); fire("UPDATE_BATTLEFIELD_SCORE")
  G.instName = "Westfall"
  check(count() == before, "a battleground win is no highlight any more")
  fire("PLAYER_PVP_RANK_CHANGED")
  check(count() == before and H.cdb.pvpRank == 0, "without a rank there is nothing to report")
  index = 5; fire("PLAYER_PVP_RANK_CHANGED"); fire("PLAYER_PVP_RANK_CHANGED")
  check(count() == before + 1 and newest().pk == "rank" and newest().pr == 1 and newest().name == "Gefreiter",
    "the first PvP rank is a highlight, reported once")
  check(H:Format(newest()):find("PvP-Rang 1 (Gefreiter)", 1, true), "its line names the rank number and title")
  index = 7; fire("PLAYER_PVP_RANK_CHANGED")
  check(count() == before + 2 and newest().pr == 3, "a higher rank is a highlight")
  index = 6; fire("PLAYER_PVP_RANK_CHANGED"); index = 7; fire("PLAYER_PVP_RANK_CHANGED")
  check(count() == before + 2, "losing a rank and gaining it back is not news")
end

do
  local before = count()
  fire("CHAT_MSG_SYSTEM", "Me Smith hat Bud Stone in einem Duell besiegt.")
  check(count() == before + 1 and newest().k == "duel" and newest().foe == "Bud Stone", "winning a duel against a guildie is a highlight")
  fire("CHAT_MSG_SYSTEM", "Me Smith hat Bud Stone in einem Duell besiegt.")
  fire("CHAT_MSG_SYSTEM", "Bud Stone hat Me Smith in einem Duell besiegt.")
  fire("CHAT_MSG_SYSTEM", "Rando Pug ist vor Me Smith aus einem Duell geflohen.")
  check(count() == before + 1, "a rematch the same day, a lost duel and a duel against a stranger are no highlights")
  fire("CHAT_MSG_SYSTEM", "Cara Moss ist vor Me Smith aus einem Duell geflohen.")
  check(count() == before + 2 and newest().foe == "Cara Moss", "a guildie fleeing from a duel counts as a win")
end

do
  local now = T()
  for i, e in ipairs({ { k = "mount", epic = true }, { k = "rep", st = 8, fac = "Argentumdämmerung" },
    { k = "skill", skill = "Schmiedekunst", rank = 300 }, { k = "pvp", pk = "rank", pr = 5, name = "Feldwebel" },
    { k = "pvp", pk = "win", name = "Arathibecken" }, { k = "duel", foe = "Bud Stone" } }) do
    e.t, e.id, e.who, e.lvl, e.cls = now, "Me Smith#" .. now .. "#" .. (60 + i), "Me Smith", 30, "ROGUE"
    local x = H.Decode("Me Smith", H.Encode(e))
    local same = x ~= nil
    for key, v in pairs(e) do if x and x[key] ~= v then same = false end end
    check(same, "round trip " .. e.k .. (e.pk and (" " .. e.pk) or ""))
  end
end

Kit.section("Gear: putting an epic on is no highlight, taking it off into the bags is not news either")
do
  local base, acts = count(), #H.cdb.activity
  G.items[316] = { name = "Lila Handschuhe", q = 4, il = 45 }
  equip(10, 316); advance(2)
  check(count() == base and #H.cdb.activity == acts, "an epic that was never loot is no highlight when it is put on")
  equip(10, nil); G.bags[0][10] = 316; fire("BAG_UPDATE_DELAYED"); advance(2)
  check(count() == base, ("taken off into the bags, that epic is not reported as received afterwards (%d new)"):format(count() - base))
end
check(#errors == 0, "no Lua errors after the new kinds (" .. #errors .. ")")

local SV_NAMES = { "RavenquillExpeditionDB", "RavenquillExpeditionHighlightsDB", "RavenquillExpeditionHighlightsCharDB" }
local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end
local characters = {}
local function Character(saved)
  local opts = {}
  for k, v in pairs(meOpts) do opts[k] = v end
  opts.setup = function(cenv, c)
    meOpts.setup(cenv, c)
    for _, k in ipairs(SV_NAMES) do cenv[k] = Copy(saved and saved[k]) end
  end
  local c = Kit.Client(sched, nil, "Me Smith", opts)
  c.H = c.ns.RavenquillExpedition_Highlights.H
  characters[#characters + 1] = c
  return c
end
local function LogOut(c)
  c.online = false
  local saved = {}
  for _, k in ipairs(SV_NAMES) do saved[k] = Copy(c.env[k]) end
  return saved
end
local function Reload(saved)
  local c = Character(saved)
  for _, a in ipairs(c.addons) do c.fire("ADDON_LOADED", a) end
  c.fire("PLAYER_LOGIN")
  c.fire("PLAYER_ENTERING_WORLD", false, true)
  return c
end
local function Kinds(c, k, list)
  local found = 0
  for _, e in ipairs(list or (c.H:Log())) do if e.k == k then found = found + 1 end end
  return found
end

local function Reported(c)
  local out, total = {}, 0
  for _, e in ipairs((c.H:Log())) do
    if e.k == "loot" then out[e.item] = true; total = total + 1 end
  end
  return out, total
end

Kit.section("Epics a character had at login are not reported as received")
do
  G.items[317] = { name = "Lila Gürtel", q = 4, il = 30 }
  G.items[318] = { name = "Lila Ring", q = 4, il = 30 }
  G.equipped[6] = 317
  local first = Character(); first.login(); advance(5)
  first.fire("BAG_UPDATE_DELAYED"); advance(2)
  local _, atInstall = Reported(first)
  check(atInstall == 0, ("right after the install: the epics in the bags are not reported (%d)"):format(atInstall))
  local saved = LogOut(first)
  G.bags[0][11] = 318
  local c = Character(saved); c.login(); advance(5)
  G.equipped[6] = nil; c.fire("PLAYER_EQUIPMENT_CHANGED", 6, false)
  G.bags[0][9] = 317; c.fire("BAG_UPDATE_DELAYED"); advance(2)
  local reported, total = Reported(c)
  check(not reported[317], "an epic worn at login and taken off into the bags is not reported as received")
  check(not reported[318], "an epic that came into the bags while the addon was off is not reported")
  check(total == 0, ("nor is any other epic that was in the bags at login (%d)"):format(total))
  G.bags[0][9], G.bags[0][11] = nil, nil
  LogOut(c)
end

local function EchoTo(c)
  for _, s in ipairs(G.sent) do
    if not s.echoed then
      s.echoed = true
      fire("CHAT_MSG_ADDON", s.prefix, s.msg, "GUILD", "Me Smith")
      c.fire("CHAT_MSG_ADDON", s.prefix, s.msg, "GUILD", "Me Smith")
    end
  end
end

Kit.section("Rule settings saved by an older version change nothing")
do
  local old = { RavenquillExpeditionHighlightsDB = { v = 3, settings = { minLootQuality = 3, minGearQuality = 2, minGain = 1,
    levelStep = 5, shareCap = 20 } } }
  local c = Character(old); c.login(); advance(5)
  local function Outbox() local queued = 0; for _ in pairs(c.H.cdb.outbox) do queued = queued + 1 end; return queued end
  G.items[320], G.items[321], G.items[322] = { name = "Blaue Hose", q = 3, il = 40 }, { name = "Blauer Mantel", q = 3, il = 40 },
    { name = "Grüner Riesenring", q = 2, il = 60 }
  c.fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(320) .. ".", "Me Smith")
  G.bags[0][13] = 321; c.fire("BAG_UPDATE_DELAYED"); advance(2)
  local _, rares = Reported(c)
  check(rares == 0, ("a saved loot quality of rare: looted and received rares are still no highlights (%d)"):format(rares))
  G.items[323] = { name = "Blauer Siegelring", q = 3, il = G.items[G.equipped[12]].il + 3 }
  local rings = { G.equipped[11], G.equipped[12] }
  G.equipped[11] = 322; c.fire("PLAYER_EQUIPMENT_CHANGED", 11, true)
  G.equipped[12] = 323; c.fire("PLAYER_EQUIPMENT_CHANGED", 12, true); advance(2)
  check(Kinds(c, "gear") == 0, "saved gear rules of green and +1: a green +34 and a rare +3 upgrade are still no highlights")
  c.fire("PLAYER_LEVEL_UP", 35)
  check(Kinds(c, "level") == 0, "a saved level step of 5: level 35 is still no highlight")
  for lvl = 40, 130, 10 do c.fire("PLAYER_LEVEL_UP", lvl) end
  for _ = 1, 30 do advance(10); EchoTo(c) end
  check(Kinds(c, "level") == 10 and #c.H.cdb.shareLog == 8 and Outbox() == 2,
    ("a saved cap of 20 an hour: of 10 level highlights still only 8 go out within the hour (%d wait)"):format(Outbox()))
  G.equipped[11], G.equipped[12], G.bags[0][13] = rings[1], rings[2], nil
  LogOut(c)
end

Kit.section("Raid night: kills a guildmate reports for the raid do not use up my hourly cap")
do
  local c = Character(); c.login(); advance(5)
  c.RQ:NotePeer("Bud Stone")
  c.H:Log()
  local known = {}
  for i = 1, 8 do known["e" .. (610 + i)] = T() - 7 * 86400 end
  c.H.db.guilds[c.H:GuildKey()].firsts = known
  local level = G.level
  G.level, G.inInstance, G.itype, G.instName, G.raid = 60, true, "raid", "Pechschwingenhort", true
  G.group = { raid1 = { "Me", "Smith" }, raid2 = { "Bud", "Stone" } }
  c.fire("PLAYER_ENTERING_WORLD")
  local kills = {}
  for i = 1, 8 do
    c.fire("ENCOUNTER_END", 610 + i, "Boss " .. i, 9, 40, 1)
    for _, e in ipairs((c.H:Log())) do if e.k == "boss" and e.enc == 610 + i then kills[i] = e end end
    advance(300)
  end
  G.items[324] = { name = "Lila Klinge", q = 4, il = 70 }
  c.fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: " .. link(324) .. ".", "Me Smith")
  G.inInstance, G.itype, G.raid, G.group, G.instName = false, "none", false, {}, "Burgschmied"
  c.fire("PLAYER_ENTERING_WORLD"); advance(5)
  for _, k in ipairs(kills) do
    c.fire("CHAT_MSG_ADDON", "RQE1", ("H;1;b;%d;9;Bud Stone;60;9;%d;0;1;%s;Pechschwingenhort;2"):format(k.t + 5, k.enc, k.boss),
      "GUILD", "Bud Stone")
  end
  c.fire("CHAT_MSG_ADDON", "RQE1", ("H;1;c;%d;10;Bud Stone;60;9;617;2;Pechschwingenhort"):format(kills[7].t + 5), "GUILD", "Bud Stone")
  for _ = 1, 30 do advance(10); EchoTo(c) end
  check(Kinds(c, "boss") == 8 and Kinds(c, "clear") == 1 and sendsOf(";Me Smith;60;4;61") == 0,
    "setup: Bud reported all 8 kills and the clear, I sent none of them")
  check(sendsOf(";Me Smith;60;4;324;") == 1, "my own epic after 8 kills that Bud reported goes to the guild")
  check(#c.H.cdb.shareLog == 1, ("only what I sent counts against the hourly cap (%d)"):format(#c.H.cdb.shareLog))
  G.level = level
  LogOut(c)
end

Kit.section("An empty log points to the explanations")
do
  local fresh = Character(); fresh.login(); advance(5)
  local page = OpenLog(fresh.env)
  local empty = page.empty
  local shown = empty and empty.text:GetText() or ""
  check(empty and empty:IsShown() and shown:find("Was zählt, steht unter /rq hl.", 1, true)
    and not shown:find("Gegenstandsstufen", 1, true), "an empty log points to /rq hl for what counts instead of listing the rules")
  check(empty and not shown:find("/rq hl >", 1, true) and empty.tests:GetText() == "Testeinträge hinzufügen",
    "instead of a path into the settings the empty log offers a 'Testeinträge hinzufügen' button")
  if empty then rawget(empty.tests, "_scripts").OnClick(empty.tests) end
  check(#fresh.H:Log() == 11 and empty and not empty:IsShown() and lines[#lines]:find("Stufe 60 – Höchststufe!", 1, true),
    "one click adds the 11 test entries and the log lists them in place of the hint")
  check(#fresh.errors == 0, "no Lua errors (" .. tostring(fresh.errors[1]) .. ")")
  LogOut(fresh)
end

Kit.section("The chronicle's footer names the activities 'Nur Highlights' hides")
do
  local c = Character(); c.login(); advance(5)
  c.H:AddTests()
  c.H:Activity({ k = "loot", item = 300, q = 2 })
  c.H:Activity({ k = "loot", item = 106, q = 1 })
  local page = OpenLog(c.env)
  local footer, onlyHL = page.footer, page.onlyHL
  local function Filter(on)
    onlyHL:SetChecked(on)
    rawget(onlyHL, "_scripts").OnClick(onlyHL)
  end
  Filter(true)
  check(footer:IsShown() and footer:GetText() == "2 Aktivitäten ausgeblendet",
    "'Nur Highlights' on: the footer names the activities it hides, not a second entry count (" .. tostring(footer:GetText()) .. ")")
  table.remove(c.H.cdb.activity)
  Filter(true)
  check(footer:IsShown() and footer:GetText() == "1 Aktivität ausgeblendet",
    "one hidden activity reads in the singular (" .. tostring(footer:GetText()) .. ")")
  Filter(false)
  check(not footer:IsShown(), "'Nur Highlights' off: every entry is in view, the footer is hidden; the header already counts them")
  c.H.cdb.activity = {}
  Filter(true)
  check(not footer:IsShown(), "'Nur Highlights' on while there is no activity to hide: the footer stays hidden")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
  LogOut(c)
end

Kit.section("A mount owned at install is quiet in the install session; the first one bought later is news")
do
  local level = G.level
  G.level, G.mounted, G.runSpeed = 45, true, 11.2
  local riding = Character(); riding.login(); advance(5)
  riding.fire("UNIT_AURA", "player"); advance(2)
  check(Kinds(riding, "mount") == 0 and Kinds(riding, "mount", riding.H.cdb.activity) == 1,
    "installed at 45 and riding: the mount is seen, but it is no highlight")
  LogOut(riding)
  G.mounted = false
  local first = Character(); first.login(); advance(5)
  local installed = LogOut(first)
  local reloaded = Reload(installed); advance(5)
  G.mounted = true
  reloaded.fire("UNIT_AURA", "player"); advance(2)
  check(Kinds(reloaded, "mount") == 0, "a /reload does not end the install session: riding afterwards is still quiet")
  LogOut(reloaded)
  G.mounted = false
  local later = Character(installed); later.login(); advance(5)
  G.mounted = true
  later.fire("UNIT_AURA", "player"); advance(2)
  check(Kinds(later, "mount") == 1, "installed at 45 without a mount: the first mount, ridden after a relog, is a highlight")
  LogOut(later)
  G.level, G.mounted, G.runSpeed = level, false, 0
end

Kit.section("Reputation the character had at install is not news")
do
  G.factions = { { "Allianz", 4, header = true }, { "Argentumdämmerung", 7 }, { "Holzschlundfeste", 8 }, { "Darnassus", 6 } }
  local c = Character(); c.login(); advance(5)
  c.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Respektvoll bei Argentumdämmerung.")
  check(Kinds(c, "rep") == 0, "revered before the install: revered again is not news")
  local seen = Kinds(c, "rep")
  c.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Respektvoll bei Holzschlundfeste.")
  c.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Ehrfürchtig bei Holzschlundfeste.")
  check(Kinds(c, "rep") == seen, "exalted before the install: dropping to revered and coming back is not news")
  seen = Kinds(c, "rep")
  c.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Respektvoll bei Darnassus.")
  check(Kinds(c, "rep") == seen, "honored before the install: revered is no highlight")
  c.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Ihr seid jetzt Ehrfürchtig bei Darnassus.")
  check(Kinds(c, "rep") == seen + 1, "honored before the install: exalted is a highlight")
  LogOut(c)
  G.factions = {}
end

Kit.section("A PvP rank the character had at install is not news; the next one is")
do
  local index = 7
  local c = Character()
  c.env.UnitPVPRank = function() return index end
  c.env.GetPVPRankInfo = function(i) return "Rang " .. (i - 4), i - 4 end
  c.login(); advance(5)
  check(Kinds(c, "pvp") == 0 and c.H.cdb.pvpRank == 3, "rank 3 at install: no highlight, the record starts there")
  local saved = LogOut(c)
  index = 8
  local later = Reload(saved); advance(5)
  later.env.UnitPVPRank = function() return index end
  later.env.GetPVPRankInfo = function(i) return "Rang " .. (i - 4), i - 4 end
  later.fire("PLAYER_PVP_RANK_CHANGED")
  check(Kinds(later, "pvp") == 1 and later.H.cdb.pvpRank == 4, "rank 4 after a relog is a highlight")
  LogOut(later)
end

Kit.section("New since you last looked: guildies' entries count, your own never do")
do
  local c = Character(); c.login(); advance(40)
  local function hear(sender, msg) c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. msg, "GUILD", sender) end
  local function status() return c.H:OverviewStatus() end
  check(not status():find("neu", 1, true), "a fresh log has nothing new (" .. status() .. ")")
  local t = T()
  hear("Cara Moss", ("1;v;%d;41;Cara Moss;40;7"):format(t))
  hear("Bud Stone", ("1;v;%d;42;Bud Stone;40;9"):format(t - 7200))
  hear("Abe Ash", ("1;Rv;%d;43;Dora Dunn;30;5"):format(t - 86400))
  check(Kinds(c, "level") == 3 and (c.H.db.diag.catchup.accepted or 0) == 1,
    "a live entry, one sent late and one caught up from yesterday are logged")
  check(status():sub(1, #"3 neu · ") == "3 neu · ", "all three are new, however old their time (" .. status() .. ")")
  local row
  for _, r in ipairs(c.RQ:OverviewRows()) do if r.name == "Highlights" then row = r end end
  check(row and row.status == status(), "the /rq overview line carries the same count (" .. tostring(row and row.status) .. ")")
  c.fire("PLAYER_LEVEL_UP", 40)
  hear("Bud Stone", ("1;l;%d;w;Me Smith;30;4;301;4;"):format(t))
  check(Kinds(c, "level") == 4 and Kinds(c, "loot") == 1, "my own level and a guildie's report of my loot are logged")
  check(status():sub(1, #"3 neu · ") == "3 neu · ", "neither of my own entries counts as new (" .. status() .. ")")
  LogOut(c)
end

Kit.section("New since you last looked: opening the log marks where new starts and clears the count")
do
  local c = Character(); c.login(); advance(40)
  local function hear(sender, msg) c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. msg, "GUILD", sender) end
  local function newCount(h) return tonumber((h or c.H):OverviewStatus():match("^(%d+) neu ·")) or 0 end
  local function divider()
    local at, found = nil, 0
    for i, l in ipairs(lines) do if l:find("neu seit deinem letzten Blick", 1, true) then at, found = i, found + 1 end end
    return at, found
  end
  local function lineOf(who) for i, l in ipairs(lines) do if l:find(who, 1, true) then return i end end end
  local t = T()
  hear("Cara Moss", ("1;v;%d;51;Cara Moss;40;7"):format(t - 600))
  c.fire("PLAYER_LEVEL_UP", 40)
  hear("Bud Stone", ("1;v;%d;52;Bud Stone;40;9"):format(t))
  check(newCount() == 2, "two new before the log is opened (" .. newCount() .. ")")
  OpenLog(c.env)
  local at, marks = divider()
  check(marks == 1 and lines[at + 1]:find("Cara Moss", 1, true) and lineOf("Bud Stone") > at,
    "the log marks the first new entry once, the newer ones below it")
  check(newCount() == 0, "opening the log clears the count")
  CloseLog(c.env)
  hear("Dora Dunn", ("1;v;%d;53;Dora Dunn;30;5"):format(t - 300))
  check(newCount() == 1, "an entry older than the last look but heard after it is new (" .. newCount() .. ")")
  OpenLog(c.env)
  at = divider()
  check(at and lines[at + 1]:find("Dora Dunn", 1, true) and lineOf("Cara Moss") < at and lineOf("Bud Stone") > at,
    "the mark sits right above it, between entries already seen")
  CloseLog(c.env)
  OpenLog(c.env)
  check(select(2, divider()) == 0 and newCount() == 0, "nothing new: no mark")
  hear("Abe Ash", ("1;v;%d;54;Abe Ash;60;1"):format(T()))
  advance(1)
  check(lineOf("Abe Ash") and newCount() == 0, "an entry that arrives while the log is open is seen there")
  CloseLog(c.env)
  hear("Cara Moss", ("1;v;%d;55;Cara Moss;50;7"):format(T()))
  local r = Reload(LogOut(c)); advance(5)
  check(newCount(r.H) == 1, "the count survives a logout (" .. newCount(r.H) .. ")")
  r.RQ:ShowModulePage("Highlights")
  check(newCount(r.H) == 0 and not r.RQ:OverviewRows()[1].status:find("neu", 1, true),
    "the Chronik on the /rq Highlights tab clears it too, and the status line follows")
  LogOut(r)
end

Kit.section("New since you last looked: only the paper or the log on screen clears the count")
do
  local c = Character(); c.login(); advance(40)
  local function hear(sender, msg) c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. msg, "GUILD", sender) end
  local function newCount() return tonumber(c.H:OverviewStatus():match("^(%d+) neu ·")) or 0 end
  local function toggle(key)
    for _, o in ipairs(c.H.options) do if o.key == key then o.set(not o.get()) end end
  end
  local function touchEverything()
    toggle("echoOwn"); toggle("echoOwn")
    c.fire("GET_ITEM_INFO_RECEIVED", 309, true)
    c.H:ClearTests()
    advance(1)
  end
  hear("Cara Moss", ("1;v;%d;61;Cara Moss;40;7"):format(T()))
  touchEverything()
  check(newCount() == 1, "an option, item data or clearing test entries with the log never opened keep the count ("
    .. newCount() .. ")")
  c.RQ:ShowModuleOptions("Highlights")
  touchEverything()
  check(newCount() == 1, "the Highlights options in /rq hide the log: changing them keeps the count (" .. newCount() .. ")")
  c.RQ:ShowModulePage("Highlights")
  check(newCount() == 0, "the Chronik on the /rq Highlights tab clears it")
  LogOut(c)
end

Kit.section("New since you last looked: the log opens with the new-entries line on screen")
do
  local c = Character(); c.login(); advance(40)
  local VISIBLE = 10
  c.frameMethods.ScrollToBottom = function(f) f._offset = 0 end
  c.frameMethods.GetScrollOffset = function(f) return f._offset or 0 end
  c.frameMethods.SetScrollOffset = function(f, v) f._offset = v end
  c.frameMethods.GetNumVisibleLines = function() return VISIBLE end
  local function hear(sender, msg) c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. msg, "GUILD", sender) end
  local function msg() return LogPage(c.env).msg end
  local function top() return #lines - msg()._offset - VISIBLE + 1 end
  local function onScreen(pattern)
    for i = math.max(1, top()), #lines - msg()._offset do if lines[i]:find(pattern, 1, true) then return i end end
  end
  local t = T()
  for i = 1, 5 do hear("Abe Ash", ("1;v;%d;%d;Abe Ash;%d;1"):format(t - 900 + i, 80 + i, 40 + i)) end
  OpenLog(c.env)
  CloseLog(c.env)
  for i = 1, 14 do hear("Cara Moss", ("1;v;%d;%d;Cara Moss;%d;7"):format(t - 600 + i, 90 + i, 40 + i)) end
  OpenLog(c.env)
  local at = onScreen("neu seit deinem letzten Blick")
  check(at == top() and lines[at + 1]:find("Cara Moss", 1, true),
    "14 new entries do not fit: the log scrolls so the line opens the screen (line " .. tostring(at) .. " of " .. #lines
    .. ", offset " .. tostring(msg()._offset) .. ")")
  hear("Dora Dunn", ("1;v;%d;120;Dora Dunn;30;5"):format(T()))
  advance(1)
  check(onScreen("neu seit deinem letzten Blick") and onScreen("Cara Moss"),
    "an entry arriving while reading keeps the line where it was")
  CloseLog(c.env)
  hear("Bud Stone", ("1;v;%d;121;Bud Stone;40;9"):format(T()))
  msg()._offset = 0
  OpenLog(c.env)
  check(msg()._offset == 0 and onScreen("neu seit deinem letzten Blick") and onScreen("Bud Stone"),
    "one new entry fits at the bottom: the log stays at the bottom")
  CloseLog(c.env)
  LogOut(c)
end

Kit.section("New since you last looked: raid kills are records, never new, whether I was at them or not")
do
  local saved = { G.inInstance, G.itype, G.instName, G.raid, G.group }
  local c = Character(); c.login(); advance(40)
  local function hear(sender, msg) c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. msg, "GUILD", sender) end
  local function newCount() return tonumber(c.H:OverviewStatus():match("^(%d+) neu ·")) or 0 end
  local function own(enc)
    for _, e in ipairs((c.H:Log())) do if e.k == "boss" and e.enc == enc and e.who == "Me Smith" then return e end end
  end
  local function report(entryId, enc, boss, t)
    hear("Cara Moss", ("1;b;%d;%d;Cara Moss;31;7;%d;0;1;%s;Geschmolzener Kern;3"):format(t, entryId, enc, boss))
  end
  G.inInstance, G.itype, G.instName, G.raid = true, "raid", "Geschmolzener Kern", true
  G.group = { raid1 = { "Me", "Smith" }, raid2 = { "Cara", "Moss" }, raid3 = { "Bud", "Stone" } }
  c.fire("PLAYER_ENTERING_WORLD")
  c.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
  local myLuci = own(663)
  check(myLuci and myLuci.grp and c.H.cdb.outbox[myLuci.id], "my Lucifron kill waits to be sent as a group report")
  report(131, 663, "Lucifron", myLuci.t + 30)
  check(own(663) == nil and newCount() == 0, "Cara's report replaces mine and is not new to me (" .. newCount() .. ")")
  c.fire("ENCOUNTER_END", 664, "Magmadar", 9, 40, 1)
  local myMag = own(664)
  G.inInstance, G.itype, G.instName, G.raid, G.group = false, "none", "Burgschmied", false, {}
  c.fire("PLAYER_ENTERING_WORLD")
  local sentMark = #G.sent
  for _ = 1, 300 do
    advance(1)
    for i = sentMark + 1, #G.sent do
      local m = G.sent[i]
      if not m.echoed then m.echoed = true; c.fire("CHAT_MSG_ADDON", m.prefix, m.msg, "GUILD", "Me Smith") end
    end
  end
  check(myMag and c.H.cdb.outbox[myMag.id] == nil and own(664), "my Magmadar report went out")
  report(132, 664, "Magmadar", myMag.t + 20)
  check(newCount() == 0, "Cara's later Magmadar report is not new either (" .. newCount() .. ")")
  report(133, 665, "Gehennas", T() - 60)
  check(newCount() == 0, "a raid kill I was not at is not new either: it has no line to read (" .. newCount() .. ")")
  LogOut(c)
  G.inInstance, G.itype, G.instName, G.raid, G.group = saved[1], saved[2], saved[3], saved[4], saved[5]
end

do
  local errs = 0
  for _, c in ipairs(characters) do errs = errs + #c.errors end
  check(errs == 0, "no Lua errors in the fresh logins (" .. errs .. ")")
end

Kit.finish()
