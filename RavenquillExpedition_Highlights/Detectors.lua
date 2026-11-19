local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, IsSecret, Plain = GS.SafeCall, GS.IsSecret, GS.Plain

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
ns.Own = Own

local function Act(k, fields)
  local e = { k = k, lvl = MyLevel() }
  for key, v in pairs(fields) do e[key] = v end
  return e
end
ns.Act = Act
ns.MyLevel = MyLevel

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

local HEX_QUALITY = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local function LinkQuality(link)
  local q = tonumber(link:match("|cnIQ(%d)"))
  if q then return q end
  local hex = link:match("|cff(%x%x%x%x%x%x)")
  return hex and HEX_QUALITY[hex:lower()]
end

local function ItemFacts(link)
  link = Plain(link, "string")
  if not link then return end
  local f = { id = ItemID(link) }
  local name, _, q, il = H.ItemInfo(link)
  local dil = Plain(SafeCall((C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo, link), "number")
  if dil and dil > 0 then il = dil end
  f.name = Plain(name, "string")
  f.q = Plain(q, "number") or LinkQuality(link)
  f.il = Plain(il, "number")
  f.ready = f.name ~= nil and f.il ~= nil
  if not f.ready and f.id then H.RequestItemData(f.id) end
  return f
end

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
ns.Diag = Diag

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

local function EachItem(bags, fn)
  for _, bag in ipairs(bags) do
    for slot = 1, NumSlots(bag) do
      local link, q, id = SlotItem(bag, slot)
      if id or link then fn(link, q, id or ItemID(link)) end
    end
  end
end

local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
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
  if not H.cdb.bagsSeeded then
    EachItem(BagList(), function(_, q, id) if id then H.cdb.everEquipped[id] = true; MarkEpic(q, id) end end)
    H.cdb.bagsSeeded = true
  else
    EachItem(BagList(), function(_, q, id) MarkEpic(q, id) end)
  end
  snapReady = true
end

local EvaluateGear
do
  local function StillLoading(nf, of) return not nf.ready or (of and not of.ready) end

  local function GearWorthSharing(nf, of)
    local s = H:Settings()
    local gain = of and (nf.il - of.il)
    local epicNew = (nf.q or 0) >= 4 and (not of or (of.q or 0) < 4)
    local bigGain = gain and gain >= s.minGain and (nf.q or 0) >= (s.minGearQuality or 3)
    return bigGain or epicNew
  end

  EvaluateGear = function(slot, old, new, tries)
    local nf, of = ItemFacts(new), old and ItemFacts(old)
    if not nf then return end
    if StillLoading(nf, of) then
      if tries < 5 then C_Timer.After(1, function() GS:Call(EvaluateGear, slot, old, new, tries + 1) end) end
      return
    end
    local fields = { item = nf.id, link = new, il = nf.il, q = nf.q, oil = of and of.il, slot = slot }
    if GearWorthSharing(nf, of) then H:Add(Own("gear", fields), "self") else H:Activity(Act("gear", fields)) end
  end
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
      if not H.cdb.bankSeeded then H.cdb.everEquipped[id] = true end
    end
  end)
  H.cdb.bankSeeded = true
end

local recentKill = {}

local OnKill
do
  local function KillIdentity(encID, name)
    encID = Plain(encID, "number")
    if encID and encID <= 0 then encID = nil end
    name = Plain(name, "string")
    if name == "" then name = nil end
    return encID, name
  end

  local function KilledWithinMinute(key, now) return key and recentKill[key] and now - recentKill[key] < 60 end

  local function KillPlace()
    local inst, itype, _, _, _, _, _, instID = SafeCall(GetInstanceInfo)
    inst, itype = Plain(inst, "string"), Plain(itype, "string")
    if not inst or itype == "none" then inst = Plain(SafeCall(GetRealZoneText), "string") or inst end
    return inst, itype, Plain(instID, "number")
  end

  local function StillLevelling()
    local lvl, max = MyLevel(), MaxLevel()
    return not (lvl and max and lvl >= max)
  end

  local ENDGAME_DUNGEONS = { [229] = true, [230] = true, [289] = true, [329] = true, [429] = true }
  local function CountsAsNew(first, instID) return first and (StillLevelling() or ENDGAME_DUNGEONS[instID or 0]) end

  local function ReportRaidKill(fields, first)
    local guildies = GS:GroupGuildies()
    local rank = GS:ElectionRank(guildies)
    fields.raid, fields.grp, fields.n, fields.first = true, true, #guildies + 1, first or nil
    H:Add(Own("boss", fields), "self", { group = true, rank = rank })
  end

  local function ReportKill(fields, first, dungeon, instID)
    if dungeon then H:NoteDungeonKill(fields.inst, fields.boss, CountsAsNew(first, instID)) end
    if first and not dungeon then
      fields.first = true
      H:Add(Own("boss", fields), "self")
      return
    end
    fields.first = first or nil
    H:Activity(Act("boss", fields))
  end

  OnKill = function(encID, name)
    encID, name = KillIdentity(encID, name)
    local encKey, nameKey = encID and ("e" .. encID), name and ("n" .. name)
    local key = encKey or nameKey
    if not key then return end
    local now = GetTime()
    if KilledWithinMinute(encKey, now) or KilledWithinMinute(nameKey, now) then return end
    if encKey then recentKill[encKey] = now end
    if nameKey then recentKill[nameKey] = now end
    local inst, itype, instID = KillPlace()
    local first = not H.cdb.kills[key]
    H.cdb.kills[key] = GS:Now()
    local fields = { enc = encID, boss = name, inst = inst }
    if itype == "raid" then return ReportRaidKill(fields, first) end
    ReportKill(fields, first, itype == "party", instID)
  end
end

local qcache = {}

local ScanQuestLog
do
  local function CacheQuest(qid, title, level)
    if not qid or qid <= 0 then return end
    qcache[qid] = { title = Plain(title, "string"), level = Plain(level, "number") }
  end

  local function ScanModernQuestLog(QL)
    local n = Plain(SafeCall(QL.GetNumQuestLogEntries), "number") or 0
    for i = 1, n do
      local info = SafeCall(QL.GetInfo, i)
      if type(info) == "table" and not IsSecret(info) and not Plain(info.isHeader) then
        CacheQuest(Plain(info.questID, "number"), info.title, info.level)
      end
    end
  end

  local function ScanLegacyQuestLog()
    local n = Plain(SafeCall(GetNumQuestLogEntries), "number") or 0
    for i = 1, n do
      local r = { SafeCall(GetQuestLogTitle, i) }
      if not Plain(r[4]) then CacheQuest(Plain(r[8], "number"), r[1], r[2]) end
    end
  end

  ScanQuestLog = function()
    local QL = C_QuestLog
    if QL and QL.GetNumQuestLogEntries and QL.GetInfo then return ScanModernQuestLog(QL) end
    ScanLegacyQuestLog()
  end
end

H.NOTABLE_QUESTS = {
  [4743] = true, [6502] = true, [6602] = true, [7622] = true, [7636] = true, [7761] = true, [7787] = true, [7848] = true,
}

local QuestTag
do
  local function ReadQuestTagID(qid)
    local QL = C_QuestLog
    if QL and QL.GetQuestTagInfo then
      local info = SafeCall(QL.GetQuestTagInfo, qid)
      if type(info) == "table" and not IsSecret(info) then return Plain(info.tagID, "number") end
      return
    end
    if GetQuestTagInfo then return Plain(SafeCall(GetQuestTagInfo, qid), "number") end
  end

  local function IsOneOf(v, ...)
    for i = 1, select("#", ...) do if v == select(i, ...) then return true end end
    return false
  end

  QuestTag = function(qid)
    if H.NOTABLE_QUESTS[qid] then return "special" end
    local tagID = ReadQuestTagID(qid)
    if not tagID then return end
    local T = Enum and Enum.QuestTag or {}
    if IsOneOf(tagID, T.Legendary, 83) then return "legend" end
    if IsOneOf(tagID, T.Raid, T.Raid10, T.Raid25, 62, 88, 89) then return "raid" end
  end
end

local OnQuestTurnedIn
do
  local function QuestTitle(qid, c)
    if c.title or not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then return c.title end
    return Plain(SafeCall(C_QuestLog.GetTitleForQuestID, qid), "string")
  end

  OnQuestTurnedIn = function(qid)
    qid = Plain(qid, "number")
    if not qid then return end
    local c = qcache[qid] or {}
    local title = QuestTitle(qid, c)
    local tag = QuestTag(qid)
    local fields = { qid = qid, title = title, ql = c.level, tag = tag }
    if not tag or H.cdb.quests[qid] then H:Activity(Act("quest", fields)) return end
    H.cdb.quests[qid] = true
    H:Add(Own("quest", fields), "self")
  end
end

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

local function Pattern(f)
  local p = GS.FormatToPattern(f)
  if p and p:sub(-3) == "%.$" then p = p:sub(1, -4) .. "%.?$" end
  return p
end
local P
local function LootPatterns()
  if P then return P end
  P = { self = {}, other = {} }
  local own = { { LOOT_ITEM_SELF_MULTIPLE }, { LOOT_ITEM_SELF }, { LOOT_ITEM_CREATED_SELF_MULTIPLE, "craft" },
    { LOOT_ITEM_CREATED_SELF, "craft" } }
  for _, f in ipairs(own) do
    local p = Pattern(f[1])
    if p then P.self[#P.self + 1] = { p = p, src = f[2] } end
  end
  for _, f in ipairs({ LOOT_ITEM_MULTIPLE, LOOT_ITEM }) do
    local p = Pattern(f)
    if p then P.other[#P.other + 1] = p end
  end
  return P
end

local OnLoot
do
  local function MatchOwnLoot(text, pats)
    for _, own in ipairs(pats.self) do
      local l, n = text:match(own.p)
      if l then return l, GS:PlayerKey(), tonumber(n), own.src end
    end
  end

  local function MatchOthersLoot(text, pats, playerName)
    for _, p in ipairs(pats.other) do
      local name, l = text:match(p)
      if name and l then return l, GS:NormName(Plain(playerName, "string") or name) end
    end
  end

  local function NoteSecretLoot()
    if H.db then H.db.diag.secretLoot = (H.db.diag.secretLoot or 0) + 1 end
  end

  local function Notable(f) return f and f.id and f.q and f.q >= H:Settings().minLootQuality end

  local function GroupedWith(who)
    local inGroup, others = false, {}
    for _, k in ipairs(GS:GroupGuildies()) do
      if k == who then inGroup = true else others[#others + 1] = k end
    end
    return inGroup, others
  end

  local function WitnessLoot(who, me, f, link)
    if GS:IsGuildMember(who) ~= true or GS:IsPeer(who) then return end
    local inGroup, others = GroupedWith(who)
    if not inGroup then return end
    local r = GS:RosterEntry(who) or {}
    local t = GS:Now()
    H:Add({ k = "loot", t = t, who = who, by = me, cls = r.class, lvl = r.level, item = f.id, link = link, q = f.q,
      id = H.WitnessID(who, f.id, t) }, "witness", { group = true, rank = (GS:ElectionRank(others)) })
  end

  OnLoot = function(text, playerName)
    text = Plain(text, "string")
    if not text then return NoteSecretLoot() end
    local pats = LootPatterns()
    local link, who, count, src = MatchOwnLoot(text, pats)
    if not link then link, who = MatchOthersLoot(text, pats, playerName) end
    if not (link and who) then return end
    link = link:match("(|c.-|r)") or link
    local f = ItemFacts(link)
    local me = GS:PlayerKey()
    if not Notable(f) then
      if who == me and f and f.id then H:Activity(Act("loot", { item = f.id, link = link, q = f.q, n = count })) end
      return
    end
    if who ~= me then return WitnessLoot(who, me, f, link) end
    H.cdb.ownedEpics[f.id] = true
    H:Add(Own("loot", { item = f.id, link = link, q = f.q, src = src }), "self")
  end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "ENCOUNTER_END", "BOSS_KILL", "QUEST_LOG_UPDATE",
  "QUEST_ACCEPTED", "QUEST_COMPLETE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "CHAT_MSG_LOOT",
  "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }
local QUIET = { QUEST_LOG_UPDATE = true, BAG_UPDATE_DELAYED = true }

local armed = {}
local function Soon(key, delay, fn)
  if armed[key] then return end
  armed[key] = true
  C_Timer.After(delay, function() armed[key] = nil; GS:Call(fn) end)
end

local wasInInstance = false
local OnEvent
do
  local function QueueQuestScan() Soon("quests", 1, ScanQuestLog) end

  local Handlers = {
    PLAYER_ENTERING_WORLD = function()
      if not snapReady then Soon("snap", 3, TakeSnapshot) end
      QueueQuestScan()
      local inside = GS:InInstance()
      if wasInInstance and not inside then GS:Call(H.OnLeftInstance, H) end
      wasInInstance = inside
      GS:Call(H.OnRunZone, H, inside)
    end,
    PLAYER_EQUIPMENT_CHANGED = function(slot) GS:Call(OnEquipmentChanged, slot) end,
    ENCOUNTER_END = function(encID, name, _, _, success)
      success = Plain(success)
      if success == 1 or success == true then GS:Call(OnKill, encID, name) end
    end,
    BOSS_KILL = function(encID, name) GS:Call(OnKill, encID, name) end,
    QUEST_LOG_UPDATE = QueueQuestScan,
    QUEST_ACCEPTED = QueueQuestScan,
    QUEST_COMPLETE = function() GS:Call(ScanQuestLog) end,
    QUEST_TURNED_IN = function(qid) GS:Call(OnQuestTurnedIn, qid) end,
    PLAYER_LEVEL_UP = function(level) GS:Call(OnLevelUp, level) end,
    CHAT_MSG_LOOT = function(text, playerName) GS:Call(OnLoot, text, playerName) end,
    BAG_UPDATE_DELAYED = function() Soon("bags", 1, ScanBagsForEpics) end,
    BANKFRAME_OPENED = function() GS:Call(OnBankOpened) end,
    BANKFRAME_CLOSED = function() C_Timer.After(1, function() bankOpen = false end) end,
  }

  OnEvent = function(event, ...)
    if not H.db then return end
    if not QUIET[event] then Diag(event, ...) end
    local handle = Handlers[event]
    if handle then handle(...) end
  end
end
for _, e in ipairs(EVENTS) do H:RegisterEvent(e, function(_, ...) OnEvent(e, ...) end) end

function H:OnLogin()
  LootPatterns()
  self:SeedMilestones()
  wasInInstance = GS:InInstance()
  self:OnLoginOutbox()
  self:OnLoginCatchup()
end
