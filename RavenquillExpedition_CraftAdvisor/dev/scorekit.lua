local P = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "paths.lua")
local Kit = dofile(P.ADDONS .. "RavenquillExpedition/dev/testkit.lua")
local ROOT = P.ROOT
local SG = P.SimGear(arg[1])
if not SG then
  Kit.skip("score:simgear-source", "SimGear Forever not found (pass its folder, set RQ_SIMGEAR or unzip it into <repo>/.cache/simgear/)")
  Kit.finish()
end

local H = {}
local check, section = Kit.check, Kit.section
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 1e-9) * math.max(1, math.abs(a or 0), math.abs(b or 0)) end

local seed = 12345
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return (seed % n) + 1 end

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local function cap(s) return s:sub(1, 1) .. s:sub(2):lower() end

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

local sched = Kit.Scheduler({ start = 1000 })
local function advance(sec) sched:advance(sec) end
local itemDB = {}
local known = {}
local talent = { config = nil, nodes = {}, inspect = nil }
local requests = {}
local player = { first = "Me", surname = "Stone", class = "DRUID", level = 40, items = {} }
local Files = dofile(ROOT .. "dev/files.lua")
local CA = "RavenquillExpedition_CraftAdvisor"
local files = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua", "Sync",
  "RecipeSources.lua", "UI" } }))
local function idOf(item) return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)")) end
local client = Kit.Client(sched, nil, "Me Stone", { class = "DRUID", level = 40, epoch = 1800000000, files = files,
  setup = function(env)
    env.Constants.TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 }
    env.C_GuildInfo = nil
    env.UnitName = function(u) if u == "player" then return player.first, player.surname end end
    env.UnitNameUnmodified = env.UnitName
    env.UnitClass = function(u) if u == "player" then return player.class, player.class end end
    env.UnitLevel = function(u) if u == "player" then return player.level end end
    env.UnitGUID = function(u) if u == "player" then return "G-me" end end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitIsPlayer = function(u) return u == "player" end
    env.GetInventoryItemLink = function(u, slot) if u == "player" then return player.items[slot] end end
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
        local i = nodeID % 1000
        local list = config == talent.config and talent.nodes or (talent.inspect and talent.inspect.nodes) or {}
        local n = list[i]
        if not n then return nil end
        return { posX = n[1], ranksPurchased = n[2], activeRank = n[3] or n[2] }
      end,
    }
    env.RavenquillExpeditionCraftDB = {}
  end })
local env, ns, RQ = client.env, client.ns[CA], client.RQ
H.printed = client.printed
local GCA, Scoring, W = ns.GCA, ns.Scoring, ns.Weights
H.refreshes = 0
GCA.UI = { Refresh = function() H.refreshes = H.refreshes + 1; if GCA.UI.onRefresh then GCA.UI.onRefresh() end end }
local fire = function(_, ev, ...) client.fire(ev, ...) end
local function reloadDB() client.coreNs.SetupModuleDB(GCA); GCA:OnLoad() end
fire(GCA, "ADDON_LOADED", "RavenquillExpedition")
fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
fire(GCA, "PLAYER_LOGIN")

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

local CRAFT = {}
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
local LEVELS = { 1, 9, 10, 12, 14, 19, 20, 25, 26, 30, 35, 40, 45, 49, 50, 51, 54, 55, 57, 58, 59, 60 }
local SHARES = { 0, 0.5, 1 }
local function sgCompose(class, spec, level, share)
  local sets = SGW[class][spec]
  local raw = SGns.Score.pickSet(sets, level)
  local ref = SGns.Plan.leveling(sets, level)
  return SGns.Plan.apply(raw, ref, share, SGns.Plan.handover(level, false)), raw, ref
end
local OURSETS = Scoring.buildSets(W.itemSets)

local function link(id) return "item:" .. id .. "::::::::40:1488" end
local function addItem(id, name, loc, minLevel, raw, sub)
  itemDB[id] = { name = name, equipLoc = loc, minLevel = minLevel or 1, classID = 4, subClassID = sub or 2, raw = raw }
end
local function recipeFor(itemID) return recipeOf[itemID] end
local profState = { list = { 1 }, lines = { [1] = { "Lederverarbeitung", 225, 300, 165 } } }
local function setProfs(spec)
  profState.list, profState.lines = {}, {}
  for i, p in ipairs(spec) do profState.list[i] = i; profState.lines[i] = p end
end

function H.professionMocks()
  env.GetProfessions = function() return table.unpack(profState.list) end
  env.GetProfessionInfo = function(i) local p = profState.lines[i]; if p then return p[1], nil, p[2], p[3], nil, nil, p[4] end end
end

H.finish = Kit.finish
H.client = client
H.sched = sched

H.CLASSES = CLASSES
H.CRAFT = CRAFT
H.Files = Files
H.GCA = GCA
H.LEVELS = LEVELS
H.OURSETS = OURSETS
H.ROOT = ROOT
H.RQ = RQ
H.SG = SG
H.SGItems = SGItems
H.SGSets = SGSets
H.SGW = SGW
H.SGns = SGns
H.SHARES = SHARES
H.Scoring = Scoring
H.W = W
H.addItem = addItem
H.advance = advance
H.cap = cap
H.check = check
H.env = env
H.fire = fire
H.itemDB = itemDB
H.known = known
H.link = link
H.near = near
H.ns = ns
H.recipeFor = recipeFor
H.reloadDB = reloadDB
H.requests = requests
H.rnd = rnd
H.section = section
H.setProfs = setProfs
H.sgCompose = sgCompose
H.sgEnv = sgEnv
H.talent = talent
return H
