-- Scoring: item stats -> canonical stats -> score with SimGear Forever's weights.
-- Pure: no WoW API access, so the offline harness can run it next to SimGear's own code.
--
-- Parts of this file are ported from SimGear Forever 0.14.0 (Stats.lua, Score.lua, Plan.lua):
--   Copyright (c) 2026 Flavius and SimGear Forever contributors
--   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
--   associated documentation files (the "Software"), to deal in the Software without restriction,
--   including without limitation the rights to use, copy, modify, merge, publish, distribute,
--   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
--   furnished to do so, subject to the following conditions: The above copyright notice and this
--   permission notice shall be included in all copies or substantial portions of the Software.
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
--   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
--   OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
--   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- See NOTICE.txt. Differences from SimGear are marked "GCA:".
local _, ns = ...

local Scoring = {}
ns.Scoring = Scoring

---------------------------------------------------------------------------
-- Stats (SimGear Stats.lua)
---------------------------------------------------------------------------
-- GetItemStats key -> canonical key (SimGear Stats.KEY_MAP, keys confirmed in game by SimGear).
Scoring.KEY_MAP = {
  ITEM_MOD_STRENGTH_SHORT = "Strength",
  ITEM_MOD_AGILITY_SHORT = "Agility",
  ITEM_MOD_STAMINA_SHORT = "Stamina",
  ITEM_MOD_INTELLECT_SHORT = "Intellect",
  ITEM_MOD_SPIRIT_SHORT = "Spirit",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense",
  ITEM_MOD_DODGE_RATING_SHORT = "Dodge",
  ITEM_MOD_PARRY_RATING_SHORT = "Parry",
  ITEM_MOD_BLOCK_RATING_SHORT = "Block",
  ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
  SHIELD_BLOCK = "BlockValue", -- never in GetItemStats (SimGear reads it from the tooltip); GCA: not read yet
  ITEM_MOD_CRIT_RATING_SHORT = "Crit",
  ITEM_MOD_HIT_RATING_SHORT = "Hit",
  ITEM_MOD_ATTACK_POWER_SHORT = "AttackPower",
  ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RangedAttackPower",
  ITEM_MOD_SPELL_POWER_SHORT = "SpellPower",
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellPower",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HealingPower",
  ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "HolyPower",
  ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "ShadowPower",
  ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "FirePower",
  ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "FrostPower",
  ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "ArcanePower",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Dps",
  RESISTANCE0_NAME = "Armor",
  ITEM_MOD_SPELL_POWER = "SpellPower",
}
Scoring.SAME_AS = { ITEM_MOD_SPELL_POWER = "ITEM_MOD_SPELL_POWER_SHORT" }
-- Rating per percentage point (Forever stores "+1%" as ratings; SimGear Stats.RATING_PER_POINT).
Scoring.RATING_PER_POINT = { Crit = 14, Hit = 10, Dodge = 12, Parry = 15, Block = 5 }
Scoring.EXPANDS = { Crit = { "MeleeCrit", "SpellCrit" }, Hit = { "MeleeHit", "SpellHit" } }

-- raw GetItemStats table -> canonical stats, sorted list of unmapped client keys.
function Scoring.normalize(raw)
  local keyMap, perPoint = Scoring.KEY_MAP, Scoring.RATING_PER_POINT
  local stats, unknown = {}, {}
  for key, amount in pairs(raw or {}) do
    local canonical = keyMap[key]
    local twin = Scoring.SAME_AS[key]
    if twin and raw[twin] ~= nil then
      -- counted under its other name
    elseif canonical and type(amount) == "number" then
      stats[canonical] = (stats[canonical] or 0) + amount
    else
      unknown[#unknown + 1] = tostring(key)
    end
  end
  for canonical, per in pairs(perPoint) do
    if stats[canonical] then stats[canonical] = stats[canonical] / per end
  end
  for key, targets in pairs(Scoring.EXPANDS) do
    local amount = stats[key]
    if amount then
      stats[key] = nil
      for _, target in ipairs(targets) do stats[target] = (stats[target] or 0) + amount end
    end
  end
  table.sort(unknown)
  return stats, unknown
end

local DPS_KEY_BY_EQUIPLOC = {
  INVTYPE_2HWEAPON = "TwoHandDps", INVTYPE_WEAPON = "MainHandDps", INVTYPE_WEAPONMAINHAND = "MainHandDps",
  INVTYPE_WEAPONOFFHAND = "OffHandDps",
  INVTYPE_RANGED = "RangedDps", INVTYPE_RANGEDRIGHT = "RangedDps", INVTYPE_THROWN = "RangedDps",
}
-- Moves the intermediate "Dps" stat to the per-hand stat for this equip location (changes stats in place).
function Scoring.addWeaponDps(stats, equipLoc)
  local dps = stats.Dps
  stats.Dps = nil
  local key = DPS_KEY_BY_EQUIPLOC[equipLoc or ""]
  if dps and key then stats[key] = (stats[key] or 0) + dps end
  return stats
end

-- The item as it counts in the off hand: MainHandDps weighs as OffHandDps (SimGear Score.inOffHand).
function Scoring.inOffHand(item)
  local dps = item and item.stats and item.stats.MainHandDps
  if not dps then return item end
  local stats = {}
  for k, v in pairs(item.stats) do stats[k] = v end
  stats.MainHandDps, stats.OffHandDps = nil, (stats.OffHandDps or 0) + dps
  local copy = {}
  for k, v in pairs(item) do copy[k] = v end
  copy.stats = stats
  copy.info = nil -- GCA: a cached score (Core valueOf) belongs to the main-hand stats
  return copy
end

---------------------------------------------------------------------------
-- Weight sets (SimGear Score.lua)
---------------------------------------------------------------------------
-- The set whose level range is nearest to `level`; no range = any level; tie -> lower; same level -> sim.
function Scoring.pickSet(sets, level)
  local best, bestDistance
  for _, set in ipairs(sets or {}) do
    local lo, hi = set.source.minLevel, set.source.maxLevel
    local distance = 0
    if lo and level < lo then distance = lo - level
    elseif hi and level > hi then distance = level - hi end
    local bestLo = bestDistance and (best.source.minLevel or 0)
    if not bestDistance or distance < bestDistance
      or (distance == bestDistance and ((lo or 0) < bestLo
        or ((lo or 0) == bestLo and set.source.kind == "sim" and best.source.kind ~= "sim"))) then
      best, bestDistance = set, distance
    end
  end
  return best
end

-- Spell power counts 0 on an item that also has healing when the set weighs healing (Score.weightOf).
function Scoring.weightOf(stats, key, set)
  local w = set.weights[key] or 0
  if key == "SpellPower" and (stats.HealingPower or 0) > 0 and (set.weights.HealingPower or 0) > 0 then return 0 end
  return w
end

function Scoring.value(stats, set)
  if not (set and set.weights) then return 0 end
  local total = 0
  for key, amount in pairs(stats or {}) do
    total = total + amount * Scoring.weightOf(stats, key, set)
  end
  return total
end

---------------------------------------------------------------------------
-- Weapon speed (SimGear Score.lua:159-199 speedKind/speedFactor/speedValue, Stats.lua:143-160)
---------------------------------------------------------------------------
Scoring.SPEED_KINDS = {
  twoHand = { ref = 3.3, min = 2.8, max = 3.9 }, oneHand = { ref = 2.4, min = 1.5, max = 2.9 },
  dagger = { ref = 1.7, min = 1.3, max = 1.9 }, ranged = { ref = 2.8, min = 2.0, max = 3.2 },
}
local CURVE_OF = { MainHandDps = "mainHand", TwoHandDps = "mainHand", OffHandDps = "offHand", RangedDps = "ranged" }
-- GCA: SimGear iterates CURVE_OF with pairs (an item has one weapon-DPS key, so the order doesn't matter); a fixed
-- order keeps it deterministic.
local CURVE_KEYS = { "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }

function Scoring.speedKind(item, key)
  if key == "RangedDps" then return "ranged" end
  if item.equipLoc == "INVTYPE_2HWEAPON" then return "twoHand" end
  return item.dagger and "dagger" or "oneHand"
end

-- The multiplier on the item's `key` weapon DPS for its speed: 1 without a speed or a curve.
function Scoring.speedFactor(item, key, set)
  local curves = set and set.speedCurves
  local curve = curves and CURVE_OF[key] and curves[CURVE_OF[key]]
  local speed = item and item.speed
  if type(curve) ~= "table" or type(curve.perSecond) ~= "number" or curve.perSecond == 0
     or type(speed) ~= "number" or speed <= 0 then
    return 1
  end
  local k = Scoring.SPEED_KINDS[Scoring.speedKind(item, key)]
  return 1 + curve.perSecond * (math.min(math.max(speed, k.min), k.max) - k.ref)
end

-- What the item's speed adds to (or takes from) its value: its weapon DPS value x (factor - 1), and the key.
function Scoring.speedValue(item, set)
  local stats = item and item.stats
  if not stats or not item.speed or not (set and set.weights) then return 0 end
  for _, key in ipairs(CURVE_KEYS) do
    local dps = stats[key]
    if dps and dps > 0 then
      return dps * Scoring.weightOf(stats, key, set) * (Scoring.speedFactor(item, key, set) - 1), key
    end
  end
  return 0
end

-- A weapon's speed in seconds from tooltip lines (the damage line's right text: "Speed 2.60", deDE "Tempo 2,60"),
-- or nil. label = the client's SPEED; "Speed" is always tried too. Callers pass no secret text.
function Scoring.weaponSpeedFromLines(lines, label)
  local labels = { "Speed" }
  if type(label) == "string" and label ~= "Speed" and label ~= "" then table.insert(labels, 1, label) end
  for _, line in ipairs(lines or {}) do
    local text = type(line) == "table" and line.rightText
    if type(text) == "string" then
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      for _, l in ipairs(labels) do
        local amount = text:match("^" .. (l:gsub("%p", "%%%0")) .. "%s+(%d+[%.,]?%d*)$")
        local n = amount and tonumber((amount:gsub(",", ".")))
        if n and n > 0 and n < 10 then return n end
      end
    end
  end
end

-- GCA: SimGear's itemValue also adds simmed trinket effects (stripped from our data: 0 here).
local function itemValue(item, set)
  if not item then return 0 end
  return Scoring.value(item.stats, set) + Scoring.speedValue(item, set)
end
-- GCA: compare() may get a valueOf(item) that returns a cached score (Core: per item and weight set).
local valueOf
local function val(item, set)
  if not item then return 0 end
  if valueOf then
    local v = valueOf(item)
    if v then return v end
  end
  return itemValue(item, set)
end
Scoring.itemValue = itemValue

Scoring.PLACEHOLDER_LABEL = "placeholder, not derived"
function Scoring.isPlaceholder(set)
  local src = set and set.source
  return src ~= nil and src.kind == "curated" and src.label == Scoring.PLACEHOLDER_LABEL
end

---------------------------------------------------------------------------
-- Survival layer (SimGear Plan.lua)
---------------------------------------------------------------------------
Scoring.FADE_FROM, Scoring.FADE_TO = 50, 58

-- 0..1: how far the handover to the raid sim has gone at a level (no "preparing for raids" option here).
function Scoring.handover(level)
  if not level then return 0 end
  local t = (level - Scoring.FADE_FROM) / (Scoring.FADE_TO - Scoring.FADE_FROM)
  return math.max(0, math.min(1, t))
end

-- The set with a `survival` table nearest to the level (pickSet's rule), or nil.
function Scoring.leveling(sets, level)
  local with = {}
  for _, set in ipairs(sets or {}) do
    if set.survival and next(set.survival) then with[#with + 1] = set end
  end
  return with[1] and Scoring.pickSet(with, level or 1) or nil
end

-- GCA: SimGear derives this from `derivation` (stripped); the generator stores the result as `unit`.
function Scoring.unitKey(set)
  return set and set.unit or nil
end

local function scaleOf(set, ref)
  if set == ref then return 1 end
  local unit = Scoring.unitKey(ref)
  local w = unit and set.weights[unit]
  if w and w > 0 then return w end
end
Scoring.scaleOf = scaleOf

local function copySet(set)
  local out = {}
  for k, v in pairs(set) do out[k] = v end
  out.weights, out.source = {}, {}
  for k, v in pairs(set.weights) do out.weights[k] = v end
  for k, v in pairs(set.source or {}) do out.source[k] = v end
  return out
end

local applied = setmetatable({}, { __mode = "k" })

-- `set` minus its own survival layer plus ref's x share x (1 - t) x scale (SimGear Plan.apply).
function Scoring.apply(set, ref, share, t)
  if not (set and set.weights) then return set end
  local own = set.survival
  local keep = (1 - (t or 0)) * (share or 1)
  local scale = ref and scaleOf(set, ref)
  if not own and (not scale or (t or 0) >= 1) then return set end
  local key = tostring(ref) .. "|" .. keep
  local byKey = applied[set]
  if byKey and byKey[key] then return byKey[key] end
  local out = copySet(set)
  for k, v in pairs(own or {}) do out.weights[k] = (out.weights[k] or 0) - v end
  local added = {}
  if scale and keep > 0 then
    for k, v in pairs(ref.survival) do
      added[k] = v * keep * scale
      out.weights[k] = (out.weights[k] or 0) + added[k]
    end
  end
  for k, w in pairs(out.weights) do
    if math.abs(w) < 1e-12 then out.weights[k] = 0 end
  end
  out.survival = nil
  out.source.plan = { share = share or 1, t = t or 0, added = added }
  applied[set] = byKey or {}
  applied[set][key] = out
  return out
end

---------------------------------------------------------------------------
-- Item sets (SimGear Score.setChanges)
---------------------------------------------------------------------------
-- itemSets: [setID] = { name, items, bonuses }; returns { bySet, ofItem } as SimGear's Data.lua builds it.
function Scoring.buildSets(itemSets)
  local ofItem = {}
  for setID, set in pairs(itemSets or {}) do
    for _, id in ipairs(set.items or {}) do ofItem[id] = setID end
  end
  return { bySet = itemSets or {}, ofItem = ofItem }
end

local function piecesOf(ids, sets)
  local seen, count = {}, {}
  for _, id in ipairs(ids) do
    local set = id and not seen[id] and sets.ofItem[id]
    if set then
      seen[id] = true
      count[set] = (count[set] or 0) + 1
    end
  end
  return count
end
Scoring.piecesOf = piecesOf

function Scoring.setChanges(before, after, sets, set)
  local a, b = piecesOf(before, sets), piecesOf(after, sets)
  local ids = {}
  for id in pairs(a) do ids[id] = true end
  for id in pairs(b) do ids[id] = true end
  local delta, changes = 0, {}
  for setID in pairs(ids) do
    local s, was, now = sets.bySet[setID], a[setID] or 0, b[setID] or 0
    if s and was ~= now then
      local c = { id = setID, name = s.name, size = #(s.items or {}), worn = was, after = now, gained = {}, lost = {}, value = 0 }
      for _, bonus in ipairs(s.bonuses or {}) do
        local v = Scoring.value(bonus.stats, set)
        if now >= bonus.n and was < bonus.n then
          c.gained[#c.gained + 1], c.value = bonus, c.value + v
        elseif was >= bonus.n and now < bonus.n then
          c.lost[#c.lost + 1], c.value = bonus, c.value - v
        end
      end
      if #c.gained + #c.lost > 0 then
        changes[#changes + 1] = c
        delta = delta + c.value
      end
    end
  end
  table.sort(changes, function(x, y) return x.name < y.name end)
  return delta, changes
end

---------------------------------------------------------------------------
-- Compare (SimGear Score.compareLinear + compareWeapon + applySets)
---------------------------------------------------------------------------
local SINGLE = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
  INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
  INVTYPE_CLOAK = 15, INVTYPE_RELIC = 18,
  INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18,
}
local PAIRED = { INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }
local MAIN_HAND_TYPES = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_HAND_TYPES = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
Scoring.MAIN_HAND_TYPES, Scoring.OFF_HAND_TYPES = MAIN_HAND_TYPES, OFF_HAND_TYPES

-- Adds pct and status. A preset status ("needs-partner") is kept, but pct is still filled in (SimGear finish).
local function finish(result)
  if result.oldValue <= 0 then
    result.status = result.status or "no-baseline"
    return result
  end
  result.pct = (result.newValue - result.oldValue) / result.oldValue
  result.status = result.status or (result.pct > 0 and "upgrade" or "downgrade")
  return result
end

local function isTwoHand(item) return item ~= nil and item.equipLoc == "INVTYPE_2HWEAPON" end

-- The main hand + off hand pair (SimGear Score.compareWeapon): a two-hander against both worn hands; a one-hander or
-- off hand against a worn two-hander is scored alone, status "needs-partner" (SimGear takes the best partner from
-- your bags; GCA can't see a guildie's bags, so there never is one). opts.dualWield: a one-hander
-- (INVTYPE_WEAPON) may also replace the off hand; opts.hand "main"/"off" picks the hand, otherwise the better of the
-- two (result.hand = "off" when used).
local function compareWeapon(candidate, equipped, set, opts)
  local mh, oh = equipped[16], equipped[17]
  local cand = val(candidate, set)
  local ohValue = val(Scoring.inOffHand(oh), set)
  local result = { replaces = { 16, 17 }, oldValue = val(mh, set) + ohValue }
  local loc = candidate.equipLoc
  if loc == "INVTYPE_2HWEAPON" then
    result.newValue = cand
  elseif MAIN_HAND_TYPES[loc] then
    result.replaces = { 16 }
    if isTwoHand(mh) then
      result.newValue, result.status = cand, "needs-partner"
    else
      local asMain = cand + ohValue
      local asOff = opts.dualWield and loc == "INVTYPE_WEAPON" and val(mh, set) + val(Scoring.inOffHand(candidate), set) or nil
      if asOff and (opts.hand == "off" or (opts.hand ~= "main" and asOff > asMain)) then
        result.replaces, result.newValue, result.hand = { 17 }, asOff, "off"
      else
        result.newValue = asMain
      end
    end
  elseif OFF_HAND_TYPES[loc] then
    result.replaces = { 17 }
    if isTwoHand(mh) then
      result.replaces = { 16 }
      result.newValue, result.status = cand, "needs-partner"
    else
      result.newValue = val(mh, set) + val(Scoring.inOffHand(candidate), set)
    end
  else
    return nil
  end
  return finish(result)
end

local function compareLinear(candidate, equipped, set, opts)
  local loc = candidate.equipLoc
  for _, item in pairs(equipped) do
    if item.itemID ~= nil and item.itemID == candidate.itemID then
      return { status = "equipped", newValue = val(candidate, set), oldValue = val(item, set) }
    end
  end
  local slot = SINGLE[loc]
  if slot then
    local current = equipped[slot]
    if not current then
      return { status = "empty-slot", replaces = { slot }, newValue = val(candidate, set), oldValue = 0 }
    end
    return finish({ replaces = { slot }, newValue = val(candidate, set), oldValue = val(current, set) })
  end
  local pair = PAIRED[loc]
  if pair then
    local a, b = equipped[pair[1]], equipped[pair[2]]
    local newValue = val(candidate, set)
    if not a or not b then
      return { status = "empty-slot", replaces = { a and pair[2] or pair[1] }, newValue = newValue, oldValue = 0 }
    end
    local va, vb = val(a, set), val(b, set)
    local weaker, weakerValue = pair[1], va
    if vb < va then weaker, weakerValue = pair[2], vb end
    return finish({ replaces = { weaker }, newValue = newValue, oldValue = weakerValue })
  end
  return compareWeapon(candidate, equipped, set, opts or {})
end

-- candidate/equipped items: { itemID, equipLoc, stats (canonical), speed?, dagger? }; equipped: slot -> item.
-- sets: Scoring.buildSets(...) or nil; valueFn(item): optional cached item score (nil = compute);
-- opts: { dualWield = bool, hand = "main"|"off"|nil } (SimGear's opts without bags, hit and effects).
-- Returns SimGear's result shape: { status, pct, newValue, oldValue, replaces, hand, sets, setDelta } or nil when
-- the item has no slot we compare.
function Scoring.compare(candidate, equipped, set, sets, valueFn, opts)
  equipped = equipped or {}
  valueOf = valueFn
  local ok, result = pcall(compareLinear, candidate, equipped, set, opts)
  valueOf = nil
  if not ok then error(result, 0) end
  if not result or result.status == "equipped" or not sets then return result end
  local replaced = {}
  for _, slot in ipairs(result.replaces or {}) do replaced[slot] = true end
  local before, after = {}, {}
  for slot, item in pairs(equipped) do
    before[#before + 1] = item.itemID
    if not replaced[slot] then after[#after + 1] = item.itemID end
  end
  after[#after + 1] = candidate.itemID
  local delta, changes = Scoring.setChanges(before, after, sets, set)
  if #changes == 0 then return result end
  result.sets, result.setDelta = changes, delta
  if delta == 0 then return result end
  result.newValue = result.newValue + delta
  if result.status ~= "empty-slot" then
    if result.status ~= "needs-partner" then result.status = nil end
    result.pct = nil
    finish(result)
  end
  return result
end

return Scoring
