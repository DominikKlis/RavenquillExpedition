local P = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "paths.lua")
local ROOT = P.ROOT
local SG = assert(P.SimGear(arg[1]), "SimGear Forever not found: pass it as argument 1, set RQ_SIMGEAR or unzip it into <repo>/.cache/simgear/")
local SG_VERSION = "0.14.0"

local RECIPE_FILES = {
  { "Data/Leatherworking.lua", "Leatherworking" },
  { "Data/Blacksmithing.lua", "Blacksmithing" },
  { "Data/Tailoring.lua", "Tailoring" },
  { "Data/Engineering.lua", "Engineering" },
  { "Data/Enchanting.lua", "Enchanting" },
}

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local function cap(s) return s:sub(1, 1) .. s:sub(2):lower() end

local function sandboxLoad(path, ns)
  local env = { pairs = pairs, ipairs = ipairs, type = type, tostring = tostring, tonumber = tonumber,
    string = string, table = table, math = math, setmetatable = setmetatable, next = next, select = select }
  local chunk = assert(loadfile(path, "t", env))
  chunk("SimGearForever", ns)
  return env
end

local UNITS = { "RangedAttackPower", "AttackPower", "SpellPower", "HealingPower" }
local function unitKey(set)
  local keys = {}
  for k in pairs(set.derivation or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local found
  for _, k in ipairs(keys) do
    local why = set.derivation[k]
    if type(why) == "string" and why:find("^reference unit") then
      assert(not found, "two reference units in one set")
      found = k
    end
  end
  if found then return found end
  for _, k in ipairs(UNITS) do
    if set.weights[k] == 1 then return k end
  end
end

local craftable = {}
for _, rf in ipairs(RECIPE_FILES) do
  local ns = {}
  assert(loadfile(ROOT .. rf[1], "t", {}))("RavenquillExpedition_CraftAdvisor", ns)
  for _, r in pairs(ns.Recipes[rf[2]]) do craftable[r.item] = true end
end

local out = { classes = {}, meta = {} }
local allSets, setOrigin, warnings = {}, {}, {}
local stats = { sets = 0, dropped = 0 }

local function num(v)
  local s = string.format("%.15g", v)
  if tonumber(s) ~= v then s = string.format("%.17g", v) end
  return s
end

for _, class in ipairs(CLASSES) do
  local dir = SG .. "SimGearForever_" .. cap(class) .. "/data/"
  local ns = {}
  sandboxLoad(dir .. "weights/" .. class .. ".lua", ns)
  local W = ns.Weights[class]
  out.meta[class] = { engine = W.meta.engine, engineDate = W.meta.engineDate, generated = W.meta.generated }
  local specs = {}
  local keys = {}
  for k in pairs(W.sets) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, spec in ipairs(keys) do
    if spec:match("_DUNGEON$") then
      stats.dropped = stats.dropped + #W.sets[spec]
    else
      local list, specUnit = {}, nil
      for _, set in ipairs(W.sets[spec]) do
        local u = unitKey(set)
        if u and set.source.kind ~= "sim" then
          if specUnit and specUnit ~= u then warnings[#warnings + 1] = class .. " " .. spec .. ": curated units differ " .. specUnit .. "/" .. u end
          specUnit = specUnit or u
        end
      end
      for _, set in ipairs(W.sets[spec]) do
        local own = unitKey(set)
        if set.survival and next(set.survival) then
          assert(own, class .. " " .. spec .. ": a set with a survival layer has no unit stat")
        end
        local unit = own or specUnit
        if not unit then
          for _, k in ipairs(UNITS) do if (set.weights[k] or 0) > 0 then unit = k break end end
        end
        list[#list + 1] = {
          source = { kind = set.source.kind, label = set.source.label, minLevel = set.source.minLevel, maxLevel = set.source.maxLevel },
          unit = unit, unitOwn = own ~= nil,
          weights = set.weights, survival = set.survival, speedCurves = set.speedCurves,
        }
        stats.sets = stats.sets + 1
      end
      specs[spec] = list
    end
  end
  out.classes[class] = specs

  local ens = {}
  sandboxLoad(dir .. "items/" .. class .. "_extras.lua", ens)
  local E = ens.Extras[class]
  for id, set in pairs(E.sets or {}) do
    local keep = false
    for _, item in ipairs(set.items or {}) do if craftable[item] then keep = true end end
    if keep then
      if allSets[id] then
        local a, b = allSets[id], set
        local function sig(s)
          local parts = { s.name, table.concat(s.items, ",") }
          for _, bo in ipairs(s.bonuses or {}) do
            local ks = {}
            for k, v in pairs(bo.stats or {}) do ks[#ks + 1] = k .. "=" .. v end
            table.sort(ks)
            parts[#parts + 1] = bo.n .. ":" .. table.concat(ks, ",") .. (bo.unscored and "u" or "")
          end
          return table.concat(parts, "|")
        end
        if sig(a) ~= sig(b) then warnings[#warnings + 1] = ("set %d differs between %s and %s"):format(id, setOrigin[id], class) end
      else
        allSets[id], setOrigin[id] = set, class
      end
    end
  end
end

local classWeapons = {}
do
  local cns = { N = function(s) return s end, L = function(s) return s end }
  sandboxLoad(SG .. "SimGearForever/Classes.lua", cns)
  for _, class in ipairs(CLASSES) do
    local c = assert(cns.Classes[class], "Classes.lua has no " .. class)
    assert(type(c.equip) == "table" and type(c.equip.weapons) == "table", class .. ": no equip.weapons")
    local list = {}
    for i, v in ipairs(c.equip.weapons) do list[i] = v end
    table.sort(list)
    classWeapons[class] = { weapons = list, noHoldable = c.equip.noHoldable == true, dualWield = c.dualWield or {},
      dualWieldFrom = c.dualWieldFrom, dualWieldSets = c.dualWieldSets or {} }
  end
end

local w = {}
local function p(s) w[#w + 1] = s end
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
  end)
  return ks
end
local function statTable(t)
  if not t then return "nil" end
  local parts = {}
  for _, k in ipairs(sortedKeys(t)) do if t[k] ~= 0 then parts[#parts + 1] = k .. " = " .. num(t[k]) end end
  return "{ " .. table.concat(parts, ", ") .. (#parts > 0 and " }" or "}")
end
local function curves(t)
  if not t then return nil end
  local parts = {}
  for _, hand in ipairs(sortedKeys(t)) do
    local c = t[hand]
    local inner = {}
    for _, k in ipairs(sortedKeys(c)) do
      local v = c[k]
      if type(v) == "number" then inner[#inner + 1] = k .. " = " .. num(v) end
    end
    parts[#parts + 1] = hand .. " = { " .. table.concat(inner, ", ") .. " }"
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end
local function q(s) return string.format("%q", s) end

p("local _, ns = ...")
p("ns.Weights = {")
p("  meta = { source = \"SimGear Forever\", version = " .. q(SG_VERSION) .. ", engines = {")
for _, class in ipairs(CLASSES) do
  local m = out.meta[class]
  p(("    %s = { engine = %s, engineDate = %s, generated = %s },"):format(class, q(m.engine), q(m.engineDate or ""), q(m.generated or "")))
end
p("  } },")
p("  classes = {")
for _, class in ipairs(CLASSES) do
  p("    " .. class .. " = {")
  for _, spec in ipairs(sortedKeys(out.classes[class])) do
    p("      " .. spec .. " = {")
    for _, s in ipairs(out.classes[class][spec]) do
      local src = { "kind = " .. q(s.source.kind) }
      if s.source.label then src[#src + 1] = "label = " .. q(s.source.label) end
      if s.source.minLevel then src[#src + 1] = "minLevel = " .. s.source.minLevel end
      if s.source.maxLevel then src[#src + 1] = "maxLevel = " .. s.source.maxLevel end
      p("        { source = { " .. table.concat(src, ", ") .. " }, unit = " .. (s.unit and q(s.unit) or "nil")
        .. (s.unitOwn and "" or ", unitBorrowed = true") .. ",")
      p("          weights = " .. statTable(s.weights) .. ",")
      if s.survival and next(s.survival) then p("          survival = " .. statTable(s.survival) .. ",") end
      local c = curves(s.speedCurves)
      if c then p("          speedCurves = " .. c .. ",") end
      p("        },")
    end
    p("      },")
  end
  p("    },")
end
p("  },")
p("  itemSets = {")
local nsets = 0
for _, id in ipairs(sortedKeys(allSets)) do
  local s = allSets[id]
  local bon = {}
  for _, b in ipairs(s.bonuses or {}) do
    bon[#bon + 1] = "{ n = " .. b.n .. ", stats = " .. statTable(b.stats or {}) .. (b.unscored and ", unscored = true" or "") .. " }"
  end
  p(("    [%d] = { name = %s, items = { %s }, bonuses = { %s } },"):format(id, q(s.name), table.concat(s.items, ", "), table.concat(bon, ", ")))
  nsets = nsets + 1
end
p("  },")
p("  classWeapons = {")
for _, class in ipairs(CLASSES) do
  local c = classWeapons[class]
  local function keys(t)
    local parts = {}
    for _, k in ipairs(sortedKeys(t)) do
      local v = t[k]
      parts[#parts + 1] = k .. " = " .. (type(v) == "string" and q(v) or tostring(v))
    end
    return "{ " .. table.concat(parts, ", ") .. (#parts > 0 and " }" or "}")
  end
  p(("    %s = { weapons = { %s }, noHoldable = %s, dualWield = %s, dualWieldFrom = %s, dualWieldSets = %s },"):format(
    class, table.concat(c.weapons, ", "), tostring(c.noHoldable), keys(c.dualWield), tostring(c.dualWieldFrom), keys(c.dualWieldSets)))
end
p("  },")
p("}")
io.write(table.concat(w, "\n"), "\n")
io.stderr:write(("gen_weights: %d weight sets (%d dungeon sets skipped), %d item sets with a craftable piece\n"):format(stats.sets, stats.dropped, nsets))
for _, wn in ipairs(warnings) do io.stderr:write("WARNING: " .. wn .. "\n") end
