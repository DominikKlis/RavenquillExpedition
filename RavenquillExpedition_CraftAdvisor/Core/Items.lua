local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local priv = GCA.priv
local IsSecret, SafeCall, ItemAPI, ItemIDFrom = priv.IsSecret, priv.SafeCall, priv.ItemAPI, priv.ItemIDFrom

---------------------------------------------------------------------------
-- Weights (SimGear Forever data, Data/Weights.lua) and the pure scoring code (Scoring.lua)
---------------------------------------------------------------------------
local Scoring = ns.Scoring
GCA.Scoring = Scoring
GCA.MIN_PCT = 0.01      -- an upgrade needs +1 % of the equipped item's score (a noise filter, never displayed)
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
    -- score cache key: (spec, bracket, survival share) (+ fade step, which changes the set too)
    key = class .. "/" .. spec .. "#" .. rawIdx .. "/" .. refIdx .. "@" .. share .. "~" .. string.format("%.3f", (ref and set ~= raw) and t or 1),
  }
  self.wsCache[ck] = e
  return e
end

local UNIT_SHORT = { AttackPower = "AP", RangedAttackPower = "RAP", SpellPower = "SP", HealingPower = "HP" }
-- "AP" = worth as much as that much Attack Power (score ÷ the set's unit-stat weight); "pts" without a unit stat
function GCA:UnitLabel(e) return e and e.unitW and (UNIT_SHORT[e.unit] or e.unit) or "pts" end
function GCA:ToPoints(e, v) return e and e.unitW and v / e.unitW or v end

-- "SimGear Forever 0.14.0 · Feral (Cat) Lv40 · simmed · leveling bonus 50%" (localized; the survival
-- layer is called "leveling bonus" in the UI)
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
-- (SimGear speedValue); everything else is stats x weights.
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

-- shared with the files loaded after this one (priv)
priv.Scoring = Scoring
