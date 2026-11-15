-- Guild Craft Advisor: records guildmates' gear when you inspect them and
-- suggests crafts (Leatherworking, Blacksmithing, Tailoring, Engineering, Enchanting) and enchants that would be upgrades.
local ADDON, ns = ...
local L = ns.L

local GCA = CreateFrame("Frame")
ns.GCA = GCA
GuildCraftAdvisor = GCA
GCA.L, GCA.G, GCA.LGet = ns.L, ns.G, ns.LGet -- locale (Locales\*.lua, plan H4)

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
-- equipLoc -> inventory slots it can go into (relics plan G7.13, weapons plan W1)
GCA.SLOTS_FOR = {
  INVTYPE_RELIC = { 18 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}

---------------------------------------------------------------------------
-- Weights (SimGear Forever data, Data/Weights.lua) and the pure scoring code (Scoring.lua)
---------------------------------------------------------------------------
local Scoring = ns.Scoring
GCA.Scoring = Scoring
GCA.MIN_PCT = 0.01      -- an upgrade needs +1 % of the equipped item's score (F7.4; a noise filter, never displayed)
GCA.MIN_POINTS = 0.05   -- no-baseline and empty-slot gains need >= 0.05 display points, so "+0.0" never shows (post-review)
GCA.SURVIVAL_DEFAULT = 0.5

function GCA:WeightData() return ns.Weights end
function GCA:ItemSets()
  if not self.itemSets then self.itemSets = Scoring.buildSets(ns.Weights and ns.Weights.itemSets) end
  return self.itemSets
end

function GCA:SurvivalShare()
  local v = self.db and self.db.settings.survival
  if type(v) ~= "number" then return self.SURVIVAL_DEFAULT end
  return math.max(0, math.min(1, v))
end

-- The composed weight set for class/spec/level: SimGear's pickSet, then the survival layer
-- (Plan.apply with the slider's share and the 50->58 fade). Returns an entry or nil, why.
--   entry = { set (composed), raw, ref, unit, unitW, key (score cache key), spec, class, level, share, t }
GCA.wsCache = {}
function GCA:WeightSetFor(class, spec, level)
  local W = ns.Weights
  if not (W and class and spec and type(level) == "number") then return nil, "no-data" end
  local share = self:SurvivalShare()
  local ck = class .. "|" .. spec .. "|" .. level .. "|" .. share
  local e = self.wsCache[ck]
  if e then return e end
  local sets = W.classes[class] and W.classes[class][spec]
  if not sets or not sets[1] then return nil, "no-weights" end
  local raw = Scoring.pickSet(sets, level)
  if not raw or next(raw.weights) == nil then return nil, "no-weights" end
  local ref = Scoring.leveling(sets, level)
  local t = Scoring.handover(level)
  local set = Scoring.apply(raw, ref, share, t)
  local rawIdx, refIdx = 0, 0
  for i, s in ipairs(sets) do
    if s == raw then rawIdx = i end
    if s == ref then refIdx = i end
  end
  local unit = raw.unit
  local unitW = unit and raw.weights[unit]
  if not (unitW and unitW > 0) then unitW = nil end
  e = {
    set = set, raw = raw, ref = ref, unit = unit, unitW = unitW, spec = spec, class = class, level = level,
    share = share, t = t,
    -- score cache key: (spec, bracket, survival share) as F8.11 (+ fade step, which changes the set too)
    key = class .. "/" .. spec .. "#" .. rawIdx .. "/" .. refIdx .. "@" .. share .. "~" .. string.format("%.3f", (ref and set ~= raw) and t or 1),
  }
  self.wsCache[ck] = e
  return e
end

local UNIT_SHORT = { AttackPower = "AP", RangedAttackPower = "RAP", SpellPower = "SP", HealingPower = "HP" }
-- "AP" = worth as much as that much Attack Power (score ÷ the set's unit-stat weight); "pts" without a unit stat
function GCA:UnitLabel(e) return e and e.unitW and (UNIT_SHORT[e.unit] or e.unit) or "pts" end
function GCA:ToPoints(e, v) return e and e.unitW and v / e.unitW or v end

-- "SimGear Forever 0.14.0 · Feral (Cat) Lv40 · simmed · leveling bonus 50%" (localized, H4; the survival
-- layer is called "leveling bonus" in the UI since H0/U4)
function GCA:SourceLine(e)
  if not e then return "" end
  local W = ns.Weights
  local src = e.raw.source
  local lv
  if src.minLevel and src.maxLevel then
    lv = src.minLevel == src.maxLevel and ("Lv" .. src.minLevel) or ("Lv" .. src.minLevel .. "-" .. src.maxLevel)
    if e.level < src.minLevel or e.level > src.maxLevel then lv = string.format(L.SRCL_NEAREST, lv, e.level) end
  else
    lv = L.SRCL_ALL_LEVELS
  end
  local kind = src.kind == "sim" and L.SRCL_SIMMED or (src.kind == "measured" and L.SRCL_MEASURED or src.kind)
  if Scoring.isPlaceholder(e.raw) then kind = L.SRCL_ROUGH end
  local parts = { "SimGear Forever " .. (W and W.meta.version or "?"), self:SpecName(e.class, e.spec) .. " " .. lv, kind }
  local plan = e.set.source.plan
  if not e.ref then
    parts[#parts + 1] = L.SRCL_NO_BONUS
  elseif plan and e.t < 1 then
    local s = string.format(L.SRCL_BONUS, math.floor(e.share * 100 + 0.5))
    if e.t > 0 then s = s .. string.format(L.SRCL_FADING, math.floor((1 - e.t) * 100 + 0.5)) end
    parts[#parts + 1] = s
  elseif e.t >= 1 then
    parts[#parts + 1] = L.SRCL_FADED
  end
  return table.concat(parts, " · ")
end

-- Per-stat rows { key, amount, weight, value } in display units, biggest |value| first.
function GCA:Breakdown(stats, e)
  local rows = {}
  if not (stats and e) then return rows end
  for k, amount in pairs(stats) do
    local w = Scoring.weightOf(stats, k, e.set)
    if w ~= 0 then
      rows[#rows + 1] = { key = k, amount = amount, weight = self:ToPoints(e, w), value = self:ToPoints(e, amount * w) }
    end
  end
  table.sort(rows, function(a, b)
    if math.abs(a.value - b.value) > 1e-9 then return math.abs(a.value) > math.abs(b.value) end
    return a.key < b.key
  end)
  return rows
end

-- Everything that changes scores: drop cached weight sets, item scores and suggestions.
function GCA:InvalidateScores()
  wipe(self.wsCache)
  for _, info in pairs(self.infoCache or {}) do wipe(info.scores) end
  self.sugCache = {}
  if self.Invalidate then self:Invalidate() end
end

---------------------------------------------------------------------------
-- Item info cache (keyed by itemID or full link)
---------------------------------------------------------------------------
GCA.infoCache = {}

-- Items that never load (post-review): requests per itemID are LOAD_RETRY s apart; after LOAD_TRIES requests
-- or LOAD_TIMEOUT s since the first miss we give up on the item for this session ("failed"). A failed
-- equipped item makes its slot unknown (not empty); a failed craft is skipped. Nothing is persisted.
GCA.LOAD_TRIES, GCA.LOAD_RETRY, GCA.LOAD_TIMEOUT = 3, 2, 10
GCA.loadState = {} -- itemID -> { first, last, tries, failed }

-- Returns true when we gave up on the item.
function GCA:NoteMissingItem(id)
  if type(id) ~= "number" then return true end
  local now = GetTime()
  local st = self.loadState[id]
  if not st then st = { first = now, tries = 0 }; self.loadState[id] = st end
  if st.failed then return true end
  if not st.last or now - st.last >= self.LOAD_RETRY then
    if st.tries >= self.LOAD_TRIES then st.failed = true return true end
    st.tries, st.last = st.tries + 1, now
    if ItemAPI.Request then SafeCall(ItemAPI.Request, id) end
  end
  if now - st.first >= self.LOAD_TIMEOUT then st.failed = true end
  return st.failed == true
end

-- One refresh LOAD_RETRY s later while something is still loading (drives the retries above; it ends when
-- every item has loaded or failed, so "loading" can't keep the window refreshing forever).
function GCA:ScheduleLoadRetry()
  if self.loadRetryPending then return end
  self.loadRetryPending = true
  C_Timer.After(self.LOAD_RETRY + 0.1, function()
    self.loadRetryPending = false
    self:Invalidate()
  end)
end

-- Returns info, or nil plus true when the item failed to load (see above).
function GCA:GetInfo(item)
  if not item then return end
  local c = self.infoCache[item]
  if c then return c end
  local name, link, quality, ilvl, minLevel, _, _, _, equipLoc, icon, _, classID, subClassID, bindType =
    SafeCall(ItemAPI.Info, item)
  if not name or IsSecret(name) then
    return nil, self:NoteMissingItem(ItemIDFrom(item))
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
  c.cstats, c.unknownStats = Scoring.normalize(c.stats)
  Scoring.addWeaponDps(c.cstats, equipLoc)
  if classID == 2 then -- W3: speed from the tooltip; dagger = weapon subclass 15
    c.speed = self:WeaponSpeed(c.itemID, c.link)
    c.dagger = subClassID == 15 or nil
  end
  self.infoCache[item] = c
  if c.itemID then self.loadState[c.itemID] = nil end
  return c
end

-- An item's score for a weight-set entry (cached on the item per entry key). Weapons include their speed
-- (SimGear speedValue, plan W3); everything else is stats x weights.
function GCA:ScoreItem(info)
  return { itemID = info.itemID, equipLoc = info.equipLoc, stats = info.cstats, speed = info.speed, dagger = info.dagger, info = info }
end
function GCA:Score(info, e)
  local s = info.scores[e.key]
  if not s then
    s = Scoring.itemValue(self:ScoreItem(info), e.set)
    info.scores[e.key] = s
  end
  return s
end

-- A weapon's speed in seconds from its tooltip (SimGear Stats.weaponSpeedFromLines: the damage line's right text,
-- label = the client's SPEED, deDE "Tempo 2,60"), or nil (then it is scored on DPS alone: factor 1). Cached per
-- item ID; a miss is not cached (the tooltip data may still be loading).
GCA.speedCache = {}
function GCA:WeaponSpeed(itemID, link)
  if itemID and self.speedCache[itemID] then return self.speedCache[itemID] end
  local TI = C_TooltipInfo
  if type(TI) ~= "table" then return nil end
  local data
  if itemID and TI.GetItemByID then data = SafeCall(TI.GetItemByID, itemID) end
  if (type(data) ~= "table" or type(data.lines) ~= "table") and type(link) == "string" and TI.GetHyperlink then
    data = SafeCall(TI.GetHyperlink, link)
  end
  if type(data) ~= "table" or type(data.lines) ~= "table" or IsSecret(data.lines) then return nil end
  local lines = {}
  for i, line in ipairs(data.lines) do
    local r = type(line) == "table" and line.rightText
    lines[i] = { rightText = (type(r) == "string" and not IsSecret(r)) and r or nil }
  end
  local label = SPEED
  if type(label) ~= "string" or IsSecret(label) then label = nil end
  local speed = Scoring.weaponSpeedFromLines(lines, label)
  if speed and itemID then self.speedCache[itemID] = speed end
  return speed
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
  if IsSecret(n) or n == 0 then self.rosterCount = 0 return end -- keeps the last roster; no pruning on it (K0/L4)
  self.rosterLoaded = true
  wipe(self.roster)
  local read, offline = 0, 0
  for i = 1, n do
    local name, _, _, level, _, _, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      self.roster[key] = { level = level, class = classFile, online = online and true or false }
      read = read + 1
      if not online then offline = offline + 1 end
    end
  end
  self.rosterCount, self.rosterRead, self.rosterOffline = n, read, offline
end

---------------------------------------------------------------------------
-- K0/L4: prune SavedVariables of characters that left the guild. Conservative: once per session, at least
-- PRUNE_DELAY s after login, only on a complete roster read (every index gave a name) of at least
-- PRUNE_MIN_ROSTER members, with offline members in it (not an online-only list), not on the first session
-- that records a roster size and not less than half of last session's count; never your own characters
-- (every character key this account has stored); only data older than PRUNE_AGE (newest of m.time, m.ts,
-- spec ts, crafted marks). Touches db.members, db.specs and the crafted marks of every own character.
---------------------------------------------------------------------------
GCA.PRUNE_DELAY, GCA.PRUNE_MIN_ROSTER, GCA.PRUNE_AGE = 60, 5, 30 * 86400

function GCA:OwnCharacterKeys()
  local own, realm = {}, SafeCall(GetRealmName)
  if self.playerKey then own[self.playerKey] = true end
  local db = self.db
  for _, t in ipairs({ db.known or {}, db.sync or {}, db.profSel or {}, db.crafted or {} }) do
    for charKey in pairs(t) do
      if type(charKey) == "string" then
        own[charKey] = true
        if type(realm) == "string" and not IsSecret(realm) and charKey:sub(-(#realm + 1)) == "-" .. realm then
          own[charKey:sub(1, -(#realm + 2))] = true
        end
        local base = charKey:match("^(.+)%-[^%-]+$")
        if base then own[base] = true end
      end
    end
  end
  return own
end

function GCA:PruneStale()
  if self.pruneDone or not (self.db and IsInGuild()) then return end
  if not (self.loginTime and GetTime() - self.loginTime >= self.PRUNE_DELAY) then return end
  local n, read = self.rosterCount, self.rosterRead
  if not (self.rosterLoaded and type(n) == "number" and n > 0 and read == n) then return end
  local db = self.db
  local last = db.rosterLast
  db.rosterLast = n
  if type(last) ~= "number" or n < self.PRUNE_MIN_ROSTER or n < last / 2 or (self.rosterOffline or 0) == 0 then
    self.pruneDone = true -- suspicious: not this session
    return
  end
  self.pruneDone = true
  local own, cutoff = self:OwnCharacterKeys(), time() - self.PRUNE_AGE
  local seen, cand = {}, {}
  local function note(key, t)
    if type(key) ~= "string" then return end
    cand[key] = true
    if type(t) == "number" and t > (seen[key] or 0) then seen[key] = t end
  end
  for key, m in pairs(db.members) do note(key, m.time); note(key, m.ts) end
  for key, r in pairs(db.specs or {}) do note(key, type(r) == "table" and r.ts) end
  for _, byMember in pairs(db.crafted or {}) do
    if type(byMember) == "table" then
      for key, profs in pairs(byMember) do
        note(key, nil)
        if type(profs) == "table" then
          for _, marks in pairs(profs) do
            if type(marks) == "table" then for _, mk in pairs(marks) do note(key, type(mk) == "table" and mk.t) end end
          end
        end
      end
    end
  end
  local removed = 0
  for key in pairs(cand) do
    -- no timestamp at all = unknown age: kept
    if not self.roster[key] and not own[key] and seen[key] and seen[key] < cutoff then
      db.members[key] = nil
      if db.specs then db.specs[key] = nil end
      for _, byMember in pairs(db.crafted or {}) do if type(byMember) == "table" then byMember[key] = nil end end
      removed = removed + 1
    end
  end
  if removed > 0 then
    self.sugCache = {}
    Print(string.format(L.MSG_PRUNED, removed))
    self:Invalidate()
  end
  return removed
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
  self:ClearWornCrafted(key, m.items) -- H5.1: a "crafted" mark ends once a record shows it worn
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
  if changed and self.ownSpec and self.playerClass == "SHAMAN" then self:QueueOwnSpecRefresh() end
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
  if InspectFrame and InspectFrame.unit and not IsSecret(InspectFrame.unit) then
    local ig = SafeCall(UnitGUID, InspectFrame.unit)
    if ig and not IsSecret(ig) and ig == guid then return InspectFrame.unit end
  end
  for _, u in ipairs(UNIT_TOKENS) do
    local g = SafeCall(UnitGUID, u)
    if g and not IsSecret(g) and g == guid then return u end
  end
end

-- INSPECT_READY fires both for our own requests and when you inspect someone
-- with the normal UI. Item links can arrive in pieces, so read a few times.
-- Inspect generation: bumped on every INSPECT_READY and every NotifyInspect (ours or the default UI's), so
-- delayed talent reads of an older inspect can tell that the client's inspect data may be someone else's now.
GCA.inspectGen = 0
function GCA:OnNotifyInspect(unit)
  self.inspectGen = self.inspectGen + 1
  local g = unit and SafeCall(UnitGUID, unit)
  self.inspectGUID = (g and not IsSecret(g)) and g or nil
end
if hooksecurefunc then pcall(hooksecurefunc, "NotifyInspect", function(unit) GCA:OnNotifyInspect(unit) end) end

function GCA:OnInspectReady(guid)
  self.inspectGen = self.inspectGen + 1
  self.inspectGUID = (guid and not IsSecret(guid)) and guid or nil
  local gen = self.inspectGen
  -- K0/M2: our queued inspect got its answer; the queue now waits for the final read below (InspectDone)
  if self.inspecting and self.inspecting == guid then self.inspectAnswered = guid end
  local unit = self:UnitFromGUID(guid)
  if unit and SafeCall(UnitIsPlayer, unit) and not SafeCall(UnitIsUnit, unit, "player")
     and (not self.db.settings.guildOnly or self:IsGuildmate(unit)) then
    -- Who it is is fixed on the first pass; later passes only add items. Only the final pass
    -- stores, and it stores what was collected even if the unit token is gone by then.
    local fresh = {}
    local key = self:UnitKey(unit)
    local class, level = UnitClassLevel(unit)
    if not key then self:InspectDone(guid) return end
    if self.TryInspectTalents then SafeCall(self.TryInspectTalents, self, key, class, level, guid, gen) end
    local function read()
      local u = self:UnitFromGUID(guid)
      if u then self:ReadUnitItems(u, fresh) end
    end
    read()
    C_Timer.After(0.5, read)
    C_Timer.After(GCA.INSPECT_FINAL_READ, function()
      SafeCall(function()
        read()
        if not next(fresh) then return end
        local changed = self:StoreRecord(key, class, level, fresh, "inspect")
        if changed and self.RelayInspect then SafeCall(self.RelayInspect, self, key) end
        if self.verbose or self.announce == guid then
          self.announce = nil
          Print(string.format(L.MSG_RECORDED, key))
          if self.UI then self.UI.selected = key end
        end
        self:Invalidate()
      end)
      -- K0/M2: only now may the next NotifyInspect go out (it would replace this unit's inspect data)
      self:InspectDone(guid)
    end)
    return
  end
  self:InspectDone(guid)
end

---------------------------------------------------------------------------
-- Inspect queue (for "Inspect target", "Scan group" and auto-inspect)
---------------------------------------------------------------------------
GCA.queue, GCA.lastInspect = {}, {}
-- K0/M2 timings: final storing read after INSPECT_READY; no answer within NO_ANSWER s -> next; HARD_LIMIT s
-- after NotifyInspect the queue moves on whatever happened (a lost timer or an error can't hang it).
GCA.INSPECT_FINAL_READ, GCA.INSPECT_NO_ANSWER, GCA.INSPECT_HARD_LIMIT, GCA.INSPECT_GAP = 1.5, 3, 8, 1
GCA.inspectToken = 0

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
      self.inspectAnswered = nil
      self.inspectToken = self.inspectToken + 1
      local token = self.inspectToken
      self.lastInspect[guid] = GetTime()
      SafeCall(NotifyInspect, unit)
      -- no answer (out of range?): move on; an answered inspect waits for its final read instead
      C_Timer.After(self.INSPECT_NO_ANSWER, function()
        if self.inspectToken == token and self.inspecting == guid and self.inspectAnswered ~= guid then
          self.inspecting = nil
          self:ProcessQueue()
        end
      end)
      -- safety net: never stuck on one inspect
      C_Timer.After(self.INSPECT_HARD_LIMIT, function()
        if self.inspectToken == token and self.inspecting == guid then
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
    self.inspectAnswered = nil
    C_Timer.After(self.INSPECT_GAP, function() self:ProcessQueue() end)
  end
end

function GCA:InspectTarget()
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then
    Print(L.MSG_TARGET_FIRST) return
  end
  if self.db.settings.guildOnly and not self:IsGuildmate("target") then
    Print(L.MSG_NOT_GUILD) return
  end
  if not SafeCall(CanInspect, "target") then Print(L.MSG_CANT_INSPECT) return end
  self.announce = SafeCall(UnitGUID, "target")
  self:QueueInspect("target", true)
  Print(string.format(L.MSG_INSPECTING, self:UnitKey("target") or "target"))
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
  Print(n > 0 and string.format(L.MSG_QUEUED, n) or L.MSG_NONE_IN_GROUP)
end

---------------------------------------------------------------------------
-- K5: automatic gear reading (replaces the "Inspect target" / "Scan group" buttons; the slash commands stay).
-- Group members (GROUP_ROSTER_UPDATE, debounced) and guildies under the mouse (UPDATE_MOUSEOVER_UNIT, low
-- priority: only while the queue is idle, at most one per AUTO_MOUSEOVER_GAP s) go through the same inspect
-- queue (K0/M2 timing, one at a time). Rules for every automatic read (AutoInspectCheck):
--   setting "autoInspect" on; not in combat (a group scan asked for in combat runs at PLAYER_REGEN_ENABLED);
--   the default inspect window is not open (never take the user's inspect data away); a player, not you, a
--   guildmate; CanInspect true; not out of range (CheckInteractDistance(unit, 1), pcall'd as Overlord
--   RankProof.lua:1442-1444 does on Forever: only a plain `false` counts, an error / secret / nil doesn't);
--   no gear record younger than AUTO_FRESH s (db.members[key].time = when we last stored or received it);
--   not tried within AUTO_RETRY s (lastInspect, also set for attempts that got no answer); not queued already.
---------------------------------------------------------------------------
GCA.AUTO_FRESH, GCA.AUTO_RETRY, GCA.AUTO_GROUP_DELAY, GCA.AUTO_MOUSEOVER_GAP = 1800, 600, 2, 10

function GCA:AutoInspectCheck(unit)
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return false, "off" end
  if InCombatLockdown() then return false, "combat" end
  if InspectFrame and SafeCall(InspectFrame.IsShown, InspectFrame) then return false, "inspectframe" end
  if not SafeCall(UnitIsPlayer, unit) or SafeCall(UnitIsUnit, unit, "player") then return false, "unit" end
  if not self:IsGuildmate(unit) then return false, "guild" end
  local can = SafeCall(CanInspect, unit)
  if not can or IsSecret(can) then return false, "caninspect" end
  if type(CheckInteractDistance) == "function" then
    local ok, near = pcall(CheckInteractDistance, unit, 1)
    if ok and not IsSecret(near) and near == false then return false, "range" end
  end
  local guid = SafeCall(UnitGUID, unit)
  if not guid or IsSecret(guid) then return false, "unit" end
  local key = self:UnitKey(unit)
  local m = key and self.db.members[key]
  if m and type(m.time) == "number" and time() - m.time < self.AUTO_FRESH then return false, "fresh" end
  local last = self.lastInspect[guid]
  if last and GetTime() - last < self.AUTO_RETRY then return false, "recent" end
  if self.inspecting == guid then return false, "queued" end
  for _, g in ipairs(self.queue) do if g == guid then return false, "queued" end end
  return true, guid
end

-- Party/raid members that pass the rules go into the queue. In combat: remembered and run after combat.
function GCA:AutoScanGroup()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return 0 end
  if InCombatLockdown() then self.autoGroupPending = true; return 0 end
  self.autoGroupPending = nil
  local prefix, count = "party", SafeCall(GetNumSubgroupMembers) or 0
  if SafeCall(IsInRaid) then prefix, count = "raid", SafeCall(GetNumGroupMembers) or 0 end
  if IsSecret(count) or type(count) ~= "number" then return 0 end
  local n = 0
  for i = 1, count do
    local u = prefix .. i
    if self:AutoInspectCheck(u) and self:QueueInspect(u, true) then n = n + 1 end
  end
  if n > 0 and self.verbose then Print(string.format(L.MSG_AUTO_QUEUED, n)) end
  return n
end

function GCA:AutoMouseover()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return false end
  if self.inspecting or #self.queue > 0 then return false end -- low priority: only while idle
  local t = GetTime()
  if self.lastAutoMouseover and t - self.lastAutoMouseover < self.AUTO_MOUSEOVER_GAP then return false end
  if not self:AutoInspectCheck("mouseover") then return false end
  self.lastAutoMouseover = t
  return self:QueueInspect("mouseover", true)
end

---------------------------------------------------------------------------
-- Recipes you know
---------------------------------------------------------------------------
-- Professions (plan G0/G3/G7). Order = default choice order and the order in the selector.
GCA.PROFESSIONS = {
  { key = "Leatherworking", skillLine = 165, icon = "Interface\\Icons\\Trade_LeatherWorking", crafter = "a leatherworker", spec = true },
  { key = "Blacksmithing", skillLine = 164, icon = "Interface\\Icons\\Trade_BlackSmithing", crafter = "a blacksmith", spec = true },
  { key = "Tailoring", skillLine = 197, icon = "Interface\\Icons\\Trade_Tailoring", crafter = "a tailor" },
  { key = "Engineering", skillLine = 202, icon = "Interface\\Icons\\Trade_Engineering", crafter = "an engineer", spec = true },
  { key = "Enchanting", skillLine = 333, icon = "Interface\\Icons\\Trade_Engraving", crafter = "an enchanter" },
}
GCA.PROF_BY_KEY, GCA.PROF_BY_LINE = {}, {}
for _, p in ipairs(GCA.PROFESSIONS) do GCA.PROF_BY_KEY[p.key], GCA.PROF_BY_LINE[p.skillLine] = p, p end
GCA.DEFAULT_PROFESSION = "Leatherworking"
-- GetProfessions() may return nothing for a moment after login: an empty answer is trusted only this long after login
GCA.PROF_TRUST_DELAY = 10

local EMPTY = {}
-- Item recipes of a profession: [spellID] = { item, skill, src, name, r, faction }.
function GCA:RecipeTable(prof)
  prof = prof or self:SelectedProfession()
  return ns.Recipes and ns.Recipes[prof] or EMPTY
end

-- Enchant rows (Data/Enchants.lua) and the lookups built from them (G7.7: separate table, dedupe by enchant ID).
function GCA:EnchantData()
  if self.enchantData then return self.enchantData end
  local rows = ns.Enchants and ns.Enchants.rows or EMPTY
  local d = { rows = rows, bySpell = {}, byEnchant = {}, bySlot = {} }
  for _, r in ipairs(rows) do
    d.bySpell[r.spell] = r
    d.byEnchant[r.enchant] = d.byEnchant[r.enchant] or r
    d.bySlot[r.slot] = d.bySlot[r.slot] or {}
    table.insert(d.bySlot[r.slot], r)
  end
  self.enchantData = d
  return d
end

-- Every spell of a profession that can be "known": item recipes, plus the enchants for Enchanting.
function GCA:KnowableSpells(prof)
  local out = {}
  for spellID in pairs(self:RecipeTable(prof)) do out[spellID] = true end
  if prof == "Enchanting" then
    for spellID in pairs(self:EnchantData().bySpell) do out[spellID] = true end
  end
  return out
end

-- itemID -> recipe spell of one profession (G7.5: spell and item IDs repeat across professions, so per profession).
GCA.itemToSpellOf = {}
function GCA:ItemToSpell(prof)
  local m = self.itemToSpellOf[prof]
  if not m then
    m = {}
    for spellID, r in pairs(self:RecipeTable(prof)) do m[r.item] = spellID end
    self.itemToSpellOf[prof] = m
  end
  return m
end

---------------------------------------------------------------------------
-- Your professions (GetProfessions) and the selected one
---------------------------------------------------------------------------
-- Returns own, trusted. own = { [key] = { rank, maxRank, name } }. trusted = the answer can be used to
-- clear known recipes / mark "browse" (the API answered with at least one profession, or long enough after login).
function GCA:ReadProfessions()
  local own, trusted = {}, false
  if not (GetProfessions and GetProfessionInfo) then self.ownProfs, self.profsTrusted = own, false return own, false end
  local list = { SafeCall(GetProfessions) }
  local any = false
  for i = 1, 6 do
    local idx = list[i]
    if idx ~= nil and not IsSecret(idx) then
      any = true
      local name, _, rank, maxRank, _, _, skillLine = SafeCall(GetProfessionInfo, idx)
      local p = type(skillLine) == "number" and not IsSecret(skillLine) and self.PROF_BY_LINE[skillLine]
      if p then
        own[p.key] = { rank = (not IsSecret(rank)) and rank or nil, maxRank = (not IsSecret(maxRank)) and maxRank or nil,
          name = (type(name) == "string" and not IsSecret(name)) and name or nil }
      end
    end
  end
  trusted = any or (self.loginTime ~= nil and GetTime() - self.loginTime >= self.PROF_TRUST_DELAY)
  self.ownProfs, self.profsTrusted = own, trusted
  return own, trusted
end

function GCA:OwnProfessions()
  if not self.ownProfs then self:ReadProfessions() end
  return self.ownProfs, self.profsTrusted
end

-- Browse = a profession you don't have (G6.1/G7.11). Only when GetProfessions gave a trusted answer;
-- without one (API missing / not loaded yet) every profession is treated as yours.
function GCA:IsBrowse(prof)
  prof = prof or self:SelectedProfession()
  local own, trusted = self:OwnProfessions()
  return trusted and not own[prof] or false
end

-- The selected profession (saved per character), else your first gear profession, else Leatherworking.
function GCA:SelectedProfession()
  local sel = self.db and self.db.profSel and self.charKey and self.db.profSel[self.charKey]
  if sel and self.PROF_BY_KEY[sel] then return sel end
  local own = self:OwnProfessions()
  for _, p in ipairs(self.PROFESSIONS) do if own[p.key] then return p.key end end
  return self.DEFAULT_PROFESSION
end

function GCA:SelectProfession(prof)
  if not self.PROF_BY_KEY[prof] or not (self.db and self.charKey) then return end
  self.db.profSel = self.db.profSel or {}
  self.db.profSel[self.charKey] = prof
  self:OnProfessionChanged()
end

-- Per-profession state that follows the selection: itemToSpell, knownCount; then refresh.
function GCA:OnProfessionChanged()
  local prof = self:SelectedProfession()
  self.itemToSpell = self:ItemToSpell(prof)
  self.knownCount = self.knownCounts[prof] or 0
  self:PreloadItems()
  self:Invalidate()
end

---------------------------------------------------------------------------
-- Recipes you know (per profession, G7.5/G7.6)
---------------------------------------------------------------------------
GCA.knownNow, GCA.knownCounts, GCA.itemToSpell = {}, {}, {}

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
GCA.SpellKnown = SpellKnown

-- db.known[charKey] = { [profession] = { [spellID] = true } }. Older builds stored a flat { [spellID] = true }
-- (Leatherworking only): moved once.
function GCA:KnownStore()
  local store = self.db.known[self.charKey]
  if type(store) ~= "table" then store = {}; self.db.known[self.charKey] = store end
  local flat
  for k in pairs(store) do if type(k) == "number" then flat = true break end end
  if flat then
    local lw = type(store.Leatherworking) == "table" and store.Leatherworking or {}
    for k, v in pairs(store) do
      if type(k) == "number" then lw[k] = v; store[k] = nil end
    end
    store.Leatherworking = lw
  end
  return store
end

local function SameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

-- Re-reads which recipes you know for every profession. A profession that GetProfessions (trusted answer)
-- no longer lists loses its saved IDs (G7.6). Returns true when any known set changed.
function GCA:RefreshKnown()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local changed = false
  for _, p in ipairs(self.PROFESSIONS) do
    local now, n = {}, 0
    if trusted and not own[p.key] then
      store[p.key] = nil
    else
      local saved = store[p.key] or {}
      store[p.key] = saved
      local knowable = self:KnowableSpells(p.key)
      -- once the profession window answered for this profession, its list is the truth: spell-API hits that
      -- it didn't confirm are not added (they caused wrong "known" marks); new recipes come via NEW_RECIPE_LEARNED
      local auth = self.db.knownAuth and self.db.knownAuth[self.charKey] and self.db.knownAuth[self.charKey][p.key]
      for spellID in pairs(knowable) do
        if saved[spellID] or (not auth and SpellKnown(spellID)) then
          now[spellID] = true
          saved[spellID] = true
          n = n + 1
        end
      end
      -- saved IDs that no longer exist in our data stay saved but don't count
    end
    if not SameSet(now, self.knownNow[p.key] or EMPTY) then changed = true end
    self.knownNow[p.key], self.knownCounts[p.key] = now, n
  end
  self.knownCount = self.knownCounts[self:SelectedProfession()] or 0
  self.itemToSpell = self:ItemToSpell(self:SelectedProfession())
  -- knownGen is part of the suggestion cache key: bump it only when a set really changed (post-review F9.5)
  if changed then
    self.knownGen = (self.knownGen or 0) + 1
    self:Invalidate()
  end
  return changed
end

-- Known in the given (default: selected) profession. Browse mode never counts anything as known (G6.1).
function GCA:IsKnown(spellID, prof)
  prof = prof or self:SelectedProfession()
  local set = self.knownNow[prof]
  return set ~= nil and set[spellID] == true
end

-- Extra safety net: read the open profession window directly.
function GCA:ScanTradeSkill()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local profs = {}
  for _, p in ipairs(self.PROFESSIONS) do
    if not trusted or own[p.key] then profs[#profs + 1] = p.key end
  end
  local function mark(prof, spellID)
    store[prof] = store[prof] or {}
    store[prof][spellID] = true
  end
  local api = C_TradeSkillUI
  local modernAnswered = false
  if api and api.GetAllRecipeIDs and api.GetRecipeInfo then
    local ids = SafeCall(api.GetAllRecipeIDs)
    if type(ids) == "table" then
      local knowable, seen, learned = {}, {}, {}
      for _, prof in ipairs(profs) do knowable[prof] = self:KnowableSpells(prof); seen[prof] = 0; learned[prof] = {} end
      for _, id in ipairs(ids) do
        local info
        for _, prof in ipairs(profs) do
          if knowable[prof][id] then
            info = info or SafeCall(api.GetRecipeInfo, id)
            if type(info) == "table" and info.learned ~= nil and not IsSecret(info.learned) then
              seen[prof] = seen[prof] + 1
              if info.learned == true then learned[prof][id] = true end
            end
          end
        end
      end
      -- The open profession window lists that profession's recipes, learned or not: when it answered for
      -- enough of them, it is the truth for that profession and replaces the saved set (drops wrong old marks).
      for _, prof in ipairs(profs) do
        if seen[prof] >= 10 then
          modernAnswered = true
          store[prof] = learned[prof]
          self.db.knownAuth = self.db.knownAuth or {}
          self.db.knownAuth[self.charKey] = self.db.knownAuth[self.charKey] or {}
          self.db.knownAuth[self.charKey][prof] = time()
        else
          for id in pairs(learned[prof]) do mark(prof, id) end
        end
      end
    end
  end
  if GetNumTradeSkills and not modernAnswered then
    -- which profession's window is open: by its localized name, else every profession of yours
    local lineName = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
    local which = {}
    for _, prof in ipairs(profs) do
      if type(lineName) == "string" and own[prof] and own[prof].name == lineName then which = { prof } break end
    end
    if #which == 0 then which = profs end
    local n = SafeCall(GetNumTradeSkills) or 0
    if IsSecret(n) then n = 0 end
    for i = 1, n do
      local id = GetTradeSkillItemLink and ItemIDFrom(SafeCall(GetTradeSkillItemLink, i))
      -- enchants have no item; their recipe link names the spell ("enchant:13419")
      local rlink = GetTradeSkillRecipeLink and SafeCall(GetTradeSkillRecipeLink, i)
      local spell = type(rlink) == "string" and not IsSecret(rlink) and tonumber(rlink:match("enchant:(%d+)"))
      for _, prof in ipairs(which) do
        local s1 = id and self:ItemToSpell(prof)[id]
        if s1 then mark(prof, s1) end
        if spell and self:KnowableSpells(prof)[spell] then mark(prof, spell) end
      end
    end
  end
  self:RefreshKnown()
end

-- rank, maxRank, localized name of a profession you have (default: the selected one).
function GCA:GetSkill(prof)
  prof = prof or self:SelectedProfession()
  local own = self:ReadProfessions()
  local p = own[prof]
  if p and p.rank then return p.rank, p.maxRank, p.name end
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
local CLOTH_ONLY = { MAGE = true, PRIEST = true, WARLOCK = true }
-- Classes that can't hold an off-hand item (SimGear Classes.lua equip.noHoldable, G7.13)
GCA.NO_HOLDABLE = { HUNTER = true, ROGUE = true }
-- Relics (armor subclass 7 libram, 8 idol, 9 totem; SimGear Classes.lua equip.armor)
GCA.RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

-- Armor: SimGear's equip tables: plate Warrior/Paladin 40+, mail Warrior/Paladin always and Hunter/Shaman 40+,
-- shields Warrior/Paladin/Shaman, relics per class, no held off-hand for Hunter/Rogue.
-- Weapons (plan W2): the class's weapon subclasses from SimGear Classes.lua equip.weapons (Data/Weights.lua
-- classWeapons, generated); a subclass SimGear never bars (fishing poles, miscellaneous) any class can use;
-- polearms for Hunter/Warrior from 20 (client SkillRaceClassInfo, per SimGear's Warrior comment). Weapon skill
-- levels are ignored (we can't read a guildie's).
-- WearFrom returns the level from which the class can use the item (0 = any level) or nil (never).
-- K0/L1: callers pass the look-ahead level to CanWear; a piece only wearable later is then a future row.
GCA.ARMOR_PROF_LEVEL = 40
-- Weapon subclasses SimGear's Classes.barredType can bar (its WEAPON_TYPE names; golden-tested in harness_score).
GCA.BARRABLE_WEAPON = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
  [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [19] = true }
GCA.WEAPON_FROM = { [6] = { HUNTER = 20, WARRIOR = 20 } } -- polearms (plan W2)
function GCA:ClassWeapons(class)
  local cw = ns.Weights and ns.Weights.classWeapons
  return class and cw and cw[class]
end
function GCA:WearFrom(class, cand)
  local sub = cand.subClassID
  if cand.equipLoc == "INVTYPE_HOLDABLE" and class and self.NO_HOLDABLE[class] then return nil end
  if cand.classID == 2 then
    if not class or not self.BARRABLE_WEAPON[sub] then return 0 end
    local cw = self:ClassWeapons(class)
    if not cw then return 0 end -- no data: never bar (SimGear: unknown never bars)
    local ok = false
    for _, s in ipairs(cw.weapons) do if s == sub then ok = true end end
    if not ok then return nil end
    return self.WEAPON_FROM[sub] and self.WEAPON_FROM[sub][class] or 0
  end
  if cand.classID ~= 4 then return nil end
  if cand.equipLoc == "INVTYPE_CLOAK" or sub == 0 or sub == 1 then return 0 end
  if not class then return 0 end
  if sub == 2 then return not CLOTH_ONLY[class] and 0 or nil end
  if sub == 3 then
    if class == "WARRIOR" or class == "PALADIN" then return 0 end
    if class == "HUNTER" or class == "SHAMAN" then return self.ARMOR_PROF_LEVEL end
    return nil
  end
  if sub == 4 then return (class == "WARRIOR" or class == "PALADIN") and self.ARMOR_PROF_LEVEL or nil end
  if sub == 6 then return (class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN") and 0 or nil end
  if self.RELIC_CLASS[sub] then return self.RELIC_CLASS[sub] == class and 0 or nil end
  return nil
end
function GCA:CanWear(class, level, cand)
  local from = self:WearFrom(class, cand)
  return from ~= nil and (level or 0) >= from
end

-- Dual wield (plan W4 / W8.1, SimGear Spec.canDualWield + Classes dualWield/dualWieldFrom/dualWieldSets). Returns the
-- level from which this member's spec holds a weapon in each hand (0 = now), or nil. The spec must dual-wield in
-- SimGear's sims (Rogue all, Hunter all, Warrior Fury, Shaman only as ENHANCEMENT_DW = a one-hander was seen in the
-- off hand). Your own character: Dual Wield (spell 674) known wins (not known = no, whatever the level; known = yes).
-- Guildies: the class trainer level (Rogue 10, Hunter/Warrior 20); a class without one (Shaman) needs the DW spec.
GCA.DUAL_WIELD_SPELL = 674
function GCA:DualWieldFrom(class, spec, level, isSelf)
  local cw = self:ClassWeapons(class)
  if not (cw and spec) then return nil end
  local dwSpec = cw.dualWield[spec] == true
  for base, dw in pairs(cw.dualWieldSets or EMPTY) do
    if dw == spec then dwSpec = true end
    if base == spec and cw.dualWield[spec] and not cw.dualWieldFrom then dwSpec = false end -- Shaman 2H sim
  end
  if not dwSpec then return nil end
  if isSelf then
    if self.SpellKnown(self.DUAL_WIELD_SPELL) then return 0 end
    -- not known: only a later level (look-ahead) can bring it, from the trainer level
    if cw.dualWieldFrom and (level or 0) < cw.dualWieldFrom then return cw.dualWieldFrom end
    return nil
  end
  return cw.dualWieldFrom or 0
end

-- Tooltip restrictions of a crafted item (G7.13, judgement): "Requires Engineering (225)" and "Classes: Paladin".
-- Read from C_TooltipInfo where the client has it; nothing readable = no restriction (unknown never bars).
-- Returns { skill = "Engineering", classes = { [localized class name] = true } } (fields nil when absent).
-- Client format string -> anchored Lua pattern, or nil. Handles positional specifiers used by localized
-- clients ("%1$s" on deDE: the old version turned "%1" into a back-reference -> "invalid capture index").
local function FormatToPattern(fmt)
  if type(fmt) ~= "string" or IsSecret(fmt) then return end
  local f = fmt:gsub("%%(%d+)%$([sd])", "%%%2")            -- "%1$s" -> "%s"
  local out, i = {}, 1
  while i <= #f do
    local c = f:sub(i, i)
    if c == "%" then
      local n = f:sub(i + 1, i + 1)
      if n == "s" then out[#out + 1] = "(.+)"
      elseif n == "d" then out[#out + 1] = "(%d+)"
      elseif n == "%" then out[#out + 1] = "%%"
      else return end                                      -- an unknown specifier: don't guess
      i = i + 2
    else
      out[#out + 1] = c:find("[%(%)%.%[%]%*%+%-%?%^%$]") and ("%" .. c) or c
      i = i + 1
    end
  end
  local p = "^" .. table.concat(out) .. "$"
  if not pcall(string.match, "", p) then return end         -- never hand an invalid pattern to match()
  return p
end
GCA.FormatToPattern = FormatToPattern
function GCA:ItemRestrictions(itemID)
  self.restrCache = self.restrCache or {}
  local c = self.restrCache[itemID]
  if c then return c end
  local get = C_TooltipInfo and C_TooltipInfo.GetItemByID
  local data = get and SafeCall(get, itemID)
  if type(data) ~= "table" or type(data.lines) ~= "table" or IsSecret(data.lines) then return EMPTY end
  c = {}
  local reqSkill = FormatToPattern(ITEM_REQ_SKILL or "Requires %s")
  local classes = FormatToPattern(ITEM_CLASSES_ALLOWED or "Classes: %s")
  for _, line in ipairs(data.lines) do
    local t = type(line) == "table" and line.leftText
    if type(t) == "string" and not IsSecret(t) then
      local what = reqSkill and SafeCall(string.match, t, reqSkill)
      -- a skill requirement has a rank in brackets ("Engineering (225)"); "Requires Level 40" has none
      local skill = what and what:match("^(.-) %(%d+%)$")
      if skill then c.skill = skill end
      local list = classes and SafeCall(string.match, t, classes)
      if list then
        c.classes = {}
        for name in list:gmatch("[^,]+") do c.classes[(name:gsub("^%s+", ""):gsub("%s+$", "")):lower()] = true end
      end
    end
  end
  self.restrCache[itemID] = c
  return c
end

-- false when the tooltip bars `class` (class list) or the wearer can't have the required skill.
function GCA:PassesRestrictions(itemID, class, isSelf)
  local r = self:ItemRestrictions(itemID)
  if r.classes and class then
    -- localized names (male/female), and the token itself where no localized table exists (case-insensitive)
    local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
    if not ((m and r.classes[m:lower()]) or (f and r.classes[f:lower()]) or r.classes[class:lower()]) then return false end
  end
  if r.skill then
    -- we don't know a guildie's professions: only you, and only for a skill you have
    if not isSelf then return false end
    local ok = false
    for _, p in pairs(self:OwnProfessions()) do if p.name == r.skill then ok = true end end
    for key in pairs(self:OwnProfessions()) do if key == r.skill then ok = true end end
    return ok
  end
  return true
end

-- Equippable crafted items of a profession (needs only the client's static item DB), weapons included (W1).
function GCA:GetCandidates(prof)
  prof = prof or self:SelectedProfession()
  self.candidates = self.candidates or {}
  if self.candidates[prof] then return self.candidates[prof] end
  local list, missing = {}, false
  for spellID, r in pairs(self:RecipeTable(prof)) do
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
  if not missing then self.candidates[prof] = list end
  return list
end

-- Short text for set-bonus stats: "+2% hit", "+20 spell power" (stat words localized, H4 / review M-1).
local BONUS_KEYS = { AttackPower = "BONUS_ATTACKPOWER", RangedAttackPower = "BONUS_RANGEDATTACKPOWER",
  SpellPower = "BONUS_SPELLPOWER", HealingPower = "BONUS_HEALINGPOWER", Stamina = "BONUS_STAMINA",
  Strength = "BONUS_STRENGTH", Agility = "BONUS_AGILITY", Intellect = "BONUS_INTELLECT", Spirit = "BONUS_SPIRIT",
  Armor = "BONUS_ARMOR", Defense = "BONUS_DEFENSE", BlockValue = "BONUS_BLOCKVALUE" }
local PCT_KEYS = { MeleeHit = "BONUS_MELEEHIT", SpellHit = "BONUS_SPELLHIT", MeleeCrit = "BONUS_MELEECRIT",
  SpellCrit = "BONUS_SPELLCRIT", Dodge = "BONUS_DODGE", Parry = "BONUS_PARRY", Block = "BONUS_BLOCK" }
function GCA:BonusText(stats)
  local parts, used = {}, {}
  for _, pair in ipairs({ { "MeleeHit", "SpellHit", "BONUS_HIT" }, { "MeleeCrit", "SpellCrit", "BONUS_CRIT" } }) do
    local a, b = stats[pair[1]], stats[pair[2]]
    if a and b and a == b then
      parts[#parts + 1] = string.format("+%g%% %s", a, L[pair[3]]); used[pair[1]], used[pair[2]] = true, true
    end
  end
  local keys = {}
  for k in pairs(stats) do if not used[k] then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if PCT_KEYS[k] then
      parts[#parts + 1] = string.format("+%g%% %s", stats[k], L[PCT_KEYS[k]])
    else
      parts[#parts + 1] = string.format("+%g %s", stats[k], BONUS_KEYS[k] and L[BONUS_KEYS[k]] or k)
    end
  end
  return table.concat(parts, ", ")
end

-- "Devilsaur Armor: +2% hit with Devilsaur Gauntlets": the next bonus of the candidate's set not reached yet (F8.14).
-- Whole localized sentences (HINT_ONE / HINT_MORE), so German can use its own word order (review M-1).
function GCA:SetHint(itemID, afterIDs, prof)
  local sets = self:ItemSets()
  local setID = sets.ofItem[itemID]
  local set = setID and sets.bySet[setID]
  if not set then return end
  local have = Scoring.piecesOf(afterIDs, sets)[setID] or 0
  local wearing = {}
  for _, id in ipairs(afterIDs) do wearing[id] = true end
  for _, bonus in ipairs(set.bonuses or {}) do
    if bonus.n > have then
      local missing = {}
      for _, id in ipairs(set.items) do
        if not wearing[id] then
          local info = self:GetInfo(id)
          local name = info and info.name or string.format(L.ITEM_FALLBACK, id)
          prof = prof or self:SelectedProfession()
          local spell = self:ItemToSpell(prof)[id]
          if spell and not self:IsBrowse(prof) and self:IsKnown(spell, prof) then name = string.format(L.HINT_YOU_CRAFT, name) end
          missing[#missing + 1] = name
        end
      end
      local need = bonus.n - have
      local what = next(bonus.stats or {}) and self:BonusText(bonus.stats) or L.HINT_UNSCORED
      if need == 1 then return string.format(L.HINT_ONE, set.name, what, table.concat(missing, L.HINT_OR)) end
      return string.format(L.HINT_MORE, set.name, what, need, table.concat(missing, ", "))
    end
  end
end

-- Order of suggestions (user 2026-11-14: no more %, sorted by the gain itself): tier 1 = real gains (upgrades,
-- empty-slot fills, no-baseline upgrades) by points (AP/SP/RAP-equivalents), tier TIER_PARTNER = one-handers /
-- off hands next to a worn two-hander (scored alone, not a real gain) by points.
-- The member list ranks members by their best suggestion with the same order.
local function Better(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if math.abs(a.points - b.points) > 1e-9 then return a.points > b.points end
  if a.known ~= b.known then return a.known end
  if (a.kind == "enchant") ~= (b.kind == "enchant") then return b.kind == "enchant" end -- items before enchants
  return a.slot < b.slot
end
GCA.BetterSuggestion = Better
-- W8.2: tier of one-handers / off hands next to a worn two-hander (scored alone): after the real gains.
GCA.TIER_PARTNER = 2
-- Equip locations compared as the main hand + off hand pair (plan W4).
GCA.HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

-- The worn main hand + off hand as one "item" for a two-hander's comparison (W4: it replaces both): name "A + B",
-- canonical stats summed with the off hand counted as it weighs there (SimGear inOffHand).
function GCA:PairInfo(mh, oh)
  local stats = {}
  for k, v in pairs(mh.cstats or EMPTY) do stats[k] = v end
  local off = Scoring.inOffHand({ stats = oh.cstats or EMPTY })
  for k, v in pairs(off.stats or EMPTY) do stats[k] = (stats[k] or 0) + v end
  return { name = (mh.name or "?") .. " + " .. (oh.name or "?"), quality = mh.quality, icon = mh.icon, link = mh.link,
    cstats = stats, speed = mh.speed, pair = { mh, oh } }
end

-- Display order (H5.2): Better's tiers, but inside each tier the items the member can wear now come first and
-- the look-ahead ones (too high level yet) after them. Better alone still picks the best suggestion per slot.
local function Order(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  local fa, fb = a.future and true or false, b.future and true or false
  if fa ~= fb then return fb end
  return Better(a, b)
end
GCA.SuggestionOrder = Order

---------------------------------------------------------------------------
-- Enchants (plan G4 + G7.1, G7.2, G7.7, G7.8, G7.9)
---------------------------------------------------------------------------
-- Enchant slot rows a worn item takes (SimGear Enchants.lua:17-36, 113-119). Weapon rows also go on a
-- two-hander; shield/off-hand rows by the worn item's equip location; an empty slot takes none.
GCA.ENCHANT_SLOTS = { [15] = "back", [5] = "chest", [9] = "wrist", [10] = "hands", [8] = "feet", [2] = "neck" }
local ENCHANT_HAND = { INVTYPE_2HWEAPON = { "twohand", "weapon" }, INVTYPE_WEAPON = { "weapon" }, INVTYPE_WEAPONMAINHAND = { "weapon" } }
local ENCHANT_OFF = { INVTYPE_SHIELD = { "shield" }, INVTYPE_HOLDABLE = { "offhand" } }
function GCA:EnchantKeysFor(slot, equipLoc)
  if self.ENCHANT_SLOTS[slot] then return { self.ENCHANT_SLOTS[slot] } end
  if slot == 16 then return ENCHANT_HAND[equipLoc or ""] end
  if slot == 17 then return ENCHANT_OFF[equipLoc or ""] end
end

-- Enchant ID in link field 2, or nil for none (G1.5).
function GCA:EnchantIDOf(link)
  local f = self:ParseLink(link)
  local id = f and tonumber(f[2])
  if id and id > 0 then return id end
end

-- The same item string with field 2 (enchant) blanked: the item as it scores without its enchant.
function GCA:WithoutEnchant(link)
  if type(link) ~= "string" then return link end
  return (link:gsub("(item:%-?%d+):%d*", "%1:", 1))
end

-- A school's spell power the set doesn't weigh while it weighs spell power: not simmed for this spec, can't be
-- scored (SimGear Enchants.lua:100-110). GCA: our data leaves exact-zero weights out, so a school SimGear lists
-- with 0 is "unsimmed" here too; both ways the enchant is not suggested.
local SCHOOLS = { HolyPower = true, FirePower = true, FrostPower = true, ShadowPower = true, ArcanePower = true, NaturePower = true }
function GCA.UnsimmedSchool(stats, set)
  local w = set and set.weights or EMPTY
  if (w.SpellPower or 0) <= 0 then return nil end
  for k in pairs(stats or EMPTY) do
    if SCHOOLS[k] and w[k] == nil then return k end
  end
end

local function PlayerFaction()
  local f = UnitFactionGroup and SafeCall(UnitFactionGroup, "player")
  if type(f) == "string" and not IsSecret(f) then return f end
end
GCA.PlayerFaction = PlayerFaction

-- Display info for an enchant row, shaped like item info for the UI (name, icon, quality, cstats).
GCA.enchantInfo = {}
function GCA:EnchantInfo(row)
  local c = self.enchantInfo[row.spell]
  if c then return c end
  local name, icon
  if C_Spell and C_Spell.GetSpellName then name = SafeCall(C_Spell.GetSpellName, row.spell) end
  if C_Spell and C_Spell.GetSpellTexture then icon = SafeCall(C_Spell.GetSpellTexture, row.spell) end
  if (not name or not icon) and GetSpellInfo then
    local n, _, ic = SafeCall(GetSpellInfo, row.spell)
    name, icon = name or n, icon or ic
  end
  if IsSecret(name) or type(name) ~= "string" then name = nil end
  if IsSecret(icon) then icon = nil end
  c = { name = name or row.name, icon = icon or "Interface\\Icons\\Trade_Engraving", quality = 1, minLevel = 0,
    cstats = row.stats or {}, enchantRow = row }
  if name then self.enchantInfo[row.spell] = c end
  return c
end

-- Weapon-damage enchants (W5, SimGear Enchants.statsOf): damage per hit ÷ the WORN weapon's speed (fallback SimGear's
-- assumed 2.6 one-hand / 3.5 two-hand) as MainHandDps, or TwoHandDps on a two-hander. Stat rows: their own stats.
GCA.ENCHANT_SPEED = { weapon = 2.6, twohand = 3.5 }
function GCA:EnchantStats(row, worn)
  if row.kind ~= "damage" then return row.stats or EMPTY end
  local stats = {}
  for k, v in pairs(row.stats or EMPTY) do stats[k] = v end
  local two = worn and worn.equipLoc == "INVTYPE_2HWEAPON"
  local speed = worn and type(worn.speed) == "number" and worn.speed > 0 and worn.speed
    or (two and self.ENCHANT_SPEED.twohand or self.ENCHANT_SPEED.weapon)
  local key = two and "TwoHandDps" or "MainHandDps"
  if row.damage and row.damage ~= 0 then stats[key] = (stats[key] or 0) + row.damage / speed end
  return stats
end
local SCORED_ENCHANT = { stats = true, damage = true }

-- EnchantInfo with cstats = what the row adds on this weapon (W5: damage rows depend on the worn weapon's speed).
function GCA:EnchantInfoOn(row, stats)
  local base = self:EnchantInfo(row)
  if row.kind ~= "damage" then return base end
  local c = {}
  for k, v in pairs(base) do c[k] = v end
  c.cstats = stats
  return c
end

-- Adds enchant suggestions into `best` (one per slot and known/unlearned). Returns the number of items still loading.
-- Gain = (new − current enchant value) ÷ the item's own score (G7.9), F's tiers: % upgrade (≥ 1 %), or points only
-- when the item scores ≤ 0 (no-baseline). W5: weapons have a real score now, so the weapon slot gets a % like armour,
-- and weapon-damage enchants (Striking/Impact) are scored (EnchantStats).
function GCA:AddEnchantSuggestions(best, ctx)
  local data = self:EnchantData()
  local e, items, prof = ctx.e, ctx.items, ctx.prof
  local faction = PlayerFaction()
  local pending = 0
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local info = ctx.equippedInfo[slot]
    local keys = info and not ctx.unknownSlot[slot] and self:EnchantKeysFor(slot, info.equipLoc)
    if keys then
      local curID = self:EnchantIDOf(items[slot])
      local curRow = curID and data.byEnchant[curID]
      -- unknown enchant ID (G7.1), proc/utility (never replaced, G7.2) or an unsimmed school: we can't value what is
      -- on the item, so nothing is suggested for this slot (weapon damage is valued since W5)
      local usable = curID == nil or (curRow ~= nil and SCORED_ENCHANT[curRow.kind] and not self.UnsimmedSchool(curRow.stats, e.set))
      local base = usable and info or nil
      if usable and curID then
        -- the item without its enchant, in case GetItemStats includes the enchant on an enchanted link (G7.9)
        local plain, failed = self:GetInfo(self:WithoutEnchant(items[slot]))
        if plain then base = plain elseif not failed then base = nil; pending = pending + 1 end
      end
      if base then
        local baseScore = self:Score(base, e)
        local curStats = curRow and self:EnchantStats(curRow, info)
        local curValue = curRow and Scoring.value(curStats, e.set) or 0
        for _, key in ipairs(keys) do
          for _, row in ipairs(data.bySlot[key] or EMPTY) do
            local known = not ctx.browse and self:IsKnown(row.spell, prof)
            if SCORED_ENCHANT[row.kind] and row.enchant ~= curID and (known or ctx.showAll)
               and (known or not (row.faction and faction and row.faction ~= faction))
               and not self.UnsimmedSchool(row.stats, e.set) then
              local rowStats = self:EnchantStats(row, info)
              local value = Scoring.value(rowStats, e.set)
              local gain = value - curValue
              local pts = self:ToPoints(e, gain)
              local status, pct, tier
              if gain > 0 then
                if baseScore <= 0 then
                  if pts >= self.MIN_POINTS then status, tier = "no-baseline", 1 end
                else
                  pct = gain / baseScore
                  if pct >= self.MIN_PCT then status, tier = "upgrade", 1 else pct = nil end
                end
              end
              if tier then
                local sug = {
                  kind = "enchant", enchant = row, current = curRow, hasEnchant = curID ~= nil,
                  cand = { spellID = row.spell, recipe = row, enchant = true },
                  info = self:EnchantInfoOn(row, rowStats), item = info, slot = slot, known = known, future = false,
                  status = status, pct = pct, tier = tier, gain = gain, points = pts,
                  newScore = baseScore + value, oldScore = baseScore + curValue, baseScore = baseScore,
                  equipped = curRow and { name = self:EnchantInfo(curRow).name, cstats = curStats } or nil, e = e,
                }
                -- one per slot and known/unlearned; rows sharing an enchant ID (G7.7) never show twice
                local gkey = "E" .. slot .. "|w" .. (known and "k" or "u")
                local cur = best[gkey]
                if not cur or Better(sug, cur) then best[gkey] = sug end
                if ctx.all then -- section I: every enchant row goes to its slot's section (top 3 there)
                  ctx.all[slot] = ctx.all[slot] or {}
                  ctx.all[slot][#ctx.all[slot] + 1] = sug
                end
              end
            end
          end
        end
      end
    end
  end
  return pending
end

-- view = { key, class, level, items, spec }. prof: profession (default: the selected one).
-- Returns list, pending, state, weight entry. state: "ok", "no-level", "no-class", "no-spec", "no-weights", "loading".
function GCA:ComputeSuggestions(m, isSelf, prof)
  local s = self.db.settings
  prof = prof or self:SelectedProfession()
  local browse = self:IsBrowse(prof)
  local showAll = s.showUnlearned or browse -- browse forces show-unlearned (G7.11)
  local class, level = m.class, m.level
  if not class then return {}, 0, "no-class" end
  if type(level) ~= "number" or level < 1 then return {}, 0, "no-level" end -- F8.10
  if not m.spec then return {}, 0, "no-spec" end                             -- F8.2
  local e = self:WeightSetFor(class, m.spec, level)
  if not e then return {}, 0, "no-weights" end
  local maxLevel = level + (s.lookahead and self.LOOKAHEAD_LEVELS or 0)
  local items = m.items or {}
  local pending = 0

  -- equipped items in SimGear's shape; an item that failed to load makes its slot unknown
  local equipped, equippedInfo, unknownSlot = {}, {}, {}
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local link = items[slot]
    if link then
      local info, failed = self:GetInfo(link)
      if failed then
        unknownSlot[slot] = true
      elseif not info then
        pending = pending + 1
      else
        equipped[slot] = self:ScoreItem(info)
        equippedInfo[slot] = info
      end
    end
  end
  -- comparing against half-loaded gear would show fake "empty slot" upgrades
  if pending > 0 then return {}, pending, "loading", e end

  local excluded = self.GEAR_RULES[class .. "/" .. m.spec] or {}
  -- a candidate that would be compared with an unknown slot is not offered (rings/trinkets: either slot; weapons,
  -- shields and held off-hands are compared as the main hand + off hand pair, plan W4)
  local function touchesUnknown(loc)
    for _, sl in ipairs(self.SLOTS_FOR[loc] or {}) do if unknownSlot[sl] then return true end end
    return self.HAND_LOCS[loc] == true and (unknownSlot[16] == true or unknownSlot[17] == true)
  end
  local function valueOf(item) return item.info and self:Score(item.info, e) end
  local sets = self:ItemSets()
  local faction = PlayerFaction()
  -- W4: dual wield now (compare opts) and from which level (off-hand weapons are look-ahead rows before it)
  local dwFrom = self:DualWieldFrom(class, m.spec, level, isSelf)
  local opts = { dualWield = dwFrom ~= nil and level >= dwFrom }
  local best, all = {}, {} -- best: the 0.5.0 per-slot pick (badge meaning); all: every suggestion per section (I)
  for _, cand in ipairs(self:GetCandidates(prof)) do
    local known = not browse and self:IsKnown(cand.spellID, prof)
    local r = cand.recipe
    local offWeapon = cand.equipLoc == "INVTYPE_WEAPONOFFHAND" -- only for a dual-wielder (SimGear Advisor.scoreItem)
    if (known or showAll) and (known or not (r.faction and faction and r.faction ~= faction))
       and self:CanWear(class, maxLevel, cand) and not excluded[cand.equipLoc] and not touchesUnknown(cand.equipLoc)
       and not (offWeapon and not (dwFrom and dwFrom <= maxLevel)) then
      local info, failed = self:GetInfo(cand.itemID)
      -- K0/L1: the level this member can actually wear it at (item level, armor/weapon proficiency, dual wield)
      local needLevel = info and math.max(info.minLevel, self:WearFrom(class, cand) or 0)
      if info and offWeapon then needLevel = math.max(needLevel, dwFrom) end
      if not info then
        if not failed then pending = pending + 1 end
      elseif needLevel <= maxLevel and (isSelf or info.bind ~= 1) and self:PassesRestrictions(cand.itemID, class, isSelf) then
        local candItem = self:ScoreItem(info)
        candItem.equipLoc = info.equipLoc or cand.equipLoc
        local r = Scoring.compare(candItem, equipped, e.set, sets, valueOf, opts)
        local sug
        if r and r.status ~= "equipped" then
          local gain = r.newValue - r.oldValue
          local tier, points = nil, self:ToPoints(e, gain)
          if r.status == "needs-partner" then
            -- W8.2: a one-hander / off hand next to a worn two-hander: scored alone, its own tier after the real gains
            points = self:ToPoints(e, r.newValue)
            if r.newValue > 0 and points >= self.MIN_POINTS then tier = self.TIER_PARTNER end
          elseif r.status == "empty-slot" then
            if r.newValue > 0 and points >= self.MIN_POINTS then tier = 1 end
          elseif r.status == "no-baseline" then
            if gain > 0 and points >= self.MIN_POINTS then tier = 1 end
          elseif r.pct and r.pct >= self.MIN_PCT then
            tier = 1
          end
          if tier then
            -- the hand/slot the craft goes into (W4): a dual-wield one-hander in the off hand -> 17; a needs-partner
            -- off hand -> 17 even though the worn two-hander is what it displaces
            local slot = r.replaces and r.replaces[1] or self.SLOTS_FOR[cand.equipLoc][1]
            local worn = equippedInfo[slot]
            if r.status == "needs-partner" then
              slot = Scoring.OFF_HAND_TYPES[cand.equipLoc] and 17 or 16
              worn = equippedInfo[16]
            elseif cand.equipLoc == "INVTYPE_2HWEAPON" and equippedInfo[16] and equippedInfo[17] then
              worn = self:PairInfo(equippedInfo[16], equippedInfo[17])
            end
            sug = {
              kind = "item", cand = cand, info = info, slot = slot, known = known, future = needLevel > level,
              wearAt = needLevel > level and needLevel or nil, -- H5.2: "wearable at level N (in X levels)"
              levelsToGo = needLevel > level and (needLevel - level) or nil,
              status = r.status, pct = r.status ~= "needs-partner" and r.pct or nil, tier = tier,
              gain = gain, points = points, newScore = r.newValue, oldScore = r.oldValue,
              equipped = worn, sets = r.sets, setDelta = r.setDelta, e = e,
              hand = r.hand, -- "off": a dual-wield one-hander scored in the off hand (row says "(off hand)")
              bothHands = (cand.equipLoc == "INVTYPE_2HWEAPON" and equippedInfo[17] ~= nil) or nil, -- "replaces both hands"
            }
          end
        end
        if sug then
          local afterIDs = {}
          for sl, it in pairs(equipped) do
            local gone = sl == sug.slot or (r.replaces and (r.replaces[1] == sl or r.replaces[2] == sl))
            if not gone then afterIDs[#afterIDs + 1] = it.itemID end
          end
          afterIDs[#afterIDs + 1] = cand.itemID
          sug.afterIDs = afterIDs
          -- one per slot, known/unlearned AND wearable/look-ahead (review M-2): a bigger look-ahead craft must not
          -- hide the craft the member can wear now; both are listed (wearable first inside a tier, SuggestionOrder)
          -- W4: weapons go to the section of the hand they are scored in
          local group = self.HAND_LOCS[cand.equipLoc] and sug.slot or self.SLOTS_FOR[cand.equipLoc][1]
          local gkey = group .. "|" .. (sug.future and "f" or "w") .. (known and "k" or "u")
          local cur = best[gkey]
          if not cur or Better(sug, cur) then best[gkey] = sug end
          -- section I: every suggestion is kept per section for the top 3
          all[group] = all[group] or {}
          all[group][#all[group] + 1] = sug
        end
      end
    end
  end
  if prof == "Enchanting" then
    pending = pending + self:AddEnchantSuggestions(best, { e = e, items = items, prof = prof, browse = browse, showAll = showAll,
      equippedInfo = equippedInfo, unknownSlot = unknownSlot, all = all })
  end

  -- The per-slot pick of 0.5.0 ("primary" rows): best per slot × known/unlearned × wearable/look-ahead, hidden when
  -- another one for the same slot is at least as good AND at least as usable: known beats unlearned, wearable now
  -- beats look-ahead (so a look-ahead craft no better than a wearable one isn't listed, and an unlearned recipe no
  -- better than a known one isn't either). A better look-ahead craft stays (M-2). These rows keep the meaning of the
  -- member badge/best, the member order and the minimap counts (section I); the extra rows of the top 3 don't count.
  local primary = {}
  for gkey, sug in pairs(best) do
    local group = gkey:match("^(.*)|")
    local hidden = false
    for _, flags in ipairs({ "wk", "wu", "fk", "fu" }) do
      local other = best[group .. "|" .. flags]
      if other and other ~= sug and (other.known or not sug.known) and (sug.future or not other.future)
         and not Better(sug, other) then
        hidden = true
        break
      end
    end
    if not hidden then primary[sug] = true end
  end

  -- Section I: up to SECTION_TOP rows per section (slot; rings and trinkets one section each), in the display order.
  local list, shownBy, totals = {}, {}, {}
  for group, rows in pairs(all) do
    local shown, total = self:SectionCut(rows, primary)
    shownBy[group], totals[group] = shown, total
    for _, sug in ipairs(shown) do list[#list + 1] = sug end
  end
  for _, sug in ipairs(list) do
    if sug.kind == "item" then sug.hint = self:SetHint(sug.cand.itemID, sug.afterIDs, prof) end
  end
  table.sort(list, Order)
  if next(unknownSlot) then list.unknownSlots = unknownSlot end
  list.sections = self:BuildSections(shownBy, totals, items, equippedInfo, unknownSlot, e)
  return list, pending, "ok", e
end

-- Section I: how many crafts/enchants a slot section lists.
GCA.SECTION_TOP = 3
-- Section order "in character order" for slots without an upgrade; rings and trinkets are one section each.
GCA.SECTION_SLOTS = { { 1 }, { 2 }, { 3 }, { 15 }, { 5 }, { 9 }, { 10 }, { 6 }, { 7 }, { 8 }, { 11, 12 }, { 13, 14 }, { 16 }, { 17 }, { 18 } }
GCA.SECTION_OF = {}
for _, slots in ipairs(GCA.SECTION_SLOTS) do for _, sl in ipairs(slots) do GCA.SECTION_OF[sl] = slots[1] end end

-- The rows of one section (all suggestions for that slot): duplicates dropped (the same item from two recipes, or
-- two enchant rows with the same enchant ID, G7.7), rows dominated by a more usable one dropped (the rule above:
-- an unlearned recipe no better than a known one, a look-ahead craft no better than a wearable one), then the
-- first SECTION_TOP in SuggestionOrder. A known primary row (it counts for the badge/minimap) is never cut: it takes
-- the place of the last non-primary row. Every row gets `extra = true` unless it is a primary row.
-- Returns the shown rows (SuggestionOrder) and how many rows were eligible before the cut.
function GCA:SectionCut(rows, primary)
  local sorted = {}
  for i, s in ipairs(rows) do sorted[i] = s end
  table.sort(sorted, Order)
  local uniq, at = {}, {}
  for _, s in ipairs(sorted) do
    local id = s.kind == "enchant" and ("E" .. tostring(s.enchant and s.enchant.enchant)) or ("I" .. tostring(s.cand and s.cand.itemID))
    local i = at[id]
    if not i then
      uniq[#uniq + 1] = s
      at[id] = #uniq
    elseif primary[s] and not primary[uniq[i]] then
      uniq[i] = s
    end
  end
  local kept = {}
  for _, s in ipairs(uniq) do
    local hidden = false
    if not primary[s] then
      for _, o in ipairs(uniq) do
        if o ~= s and o.kind == s.kind and ((o.known and not s.known) or (s.future and not o.future))
           and (o.known or not s.known) and (s.future or not o.future) and not Better(s, o) then
          hidden = true
          break
        end
      end
    end
    if not hidden then kept[#kept + 1] = s end
  end
  local top = self.SECTION_TOP
  local shown = {}
  for i = 1, math.min(top, #kept) do shown[i] = kept[i] end
  for i = top + 1, #kept do
    local s = kept[i]
    if primary[s] and s.known then
      for j = #shown, 1, -1 do
        if not (primary[shown[j]] and shown[j].known) then shown[j] = s; break end
      end
    end
  end
  table.sort(shown, Order)
  for _, s in ipairs(shown) do s.extra = (not primary[s]) or nil end
  return shown, #kept
end

-- Sections for the window (section I): one per SECTION_SLOTS entry with the worn item(s) and their scores; the
-- sections with rows first, by their first row (SuggestionOrder, the comparison of the member order), then the
-- ones without an upgrade in character order. sec = { key, slots, rows, total, worn = { {slot, link, info, score,
-- unknown} }, unknown = a worn item didn't load (nothing was compared there), index }.
function GCA:BuildSections(shownBy, totals, items, equippedInfo, unknownSlot, e)
  local secs = {}
  for i, slots in ipairs(self.SECTION_SLOTS) do
    local key = slots[1]
    local worn, unknown = {}, false
    for _, sl in ipairs(slots) do
      local info = equippedInfo[sl]
      worn[#worn + 1] = { slot = sl, link = items[sl], info = info, unknown = unknownSlot[sl] or nil,
        score = info and self:ToPoints(e, self:Score(info, e)) or nil }
      if unknownSlot[sl] then unknown = true end
    end
    secs[#secs + 1] = { key = key, slots = slots, index = i, rows = shownBy[key] or {}, total = totals[key] or 0,
      worn = worn, unknown = unknown }
  end
  table.sort(secs, function(a, b)
    local ra, rb = a.rows[1], b.rows[1]
    if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
    if ra and rb then
      if Order(ra, rb) then return true end
      if Order(rb, ra) then return false end
    end
    return a.index < b.index
  end)
  return secs
end

-- Suggestions for one member and profession, cached on gear signature + spec + level + settings (F8.11)
-- + profession, browse and the known-set revision (G7.11).
GCA.sugCache = {}
GCA.knownGen = 0
function GCA:MemberSuggestions(view, isSelf, prof)
  local s = self.db.settings
  prof = prof or self:SelectedProfession()
  local sig = table.concat({ self:GearSignature(view.items), tostring(view.class), tostring(view.level), tostring(view.spec),
    s.showUnlearned and "u" or "", s.lookahead and "l" or "", tostring(self:SurvivalShare()), self.knownGen,
    prof, self:IsBrowse(prof) and "b" or "" }, "|")
  local ck = tostring(view.key) .. "|" .. prof
  local c = self.sugCache[ck]
  if c and c.sig == sig then return c.list, c.pending, c.state, c.e end
  local list, pending, state, e = self:ComputeSuggestions(view, isSelf, prof)
  if (pending or 0) == 0 then
    self.sugCache[ck] = { sig = sig, list = list, pending = pending, state = state, e = e }
  else
    self:ScheduleLoadRetry()
  end
  return list, pending, state, e
end

-- Known suggestions only (badges, member order, minimap: G7.11 counts only what you can craft).
-- The member's best is the first wearable one (review M-2); a look-ahead one only when nothing known is wearable.
-- Section I: the extra rows of a slot's top 3 (`extra`) don't count, so the badge and the minimap count keep
-- their meaning (one per slot and wearable/look-ahead, as in 0.5.0).
local function KnownOnly(list)
  local n, first, firstFuture = 0, nil, nil
  for _, sug in ipairs(list or EMPTY) do
    if sug.known and not sug.extra then
      n = n + 1
      if sug.future then firstFuture = firstFuture or sug else first = first or sug end
    end
  end
  return n, first or firstFuture
end
GCA.KnownOnly = KnownOnly

-- All members for the left-hand list (guild roster + everyone we have gear for)
function GCA:GetMemberList()
  local s = self.db.settings
  local prof = self:SelectedProfession()
  local browse = self:IsBrowse(prof)
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
      key = key, isSelf = isSelf, online = online, member = m, browse = browse, prof = prof,
      class = (r and r.class) or (m and m.class), level = (r and r.level) or (m and m.level),
    }
    if type(e.level) ~= "number" or e.level < 1 then e.level = nil end
    e.spec, e.specHow, e.specAssumed = self:MemberSpec(key, e.class, m and m.items)
    if m then
      local view = { key = key, class = e.class, level = e.level, items = m.items, spec = e.spec }
      e.suggestions, e.pending, e.state, e.weights = self:MemberSuggestions(view, isSelf, prof)
      -- badges and the member order count only recipes you know; browse counts nothing (G7.11)
      if browse then e.knownCount = 0 else e.knownCount, e.best = KnownOnly(e.suggestions) end
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
    -- members with the biggest single % upgrade first (F7.4, F8.5)
    if (a.best ~= nil) ~= (b.best ~= nil) then return a.best ~= nil end
    if a.best and b.best then
      if Order(a.best, b.best) then return true end
      if Order(b.best, a.best) then return false end
    end
    if a.online ~= b.online then return a.online end
    return a.key < b.key
  end)
  return entries
end

-- K2 "Guild needs": one row per member and suggestion, biggest gain first. Built from GetMemberList's entries
-- (their suggestion lists are the cached MemberSuggestions results, so nothing is scored here). Rows = what the
-- member view lists minus the extra rows of a slot's top 3 (`extra`): the primary per-slot picks that also drive
-- the badge; with "Show unlearned" / browse that includes unlearned recipes, exactly as in the member view.
-- You (isSelf) and members without a gear record have no rows. Order: SuggestionOrder (tiers, wearable before
-- look-ahead, gain), then member key, then recipe. Returns { online = {rows}, offline = {rows} }, rows =
-- { rowKind = "need", sug = suggestion, member = entry }.
-- Cached: the same entries (key, suggestion list, online, class, in the same order) and the same sugCache table
-- (InvalidateScores replaces it) give the same result without sorting again.
function GCA:GuildNeeds(entries)
  entries = entries or self:GetMemberList()
  local c = self.needsCache
  if c and c.sugCache == self.sugCache and #c.keys == #entries then
    local same = true
    for i, e in ipairs(entries) do
      local k = c.keys[i]
      if k[1] ~= e.key or k[2] ~= e.suggestions or k[3] ~= e.online or k[4] ~= e.class then same = false; break end
    end
    if same then return c.result end
  end
  local online, offline, keys = {}, {}, {}
  for i, e in ipairs(entries) do
    keys[i] = { e.key, e.suggestions, e.online, e.class }
    if not e.isSelf and e.member then
      for _, s in ipairs(e.suggestions or EMPTY) do
        if not s.extra then
          local row = { rowKind = "need", sug = s, member = e }
          if e.online then online[#online + 1] = row else offline[#offline + 1] = row end
        end
      end
    end
  end
  local function order(a, b)
    if Order(a.sug, b.sug) then return true end
    if Order(b.sug, a.sug) then return false end
    if a.member.key ~= b.member.key then return a.member.key < b.member.key end
    return (a.sug.cand and a.sug.cand.spellID or 0) < (b.sug.cand and b.sug.cand.spellID or 0)
  end
  table.sort(online, order)
  table.sort(offline, order)
  -- K5: grouped by craft (one entry per recipe that is an upgrade for >= 1 member). Built from the sorted rows, so
  -- a group's first row is its best and the groups come out in the same order as their best rows (wearable
  -- before look-ahead inside a tier, then the gain). One row per member and craft (a ring craft for both rings:
  -- the better one). crafts = online members only (the default), craftsAll = online + offline.
  local function group(rows)
    local out, byKey = {}, {}
    for _, r in ipairs(rows) do
      local s = r.sug
      local key = (s.kind == "enchant" and "e" or "i") .. tostring(s.cand and s.cand.spellID or (s.info and s.info.name) or "?")
      local g = byKey[key]
      if not g then
        g = { rowKind = "craft", key = key, sug = s, rows = {}, seen = {}, future = s.future and true or false }
        byKey[key] = g
        out[#out + 1] = g
      end
      if not g.seen[r.member.key] then
        g.seen[r.member.key] = true
        g.rows[#g.rows + 1] = r
      end
    end
    for _, g in ipairs(out) do g.best = g.rows[1]; g.seen = nil end
    return out
  end
  local all = {}
  for _, r in ipairs(online) do all[#all + 1] = r end
  for _, r in ipairs(offline) do all[#all + 1] = r end
  table.sort(all, order)
  local result = { online = online, offline = offline, crafts = group(online), craftsAll = group(all) }
  self.needsCache = { sugCache = self.sugCache, keys = keys, result = result }
  self.needsBuilds = (self.needsBuilds or 0) + 1
  return result
end

-- K5: the guild needs grouped by craft, for the UI (and the K6 rebuild). withOffline: include offline members.
-- Returns the cached list of groups { rowKind = "craft", key, sug = best suggestion, best = best row,
-- rows = { { rowKind = "need", sug, member } ... } best first, future = only too-high-level }, best group first.
function GCA:GuildNeedsByCraft(entries, withOffline)
  local needs = self:GuildNeeds(entries)
  return withOffline and needs.craftsAll or needs.crafts, needs
end

-- Upgrades you can craft, per profession of yours (minimap tooltip). Browse never counts (G7.11).
-- Without a trusted GetProfessions answer: the selected profession only.
function GCA:UpgradeCounts()
  local own, trusted = self:OwnProfessions()
  local sel = self:SelectedProfession()
  local entries = self:GetMemberList()
  local out = {}
  for _, p in ipairs(self.PROFESSIONS) do
    if (trusted and own[p.key]) or (not trusted and p.key == sel) then
      local n, members = 0, 0
      for _, en in ipairs(entries) do
        if en.member and not en.isSelf then
          local list = self:MemberSuggestions({ key = en.key, class = en.class, level = en.level, items = en.member.items, spec = en.spec }, false, p.key)
          local k = KnownOnly(list)
          n = n + k
          if k > 0 then members = members + 1 end
        end
      end
      out[#out + 1] = { prof = p.key, upgrades = n, members = members }
    end
  end
  local recorded = 0
  for _, en in ipairs(entries) do if en.member and not en.isSelf then recorded = recorded + 1 end end
  return out, recorded
end
---------------------------------------------------------------------------
-- "Crafted" marks (plan H5.1): a local reminder per character, keyed member -> profession -> recipe spellID.
-- Not synced. Cleared when a new gear record of that member shows the item in a slot that didn't hold it when
-- you ticked, or more copies of it than then (review M-3); for an enchant, when the marked slot carries that
-- enchant ID. Otherwise kept until unticked.
-- db.crafted[charKey][memberKey][prof][spellID] = { item = itemID, had = { [slot] = true }, count | enchant = enchantID, slot, t }
---------------------------------------------------------------------------
function GCA:CraftedStore(create)
  if not (self.db and self.charKey) then return nil end
  if not self.db.crafted then
    if not create then return nil end
    self.db.crafted = {}
  end
  local t = self.db.crafted[self.charKey]
  if not t and create then t = {}; self.db.crafted[self.charKey] = t end
  return t
end

function GCA:CraftedMark(member, prof, spellID)
  local t = self:CraftedStore(false)
  local p = t and member and t[member] and t[member][prof]
  return p and spellID and p[spellID] or nil
end

function GCA:SetCrafted(member, prof, sug, on)
  if not (member and prof and sug and sug.cand and sug.cand.spellID) then return end
  local spellID = sug.cand.spellID
  if on then
    local t = self:CraftedStore(true)
    if not t then return end
    t[member] = t[member] or {}
    t[member][prof] = t[member][prof] or {}
    local isEnchant = sug.kind == "enchant"
    local mark = {
      item = (not isEnchant) and sug.cand.itemID or nil,
      enchant = isEnchant and sug.enchant and sug.enchant.enchant or nil,
      slot = sug.slot, t = time(),
    }
    -- review M-3: the slots that already hold this item when you tick (e.g. one ring of a pair you made earlier);
    -- only a NEW slot with it, or more copies than now, counts as "wearing the one you crafted"
    if mark.item then
      local m = self.db.members and self.db.members[member]
      mark.had, mark.count = {}, 0
      for slot, link in pairs(m and m.items or EMPTY) do
        if ItemIDFrom(link) == mark.item then mark.had[slot] = true; mark.count = mark.count + 1 end
      end
    end
    t[member][prof][spellID] = mark
  else
    local t = self:CraftedStore(false)
    local p = t and t[member] and t[member][prof]
    if not p then return end
    p[spellID] = nil
    if not next(p) then t[member][prof] = nil end
    if not next(t[member]) then t[member] = nil end
  end
end

local function MarkWorn(self, mark, items)
  if mark.enchant then
    return mark.slot ~= nil and self:EnchantIDOf(items[mark.slot]) == mark.enchant
  end
  if not mark.item then return false end
  -- review M-3: marks ticked before this fix have no `had`/`count`: then any slot with the item counts (as in 0.5.0)
  local had, n = mark.had or EMPTY, 0
  for slot, link in pairs(items) do
    if ItemIDFrom(link) == mark.item then
      n = n + 1
      if not had[slot] then return true end
    end
  end
  return n > (mark.count or 0)
end

-- Called for every stored record (own inspect, own gear, guild sync). Marks of all your characters are checked:
-- once the member wears it, nobody needs the reminder. Returns the number of marks cleared.
function GCA:ClearWornCrafted(member, items)
  if not (self.db and self.db.crafted and member and type(items) == "table") then return 0 end
  local n = 0
  for _, byMember in pairs(self.db.crafted) do
    local profs = byMember[member]
    if profs then
      for prof, marks in pairs(profs) do
        for spellID, mark in pairs(marks) do
          if MarkWorn(self, mark, items) then marks[spellID] = nil; n = n + 1 end
        end
        if not next(marks) then profs[prof] = nil end
      end
      if not next(profs) then byMember[member] = nil end
    end
  end
  return n
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
local DEFAULTS = { guildOnly = true, showUnlearned = false, lookahead = true, autoTarget = true, hideOffline = true, sync = true,
  survival = 0.5, inspectTalents = false, -- inspected talents: off until verified in game (F8.6)
  memberView = "sheet", -- K4: member view variant "sheet" (character sheet) or "list" (cards)
  autoInspect = true,   -- K5: read gear automatically (target, group, mouseover); replaces autoTarget's toggle
  needsOffline = false } -- K5: guild needs include offline members

local events = {}

function events:ADDON_LOADED(name)
  if name ~= ADDON then return end
  RavenquillExpeditionCraftDB = RavenquillExpeditionCraftDB or {}
  local db = RavenquillExpeditionCraftDB
  db.members = db.members or {}
  db.known = db.known or {}
  db.settings = db.settings or {}
  db.specs = db.specs or {}           -- [key] = { class, spec | tree, src = "sync"|"inspect", ts }
  db.specManual = db.specManual or {} -- [key] = { class, spec }: manual pick, wins (F4)
  -- K5: "Auto-inspect target" became "Read gear automatically"; whoever had turned the old toggle off keeps it off
  if db.settings.autoInspect == nil and db.settings.autoTarget == false then db.settings.autoInspect = false end
  for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
  -- 0.3.0 dev builds defaulted inspectTalents to true: reset once (nobody has turned it on by hand yet)
  if not db.inspectTalentsOffV1 then db.settings.inspectTalents = false; db.inspectTalentsOffV1 = true end
  db.profSel = db.profSel or {}       -- [charKey] = selected profession key (G3)
  self.db = db
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
  self.loginTime = GetTime()
  self.playerKey = self:UnitKey("player")
  local _, class = SafeCall(UnitClass, "player")
  if class and not IsSecret(class) then self.playerClass = class end
  -- per-character key: first name alone isn't unique on Forever, so include the surname.
  -- v0.1 used "First-Realm"; move that entry once.
  local realm = GetRealmName() or "?"
  self.charKey = (self.playerKey or UnitName("player") or "?") .. "-" .. realm
  local oldKey = (UnitName("player") or "?") .. "-" .. realm
  if oldKey ~= self.charKey and self.db.known[oldKey] and not self.db.known[self.charKey] then
    self.db.known[self.charKey] = self.db.known[oldKey]
    self.db.known[oldKey] = nil
  end
  self.itemToSpell = self:ItemToSpell(self:SelectedProfession())
  self:RequestRoster()
  C_Timer.After(3, function()
    self:CaptureSelf()
    self:RefreshKnown()
    self:PreloadItems()
    self:RefreshOwnSpec()
  end)
  -- K0/L4: ask for a fresh roster once pruning is allowed (GUILD_ROSTER_UPDATE then prunes)
  C_Timer.After(self.PRUNE_DELAY + 1, function() self:RequestRoster() end)
  -- an empty GetProfessions answer is only trusted PROF_TRUST_DELAY s after login: look again then (G7.6)
  C_Timer.After(self.PROF_TRUST_DELAY + 2, function() self:RefreshKnown(); SafeCall(self.KnownDiag, self, "login") end)
end

function events:PLAYER_EQUIPMENT_CHANGED()
  if self.equipTimer then return end
  self.equipTimer = true
  C_Timer.After(1, function() self.equipTimer = nil; self:CaptureSelf() end)
end

function events:PLAYER_LEVEL_UP() C_Timer.After(1, function() self:CaptureSelf(); self:QueueOwnSpecRefresh() end) end

-- own talents changed (names differ between client generations; unknown events are skipped by pcall)
function GCA:QueueOwnSpecRefresh()
  if self.specTimer or not (self.db and self.playerKey) then return end
  self.specTimer = true
  C_Timer.After(1.5, function() self.specTimer = nil; self:RefreshOwnSpec() end)
end
function events:TRAIT_CONFIG_UPDATED() self:QueueOwnSpecRefresh() end
events.TRAIT_CONFIG_LIST_UPDATED = events.TRAIT_CONFIG_UPDATED
events.PLAYER_TALENT_UPDATE = events.TRAIT_CONFIG_UPDATED
events.CHARACTER_POINTS_CHANGED = events.TRAIT_CONFIG_UPDATED
events.SPELLS_CHANGED = events.TRAIT_CONFIG_UPDATED -- Cat Form learned

function events:INSPECT_READY(guid) self:OnInspectReady(guid) end

function events:GUILD_ROSTER_UPDATE()
  self:ReadRoster()
  SafeCall(self.PruneStale, self) -- K0/L4: no-op until the roster is trustworthy, then once per session
  self:Invalidate()
end

-- Only items we are waiting for; a failed item that arrives after all drops the suggestion cache (its slot was
-- treated as unknown). success == false: the item doesn't exist -> give up on it, no refresh.
function events:GET_ITEM_INFO_RECEIVED(itemID, success)
  if IsSecret(itemID) or IsSecret(success) then return end
  local st = itemID and self.loadState[itemID]
  if not st then return end
  if success == false then st.failed = true return end
  if st.failed then self.sugCache = {} end
  self:Invalidate()
end

function events:TRADE_SKILL_SHOW()
  C_Timer.After(0.5, function()
    SafeCall(self.KnownDiag, self, "window") -- before the scan may replace the saved set
    self:ScanTradeSkill()
  end)
end
events.TRADE_SKILL_LIST_UPDATE = events.TRADE_SKILL_SHOW
events.TRADE_SKILL_DATA_SOURCE_CHANGED = events.TRADE_SKILL_SHOW

function events:NEW_RECIPE_LEARNED(recipeID)
  -- the event names the recipe: mark it directly (the spell APIs are not trusted once the window answered)
  if type(recipeID) == "number" and not IsSecret(recipeID) and self.db and self.charKey then
    local store = self:KnownStore()
    for _, p in ipairs(self.PROFESSIONS) do
      if self:KnowableSpells(p.key)[recipeID] then
        store[p.key] = store[p.key] or {}
        store[p.key][recipeID] = true
      end
    end
  end
  C_Timer.After(0.5, function() self:RefreshKnown() end)
end
function events:LEARNED_SPELL_IN_TAB() C_Timer.After(0.5, function() self:RefreshKnown() end) end

-- Diagnostic (temporary): what each "known" source says for recipes that any source calls known.
-- Saved to db.knownDiag so it can be read offline after a /reload. "ips/isk/tsl/saved" = IsPlayerSpell,
-- C_SpellBook.IsSpellKnown, C_TradeSkillUI learned (only while a profession window is open), saved mark.
function GCA:KnownDiag(tag)
  if not (self.db and self.charKey) then return end
  local store = self:KnownStore()
  local out = { when = date and date("%Y-%m-%d %H:%M:%S"), tag = tag }
  local api = C_TradeSkillUI
  for _, p in ipairs(self.PROFESSIONS) do
    local rows = {}
    for id in pairs(self:KnowableSpells(p.key)) do
      local ips = IsPlayerSpell and SafeCall(IsPlayerSpell, id)
      local isk = C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, id)
      local info = api and api.GetRecipeInfo and SafeCall(api.GetRecipeInfo, id)
      local tsl = type(info) == "table" and info.learned
      local saved = store[p.key] and store[p.key][id]
      local function b(v) if IsSecret(v) then return "S" end return v and "1" or (v == false and "0" or "-") end
      if (ips and not IsSecret(ips)) or (isk and not IsSecret(isk)) or (tsl and not IsSecret(tsl)) or saved then
        rows[id] = b(ips) .. b(isk) .. b(tsl) .. b(saved)
      end
    end
    if next(rows) then out[p.key] = rows end
  end
  self.db.knownDiag = self.db.knownDiag or {}
  self.db.knownDiag[tag or "login"] = out
end
-- a profession learned or dropped (G7.6): re-read professions, clear dropped ones, follow the default selection
function events:SKILL_LINES_CHANGED()
  if self.skillTimer or not self.charKey then return end
  self.skillTimer = true
  C_Timer.After(1, function() self.skillTimer = nil; self:RefreshKnown(); self:Invalidate() end)
end

function events:PLAYER_TARGET_CHANGED()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) or InCombatLockdown() then return end
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then return end
  if not self:IsGuildmate("target") or not SafeCall(CanInspect, "target") then return end
  self:QueueInspect("target", false)
end

-- K5: automatic reading of group members (debounced: the event fires in bursts) and of guildies under the mouse
function events:GROUP_ROSTER_UPDATE()
  if self.groupTimer or not (self.db and self.db.settings.autoInspect) then return end
  self.groupTimer = true
  C_Timer.After(self.AUTO_GROUP_DELAY, function() self.groupTimer = nil; self:AutoScanGroup() end)
end
function events:UPDATE_MOUSEOVER_UNIT() SafeCall(self.AutoMouseover, self) end
-- combat over: a group scan asked for during combat runs now, a waiting queue resumes at once
function events:PLAYER_REGEN_ENABLED()
  if self.autoGroupPending then self:AutoScanGroup() end
  self:ProcessQueue()
end

GCA:SetScript("OnEvent", function(self, event, ...)
  local h = events[event]
  if h then h(self, ...) end
end)
for event in pairs(events) do pcall(GCA.RegisterEvent, GCA, event) end

---------------------------------------------------------------------------
-- /gca stats <item link>: raw GetItemStats keys + our canonical result (F3)
---------------------------------------------------------------------------
function GCA:StatsDebug(link)
  if not link or not link:find("item:", 1, true) then Print("Usage: " .. (GCA.CMD or "/gca") .. " stats <shift-click an item>") return end
  local raw = SafeCall(ItemAPI.Stats, link)
  if type(raw) ~= "table" or IsSecret(raw) then
    local id = ItemIDFrom(link)
    if id and ItemAPI.Request then SafeCall(ItemAPI.Request, id) end
    Print("No stats returned yet (item data loading?). Try again in a moment.")
    return
  end
  local keys = {}
  for k, v in pairs(raw) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(keys)
  Print("GetItemStats: " .. (#keys > 0 and table.concat(keys, ", ") or "(empty)"))
  local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subClassID = SafeCall(ItemAPI.Info, link)
  local stats, unknown = Scoring.normalize(raw)
  Scoring.addWeaponDps(stats, equipLoc)
  local speed
  if classID == 2 then -- W7: speed + DPS of a weapon
    speed = self:WeaponSpeed(ItemIDFrom(link), link)
    local dps
    for _, k in ipairs({ "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }) do dps = dps or stats[k] end
    Print(string.format("Weapon: speed %s (label %s), DPS %s, dagger %s", speed and string.format("%.2f", speed) or "not read",
      tostring(type(SPEED) == "string" and not IsSecret(SPEED) and SPEED or "nil"), dps and string.format("%.2f", dps) or "-",
      tostring(subClassID == 15)))
  end
  local out = {}
  for k, v in pairs(stats) do out[#out + 1] = string.format("%s=%g", k, v) end
  table.sort(out)
  Print("Canonical: " .. (#out > 0 and table.concat(out, ", ") or "(none)") ..
    (#unknown > 0 and ("  |cffff8800unmapped: " .. table.concat(unknown, ", ") .. "|r") or ""))
  local key = self.UI and self.UI.selected or self.playerKey
  local entry = key and self.UI and self.UI.current
  local e = entry and entry.weights
  if e then
    local v = Scoring.itemValue({ equipLoc = equipLoc, stats = stats, speed = speed, dagger = subClassID == 15 or nil }, e.set)
    Print(string.format("Score for %s (%s): %.2f %s  [%s]", key, self:SpecName(e.class, e.spec), self:ToPoints(e, v), self:UnitLabel(e), self:SourceLine(e)))
  end
end

---------------------------------------------------------------------------
-- /gca known debug (G7.10): which APIs see your recipes, item recipes vs enchant spells
---------------------------------------------------------------------------
function GCA:KnownDebug()
  local own, trusted = self:ReadProfessions()
  local raw = { SafeCall(GetProfessions or function() end) }
  local parts = {}
  for i = 1, 6 do parts[#parts + 1] = tostring(raw[i]) end
  Print("GetProfessions: " .. table.concat(parts, ", ") .. (trusted and "  (trusted)" or "  (not trusted yet: nothing is cleared, nothing is 'browse')"))
  for _, p in ipairs(self.PROFESSIONS) do
    local o = own[p.key]
    Print(string.format("%s (skill line %d): %s, selected=%s", p.key, p.skillLine,
      o and string.format("yours %s/%s \"%s\"", tostring(o.rank), tostring(o.maxRank), tostring(o.name)) or "not yours",
      tostring(p.key == self:SelectedProfession())))
  end
  local store = self:KnownStore()
  local function probe(label, spells)
    local isk, isp, saved, n, sample = 0, 0, 0, 0, {}
    local sp = store[label.prof] or EMPTY
    for id in pairs(spells) do
      n = n + 1
      local a = C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, id)
      local b = IsPlayerSpell and SafeCall(IsPlayerSpell, id)
      if a and not IsSecret(a) then isk = isk + 1 end
      if b and not IsSecret(b) then isp = isp + 1 end
      if sp[id] then saved = saved + 1 end
      if (a or b) and #sample < 3 then sample[#sample + 1] = id end
    end
    Print(string.format("  %s: %d in data, IsSpellKnown %d, IsPlayerSpell %d, saved %d%s", label.text, n, isk, isp, saved,
      #sample > 0 and (" (e.g. " .. table.concat(sample, ", ") .. ")") or ""))
  end
  for _, p in ipairs(self.PROFESSIONS) do
    if own[p.key] or not trusted then
      probe({ prof = p.key, text = p.key .. " item recipes" }, self:RecipeTable(p.key))
      if p.key == "Enchanting" then probe({ prof = p.key, text = "Enchanting enchant spells" }, self:EnchantData().bySpell) end
    end
  end
  local api = C_TradeSkillUI
  if api and api.GetAllRecipeIDs then
    local ids = SafeCall(api.GetAllRecipeIDs)
    if type(ids) == "table" then
      local items, enchants, learned = 0, 0, 0
      local ench = self:EnchantData().bySpell
      for _, id in ipairs(ids) do
        local isEnch = ench[id] ~= nil
        local isItem = false
        for _, p in ipairs(self.PROFESSIONS) do if self:RecipeTable(p.key)[id] then isItem = true end end
        if isEnch then enchants = enchants + 1 elseif isItem then items = items + 1 end
        if (isEnch or isItem) and api.GetRecipeInfo then
          local info = SafeCall(api.GetRecipeInfo, id)
          if type(info) == "table" and info.learned and not IsSecret(info.learned) then learned = learned + 1 end
        end
      end
      Print(string.format("C_TradeSkillUI.GetAllRecipeIDs: %d IDs (open window), %d item recipes + %d enchants in our data, %d learned", #ids, items, enchants, learned))
    else
      Print("C_TradeSkillUI.GetAllRecipeIDs: no list (open a profession window and run this again)")
    end
  else
    Print("C_TradeSkillUI.GetAllRecipeIDs: not available")
  end
  if GetNumTradeSkills then
    local n = SafeCall(GetNumTradeSkills)
    local line = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
    local rl = GetTradeSkillRecipeLink and SafeCall(GetTradeSkillRecipeLink, 1)
    Print(string.format("Legacy trade skill window: line %s, %s rows, recipe link 1 = %s", tostring(line), tostring(n), tostring(rl)))
  end
  Print(string.format("Known counts: %s", (function()
    local t = {}
    for _, p in ipairs(self.PROFESSIONS) do t[#t + 1] = p.key .. "=" .. (self.knownCounts[p.key] or 0) end
    return table.concat(t, ", ")
  end)()))
end

---------------------------------------------------------------------------
-- /gca enchant debug [item link] (G7.9): does GetItemStats on an enchanted link include the enchant?
---------------------------------------------------------------------------
function GCA:EnchantDebug(link)
  local links = {}
  if link and link:find("item:", 1, true) then links[1] = link
  else
    for _, slot in ipairs(self.SYNC_SLOTS) do
      local l = SafeCall(GetInventoryItemLink, "player", slot)
      if type(l) == "string" and not IsSecret(l) and self:EnchantIDOf(l) then links[#links + 1] = l end
    end
  end
  if #links == 0 then Print("No enchanted item found. Usage: " .. (GCA.CMD or "/gca") .. " enchant debug [shift-click an enchanted item]") return end
  local data = self:EnchantData()
  local function canon(l)
    local raw = SafeCall(ItemAPI.Stats, l)
    if type(raw) ~= "table" or IsSecret(raw) then return nil end
    return (Scoring.normalize(raw))
  end
  for _, l in ipairs(links) do
    local id = self:EnchantIDOf(l)
    local row = id and data.byEnchant[id]
    local a, b = canon(l), canon(self:WithoutEnchant(l))
    local diff = {}
    if a and b then
      local keys = {}
      for k in pairs(a) do keys[k] = true end
      for k in pairs(b) do keys[k] = true end
      for k in pairs(keys) do
        local d = (a[k] or 0) - (b[k] or 0)
        if math.abs(d) > 1e-9 then diff[#diff + 1] = string.format("%s%+g", k, d) end
      end
      table.sort(diff)
    end
    local verdict
    if not (a and b) then verdict = "stats not loaded yet, try again"
    elseif #diff == 0 then verdict = "NOT included (enchanted and plain link give the same stats)"
    else verdict = "INCLUDED: " .. table.concat(diff, ", ") end
    Print(string.format("%s enchant %s = %s: %s", l, tostring(id),
      row and (row.name .. " [" .. row.kind .. "]") or "|cffff8800not in our table (no suggestion for this slot)|r", verdict))
  end
  Print("Enchant suggestions always score the item without its enchant (link field 2 blanked), so both cases are handled.")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Ravenquill Expedition (user decision): with the suite core installed this addon is its module "Craft" and
-- answers to "/rq craft ..." only (no /gca). Without the core, /gca and /guildcraft stay so it remains usable.
-- The texts that name the command ("/gca ...") are rewritten to the active command once, here.
local RQ = _G.RavenquillExpedition
GCA.onCore = type(RQ) == "table" and type(RQ.NewModule) == "function"
GCA.CMD = GCA.onCore and "/rq craft" or "/gca"
if GCA.onCore then
  -- K15: on the core most commands are gone (options live in /rq craft), so the texts that point to a command have
  -- their own core variant KEY_RQ (EMPTY_NOGEAR, HELP_LINES, WHISPER_DRAFT_KEPT, CMD_HELP, MSG_RECORDED,
  -- SYNC_STOPPED_MSG). Any other text still naming "/gca" is rewritten as a last resort.
  for _, t in pairs(ns.Locales or {}) do
    if type(t) == "table" then
      local swap = {}
      for k, v in pairs(t) do
        local base = type(k) == "string" and k:match("^(.+)_RQ$")
        if base and type(v) == "string" then swap[base] = v end
      end
      for k, v in pairs(swap) do t[k] = v end
      for k, v in pairs(t) do
        if type(v) == "string" and v:find("/gca", 1, true) then t[k] = (v:gsub("/gca", "/rq craft")) end
      end
    end
  end
else
  SLASH_GUILDCRAFTADVISOR1 = "/gca"
  SLASH_GUILDCRAFTADVISOR2 = "/guildcraft"
end
SlashCmdList.GUILDCRAFTADVISOR = function(msg)
  local raw = (msg or ""):match("^%s*(.-)%s*$")
  msg = raw:lower()
  if msg:match("^stats%s") or msg == "stats" then GCA:StatsDebug(raw:match("^%S+%s+(.+)$"))
  elseif msg == "spec debug" then GCA:SpecDebug()
  elseif msg == "known debug" then GCA:KnownDebug()
  elseif msg:match("^enchant debug") then GCA:EnchantDebug(raw:match("^%S+%s+%S+%s+(.+)$"))
  elseif msg == "spec inspect on" or msg == "spec inspect off" then
    GCA.db.settings.inspectTalents = msg == "spec inspect on"
    GCA:InvalidateScores()
    Print(GCA.db.settings.inspectTalents and L.CMD_INSPECT_TALENTS_ON or L.CMD_INSPECT_TALENTS_OFF)
  elseif msg == "inspect" then GCA:InspectTarget()
  elseif msg == "scan" then GCA:ScanGroup()
  elseif msg == "sync" then
    if GCA.SyncStatus then GCA:SyncStatus() else Print(L.CMD_SYNC_NOT_LOADED) end
  elseif msg == "sync retry" then
    if GCA.Sync and not GCA.Sync.stopped then Print(L.CMD_SYNC_NOT_PAUSED) end -- K0/L7
    if GCA.SyncRetry then GCA:SyncRetry() end
  elseif msg == "minimap debug" then
    if GCA.MinimapDebug then GCA:MinimapDebug() end
  elseif msg == "minimap reset" then
    GCA.db.settings.minimapDragged = nil
    if GCA.MinimapAutoPlace then GCA:MinimapAutoPlace() end
    Print(string.format(L.CMD_MM_MOVED, GCA.db.settings.minimapAngle or 0))
  elseif msg == "minimap" then
    GCA.db.settings.minimapHide = not GCA.db.settings.minimapHide
    GCA:UpdateMinimapButton()
    Print(GCA.db.settings.minimapHide and L.CMD_MM_HIDDEN or L.CMD_MM_SHOWN)
  elseif msg == "whisper" then
    if GCA.UI and GCA.UI.OpenWhisperEditor then GCA.UI:OpenWhisperEditor() end
  elseif msg == "verbose" then
    GCA.verbose = not GCA.verbose
    Print(GCA.verbose and L.CMD_VERBOSE_ON or L.CMD_VERBOSE_OFF)
  elseif msg == "reset" then
    wipe(GCA.db.members)
    GCA:CaptureSelf()
    Print(L.CMD_RESET)
  elseif msg == "help" then
    Print(L.CMD_HELP)
  else
    GCA.UI:Toggle()
  end
end

function RavenquillExpedition_CraftAdvisor_OnCompartmentClick() GCA.UI:Toggle() end
GuildCraftAdvisor_OnCompartmentClick = RavenquillExpedition_CraftAdvisor_OnCompartmentClick -- old name (core overview of older cores)

---------------------------------------------------------------------------
-- K15: Capture(fn, ...) runs fn with the global print replaced and returns what it printed as plain lines
-- (colour codes and our "GuildCraft:" prefix stripped, one entry per line). print is restored in every case
-- (pcall); an error becomes the last line. Used for the read-only copy boxes in the core's options view.
---------------------------------------------------------------------------
local function PlainLine(s)
  s = s:gsub("|c[nN][^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return (s:gsub("^GuildCraft:%s*", ""))
end
function GCA.Capture(fn, ...)
  local lines, orig = {}, _G.print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      parts[#parts + 1] = IsSecret(v) and "?" or tostring(v)
    end
    for line in (table.concat(parts, " ") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = PlainLine(line) end
  end
  local ok, err
  if type(fn) == "function" then ok, err = pcall(fn, ...) else ok, err = false, "not available" end
  _G.print = orig
  if not ok then lines[#lines + 1] = "error: " .. PlainLine(tostring(err)) end
  return lines
end

-- open (never close) our window: the core's "Open" row button, the options' "Open window", "/rq craft <other>"
function GCA:OpenWindow()
  local UI = self.UI
  if not UI then return end
  if UI.frame and UI.frame:IsShown() then return end
  UI:Toggle()
end

-- K15: every option in the core's /rq UI (contract: RavenquillExpedition Overview.lua / dev/PLAN.md 2b).
-- get/disabled are re-read when the view shows and after each change; lines() runs when its box is opened.
local function Settings() return GCA.db and GCA.db.settings end
local function RefreshUI() if GCA.UI and GCA.UI.Refresh then GCA.UI:Refresh() end end
local function SettingToggle(key, label, tip)
  return { type = "toggle", label = L[label], tooltip = tip and L[tip] or nil,
    get = function() local s = Settings(); return s and s[key] and true or false end,
    set = function(v)
      local s = Settings()
      if not s or (s[key] and true or false) == (v and true or false) then return end
      if GCA.UI and GCA.UI.ToggleSetting then GCA.UI.ToggleSetting(key) else s[key] = v and true or false end
    end }
end
function GCA:BuildOptions()
  local a, b = ns.G("SPELL_STAT3_NAME"), ns.G("SPELL_STAT5_NAME")
  return {
    { type = "header", label = L.OPT_H_SUGGEST },
    SettingToggle("showUnlearned", "FILTER_UNLEARNED", "FILTER_UNLEARNED_TIP"),
    SettingToggle("lookahead", "FILTER_LOOKAHEAD", "FILTER_LOOKAHEAD_TIP"),
    { type = "range", label = string.format(L.OPT_SURVIVAL, a, b), tooltip = string.format(L.SLIDER_TIP, a, b),
      min = 0, max = 100, step = 5, format = "%d %%",
      get = function() return math.floor(GCA:SurvivalShare() * 100 + 0.5) end,
      set = function(v)
        v = tonumber(v)
        local s = Settings()
        if not (v and s) then return end
        v = math.max(0, math.min(100, v))
        if GCA.UI and GCA.UI.SetSurvival then GCA.UI.SetSurvival(v)
        elseif math.abs(GCA:SurvivalShare() * 100 - v) >= 0.5 then s.survival = v / 100; GCA:InvalidateScores() end
      end },

    { type = "header", label = L.OPT_H_GEAR },
    SettingToggle("autoInspect", "FILTER_AUTOINSPECT", "FILTER_AUTOINSPECT_TIP"),
    { type = "toggle", label = L.OPT_INSPECT_TALENTS, tooltip = L.OPT_INSPECT_TALENTS_TIP,
      get = function() local s = Settings(); return s and s.inspectTalents and true or false end,
      set = function(v)
        local s = Settings()
        if not s then return end
        s.inspectTalents = v and true or false
        GCA:InvalidateScores()
        RefreshUI()
      end },
    { type = "button", label = L.OPT_INSPECT_NOW, tooltip = L.OPT_INSPECT_NOW_TIP,
      func = function() if GCA.db then GCA:InspectTarget() end end },
    { type = "button", label = L.OPT_SCAN_NOW, tooltip = L.OPT_SCAN_NOW_TIP,
      func = function() if GCA.db then GCA:ScanGroup() end end },
    { type = "button", label = L.OPT_RESET, tooltip = L.OPT_RESET_TIP,
      func = function()
        if not GCA.db then return end
        wipe(GCA.db.members)
        GCA:CaptureSelf()
        Print(L.CMD_RESET)
        RefreshUI()
      end },

    { type = "header", label = L.OPT_H_SYNC },
    SettingToggle("sync", "FILTER_SYNC", "FILTER_SYNC_TIP"),
    { type = "button", label = L.OPT_SYNC_RETRY, tooltip = L.OPT_SYNC_RETRY_TIP,
      disabled = function() return not (GCA.SyncState and GCA:SyncState() == "paused") end,
      func = function() if GCA.SyncRetry then GCA:SyncRetry() end; RefreshUI() end },
    { type = "text", label = L.OPT_SYNC_STATUS,
      lines = function()
        if not GCA.SyncStatus then return { L.CMD_SYNC_NOT_LOADED } end
        return GCA.Capture(GCA.SyncStatus, GCA)
      end },

    { type = "header", label = L.OPT_H_WINDOW },
    { type = "button", label = L.OPT_OPEN, func = function() GCA:OpenWindow() end },
    { type = "toggle", label = L.OPT_MINIMAP,
      get = function() local s = Settings(); return s and not s.minimapHide or false end,
      set = function(v)
        local s = Settings()
        if not s then return end
        s.minimapHide = not v
        if GCA.UpdateMinimapButton then GCA:UpdateMinimapButton() end
      end },
    { type = "button", label = L.OPT_MM_RESET, tooltip = L.OPT_MM_RESET_TIP,
      disabled = function() local s = Settings(); return not s or s.minimapHide and true or false end,
      func = function()
        local s = Settings()
        if not s then return end
        s.minimapDragged = nil
        if GCA.MinimapAutoPlace then GCA:MinimapAutoPlace() end
        Print(string.format(L.CMD_MM_MOVED, s.minimapAngle or 0))
      end },
    { type = "button", label = L.EDIT_WHISPER, tooltip = L.EDIT_WHISPER_TIP,
      func = function() if GCA.UI and GCA.UI.OpenWhisperEditor then GCA.UI:OpenWhisperEditor() end end },

    { type = "header", label = L.OPT_H_DIAG },
    { type = "toggle", label = L.OPT_VERBOSE, tooltip = L.OPT_VERBOSE_TIP,
      get = function() return GCA.verbose and true or false end,
      set = function(v) GCA.verbose = v and true or false end },
    { type = "text", label = L.OPT_DIAG_SPEC, lines = function() return GCA.Capture(GCA.SpecDebug, GCA) end },
    { type = "text", label = L.OPT_DIAG_KNOWN, lines = function() return GCA.Capture(GCA.KnownDebug, GCA) end },
    { type = "text", label = L.OPT_DIAG_MINIMAP, lines = function() return GCA.Capture(GCA.MinimapDebug, GCA) end },
    { type = "text", label = L.OPT_DIAG_ERROR,
      lines = function()
        local e = GCA.db and GCA.db.lastError
        if type(e) ~= "table" then return { L.OPT_NO_ERROR } end
        local out = { tostring(e.at or "?") .. "  " .. tostring(e.where or "?") }
        for line in (tostring(e.msg or "") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = PlainLine(line) end
        return out
      end },
  }
end

-- "/rq craft <args>" on the core: only the commands that need an item link stay in chat ("stats <link>",
-- "enchant debug [link]"); anything else opens our window. ("/rq craft" alone shows our options in the core's window.)
function GCA:CoreSlash(rest)
  local raw = (type(rest) == "string" and rest or ""):match("^%s*(.-)%s*$")
  local low = raw:lower()
  if low == "stats" or low:match("^stats%s") or low:match("^enchant%s+debug") then
    SlashCmdList.GUILDCRAFTADVISOR(raw)
  else
    self:OpenWindow()
  end
end

-- Ravenquill Expedition module (like RavenquillExpedition_Map): "/rq craft" opens our options in the core's
-- window, "/rq craft <args>" reaches CoreSlash; the core's overview lists us as a module ("Open" = our window).
-- Folder, SavedVariables and our own GCAdv1 sync stay unchanged.
if GCA.onCore then
  local okOpt, options = pcall(GCA.BuildOptions, GCA)
  local ok, mod = pcall(RQ.NewModule, RQ, "Craft", {
    addon = ADDON, slash = "craft", title = ns.LGet("ADDON_TITLE") or "Guild Craft Advisor",
    icon = "Interface\\Icons\\Trade_LeatherWorking",
    options = okOpt and options or nil,
    OnSlash = function(_, rest) GCA:CoreSlash(rest) end,
    -- the core's overview (Overview.lua OverviewRows): Open() for its row button, OverviewStatus() for its status
    Open = function() GCA:OpenWindow() end,
    OverviewStatus = function()
      local v = GCA.SyncStatusLine and SafeCall(GCA.SyncStatusLine, GCA)
      return type(v) == "string" and not IsSecret(v) and v or nil
    end,
  })
  GCA.rqModule = ok and mod or nil
end
