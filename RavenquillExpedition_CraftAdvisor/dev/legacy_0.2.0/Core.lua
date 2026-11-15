-- Guild Craft Advisor: records guildmates' gear when you inspect them and
-- suggests Leatherworking crafts that would be upgrades.
local ADDON, ns = ...

local GCA = CreateFrame("Frame")
ns.GCA = GCA
GuildCraftAdvisor = GCA

GCA.PROFESSION_SKILL_LINE = 165 -- Leatherworking
GCA.MIN_GAIN = 0.5               -- smallest score gain that counts as an upgrade
GCA.LOOKAHEAD_LEVELS = 5

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Print(...) print("|cff33ff99GuildCraft|r:", ...) end
GCA.Print = Print

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
GCA.IsSecret = IsSecret

local function pack(...) return { n = select("#", ...), ... } end
local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end
GCA.SafeCall = SafeCall

local ItemAPI = {
  Info     = (C_Item and C_Item.GetItemInfo) or GetItemInfo,
  Instant  = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
  Request  = C_Item and C_Item.RequestLoadItemDataByID,
  Stats    = (C_Item and C_Item.GetItemStats) or GetItemStats,
  NameByID = C_Item and C_Item.GetItemNameByID,
  Count    = (C_Item and C_Item.GetItemCount) or GetItemCount,
}
GCA.ItemAPI = ItemAPI

local function ItemIDFrom(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
end
GCA.ItemIDFrom = ItemIDFrom

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- equipLoc -> inventory slots it can go into (weapons left out on purpose)
GCA.SLOTS_FOR = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}
GCA.DISPLAY_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

---------------------------------------------------------------------------
-- Stat weights (rough, general-purpose per class; tweak to taste)
---------------------------------------------------------------------------
local STATKEY = {
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
  RESISTANCE0_NAME = "armor",
  RESISTANCE1_NAME = "res", RESISTANCE2_NAME = "res", RESISTANCE3_NAME = "res",
  RESISTANCE4_NAME = "res", RESISTANCE5_NAME = "res", RESISTANCE6_NAME = "res",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
  ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap",
  ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
  ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "scrit",
  ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
  ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
  ITEM_MOD_PARRY_RATING_SHORT = "dodge", ITEM_MOD_BLOCK_RATING_SHORT = "dodge",
  ITEM_MOD_BLOCK_VALUE_SHORT = "blockv",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
}

local BASE = { armor = 0.02, res = 0.05, hp5 = 0.5 }
local function W(t) for k, v in pairs(BASE) do if t[k] == nil then t[k] = v end end return t end
GCA.WEIGHTS = {
  WARRIOR = W{ str = 1.0, agi = 0.6, sta = 0.6, ap = 0.5, crit = 12, hit = 12, def = 0.8, dodge = 8, blockv = 0.1, armor = 0.04 },
  PALADIN = W{ str = 0.9, agi = 0.4, sta = 0.6, int = 0.5, spi = 0.2, ap = 0.4, sp = 0.5, heal = 0.5, crit = 10, hit = 10, mp5 = 1.5, def = 0.5, armor = 0.03 },
  ROGUE   = W{ agi = 1.0, str = 0.5, sta = 0.4, ap = 0.5, crit = 12, hit = 14, dodge = 4 },
  HUNTER  = W{ agi = 1.0, int = 0.3, sta = 0.4, spi = 0.1, rap = 0.5, ap = 0.1, crit = 12, hit = 12, mp5 = 1 },
  DRUID   = W{ agi = 0.7, str = 0.6, sta = 0.5, int = 0.6, spi = 0.4, ap = 0.3, fap = 0.3, sp = 0.6, heal = 0.4, crit = 8, hit = 8, scrit = 6, mp5 = 1.5 },
  SHAMAN  = W{ int = 0.7, str = 0.6, agi = 0.5, sta = 0.5, spi = 0.2, ap = 0.3, sp = 0.7, heal = 0.5, crit = 8, hit = 8, scrit = 8, mp5 = 2 },
  MAGE    = W{ int = 0.8, sta = 0.6, spi = 0.4, sp = 1.0, scrit = 10, shit = 12, mp5 = 1.5, armor = 0.01 },
  WARLOCK = W{ int = 0.6, sta = 0.8, spi = 0.3, sp = 1.0, scrit = 8, shit = 12, mp5 = 1, armor = 0.01 },
  PRIEST  = W{ int = 0.8, spi = 0.7, sta = 0.5, sp = 0.7, heal = 0.8, scrit = 8, mp5 = 2, armor = 0.01 },
}
GCA.WEIGHTS.DEFAULT = W{ str = 0.6, agi = 0.6, sta = 0.6, int = 0.6, spi = 0.3, ap = 0.3, sp = 0.5, heal = 0.4 }

local PERCENT_STATS = { crit = true, hit = true, scrit = true, shit = true, dodge = true }

function GCA:ScoreStats(stats, class)
  if type(stats) ~= "table" then return 0 end
  local w = self.WEIGHTS[class or ""] or self.WEIGHTS.DEFAULT
  local s = 0
  for k, v in pairs(stats) do
    local key = STATKEY[k]
    if key and type(v) == "number" and w[key] then
      -- Vanilla items give "+1% crit"; if a client reports ratings instead, scale them down.
      if PERCENT_STATS[key] and v > 5 then v = v / 14 end
      s = s + v * w[key]
    end
  end
  return s
end

---------------------------------------------------------------------------
-- Item info cache (keyed by itemID or full link)
---------------------------------------------------------------------------
GCA.infoCache = {}

function GCA:GetInfo(item)
  if not item then return end
  local c = self.infoCache[item]
  if c then return c end
  local name, link, quality, ilvl, minLevel, _, _, _, equipLoc, icon, _, classID, subClassID, bindType =
    SafeCall(ItemAPI.Info, item)
  if not name or IsSecret(name) then
    local id = ItemIDFrom(item)
    if id and ItemAPI.Request then SafeCall(ItemAPI.Request, id) end
    return
  end
  local statLink = (type(item) == "string" and item) or link
  local stats = SafeCall(ItemAPI.Stats, statLink)
  c = {
    itemID = ItemIDFrom(item) or ItemIDFrom(link), name = name,
    link = (type(link) == "string" and link:find("|H", 1, true) and link) or (type(item) == "string" and item) or link,
    quality = quality, ilvl = ilvl, minLevel = minLevel or 0, equipLoc = equipLoc, icon = icon,
    classID = classID, subClassID = subClassID, bind = bindType,
    stats = type(stats) == "table" and stats or {}, scores = {},
  }
  self.infoCache[item] = c
  return c
end

function GCA:Score(info, class)
  local key = class or "DEFAULT"
  local s = info.scores[key]
  if not s then
    s = self:ScoreStats(info.stats, class)
    info.scores[key] = s
  end
  return s
end

---------------------------------------------------------------------------
-- Names / guild
---------------------------------------------------------------------------
function GCA:NormName(n)
  if not n or IsSecret(n) then return end
  if Ambiguate then n = Ambiguate(n, "none") end
  return n
end

-- On Forever the 2nd value of UnitName is a SURNAME (not a realm), and the guild
-- roster / addon senders show "First<sep>Surname" (sep is usually a space).
local IS_FOREVER = (select(4, GetBuildInfo()) or 0) >= 16000 and (select(4, GetBuildInfo()) or 0) < 20000
local function SurnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and sep ~= "" and not IsSecret(sep) then return sep end
  return " "
end

function GCA:UnitKey(unit)
  local read = UnitNameUnmodified or UnitName
  local name, second = SafeCall(read, unit)
  if not name or IsSecret(name) or name == "" or name == UNKNOWNOBJECT then return end
  if second and not IsSecret(second) and second ~= "" then
    local sep = IS_FOREVER and SurnameSeparator() or "-"
    if name:sub(-(#sep + #second)) ~= sep .. second then name = name .. sep .. second end
  end
  return self:NormName(name)
end

function GCA:IsGuildmate(unit)
  if SafeCall(UnitIsUnit, unit, "player") then return true end
  if UnitIsInMyGuild and SafeCall(UnitIsInMyGuild, unit) then return true end
  local key = self:UnitKey(unit)
  if key and self.roster[key] then return true end
  local g, mine = SafeCall(GetGuildInfo, unit), SafeCall(GetGuildInfo, "player")
  return g and mine and not IsSecret(g) and g == mine or false
end

GCA.roster = {}
function GCA:ReadRoster()
  if not IsInGuild() then wipe(self.roster) return end
  local n = SafeCall(GetNumGuildMembers) or 0
  if IsSecret(n) or n == 0 then return end
  self.rosterLoaded = true
  wipe(self.roster)
  for i = 1, n do
    local name, _, _, level, _, _, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      self.roster[key] = { level = level, class = classFile, online = online and true or false }
    end
  end
end

function GCA:RequestRoster()
  if not IsInGuild() then return end
  if C_GuildInfo and C_GuildInfo.GuildRoster then SafeCall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then SafeCall(GuildRoster) end
end

---------------------------------------------------------------------------
-- Gear capture
---------------------------------------------------------------------------
function GCA:ReadUnitItems(unit, into)
  local got = 0
  for slot = 1, 19 do
    local link = SafeCall(GetInventoryItemLink, unit, slot)
    if type(link) == "string" and not IsSecret(link) then
      into[slot] = link
      got = got + 1
    end
  end
  return got
end

function GCA:Now() return (GetServerTime and GetServerTime()) or time() end

-- The 17 slots that are compared and synced (no shirt 4, no tabard 19).
GCA.SYNC_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
GCA.IS_SYNC_SLOT = {}
for _, s in ipairs(GCA.SYNC_SLOTS) do GCA.IS_SYNC_SLOT[s] = true end

-- Split on ":" keeping empty fields (string.gmatch with empty matches differs between Lua 5.1 and 5.4).
local function SplitColon(s)
  local out, pos = {}, 1
  while true do
    local i = s:find(":", pos, true)
    if not i then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, i - 1)
    pos = i + 1
  end
end
GCA.SplitColon = SplitColon

-- Fields of the item string after "item:" (works for full hyperlinks and bare "item:..." strings).
function GCA:ParseLink(link)
  if type(link) ~= "string" then return end
  local s = link:match("item:([^|%[%]]+)")
  if not s or not s:match("^%d") then return end
  return SplitColon(s)
end

-- Item string with the VIEWER's fields blanked (9 = link level, 10 = spec; they hold the level of
-- whoever looked, not the wearer: plan rev 4 B1b) and trailing empty fields trimmed.
function GCA:NormItem(link)
  local f = self:ParseLink(link)
  if not f then return end
  if f[9] then f[9] = "" end
  if f[10] then f[10] = "" end
  local n = #f
  while n > 1 and f[n] == "" do f[n] = nil; n = n - 1 end
  return table.concat(f, ":")
end

-- Fingerprint of a gear set over the 17 synced slots.
function GCA:GearSignature(items)
  local parts = {}
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local n = items and self:NormItem(items[slot])
    if n then parts[#parts + 1] = slot .. "=" .. n end
  end
  return table.concat(parts, ",")
end

local function CountSync(self, items)
  local n = 0
  for _, slot in ipairs(self.SYNC_SLOTS) do if items and self:NormItem(items[slot]) then n = n + 1 end end
  return n
end

-- True when `fresh` read fewer slots than `old` and every slot it did read is identical:
-- an incomplete read, not a gear change (plan rev 4 D1.6).
function GCA:IsPartialRead(old, fresh)
  if not old then return false end
  if CountSync(self, fresh) >= CountSync(self, old) then return false end
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local f = self:NormItem(fresh[slot])
    if f and f ~= self:NormItem(old[slot]) then return false end
  end
  return true
end

-- Stores a gear record for `key`. Returns changed (true only for a real gear change).
-- Unchanged gear only refreshes time/level/class; ts, source and from stay (plan rev 4 D1.5).
function GCA:StoreRecord(key, class, level, items, source)
  if not key then return false end
  local m = self.db.members[key]
  local isNew = m == nil
  m = m or {}
  if class then m.class = class end
  if type(level) == "number" and level > 0 then m.level = level end
  m.time = time()
  local changed = isNew or not m.items or self:GearSignature(m.items) ~= self:GearSignature(items)
  if changed and source == "inspect" and self:IsPartialRead(m.items, items) then changed = false end
  if changed then
    m.items = items
    m.ts = self:Now()
    m.source = source
    m.from = nil
  else
    -- same gear: keep the record, but take fresh real hyperlinks for slots we read
    if m.items then
      for slot, link in pairs(items) do
        if self:NormItem(link) == self:NormItem(m.items[slot]) then m.items[slot] = link end
      end
    end
    if not m.ts then m.ts = self:Now() end
    if not m.source then m.source = source end
  end
  self.db.members[key] = m
  return changed
end

local function UnitClassLevel(unit)
  local _, class = SafeCall(UnitClass, unit)
  local level = SafeCall(UnitLevel, unit)
  if IsSecret(class) then class = nil end
  if IsSecret(level) or type(level) ~= "number" then level = nil end
  return class, level
end

-- Returns key, changed
function GCA:StoreMember(unit, items, source)
  local key = self:UnitKey(unit)
  if not key then return end
  local class, level = UnitClassLevel(unit)
  return key, self:StoreRecord(key, class, level, items, source)
end

function GCA:CaptureSelf()
  if not self.db then return end
  local items = {}
  self:ReadUnitItems("player", items)
  local key, changed = self:StoreMember("player", items, "self")
  self.playerKey = key
  if changed and self.OnOwnGearChanged then SafeCall(self.OnOwnGearChanged, self) end
  self:Invalidate()
end

local UNIT_TOKENS = { "target", "mouseover", "focus", "party1", "party2", "party3", "party4" }
for i = 1, 40 do UNIT_TOKENS[#UNIT_TOKENS + 1] = "raid" .. i end

function GCA:UnitFromGUID(guid)
  if not guid or IsSecret(guid) then return end
  if UnitTokenFromGUID then
    local u = SafeCall(UnitTokenFromGUID, guid)
    if u and not IsSecret(u) then return u end
  end
  if InspectFrame and InspectFrame.unit and SafeCall(UnitGUID, InspectFrame.unit) == guid then
    return InspectFrame.unit
  end
  for _, u in ipairs(UNIT_TOKENS) do
    local g = SafeCall(UnitGUID, u)
    if g and not IsSecret(g) and g == guid then return u end
  end
end

-- INSPECT_READY fires both for our own requests and when you inspect someone
-- with the normal UI. Item links can arrive in pieces, so read a few times.
function GCA:OnInspectReady(guid)
  local unit = self:UnitFromGUID(guid)
  if unit and SafeCall(UnitIsPlayer, unit) and not SafeCall(UnitIsUnit, unit, "player")
     and (not self.db.settings.guildOnly or self:IsGuildmate(unit)) then
    -- Who it is is fixed on the first pass; later passes only add items. Only the final pass
    -- stores, and it stores what was collected even if the unit token is gone by then.
    local fresh = {}
    local key = self:UnitKey(unit)
    local class, level = UnitClassLevel(unit)
    if not key then self:InspectDone(guid) return end
    local function read()
      local u = self:UnitFromGUID(guid)
      if u then self:ReadUnitItems(u, fresh) end
    end
    read()
    C_Timer.After(0.5, read)
    C_Timer.After(1.5, function()
      read()
      if not next(fresh) then return end
      local changed = self:StoreRecord(key, class, level, fresh, "inspect")
      if changed and self.RelayInspect then SafeCall(self.RelayInspect, self, key) end
      if self.verbose or self.announce == guid then
        self.announce = nil
        Print("Recorded gear of " .. key .. ". /gca to view.")
        if self.UI then self.UI.selected = key end
      end
      self:Invalidate()
    end)
  end
  self:InspectDone(guid)
end

---------------------------------------------------------------------------
-- Inspect queue (for "Inspect target", "Scan group" and auto-inspect)
---------------------------------------------------------------------------
GCA.queue, GCA.lastInspect = {}, {}

function GCA:QueueInspect(unit, force)
  local guid = SafeCall(UnitGUID, unit)
  if not guid or IsSecret(guid) then return false end
  if not force and self.lastInspect[guid] and GetTime() - self.lastInspect[guid] < 120 then return false end
  for _, g in ipairs(self.queue) do if g == guid then return true end end
  self.queue[#self.queue + 1] = guid
  self:ProcessQueue()
  return true
end

function GCA:ProcessQueue()
  if self.inspecting then return end
  if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then
    if #self.queue > 0 then C_Timer.After(3, function() self:ProcessQueue() end) end
    return
  end
  while #self.queue > 0 do
    local guid = table.remove(self.queue, 1)
    local unit = self:UnitFromGUID(guid)
    if unit and SafeCall(CanInspect, unit) then
      self.inspecting = guid
      self.lastInspect[guid] = GetTime()
      SafeCall(NotifyInspect, unit)
      C_Timer.After(3, function()
        if self.inspecting == guid then -- no answer (out of range?)
          self.inspecting = nil
          self:ProcessQueue()
        end
      end)
      return
    end
  end
end

function GCA:InspectDone(guid)
  if self.inspecting and self.inspecting == guid then
    self.inspecting = nil
    C_Timer.After(1, function() self:ProcessQueue() end)
  end
end

function GCA:InspectTarget()
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then
    Print("Target a guild member first.") return
  end
  if self.db.settings.guildOnly and not self:IsGuildmate("target") then
    Print("Your target is not in your guild.") return
  end
  if not SafeCall(CanInspect, "target") then Print("Can't inspect that target right now.") return end
  self.announce = SafeCall(UnitGUID, "target")
  self:QueueInspect("target", true)
  Print("Inspecting " .. (self:UnitKey("target") or "target") .. "...")
end

function GCA:ScanGroup()
  local n = 0
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  for i = 1, count do
    local u = prefix .. i
    if SafeCall(UnitIsPlayer, u) and not SafeCall(UnitIsUnit, u, "player") and self:IsGuildmate(u)
       and SafeCall(CanInspect, u) and self:QueueInspect(u, true) then
      n = n + 1
    end
  end
  Print(n > 0 and ("Queued " .. n .. " guild members for inspection.") or "No guild members in your group to inspect.")
end

---------------------------------------------------------------------------
-- Recipes you know
---------------------------------------------------------------------------
GCA.knownNow, GCA.itemToSpell = {}, {}

function GCA:RecipeTable() return ns.Recipes.Leatherworking end

local function SpellKnown(spellID)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID)
    if ok and not IsSecret(v) and v then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, spellID)
    if ok and not IsSecret(v) and v then return true end
  end
  return false
end

function GCA:RefreshKnown()
  local saved = self.db.known[self.charKey] or {}
  self.db.known[self.charKey] = saved
  wipe(self.knownNow)
  local n = 0
  for spellID in pairs(self:RecipeTable()) do
    if saved[spellID] or SpellKnown(spellID) then
      self.knownNow[spellID] = true
      saved[spellID] = true
      n = n + 1
    end
  end
  self.knownCount = n
  self.candidates = nil
  self:Invalidate()
end

function GCA:IsKnown(spellID) return self.knownNow[spellID] == true end

-- Extra safety net: read the open profession window directly.
function GCA:ScanTradeSkill()
  local saved = self.db.known[self.charKey]
  local api = C_TradeSkillUI
  if api and api.GetAllRecipeIDs and api.GetRecipeInfo then
    local ids = SafeCall(api.GetAllRecipeIDs)
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        if self:RecipeTable()[id] then
          local info = SafeCall(api.GetRecipeInfo, id)
          if type(info) == "table" and info.learned then saved[id] = true end
        end
      end
    end
  end
  if GetNumTradeSkills and GetTradeSkillItemLink then
    local n = SafeCall(GetNumTradeSkills) or 0
    for i = 1, n do
      local id = ItemIDFrom(SafeCall(GetTradeSkillItemLink, i))
      local spellID = id and self.itemToSpell[id]
      if spellID then saved[spellID] = true end
    end
  end
  self:RefreshKnown()
end

function GCA:GetSkill()
  if not (GetProfessions and GetProfessionInfo) then return end
  local p1, p2 = SafeCall(GetProfessions)
  for _, idx in pairs({ p1, p2 }) do
    local name, _, rank, maxRank, _, _, skillLine = SafeCall(GetProfessionInfo, idx)
    if skillLine == self.PROFESSION_SKILL_LINE then return rank, maxRank, name end
  end
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
local CLOTH_ONLY = { MAGE = true, PRIEST = true, WARLOCK = true }

function GCA:CanWear(class, level, cand)
  if cand.classID ~= 4 then return false end -- armor only
  local sub = cand.subClassID
  if cand.equipLoc == "INVTYPE_CLOAK" or sub == 0 or sub == 1 then return true end
  if not class then return true end
  if sub == 2 then return not CLOTH_ONLY[class] end
  if sub == 3 then
    return class == "WARRIOR" or class == "PALADIN"
      or ((class == "HUNTER" or class == "SHAMAN") and (level or 0) >= 40)
  end
  if sub == 4 then return (class == "WARRIOR" or class == "PALADIN") and (level or 0) >= 40 end
  if sub == 6 then return class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" end
  return false
end

-- Equippable crafted items (needs only the client's static item DB).
function GCA:GetCandidates()
  if self.candidates then return self.candidates end
  local list, missing = {}, false
  for spellID, r in pairs(self:RecipeTable()) do
    local _, _, _, equipLoc, icon, classID, subClassID = SafeCall(ItemAPI.Instant, r.item)
    if equipLoc == nil then
      missing = true
    elseif self.SLOTS_FOR[equipLoc] then
      list[#list + 1] = {
        spellID = spellID, itemID = r.item, recipe = r, equipLoc = equipLoc,
        icon = icon, classID = classID, subClassID = subClassID,
      }
    end
  end
  if not missing then self.candidates = list end
  return list
end

-- Returns: sorted list of suggestions, number of items still loading
function GCA:ComputeSuggestions(m, isSelf)
  local s = self.db.settings
  local class, level = m.class, m.level or 60
  local maxLevel = level + (s.lookahead and self.LOOKAHEAD_LEVELS or 0)
  local items = m.items or {}
  local pending = 0
  local slotCache = {}

  local function slotScore(slot)
    local c = slotCache[slot]
    if c then return c.score, c.info end
    local link = items[slot]
    if not link then slotCache[slot] = { score = 0 } return 0 end
    local info = self:GetInfo(link)
    if not info then pending = pending + 1 return end
    local sc = self:Score(info, class)
    slotCache[slot] = { score = sc, info = info }
    return sc, info
  end

  local best = {}
  for _, cand in ipairs(self:GetCandidates()) do
    local known = self:IsKnown(cand.spellID)
    if (known or s.showUnlearned) and self:CanWear(class, level, cand) then
      local info = self:GetInfo(cand.itemID)
      if not info then
        pending = pending + 1
      elseif info.minLevel <= maxLevel and (isSelf or info.bind ~= 1) then
        local slots = self.SLOTS_FOR[cand.equipLoc]
        local tSlot, tScore, tInfo
        for _, slot in ipairs(slots) do
          local sc, ei = slotScore(slot)
          if sc and (not tScore or sc < tScore) then tSlot, tScore, tInfo = slot, sc, ei end
        end
        if tSlot and not (tInfo and tInfo.itemID == cand.itemID) then
          local newScore = self:Score(info, class)
          local gain = newScore - tScore
          if gain >= self.MIN_GAIN then
            local gkey = slots[1] .. (known and "k" or "u")
            local cur = best[gkey]
            if not cur or gain > cur.gain then
              best[gkey] = {
                cand = cand, info = info, slot = tSlot, gain = gain, newScore = newScore,
                oldScore = tScore, equipped = tInfo, known = known,
                future = info.minLevel > level,
              }
            end
          end
        end
      end
    end
  end

  local list = {}
  for gkey, sug in pairs(best) do
    -- hide an unlearned suggestion when a known recipe for that slot is at least as good
    local other = (not sug.known) and best[gkey:sub(1, -2) .. "k"]
    if not (other and other.gain >= sug.gain) then list[#list + 1] = sug end
  end
  -- biggest upgrade first, learned or not (unlearned ones are marked in the UI)
  table.sort(list, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    if a.known ~= b.known then return a.known end
    return a.slot < b.slot
  end)
  return list, pending
end

-- All members for the left-hand list (guild roster + everyone we have gear for)
function GCA:GetMemberList()
  local s = self.db.settings
  local entries, seen = {}, {}
  local function add(key)
    if seen[key] then return end
    seen[key] = true
    local m, r = self.db.members[key], self.roster[key]
    local isSelf = key == self.playerKey
    if not isSelf and not r and not (m and m.source ~= "self") then return end
    local online = isSelf or (r and r.online) or false
    if s.hideOffline and not online and not m then return end
    local e = {
      key = key, isSelf = isSelf, online = online, member = m,
      class = (r and r.class) or (m and m.class), level = (r and r.level) or (m and m.level),
    }
    if m then
      local view = { class = e.class, level = e.level, items = m.items }
      e.suggestions, e.pending = self:ComputeSuggestions(view, isSelf)
      e.bestGain = e.suggestions[1] and e.suggestions[1].gain or 0
    end
    entries[#entries + 1] = e
  end
  if self.playerKey then add(self.playerKey) end
  for key in pairs(self.db.members) do add(key) end
  for key in pairs(self.roster) do add(key) end

  table.sort(entries, function(a, b)
    if a.isSelf ~= b.isSelf then return a.isSelf end
    local ai, bi = a.member and 1 or 0, b.member and 1 or 0
    if ai ~= bi then return ai > bi end
    -- members with the biggest single upgrade first
    local ag, bg = a.bestGain or 0, b.bestGain or 0
    if ag ~= bg then return ag > bg end
    if a.online ~= b.online then return a.online end
    return a.key < b.key
  end)
  return entries
end

---------------------------------------------------------------------------
-- Refresh plumbing
---------------------------------------------------------------------------
function GCA:Invalidate()
  if self.refreshPending then return end
  self.refreshPending = true
  C_Timer.After(0.25, function()
    self.refreshPending = false
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
  end)
end

function GCA:PreloadItems()
  for _, cand in ipairs(self:GetCandidates()) do self:GetInfo(cand.itemID) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local DEFAULTS = { guildOnly = true, showUnlearned = false, lookahead = true, autoTarget = true, hideOffline = true, sync = true }

local events = {}

function events:ADDON_LOADED(name)
  if name ~= ADDON then return end
  GuildCraftAdvisorDB = GuildCraftAdvisorDB or {}
  local db = GuildCraftAdvisorDB
  db.members = db.members or {}
  db.known = db.known or {}
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
  self.db = db
  for spellID, r in pairs(self:RecipeTable()) do self.itemToSpell[r.item] = spellID end
  -- v0.1 stored Forever names as "First-Surname"; the roster uses "First<sep>Surname".
  if IS_FOREVER and not db.keysV2 then
    local sep, moved = SurnameSeparator(), {}
    for key, m in pairs(db.members) do
      local first, last = key:match("^([^%-]+)%-(.+)$")
      if first then moved[first .. sep .. last] = m; db.members[key] = nil end
    end
    for key, m in pairs(moved) do
      local cur = db.members[key]
      if not cur or (m.time or 0) > (cur.time or 0) then db.members[key] = m end
    end
    db.keysV2 = true
  end
end

function events:PLAYER_LOGIN()
  self.playerKey = self:UnitKey("player")
  -- per-character key: first name alone isn't unique on Forever, so include the surname.
  -- v0.1 used "First-Realm"; move that entry once.
  local realm = GetRealmName() or "?"
  self.charKey = (self.playerKey or UnitName("player") or "?") .. "-" .. realm
  local oldKey = (UnitName("player") or "?") .. "-" .. realm
  if oldKey ~= self.charKey and self.db.known[oldKey] and not self.db.known[self.charKey] then
    self.db.known[self.charKey] = self.db.known[oldKey]
    self.db.known[oldKey] = nil
  end
  self:RequestRoster()
  C_Timer.After(3, function()
    self:CaptureSelf()
    self:RefreshKnown()
    self:PreloadItems()
  end)
end

function events:PLAYER_EQUIPMENT_CHANGED()
  if self.equipTimer then return end
  self.equipTimer = true
  C_Timer.After(1, function() self.equipTimer = nil; self:CaptureSelf() end)
end

function events:PLAYER_LEVEL_UP() C_Timer.After(1, function() self:CaptureSelf() end) end

function events:INSPECT_READY(guid) self:OnInspectReady(guid) end

function events:GUILD_ROSTER_UPDATE()
  self:ReadRoster()
  self:Invalidate()
end

function events:GET_ITEM_INFO_RECEIVED() self:Invalidate() end

function events:TRADE_SKILL_SHOW() C_Timer.After(0.5, function() self:ScanTradeSkill() end) end
events.TRADE_SKILL_LIST_UPDATE = events.TRADE_SKILL_SHOW
events.TRADE_SKILL_DATA_SOURCE_CHANGED = events.TRADE_SKILL_SHOW

function events:NEW_RECIPE_LEARNED() C_Timer.After(0.5, function() self:RefreshKnown() end) end
events.LEARNED_SPELL_IN_TAB = events.NEW_RECIPE_LEARNED

function events:PLAYER_TARGET_CHANGED()
  local s = self.db and self.db.settings
  if not (s and s.autoTarget) or InCombatLockdown() then return end
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then return end
  if not self:IsGuildmate("target") or not SafeCall(CanInspect, "target") then return end
  self:QueueInspect("target", false)
end

GCA:SetScript("OnEvent", function(self, event, ...)
  local h = events[event]
  if h then h(self, ...) end
end)
for event in pairs(events) do pcall(GCA.RegisterEvent, GCA, event) end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GUILDCRAFTADVISOR1 = "/gca"
SLASH_GUILDCRAFTADVISOR2 = "/guildcraft"
SlashCmdList.GUILDCRAFTADVISOR = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "inspect" then GCA:InspectTarget()
  elseif msg == "scan" then GCA:ScanGroup()
  elseif msg == "sync" then
    if GCA.SyncStatus then GCA:SyncStatus() else Print("Sync not loaded (needs a full game restart after installing).") end
  elseif msg == "sync retry" then
    if GCA.SyncRetry then GCA:SyncRetry() end
  elseif msg == "minimap debug" then
    if GCA.MinimapDebug then GCA:MinimapDebug() end
  elseif msg == "minimap reset" then
    GCA.db.settings.minimapDragged = nil
    if GCA.MinimapAutoPlace then GCA:MinimapAutoPlace() end
    Print(string.format("Minimap button moved to the largest free gap (%.0f°).", GCA.db.settings.minimapAngle or 0))
  elseif msg == "minimap" then
    GCA.db.settings.minimapHide = not GCA.db.settings.minimapHide
    GCA:UpdateMinimapButton()
    Print("Minimap button " .. (GCA.db.settings.minimapHide and "hidden" or "shown"))
  elseif msg == "verbose" then
    GCA.verbose = not GCA.verbose
    Print("Verbose " .. (GCA.verbose and "on" or "off"))
  elseif msg == "reset" then
    wipe(GCA.db.members)
    GCA:CaptureSelf()
    Print("Stored guild gear cleared.")
  elseif msg == "help" then
    Print("/gca – toggle window | /gca inspect – inspect target | /gca scan – inspect guildies in your group | /gca reset – forget stored gear | /gca minimap – show/hide map button | /gca minimap debug – list minimap buttons | /gca minimap reset – move to a free spot |/gca sync – guild sync status | /gca verbose")
  else
    GCA.UI:Toggle()
  end
end

function GuildCraftAdvisor_OnCompartmentClick() GCA.UI:Toggle() end
