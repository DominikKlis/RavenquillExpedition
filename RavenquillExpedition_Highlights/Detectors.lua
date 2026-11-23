local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, IsSecret, Plain = GS.SafeCall, GS.IsSecret, GS.Plain

local function MyLevel() return Plain(SafeCall(UnitLevel, "player"), "number") end
local function MaxLevel() return Plain(SafeCall(GetMaxPlayerLevel), "number") end

local function Own(k, fields, at)
  local who = GS:PlayerKey()
  if not who then return end
  local t = at or GS:Now()
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
  local name, _, q = H.ItemInfo(link)
  f.q = Plain(q, "number") or LinkQuality(link)
  if not Plain(name, "string") and f.id then H.RequestItemData(f.id) end
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
local ownedSeeded = false

local function WornItem(slot) return ItemID(Plain(SafeCall(GetInventoryItemLink, "player", slot), "string")) end

local function MarkOwned(id)
  if id then H.cdb.ownedEpics[id] = true end
end

local function SeedOwned()
  for _, s in ipairs(GEAR_SLOTS) do MarkOwned(WornItem(s)) end
  EachItem(BagList(), function(_, _, id) MarkOwned(id) end)
  ownedSeeded = true
end

local function OnEquipmentChanged(slot)
  if ownedSeeded and IS_GEAR[slot] then MarkOwned(WornItem(slot)) end
end

H.QUEST_REWARD_WINDOW = 10
local bankOpen, questRewardUntil = false, -math.huge

local function NewEpicInBags(link, q, id, reward)
  if reward then return H:Add(Own("loot", { item = id, link = link, q = q, src = "quest" }), "self") end
  H:Activity(Act("loot", { item = id, link = link, q = q, src = "bag" }))
end

local function ScanBagsForEpics()
  if not ownedSeeded then return end
  local reward = GetTime() <= questRewardUntil
  EachItem(BagList(), function(link, q, id)
    if not id or H.cdb.ownedEpics[id] then return end
    MarkOwned(id)
    if not bankOpen and (q or 0) >= H.LOOT_QUALITY then NewEpicInBags(link, q, id, reward) end
  end)
end

local function OnBankOpened()
  bankOpen = true
  EachItem(BankList(), function(_, _, id) MarkOwned(id) end)
end

local recentKill = {}
H.RAID_FINALE = { [672] = true, [1084] = true, [617] = true, [793] = true, [723] = true, [717] = true, [1114] = true }

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
    local inst, itype = SafeCall(GetInstanceInfo)
    inst, itype = Plain(inst, "string"), Plain(itype, "string")
    if not inst or itype == "none" then inst = Plain(SafeCall(GetRealZoneText), "string") or inst end
    return inst, itype
  end

  local function GuildFirst(fields, first)
    return first and fields.enc ~= nil and not H:FirstKnown("e" .. fields.enc)
  end

  local function ReportGuildFirst(fields)
    local guildies = GS:GroupGuildies()
    local e = Own("first", { what = "boss", enc = fields.enc, boss = fields.boss, inst = fields.inst })
    if not guildies[1] then return H:Add(e, "self") end
    e.grp, e.n = true, #guildies + 1
    H:Add(e, "self", { group = true, rank = (GS:ElectionRank(guildies)) })
  end

  local function ReportRaidKill(fields, first)
    local guildies = GS:GroupGuildies()
    local share = { group = true, rank = (GS:ElectionRank(guildies)) }
    local guildFirst = GuildFirst(fields, first)
    fields.raid, fields.grp, fields.n, fields.first = true, true, #guildies + 1, first or nil
    H:Add(Own("boss", fields), "self", share)
    if guildFirst then ReportGuildFirst(fields) end
    if not H.RAID_FINALE[fields.enc or 0] then return end
    H:Add(Own("clear", { enc = fields.enc, inst = fields.inst, n = fields.n, grp = true }), "self", share)
  end

  local function ReportKill(fields, first, dungeon)
    if dungeon then H:NoteDungeonKill(fields.inst, fields.boss, first) end
    if first and not dungeon then
      if GuildFirst(fields, first) then return ReportGuildFirst(fields) end
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
    local inst, itype = KillPlace()
    local first = not H.cdb.kills[key]
    H.cdb.kills[key] = GS:Now()
    local fields = { enc = encID, boss = name, inst = inst }
    if itype == "raid" then return ReportRaidKill(fields, first) end
    ReportKill(fields, first, itype == "party")
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

local OnQuestTurnedIn
do
  local function QuestTitle(qid, c)
    if c.title or not (C_QuestLog and C_QuestLog.GetTitleForQuestID) then return c.title end
    return Plain(SafeCall(C_QuestLog.GetTitleForQuestID, qid), "string")
  end

  OnQuestTurnedIn = function(qid)
    questRewardUntil = GetTime() + H.QUEST_REWARD_WINDOW
    qid = Plain(qid, "number")
    if not (qid and H.ATTUNEMENT_QUESTS[qid]) or H.cdb.quests[qid] then return end
    H.cdb.quests[qid] = true
    local c = qcache[qid] or {}
    H:CompleteStep(Own("quest", { qid = qid, title = QuestTitle(qid, c), ql = c.level, tag = "special" }))
  end
end

local function FirstAtLevel(level)
  if not GS:RosterComplete() or H:FirstKnown("v" .. level) then return false end
  for key, member in GS:EachMember() do
    if not GS:IsMe(key) and (member.level or 0) >= level then return false end
  end
  return true
end

local function OnLevelUp(level)
  level = Plain(level, "number")
  if not level then return end
  local max = MaxLevel()
  if max and level == max and FirstAtLevel(level) then return H:Add(Own("first", { what = "level", lvl = level }), "self") end
  if level % H.LEVEL_STEP == 0 or (max and level == max) then
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

  local function Notable(f) return f and f.id and f.q and f.q >= H.LOOT_QUALITY end

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

  local function MatchLoot(text, playerName)
    local pats = LootPatterns()
    local link, who, count, src = MatchOwnLoot(text, pats)
    if not link then link, who = MatchOthersLoot(text, pats, playerName) end
    if link and who then return link:match("(|c.-|r)") or link, who, count, src end
  end

  local function OwnLoot(f, link, count, src)
    if not Notable(f) then
      if f and f.id then H:Activity(Act("loot", { item = f.id, link = link, q = f.q, n = count })) end
      return
    end
    H.cdb.ownedEpics[f.id] = true
    H:Add(Own("loot", { item = f.id, link = link, q = f.q, src = src }), "self")
  end

  OnLoot = function(text, playerName)
    text = Plain(text, "string")
    if not text then return NoteSecretLoot() end
    local link, who, count, src = MatchLoot(text, playerName)
    if not link then return end
    local f, me = ItemFacts(link), GS:PlayerKey()
    if who == me then return OwnLoot(f, link, count, src) end
    if Notable(f) then WitnessLoot(who, me, f, link) end
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
    PLAYER_ENTERING_WORLD = function(initialLogin)
      if Plain(initialLogin) then GS:Call(H.EndMountSeeding, H) end
      if not ownedSeeded then Soon("owned", 3, SeedOwned) end
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
