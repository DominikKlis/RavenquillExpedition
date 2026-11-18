local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local SafeCall, Plain, ItemAPI, ItemIDFrom = GCA.SafeCall, GCA.Plain, GCA.ItemAPI, GCA.ItemIDFrom

local Scoring = ns.Scoring
GCA.Scoring = Scoring
GCA.MIN_PCT = 0.01
GCA.MIN_POINTS = 0.05
GCA.SURVIVAL_DEFAULT = 0.5

function GCA:ItemSets()
  if not self.itemSets then self.itemSets = Scoring.buildSets(ns.Weights and ns.Weights.itemSets) end
  return self.itemSets
end

function GCA:SurvivalShare()
  local v = self.db and self.db.settings.survival
  if type(v) ~= "number" then return self.SURVIVAL_DEFAULT end
  return math.max(0, math.min(1, v))
end

local function SpecSets(W, class, spec)
  local sets = W.classes[class] and W.classes[class][spec]
  if sets and sets[1] then return sets end
end

local function IndexOf(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
  return 0
end

local function UnitWeight(raw)
  local w = raw.unit and raw.weights[raw.unit]
  if w and w > 0 then return w end
end

local function WeightSetKey(e, sets)
  local fade = (e.ref and e.set ~= e.raw) and e.t or 1
  return e.class .. "/" .. e.spec .. "#" .. IndexOf(sets, e.raw) .. "/" .. IndexOf(sets, e.ref) .. "@" .. e.share .. "~"
    .. string.format("%.3f", fade)
end

GCA.wsCache = {}
function GCA:WeightSetFor(class, spec, level)
  local W = ns.Weights
  if not (W and class and spec and type(level) == "number") then return nil, "no-data" end
  local share = self:SurvivalShare()
  local ck = class .. "|" .. spec .. "|" .. level .. "|" .. share
  if self.wsCache[ck] then return self.wsCache[ck] end
  local sets = SpecSets(W, class, spec)
  local raw = sets and Scoring.pickSet(sets, level)
  if not raw or next(raw.weights) == nil then return nil, "no-weights" end
  local ref, t = Scoring.leveling(sets, level), Scoring.handover(level)
  local e = { set = Scoring.apply(raw, ref, share, t), raw = raw, ref = ref, unit = raw.unit, unitW = UnitWeight(raw),
    spec = spec, class = class, level = level, share = share, t = t }
  e.key = WeightSetKey(e, sets)
  self.wsCache[ck] = e
  return e
end

local UNIT_SHORT = { AttackPower = "AP", RangedAttackPower = "RAP", SpellPower = "SP", HealingPower = "HP" }
function GCA:UnitLabel(e) return e and e.unitW and (UNIT_SHORT[e.unit] or e.unit) or "pts" end
function GCA:ToPoints(e, v) return e and e.unitW and v / e.unitW or v end

local function LevelRangeLabel(src, level)
  if not (src.minLevel and src.maxLevel) then return L.SRCL_ALL_LEVELS end
  local lv = src.minLevel == src.maxLevel and ("Lv" .. src.minLevel) or ("Lv" .. src.minLevel .. "-" .. src.maxLevel)
  if level < src.minLevel or level > src.maxLevel then lv = string.format(L.SRCL_NEAREST, lv, level) end
  return lv
end

local KIND_LABEL = { sim = "SRCL_SIMMED", measured = "SRCL_MEASURED" }
local function KindLabel(raw)
  if Scoring.isPlaceholder(raw) then return L.SRCL_ROUGH end
  local kind = raw.source.kind
  return KIND_LABEL[kind] and L[KIND_LABEL[kind]] or kind
end

local function BonusLabel(e)
  if not e.ref then return L.SRCL_NO_BONUS end
  if e.t >= 1 then return L.SRCL_FADED end
  if not e.set.source.plan then return nil end
  local s = string.format(L.SRCL_BONUS, math.floor(e.share * 100 + 0.5))
  if e.t > 0 then s = s .. string.format(L.SRCL_FADING, math.floor((1 - e.t) * 100 + 0.5)) end
  return s
end

function GCA:SourceLine(e)
  if not e then return "" end
  local W = ns.Weights
  local parts = { "SimGear Forever " .. (W and W.meta.version or "?"),
    self:SpecName(e.class, e.spec) .. " " .. LevelRangeLabel(e.raw.source, e.level), KindLabel(e.raw) }
  parts[#parts + 1] = BonusLabel(e)
  return table.concat(parts, " · ")
end

function GCA:InvalidateScores()
  wipe(self.wsCache)
  for _, info in pairs(self.infoCache or {}) do wipe(info.scores) end
  self.sugCache = {}
  if self.Invalidate then self:Invalidate() end
end

GCA.infoCache = {}

GCA.LOAD_TRIES, GCA.LOAD_RETRY, GCA.LOAD_TIMEOUT = 3, 2, 10
GCA.loadState = {}

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

function GCA:ScheduleLoadRetry()
  if self.loadRetryPending then return end
  self.loadRetryPending = true
  C_Timer.After(self.LOAD_RETRY + 0.1, function()
    self.loadRetryPending = false
    self:Invalidate()
  end)
end

local function KeptLink(itemString, apiLink)
  if type(apiLink) == "string" and apiLink:find("|H", 1, true) then return apiLink end
  return itemString or apiLink
end

local function ReadInfo(self, item)
  local name, link, quality, ilvl, minLevel, _, _, _, equipLoc, icon, _, classID, subClassID, bindType =
    SafeCall(ItemAPI.Info, item)
  if not Plain(name) then return nil end
  local itemString = type(item) == "string" and item
  local stats = SafeCall(ItemAPI.Stats, itemString or link)
  local c = {
    itemID = ItemIDFrom(item) or ItemIDFrom(link), name = name, link = KeptLink(itemString, link),
    quality = quality, ilvl = ilvl, minLevel = minLevel or 0, equipLoc = equipLoc, icon = icon,
    classID = classID, subClassID = subClassID, bind = bindType,
    stats = type(stats) == "table" and stats or {}, scores = {},
  }
  c.cstats, c.unknownStats = Scoring.normalize(c.stats)
  Scoring.addWeaponDps(c.cstats, equipLoc)
  if classID == 2 then
    c.speed = self:WeaponSpeed(c.itemID, c.link)
    c.dagger = subClassID == 15 or nil
  end
  return c
end

function GCA:GetInfo(item)
  if not item then return end
  local c = self.infoCache[item]
  if c then return c end
  c = ReadInfo(self, item)
  if not c then return nil, self:NoteMissingItem(ItemIDFrom(item)) end
  self.infoCache[item] = c
  if c.itemID then self.loadState[c.itemID] = nil end
  return c
end

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

local function TipLines(data)
  return type(data) == "table" and type(data.lines) == "table" and data.lines or nil
end

local function ItemTooltipLines(TI, itemID, link)
  local lines = TipLines(itemID and TI.GetItemByID and SafeCall(TI.GetItemByID, itemID))
  if not lines and type(link) == "string" and TI.GetHyperlink then lines = TipLines(SafeCall(TI.GetHyperlink, link)) end
  return Plain(lines)
end

GCA.speedCache = {}
function GCA:WeaponSpeed(itemID, link)
  if itemID and self.speedCache[itemID] then return self.speedCache[itemID] end
  local TI = C_TooltipInfo
  if type(TI) ~= "table" then return nil end
  local rawLines = ItemTooltipLines(TI, itemID, link)
  if not rawLines then return nil end
  local lines = {}
  for i, line in ipairs(rawLines) do lines[i] = { rightText = Plain(type(line) == "table" and line.rightText, "string") } end
  local speed = Scoring.weaponSpeedFromLines(lines, Plain(SPEED, "string"))
  if speed and itemID then self.speedCache[itemID] = speed end
  return speed
end

