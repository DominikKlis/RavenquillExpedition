-- Section F harness (plan F6 + F8.15): scoring, weight sets, survival layer, set bonuses, spec detection.
-- Golden test: SimGear Forever's own pure Score.lua / Plan.lua / Stats.lua (loaded sandboxed from the
-- downloaded zip) against our Scoring.lua + Core on the same items, specs, levels and survival shares.
-- Run from the addon folder: lua dev/harness_score.lua [SimGear unzip dir]
local ROOT = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/RavenquillExpedition_CraftAdvisor/"
local SG = arg[1] or "C:/Users/domin/AppData/Local/Temp/claude/c3eb6a3b93e84048/70dabcec-7ea2-45c3-96bc-081d254b7578/scratchpad/simgear_dl/x/"
if not SG:match("[/\\]$") then SG = SG .. "/" end

local fails, passes = 0, 0
local function check(cond, label)
  if cond then passes = passes + 1; print("  ok   " .. label)
  else fails = fails + 1; print("  FAIL " .. label) end
end
local function section(s) print("== " .. s) end
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 1e-9) * math.max(1, math.abs(a or 0), math.abs(b or 0)) end

-- deterministic RNG (same on every Lua)
local seed = 12345
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return (seed % n) + 1 end

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local function cap(s) return s:sub(1, 1) .. s:sub(2):lower() end

---------------------------------------------------------------------------
-- SimGear, sandboxed
---------------------------------------------------------------------------
local function sgEnv()
  return { pairs = pairs, ipairs = ipairs, type = type, tostring = tostring, tonumber = tonumber, next = next,
    string = string, table = table, math = math, setmetatable = setmetatable, select = select, assert = assert,
    error = error, pcall = pcall }
end
local SGns = { N = function(s) return s end, L = function(s) return s end }
for _, f in ipairs({ "Stats.lua", "Score.lua", "Plan.lua" }) do
  assert(loadfile(SG .. "SimGearForever/" .. f, "t", sgEnv()))("SimGearForever", SGns)
end
local SGW, SGItems, SGSets = {}, {}, {}
for _, class in ipairs(CLASSES) do
  local dir = SG .. "SimGearForever_" .. cap(class) .. "/data/"
  local ns = {}
  assert(loadfile(dir .. "weights/" .. class .. ".lua", "t", sgEnv()))("x", ns)
  SGW[class] = ns.Weights[class].sets
  local ins = {}
  assert(loadfile(dir .. "items/" .. class .. ".lua", "t", sgEnv()))("x", ins)
  SGItems[class] = ins.Items[class].items
  local ens = {}
  assert(loadfile(dir .. "items/" .. class .. "_extras.lua", "t", sgEnv()))("x", ens)
  local ofItem = {}
  for setID, set in pairs(ens.Extras[class].sets or {}) do for _, id in ipairs(set.items) do ofItem[id] = setID end end
  SGSets[class] = { bySet = ens.Extras[class].sets, ofItem = ofItem }
end
print("SimGear loaded")

---------------------------------------------------------------------------
-- Our addon in a stubbed WoW environment
---------------------------------------------------------------------------
local now = 1000
local timers = {}
local function advance(sec)
  local target = now + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > target then break end
    table.remove(timers, 1); now = t.at; t.fn()
  end
  now = target
end
local itemDB = {}      -- itemID -> { name, equipLoc, minLevel, classID, subClassID, bind, raw (GetItemStats) }
local known = {}       -- spellID -> true
local talent = { config = nil, nodes = {}, inspect = nil } -- fake C_Traits
local requests = {}    -- itemID -> RequestLoadItemDataByID calls
local env = setmetatable({}, { __index = _G })
env.unpack = table.unpack
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.tinsert = table.insert
env.time = function() return 1800000000 + math.floor(now) end
env.GetTime = function() return now end
env.GetServerTime = function() return 1800000000 + math.floor(now) end
env.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
env.GetBuildInfo = function() return "1.60.1", "70938", "", 16001 end
env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " }, TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
env.SlashCmdList = {}
env.IsInGuild = function() return true end
env.InCombatLockdown = function() return false end
env.GetRealmName = function() return "Realm" end
local printed = {}
env.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
local player = { first = "Me", surname = "Stone", class = "DRUID", level = 40, items = {} }
env.UnitName = function(u) if u == "player" then return player.first, player.surname end end
env.UnitNameUnmodified = env.UnitName
env.UnitClass = function(u) if u == "player" then return player.class, player.class end end
env.UnitLevel = function(u) if u == "player" then return player.level end end
env.UnitGUID = function(u) if u == "player" then return "G-me" end end
env.UnitIsUnit = function(a, b) return a == b end
env.UnitIsPlayer = function(u) return u == "player" end
env.GetInventoryItemLink = function(u, slot) if u == "player" then return player.items[slot] end end
env.GetNumGuildMembers = function() return 0 end
local frames = {}
local FrameMT = { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end }
env.CreateFrame = function() local f = setmetatable({ scripts = {} }, FrameMT); f.SetScript = function(s, ev, fn) s.scripts[ev] = fn end; frames[#frames + 1] = f; return f end
local function idOf(item) return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)")) end
env.C_Item = {
  GetItemInfoInstant = function(item) local m = itemDB[idOf(item)]; if not m then return nil end return idOf(item), "Armor", "x", m.equipLoc, 134, m.classID, m.subClassID end,
  GetItemInfo = function(item)
    local id = idOf(item); local m = itemDB[id]; if not m then return nil end
    return m.name, "|cff|Hitem:" .. id .. "::::::::|h[" .. m.name .. "]|h|r", 2, 20, m.minLevel, nil, nil, nil, m.equipLoc, 134, nil, m.classID, m.subClassID, m.bind or 2
  end,
  GetItemStats = function(link) local m = itemDB[idOf(link)]; return m and m.raw or {} end,
  RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
}
env.C_SpellBook = { IsSpellKnown = function(id) if id == 768 then return talent.cat end return known[id] == true end }
env.C_ClassTalents = { GetActiveConfigID = function() return talent.config end }
env.C_Traits = {
  GetConfigInfo = function(id)
    if id == talent.config then return { treeIDs = { 777 } } end
    if id == -1 and talent.inspect then return { treeIDs = { talent.inspect.tree } } end
  end,
  GetTreeNodes = function(tree)
    local list = (tree == 777) and talent.nodes or (talent.inspect and tree == talent.inspect.tree and talent.inspect.nodes) or {}
    local ids = {}
    for i in ipairs(list) do ids[i] = tree * 1000 + i end
    return ids
  end,
  GetNodeInfo = function(config, nodeID)
    local tree, i = math.floor(nodeID / 1000), nodeID % 1000
    local list = config == talent.config and talent.nodes or (talent.inspect and talent.inspect.nodes) or {}
    local n = list[i]
    if not n then return nil end
    return { posX = n[1], ranksPurchased = n[2], activeRank = n[3] or n[2] }
  end,
}
env.RavenquillExpeditionCraftDB = {}
local ns = {}
for _, f in ipairs({ "Locales/enUS.lua", "Locales/deDE.lua", "Data/Leatherworking.lua", "Data/Blacksmithing.lua", "Data/Tailoring.lua", "Data/Engineering.lua",
  "Data/Enchanting.lua", "Data/Enchants.lua", "Data/Weights.lua", "Scoring.lua", "Core.lua", "Spec.lua" }) do
  assert(loadfile(ROOT .. f, "t", env))("RavenquillExpedition_CraftAdvisor", ns)
end
local GCA, Scoring, W = ns.GCA, ns.Scoring, ns.Weights
local refreshes = 0
GCA.UI = { Refresh = function() refreshes = refreshes + 1; if GCA.UI.onRefresh then GCA.UI.onRefresh() end end } -- no window here
local fire = frames[1].scripts.OnEvent
fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
fire(GCA, "PLAYER_LOGIN")

-- raw GetItemStats keys from SimGear's canonical stats (inverse of Stats.KEY_MAP / RATING_PER_POINT)
local INV = { Strength = "ITEM_MOD_STRENGTH_SHORT", Agility = "ITEM_MOD_AGILITY_SHORT", Stamina = "ITEM_MOD_STAMINA_SHORT",
  Intellect = "ITEM_MOD_INTELLECT_SHORT", Spirit = "ITEM_MOD_SPIRIT_SHORT", Defense = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
  AttackPower = "ITEM_MOD_ATTACK_POWER_SHORT", RangedAttackPower = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
  SpellPower = "ITEM_MOD_SPELL_POWER_SHORT", HealingPower = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", Armor = "RESISTANCE0_NAME",
  BlockValue = "ITEM_MOD_BLOCK_VALUE_SHORT", HolyPower = "ITEM_MOD_HOLY_DAMAGE_DONE_SHORT", ShadowPower = "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT",
  FirePower = "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", FrostPower = "ITEM_MOD_FROST_DAMAGE_DONE_SHORT", ArcanePower = "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT" }
local function rawOf(stats)
  local raw = {}
  for k, v in pairs(stats) do
    if INV[k] then raw[INV[k]] = v
    elseif k == "Dodge" then raw.ITEM_MOD_DODGE_RATING_SHORT = v * 12
    elseif k == "Parry" then raw.ITEM_MOD_PARRY_RATING_SHORT = v * 15
    elseif k == "Block" then raw.ITEM_MOD_BLOCK_RATING_SHORT = v * 5 end
  end
  if stats.MeleeHit then raw.ITEM_MOD_HIT_RATING_SHORT = stats.MeleeHit * 10 end
  if stats.MeleeCrit then raw.ITEM_MOD_CRIT_RATING_SHORT = stats.MeleeCrit * 14 end
  return raw
end

-- Leatherworking crafts that SimGear's item data has, per class, as SimGear-shaped items
local SUBCLASS = { cloth = 1, leather = 2, mail = 3 }
local CRAFT = {} -- class -> list of { itemID, equipLoc, stats }
local recipeOf = {}
for spellID, r in pairs(ns.Recipes.Leatherworking) do recipeOf[r.item] = spellID end
local SLOTTED = { INVTYPE_HEAD = 1, INVTYPE_NECK = 1, INVTYPE_SHOULDER = 1, INVTYPE_CHEST = 1, INVTYPE_ROBE = 1, INVTYPE_WAIST = 1,
  INVTYPE_LEGS = 1, INVTYPE_FEET = 1, INVTYPE_WRIST = 1, INVTYPE_HAND = 1, INVTYPE_CLOAK = 1, INVTYPE_FINGER = 1, INVTYPE_TRINKET = 1 }
for _, class in ipairs(CLASSES) do
  CRAFT[class] = {}
  for id, it in pairs(SGItems[class]) do
    if recipeOf[id] and SLOTTED[it.slot] and type(it.stats) == "table" then
      local stats = {}
      for k, v in pairs(it.stats) do stats[k] = v end
      CRAFT[class][#CRAFT[class] + 1] = { itemID = id, equipLoc = it.slot, stats = stats, name = it.name, req = it.req }
      if not itemDB[id] then
        itemDB[id] = { name = it.name, equipLoc = it.slot, minLevel = it.req or 1, classID = 4,
          subClassID = it.slot == "INVTYPE_CLOAK" and 1 or 2, raw = rawOf(stats) }
      end
    end
  end
  table.sort(CRAFT[class], function(a, b) return a.itemID < b.itemID end)
end
print(("LW crafts in SimGear's item data: DRUID %d, HUNTER %d, ROGUE %d, MAGE %d"):format(#CRAFT.DRUID, #CRAFT.HUNTER, #CRAFT.ROGUE, #CRAFT.MAGE))

---------------------------------------------------------------------------
section("Generator: Data/Weights.lua equals SimGear's tables (every set, every weight)")
---------------------------------------------------------------------------
do
  local sets, bad, dungeon = 0, 0, 0
  for _, class in ipairs(CLASSES) do
    for spec, list in pairs(SGW[class]) do
      if spec:match("_DUNGEON$") then
        dungeon = dungeon + 1
        if W.classes[class][spec] then bad = bad + 1; print("    dungeon set kept: " .. spec) end
      else
        local ours = W.classes[class][spec]
        if not ours or #ours ~= #list then bad = bad + 1; print("    count differs: " .. class .. " " .. spec)
        else
          for i, s in ipairs(list) do
            local o = ours[i]
            sets = sets + 1
            local keys = {}
            for k in pairs(s.weights) do keys[k] = true end
            for k in pairs(o.weights) do keys[k] = true end
            for k in pairs(keys) do
              if (s.weights[k] or 0) ~= (o.weights[k] or 0) then bad = bad + 1; print("    weight differs: " .. class .. " " .. spec .. " " .. i .. " " .. k) end
            end
            for k, v in pairs(s.survival or {}) do if (o.survival or {})[k] ~= v then bad = bad + 1 end end
            for k in pairs(o.survival or {}) do if not (s.survival or {})[k] then bad = bad + 1 end end
            if s.source.kind ~= o.source.kind or s.source.minLevel ~= o.source.minLevel or s.source.maxLevel ~= o.source.maxLevel
              or s.source.label ~= o.source.label then bad = bad + 1; print("    source differs: " .. class .. " " .. spec .. " " .. i) end
            if (s.speedCurves ~= nil) ~= (o.speedCurves ~= nil) then bad = bad + 1; print("    speedCurves missing: " .. class .. " " .. spec) end
            if SGns.Plan.unitKey(s) and SGns.Plan.unitKey(s) ~= o.unit then bad = bad + 1; print("    unit differs: " .. class .. " " .. spec .. " " .. i) end
            for _, f in ipairs({ "stdev", "derivation", "hitParts", "pooled", "blend", "effects", "notes", "placeholders", "defensePastCap", "hitPastCap" }) do
              if o[f] ~= nil then bad = bad + 1; print("    not stripped: " .. f) end
            end
          end
        end
      end
    end
  end
  check(bad == 0 and sets == 175, ("%d weight sets identical to SimGear's, %d dungeon specs left out, %d differences"):format(sets, dungeon, bad))
  -- item sets: every kept set has a craftable piece (any of the five professions, G7.14) and equals SimGear's;
  -- every SimGear set with a craftable piece is kept
  local recipeOf = {}
  for _, prof in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
    for spellID, r in pairs(ns.Recipes[prof]) do recipeOf[r.item] = spellID end
  end
  local missing, extra = 0, 0
  for _, class in ipairs(CLASSES) do
    for id, set in pairs(SGSets[class].bySet) do
      local craftable = false
      for _, item in ipairs(set.items) do if recipeOf[item] then craftable = true end end
      if craftable and not W.itemSets[id] then missing = missing + 1 end
    end
  end
  for id, set in pairs(W.itemSets) do
    local craftable = false
    for _, item in ipairs(set.items) do if recipeOf[item] then craftable = true end end
    if not craftable then extra = extra + 1 end
  end
  local n = 0 for _ in pairs(W.itemSets) do n = n + 1 end
  check(missing == 0 and extra == 0 and n == 15, ("item sets: %d kept (all with a craftable piece of the five professions), %d missing, %d extra"):format(n, missing, extra))
  check(W.itemSets[321] and W.itemSets[1972] and W.itemSets[421], "sets of Blacksmithing (Imperial Plate) and Tailoring (Stormcloth, Bloodvine) kept")
  check(W.itemSets[143] and W.itemSets[143].bonuses[1].stats.MeleeHit == 2, "Devilsaur Armor 2-piece: +2 MeleeHit / SpellHit")
end

---------------------------------------------------------------------------
section("Stats: our normalize = SimGear Stats.normalize (ratings -> %, Crit/Hit expand)")
---------------------------------------------------------------------------
do
  local keys = {}
  for k in pairs(SGns.Stats.KEY_MAP) do keys[#keys + 1] = k end
  table.sort(keys)
  local diffs = 0
  for trial = 1, 300 do
    local raw = {}
    for _ = 1, rnd(6) do raw[keys[rnd(#keys)]] = rnd(40) end
    if rnd(5) == 1 then raw.SOME_NEW_KEY = 3 end
    local a, ua = SGns.Stats.normalize(raw)
    local b, ub = Scoring.normalize(raw)
    for k, v in pairs(a) do if not near(v, b[k]) then diffs = diffs + 1 end end
    for k in pairs(b) do if a[k] == nil then diffs = diffs + 1 end end
    if table.concat(ua, ",") ~= table.concat(ub, ",") then diffs = diffs + 1 end
  end
  check(diffs == 0, "300 random raw stat tables normalize identically (" .. diffs .. " differences)")
  local s = Scoring.normalize({ ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 5,
    ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_PARRY_RATING_SHORT = 15, ITEM_MOD_SPELL_POWER = 9, ITEM_MOD_SPELL_POWER_SHORT = 9 })
  check(s.MeleeHit == 1 and s.SpellHit == 1 and s.MeleeCrit == 1 and s.SpellCrit == 1 and s.Block == 1 and s.Dodge == 1 and s.Parry == 1,
    "hit 10 / crit 14 / block 5 / dodge 12 / parry 15 rating = 1 % each (the old ÷14 bug is gone)")
  check(s.SpellPower == 9, "ITEM_MOD_SPELL_POWER counted once when _SHORT is there too")
end

---------------------------------------------------------------------------
section("Golden: composed weight sets (pickSet + survival layer) = SimGear Score.pickSet + Plan.apply")
---------------------------------------------------------------------------
local LEVELS = { 1, 9, 10, 12, 14, 19, 20, 25, 26, 30, 35, 40, 45, 49, 50, 51, 54, 55, 57, 58, 59, 60 }
local SHARES = { 0, 0.5, 1 }
local function sgCompose(class, spec, level, share)
  local sets = SGW[class][spec]
  local raw = SGns.Score.pickSet(sets, level)
  local ref = SGns.Plan.leveling(sets, level)
  return SGns.Plan.apply(raw, ref, share, SGns.Plan.handover(level, false)), raw, ref
end
do
  local cmp, bad = 0, 0
  for _, class in ipairs(CLASSES) do
    for spec in pairs(W.classes[class]) do
      for _, level in ipairs(LEVELS) do
        for _, share in ipairs(SHARES) do
          GCA.db.settings.survival = share
          local e = GCA:WeightSetFor(class, spec, level)
          local sg, sgRaw = sgCompose(class, spec, level, share)
          cmp = cmp + 1
          local keys = {}
          for k in pairs(sg.weights) do keys[k] = true end
          for k in pairs(e.set.weights) do keys[k] = true end
          local ok = sgRaw.source.minLevel == e.raw.source.minLevel and sgRaw.source.kind == e.raw.source.kind
          for k in pairs(keys) do if not near(sg.weights[k], e.set.weights[k], 1e-12) then ok = false end end
          if not ok then bad = bad + 1; if bad <= 5 then print(("    differs: %s %s Lv%d share %.1f"):format(class, spec, level, share)) end end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  check(bad == 0, ("%d class/spec/level/share combinations identical (%d differ)"):format(cmp, bad))
end

---------------------------------------------------------------------------
section("Golden: item comparisons (real LW crafts, random worn gear, set bonuses) = SimGear Score.compare")
---------------------------------------------------------------------------
local OURSETS = Scoring.buildSets(W.itemSets)
do
  local cmp, bad, statuses, withSets = 0, 0, {}, 0
  local SLOT_OF = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }
  for _, class in ipairs(CLASSES) do
    local pool = CRAFT[class]
    if #pool > 0 then
      for spec in pairs(W.classes[class]) do
        for _, level in ipairs({ 9, 25, 26, 40, 54, 58, 60 }) do
          local share = SHARES[rnd(3)]
          GCA.db.settings.survival = share
          local e = GCA:WeightSetFor(class, spec, level)
          local sg = sgCompose(class, spec, level, share)
          for _ = 1, 25 do
            local equipped = {}
            for _, it in ipairs(pool) do
              local slots = SLOT_OF[it.equipLoc]
              local slot = slots[rnd(#slots)]
              if rnd(3) == 1 then equipped[slot] = it end
            end
            -- force set situations: sometimes wear one Devilsaur piece, sometimes both
            if rnd(3) == 1 and itemDB[15063] then equipped[10] = { itemID = 15063, equipLoc = "INVTYPE_HAND", stats = Scoring.normalize(itemDB[15063].raw) } end
            local cand = pool[rnd(#pool)]
            local a = SGns.Score.compare(cand, equipped, sg, { sets = SGSets[class] })
            local b = Scoring.compare(cand, equipped, e.set, OURSETS)
            cmp = cmp + 1
            local ok = (a == nil) == (b == nil)
            if a and b then
              ok = ok and a.status == b.status and near(a.newValue, b.newValue) and near(a.oldValue, b.oldValue)
                and ((a.pct == nil and b.pct == nil) or near(a.pct, b.pct)) and near(a.setDelta or 0, b.setDelta or 0)
              statuses[a.status] = (statuses[a.status] or 0) + 1
              if a.sets then withSets = withSets + 1 end
            end
            if not ok then
              bad = bad + 1
              if bad <= 5 then print(("    differs: %s %s Lv%d item %d: %s %s vs %s %s"):format(class, spec, level, cand.itemID,
                a and a.status, a and a.newValue, b and b.status, b and b.newValue)) end
            end
          end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  local st = {}
  for k, v in pairs(statuses) do st[#st + 1] = k .. " " .. v end
  table.sort(st)
  check(bad == 0, ("%d comparisons identical to SimGear (%d differ); %s; %d with a set change"):format(cmp, bad, table.concat(st, ", "), withSets))
end

---------------------------------------------------------------------------
section("pickSet at levels 9 / 25 / 26 / 58 / 60 and bracket gaps (F8.9)")
---------------------------------------------------------------------------
do
  local function pick(class, spec, level)
    local e = GCA:WeightSetFor(class, spec, level)
    return e.raw.source.kind .. (e.raw.source.minLevel or "*")
  end
  check(pick("ROGUE", "COMBAT", 9) == "curated20", "Combat Lv9 -> curated Lv20 (lowest set)")
  check(pick("ROGUE", "COMBAT", 25) == "curated20", "Combat Lv25 -> tie 20/30 goes to the lower (curated Lv20)")
  check(pick("ROGUE", "COMBAT", 26) == "sim30", "Combat Lv26 -> sim Lv30")
  check(pick("ROGUE", "COMBAT", 58) == "sim60", "Combat Lv58 -> sim Lv60")
  check(pick("ROGUE", "COMBAT", 60) == "sim60", "Combat Lv60 -> sim Lv60")
  check(pick("DRUID", "FERAL_CAT", 12) == "sim30", "Feral Cat Lv12 -> Lv30, sim beats measured at the same level")
  check(pick("MAGE", "FIRE", 9) == "curated10" and pick("MAGE", "FIRE", 25) == "curated20" and pick("MAGE", "FIRE", 26) == "sim30",
    "Fire 9/25/26 -> curated 10 / curated 20 / sim 30 (same level: sim wins)")
  check(pick("WARLOCK", "DESTRUCTION", 55) == "curated50" and pick("WARLOCK", "DESTRUCTION", 56) == "sim60",
    "Destruction (no sim 30-50): Lv55 tie -> curated 50, Lv56 -> sim 60")
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 12)
  check(GCA:SourceLine(e):find("Lv30 %(nearest set for Lv12%)") ~= nil, "source line shows the gap: " .. GCA:SourceLine(e))
end

---------------------------------------------------------------------------
section("Survival slider and fade (F8.3)")
---------------------------------------------------------------------------
do
  GCA.db.settings.survival = 0
  local e0 = GCA:WeightSetFor("ROGUE", "COMBAT", 20)
  local raw = e0.raw
  check(near(e0.set.weights.Stamina, (raw.weights.Stamina or 0) - (raw.survival.Stamina or 0)), "0 %: the set's own survival layer is removed")
  GCA.db.settings.survival = 1
  local e1 = GCA:WeightSetFor("ROGUE", "COMBAT", 20)
  check(near(e1.set.weights.Stamina, raw.weights.Stamina), "100 %: the curated set as SimGear ships it")
  GCA.db.settings.survival = 0.5
  local e40 = GCA:WeightSetFor("ROGUE", "COMBAT", 40)
  local add = e40.ref.survival.Stamina * 0.5 * e40.raw.weights.AttackPower
  check(near(e40.set.weights.Stamina, (e40.raw.weights.Stamina or 0) + add), "Lv40 sim: + ref survival × 0.5 × AP weight (scale)")
  local e54 = GCA:WeightSetFor("ROGUE", "COMBAT", 54)
  check(near(e54.t, 0.5) and GCA:SourceLine(e54):find("fading, 50%% left"), "Lv54: half faded: " .. GCA:SourceLine(e54))
  local e58 = GCA:WeightSetFor("ROGUE", "COMBAT", 58)
  check(e58.set == e58.raw and GCA:SourceLine(e58):find("faded out"), "Lv58+: no survival layer")
  local wp = GCA:WeightSetFor("WARRIOR", "PROTECTION", 30)
  check(wp.ref == nil and GCA:SourceLine(wp):find("no leveling bonus"), "Warrior Prot: no layer, slider does nothing")
  check(GCA:WeightSetFor("ROGUE", "COMBAT", 40) == e40, "weight set cached per (spec, level, share)")
  GCA.db.settings.survival = 0.8
  check(GCA:WeightSetFor("ROGUE", "COMBAT", 40) ~= e40, "another share -> another set")
  GCA.db.settings.survival = 0.5
end

---------------------------------------------------------------------------
section("Healers: curated placeholders, any level, marked rough (F7.3)")
---------------------------------------------------------------------------
do
  for _, cs in ipairs({ { "PRIEST", "HOLY" }, { "PRIEST", "DISCIPLINE" }, { "DRUID", "RESTORATION" }, { "SHAMAN", "RESTORATION" }, { "PALADIN", "HOLY" } }) do
    local e9, e60 = GCA:WeightSetFor(cs[1], cs[2], 9), GCA:WeightSetFor(cs[1], cs[2], 60)
    check(e9.raw == e60.raw and Scoring.isPlaceholder(e9.raw) and GCA:SourceLine(e9):find("rough %(healer weights not simulated%)")
      and GCA:SourceLine(e9):find("all levels"), cs[1] .. " " .. cs[2] .. ": " .. GCA:SourceLine(e9))
  end
  -- "healing up to 33 and damage up to 11": spell power not counted again by a set that weighs healing
  local e = GCA:WeightSetFor("PRIEST", "HOLY", 30)
  local st = { HealingPower = 33, SpellPower = 11 }
  check(near(Scoring.value(st, e.set), 33 * e.set.weights.HealingPower), "HealingPower item: its SpellPower counts 0 for healers")
end

---------------------------------------------------------------------------
section("Display points = score ÷ unit-stat weight (F8.1)")
---------------------------------------------------------------------------
do
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 60)
  check(e.unit == "AttackPower" and near(e.unitW, e.raw.weights.AttackPower) and near(GCA:ToPoints(e, e.raw.weights.AttackPower * 10), 10),
    ("Feral Cat Lv60 sim: 10 AP = 10 AP-eq (AP weight %.4f)"):format(e.unitW))
  local c = GCA:WeightSetFor("MAGE", "FIRE", 20)
  check(c.unit == "SpellPower" and c.unitW == 1 and GCA:UnitLabel(c) == "SP", "Fire Lv20 curated: SP, unit weight 1")
  local h = GCA:WeightSetFor("HUNTER", "MARKSMANSHIP", 40)
  check(h.unit == "RangedAttackPower" and GCA:UnitLabel(h) == "RAP", "Marksmanship: RAP")
end

---------------------------------------------------------------------------
-- end-to-end through Core: a guildie with gear, known recipes, ComputeSuggestions
---------------------------------------------------------------------------
local function link(id) return "item:" .. id .. "::::::::40:1488" end
local function addItem(id, name, loc, minLevel, raw, sub)
  itemDB[id] = { name = name, equipLoc = loc, minLevel = minLevel or 1, classID = 4, subClassID = sub or 2, raw = raw }
end
-- synthetic crafts (spell IDs from the real recipe table so CanWear/known logic is used as is)
local function recipeFor(itemID) return recipeOf[itemID] end

section("No baseline, negative scores, sorting, 1 % threshold, cap (F8.5)")
do
  -- Rogue Combat Lv40 sim: Armor weight?
  local e = GCA:WeightSetFor("ROGUE", "COMBAT", 40)
  -- find a Lv60 set with a negative weight (F8.5 says four exist)
  local negSets = 0
  for _, class in ipairs(CLASSES) do
    for spec, list in pairs(W.classes[class]) do
      for _, s in ipairs(list) do
        for _, v in pairs(s.weights) do if v < 0 then negSets = negSets + 1; break end end
      end
    end
  end
  check(negSets >= 1, negSets .. " weight sets have a negative weight")
  -- no-baseline: equipped item only has Armor; Combat's Lv40 sim weighs Armor 0 or nearly
  local eq = { [5] = { itemID = 1, equipLoc = "INVTYPE_CHEST", stats = { Armor = 50 } } }
  local cand = { itemID = 2, equipLoc = "INVTYPE_CHEST", stats = { Agility = 5, Armor = 60 } }
  local zeroArmor = (e.set.weights.Armor or 0) <= 0
  local r = Scoring.compare(cand, eq, e.set, OURSETS)
  check(not zeroArmor or (r.status == "no-baseline" and r.pct == nil and r.newValue > 0), "armor-only equipped item (score ≤ 0) -> no-baseline, no % (" .. r.status .. ")")
  local neg = Scoring.compare(cand, { [5] = { itemID = 1, equipLoc = "INVTYPE_CHEST", stats = { Agility = -3 } } }, e.set, OURSETS)
  check(neg.status == "no-baseline", "negative equipped score -> no-baseline")
  -- sorting helper
  local B = GCA.BetterSuggestion
  local list = {
    { tier = 1, points = 50, known = true, slot = 1, name = "nobase-50" },
    { tier = 1, points = 3, known = true, slot = 2, name = "up-3" },
    { tier = 1, points = 30, known = true, slot = 3, name = "up-30" },
    { tier = 1, points = 9, known = true, slot = 4, name = "empty-9" },
    { tier = 1, points = 90, known = true, slot = 6, name = "empty-90" },
    { tier = 1, points = 30, known = false, slot = 5, name = "up-30-unlearned" },
    { tier = GCA.TIER_PARTNER, points = 99, known = true, slot = 7, name = "partner-99" },
  }
  table.sort(list, B)
  local order = {}
  for i, x in ipairs(list) do order[i] = x.name end
  check(table.concat(order, ",") == "empty-90,nobase-50,up-30,up-30-unlearned,empty-9,up-3,partner-99",
    "order (user 2026-11-14): real gains by points (known first on a tie), needs-partner after: " .. table.concat(order, ","))
end

section("End to end: Core.ComputeSuggestions with a guildie, sets, threshold, unknown spec/level")
do
  -- gear and crafts for a level 58 Feral Cat druid (Devilsaur set, real items from SimGear's data)
  local legs, gloves = 15062, 15063
  check(itemDB[legs] and itemDB[gloves] and recipeFor(legs) and recipeFor(gloves), "Devilsaur Leggings/Gauntlets are LW crafts in the data")
  known[recipeFor(legs)] = true; known[recipeFor(gloves)] = true
  -- worn: weak legs and gloves, chest
  addItem(900001, "Old Pants", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 100 })
  addItem(900002, "Old Gloves", "INVTYPE_HAND", 40, { ITEM_MOD_AGILITY_SHORT = 8 })
  addItem(900003, "Plain Robe", "INVTYPE_CHEST", 40, { RESISTANCE0_NAME = 120 })                   -- armor only
  addItem(900004, "Shiny Belt", "INVTYPE_WAIST", 40, { ITEM_MOD_AGILITY_SHORT = 30, ITEM_MOD_STRENGTH_SHORT = 30 }) -- too good
  -- a known chest and boots craft with Agility (real items): chest vs the armor-only robe, boots into an empty slot
  local function firstCraft(loc)
    for _, it in ipairs(CRAFT.DRUID) do
      if it.equipLoc == loc and (it.stats.Agility or 0) > 0 and (it.req or 1) <= 58 and itemDB[it.itemID].bind ~= 1 then return it end
    end
  end
  local chestCraft, bootCraft = firstCraft("INVTYPE_CHEST"), firstCraft("INVTYPE_FEET")
  known[recipeFor(chestCraft.itemID)] = true; known[recipeFor(bootCraft.itemID)] = true
  GCA:RefreshKnown()
  GCA.db.settings.showUnlearned = false
  local items = { [7] = link(900001), [10] = link(900002), [5] = link(900003), [6] = link(900004) }
  GCA.db.members["Kat Paw"] = { class = "DRUID", level = 58, items = items, ts = 1, source = "inspect" }
  GCA.roster["Kat Paw"] = { class = "DRUID", level = 58, online = true }
  -- spec unknown -> no suggestions (F8.2)
  local list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items }, false)
  check(#list == 0 and state == "no-spec", "spec unknown -> no suggestions (" .. state .. ")")
  list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", items = items, spec = "FERAL_CAT" }, false)
  check(#list == 0 and state == "no-level", "level unknown -> no suggestions (" .. state .. ")")
  list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local bySlot = {}
  for _, s in ipairs(list) do bySlot[s.slot] = s end
  check(state == "ok" and bySlot[7] and bySlot[10], "Devilsaur legs and gloves suggested (" .. #list .. " suggestions)")
  -- the first one counted alone (the set is completed only by wearing both); hint names the other piece
  local L = bySlot[7]
  check(L and L.hint and L.hint:find("Devilsaur Armor: %+2%% hit with Devilsaur Gauntlets %(you craft it%)"), "set hint: " .. tostring(L and L.hint))
  -- review M-1: the hint and the bonus words are localized as whole sentences
  ns.locale = "deDE"
  local deHint = L and GCA:SetHint(legs, L.afterIDs, "Leatherworking")
  check(deHint == "Devilsaur Armor: +2% Trefferchance mit Devilsaur Gauntlets (stellst du her)", "German set hint: " .. tostring(deHint))
  check(GCA:BonusText({ SpellPower = 20, MeleeCrit = 1 }) == "+1% kritische Trefferchance (Nahkampf), +20 Zaubermacht",
    "German bonus words: " .. GCA:BonusText({ SpellPower = 20, MeleeCrit = 1 }))
  ns.locale = "enUS"
  check(GCA:BonusText({ SpellPower = 20, MeleeHit = 1, SpellHit = 1 }) == "+1% hit, +20 spell power", "English bonus words unchanged: "
    .. GCA:BonusText({ SpellPower = 20, MeleeHit = 1, SpellHit = 1 }))
  for i = 2, #list do check(not GCA.BetterSuggestion(list[i], list[i - 1]), "list sorted (" .. i .. ")") end
  -- with the gloves worn, the legs complete the set: set gain counted
  local items2 = { [7] = link(900001), [10] = link(gloves), [5] = link(900003), [6] = link(900004) }
  local l2 = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items2, spec = "FERAL_CAT" }, false)
  local L2
  for _, s in ipairs(l2) do if s.slot == 7 then L2 = s end end
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local bonus = 2 * (e.set.weights.MeleeHit or 0) + 2 * (e.set.weights.SpellHit or 0)
  check(L2 and L2.sets and near(L2.setDelta, bonus) and L2.hint == nil, ("legs with gloves worn: set gain %.4f counted"):format(L2 and L2.setDelta or -1))
  check(L and L2 and near(L2.newScore - L.newScore, bonus), "set gain = difference of the two cases")
  -- losing the set: wearing both, a non-set gloves candidate would break it
  addItem(900005, "Rival Gloves", "INVTYPE_HAND", 40, { ITEM_MOD_AGILITY_SHORT = 40 })
  local both = { [7] = { itemID = legs, equipLoc = "INVTYPE_LEGS", stats = GCA:GetInfo(legs).cstats },
    [10] = { itemID = gloves, equipLoc = "INVTYPE_HAND", stats = GCA:GetInfo(gloves).cstats } }
  local lose = Scoring.compare({ itemID = 900005, equipLoc = "INVTYPE_HAND", stats = { Agility = 40 } }, both, e.set, OURSETS)
  check(lose.sets and near(lose.setDelta, -bonus), "replacing a set piece subtracts the bonus")
  -- duplicate piece: two copies of one item count once (rings in SimGear) -> piecesOf
  local p = Scoring.piecesOf({ legs, legs }, OURSETS)
  check(p[143] == 1, "two copies of the same piece count as one")
  -- below 1 %: a marginal upgrade is not listed
  addItem(900006, "Pants+", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 101 })
  local tiny = Scoring.compare({ itemID = 900006, equipLoc = "INVTYPE_LEGS", stats = Scoring.normalize(itemDB[900006].raw) },
    { [7] = { itemID = 900001, equipLoc = "INVTYPE_LEGS", stats = Scoring.normalize(itemDB[900001].raw) } }, e.set, OURSETS)
  check(tiny.pct == nil or tiny.pct < GCA.MIN_PCT, ("a 1-armor gain is %.4f%% (< 1 %%) -> would not be listed"):format((tiny.pct or 0) * 100))
  -- no-baseline chest: armor-only robe scores ≤ 0 for Cat -> listed by points after the % ones
  local chest
  for _, s in ipairs(list) do if s.slot == 5 then chest = s end end
  check(chest and chest.status == "no-baseline" and chest.tier == 1 and chest.pct == nil and chest.points > 0,
    "no-baseline chest (" .. chestCraft.name .. " vs armor-only robe): listed with the others by points, no %")
  local feet = bySlot[8]
  local sorted = true
  for i = 2, #list do
    local a, b = list[i - 1], list[i]
    if a.tier == b.tier and (a.future and true or false) == (b.future and true or false) and a.points < b.points - 1e-9 then sorted = false end
  end
  check(feet and feet.status == "empty-slot" and feet.tier == 1 and feet.equipped == nil and sorted,
    ("empty feet slot (%s): same tier as the upgrades, the list sorted by points"):format(bootCraft.name))
  check(bySlot[6] == nil, "no suggestion for the waist (worn belt is better)")
  -- caching: same inputs -> same table; a new spec -> recomputed
  local c1 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local c2 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local c3 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_BEAR" }, false)
  check(c1 == c2 and c3 ~= c1, "suggestions cached per member on gear + spec + level + settings")
  -- gear rule: Feral excludes held off-hands
  check(GCA.GEAR_RULES["DRUID/FERAL_CAT"].INVTYPE_HOLDABLE, "Feral: held off-hands excluded")
  -- member list: manual spec pick drives it
  GCA:SetManualSpec("Kat Paw", "DRUID", "FERAL_CAT")
  local entries = GCA:GetMemberList()
  local kat
  for _, en in ipairs(entries) do if en.key == "Kat Paw" then kat = en end end
  check(kat and kat.spec == "FERAL_CAT" and kat.specHow == "manual" and kat.best ~= nil, "member list: manual spec -> suggestions, best upgrade known")
  check(entries[1].isSelf, "you stay pinned on top")
end

section("Empty-slot tier in the member list (user decision 2026-11-13)")
do
  -- three members: a small % upgrade, only an empty-slot fill (big points), only a no-baseline gain (bigger points)
  local fake = {
    ["Pct Paw"] = { { tier = 1, points = 1, known = true, slot = 7, status = "upgrade", pct = 0.02 } },
    ["Empty Paw"] = { { tier = 1, points = 40, known = true, slot = 8, status = "empty-slot" } },
    ["Empty Two"] = { { tier = 1, points = 60, known = true, slot = 8, status = "empty-slot" } },
    ["Nobase Paw"] = { { tier = 1, points = 99, known = true, slot = 5, status = "no-baseline" } },
  }
  for key in pairs(fake) do
    GCA.db.members[key] = { class = "DRUID", level = 58, items = {}, ts = 1, source = "inspect" }
    GCA.roster[key] = { class = "DRUID", level = 58, online = true }
  end
  local real = GCA.MemberSuggestions
  GCA.MemberSuggestions = function(self, view, isSelf)
    if fake[view.key] then return fake[view.key], 0, "ok" end
    return real(self, view, isSelf)
  end
  local order = {}
  for _, en in ipairs(GCA:GetMemberList()) do if fake[en.key] then order[#order + 1] = en.key end end
  GCA.MemberSuggestions = real
  check(table.concat(order, ",") == "Nobase Paw,Empty Two,Empty Paw,Pct Paw",
    "members: by their best gain in points (user 2026-11-14): " .. table.concat(order, ","))
  for key in pairs(fake) do GCA.db.members[key] = nil; GCA.roster[key] = nil end
  -- display: points only plus "empty slot" (UI.GainText; UI.lua loaded standalone just for this function)
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  local okUI = pcall(function() assert(loadfile(ROOT .. "UI.lua", "t", env))("RavenquillExpedition_CraftAdvisor", uiNs) end)
  local UI = GCA.UI
  GCA.UI = savedUI
  local txt = okUI and UI and UI.GainText and UI.GainText({ status = "empty-slot", points = 7.07 })
  check(txt and txt:find("+7.1", 1, true) and txt:find("empty slot", 1, true) and not txt:find("%%"),
    "empty-slot gain shown as points + \"empty slot\", no %: " .. tostring(txt))
end

section("Post-review: tiny no-baseline gain, unchanged known set, item that never loads")
do
  local view = function(key, items) return { key = key, class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" } end
  -- (e) no-baseline tiny gain: armor-only wrist worn (scores <= 0 for Cat), a craft with +0.01 Agility
  local fakeSpell, fakeItem = 990001, 900030
  addItem(900031, "Armor Bracers", "INVTYPE_WRIST", 40, { RESISTANCE0_NAME = 50 })
  addItem(fakeItem, "Faint Bracers", "INVTYPE_WRIST", 40, { RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 0.01 })
  ns.Recipes.Leatherworking[fakeSpell] = { item = fakeItem, skill = 1, src = "trainer", name = "Faint Bracers", r = {} }
  GCA.candidates = nil
  known[fakeSpell] = true
  check(GCA:RefreshKnown() == true, "RefreshKnown reports a changed known set")
  -- (d) same set again: knownGen unchanged, no refresh
  local gen, before = GCA.knownGen, refreshes
  advance(1)
  before = refreshes
  check(GCA:RefreshKnown() == false and GCA.knownGen == gen, "RefreshKnown with the same set: knownGen unchanged (" .. gen .. ")")
  advance(1)
  check(refreshes == before, "... and no window refresh")
  local items = { [9] = link(900031) }
  local list = GCA:ComputeSuggestions(view("Wrist Paw", items), false)
  local wrist
  for _, sug in ipairs(list) do if sug.slot == 9 then wrist = sug end end
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local pts = GCA:ToPoints(e, 0.01 * (e.set.weights.Agility or 0))
  check(pts > 0 and pts < GCA.MIN_POINTS and wrist == nil, ("no-baseline gain of %.4f points (< %.2f) is not listed"):format(pts, GCA.MIN_POINTS))
  itemDB[fakeItem].raw.ITEM_MOD_AGILITY_SHORT = 1; GCA.infoCache[fakeItem] = nil
  list = GCA:ComputeSuggestions(view("Wrist Paw", items), false)
  wrist = nil
  for _, sug in ipairs(list) do if sug.slot == 9 then wrist = sug end end
  check(wrist and wrist.status == "no-baseline" and wrist.points >= GCA.MIN_POINTS and string.format("%+.1f", wrist.points) ~= "+0.0",
    ("control: +1 Agility -> listed (%s points)"):format(wrist and string.format("%.2f", wrist.points) or "-"))
  ns.Recipes.Leatherworking[fakeSpell] = nil; known[fakeSpell] = nil; GCA.candidates = nil
  GCA.db.known[GCA.charKey].Leatherworking[fakeSpell] = nil
  GCA:RefreshKnown()

  -- (c) an equipped item that never loads (not in the item DB): legs slot unknown, others still suggested
  local ghost = 900099
  local items2 = { [7] = link(ghost), [10] = link(900002), [5] = link(900003), [6] = link(900004) }
  local v = view("Ghost Paw", items2)
  local calls = 0
  GCA.UI.onRefresh = function() calls = calls + 1; GCA:MemberSuggestions(v, false) end -- what the window does
  refreshes = 0
  local l0, p0, st0 = GCA:MemberSuggestions(v, false)
  check(st0 == "loading" and p0 > 0 and requests[ghost] == 1, "first look: loading, one request")
  advance(30)
  local l1, p1, st1 = GCA:MemberSuggestions(v, false)
  local slots = {}
  for _, sug in ipairs(l1) do slots[sug.slot] = sug end
  check(requests[ghost] == GCA.LOAD_TRIES, ("gave up after %d requests (%d)"):format(GCA.LOAD_TRIES, requests[ghost] or 0))
  check(st1 == "ok" and p1 == 0 and slots[10] and slots[8], "other slots still suggested (gloves, empty feet)")
  check(slots[7] == nil and l1.unknownSlots and l1.unknownSlots[7], "legs slot unknown: not offered, not treated as empty")
  check(refreshes <= 6, ("bounded refreshes while loading (%d in 30 s)"):format(refreshes))
  local r0 = refreshes
  advance(60)
  check(refreshes == r0 and not GCA.loadRetryPending, "no further refreshes once given up (no endless loop)")
  fire(GCA, "GET_ITEM_INFO_RECEIVED", ghost, false)
  fire(GCA, "GET_ITEM_INFO_RECEIVED", 123456, true)
  advance(5)
  check(refreshes == r0, "GET_ITEM_INFO_RECEIVED with success=false or for an item we don't wait for: no refresh")
  -- the item arrives after all: cache dropped, legs compared again
  addItem(ghost, "Late Pants", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 1 })
  fire(GCA, "GET_ITEM_INFO_RECEIVED", ghost, true)
  advance(1)
  GCA.UI.onRefresh = nil
  local l2 = GCA:MemberSuggestions(v, false)
  local legs2
  for _, sug in ipairs(l2) do if sug.slot == 7 then legs2 = sug end end
  check(legs2 and not l2.unknownSlots, "late arrival: refresh, legs compared again")
end

---------------------------------------------------------------------------
section("Spec from talents: own C_Traits nodes, ties, variants (F4, F8.2, F8.7)")
---------------------------------------------------------------------------
do
  local pts = GCA:PointsFromNodes({ { posX = 1020, ranks = 5 }, { posX = 50300, ranks = 3 }, { posX = 9080, ranks = 2 }, { posX = 990, ranks = 1 } }, "ROGUE")
  check(pts.ASSASSINATION == 6 and pts.COMBAT == 3 and pts.SUBTLETY == 2, "posX buckets incl. slack and the stray extra zero (50300 -> 5030)")
  check(GCA:InferTree({ ASSASSINATION = 5, COMBAT = 5 }, "ROGUE") == nil and select(2, GCA:InferTree({}, "ROGUE")) == "no-talents", "tie / zero -> unknown")
  -- own talents through the fake C_Traits: Druid with points in Feral
  talent.config = 55
  talent.nodes = { { 5020, 5 }, { 5100, 3 }, { 1020, 2 } }
  talent.cat = true
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_CAT" and not GCA.ownSpec.assumed, "own Feral + Cat Form known -> Feral (Cat)")
  talent.cat = false
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_BEAR", "own Feral without Cat Form -> Bear (SimGear's rule)")
  talent.cat = nil -- can't check -> same default as guildies
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_CAT" and GCA.ownSpec.assumed, "own Feral, Cat Form not checkable -> Cat, assumed")
  local s, how = GCA:MemberSpec(GCA.playerKey, "DRUID", {})
  check(s == "FERAL_CAT" and how == "talents", "your own spec from talents")
  talent.nodes = { { 1020, 3 }, { 5020, 3 } }
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == nil and GCA.ownSpec.reason == "tie", "own tie -> spec unknown")
  talent.nodes = { { 5020, 5 }, { 5100, 3 } }
  talent.cat = true
  GCA:RefreshOwnSpec()
  -- guildie variants
  check(GCA:ResolveTree("FERAL", "DRUID", {}, nil) == "FERAL_CAT", "guildie Feral tree -> Cat (assumed)")
  addItem(900010, "Axe", "INVTYPE_WEAPON", 30, {}); itemDB[900010].classID = 2
  addItem(900011, "Shield", "INVTYPE_SHIELD", 30, {}, 6)
  local sp, why = GCA:ResolveTree("ENHANCEMENT", "SHAMAN", { [17] = link(900010) }, nil)
  check(sp == "ENHANCEMENT_DW" and why, "Enhancement + one-hander in slot 17 -> Enhancement (dual-wield), assumed")
  check(GCA:ResolveTree("ENHANCEMENT", "SHAMAN", { [17] = link(900011) }, nil) == "ENHANCEMENT", "Enhancement + shield -> Enhancement")
  check(GCA:ResolveTree("DISCIPLINE", "PRIEST", {}) == "DISCIPLINE" and GCA:ResolveTree("SURVIVAL", "HUNTER", {}) == "SURVIVAL", "Smite / Survival (melee): never inferred")
  -- manual pick wins over synced and inspected
  GCA:StoreSpec("Bo Hunt", "HUNTER", { spec = "MARKSMANSHIP", src = "sync", ts = 100 })
  check(GCA:MemberSpec("Bo Hunt", "HUNTER", {}) == "MARKSMANSHIP", "synced spec used")
  GCA:SetManualSpec("Bo Hunt", "HUNTER", "SURVIVAL_MELEE")
  local ms, mhow = GCA:MemberSpec("Bo Hunt", "HUNTER", {})
  check(ms == "SURVIVAL_MELEE" and mhow == "manual", "manual pick wins")
  check(not GCA:StoreSpec("Bo Hunt", "HUNTER", { spec = "BEAST_MASTERY", src = "sync", ts = 50 }), "older synced spec rejected")
  GCA:SetManualSpec("Bo Hunt", "HUNTER", nil)
  check(GCA:MemberSpec("Bo Hunt", "HUNTER", {}) == "MARKSMANSHIP", "manual pick cleared -> synced again")
  check(GCA:MemberSpec("Bo Hunt", "MAGE", {}) == nil, "a stored spec of another class is ignored")
end

---------------------------------------------------------------------------
section("Inspected talents: plausibility gate (F8.6)")
---------------------------------------------------------------------------
do
  -- own: Druid Feral 8 points (above). Guildie Rogue Lv30 with 21 points in Combat
  talent.inspect = { tree = 888, nodes = { { 5020, 15 }, { 5200, 6 } } }
  local tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == "COMBAT" and why == "ok", "plausible inspect read -> Combat")
  talent.inspect = { tree = 888, nodes = { { 5020, 0, 15 }, { 1020, 0, 2 } } }
  tree = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == "COMBAT", "ranksPurchased all 0 -> activeRank used (Leatrix Plus' fallback)")
  talent.inspect = { tree = 888, nodes = { { 5020, 40 } } }
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil and why:find("more points"), "more points than level 30 allows -> rejected (" .. why .. ")")
  talent.inspect = { tree = 777, nodes = { { 5020, 5 }, { 5100, 3 } } }
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil and why:find("same tree"), "our own tree handed back for another class -> rejected (" .. why .. ")")
  tree, why = GCA:ReadInspectTalents("DRUID", 30)
  check(tree == nil and why:find("identical"), "same class, node-for-node our own talents -> rejected (" .. why .. ")")
  talent.inspect = nil
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil, "no inspect config -> nothing, no error (" .. tostring(why) .. ")")
  -- default OFF (F8.6 "used only if verified in game"), incl. a one-time reset of 0.3.0 dev builds' true
  check(GCA.db.settings.inspectTalents == false, "inspected talents default off")
  local db = env.RavenquillExpeditionCraftDB
  db.settings.inspectTalents, db.inspectTalentsOffV1 = true, nil
  fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
  check(db.settings.inspectTalents == false and db.inspectTalentsOffV1, "0.3.0 dev SavedVariables with true -> reset to off once")
  db.settings.inspectTalents = true
  fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
  check(db.settings.inspectTalents == true, "turned on by hand afterwards -> stays on")
  -- TryInspectTalents stores a plausible tree; resolved with the variant rule on use
  GCA.db.settings.inspectTalents = true
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Fera Paw", "DRUID", 40)
  advance(2)
  local s, how, assumed = GCA:MemberSpec("Fera Paw", "DRUID", {})
  check(s == "FERAL_CAT" and how == "inspected" and assumed, "inspected Feral -> Cat (assumed)")
  GCA.db.settings.inspectTalents = false
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  GCA:TryInspectTalents("Bala Paw", "DRUID", 40)
  advance(2)
  check(GCA:MemberSpec("Bala Paw", "DRUID", {}) == nil, "/gca spec inspect off -> not used")
  GCA.db.settings.inspectTalents = true
  -- a synced Bear pick is not overwritten by a later inspect of the same (Feral) tree; another tree does replace it
  GCA.db.settings.inspectTalents = true
  GCA:StoreSpec("Ursa Paw", "DRUID", { spec = "FERAL_BEAR", src = "sync", ts = 5 })
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Ursa Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Ursa Paw", "DRUID", {}) == "FERAL_BEAR", "inspect of the same tree keeps the synced Bear")
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  GCA:TryInspectTalents("Ursa Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Ursa Paw", "DRUID", {}) == "BALANCE", "inspect of another tree (newer) replaces it")
  -- (a) inspect stored first, then the guildie's S with their (older) last-spec-change ts, same tree -> sync wins
  GCA.db.settings.inspectTalents = true
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Bear Paw", "DRUID", 40); advance(2)
  local s1, h1 = GCA:MemberSpec("Bear Paw", "DRUID", {})
  local stored = GCA:StoreSpec("Bear Paw", "DRUID", { spec = "FERAL_BEAR", src = "sync", ts = GCA:Now() - 86400 })
  local s2, h2 = GCA:MemberSpec("Bear Paw", "DRUID", {})
  check(s1 == "FERAL_CAT" and h1 == "inspected" and stored and s2 == "FERAL_BEAR" and h2 == "synced",
    "inspect first, then an older synced spec on the same tree -> synced wins (" .. tostring(s2) .. ", " .. tostring(h2) .. ")")
  GCA:TryInspectTalents("Bear Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Bear Paw", "DRUID", {}) == "FERAL_BEAR", "a later inspect of the same tree still doesn't replace it")
  check(not GCA:StoreSpec("Bear Paw", "DRUID", { spec = "BALANCE", src = "sync", ts = GCA:Now() - 99999 }), "an older synced spec still loses to a newer synced one")
  -- (b) inspected talents off: an old inspect record is ignored, and a synced spec (even older, other tree) replaces it
  GCA.db.settings.inspectTalents = false
  local s3, h3 = GCA:MemberSpec("Fera Paw", "DRUID", {})
  check(s3 == nil and GCA.db.specs["Fera Paw"].src == "inspect", "inspect off: stored inspect record ignored (" .. tostring(h3) .. ")")
  check(GCA:StoreSpec("Fera Paw", "DRUID", { spec = "BALANCE", src = "sync", ts = 1 }) and GCA:MemberSpec("Fera Paw", "DRUID", {}) == "BALANCE",
    "inspect off: an older synced spec of another tree replaces the ignored inspect record")
  GCA.db.settings.inspectTalents = true
  -- (f) a later inspect started (counter moved) or the inspected GUID changed -> the late retry doesn't store
  talent.inspect = nil -- A's talents not there at 0 s
  GCA:TryInspectTalents("Late Paw", "DRUID", 40, "G-A", GCA.inspectGen)
  GCA:OnInspectReady("G-B")  -- B's INSPECT_READY bumps the counter (unit unknown here: nothing else happens)
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } } -- B's talents now in the inspect config
  advance(2)
  check(GCA:MemberSpec("Late Paw", "DRUID", {}) == nil and GCA.db.specs["Late Paw"] == nil, "counter moved -> late retry stores nothing under A")
  talent.inspect = nil
  GCA:TryInspectTalents("Late Two", "DRUID", 40, "G-A2", GCA.inspectGen)
  GCA.inspectGUID = "G-B2" -- e.g. NotifyInspect on someone else, GUID only
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  advance(2)
  check(GCA.db.specs["Late Two"] == nil, "inspected GUID changed -> late retry stores nothing")
  local g0 = GCA.inspectGen
  GCA:OnNotifyInspect("player")
  check(GCA.inspectGen == g0 + 1 and GCA.inspectGUID == "G-me", "NotifyInspect hook bumps the counter and records the GUID")
  talent.inspect = nil
  GCA.inspectGUID = "G-C"
  GCA:TryInspectTalents("Late Ok", "DRUID", 40, "G-C", GCA.inspectGen)
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  advance(2)
  check(GCA:MemberSpec("Late Ok", "DRUID", {}) == "BALANCE", "control: nothing moved -> the 0.3 s retry stores")
  local ok = pcall(GCA.SpecDebug, GCA)
  check(ok, "/gca spec debug runs without error")
end

---------------------------------------------------------------------------
section("Debug: /gca stats <item link>")
---------------------------------------------------------------------------
do
  addItem(900020, "Hit Ring", "INVTYPE_FINGER", 30, { ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_STRANGE_SHORT = 1 })
  printed = {}
  env.SlashCmdList.GUILDCRAFTADVISOR("stats |cff|Hitem:900020::::::::40:1488|h[Hit Ring]|h|r")
  local all = table.concat(printed, "\n")
  check(all:find("ITEM_MOD_HIT_RATING_SHORT=10") and all:find("MeleeHit=1") and all:find("SpellHit=1") and all:find("unmapped: ITEM_MOD_STRANGE_SHORT"),
    "raw keys, canonical result and unmapped keys printed")
end


---------------------------------------------------------------------------
section("G: generator (row counts, escaped quotes, negative IDs, intermediates, faction, shipped = regenerated)")
---------------------------------------------------------------------------
local GEN_OUT = os.getenv("TEMP") and (os.getenv("TEMP"):gsub("\\", "/") .. "/gca_gen_test/") or nil
do
  local function runGen(cjDir, outDir)
    local savedArg = arg
    arg = { [0] = "gen_recipes.lua", cjDir or "", "", outDir }
    local realStderr = io.stderr
    local errLines = {}
    io.stderr = { write = function(_, ...) for i = 1, select("#", ...) do errLines[#errLines + 1] = select(i, ...) end end }
    local ok, err = pcall(function() assert(loadfile(ROOT .. "dev/gen_recipes.lua"))() end)
    io.stderr = realStderr
    arg = savedArg
    return ok, err, table.concat(errLines)
  end
  local function readAll(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("a"); f:close(); return s end
  if not GEN_OUT then
    check(false, "TEMP not set: generator test skipped")
  else
    os.execute('mkdir "' .. (GEN_OUT .. "Data"):gsub("/", "\\") .. '" 2>nul')
    local ok, err, report = runGen(nil, GEN_OUT)
    check(ok, "generator runs and its own row-count asserts pass " .. (ok and "" or tostring(err)))
    local same = true
    for _, f in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting", "Enchants" }) do
      local a, b = readAll(GEN_OUT .. "Data/" .. f .. ".lua"), readAll(ROOT .. "Data/" .. f .. ".lua")
      if not a or a ~= b then same = false; print("    differs: " .. f) end
    end
    check(same, "shipped Data/*.lua are byte-identical to a fresh generator run")
    check(report:find("Leatherworking: 501 item rows (skipped 0 negative, 2 intermediate)", 1, true)
      and report:find("Enchanting: 62 item rows (skipped 10 negative", 1, true), "report: LW 2 intermediates, Enchanting 10 negative IDs skipped")
    -- a source with one extra row must fail the count assert (copy CJ's Blacksmithing with a fake recipe added)
    local cj = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/CraftersJournal/Data/"
    local fake = GEN_OUT .. "cj/"
    os.execute('mkdir "' .. fake:gsub("/", "\\") .. '" 2>nul')
    for _, f in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
      local src = readAll(cj .. f .. ".lua")
      if f == "Blacksmithing" then
        local n
        src, n = src:gsub("(  recipes = {\r?\n)", "%1    [999999] = { name = \"Fake\", t = { 1, 1, 1, 1 }, r = { { 1, 1 } }, out = { 999998, 1 } },\n", 1)
        assert(n == 1, "fake row not inserted")
      end
      local o = io.open(fake .. f .. ".lua", "wb"); o:write(src); o:close()
    end
    local ok2, err2 = runGen(fake, GEN_OUT)
    check(not ok2 and tostring(err2):find("Blacksmithing: 439 rows, expected 438", 1, true), "an extra source row fails the count assert: " .. tostring(err2):sub(1, 80))
    runGen(nil, GEN_OUT) -- leave a clean copy
  end
  local R = ns.Recipes
  local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  check(count(R.Leatherworking) == 501 and count(R.Blacksmithing) == 438 and count(R.Tailoring) == 398
    and count(R.Engineering) == 251 and count(R.Enchanting) == 62,
    ("loaded rows LW %d, BS %d, Tailoring %d, Engineering %d, Enchanting items %d"):format(count(R.Leatherworking),
      count(R.Blacksmithing), count(R.Tailoring), count(R.Engineering), count(R.Enchanting)))
  check(R.Engineering[12720] and R.Engineering[12720].name == 'Goblin "Boom" Box' and R.Engineering[12720].item == 10580,
    "Goblin \"Boom\" Box present, escaped quotes round-trip")
  local neg = false
  for _, prof in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
    for id in pairs(R[prof]) do if id < 0 then neg = true end end
  end
  check(not neg, "no negative recipe IDs (conversions) anywhere")
  local inter = false
  for _, r in pairs(R.Leatherworking) do if r.item == 10482 or r.item == 22331 then inter = true end end
  check(not inter, "intermediates Cured Thick Hide / Rugged Leather left out")
  check(R.Tailoring[1229504].faction == "Horde" and R.Tailoring[1263425].faction == "Alliance", "faction carried (Tailoring 1229504 Horde, 1263425 Alliance)")
  check(R.Tailoring[461692] and R.Leatherworking[461692] and R.Leatherworking[22815].item == 18258 and R.Tailoring[22813].item == 18258,
    "461692 in Tailoring and LW; item 18258 made by 22815 (LW) and 22813 (Tailoring)")
  local E = ns.Enchants.rows
  local kinds = {}
  for _, r in ipairs(E) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
  check(#E == 175 and kinds.stats == 122 and kinds.damage == 10 and kinds.utility == 27 and kinds.proc == 16,
    ("enchant table %d rows: stats %d, damage %d, utility %d, proc %d"):format(#E, kinds.stats or 0, kinds.damage or 0, kinds.utility or 0, kinds.proc or 0))
  local d = GCA:EnchantData()
  check(d.bySpell[1217203] == nil and d.bySpell[435481] == nil and d.bySpell[13419] ~= nil, "SimGear-only 1217203 and CJ-only 435481 not in the table")
end

---------------------------------------------------------------------------
section("G: CanWear matrix (class x level 39/40 x subclass) against SimGear's Classes.lua")
---------------------------------------------------------------------------
do
  assert(loadfile(SG .. "SimGearForever/Classes.lua", "t", sgEnv()))("SimGearForever", SGns)
  local SGC = SGns.Classes
  local LEVEL_GATE = { [3] = { HUNTER = 40, SHAMAN = 40 }, [4] = { WARRIOR = 40, PALADIN = 40 } }
  local LOC = { [1] = "INVTYPE_CHEST", [2] = "INVTYPE_CHEST", [3] = "INVTYPE_CHEST", [4] = "INVTYPE_CHEST", [6] = "INVTYPE_SHIELD",
    [7] = "INVTYPE_RELIC", [8] = "INVTYPE_RELIC", [9] = "INVTYPE_RELIC" }
  local bad, n = 0, 0
  for _, class in ipairs(CLASSES) do
    for sub, loc in pairs(LOC) do
      for _, level in ipairs({ 39, 40 }) do
        local barred = SGC.barredType(class, { classID = 4, subclassID = sub, equipLoc = loc })
        local gate = LEVEL_GATE[sub] and LEVEL_GATE[sub][class]
        local expect = barred == nil and not (gate and level < gate)
        local got = GCA:CanWear(class, level, { classID = 4, subClassID = sub, equipLoc = loc })
        n = n + 1
        if got ~= expect then bad = bad + 1; print(("    %s lvl %d sub %d: got %s, expected %s"):format(class, level, sub, tostring(got), tostring(expect))) end
      end
    end
    -- held off-hand (subclass 0) and cloak: SimGear's noHoldable rule; cloaks for all
    local hold = GCA:CanWear(class, 40, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" })
    local sgHold = SGC.barredType(class, { classID = 4, subclassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) == nil
    if hold ~= sgHold then bad = bad + 1; print("    holdable " .. class) end
    if not GCA:CanWear(class, 1, { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK" }) then bad = bad + 1 end
    n = n + 2
  end
  check(bad == 0, ("%d class/level/subclass cases match SimGear's equip tables + level gates (%d differ)"):format(n, bad))
  check(GCA:CanWear("PALADIN", 20, { classID = 4, subClassID = 7, equipLoc = "INVTYPE_RELIC" }) and
    not GCA:CanWear("SHAMAN", 20, { classID = 4, subClassID = 7, equipLoc = "INVTYPE_RELIC" }) and
    GCA:CanWear("DRUID", 20, { classID = 4, subClassID = 8, equipLoc = "INVTYPE_RELIC" }) and
    GCA:CanWear("SHAMAN", 20, { classID = 4, subClassID = 9, equipLoc = "INVTYPE_RELIC" }), "relics: libram Paladin, idol Druid, totem Shaman only")
  check(not GCA:CanWear("ROGUE", 60, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) and
    not GCA:CanWear("HUNTER", 60, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) and
    GCA:CanWear("MAGE", 1, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }), "held off-hands: not for Hunters/Rogues")
  check(GCA:CanWear("WARRIOR", 60, { classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON" }), "W: a Warrior can wield a one-handed sword")
  check(GCA.SLOTS_FOR.INVTYPE_RELIC[1] == 18 and GCA.SLOTS_FOR.INVTYPE_WEAPON[2] == 17 and GCA.SLOTS_FOR.INVTYPE_2HWEAPON[1] == 16
    and GCA.SLOTS_FOR.INVTYPE_RANGEDRIGHT[1] == 18 and GCA.SLOTS_FOR.INVTYPE_THROWN[1] == 18 and GCA.SLOTS_FOR.INVTYPE_WEAPONOFFHAND[1] == 17,
    "SLOTS_FOR (W1): relic -> 18, one-hander 16/17, two-hander 16, off-hand weapon 17, ranged/wand/thrown 18")
end

---------------------------------------------------------------------------
section("G: professions, known recipes per profession, selector, browse, caches")
---------------------------------------------------------------------------
local profState = { list = { 1 }, lines = { [1] = { "Lederverarbeitung", 225, 300, 165 } } }
env.GetProfessions = function() return table.unpack(profState.list) end
env.GetProfessionInfo = function(i) local p = profState.lines[i]; if p then return p[1], nil, p[2], p[3], nil, nil, p[4] end end
local function setProfs(spec) -- spec: { {name, rank, max, line}, ... } or {} (nothing listed)
  profState.list, profState.lines = {}, {}
  for i, p in ipairs(spec) do profState.list[i] = i; profState.lines[i] = p end
end
do
  -- old flat known store (0.3.0) is moved under Leatherworking
  GCA.db.known[GCA.charKey] = { [2149] = true, [2160] = true }
  local store = GCA:KnownStore()
  check(store.Leatherworking and store.Leatherworking[2149] and store[2149] == nil, "0.3.0 flat known IDs moved under Leatherworking")
  -- LW + Tailoring; 461692 known (IsSpellKnown says yes) -> known in both
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schneiderei", 200, 300, 197 } })
  known[461692] = true
  GCA:RefreshKnown()
  check(GCA:IsKnown(461692, "Leatherworking") and GCA:IsKnown(461692, "Tailoring") and not GCA:IsKnown(461692, "Blacksmithing"),
    "461692 known in LW and Tailoring (both yours), not in Blacksmithing")
  check(GCA:ItemToSpell("Leatherworking")[18258] == 22815 and GCA:ItemToSpell("Tailoring")[18258] == 22813
    and GCA:ItemToSpell("Leatherworking")[227855] == 461692 and GCA:ItemToSpell("Tailoring")[227855] == 461692,
    "itemToSpell per profession: 18258 -> 22815 (LW) / 22813 (Tailoring)")
  check(GCA:SelectedProfession() == "Leatherworking" and not GCA:IsBrowse(), "default selection: your first gear profession (LW)")
  -- selector: Tailoring (yours) -> itemToSpell follows; Blacksmithing (not yours) -> browse
  GCA:SelectProfession("Tailoring")
  check(GCA.itemToSpell[18258] == 22813 and GCA.db.profSel[GCA.charKey] == "Tailoring", "switch to Tailoring: itemToSpell rebuilt, choice saved per character")
  GCA:SelectProfession("Blacksmithing")
  check(GCA:IsBrowse() and GCA:IsBrowse("Blacksmithing") and not GCA:IsBrowse("Leatherworking"), "Blacksmithing is browse (not yours)")
  GCA:SelectProfession("Leatherworking")
  -- dropping Tailoring clears its saved IDs (G7.6), bumps knownGen
  local gen = GCA.knownGen
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  check(GCA.db.known[GCA.charKey].Tailoring == nil and not GCA:IsKnown(461692, "Tailoring") and GCA.knownGen == gen + 1,
    "Tailoring dropped: its saved known IDs cleared, knownGen bumped")
  -- an empty GetProfessions right after login is not trusted: nothing cleared
  setProfs({})
  GCA.loginTime = now
  local _, trusted = GCA:ReadProfessions()
  GCA:RefreshKnown()
  check(not trusted and GCA.db.known[GCA.charKey].Leatherworking ~= nil, "empty GetProfessions within 10 s of login: not trusted, LW kept")
  advance(11)
  _, trusted = GCA:ReadProfessions()
  check(trusted, "... trusted 10 s after login (a character without professions)")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
end

do
  -- browse: everything unlearned, Offer hidden, no counts; cache keyed by profession
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  assert(loadfile(ROOT .. "UI.lua", "t", env))("RavenquillExpedition_CraftAdvisor", uiNs)
  local UIx = GCA.UI
  GCA.UI = savedUI
  -- a Paladin Ret Lv45 guildie with empty chest; a BS recipe the game says we know (IsSpellKnown) while BS is not ours
  local bsSpell, bsItem
  for spellID, r in pairs(ns.Recipes.Blacksmithing) do if not bsSpell or spellID < bsSpell then bsSpell, bsItem = spellID, r.item end end
  addItem(bsItem, "BS Chest", "INVTYPE_CHEST", 40, { ITEM_MOD_STRENGTH_SHORT = 10, RESISTANCE0_NAME = 300 }, 4)
  known[bsSpell] = true
  GCA.candidates = nil
  local key = "Pala Plate"
  GCA.db.members[key] = { class = "PALADIN", level = 45, items = {}, ts = 1, source = "inspect" }
  GCA.roster[key] = { class = "PALADIN", level = 45, online = true }
  GCA:SetManualSpec(key, "PALADIN", "RETRIBUTION")
  local view = { key = key, class = "PALADIN", level = 45, items = {}, spec = "RETRIBUTION" }
  local lwList = GCA:MemberSuggestions(view, false, "Leatherworking")
  GCA:SelectProfession("Blacksmithing")
  local bsList = GCA:MemberSuggestions(view, false)
  local chest
  for _, s in ipairs(bsList) do if s.cand.itemID == bsItem then chest = s end end
  check(chest and chest.known == false, "browse forces show-unlearned and nothing counts as known (even a spell the game reports known)")
  check(bsList ~= lwList and GCA:MemberSuggestions(view, false, "Leatherworking") == lwList, "suggestion cache per profession: switching doesn't serve LW's list, LW's stays cached")
  -- defence in depth: even if a browsed profession had a known set in memory, browse shows it as not learned
  GCA.knownNow.Blacksmithing = { [bsSpell] = true }
  GCA.sugCache = {}
  local again
  for _, s in ipairs(GCA:MemberSuggestions(view, false)) do if s.cand.itemID == bsItem then again = s end end
  check(again and again.known == false, "browse ignores a stale known set of that profession")
  GCA:RefreshKnown()
  local en
  for _, e in ipairs(GCA:GetMemberList()) do if e.key == key then en = e end end
  check(en and en.browse and en.knownCount == 0 and en.best == nil and #en.suggestions > 0, "browse: member badge/order count nothing (knownCount 0, no best)")
  check(not UIx.CanOffer(en, chest), "browse: Offer hidden")
  local counts = GCA:UpgradeCounts()
  local hasBS = false
  for _, c in ipairs(counts) do if c.prof == "Blacksmithing" then hasBS = true end end
  check(not hasBS and #counts == 1 and counts[1].prof == "Leatherworking", "minimap counts: only your professions (LW), never the browsed one")
  -- the same recipe as your own profession: known, Offer shown (online or not), text per profession
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  local own = GCA:MemberSuggestions(view, false)
  local chest2
  for _, s in ipairs(own) do if s.cand.itemID == bsItem then chest2 = s end end
  check(chest2 and chest2.known and not GCA:IsBrowse(), "Blacksmithing now yours: same recipe known (cache invalidated by browse flag + knownGen)")
  check(UIx.CanOffer({ key = key, online = true }, chest2) and not UIx.CanOffer({ key = key, online = false }, chest2)
    and UIx.OfferText("Blacksmithing", chest2):find("I'm a blacksmith", 1, true),
    "item Offer only while the member is online (H3 U3); whisper says blacksmith")
  check(not UIx.CanOffer({ key = key, online = true }, { kind = "item", known = false }), "unlearned row: no Offer")
  check(UIx.OfferText("Leatherworking", chest2):find("leatherworker", 1, true) and UIx.OfferText("Engineering", chest2):find("an engineer", 1, true),
    "whisper text per profession")
  local en2
  for _, e in ipairs(GCA:GetMemberList()) do if e.key == key then en2 = e end end
  check(en2 and en2.knownCount >= 1 and en2.best and en2.best.known, "own profession: badge counts known suggestions")
  -- faction: an unlearned recipe of the other side is not suggested
  env.UnitFactionGroup = function() return "Alliance" end
  check(GCA.PlayerFaction() == "Alliance", "faction read")
  -- restrictions (tooltip): "Requires Engineering (225)" / "Classes: Druid"
  local tipLines = {}
  env.C_TooltipInfo = { GetItemByID = function(id) local l = tipLines[id]; if l then local t = {} for i, s in ipairs(l) do t[i] = { leftText = s } end return { lines = t } end end }
  tipLines[bsItem] = { "BS Chest", "Requires Level 40", "Classes: Warrior" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and GCA:PassesRestrictions(bsItem, "WARRIOR", false), "Classes: Warrior bars a Paladin; \"Requires Level 40\" isn't a skill (no localized class table: token match)")
  env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_SKILL = "Klassen: %s", "Benötigt %s"
  env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Krieger", PALADIN = "Paladin" }
  tipLines[bsItem] = { "BS Chest", "Benötigt Stufe 40", "Klassen: Krieger" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and GCA:PassesRestrictions(bsItem, "WARRIOR", false), "German client: \"Klassen: Krieger\" bars a Paladin")
  env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_SKILL, env.LOCALIZED_CLASS_NAMES_MALE = nil, nil, nil
  tipLines[bsItem] = { "BS Chest", "Requires Engineering (225)" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and not GCA:PassesRestrictions(bsItem, "PALADIN", true),
    "Requires Engineering: not for guildies, not for you without Engineering")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Engineering", 250, 300, 202 } })
  GCA:ReadProfessions()
  check(GCA:PassesRestrictions(bsItem, "PALADIN", true), "... for you with Engineering: yes")
  tipLines[bsItem] = nil
  GCA.restrCache = nil
  env.C_TooltipInfo = nil
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  -- own -> browse with an unchanged (empty) known set: only the browse flag in the cache signature tells them apart
  known[bsSpell] = nil
  GCA.db.known[GCA.charKey].Blacksmithing = {}
  GCA:RefreshKnown()
  GCA:SelectProfession("Blacksmithing")
  GCA.db.settings.showUnlearned = false
  local gen0 = GCA.knownGen
  local ownList = GCA:MemberSuggestions(view, false)
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  local browseList = GCA:MemberSuggestions(view, false)
  check(#ownList == 0 and GCA.knownGen == gen0 and #browseList > 0 and browseList ~= ownList,
    ("own BS with nothing known: %d rows; dropped -> browse (knownGen unchanged): %d rows, not the cached list"):format(#ownList, #browseList))
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  known[bsSpell] = true
  GCA:RefreshKnown()
  -- W1: a weapon a profession makes is a candidate now
  local wSpell = 999990
  addItem(999991, "Some Sword", "INVTYPE_WEAPON", 40, { ITEM_MOD_STRENGTH_SHORT = 99 }, 7); itemDB[999991].classID = 2
  ns.Recipes.Blacksmithing[wSpell] = { item = 999991, skill = 1, src = "trainer", name = "Some Sword", r = {} }
  GCA.candidates = nil
  local isCand = false
  for _, c in ipairs(GCA:GetCandidates("Blacksmithing")) do if c.itemID == 999991 then isCand = true end end
  check(isCand, "W1: a crafted weapon is a candidate")
  ns.Recipes.Blacksmithing[wSpell] = nil
  GCA.candidates = nil
  GCA.db.members[key], GCA.roster[key] = nil, nil
  known[bsSpell] = nil
  GCA:SelectProfession("Leatherworking")
end

---------------------------------------------------------------------------
section("G: enchant suggestions (G4 + G7.1, G7.2, G7.7, G7.8, G7.9)")
---------------------------------------------------------------------------
do
  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  for id in pairs(known) do known[id] = nil end
  GCA:RefreshKnown()
  GCA:SelectProfession("Enchanting")
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  assert(loadfile(ROOT .. "UI.lua", "t", env))("RavenquillExpedition_CraftAdvisor", uiNs)
  local UIx = GCA.UI
  GCA.UI = savedUI
  local SUPERIOR, GREATER, MINOR = 1248599, 1248500, 7779 -- Bracer Agility +9 (7656), +7 (1887), +3 (247)
  local function learn(...) for _, id in ipairs({ ... }) do known[id] = true end GCA:RefreshKnown() end
  local function unlearn(id) known[id] = nil; GCA.db.known[GCA.charKey].Enchanting[id] = nil; GCA:RefreshKnown() end
  learn(SUPERIOR, GREATER, 13419 --[[Cloak Minor Agility]], 23800 --[[Weapon Agility]], 27837 --[[2H Agility]], 20030 --[[2H Superior Impact, damage]],
    1219577 --[[Off-Hand Superior Intellect]], 20017 --[[Shield Greater Stamina]], 13746 --[[Cloak Greater Defense]])
  check(GCA:IsKnown(SUPERIOR) and GCA.knownCounts.Enchanting >= 9, "enchant spells counted as known Enchanting spells (" .. GCA.knownCounts.Enchanting .. ")")
  addItem(910001, "Agile Bracers", "INVTYPE_WRIST", 40, { ITEM_MOD_AGILITY_SHORT = 5, RESISTANCE0_NAME = 40 })
  addItem(910002, "Plain Cloak", "INVTYPE_CLOAK", 40, { ITEM_MOD_AGILITY_SHORT = 4, RESISTANCE0_NAME = 30 }, 1)
  addItem(910003, "Robe", "INVTYPE_CHEST", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 80 })
  addItem(910004, "Big Staff", "INVTYPE_2HWEAPON", 40, { ITEM_MOD_AGILITY_SHORT = 10 }, 10); itemDB[910004].classID = 2
  addItem(910005, "Boots", "INVTYPE_FEET", 40, { ITEM_MOD_AGILITY_SHORT = 6, RESISTANCE0_NAME = 50 })
  local function lnk(id, ench) return "item:" .. id .. ":" .. (ench or "") .. ":::::::40:1488" end
  local function sugs(items, class, spec, level)
    GCA.sugCache = {}
    local list = GCA:ComputeSuggestions({ key = "Ench Test", class = class or "DRUID", level = level or 58, items = items, spec = spec or "FERAL_CAT" }, false)
    local by = {}
    -- section I: a slot lists up to 3 rows; the first one (SuggestionOrder) is the slot's best
    for _, s in ipairs(list) do if s.kind == "enchant" and not by[s.slot] then by[s.slot] = s end end
    return by, list
  end
  -- no enchant on the bracers -> Superior Agility, % of the bracers' own score
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local by = sugs({ [9] = lnk(910001) })
  local w = by[9]
  local base = GCA:Score(GCA:GetInfo(lnk(910001)), e)
  local val = Scoring.value({ Agility = 9 }, e.set)
  check(w and w.cand.spellID == SUPERIOR and w.tier == 1 and math.abs(w.pct - val / base) < 1e-9 and w.known,
    ("no enchant: Superior Agility, gain %% = enchant value / item score (%.1f%%)"):format(w and w.pct * 100 or -1))
  -- current Greater Agility (1887) -> Superior: gain = 9 - 7 Agility
  by = sugs({ [9] = lnk(910001, 1887) })
  w = by[9]
  local val7 = Scoring.value({ Agility = 7 }, e.set)
  check(w and w.cand.spellID == SUPERIOR and math.abs(w.pct - (val - val7) / base) < 1e-9 and w.current and w.current.enchant == 1887,
    "current Greater Agility: gain = (new − current) ÷ item score")
  -- current = best already (7656): nothing for the wrist
  by = sugs({ [9] = lnk(910001, 7656) })
  check(by[9] == nil, "already the best known enchant: no wrist suggestion")
  -- unknown 8483 (G7.1)
  by = sugs({ [9] = lnk(910001, 8483) })
  check(by[9] == nil, "unknown enchant 8483 on the wrist: no suggestion for that slot")
  -- proc current on the chest (Minor Absorption 44) / utility on the cloak (Minor Resistance 65)
  local bestChest, bestV
  for _, r in ipairs(GCA:EnchantData().bySlot.chest) do
    local v = r.kind == "stats" and Scoring.value(r.stats, e.set) or 0
    if v > 0 and (not bestV or v > bestV) then bestChest, bestV = r.spell, v end
  end
  learn(bestChest, 1219587 --[[Cloak Agility +5]])
  by = sugs({ [5] = lnk(910003), [15] = lnk(910002), [9] = lnk(910001) })
  check(by[5] and by[15] and by[9], "control: chest, cloak and wrist without enchants all get a suggestion")
  by = sugs({ [5] = lnk(910003, 44), [15] = lnk(910002, 65), [9] = lnk(910001) })
  check(by[5] == nil and by[15] == nil and by[9] ~= nil, "proc enchant on the chest / utility on the cloak: never replaced; wrist still suggested")
  -- utility and proc enchants are never suggested
  local anyBad = false
  for _, s in ipairs(select(2, sugs({ [5] = lnk(910003), [15] = lnk(910002), [9] = lnk(910001), [8] = lnk(910005) }))) do
    if s.kind == "enchant" and s.enchant.kind ~= "stats" then anyBad = true end
  end
  check(not anyBad, "only stat enchants are suggested (no utility/proc/damage rows)")
  -- shared enchant IDs (G7.7): 247 = Cloak Minor Agility AND Bracer Minor Agility; on the cloak it's recognised
  by = sugs({ [15] = lnk(910002, 247) })
  local d = GCA:EnchantData()
  check(d.byEnchant[247] and d.byEnchant[247].stats.Agility == 3, "shared enchant 247 looked up once (Agility 3)")
  local v5, v3 = Scoring.value({ Agility = 5 }, e.set), Scoring.value({ Agility = 3 }, e.set)
  check(by[15] and by[15].cand.spellID == 1219587 and by[15].current.enchant == 247 and math.abs(by[15].gain - (v5 - v3)) < 1e-9,
    "cloak with shared 247: recognised as +3 Agility, Cloak Agility (+5) suggested for the difference")
  -- empty slot: no enchant suggestion
  by = sugs({ [9] = nil, [15] = lnk(910002) })
  check(by[9] == nil, "empty wrist slot: no enchant suggestion")
  -- weapon rows on a two-hander: 2H Agility (+25) wins over Weapon Agility (+15); W5: a real % of the weapon's score
  by = sugs({ [16] = lnk(910004) })
  w = by[16]
  local staff = GCA:Score(GCA:GetInfo(lnk(910004)), e)
  check(w and w.cand.spellID == 27837 and w.status == "upgrade" and w.tier == 1
    and math.abs(w.pct - Scoring.value({ Agility = 25 }, e.set) / staff) < 1e-9,
    ("W5: 2H Agility on a two-hander: a real %% of the weapon's own score (%.0f%%)"):format(w and w.pct and w.pct * 100 or -1))
  unlearn(27837)
  by = sugs({ [16] = lnk(910004) })
  check(by[16] and by[16].cand.spellID == 23800, "2H: an Enchant Weapon (one-hand) row also goes on a two-hander")
  unlearn(23800)
  by = sugs({ [16] = lnk(910004) })
  local imp = Scoring.value({ TwoHandDps = 9 / 3.5 }, e.set)
  check(by[16] and by[16].cand.spellID == 20030 and math.abs(by[16].gain - imp) < 1e-9 and by[16].info.cstats.TwoHandDps,
    "W5: 2H Superior Impact (damage 9) scored as 9 ÷ 3.5 TwoHandDps (no speed read -> SimGear's assumed 3.5)")
  by = sugs({ [16] = lnk(910004, 943) })
  local str = Scoring.value({ TwoHandDps = 3 / 3.5 }, e.set)
  check(by[16] and by[16].cand.spellID == 20030 and math.abs(by[16].gain - (imp - str)) < 1e-9 and by[16].current.enchant == 943,
    "W5: Striking (943, damage 3) on the weapon is valued now: Superior Impact for the difference")
  -- the worn weapon's own speed is used when it was read
  GCA.infoCache[lnk(910004)] = nil
  local savedWS = GCA.WeaponSpeed
  GCA.WeaponSpeed = function() return 2.0 end
  by = sugs({ [16] = lnk(910004) })
  check(by[16] and math.abs(by[16].gain - Scoring.value({ TwoHandDps = 9 / 2.0 }, e.set)) < 1e-9,
    "W5: damage ÷ the worn weapon's speed (2.0) when it is known")
  GCA.WeaponSpeed = savedWS
  GCA.infoCache[lnk(910004)] = nil
  -- one-hander: MainHandDps at 2.6
  addItem(910006, "Club", "INVTYPE_WEAPON", 40, { ITEM_MOD_AGILITY_SHORT = 4 }, 4); itemDB[910006].classID = 2
  check(math.abs(GCA:EnchantStats(GCA:EnchantData().byEnchant[943], GCA:GetInfo(lnk(910006))).MainHandDps - 3 / 2.6) < 1e-9,
    "W5: Striking on a one-hander = 3 ÷ 2.6 MainHandDps")
  learn(27837, 23800)
  -- shield vs held off-hand
  addItem(910010, "Tome", "INVTYPE_HOLDABLE", 40, { ITEM_MOD_INTELLECT_SHORT = 6 }, 0)
  addItem(910011, "Buckler", "INVTYPE_SHIELD", 40, { ITEM_MOD_STAMINA_SHORT = 6, RESISTANCE0_NAME = 600 }, 6)
  by = sugs({ [17] = lnk(910010) }, "MAGE", "FIRE", 58)
  check(by[17] and by[17].enchant.slot == "offhand", "held off-hand: an Off-Hand enchant (" .. (by[17] and by[17].enchant.name or "none") .. ")")
  by = sugs({ [17] = lnk(910011) }, "WARRIOR", "PROTECTION", 58)
  check(by[17] and by[17].enchant.slot == "shield", "shield: a Shield enchant (" .. (by[17] and by[17].enchant.name or "none") .. ")")
  -- enchanted link stats include the enchant (one possible client behaviour): same result, base without enchant
  local realStats = env.C_Item.GetItemStats
  GCA.ItemAPI.Stats = function(l)
    local raw = realStats(l)
    local ench = tonumber(tostring(l):match("item:%d+:(%d+)"))
    local row = ench and d.byEnchant[ench]
    if not row or not row.stats then return raw end
    local copy = {}
    for k, v in pairs(raw) do copy[k] = v end
    copy.ITEM_MOD_AGILITY_SHORT = (copy.ITEM_MOD_AGILITY_SHORT or 0) + (row.stats.Agility or 0)
    return copy
  end
  GCA.infoCache = {}
  local inc = GCA:GetInfo(lnk(910001, 1887))
  check(inc and inc.cstats.Agility == 12, "mock: the enchanted link's stats now include the enchant (Agility 5 + 7)")
  by = sugs({ [9] = lnk(910001, 1887) })
  w = by[9]
  check(w and math.abs(w.pct - (val - val7) / base) < 1e-9 and math.abs(w.baseScore - base) < 1e-9,
    "GetItemStats including the enchant: base = item without enchant, same % as before")
  printed = {}
  env.SlashCmdList.GUILDCRAFTADVISOR("enchant debug " .. lnk(910001, 1887))
  check(table.concat(printed, "\n"):find("INCLUDED: Agility+7", 1, true), "/gca enchant debug reports 'included' in that case")
  GCA.ItemAPI.Stats = realStats
  GCA.infoCache = {}
  printed = {}
  env.SlashCmdList.GUILDCRAFTADVISOR("enchant debug " .. lnk(910001, 1887))
  check(table.concat(printed, "\n"):find("NOT included", 1, true), "... and 'NOT included' when the stats are the same")
  -- unsimmed school (SimGear Enchants.lua:100-110)
  check(GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { SpellPower = 1 } }) == "FirePower"
    and GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { SpellPower = 1, FirePower = 1 } }) == nil
    and GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { AttackPower = 1 } }) == nil, "unsimmed-school rule")
  -- Offer: known enchant, online only, "when we meet"
  by = sugs({ [9] = lnk(910001) })
  w = by[9]
  check(UIx.CanOffer({ online = true }, w) and not UIx.CanOffer({ online = false }, w), "enchant Offer only for online members")
  local txt = UIx.OfferText("Enchanting", w)
  check(txt:find("an enchanter", 1, true) and txt:find("when we meet", 1, true) and txt:find("Wrist", 1, true), "enchant whisper: " .. txt)
  -- browse Enchanting: all unlearned, no Offer
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  by = sugs({ [9] = lnk(910001) })
  check(by[9] and not by[9].known and not UIx.CanOffer({ online = true }, by[9]), "browse Enchanting: enchants shown as not learned, no Offer")
  -- tooltips don't error on enchant rows
  env.GameTooltip = setmetatable({}, { __index = function() return function() end end })
  local tipOk = pcall(UIx.ShowSuggestionTooltip, {}, by[9])
  check(tipOk, "suggestion tooltip renders an enchant row")
  -- known debug runs
  printed = {}
  local okD = pcall(GCA.KnownDebug, GCA)
  check(okD and table.concat(printed, "\n"):find("Enchanting enchant spells", 1, true) == nil
    and table.concat(printed, "\n"):find("Leatherworking item recipes", 1, true), "/gca known debug runs (only your professions probed)")
  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  GCA:RefreshKnown()
  printed = {}
  pcall(GCA.KnownDebug, GCA)
  check(table.concat(printed, "\n"):find("Enchanting enchant spells: 175 in data", 1, true), "/gca known debug probes enchant spells separately")
  for id in pairs(known) do known[id] = nil end
  GCA:SelectProfession("Leatherworking")
end

---------------------------------------------------------------------------
section("H: look-ahead order (H5.2), crafted marks (H5.1), locale + whisper (H4/U2), offline Offer (U3)")
---------------------------------------------------------------------------
do
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  assert(loadfile(ROOT .. "UI.lua", "t", env))("RavenquillExpedition_CraftAdvisor", uiNs)
  local UIx = GCA.UI
  GCA.UI = savedUI

  -- unit: inside each tier the wearable ones first, look-ahead after; Better (per-slot pick) unchanged
  local O, B = GCA.SuggestionOrder, GCA.BetterSuggestion
  local list = {
    { tier = 1, points = 9, known = true, slot = 1, future = true, name = "future9" },
    { tier = 1, points = 2, known = true, slot = 2, name = "now2" },
    { tier = 1, points = 50, known = true, slot = 3, future = true, name = "future50" },
    { tier = 1, points = 5, known = true, slot = 4, name = "now5" },
    { tier = 1, points = 4, known = true, slot = 6, name = "now4" },
    { tier = GCA.TIER_PARTNER, points = 1, known = true, slot = 7, name = "partner" },
  }
  table.sort(list, O)
  local order = {}
  for i, x in ipairs(list) do order[i] = x.name end
  check(table.concat(order, ",") == "now5,now4,now2,future50,future9,partner",
    "H5.2 order: look-ahead after the wearable ones in each tier: " .. table.concat(order, ","))
  check(B(list[4], list[1]), "per-slot pick (Better) still takes the bigger look-ahead gain")

  -- end to end: a Lv40 cat, legs craft wearable now (+small), gloves craft at Lv43 (+big)
  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local sLegs, sHands = spells[1], spells[2]
  local iLegs, iHands = ns.Recipes.Leatherworking[sLegs].item, ns.Recipes.Leatherworking[sHands].item
  local saved = { [iLegs] = itemDB[iLegs], [iHands] = itemDB[iHands] }
  addItem(iLegs, "Now Legs", "INVTYPE_LEGS", 38, { ITEM_MOD_AGILITY_SHORT = 14, RESISTANCE0_NAME = 100 })
  addItem(iHands, "Later Gloves", "INVTYPE_HAND", 43, { ITEM_MOD_AGILITY_SHORT = 30 })
  addItem(990001, "Worn Legs", "INVTYPE_LEGS", 30, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 100 })
  addItem(990002, "Worn Gloves", "INVTYPE_HAND", 30, { ITEM_MOD_AGILITY_SHORT = 8 })
  GCA.infoCache[iLegs], GCA.infoCache[iHands] = nil, nil
  GCA.candidates = nil
  known[sLegs], known[sHands] = true, true
  GCA:RefreshKnown()
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local items = { [7] = link(990001), [10] = link(990002) }
  GCA.sugCache = {}
  local l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local legs, hands
  for i, s in ipairs(l) do if s.slot == 7 then legs = i elseif s.slot == 10 then hands = i end end
  local H = hands and l[hands]
  check(legs and hands and legs < hands and H.future and H.wearAt == 43 and H.levelsToGo == 3 and not l[legs].future
    and H.points > l[legs].points, "Lv43 gloves (bigger gain) listed after the wearable legs; wearAt 43, 3 levels to go")
  check(UIx.WearableText(H) == "wearable at level 43 (in 3 levels)", "label: " .. tostring(H and UIx.WearableText(H)))
  GCA.db.settings.lookahead = false
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local anyFuture = false
  for _, s in ipairs(l) do if s.future then anyFuture = true end end
  check(not anyFuture and #l >= 1, "look-ahead off: no too-high-level items")
  GCA.db.settings.lookahead = true

  -- review M-2: a wearable gloves craft (small gain) and the Lv43 gloves (big gain) for the same slot: both listed,
  -- the wearable one first; a look-ahead craft no better than the wearable one is not listed; best = wearable
  local sNowHands, sWorseLater = spells[3], spells[4]
  local iNowHands, iWorseLater = ns.Recipes.Leatherworking[sNowHands].item, ns.Recipes.Leatherworking[sWorseLater].item
  saved[iNowHands], saved[iWorseLater] = itemDB[iNowHands], itemDB[iWorseLater]
  addItem(iNowHands, "Now Gloves", "INVTYPE_HAND", 38, { ITEM_MOD_AGILITY_SHORT = 12 })
  addItem(iWorseLater, "Worse Later Gloves", "INVTYPE_HAND", 44, { ITEM_MOD_AGILITY_SHORT = 11 })
  GCA.infoCache[iNowHands], GCA.infoCache[iWorseLater] = nil, nil
  GCA.candidates = nil
  known[sNowHands] = true
  GCA:RefreshKnown()
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local nowI, laterI
  for i, s in ipairs(l) do
    if s.cand.itemID == iNowHands then nowI = i elseif s.cand.itemID == iHands then laterI = i end
  end
  check(nowI and laterI and nowI < laterI and not l[nowI].future and l[laterI].future,
    "M-2: wearable gloves AND the bigger Lv43 gloves both listed, wearable first (" .. tostring(nowI) .. ", " .. tostring(laterI) .. ")")
  local _, bestNow = GCA.KnownOnly(l)
  check(bestNow and not bestNow.future, "M-2: the member's best is a wearable craft")
  -- only a worse look-ahead craft for the slot (the big one not known): it is not listed
  known[sHands] = nil
  known[sWorseLater] = true
  GCA:RefreshKnown()
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local hasNow, hasWorse = false, false
  for _, s in ipairs(l) do
    if s.cand.itemID == iNowHands then hasNow = true elseif s.cand.itemID == iWorseLater then hasWorse = true end
  end
  check(hasNow and not hasWorse, "M-2: a look-ahead craft no better than the wearable one is not listed")
  known[sHands], known[sWorseLater], known[sNowHands] = true, nil, nil
  GCA:RefreshKnown()
  GCA.sugCache = {}
  -- KnownOnly prefers wearable even across tiers (a tier-2 wearable over a tier-1 look-ahead)
  local syn = { { known = true, future = true, tier = 1, name = "f1" }, { known = false, tier = 1, name = "u1" }, { known = true, tier = 2, name = "w2" } }
  local nk, bk = GCA.KnownOnly(syn)
  check(nk == 2 and bk == syn[3], "M-2: KnownOnly counts known rows and picks the first wearable as best")
  check(select(2, GCA.KnownOnly({ syn[1] })) == syn[1], "M-2: only look-ahead known -> that one is the best")

  -- H5.1 crafted marks: craft mark cleared when the item is worn (any slot), kept otherwise; enchant by enchant ID
  local who = "Kit Paw"
  GCA.db.members[who] = { class = "DRUID", level = 40, items = items, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", H, true)
  local mark = GCA:CraftedMark(who, "Leatherworking", sHands)
  check(mark and mark.item == iHands and mark.slot == 10 and GCA.db.crafted[GCA.charKey][who].Leatherworking[sHands] == mark,
    "mark stored per character / member / profession / spellID")
  GCA:StoreRecord(who, "DRUID", 40, { [7] = link(990001), [10] = link(990002) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "a record without the item keeps the mark")
  GCA:StoreRecord("Other Guy", "DRUID", 40, { [10] = link(iHands) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "someone else wearing it doesn't clear it")
  GCA.db.members["Other Guy"] = nil
  GCA:StoreRecord(who, "DRUID", 43, { [7] = link(990001), [10] = link(iHands) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) == nil and GCA.db.crafted[GCA.charKey][who] == nil, "a record showing it worn clears the mark")
  -- persistence: survives a reload (ADDON_LOADED keeps db.crafted)
  GCA:SetCrafted(who, "Leatherworking", H, true)
  fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "mark survives ADDON_LOADED (SavedVariables)")
  GCA:SetCrafted(who, "Leatherworking", H, false)
  check(GCA:CraftedMark(who, "Leatherworking", sHands) == nil, "untick removes it")
  -- review M-3: the member already wears one copy when you tick (a ring of a pair you made earlier)
  addItem(990020, "Crafted Ring", "INVTYPE_FINGER", 30, { ITEM_MOD_AGILITY_SHORT = 5 })
  local ring = { kind = "item", cand = { spellID = 990021, itemID = 990020 }, slot = 12 }
  GCA.db.members[who] = { class = "DRUID", level = 40, items = { [11] = link(990020), [10] = link(990002) }, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", ring, true)
  local rm = GCA:CraftedMark(who, "Leatherworking", 990021)
  check(rm and rm.had and rm.had[11] and rm.count == 1, "M-3: mark remembers the slots already holding the item (11, count 1)")
  GCA:StoreRecord(who, "DRUID", 41, { [11] = link(990020), [10] = link(990002) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) ~= nil, "M-3: the old copy in the same slot does NOT clear the mark")
  GCA:StoreRecord(who, "DRUID", 41, { [11] = link(990020), [12] = link(990020) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) == nil, "M-3: a second copy (new slot, count 2) clears it")
  GCA.db.members[who] = { class = "DRUID", level = 40, items = { [11] = link(990020) }, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", ring, true)
  GCA:StoreRecord(who, "DRUID", 41, { [12] = link(990020) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) == nil, "M-3: the item showing up in a slot that didn't hold it clears it")
  GCA.db.members[who] = { class = "DRUID", level = 40, items = items, ts = 1, source = "inspect" }
  -- enchant: wrist mark for enchant ID 247; another enchant on the slot keeps it, 247 clears it
  local ench = { kind = "enchant", cand = { spellID = 7779, enchant = true }, enchant = { enchant = 247 }, slot = 9 }
  GCA:SetCrafted(who, "Enchanting", ench, true)
  local em = GCA:CraftedMark(who, "Enchanting", 7779)
  check(em and em.enchant == 247 and em.slot == 9 and em.item == nil, "enchant mark keeps the enchant ID and slot")
  GCA:StoreRecord(who, "DRUID", 43, { [9] = "item:990003:248::::::::40:1488", [10] = "item:990004:247::::::::40:1488" }, "inspect")
  check(GCA:CraftedMark(who, "Enchanting", 7779) ~= nil, "a different enchant on the slot (or 247 on another slot) keeps it")
  GCA:StoreRecord(who, "DRUID", 43, { [9] = "item:990003:247::::::::40:1488" }, "inspect")
  check(GCA:CraftedMark(who, "Enchanting", 7779) == nil, "enchant 247 on the wrist clears it")
  -- marks of another character of yours are cleared too
  GCA.db.crafted["Alt Char-Realm"] = { [who] = { Leatherworking = { [sHands] = { item = iHands, slot = 10, t = 1 } } } }
  GCA:StoreRecord(who, "DRUID", 43, { [10] = link(iHands) }, "inspect")
  check(GCA.db.crafted["Alt Char-Realm"][who] == nil, "an alt's mark for the same member is cleared as well")
  GCA.db.members[who] = nil

  -- U3: no Offer for offline members (craft and enchant)
  check(UIx.CanOffer({ key = who, online = true }, H) and not UIx.CanOffer({ key = who, online = false }, H)
    and not UIx.CanOffer({ key = who, online = false }, { kind = "enchant", known = true }), "Offer only for online members (craft + enchant)")

  -- H4 locale: deDE key -> German, missing deDE key -> English, missing everywhere -> the key
  local L = ns.L
  ns.Locales.enUS.__TEST_ONLY_EN = "English only"
  ns.locale = "deDE"
  check(L.OPTIONS == "Optionen" and L.__TEST_ONLY_EN == "English only" and ns.LGet("__NOPE__") == nil and L.__NOPE__ == "__NOPE__"
    and ns.missingL.__NOPE__, "deDE: German; key missing in deDE -> English; missing everywhere -> key (noted)")
  check(GCA:SpecName("ROGUE", "COMBAT") == "Kampf" and GCA:SpecName("PRIEST", "SMITE") == "Göttliche Pein (Schaden)", "spec names in German")
  -- German whisper with all placeholders
  local d = { kind = "item", info = { link = "|cff1eff00|Hitem:4244::::|h[Hillmans Lederweste]|h|r", name = "Hillmans Lederweste" }, slot = 5 }
  local txt = UIx.OfferText("Leatherworking", d, "Bud Stone")
  check(txt:find("^Hallo Bud! Ich bin Lederverarbeiter und könnte dir |cff1eff00|Hitem:4244::::|h%[Hillmans Lederweste%]|h|r herstellen") and txt:find("Interesse%?$"),
    "German craft whisper: " .. txt)
  local et = UIx.OfferText("Enchanting", { kind = "enchant", info = { name = "Armschiene - Beweglichkeit" }, slot = 9 }, "Bud Stone")
  check(et:find("Ich bin Verzauberer", 1, true) and et:find("Armschiene - Beweglichkeit", 1, true) and et:find("wenn wir uns treffen", 1, true), "German enchant whisper: " .. et)
  -- user template: placeholders filled literally ("%" in values can't break gsub); no member name -> no dangling space
  GCA.db.settings.whisperCraft = "Moin {name}: {item} ({slot}) – 100%? {crafter}"
  local d2 = { kind = "item", info = { link = "[50% off]", name = "x" }, slot = 5 }
  check(UIx.OfferText("Tailoring", d2, "Bud Stone") == "Moin Bud: [50% off] (Chest) – 100%? Schneider", "template with %: " .. UIx.OfferText("Tailoring", d2, "Bud Stone"))
  check(UIx.OfferText("Tailoring", d2, nil) == "Moin: [50% off] (Chest) – 100%? Schneider", "no name: " .. UIx.OfferText("Tailoring", d2, nil))
  GCA.db.settings.whisperCraft = "   "
  check(UIx.Template("craft") == ns.Locales.deDE.WHISPER_CRAFT, "blank saved template -> default of the client language")
  -- review L-2: over 255 bytes -> item name instead of the link; still too long -> cut on a UTF-8 boundary, told once
  local longLink = "|cff1eff00|Hitem:4244" .. string.rep(":", 100) .. "|h[Hillmans Lederweste]|h|r"
  local dl = { kind = "item", info = { link = longLink, name = "Hillmans Lederweste" }, slot = 5 }
  GCA.db.settings.whisperCraft = string.rep("\195\164", 60) .. " {item}" -- 60 x "ä" = 120 bytes, then the item
  local t1 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  check(#(string.rep("\195\164", 60) .. " " .. longLink) > 255 and t1 == string.rep("\195\164", 60) .. " Hillmans Lederweste",
    "L-2: too long with the link -> item name (" .. #t1 .. " bytes)")
  printed = {}
  UIx.warnedLong = nil
  GCA.db.settings.whisperCraft = "xy" .. string.rep("\195\164", 200) .. " {item}" -- byte 255 = first half of an umlaut
  local t2 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  local t3 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  local warned = 0
  for _, p in ipairs(printed) do if p:find("255 Bytes", 1, true) then warned = warned + 1 end end
  check(#t2 == 254 and t2 == "xy" .. string.rep("\195\164", 126) and t3 == t2 and warned == 1,
    "L-2: cut to " .. #t2 .. " bytes on a character boundary (not inside an umlaut), told once (" .. warned .. ")")
  check(UIx.Utf8Cut("ab|", 3) == "ab|" and UIx.Utf8Cut("abc|d", 4) == "abc" and UIx.Utf8Cut("a\226\130\172b", 3) == "a"
    and UIx.Utf8Cut("a\226\130\172b", 4) == "a\226\130\172", "Utf8Cut: no split characters, no dangling '|'")
  GCA.db.settings.whisperCraft = "{name}: {item}"
  check(UIx.OfferText("Leatherworking", dl, "Bud Stone") == "Bud: " .. longLink, "L-2: short enough -> the link stays")
  GCA.db.settings.whisperCraft = nil
  check(GCA:SourceLine(GCA:WeightSetFor("ROGUE", "COMBAT", 40)):find("Kampf Lv40 · simuliert · Levelbonus 50%", 1, true), "source line in German: "
    .. GCA:SourceLine(GCA:WeightSetFor("ROGUE", "COMBAT", 40)))
  ns.locale = "enUS"
  ns.Locales.enUS.__TEST_ONLY_EN = nil
  ns.missingL.__NOPE__ = nil

  -- static checks on the tables: every L.KEY / L["KEY"] used in the code exists in English; every German key exists in
  -- English (except "SPEC:" names); format specifiers match key by key; nothing printed a missing key so far
  local en, de = ns.Locales.enUS, ns.Locales.deDE
  local used, missingUse = {}, {}
  for _, f in ipairs({ "Core.lua", "UI.lua", "Sync.lua", "Spec.lua", "Minimap.lua" }) do
    local src = assert(io.open(ROOT .. f, "rb")):read("*a")
    for k in src:gmatch("[^%w_]L%.([%u_][%u%d_]*)") do used[k] = true end
    for k in src:gmatch("[^%w_]L%[\"([%u_][%u%d_]*)\"%]") do used[k] = true end
  end
  for _, def in ipairs(UIx.FILTERS) do used[def.label] = true; used[def.tip] = true end
  local nUsed = 0
  for k in pairs(used) do nUsed = nUsed + 1; if en[k] == nil then missingUse[#missingUse + 1] = k end end
  table.sort(missingUse)
  check(nUsed > 150 and #missingUse == 0, "all " .. nUsed .. " keys used in the code exist in enUS; missing: " .. table.concat(missingUse, ","))
  local extra, badFmt, untranslated = {}, {}, {}
  local function specs(s) local t = {} for sp in s:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([cdeEfgGiouxXqs])") do t[#t + 1] = sp end return table.concat(t) end
  for k, v in pairs(de) do
    if not k:find("^SPEC:") then
      if en[k] == nil then extra[#extra + 1] = k elseif specs(en[k]) ~= specs(v) then badFmt[#badFmt + 1] = k end
    end
  end
  for k in pairs(en) do if de[k] == nil then untranslated[#untranslated + 1] = k end end
  table.sort(extra); table.sort(badFmt); table.sort(untranslated)
  check(#extra == 0, "every German key exists in English: " .. table.concat(extra, ","))
  check(#badFmt == 0, "format specifiers match enUS for every German text: " .. table.concat(badFmt, ","))
  check(#untranslated == 0, "every English key has a German text (else it falls back to English): " .. table.concat(untranslated, ","))
  -- review H-1: every locale value used as a format string must survive string.format with matching dummy
  -- arguments, in both languages. Used = `format(L.KEY` / `format(L["KEY"]` in the code, plus the keys reached
  -- through a variable (INDIRECT). A format call whose first argument is neither a literal nor L.KEY must be one
  -- of the known indirect sites (FMT_SITES), so a new one can't slip past this check.
  local INDIRECT = { "HEAD_ENCHANTS", "HEAD_CRAFTS" } -- K17: TIP_CURRENT / TIP_EQUIPPED went with the tooltip lines
  local FMT_SITES = { ["d.kind"] = true, ["what,"] = true }
  local fmtKeys, oddSites = {}, {}
  for _, k in ipairs(INDIRECT) do fmtKeys[k] = true end
  for _, f in ipairs({ "Core.lua", "UI.lua", "Sync.lua", "Spec.lua", "Minimap.lua", "Scoring.lua" }) do
    local src = assert(io.open(ROOT .. f, "rb")):read("*a")
    for k in src:gmatch("format%(%s*L%.([%u_][%u%d_]*)") do fmtKeys[k] = true end
    for k in src:gmatch('format%(%s*L%["([^"]+)"%]') do fmtKeys[k] = true end
    for first in src:gmatch("[^%w_]format%(%s*([^%s\"'%)][^%s%)]*)") do
      if not first:find("^L[%.%[]") and not FMT_SITES[first] then oddSites[#oddSites + 1] = f .. ": format(" .. first end
    end
  end
  check(#oddSites == 0, "every non-literal format string is L.KEY or a known indirect site: " .. table.concat(oddSites, "; "))
  local function dummies(v)
    local args = {}
    for spec in v:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*(%a)") do
      if spec == "s" or spec == "q" then args[#args + 1] = "x"
      elseif spec == "f" or spec == "g" or spec == "e" or spec == "G" or spec == "E" then args[#args + 1] = 1.5
      else args[#args + 1] = 7 end
    end
    return args
  end
  local nFmt, badRun = 0, {}
  for k in pairs(fmtKeys) do
    for _, loc in ipairs({ "enUS", "deDE" }) do
      local v = ns.Locales[loc][k]
      if v == nil and loc == "enUS" then badRun[#badRun + 1] = loc .. "." .. k .. " missing" end
      if v ~= nil then
        nFmt = nFmt + 1
        local ok, err = pcall(string.format, v, (table.unpack or unpack)(dummies(v)))
        if not ok then badRun[#badRun + 1] = loc .. "." .. k .. ": " .. tostring(err) end
      end
    end
  end
  table.sort(badRun)
  check(nFmt > 100 and #badRun == 0, "string.format works on all " .. nFmt .. " format texts (enUS + deDE): " .. table.concat(badRun, "; "))
  local specMissing = {}
  for _, e in ipairs(GCA.SPEC_LIST) do if not de["SPEC:" .. e[3]] then specMissing[#specMissing + 1] = e[3] end end
  check(#specMissing == 0, "all 31 spec names have a German text: " .. table.concat(specMissing, ","))

  -- restore
  known[sLegs], known[sHands] = nil, nil
  itemDB[iLegs], itemDB[iHands] = saved[iLegs], saved[iHands]
  GCA.infoCache[iLegs], GCA.infoCache[iHands] = nil, nil
  GCA.candidates = nil
  GCA:RefreshKnown()
end

---------------------------------------------------------------------------
-- Section I: suggestions grouped per gear slot
---------------------------------------------------------------------------
section("I: slot sections (grouping, top 3, order, grey lines, rings/trinkets, enchants, browse, badge meaning)")
do
  local savedKnown, savedStore = {}, GCA.db.known[GCA.charKey]
  for k, v in pairs(known) do savedKnown[k] = v; known[k] = nil end
  GCA.db.known[GCA.charKey] = {}
  local savedSettings = { lookahead = GCA.db.settings.lookahead, showUnlearned = GCA.db.settings.showUnlearned }
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = false, false
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local saved, nextSpell = {}, 20
  local function craft(name, loc, minLevel, raw, sub, learn)
    nextSpell = nextSpell + 1
    local sp = spells[nextSpell]
    local id = ns.Recipes.Leatherworking[sp].item
    if saved[id] == nil then saved[id] = itemDB[id] or false end
    addItem(id, name, loc, minLevel, raw, sub)
    if learn ~= false then known[sp] = true end
    return sp, id
  end
  local function agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
  -- five known gloves (wearable), legs, a ring, a trinket; worn: gloves, legs, robe, two rings, one trinket
  for _, a in ipairs({ 9, 10, 11, 12, 13 }) do craft("Gloves " .. a, "INVTYPE_HAND", 30, agi(a)) end
  local _, iLegs = craft("Big Legs", "INVTYPE_LEGS", 30, agi(40))
  local _, iRing = craft("Craft Ring", "INVTYPE_FINGER", 30, agi(5), 0)
  local _, iTrink = craft("Craft Trinket", "INVTYPE_TRINKET", 30, agi(3), 0)
  addItem(991001, "Worn Gloves", "INVTYPE_HAND", 30, agi(8))
  addItem(991002, "Worn Legs", "INVTYPE_LEGS", 30, agi(10))
  addItem(991003, "Robe", "INVTYPE_CHEST", 30, agi(10))
  addItem(991004, "Ring A", "INVTYPE_FINGER", 30, agi(6), 0)
  addItem(991005, "Ring B", "INVTYPE_FINGER", 30, agi(3), 0)
  addItem(991006, "Trinket One", "INVTYPE_TRINKET", 30, agi(4), 0)
  GCA.infoCache = {}
  GCA.candidates = nil
  GCA:RefreshKnown()
  local items = { [10] = link(991001), [7] = link(991002), [5] = link(991003), [11] = link(991004), [12] = link(991005), [13] = link(991006) }
  local view = { key = "Sec Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }
  local function run(prof)
    GCA.sugCache = {}
    return GCA:ComputeSuggestions(view, false, prof)
  end
  local function sec(l, key) for _, s in ipairs(l.sections or {}) do if s.key == key then return s end end end
  local function names(rows) local t = {} for i, s in ipairs(rows) do t[i] = s.info.name end return table.concat(t, ",") end

  local l = run()
  check(l.sections and #l.sections == 15, "15 sections (rings and trinkets one each): " .. tostring(l.sections and #l.sections))
  -- grouping: every listed row sits in the section of its slot, and nowhere else
  local inSec, total, bad = {}, 0, 0
  for _, s in ipairs(l.sections) do
    for _, r in ipairs(s.rows) do
      total = total + 1
      if GCA.SECTION_OF[r.slot] ~= s.key or inSec[r] then bad = bad + 1 end
      inSec[r] = true
    end
  end
  for _, r in ipairs(l) do if not inSec[r] then bad = bad + 1 end end
  check(bad == 0 and total == #l, "grouping: every row in its slot's section exactly once (" .. total .. " rows, " .. bad .. " misplaced)")
  -- top 3
  local hands = sec(l, 10)
  check(hands and #hands.rows == 3 and hands.total == 5 and names(hands.rows) == "Gloves 13,Gloves 12,Gloves 11",
    "top 3 of 5 gloves, best first: " .. (hands and names(hands.rows) or "-") .. " (total " .. tostring(hands and hands.total) .. ")")
  check(hands and not hands.rows[1].extra and hands.rows[2].extra and hands.rows[3].extra, "only the slot's best is a primary row; #2/#3 are extra")
  -- badge / minimap meaning: one per slot (hands, legs, ring, trinket) although 6 rows are listed
  local n, best = GCA.KnownOnly(l)
  check(#l == 6 and n == 4 and best == l[1], "KnownOnly counts 4 (one per slot) of " .. #l .. " rows; best = first row")
  -- section order: biggest upgrade first (by the first row, SuggestionOrder), then no-upgrade slots in character order
  local keys, orderOK, seenNone = {}, true, false
  for i, s in ipairs(l.sections) do
    keys[i] = s.key
    if #s.rows == 0 then seenNone = true elseif seenNone then orderOK = false end
    local nx = l.sections[i + 1]
    if nx and #s.rows > 0 and #nx.rows > 0 and GCA.SuggestionOrder(nx.rows[1], s.rows[1]) then orderOK = false end
  end
  check(orderOK and keys[1] == 7, "sections with an upgrade first, by their best row's points (legs first; the empty-trinket fill by its points too): "
    .. table.concat(keys, ","))
  check(table.concat(keys, ",", 5) == "1,2,3,15,5,9,6,8,16,17,18", "no-upgrade sections after, in character order: " .. table.concat(keys, ",", 5))
  -- grey line: robe slot
  local chest = sec(l, 5)
  check(chest and #chest.rows == 0 and chest.worn[1].info and chest.worn[1].info.name == "Robe" and type(chest.worn[1].score) == "number"
    and chest.worn[1].score > 0, "no-upgrade chest: no rows, worn Robe with its score")
  local head = sec(l, 1)
  check(head and #head.rows == 0 and head.worn[1].link == nil and head.worn[1].info == nil, "empty head slot: grey line with nothing worn")
  -- rings: one section, both worn items, the craft replaces the weaker ring (12)
  local rings = sec(l, 11)
  check(rings and #rings.worn == 2 and rings.worn[1].slot == 11 and rings.worn[2].slot == 12 and rings.worn[1].info.name == "Ring A"
    and rings.worn[2].info.name == "Ring B" and #rings.rows == 1 and rings.rows[1].slot == 12 and rings.rows[1].cand.itemID == iRing,
    "rings: one section with Ring A + Ring B; the ring craft (replaces slot 12) is listed there")
  check(sec(l, 12) == nil and sec(l, 14) == nil, "no separate sections for slots 12 and 14")
  local tr = sec(l, 13)
  check(tr and #tr.worn == 2 and tr.worn[1].info.name == "Trinket One" and tr.worn[2].link == nil and #tr.rows == 1
    and tr.rows[1].status == "empty-slot" and tr.rows[1].cand.itemID == iTrink, "trinkets: one section, worn + empty slot, the craft fills the empty one")
  check(sec(l, 7).rows[1].cand.itemID == iLegs, "legs section: the legs craft")

  -- show unlearned: a worse unlearned glove is not listed (a known one beats it); better unlearned ones are, and the
  -- known best is never cut (it counts for the badge)
  local _, iWorse = craft("Gloves 9.5 unlearned", "INVTYPE_HAND", 30, agi(9), nil, false)
  craft("Gloves 50 unlearned", "INVTYPE_HAND", 30, agi(50), nil, false) -- stronger than any real LW glove in the data
  GCA.infoCache = {}; GCA.candidates = nil
  GCA.db.settings.showUnlearned = true
  l = run()
  hands = sec(l, 10)
  local hasWorse, has13 = false, false
  for _, r in ipairs(hands.rows) do
    if r.cand.itemID == iWorse then hasWorse = true end
    if r.info.name == "Gloves 13" then has13 = true end
  end
  check(not hasWorse and has13 and #hands.rows == 3 and hands.rows[1].info.name == "Gloves 50 unlearned",
    "show unlearned: better unlearned first, worse unlearned dropped (real unlearned LW gloves may fill in): " .. names(hands.rows))
  craft("Gloves 49 unlearned", "INVTYPE_HAND", 30, agi(49), nil, false)
  craft("Gloves 48 unlearned", "INVTYPE_HAND", 30, agi(48), nil, false)
  GCA.infoCache = {}; GCA.candidates = nil
  l = run()
  hands = sec(l, 10)
  check(names(hands.rows) == "Gloves 50 unlearned,Gloves 49 unlearned,Gloves 13" and not hands.rows[3].extra,
    "three better unlearned gloves: the known best takes the 3rd place (never cut): " .. names(hands.rows))
  check(select(1, GCA.KnownOnly(l)) == 4, "badge count unchanged with show unlearned (4)")
  GCA.db.settings.showUnlearned = false

  -- look-ahead: the bigger Lv43 gloves (primary, M-2) stays visible next to the wearable ones, listed after them
  craft("Later Gloves 30", "INVTYPE_HAND", 43, agi(30))
  craft("Later Gloves 29", "INVTYPE_HAND", 44, agi(29)) -- a 2nd, extra look-ahead row: the cut must still take wearable first
  GCA.infoCache = {}; GCA.candidates = nil
  GCA:RefreshKnown()
  GCA.db.settings.lookahead = true
  l = run()
  hands = sec(l, 10)
  check(names(hands.rows) == "Gloves 13,Gloves 12,Later Gloves 30" and hands.rows[3].future and not hands.rows[3].extra,
    "look-ahead: cut in tier order (wearable first, Lv44 gloves out), the bigger Lv43 gloves kept in the top 3 (counts as before): " .. names(hands.rows))
  n, best = GCA.KnownOnly(l)
  check(n == 5 and best and not best.future, "badge: 5 (hands now + hands look-ahead, legs, ring, trinket), best wearable (" .. n .. ")")
  GCA.db.settings.lookahead = false

  -- SectionCut on synthetic rows: duplicates (same item twice, same enchant ID twice) appear once
  local function syn(o) o.tier = o.tier or 1; o.points = o.points or 10; o.slot = o.slot or 9; o.kind = o.kind or "item"; return o end
  local a1 = syn({ known = false, cand = { itemID = 5 }, points = 20 })
  local a2 = syn({ known = true, cand = { itemID = 5 }, points = 20 })
  local b1 = syn({ known = true, cand = { itemID = 6 }, points = 15 })
  local shown, tot = GCA:SectionCut({ a1, b1, a2 }, { [a2] = true })
  check(#shown == 2 and tot == 2 and shown[1] == a2 and shown[2] == b1, "same item from two recipes: listed once (the known/primary one)")
  local e1 = syn({ kind = "enchant", known = true, enchant = { enchant = 247 }, cand = {}, points = 9 })
  local e2 = syn({ kind = "enchant", known = true, enchant = { enchant = 247 }, cand = {}, points = 9 })
  shown = GCA:SectionCut({ e1, e2 }, {})
  check(#shown == 1, "two enchant rows with the same enchant ID: listed once")

  -- enchants go to their slot's section (wrist, cloak, chest); top 3 there; badge counts one per slot
  setProfs({ { "Lederverarbeitung", 300, 300, 165 }, { "Verzauberkunst", 300, 300, 333 } })
  for id in pairs(known) do known[id] = nil end
  GCA.db.known[GCA.charKey] = {}
  local d = GCA:EnchantData()
  local e40 = GCA:WeightSetFor("DRUID", "FERAL_CAT", 40)
  local nWrist = 0
  for _, key in ipairs({ "wrist", "back", "chest" }) do
    for _, r in ipairs(d.bySlot[key] or {}) do
      if r.kind == "stats" and Scoring.value(r.stats, e40.set) > 0 and not GCA.UnsimmedSchool(r.stats, e40.set) then
        known[r.spell] = true
        if key == "wrist" then nWrist = nWrist + 1 end
      end
    end
  end
  addItem(991007, "Bracers", "INVTYPE_WRIST", 30, agi(4))
  addItem(991008, "Cloak", "INVTYPE_CLOAK", 30, agi(4), 1)
  GCA.infoCache = {}; GCA.candidates = nil
  GCA:RefreshKnown()
  local eItems = { [9] = link(991007), [15] = link(991008), [5] = link(991003) }
  view = { key = "Ench Paw", class = "DRUID", level = 40, items = eItems, spec = "FERAL_CAT" }
  l = run("Enchanting")
  local wrist, back, ch = sec(l, 9), sec(l, 15), sec(l, 5)
  local allEnch, ids, dup = true, {}, false
  for _, s in ipairs(l) do
    if s.kind ~= "enchant" then allEnch = false end
    local k = s.slot .. ":" .. s.enchant.enchant
    if ids[k] then dup = true end
    ids[k] = true
  end
  check(wrist and #wrist.rows == 3 and wrist.total >= 3 and nWrist >= 3 and back and #back.rows >= 1 and allEnch and not dup,
    ("enchants: wrist section %d of %d, cloak section %d; all enchant rows, no enchant twice in a slot"):format(wrist and #wrist.rows or -1, wrist and wrist.total or -1, back and #back.rows or -1))
  local placed = true
  for _, s in ipairs(l.sections) do for _, r in ipairs(s.rows) do if r.slot ~= s.key then placed = false end end end
  check(placed and ch and #ch.rows >= 1 and ch.rows[1].kind == "enchant", "every enchant row is in its slot's section (chest too)")
  local withRows = 0
  for _, s in ipairs(l.sections) do if #s.rows > 0 then withRows = withRows + 1 end end
  check(select(1, GCA.KnownOnly(l)) == withRows and withRows == 3, "enchant badge: one per slot (" .. withRows .. " slots)")

  -- browse: everything unlearned, top 3 per section, nothing counts
  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  GCA:RefreshKnown()
  view = { key = "Sec Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }
  l = run("Leatherworking")
  local maxRows, anyKnown = 0, false
  for _, s in ipairs(l.sections) do maxRows = math.max(maxRows, #s.rows) end
  for _, s in ipairs(l) do if s.known then anyKnown = true end end
  hands = sec(l, 10)
  check(GCA:IsBrowse("Leatherworking") and #l > 0 and maxRows <= 3 and not anyKnown and select(1, GCA.KnownOnly(l)) == 0
    and hands and #hands.rows == 3, ("browse: %d rows, at most %d per section, none known, badge 0"):format(#l, maxRows))

  -- restore
  for id, v in pairs(saved) do itemDB[id] = v or nil end
  for i = 991001, 991008 do itemDB[i] = nil end
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.db.known[GCA.charKey] = savedStore
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedSettings.lookahead, savedSettings.showUnlearned
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
end

section("K0/L1: look-ahead offers mail/plate that becomes wearable at 40, marked as a future row")
do
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local sMail, sLeather = spells[1], spells[2]
  local iMail, iLeather = ns.Recipes.Leatherworking[sMail].item, ns.Recipes.Leatherworking[sLeather].item
  local saved = { [iMail] = itemDB[iMail] or false, [iLeather] = itemDB[iLeather] or false }
  local savedKnown = {}
  for k, v in pairs(known) do savedKnown[k] = v end
  addItem(iMail, "Mail Vest", "INVTYPE_CHEST", 35, { ITEM_MOD_AGILITY_SHORT = 30, RESISTANCE0_NAME = 200 }, 3)
  addItem(iLeather, "Leather Boots", "INVTYPE_FEET", 30, { ITEM_MOD_AGILITY_SHORT = 12 }, 2)
  addItem(992001, "Worn Vest", "INVTYPE_CHEST", 30, { ITEM_MOD_AGILITY_SHORT = 5, RESISTANCE0_NAME = 80 }, 2)
  addItem(992002, "Worn Boots", "INVTYPE_FEET", 30, { ITEM_MOD_AGILITY_SHORT = 4 }, 2)
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  known[sMail], known[sLeather] = true, true
  GCA:RefreshKnown()
  local savedLA, savedUn = GCA.db.settings.lookahead, GCA.db.settings.showUnlearned
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local items = { [5] = link(992001), [8] = link(992002) }
  local function run(level)
    GCA.sugCache = {}
    local l = GCA:ComputeSuggestions({ key = "Hunt Er", class = "HUNTER", level = level, items = items, spec = "MARKSMANSHIP" }, false)
    local mail, boots
    for _, sg in ipairs(l) do
      if sg.cand and sg.cand.itemID == iMail then mail = sg elseif sg.cand and sg.cand.itemID == iLeather then boots = sg end
    end
    return mail, boots
  end
  local mail, boots = run(37)
  check(mail and mail.future and mail.wearAt == 40 and mail.levelsToGo == 3 and boots and not boots.future,
    "Lv37 Hunter: mail vest (item Lv35) offered as future, wearable at 40 (in 3); leather boots wearable now")
  mail = run(34)
  check(mail == nil, "Lv34 Hunter: 40 is beyond the 5-level look-ahead -> no mail")
  mail = run(41)
  check(mail and not mail.future and mail.wearAt == nil, "Lv41 Hunter: mail is a normal row")
  GCA.db.settings.lookahead = false
  mail, boots = run(37)
  check(mail == nil and boots ~= nil, "look-ahead off: no mail before 40")
  -- restore
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedLA, savedUn
  for id, v in pairs(saved) do itemDB[id] = v or nil end
  itemDB[992001], itemDB[992002] = nil, nil
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:RefreshKnown()
end

---------------------------------------------------------------------------
section("W: weapons - golden compare/speed vs SimGear, proficiency, dual wield, speed parse, crafts end to end")
---------------------------------------------------------------------------
-- W7 golden: SimGear's own Score.compare (compareWeapon + speedValue) on its own weapon items (stats, speeds from
-- the extras, daggers) against our Scoring.compare, with random worn hands, dual wield on/off, set bonuses.
do
  local WEAPON_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_2HWEAPON = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
  local cmp, bad, statuses, offHand, withSpeed = 0, 0, {}, 0, 0
  local speedCmp, speedBad = 0, 0
  for _, class in ipairs(CLASSES) do
    local ens = {}
    assert(loadfile(SG .. "SimGearForever_" .. cap(class) .. "/data/items/" .. class .. "_extras.lua", "t", sgEnv()))("x", ens)
    local X = ens.Extras[class]
    local pool, byLoc = {}, {}
    local ids = {}
    for id in pairs(SGItems[class]) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local it = SGItems[class][id]
      if WEAPON_LOCS[it.slot] and type(it.stats) == "table" then
        local stats = {}
        for k, v in pairs(it.stats) do stats[k] = v end
        local w = { itemID = id, equipLoc = it.slot, stats = stats, speed = it.speed or (X.speeds and X.speeds[id]),
          dagger = (X.daggers and X.daggers[id]) and true or nil }
        pool[#pool + 1] = w
        byLoc[it.slot] = byLoc[it.slot] or {}
        table.insert(byLoc[it.slot], w)
      end
    end
    local function pick(list) return list and #list > 0 and list[rnd(#list)] or nil end
    for spec in pairs(W.classes[class]) do
      for _, level in ipairs({ 25, 30, 40, 50, 60 }) do
        local share = SHARES[rnd(3)]
        GCA.db.settings.survival = share
        local e = GCA:WeightSetFor(class, spec, level)
        local sg = sgCompose(class, spec, level, share)
        for _ = 1, 20 do
          local equipped = {}
          local r = rnd(4)
          if r == 1 then equipped[16] = pick(byLoc.INVTYPE_2HWEAPON)
          elseif r == 2 then equipped[16] = pick(byLoc.INVTYPE_WEAPON); equipped[17] = pick(byLoc.INVTYPE_WEAPON) or pick(byLoc.INVTYPE_WEAPONOFFHAND)
          elseif r == 3 then equipped[16] = pick(byLoc.INVTYPE_WEAPONMAINHAND) or pick(byLoc.INVTYPE_WEAPON); equipped[17] = pick(byLoc.INVTYPE_SHIELD) or pick(byLoc.INVTYPE_HOLDABLE)
          end
          if rnd(2) == 1 then equipped[18] = pick(byLoc.INVTYPE_RANGED) or pick(byLoc.INVTYPE_RANGEDRIGHT) end
          local cand = pick(pool)
          if cand then
            local dw = rnd(2) == 1
            local a = SGns.Score.compare(cand, equipped, sg, { dualWield = dw, sets = SGSets[class] })
            local b = Scoring.compare(cand, equipped, e.set, OURSETS, nil, { dualWield = dw })
            cmp = cmp + 1
            local ok = (a == nil) == (b == nil)
            if a and b then
              ok = ok and a.status == b.status and near(a.newValue, b.newValue) and near(a.oldValue, b.oldValue)
                and ((a.pct == nil and b.pct == nil) or near(a.pct, b.pct)) and a.hand == b.hand
                and table.concat(a.replaces or {}, ",") == table.concat(b.replaces or {}, ",") and near(a.setDelta or 0, b.setDelta or 0)
              statuses[a.status] = (statuses[a.status] or 0) + 1
              if a.hand == "off" then offHand = offHand + 1 end
            end
            if cand.speed then withSpeed = withSpeed + 1 end
            if not ok then
              bad = bad + 1
              if bad <= 5 then print(("    differs: %s %s Lv%d item %d dw %s: %s %s vs %s %s"):format(class, spec, level, cand.itemID, tostring(dw),
                a and a.status, a and a.newValue, b and b.status, b and b.newValue)) end
            end
            -- speedFactor / speedValue on the same item for every weapon-DPS key
            for _, key in ipairs({ "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }) do
              speedCmp = speedCmp + 1
              if not near(SGns.Score.speedFactor(cand, key, sg), Scoring.speedFactor(cand, key, e.set)) then speedBad = speedBad + 1 end
            end
            speedCmp = speedCmp + 1
            if not near((SGns.Score.speedValue(cand, sg)), (Scoring.speedValue(cand, e.set))) then speedBad = speedBad + 1 end
          end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  local st = {}
  for k, v in pairs(statuses) do st[#st + 1] = k .. " " .. v end
  table.sort(st)
  check(bad == 0 and cmp > 500 and (statuses["needs-partner"] or 0) > 0 and offHand > 0,
    ("W golden: %d weapon comparisons identical to SimGear's compareWeapon (%d differ); %s; %d in the off hand; %d with a speed"):format(
      cmp, bad, table.concat(st, ", "), offHand, withSpeed))
  check(speedBad == 0, ("W golden: speedFactor/speedValue identical to SimGear on %d cases (%d differ)"):format(speedCmp, speedBad))
  -- speed changes a score at all (not a silent factor 1): a slow 2H for a Lv60 Ret Paladin (mainHand curve)
  local e = GCA:WeightSetFor("PALADIN", "RETRIBUTION", 60)
  local slow = { equipLoc = "INVTYPE_2HWEAPON", stats = { TwoHandDps = 50 }, speed = 3.8 }
  local none = { equipLoc = "INVTYPE_2HWEAPON", stats = { TwoHandDps = 50 } }
  check(Scoring.itemValue(slow, e.set) > Scoring.itemValue(none, e.set) and Scoring.speedFactor({ equipLoc = "INVTYPE_WEAPON", dagger = true, speed = 1.0 }, "MainHandDps", e.set)
    == 1 + e.set.speedCurves.mainHand.perSecond * (1.3 - 1.7), "speed: a slow two-hander scores higher for Ret 60; daggers clamp to 1.3..1.9 around 1.7")
end

-- W2 proficiency matrix: class x level 19/20/39/40 x weapon subclass 0..20 against SimGear's Classes.barredType + the
-- polearm gate (Hunter/Warrior from 20); unknown classes never bar
do
  local SGC = SGns.Classes
  local bad, n = 0, 0
  for _, class in ipairs(CLASSES) do
    for sub = 0, 20 do
      for _, level in ipairs({ 19, 20, 39, 40 }) do
        local item = { classID = 2, subclassID = sub, equipLoc = "INVTYPE_WEAPON" }
        local barred = SGC.barredType(class, item)
        local gate = sub == 6 and (class == "HUNTER" or class == "WARRIOR") and 20 or nil
        local expect = barred == nil and not (gate and level < gate)
        local got = GCA:CanWear(class, level, { classID = 2, subClassID = sub, equipLoc = "INVTYPE_WEAPON" })
        n = n + 1
        if got ~= expect then bad = bad + 1; if bad <= 5 then print(("    %s Lv%d weapon sub %d: got %s, expected %s"):format(class, level, sub, tostring(got), tostring(expect))) end end
      end
    end
  end
  check(bad == 0 and n == 9 * 21 * 4, ("W2: %d class/level/weapon-subclass cases = SimGear's equip.weapons + polearm gate (%d differ)"):format(n, bad))
  check(GCA:CanWear("MAGE", 1, { classID = 2, subClassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" }) and GCA:CanWear("PRIEST", 1, { classID = 2, subClassID = 19 })
    and GCA:CanWear("WARLOCK", 1, { classID = 2, subClassID = 19 }) and not GCA:CanWear("ROGUE", 60, { classID = 2, subClassID = 19 })
    and not GCA:CanWear("HUNTER", 60, { classID = 2, subClassID = 19 }), "wands: Mage/Priest/Warlock only")
  check(GCA:WearFrom("WARRIOR", { classID = 2, subClassID = 6 }) == 20 and GCA:WearFrom("PALADIN", { classID = 2, subClassID = 6 }) == 0
    and GCA:WearFrom("PALADIN", { classID = 2, subClassID = 15 }) == nil and GCA:WearFrom("ROGUE", { classID = 2, subClassID = 20 }) == 0,
    "WearFrom: polearms Warrior 20 / Paladin any level; Paladin never daggers; fishing pole for anyone")
  -- the generated classWeapons equal SimGear's Classes.lua (generator check)
  local same = true
  for _, class in ipairs(CLASSES) do
    local ours, sg = W.classWeapons[class], SGC[class]
    local a, b = {}, {}
    for i, v in ipairs(ours.weapons) do a[i] = v end
    for i, v in ipairs(sg.equip.weapons) do b[i] = v end
    table.sort(a); table.sort(b)
    if table.concat(a, ",") ~= table.concat(b, ",") or ours.dualWieldFrom ~= sg.dualWieldFrom or ours.noHoldable ~= (sg.equip.noHoldable == true) then same = false end
    for k in pairs(sg.dualWield or {}) do if not ours.dualWield[k] then same = false end end
    if (ours.noHoldable == true) ~= (GCA.NO_HOLDABLE[class] == true) then same = false end
  end
  check(same, "Data/Weights.lua classWeapons = SimGear Classes.lua (weapons, dualWield, dualWieldFrom, noHoldable; NO_HOLDABLE agrees)")
end

-- W4 / W8.1 dual-wield gates
do
  local saved674 = known[674]
  local function dw(class, spec, level, isSelf) return GCA:DualWieldFrom(class, spec, level, isSelf) end
  check(dw("ROGUE", "COMBAT", 9) == 10 and dw("ROGUE", "ASSASSINATION", 10) == 10, "guildie Rogue: dual wield from 10")
  check(dw("WARRIOR", "FURY", 19) == 20 and dw("WARRIOR", "ARMS", 40) == nil and dw("WARRIOR", "PROTECTION", 40) == nil,
    "guildie Warrior: Fury from 20; Arms / Prot never (not simmed with two weapons)")
  check(dw("HUNTER", "MARKSMANSHIP", 30) == 20 and dw("HUNTER", "SURVIVAL_MELEE", 30) == 20, "guildie Hunter: from 20")
  check(dw("SHAMAN", "ENHANCEMENT", 60) == nil and dw("SHAMAN", "ENHANCEMENT_DW", 30) == 0 and dw("SHAMAN", "ELEMENTAL", 60) == nil,
    "Shaman: only as ENHANCEMENT_DW (one-hander seen in the off hand), at any level")
  check(dw("MAGE", "FIRE", 60) == nil and dw("PALADIN", "RETRIBUTION", 60) == nil and dw("DRUID", "FERAL_CAT", 60) == nil, "no dual wield for Mage/Paladin/Druid")
  known[674] = nil
  check(dw("WARRIOR", "FURY", 30, true) == nil and dw("WARRIOR", "FURY", 18, true) == 20, "own Fury Warrior without spell 674: no (Lv30); Lv18 -> from 20 (look-ahead)")
  known[674] = true
  check(dw("WARRIOR", "FURY", 30, true) == 0 and dw("ROGUE", "COMBAT", 8, true) == 0 and dw("WARRIOR", "ARMS", 30, true) == nil,
    "own character: Dual Wield known wins (any level); Arms still not")
  known[674] = saved674
end

-- W3 speed parse (SimGear Stats.weaponSpeedFromLines): "Speed 2.60" and deDE "Tempo 2,60"
do
  local function L(t) return { { leftText = "x" }, { leftText = "45 - 85 Damage", rightText = t } } end
  check(Scoring.weaponSpeedFromLines(L("Speed 2.60"), "Speed") == 2.6 and Scoring.weaponSpeedFromLines(L("Tempo 2,60"), "Tempo") == 2.6
    and Scoring.weaponSpeedFromLines(L("Speed 2.60"), "Tempo") == 2.6 and Scoring.weaponSpeedFromLines(L("Speed 2.60"), nil) == 2.6,
    "speed parse: 'Speed 2.60', deDE 'Tempo 2,60', English fallback, no label")
  check(Scoring.weaponSpeedFromLines(L("Tempo 2,60"), nil) == nil and Scoring.weaponSpeedFromLines(L("Speed 12.00"), "Speed") == nil
    and Scoring.weaponSpeedFromLines({ { leftText = "Tempo 2,60" } }, "Tempo") == nil and Scoring.weaponSpeedFromLines(nil, "Speed") == nil
    and Scoring.weaponSpeedFromLines(L("  Tempo 3  "), "Tempo") == 3,
    "speed parse: unknown label, >= 10 s, left text, nil lines -> nil; '3' without decimals and padding ok")
  -- for each SimGear golden case SimGear's parser agrees
  local agree = true
  for _, t in ipairs({ "Speed 2.60", "Tempo 2,60", "Speed 1.8", "Tempo 3", "Speed 10.0", "Speed x" }) do
    for _, lab in ipairs({ "Speed", "Tempo" }) do
      if SGns.Stats.weaponSpeedFromLines(L(t), lab) ~= Scoring.weaponSpeedFromLines(L(t), lab) then agree = false end
    end
  end
  check(agree, "speed parse = SimGear's weaponSpeedFromLines on the same lines")
  -- WeaponSpeed through the client tooltip API (deDE), cached; GetInfo carries speed + dagger
  local savedTI, savedSPEED = env.C_TooltipInfo, env.SPEED
  local calls = 0
  env.SPEED = "Tempo"
  env.C_TooltipInfo = { GetItemByID = function(id) calls = calls + 1; if id == 993001 then return { lines = { { leftText = "Dolch" }, { leftText = "10 - 20 Schaden", rightText = "Tempo 1,80" } } } end end }
  GCA.speedCache = {}
  addItem(993001, "Fake Dagger", "INVTYPE_WEAPON", 30, { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }, 15); itemDB[993001].classID = 2
  GCA.infoCache[993001] = nil
  local info = GCA:GetInfo(993001)
  GCA.infoCache[link(993001)] = nil
  local info2 = GCA:GetInfo(link(993001))
  check(info.speed == 1.8 and info.dagger and info.cstats.MainHandDps == 20 and info2.speed == 1.8 and calls == 1,
    "GetInfo of a weapon: speed 1.80 read from the deDE tooltip (cached: 1 tooltip call), dagger, DPS as MainHandDps")
  env.C_TooltipInfo, env.SPEED = savedTI, savedSPEED
end

-- W1/W4/W8: fake Blacksmithing / Engineering / Enchanting weapon crafts reach the rows and sections
do
  setProfs({ { "Schmiedekunst", 300, 300, 164 } })
  GCA:RefreshKnown()
  local savedBS = ns.Recipes.Blacksmithing
  local savedKnown = {}
  for k, v in pairs(known) do savedKnown[k] = v end
  local savedLA, savedUn = GCA.db.settings.lookahead, GCA.db.settings.showUnlearned
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local function W(id, name, loc, lvl, raw, sub) addItem(id, name, loc, lvl, raw, sub); itemDB[id].classID = 2 end
  W(994001, "Craft Sword", "INVTYPE_WEAPON", 30, { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }, 7)
  W(994002, "Craft Greatsword", "INVTYPE_2HWEAPON", 30, { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 45 }, 8)
  W(994003, "Craft Polearm", "INVTYPE_2HWEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 25, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }, 6)
  W(994004, "Craft Dagger", "INVTYPE_WEAPON", 30, { ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 28 }, 15)
  W(994005, "Craft Left Blade", "INVTYPE_WEAPONOFFHAND", 30, { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 }, 7)
  W(994006, "Craft Gun", "INVTYPE_RANGEDRIGHT", 30, { ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }, 3)
  W(994007, "Craft Wand", "INVTYPE_RANGEDRIGHT", 30, { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 }, 19)
  addItem(994008, "Craft Shield", "INVTYPE_SHIELD", 30, { ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 900 }, 6)
  -- worn
  W(994101, "Old 2H", "INVTYPE_2HWEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }, 8)
  W(994102, "Old Sword", "INVTYPE_WEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 }, 7)
  W(994103, "Old Offhand Sword", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, 7)
  W(994104, "Old Dagger", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 }, 15)
  W(994105, "Old Wand", "INVTYPE_RANGEDRIGHT", 20, { ITEM_MOD_INTELLECT_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 }, 19)
  local recipes = {}
  for i, id in ipairs({ 994001, 994002, 994003, 994004, 994005, 994006, 994007, 994008 }) do
    recipes[995000 + i] = { item = id, skill = 1, src = "trainer", name = itemDB[id].name, r = {} }
    known[995000 + i] = true
  end
  ns.Recipes.Blacksmithing = recipes
  GCA.itemToSpellOf = {}
  GCA:SelectProfession("Blacksmithing")
  GCA:RefreshKnown()
  GCA.infoCache = {}; GCA.candidates = nil
  local function run(class, spec, level, items, isSelf)
    GCA.sugCache = {}
    local list = GCA:ComputeSuggestions({ key = "Weap Test", class = class, level = level, items = items, spec = spec }, isSelf)
    local by = {}
    for _, s in ipairs(list) do by[s.cand.itemID] = s end
    return by, list
  end
  local nCand = 0
  for _, c in ipairs(GCA:GetCandidates("Blacksmithing")) do if recipes[c.spellID] then nCand = nCand + 1 end end
  check(nCand == 8, "W1: all 8 weapon/shield crafts are candidates (sword, 2H, polearm, dagger, off-hand blade, gun, wand, shield): " .. nCand)
  -- Arms Warrior Lv40 with a two-hander: a greatsword is a % upgrade replacing both hands; a sword "needs an off hand"
  local by, list = run("WARRIOR", "ARMS", 40, { [16] = link(994101) })
  local gs, sw = by[994002], by[994001]
  check(gs and gs.tier == 1 and gs.slot == 16 and gs.status == "upgrade" and gs.pct and gs.pct > 0, "Arms Lv40 with a 2H: Craft Greatsword is an upgrade (main hand)")
  check(sw and sw.status == "needs-partner" and sw.tier == GCA.TIER_PARTNER and sw.slot == 16 and sw.pct == nil
    and math.abs(sw.points - GCA:ToPoints(gs.e, sw.newScore)) < 1e-9 and sw.equipped and sw.equipped.name == "Old 2H",
    "W8.2: a one-hander next to a worn 2H: own tier, scored alone (points = its own score), replaces the 2H")
  check(by[994008] and by[994008].status == "needs-partner" and by[994008].slot == 17, "a shield next to a worn 2H: needs a main hand, off-hand section")
  check(by[994005] == nil, "Arms: no off-hand weapon (no dual wield)")
  check(GCA:CanWear("WARRIOR", 40, { classID = 2, subClassID = 15 }) and by[994006] and by[994006].slot == 18
    and (GCA:WeightSetFor("WARRIOR", "ARMS", 40).set.weights.RangedDps or 0) == 0,
    "Warrior: daggers allowed; the gun is offered on its stats only (no RangedDps weight)")
  local order = {}
  for i, s in ipairs(list) do order[s] = i end
  check(order[gs] < order[sw], "the % upgrade sorts before the needs-partner row")
  -- sections: 16 main hand, 17 off hand, 18 ranged
  local secKeys = {}
  for _, sec in ipairs(list.sections) do if #sec.rows > 0 then secKeys[sec.key] = #sec.rows end end
  check(secKeys[16] and secKeys[17] and secKeys[18], "rows reach the main hand, off hand and ranged sections")
  -- polearm: Lv19 Warrior -> future (wearable at 20); Lv20 -> normal
  by = run("WARRIOR", "ARMS", 19, { [16] = link(994101) })
  check(by[994003] and by[994003].future and by[994003].wearAt == 20, "W2: polearm for a Lv19 Warrior: look-ahead row, wearable at 20")
  by = run("WARRIOR", "ARMS", 20, { [16] = link(994101) })
  check(by[994003] and not by[994003].future, "polearm at 20: a normal row")
  -- Prot Warrior: no two-handers (SimGear gearRules)
  by = run("WARRIOR", "PROTECTION", 40, { [16] = link(994102), [17] = link(994008) })
  check(by[994002] == nil and by[994003] == nil and by[994001] ~= nil, "Prot Warrior: no two-handers; a one-hander is compared")
  -- Fury Lv40 with sword + sword: a two-hander replaces both hands (pair compared, tag), dual wield: a better
  -- one-hander may go in the off hand
  by = run("WARRIOR", "FURY", 40, { [16] = link(994102), [17] = link(994103) })
  local g2 = by[994002]
  check(g2 and g2.bothHands and g2.equipped and g2.equipped.name == "Old Sword + Old Offhand Sword" and g2.equipped.pair,
    "Fury with two swords: a two-hander says 'replaces both hands', compared against both: " .. tostring(g2 and g2.equipped and g2.equipped.name))
  check(by[994005] and by[994005].slot == 17, "Fury Lv40 (dual wield): the off-hand blade is offered for the off hand")
  -- Rogue Combat Lv30 dual wield, strong main hand + weak off hand: the Craft Dagger goes in the off hand
  W(994106, "Strong Dagger", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 25, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 45 }, 15)
  by = run("ROGUE", "COMBAT", 30, { [16] = link(994106), [17] = link(994104) })
  check(by[994004] and by[994004].hand == "off" and by[994004].slot == 17 and by[994004].equipped.name == "Old Dagger",
    "W4: dual wield: a one-hander better in the off hand is offered for the off hand (hand 'off', section 17, replaces the off-hand dagger)")
  itemDB[994005].minLevel = 1; GCA.infoCache = {}
  by = run("ROGUE", "COMBAT", 8, {})
  check(by[994005] and by[994005].future and by[994005].wearAt == 10, "Rogue Lv8: the off-hand blade is a look-ahead row, wearable at 10 (Dual Wield)")
  GCA.db.settings.lookahead = false
  by = run("ROGUE", "COMBAT", 8, {})
  check(by[994005] == nil, "...and not offered without look-ahead")
  GCA.db.settings.lookahead = true
  itemDB[994005].minLevel = 30; GCA.infoCache = {}
  by = run("ROGUE", "COMBAT", 30, { [16] = link(994102), [17] = link(994104) })
  local dg = by[994004]
  local e = GCA:WeightSetFor("ROGUE", "COMBAT", 30)
  local direct = Scoring.compare(GCA:ScoreItem(GCA:GetInfo(994004)), { [16] = GCA:ScoreItem(GCA:GetInfo(link(994102))), [17] = GCA:ScoreItem(GCA:GetInfo(link(994104))) },
    e.set, nil, nil, { dualWield = true })
  check(dg and dg.hand == direct.hand and dg.slot == (direct.hand == "off" and 17 or 16), "Rogue dual wield: the dagger's hand = the compare's better hand (" .. tostring(direct.hand) .. ")")
  check(by[994002] == nil and by[994003] == nil and by[994007] == nil, "Rogue: no two-handed swords, polearms or wands")
  -- Mage: wand in the ranged section, no swords-only? (Mage has one-handed swords) no daggers? (has daggers); no 2H swords
  by = run("MAGE", "FIRE", 40, { [18] = link(994105) })
  check(by[994007] and by[994007].slot == 18 and by[994006] == nil and by[994002] == nil, "Mage: the wand (ranged section), no gun, no 2H sword")
  -- Hunter: the gun with RangedDps counts; no shield
  by = run("HUNTER", "MARKSMANSHIP", 40, {})
  check(by[994006] and by[994006].slot == 18 and by[994006].status == "empty-slot" and by[994008] == nil, "Hunter: the gun fills an empty ranged slot; no shield")
  -- an unknown (not loaded) off hand: nothing compared against the pair
  GCA.loadState[994999] = { first = 0, tries = 99, failed = true }
  by = run("WARRIOR", "FURY", 40, { [16] = link(994102), [17] = link(994999) })
  check(by[994001] == nil and by[994002] == nil and by[994008] == nil and by[994006] ~= nil, "unknown off hand: no hand crafts, ranged still")
  GCA.loadState[994999] = nil
  -- restore
  ns.Recipes.Blacksmithing = savedBS
  GCA.itemToSpellOf = {}
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedLA, savedUn
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:SelectProfession("Leatherworking")
  GCA:RefreshKnown()
end

print(("\n%d passed, %d failed"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
