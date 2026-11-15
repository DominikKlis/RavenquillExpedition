-- Generates Data/Sources.lua: where to learn every recipe of Data/<Profession>.lua and Data/Enchants.lua (trainer,
-- vendor with price, quest, drop, world drop, chests), so UI.lua needs no other addon at runtime.
-- Run from the repository root (Lua 5.4):
--   lua RavenquillExpedition_CraftAdvisor/dev/gen_sources.lua [CraftersJournal Data dir] [QuestieDB dir] [out dir]
--
-- It reproduces what CraftersJournal's Waypoints.lua answered in game (the calls the old UI.lua made):
--   * recipes: CraftersJournal Data/<Profession>.lua (fee / trainer / basic / scroll / scrollPrice / favor / rep) and
--     its trainer lists (Data/<Profession>.lua `trainers`, { NPC, rank mask });
--   * pattern sources, NPCs, quests, creature levels: CraftersJournal Data/Sources.lua (ItemSources, NPCs, Quests,
--     NPCLevels), which CraftersJournal generated from QuestieDB;
--   * what Data/Sources.lua lacks: in game CraftersJournal then asked the installed QuestieDB (WP.NPC and Item() in
--     Waypoints.lua: an NPC's name, spawns, zone and friendlyToFaction; a pattern's vendors and quest rewards).
--     This generator reads the same values from QuestieDB_Forever.toc (base64 CBOR rows, static corrections
--     already folded in) and places NPCs exactly like Waypoints.lua does (Spawn / Map / CAPITALS).
--   * faction names: CraftersJournal Core.lua FACTION_NAMES, in English from its Locales/enUS.lua.
-- Everything is loaded as DATA (sandboxed loadfile / load with an empty env); nothing of either addon runs.
-- German names: CraftersJournal has none (Spanish and English only); in game the client's own names win anyway
-- (C_Map zone names, faction names).
local P = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "paths.lua")
local ROOT = P.ROOT
local function argv(i) return arg[i] ~= "" and arg[i] or nil end
local CJ = assert(P.CraftersJournal(argv(1)), "CraftersJournal's Data folder not found: pass it as argument 1 or set RQ_CRAFTERSJOURNAL")
local QDB = assert(P.QuestieDB(argv(2)), "QuestieDB not found: pass its folder as argument 2 or set RQ_QUESTIEDB")
local OUT = argv(3) or ROOT -- tests point this at a scratch folder

local PROFS = { "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }
-- the counts of this CraftersJournal + QuestieDB; a changed source fails loudly (check the output, then update)
local EXPECT = { recipes = 1824, npcs = 642, quests = 53, fromQuestie = { items = 68, npcs = 2 } }

local function sandbox(path, ...)
  local chunk = assert(loadfile(path, "t", {}))
  chunk(...)
end
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end
local function readAll(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

---------------------------------------------------------------------------
-- CraftersJournal data
---------------------------------------------------------------------------
local ES = {}
for _, name in ipairs(PROFS) do sandbox(CJ .. name .. ".lua", "CraftersJournal", ES) end
sandbox(CJ .. "Sources.lua", "CraftersJournal", ES)
local D = ES.Data
assert(D.ItemSources and D.NPCs and D.Quests and D.NPCLevels, "CraftersJournal Data/Sources.lua: tables missing")

-- faction names: Core.lua's local FACTION_NAMES (Spanish keys), translated with Locales/enUS.lua
local FACTIONS = {}
do
  local EN = { Locales = {} }
  sandbox(CJ .. "../Locales/enUS.lua", "CraftersJournal", EN)
  local en = assert(EN.Locales.en, "CraftersJournal Locales/enUS.lua: no Locales.en")
  local block = assert(readAll(CJ .. "../Core.lua"):match("local FACTION_NAMES = ES%.Localize%(%b{}%)"),
    "CraftersJournal Core.lua: FACTION_NAMES not found")
  for id, es in block:gmatch('%[(%d+)%]%s*=%s*"([^"]*)"') do FACTIONS[tonumber(id)] = en[es] or es end
end

-- our recipes: [spellID] = { professions } (Synthetic Gordok Ogre Suit is Leatherworking and Tailoring)
local ours = {}
do
  local function add(id, name)
    ours[id] = ours[id] or {}
    for _, p in ipairs(ours[id]) do if p == name then return end end
    table.insert(ours[id], name)
  end
  local ns = {}
  for _, name in ipairs(PROFS) do sandbox(ROOT .. "Data/" .. name .. ".lua", "RavenquillExpedition_CraftAdvisor", ns) end
  sandbox(ROOT .. "Data/Enchants.lua", "RavenquillExpedition_CraftAdvisor", ns)
  for _, name in ipairs(PROFS) do
    for id in pairs(ns.Recipes[name]) do add(id, name) end
  end
  for _, row in ipairs(ns.Enchants.rows) do add(row.spell, "Enchanting") end
end

---------------------------------------------------------------------------
-- QuestieDB: the TOC metadata store (## X-<Entity>-<id>-<field>: base64 CBOR)
---------------------------------------------------------------------------
local store = {}
for line in io.lines(QDB .. "QuestieDB_Forever.toc") do
  local k, v = line:match("^## (X%-[%w]+%-[%w%-]+):%s*(.-)%s*$")
  if k then store[k] = v end
end
local function getStored(key)
  local v = store[key]
  local parts = v and tonumber(v:match("^~(%d+)~$"))
  if not parts then return v end
  local buf = {}
  for i = 1, parts do buf[i] = assert(store[key .. "-" .. i], "QuestieDB: chunk missing " .. key .. "-" .. i) end
  return table.concat(buf)
end

local B64 = {}
do
  local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do B64[abc:byte(i)] = i - 1 end
end
local function unbase64(s)
  local out, bits, n = {}, 0, 0
  for i = 1, #s do
    local v = B64[s:byte(i)]
    if v then
      bits, n = bits * 64 + v, n + 6
      if n >= 8 then
        n = n - 8
        out[#out + 1] = string.char(bits // (1 << n))
        bits = bits % (1 << n)
      end
    end
  end
  return table.concat(out)
end

-- CBOR (RFC 8949) as C_EncodingUtil.DeserializeCBOR returns it: arrays 1-based, maps as tables
local function cbor(s)
  local pos = 1
  local item
  local function arg(info)
    if info < 24 then return info end
    local size = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
    assert(size, "CBOR: indefinite lengths not supported")
    local v = string.unpack(">I" .. size, s, pos)
    pos = pos + size
    return v
  end
  function item()
    local b = s:byte(pos)
    pos = pos + 1
    local major, info = b >> 5, b & 31
    if major == 0 then return arg(info)
    elseif major == 1 then return -1 - arg(info)
    elseif major == 2 or major == 3 then
      local len = arg(info)
      local v = s:sub(pos, pos + len - 1)
      pos = pos + len
      return v
    elseif major == 4 then
      local t = {}
      for i = 1, arg(info) do t[i] = item() end
      return t
    elseif major == 5 then
      local t = {}
      for _ = 1, arg(info) do
        local k = item()
        t[k] = item()
      end
      return t
    elseif major == 6 then
      arg(info)
      return item()
    end
    if info == 20 then return false elseif info == 21 then return true elseif info == 22 or info == 23 then return nil end
    if info == 25 then
      local h = string.unpack(">I2", s, pos)
      pos = pos + 2
      local sign, e, m = (h >> 15) == 1 and -1 or 1, (h >> 10) & 31, h & 1023
      if e == 0 then return sign * m * 2.0 ^ -24 end
      if e == 31 then return m == 0 and sign * math.huge or 0 / 0 end
      return sign * (1 + m / 1024) * 2.0 ^ (e - 15)
    elseif info == 26 then
      local v = string.unpack(">f", s, pos)
      pos = pos + 4
      return v
    elseif info == 27 then
      local v = string.unpack(">d", s, pos)
      pos = pos + 8
      return v
    end
    error("CBOR: unsupported simple value " .. info)
  end
  return item()
end

-- one entity's scalar row (nil = QuestieDB doesn't know the ID) and one of its table fields
local function qRow(entity, id)
  local v = getStored("X-" .. entity .. "-" .. id .. "-S")
  return v and cbor(unbase64(v)) or nil
end
local function qTable(entity, id, row, field)
  if not (row and row.p and (row.p // (1 << (field - 1))) % 2 == 1) then return nil end
  local v = getStored("X-" .. entity .. "-" .. id .. "-" .. field)
  return v and cbor(unbase64(v)) or nil
end

-- QuestieDB's zone tables (support/Forever/Zones: Lua source in strings, as Waypoints.lua's Table() reads them)
local zones = {}
do
  local private = {}
  local env = { QuestieLoader = { ImportModule = function() return { private = private } end } }
  for _, f in ipairs({ "areaIdToUiMapId", "subZoneToParentZone" }) do
    assert(loadfile(QDB .. "support/Forever/Zones/" .. f .. ".lua", "t", env))()
  end
  local function tbl(src) return src and assert(load(src, "=zones", "t", {}))() or {} end
  zones.area, zones.parent = tbl(private.areaIdToUiMapId), tbl(private.subZoneToParentZone)
  zones.areaOverride, zones.parentOverride = tbl(private.areaIdToUiMapIdOverride), tbl(private.subZoneToParentZoneOverride)
  assert(next(zones.area) and next(zones.parent), "QuestieDB zone tables empty")
end

---------------------------------------------------------------------------
-- CraftersJournal's Waypoints.lua, offline
---------------------------------------------------------------------------
local SIDES = { A = "A", H = "H", AH = "" }
local CAPITALS = { [1519] = "A", [1537] = "A", [1657] = "A", [1637] = "H", [1497] = "H", [1638] = "H" }
local function factionOf(v) -- QuestieDB's normalize.faction
  if v == nil or v == "" then return nil end
  if v == "A" or v == "H" then return v end
  return "AH"
end
local function Map(area)
  local map = zones.areaOverride[area] or zones.area[area]
  local parent = not map and (zones.parentOverride[area] or zones.parent[area])
  map = map or (parent and (zones.areaOverride[parent] or zones.area[parent]))
  return type(map) == "number" and map or nil
end
local function Spawn(spawns, home)
  if type(spawns) ~= "table" then return nil end
  local area = type(spawns[home]) == "table" and home or nil
  if not area then
    for candidate in pairs(spawns) do
      if type(candidate) == "number" and (not area or candidate < area) then area = candidate end
    end
  end
  local spots, sumX, sumY = {}, 0, 0
  for _, xy in ipairs(area and type(spawns[area]) == "table" and spawns[area] or {}) do
    local x, y = tonumber(xy[1]), tonumber(xy[2])
    if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
      spots[#spots + 1] = { x, y }
      sumX, sumY = sumX + x, sumY + y
    end
  end
  local best, bestDistance
  for _, spot in ipairs(spots) do
    local d = (spot[1] - sumX / #spots) ^ 2 + (spot[2] - sumY / #spots) ^ 2
    if not bestDistance or d < bestDistance then best, bestDistance = spot, d end
  end
  if not best then return area end
  return area, best[1] / 100, best[2] / 100
end

local fromQuestie = { items = {}, npcs = {} }
local npcCache = {}
-- { name, side, map?, x?, y?, area? } like WP.NPC (side nil = nobody may use it, written as "X")
local function NPC(id)
  if npcCache[id] ~= nil then return npcCache[id] or nil end
  local npc = false
  local baked = D.NPCs[id]
  if baked then
    npc = { name = baked[1], side = baked[2] }
    if baked[3] and baked[3] ~= 0 then npc.map, npc.x, npc.y = baked[3], baked[4], baked[5] else npc.area = baked[6] end
  else
    local row = qRow("Npc", id)
    if row and type(row[1]) == "string" then
      fromQuestie.npcs[id] = true
      local area, x, y = Spawn(qTable("Npc", id, row, 7), row[9])
      local side = SIDES[factionOf(row[13])]
      if side == "" and area then side = CAPITALS[area] or CAPITALS[zones.parentOverride[area] or zones.parent[area]] or "" end
      npc = { name = row[1], side = side }
      local map = area and x and Map(area)
      if map then npc.map, npc.x, npc.y = map, x, y else npc.area = area end
    end
  end
  npcCache[id] = npc
  return npc or nil
end

local function IDs(list)
  local out = {}
  for _, id in ipairs(type(list) == "table" and list or {}) do
    if type(id) == "number" then out[#out + 1] = id end
  end
  return out
end
-- a pattern's vendors and quest rewards like Item() (QuestieDB installed: it answers what Data/Sources.lua lacks)
local function Item(itemID)
  local baked = D.ItemSources[itemID]
  if baked then return { vendors = baked.v or {}, quests = baked.q or {} } end
  local row = qRow("Item", itemID)
  if not row then return { vendors = {}, quests = {} } end
  local it = { vendors = IDs(qTable("Item", itemID, row, 14)), quests = IDs(qTable("Item", itemID, row, 6)) }
  if it.vendors[1] or it.quests[1] then fromQuestie.items[itemID] = true end
  return it
end

---------------------------------------------------------------------------
-- collect
---------------------------------------------------------------------------
local recipes, npcsUsed, questsUsed, levelsUsed = {}, {}, {}, {}
local trainers = {}
for _, name in ipairs(PROFS) do
  local list = {}
  for _, row in ipairs(D[name].trainers) do
    list[#list + 1] = { row[1], row[2] }
    npcsUsed[row[1]] = true
  end
  trainers[name] = list
end
local nRecipes = 0
for _, id in ipairs(sortedKeys(ours)) do
  local profs = ours[id]
  local r = assert(D[profs[1]].recipes[id], profs[1] .. " recipe " .. id .. " unknown to CraftersJournal")
  for i = 2, #profs do -- the same recipe in another profession: its source fields must agree
    local r2 = assert(D[profs[i]].recipes[id], profs[i] .. " recipe " .. id .. " unknown to CraftersJournal")
    for _, k in ipairs({ "fee", "trainer", "basic", "scroll", "scrollPrice", "favor" }) do
      assert(r[k] == r2[k], ("recipe %d: %s differs between %s and %s"):format(id, k, profs[1], profs[i]))
    end
    local function rk(x) return x.rep and (x.rep[1] .. ":" .. x.rep[2]) or "" end
    assert(rk(r) == rk(r2), "recipe " .. id .. ": rep differs between professions")
  end
  nRecipes = nRecipes + 1
  local o = { fee = r.fee, s = r.scroll, p = r.scrollPrice, fv = r.favor, rep = r.rep }
  if r.fee or r.trainer or r.basic then o.t = 1 end
  if r.scroll then
    local it = Item(r.scroll)
    o.v, o.q = it.vendors[1] and it.vendors or nil, it.quests[1] and it.quests or nil
    for _, v in ipairs(it.vendors) do npcsUsed[v] = true end
    for _, q in ipairs(it.quests) do
      local Q = assert(D.Quests[q], "quest " .. q .. " (pattern " .. r.scroll .. ") is not in CraftersJournal's Data/Sources.lua: "
        .. "read it from QuestieDB here (name, startedBy, requiredLevel, requiredRaces) before shipping")
      questsUsed[q] = true
      for _, s in ipairs(Q[4] or {}) do npcsUsed[s] = true end
    end
    local b = D.ItemSources[r.scroll] -- drops / world drops / chests: Data/Sources.lua only (WP.Drops)
    if b and (b.d or b.w or b.o) then
      o.d, o.w, o.wl, o.o = b.d, b.w, b.wl, b.o
      for _, n in ipairs(b.d or {}) do npcsUsed[n] = true; levelsUsed[n] = true end
    end
  end
  recipes[id] = o
end
local npcs, nNpcs = {}, 0
for _, id in ipairs(sortedKeys(npcsUsed)) do
  local n = NPC(id)
  if n then npcs[id] = n; nNpcs = nNpcs + 1 end
end
local nQuests, nFromItems, nFromNpcs = #sortedKeys(questsUsed), #sortedKeys(fromQuestie.items), #sortedKeys(fromQuestie.npcs)
local function expect(what, got, want) assert(got == want, ("%s: %d, expected %d"):format(what, got, want)) end
expect("recipes", nRecipes, EXPECT.recipes)
expect("NPCs", nNpcs, EXPECT.npcs)
expect("quests", nQuests, EXPECT.quests)
expect("patterns with vendors/quests from QuestieDB", nFromItems, EXPECT.fromQuestie.items)
expect("NPCs from QuestieDB", nFromNpcs, EXPECT.fromQuestie.npcs)

---------------------------------------------------------------------------
-- write
---------------------------------------------------------------------------
local function q(s) return string.format("%q", s) end
local function coord(v) return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")) end
local function ids(t) return "{ " .. table.concat(t, ", ") .. " }" end
local w = {}
w[#w + 1] = "-- GENERATED by dev/gen_sources.lua. Do not edit; regenerate."
w[#w + 1] = "-- Where to learn each recipe of Data/<Profession>.lua and Data/Enchants.lua. Source: CraftersJournal's Data/"
w[#w + 1] = "-- <Profession>.lua, Data/Sources.lua and Core.lua (CraftersJournal data, no licence file; private/guild use accepted by the"
w[#w + 1] = "-- user, see NOTICE.txt), completed from QuestieDB (see NOTICE.txt) where CraftersJournal asked it in game. Names are English;"
w[#w + 1] = "-- zones come from the client (C_Map) by map / area ID."
w[#w + 1] = ("-- %d recipes, %d NPCs (%d placed from QuestieDB), %d quests; %d patterns with vendors from QuestieDB.")
  :format(nRecipes, nNpcs, nFromNpcs, nQuests, nFromItems)
w[#w + 1] = "--   recipes[spellID] = { t = 1: a trainer teaches it, fee = trainer fee, s = pattern itemID, p = vendor price,"
w[#w + 1] = "--     fv = Merchant's Favor, rep = { factionID, standing }, v = vendors, q = quests, d = creatures that drop it,"
w[#w + 1] = "--     w = number of creatures (world drop), wl = their { min, max } level, o = number of chests/objects }"
w[#w + 1] = "--   npcs[id] = { name, side (\"A\", \"H\", \"\" both, \"X\" nobody), uiMapID, x, y } (x, y 0-1);"
w[#w + 1] = "--     without coordinates { name, side, 0, 0, 0, areaID } (dungeons; areaID 0 = unknown)"
w[#w + 1] = "--   levels[creature] = { min, max }; quests[id] = { name, side, required level, { quest givers } }"
w[#w + 1] = "--   trainers.<Profession> = { { NPC, ranks: 1 apprentice, 2 journeyman, 4 expert, 8 artisan }, ... }"
w[#w + 1] = "local _, ns = ..."
w[#w + 1] = "ns.Sources = {"
w[#w + 1] = "factions = {"
for _, id in ipairs(sortedKeys(FACTIONS)) do w[#w + 1] = ("  [%d] = %s,"):format(id, q(FACTIONS[id])) end
w[#w + 1] = "},"
w[#w + 1] = "trainers = {"
for _, name in ipairs(PROFS) do
  local parts = {}
  for _, t in ipairs(trainers[name]) do parts[#parts + 1] = ("{ %d, %d }"):format(t[1], t[2]) end
  w[#w + 1] = ("  %s = { %s },"):format(name, table.concat(parts, ", "))
end
w[#w + 1] = "},"
w[#w + 1] = "npcs = {"
for _, id in ipairs(sortedKeys(npcs)) do
  local n = npcs[id]
  local side = q(n.side or "X")
  if n.map then
    w[#w + 1] = ("  [%d] = { %s, %s, %d, %s, %s },"):format(id, q(n.name), side, n.map, coord(n.x), coord(n.y))
  else
    w[#w + 1] = ("  [%d] = { %s, %s, 0, 0, 0, %d },"):format(id, q(n.name), side, n.area or 0)
  end
end
w[#w + 1] = "},"
w[#w + 1] = "levels = {"
for _, id in ipairs(sortedKeys(levelsUsed)) do
  local lv = D.NPCLevels[id]
  if lv then w[#w + 1] = ("  [%d] = { %d, %d },"):format(id, lv[1], lv[2]) end
end
w[#w + 1] = "},"
w[#w + 1] = "quests = {"
for _, id in ipairs(sortedKeys(questsUsed)) do
  local Q = D.Quests[id]
  w[#w + 1] = ("  [%d] = { %s, %s, %d, %s },"):format(id, q(Q[1]), q(Q[2]), Q[3] or 0, ids(Q[4] or {}))
end
w[#w + 1] = "},"
w[#w + 1] = "recipes = {"
for _, id in ipairs(sortedKeys(recipes)) do
  local o, parts = recipes[id], {}
  if o.t then parts[#parts + 1] = "t = 1" end
  if o.fee then parts[#parts + 1] = "fee = " .. o.fee end
  if o.s then parts[#parts + 1] = "s = " .. o.s end
  if o.p then parts[#parts + 1] = "p = " .. o.p end
  if o.fv then parts[#parts + 1] = "fv = " .. o.fv end
  if o.rep then parts[#parts + 1] = ("rep = { %d, %d }"):format(o.rep[1], o.rep[2]) end
  if o.v then parts[#parts + 1] = "v = " .. ids(o.v) end
  if o.q then parts[#parts + 1] = "q = " .. ids(o.q) end
  if o.d then parts[#parts + 1] = "d = " .. ids(o.d) end
  if o.w then parts[#parts + 1] = "w = " .. o.w end
  if o.wl then parts[#parts + 1] = ("wl = { %d, %d }"):format(o.wl[1], o.wl[2]) end
  if o.o then parts[#parts + 1] = "o = " .. o.o end
  w[#w + 1] = ("  [%d] = { %s },"):format(id, table.concat(parts, ", "))
end
w[#w + 1] = "},"
w[#w + 1] = "}"
local text = table.concat(w, "\n") .. "\n"
local f = assert(io.open(OUT .. "Data/Sources.lua", "wb"))
f:write(text)
f:close()
io.stderr:write(("gen_sources: %d recipes, %d NPCs (%d from QuestieDB), %d quests, %d patterns with vendors from QuestieDB, %d bytes\n")
  :format(nRecipes, nNpcs, nFromNpcs, nQuests, nFromItems, #text))
