-- Ravenquill Expedition: Highlights – detectors. Everything here watches YOUR character, except epic loot,
-- which the loot chat also shows for guildies in your group.
-- Every watched event is counted in RavenquillExpeditionHighlightsDB.diag (seen / last arguments) so the
-- Forever-specific behaviour can be checked after a /reload.
local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, IsSecret, Plain = GS.SafeCall, GS.IsSecret, GS.Plain

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function MyLevel() return Plain(SafeCall(UnitLevel, "player"), "number") end
local function MaxLevel() return Plain(SafeCall(GetMaxPlayerLevel), "number") end

local function Own(k, fields)
  local who = GS:PlayerKey()
  if not who then return end
  local t = GS:Now()
  local _, cls = SafeCall(UnitClass, "player")
  local e = { k = k, t = t, who = who, cls = Plain(cls, "string"), lvl = MyLevel(), id = H:NextID(who, t) }
  for key, v in pairs(fields) do e[key] = v end
  return e
end

-- plain activity (not a highlight): only this character's log, never sent
local function Act(k, fields)
  local e = { k = k, lvl = MyLevel() }
  for key, v in pairs(fields) do e[key] = v end
  return e
end

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

local HEX_QUALITY = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local function LinkQuality(link)
  local q = tonumber(link:match("|cnIQ(%d)")) -- Forever's link format "|cnIQ3:|Hitem:..." [V: saved diag]
  if q then return q end
  local hex = link:match("|cff(%x%x%x%x%x%x)")
  return hex and HEX_QUALITY[hex:lower()]
end

-- { id, name, q, il, ready } for an item link; asks the client to load it when needed
local function ItemFacts(link)
  link = Plain(link, "string")
  if not link then return end
  local f = { id = ItemID(link) }
  local name, _, q, il = SafeCall(GetInfo, link)
  local dil = Plain(SafeCall((C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo, link), "number")
  if dil and dil > 0 then il = dil end
  f.name = Plain(name, "string")
  f.q = Plain(q, "number") or LinkQuality(link)
  f.il = Plain(il, "number")
  f.ready = f.name ~= nil and f.il ~= nil
  if not f.ready and f.id and C_Item and C_Item.RequestLoadItemDataByID then SafeCall(C_Item.RequestLoadItemDataByID, f.id) end
  return f
end
H.ItemFacts = ItemFacts

local function Diag(event, ...)
  local d = H.db and H.db.diag
  if not d then return end
  d.seen = d.seen or {}
  d.seen[event] = (d.seen[event] or 0) + 1
  d.last = d.last or {}
  local parts = {}
  for i = 1, math.min(select("#", ...), 8) do
    local v = select(i, ...)
    parts[i] = IsSecret(v) and "<secret>" or GS.Cut(tostring(v), 120)
  end
  d.last[event] = table.concat(parts, " | ")
end

---------------------------------------------------------------------------
-- Bags and bank: (bag, slot) -> link, quality
---------------------------------------------------------------------------
local CC = C_Container
local function NumSlots(bag) return Plain(SafeCall((CC and CC.GetContainerNumSlots) or GetContainerNumSlots, bag), "number") or 0 end
local function SlotItem(bag, slot)
  if CC and CC.GetContainerItemInfo then
    local info = SafeCall(CC.GetContainerItemInfo, bag, slot)
    if type(info) == "table" and not IsSecret(info) then
      return Plain(info.hyperlink, "string"), Plain(info.quality, "number"), Plain(info.itemID, "number")
    end
    return
  end
  local link = Plain(SafeCall(GetContainerItemLink, bag, slot), "string")
  return link, link and LinkQuality(link), ItemID(link)
end

local function BagList()
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  local out = {}
  for b = 0, last do out[#out + 1] = b end
  return out
end
local function BankList()
  local out = { BANK_CONTAINER or -1 }
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do out[#out + 1] = b end
  return out
end

-- calls fn(link, quality, itemID) for every item in the given containers
local function EachItem(bags, fn)
  for _, bag in ipairs(bags) do
    for slot = 1, NumSlots(bag) do
      local link, q, id = SlotItem(bag, slot)
      if id or link then fn(link, q, id or ItemID(link)) end
    end
  end
end

---------------------------------------------------------------------------
-- Gear: a big upgrade (≥ minGain item levels on a rare+ item) or the first epic in a slot.
-- Items this character had before (worn, in the bags at install, in the bank) never count.
---------------------------------------------------------------------------
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 } -- no ammo 0, shirt 4, tabard 19
local IS_GEAR = {}
for _, s in ipairs(GEAR_SLOTS) do IS_GEAR[s] = true end
local snap, snapReady = {}, false

local function ReadSlot(slot) return Plain(SafeCall(GetInventoryItemLink, "player", slot), "string") end

local function MarkEpic(q, id)
  if id and (q or 0) >= (H:Settings().minLootQuality or 4) then H.cdb.ownedEpics[id] = true end
end

local function TakeSnapshot()
  for _, s in ipairs(GEAR_SLOTS) do
    local l = ReadSlot(s)
    snap[s] = l
    local id = ItemID(l)
    if id then
      H.cdb.everEquipped[id] = true
      local f = ItemFacts(l)
      MarkEpic(f and f.q, id)
    end
  end
  -- first run: whatever is already in the bags was "worn before" (review #4), and owned epics aren't loot
  if not H.cdb.bagsSeeded then
    EachItem(BagList(), function(_, q, id) if id then H.cdb.everEquipped[id] = true; MarkEpic(q, id) end end)
    H.cdb.bagsSeeded = true
  else
    EachItem(BagList(), function(_, q, id) MarkEpic(q, id) end)
  end
  snapReady = true
end

local function EvaluateGear(slot, old, new, tries)
  local nf, of = ItemFacts(new), old and ItemFacts(old)
  if not nf then return end
  if not nf.ready or (of and not of.ready) then
    if tries < 5 then C_Timer.After(1, function() GS:Call(EvaluateGear, slot, old, new, tries + 1) end) end
    return
  end
  local s = H:Settings()
  local gain = of and (nf.il - of.il)
  local epicNew = (nf.q or 0) >= 4 and (not of or (of.q or 0) < 4)
  local bigGain = gain and gain >= s.minGain and (nf.q or 0) >= (s.minGearQuality or 3)
  local fields = { item = nf.id, link = new, il = nf.il, q = nf.q, oil = of and of.il, slot = slot }
  if bigGain or epicNew then H:Add(Own("gear", fields), "self") else H:Activity(Act("gear", fields)) end
end

local function OnEquipmentChanged(slot)
  if not snapReady or type(slot) ~= "number" or not IS_GEAR[slot] then return end
  local old, new = snap[slot], ReadSlot(slot)
  snap[slot] = new
  if not new or new == old then return end
  local id = ItemID(new)
  if not id or H.cdb.everEquipped[id] then return end
  H.cdb.everEquipped[id] = true
  EvaluateGear(slot, old, new, 0)
end

---------------------------------------------------------------------------
-- Epics that show up in the bags (review #5): catches loot whose chat line is secret, quest rewards,
-- trades, mail. Not while the bank is open (taking out ≠ getting). The loot dedupe merges it with the
-- loot line when both are seen.
---------------------------------------------------------------------------
local bankOpen = false
local function ScanBagsForEpics()
  if not snapReady or not H.cdb.bagsSeeded then return end
  local minQ = H:Settings().minLootQuality or 4
  EachItem(BagList(), function(link, q, id)
    if id and (q or 0) >= minQ and not H.cdb.ownedEpics[id] then
      H.cdb.ownedEpics[id] = true
      if not bankOpen then H:Add(Own("loot", { item = id, link = link, q = q, src = "bag" }), "self") end
    end
  end)
end

local function OnBankOpened()
  bankOpen = true
  EachItem(BankList(), function(_, q, id)
    if id then
      MarkEpic(q, id)
      if not H.cdb.bankSeeded then H.cdb.everEquipped[id] = true end -- a second gear set in the bank (review #4)
    end
  end)
  H.cdb.bankSeeded = true
end

---------------------------------------------------------------------------
-- Bosses.
-- Forever reports a won DUNGEON fight as ENCOUNTER_END with success 0, and BOSS_KILL names the kill
-- (Spoken_Bosses\Events.lua:25-30); both are handled, whichever names a kill first wins for 60 s.
-- Raid kill: a group report – one elected suite user sends "X and n guildies defeated Y".
-- Dungeon kill: only a levelling character's FIRST kill of that boss (a max-level char installing late
--   would otherwise announce farmed bosses as firsts – review #11). Every other kill goes to the activity log.
---------------------------------------------------------------------------
local recentKill = {}

local function OnKill(encID, name)
  encID = Plain(encID, "number")
  if encID and encID <= 0 then encID = nil end
  name = Plain(name, "string")
  if name == "" then name = nil end
  local key = encID and ("e" .. encID) or (name and ("n" .. name))
  if not key then return end
  local now = GetTime()
  if (encID and recentKill["e" .. encID] and now - recentKill["e" .. encID] < 60)
    or (name and recentKill["n" .. name] and now - recentKill["n" .. name] < 60) then return end
  if encID then recentKill["e" .. encID] = now end
  if name then recentKill["n" .. name] = now end

  local inst, itype = SafeCall(GetInstanceInfo)
  inst, itype = Plain(inst, "string"), Plain(itype, "string")
  if not inst or itype == "none" then inst = Plain(SafeCall(GetRealZoneText), "string") or inst end
  local raid = itype == "raid"
  local first = not H.cdb.kills[key]
  H.cdb.kills[key] = GS:Now()

  if raid then
    local guildies = GS:GroupGuildies()
    local rank = GS:ElectionRank(guildies)
    H:Add(Own("boss", { enc = encID, boss = name, inst = inst, raid = true, grp = true, n = #guildies + 1, first = first or nil }),
      "self", { group = true, rank = rank })
    return
  end
  local lvl, max = MyLevel(), MaxLevel()
  local levelling = not (lvl and max and lvl >= max)
  if first and levelling then
    H:Add(Own("boss", { enc = encID, boss = name, inst = inst, first = true }), "self")
  else
    H:Activity(Act("boss", { enc = encID, boss = name, inst = inst, first = first or nil }))
  end
end

---------------------------------------------------------------------------
-- Quests: elite / group / dungeon / raid, or a suggested group size; once per quest and character.
-- The quest is gone from the log at QUEST_TURNED_IN, so the log is cached while it changes.
---------------------------------------------------------------------------
local qcache = {}

local function ScanQuestLog()
  local QL = C_QuestLog
  if QL and QL.GetNumQuestLogEntries and QL.GetInfo then
    -- [V] on Forever: ForeverLFG QuestFacts.lua:69-80
    local n = Plain(SafeCall(QL.GetNumQuestLogEntries), "number") or 0
    for i = 1, n do
      local info = SafeCall(QL.GetInfo, i)
      if type(info) == "table" and not IsSecret(info) and not Plain(info.isHeader) then
        local qid = Plain(info.questID, "number")
        if qid and qid > 0 then
          qcache[qid] = { title = Plain(info.title, "string"), level = Plain(info.level, "number"), group = Plain(info.suggestedGroup, "number") }
        end
      end
    end
    return
  end
  local n = Plain(SafeCall(GetNumQuestLogEntries), "number") or 0 -- classic fallback [U]
  for i = 1, n do
    local r = { SafeCall(GetQuestLogTitle, i) }
    local qid = Plain(r[8], "number")
    if not Plain(r[4]) and qid and qid > 0 then
      qcache[qid] = { title = Plain(r[1], "string"), level = Plain(r[2], "number"), group = Plain(r[3], "number") }
    end
  end
end

-- tag IDs: Enum.QuestTag where present (ForeverLFG QuestFacts.lua:88-90); 1 = Elite in vanilla data
-- (Questie\Database\QuestieDB.lua:74), 62/88/89 raid, 81/85 dungeon.
local function QuestTag(qid)
  local tagID, isElite
  local QL = C_QuestLog
  if QL and QL.GetQuestTagInfo then
    local info = SafeCall(QL.GetQuestTagInfo, qid)
    if type(info) == "table" and not IsSecret(info) then tagID, isElite = Plain(info.tagID, "number"), Plain(info.isElite) end
  elseif GetQuestTagInfo then
    tagID = Plain(SafeCall(GetQuestTagInfo, qid), "number")
  end
  if isElite == nil and QL and QL.IsEliteQuest then isElite = Plain(SafeCall(QL.IsEliteQuest, qid)) end
  local T = Enum and Enum.QuestTag or {}
  if tagID and (tagID == T.Raid or tagID == T.Raid10 or tagID == T.Raid25 or tagID == 62 or tagID == 88 or tagID == 89) then return "raid" end
  if tagID and (tagID == T.Dungeon or tagID == T.Heroic or tagID == 81 or tagID == 85) then return "dungeon" end
  if isElite == true or tagID == 1 then return "elite" end
  if tagID and tagID == T.Group then return "group" end
end
H.QuestTag = QuestTag

local function OnQuestTurnedIn(qid)
  qid = Plain(qid, "number")
  if not qid then return end
  local c = qcache[qid] or {}
  local title = c.title
  if not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    title = Plain(SafeCall(C_QuestLog.GetTitleForQuestID, qid), "string")
  end
  local tag = QuestTag(qid)
  if not tag and (c.group or 0) >= 2 then tag = "group" end
  local red = H:Settings().questRedLevels or 0
  local plevel = MyLevel()
  if not tag and red > 0 and c.level and plevel and c.level - plevel >= red then tag = "red" end
  if not tag or H.cdb.quests[qid] then -- a normal quest, or a hard one done before (repeatable): activity
    H:Activity(Act("quest", { qid = qid, title = title, ql = c.level, tag = tag }))
    return
  end
  H.cdb.quests[qid] = true
  H:Add(Own("quest", { qid = qid, title = title, ql = c.level, tag = tag }), "self")
end

---------------------------------------------------------------------------
-- Level milestones: every levelStep levels and the max level
---------------------------------------------------------------------------
local function OnLevelUp(level)
  level = Plain(level, "number")
  if not level then return end
  local max = MaxLevel()
  local step = H:Settings().levelStep
  if (step and step > 0 and level % step == 0) or (max and level == max) then
    local e = Own("level", {})
    if e then e.lvl = level; H:Add(e, "self") end
  else
    H:Activity(Act("level", { lvl = level }))
  end
end

---------------------------------------------------------------------------
-- Loot: your epic+ loot, and epic+ loot of guildies in your group who don't run the suite
-- (they report their own). One elected suite user in the group reports it.
-- CHAT_MSG_LOOT arg2 = the looter as "First Surname" [V: saved diag, 2026-11-14].
---------------------------------------------------------------------------
-- The final "." is optional: on Forever the own-loot line arrived WITHOUT it ("Ihr erhaltet Beute: [x]") while other
-- players' lines had it [V: saved diag, 2026-11-14 12:43].
local function Pattern(f)
  local p = GS.FormatToPattern(f)
  if p and p:sub(-3) == "%.$" then p = p:sub(1, -4) .. "%.?$" end
  return p
end
local P
local function LootPatterns()
  if P then return P end
  P = { self = {}, other = {} }
  for _, f in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF }) do
    local p = Pattern(f)
    if p then P.self[#P.self + 1] = p end
  end
  for _, f in ipairs({ LOOT_ITEM_MULTIPLE, LOOT_ITEM }) do
    local p = Pattern(f)
    if p then P.other[#P.other + 1] = p end
  end
  return P
end

local function OnLoot(text, playerName)
  text = Plain(text, "string")
  if not text then
    if H.db then H.db.diag.secretLoot = (H.db.diag.secretLoot or 0) + 1 end
    return
  end
  local pats = LootPatterns()
  local link, who, count
  for _, p in ipairs(pats.self) do
    local l, n = text:match(p)
    if l then link, count, who = l, tonumber(n), GS:PlayerKey() break end
  end
  if not link then
    for _, p in ipairs(pats.other) do
      local name, l = text:match(p)
      if name and l then
        link = l
        who = GS:NormName(Plain(playerName, "string") or name)
        break
      end
    end
  end
  if not (link and who) then return end
  link = link:match("(|c.-|r)") or link
  local f = ItemFacts(link)
  local me = GS:PlayerKey()
  if not (f and f.id and f.q) or f.q < H:Settings().minLootQuality then
    -- not epic: my own loot still goes to the activity log (others' ordinary loot doesn't)
    if who == me and f and f.id then H:Activity(Act("loot", { item = f.id, link = link, q = f.q, n = count })) end
    return
  end
  if who == me then
    H.cdb.ownedEpics[f.id] = true
    H:Add(Own("loot", { item = f.id, link = link, q = f.q }), "self")
    return
  end
  if GS:IsGuildMember(who) ~= true or GS:IsPeer(who) then return end
  local guildies, inGroup = GS:GroupGuildies(), false
  local others = {}
  for _, k in ipairs(guildies) do
    if k == who then inGroup = true else others[#others + 1] = k end
  end
  if not inGroup then return end
  local r = GS.roster[who] or {}
  local t = GS:Now()
  H:Add({ k = "loot", t = t, who = who, by = me, cls = r.class, lvl = r.level, item = f.id, link = link, q = f.q,
    id = H.WitnessID(who, f.id, t) }, "witness", { group = true, rank = (GS:ElectionRank(others)) })
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "ENCOUNTER_END", "BOSS_KILL", "QUEST_LOG_UPDATE",
  "QUEST_ACCEPTED", "QUEST_COMPLETE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "CHAT_MSG_LOOT", "GET_ITEM_INFO_RECEIVED",
  "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }
for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
local QUIET = { QUEST_LOG_UPDATE = true, GET_ITEM_INFO_RECEIVED = true, BAG_UPDATE_DELAYED = true }

local armed = {}
local function Soon(key, delay, fn)
  if armed[key] then return end
  armed[key] = true
  C_Timer.After(delay, function() armed[key] = nil; GS:Call(fn) end)
end

local wasInInstance = false
frame:SetScript("OnEvent", function(_, event, ...)
  if not H.db then return end
  if not QUIET[event] then Diag(event, ...) end
  if event == "PLAYER_ENTERING_WORLD" then
    if not snapReady then Soon("snap", 3, TakeSnapshot) end
    Soon("quests", 1, ScanQuestLog)
    local inside = GS:InInstance()
    if wasInInstance and not inside then GS:Call(H.OnLeftInstance, H) end
    wasInInstance = inside
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    GS:Call(OnEquipmentChanged, (...))
  elseif event == "ENCOUNTER_END" then
    local encID, name, _, _, success = ...
    success = Plain(success)
    if success == 1 or success == true then GS:Call(OnKill, encID, name) end
  elseif event == "BOSS_KILL" then
    local encID, name = ...
    GS:Call(OnKill, encID, name)
  elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" then
    Soon("quests", 1, ScanQuestLog)
  elseif event == "QUEST_COMPLETE" then
    GS:Call(ScanQuestLog)
  elseif event == "QUEST_TURNED_IN" then
    GS:Call(OnQuestTurnedIn, (...))
  elseif event == "PLAYER_LEVEL_UP" then
    GS:Call(OnLevelUp, (...))
  elseif event == "CHAT_MSG_LOOT" then
    local text, playerName = ...
    GS:Call(OnLoot, text, playerName)
  elseif event == "BAG_UPDATE_DELAYED" then
    Soon("bags", 1, ScanBagsForEpics) -- after the loot line, so that one wins the dedupe
  elseif event == "BANKFRAME_OPENED" then
    GS:Call(OnBankOpened)
  elseif event == "BANKFRAME_CLOSED" then
    C_Timer.After(1, function() bankOpen = false end)
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if H.waitingItems and H.Refresh then
      Soon("refresh", 0.5, function() H.waitingItems = false; H:Refresh() end)
    end
  end
end)

function H:OnLogin()
  LootPatterns()
  wasInInstance = GS:InInstance()
  self:OnLoginOutbox()
end

-- for the offline harness
H._test = { ItemFacts = ItemFacts, OnEquipmentChanged = OnEquipmentChanged, TakeSnapshot = TakeSnapshot, OnKill = OnKill,
  OnQuestTurnedIn = OnQuestTurnedIn, ScanQuestLog = ScanQuestLog, OnLevelUp = OnLevelUp, OnLoot = OnLoot,
  qcache = qcache, LootPatterns = LootPatterns }
