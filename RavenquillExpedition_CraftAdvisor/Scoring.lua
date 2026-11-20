local _, ns = ...

local Scoring = {}
ns.Scoring = Scoring

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
  SHIELD_BLOCK = "BlockValue",
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
Scoring.RATING_PER_POINT = { Crit = 14, Hit = 10, Dodge = 12, Parry = 15, Block = 5 }
Scoring.EXPANDS = { Crit = { "MeleeCrit", "SpellCrit" }, Hit = { "MeleeHit", "SpellHit" } }

function Scoring.normalize(raw)
  local keyMap, perPoint = Scoring.KEY_MAP, Scoring.RATING_PER_POINT
  local stats, unknown = {}, {}
  for key, amount in pairs(raw or {}) do
    local canonical = keyMap[key]
    local twin = Scoring.SAME_AS[key]
    if twin and raw[twin] ~= nil then
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

local EQUIP_LOCS = {
  INVTYPE_HEAD = { slots = { 1 } }, INVTYPE_NECK = { slots = { 2 } }, INVTYPE_SHOULDER = { slots = { 3 } },
  INVTYPE_CHEST = { slots = { 5 } }, INVTYPE_ROBE = { slots = { 5 } }, INVTYPE_WAIST = { slots = { 6 } },
  INVTYPE_LEGS = { slots = { 7 } }, INVTYPE_FEET = { slots = { 8 } }, INVTYPE_WRIST = { slots = { 9 } },
  INVTYPE_HAND = { slots = { 10 } }, INVTYPE_FINGER = { slots = { 11, 12 } }, INVTYPE_TRINKET = { slots = { 13, 14 } },
  INVTYPE_CLOAK = { slots = { 15 } }, INVTYPE_RELIC = { slots = { 18 } },
  INVTYPE_RANGED = { slots = { 18 }, dps = "RangedDps" }, INVTYPE_RANGEDRIGHT = { slots = { 18 }, dps = "RangedDps" },
  INVTYPE_THROWN = { slots = { 18 }, dps = "RangedDps" },
  INVTYPE_WEAPON = { slots = { 16, 17 }, hand = "main", oneHand = true, dps = "MainHandDps", enchant = { "weapon" } },
  INVTYPE_WEAPONMAINHAND = { slots = { 16 }, hand = "main", oneHand = true, dps = "MainHandDps", enchant = { "weapon" } },
  INVTYPE_WEAPONOFFHAND = { slots = { 17 }, hand = "off", oneHand = true, dps = "OffHandDps", enchant = { "weapon" } },
  INVTYPE_2HWEAPON = { slots = { 16 }, hand = "two", dps = "TwoHandDps", enchant = { "twohand", "weapon" } },
  INVTYPE_SHIELD = { slots = { 17 }, hand = "off", enchant = { "shield" } },
  INVTYPE_HOLDABLE = { slots = { 17 }, hand = "off", enchant = { "offhand" } },
}
Scoring.EQUIP_LOCS = EQUIP_LOCS

function Scoring.addWeaponDps(stats, equipLoc)
  local dps = stats.Dps
  stats.Dps = nil
  local rule = EQUIP_LOCS[equipLoc or ""]
  local key = rule and rule.dps
  if dps and key then stats[key] = (stats[key] or 0) + dps end
  return stats
end

function Scoring.inOffHand(item)
  local dps = item and item.stats and item.stats.MainHandDps
  if not dps then return item end
  local stats = {}
  for k, v in pairs(item.stats) do stats[k] = v end
  stats.MainHandDps, stats.OffHandDps = nil, (stats.OffHandDps or 0) + dps
  local copy = {}
  for k, v in pairs(item) do copy[k] = v end
  copy.stats = stats
  copy.info = nil
  return copy
end

local function levelDistance(src, level)
  if src.minLevel and level < src.minLevel then return src.minLevel - level end
  if src.maxLevel and level > src.maxLevel then return level - src.maxLevel end
  return 0
end

local function closerSet(set, distance, best, bestDistance)
  if not best or distance ~= bestDistance then return not best or distance < bestDistance end
  local lo, bestLo = set.source.minLevel or 0, best.source.minLevel or 0
  if lo ~= bestLo then return lo < bestLo end
  return set.source.kind == "sim" and best.source.kind ~= "sim"
end

function Scoring.pickSet(sets, level)
  local best, bestDistance
  for _, set in ipairs(sets or {}) do
    local distance = levelDistance(set.source, level)
    if closerSet(set, distance, best, bestDistance) then best, bestDistance = set, distance end
  end
  return best
end

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

Scoring.SPEED_KINDS = {
  twoHand = { ref = 3.3, min = 2.8, max = 3.9 }, oneHand = { ref = 2.4, min = 1.5, max = 2.9 },
  dagger = { ref = 1.7, min = 1.3, max = 1.9 }, ranged = { ref = 2.8, min = 2.0, max = 3.2 },
}
local CURVE_OF = { MainHandDps = "mainHand", TwoHandDps = "mainHand", OffHandDps = "offHand", RangedDps = "ranged" }
local CURVE_KEYS = { "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }

function Scoring.speedKind(item, key)
  if key == "RangedDps" then return "ranged" end
  if item.equipLoc == "INVTYPE_2HWEAPON" then return "twoHand" end
  return item.dagger and "dagger" or "oneHand"
end

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

local function itemValue(item, set)
  if not item then return 0 end
  return Scoring.value(item.stats, set) + Scoring.speedValue(item, set)
end
local function val(item, ctx)
  if not item then return 0 end
  local v = ctx.valueOf and ctx.valueOf(item)
  if v then return v end
  return itemValue(item, ctx.set)
end
Scoring.itemValue = itemValue

Scoring.PLACEHOLDER_LABEL = "placeholder, not derived"
function Scoring.isPlaceholder(set)
  local src = set and set.source
  return src ~= nil and src.kind == "curated" and src.label == Scoring.PLACEHOLDER_LABEL
end

Scoring.FADE_FROM, Scoring.FADE_TO = 50, 58

function Scoring.handover(level)
  if not level then return 0 end
  local t = (level - Scoring.FADE_FROM) / (Scoring.FADE_TO - Scoring.FADE_FROM)
  return math.max(0, math.min(1, t))
end

function Scoring.leveling(sets, level)
  local with = {}
  for _, set in ipairs(sets or {}) do
    if set.survival and next(set.survival) then with[#with + 1] = set end
  end
  return with[1] and Scoring.pickSet(with, level or 1) or nil
end

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

local function addScaled(weights, delta, factor)
  for k, v in pairs(delta or {}) do weights[k] = (weights[k] or 0) + factor * v end
end

local function snapTiny(weights)
  for k, w in pairs(weights) do
    if math.abs(w) < 1e-12 then weights[k] = 0 end
  end
end

local function survivalAdded(ref, keep, scale)
  local added = {}
  if scale and keep > 0 then
    for k, v in pairs(ref.survival) do added[k] = v * keep * scale end
  end
  return added
end

function Scoring.apply(set, ref, share, t)
  if not (set and set.weights) then return set end
  share, t = share or 1, t or 0
  local keep = (1 - t) * share
  local scale = ref and scaleOf(set, ref)
  if not set.survival and (not scale or t >= 1) then return set end
  local key = tostring(ref) .. "|" .. keep
  local byKey = applied[set] or {}
  if byKey[key] then return byKey[key] end
  local out = copySet(set)
  local added = survivalAdded(ref, keep, scale)
  addScaled(out.weights, set.survival, -1)
  addScaled(out.weights, added, 1)
  snapTiny(out.weights)
  out.survival = nil
  out.source.plan = { share = share, t = t, added = added }
  applied[set] = byKey
  byKey[key] = out
  return out
end

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

local function crossed(bonus, from, to) return from < bonus.n and to >= bonus.n end

local function changeOfSet(setID, s, was, now, set)
  local c = { id = setID, name = s.name, size = #(s.items or {}), worn = was, after = now, gained = {}, lost = {}, value = 0 }
  for _, bonus in ipairs(s.bonuses or {}) do
    local v = Scoring.value(bonus.stats, set)
    if crossed(bonus, was, now) then
      c.gained[#c.gained + 1], c.value = bonus, c.value + v
    elseif crossed(bonus, now, was) then
      c.lost[#c.lost + 1], c.value = bonus, c.value - v
    end
  end
  if #c.gained + #c.lost > 0 then return c end
end

function Scoring.setChanges(before, after, sets, set)
  local a, b = piecesOf(before, sets), piecesOf(after, sets)
  local ids = {}
  for id in pairs(a) do ids[id] = true end
  for id in pairs(b) do ids[id] = true end
  local delta, changes = 0, {}
  for setID in pairs(ids) do
    local s, was, now = sets.bySet[setID], a[setID] or 0, b[setID] or 0
    local c = s and was ~= now and changeOfSet(setID, s, was, now, set)
    if c then
      changes[#changes + 1] = c
      delta = delta + c.value
    end
  end
  table.sort(changes, function(x, y) return x.name < y.name end)
  return delta, changes
end

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

local function compareWeapon(candidate, equipped, hand, ctx)
  local mh, oh = equipped[16], equipped[17]
  local cand = val(candidate, ctx)
  local ohValue = val(Scoring.inOffHand(oh), ctx)
  local result = { replaces = { 16, 17 }, oldValue = val(mh, ctx) + ohValue }
  local loc = candidate.equipLoc
  if hand == "two" then
    result.newValue = cand
  elseif hand == "main" then
    result.replaces = { 16 }
    if isTwoHand(mh) then
      result.newValue, result.status = cand, "needs-partner"
    else
      local asMain = cand + ohValue
      local asOff = ctx.opts.dualWield and loc == "INVTYPE_WEAPON" and val(mh, ctx) + val(Scoring.inOffHand(candidate), ctx) or nil
      if asOff and (ctx.opts.hand == "off" or (ctx.opts.hand ~= "main" and asOff > asMain)) then
        result.replaces, result.newValue, result.hand = { 17 }, asOff, "off"
      else
        result.newValue = asMain
      end
    end
  elseif hand == "off" then
    result.replaces = { 17 }
    if isTwoHand(mh) then
      result.replaces = { 16 }
      result.newValue, result.status = cand, "needs-partner"
    else
      result.newValue = val(mh, ctx) + val(Scoring.inOffHand(candidate), ctx)
    end
  else
    return nil
  end
  return finish(result)
end

local function compareSlot(candidate, equipped, slot, ctx)
  local current = equipped[slot]
  if not current then
    return { status = "empty-slot", replaces = { slot }, newValue = val(candidate, ctx), oldValue = 0 }
  end
  return finish({ replaces = { slot }, newValue = val(candidate, ctx), oldValue = val(current, ctx) })
end

local function comparePair(candidate, equipped, slots, ctx)
  local a, b = equipped[slots[1]], equipped[slots[2]]
  local newValue = val(candidate, ctx)
  if not a or not b then
    return { status = "empty-slot", replaces = { a and slots[2] or slots[1] }, newValue = newValue, oldValue = 0 }
  end
  local va, vb = val(a, ctx), val(b, ctx)
  local weaker, weakerValue = slots[1], va
  if vb < va then weaker, weakerValue = slots[2], vb end
  return finish({ replaces = { weaker }, newValue = newValue, oldValue = weakerValue })
end

local function compareLinear(candidate, equipped, ctx)
  for _, item in pairs(equipped) do
    if item.itemID ~= nil and item.itemID == candidate.itemID then
      return { status = "equipped", newValue = val(candidate, ctx), oldValue = val(item, ctx) }
    end
  end
  local rule = EQUIP_LOCS[candidate.equipLoc]
  if not rule or rule.hand then return compareWeapon(candidate, equipped, rule and rule.hand, ctx) end
  if rule.slots[2] then return comparePair(candidate, equipped, rule.slots, ctx) end
  return compareSlot(candidate, equipped, rule.slots[1], ctx)
end

function Scoring.compare(candidate, equipped, set, sets, valueFn, opts)
  equipped = equipped or {}
  local result = compareLinear(candidate, equipped, { set = set, valueOf = valueFn, opts = opts or {} })
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
