local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section
local ADDONS = Kit.ADDONS
local MAP, CA, HL = ADDONS .. "RavenquillExpedition_Map/", ADDONS .. "RavenquillExpedition_CraftAdvisor/", "RavenquillExpedition_Highlights"
local GEAR = dofile(CA .. "dev/fixtures/gear_sets.lua")
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

local FILES = {}
for _, f in ipairs({ "Locale.lua", "Map.lua", "Pins.lua", "Sync.lua" }) do FILES[#FILES + 1] = { MAP .. f, "RavenquillExpedition_Map" } end
for _, f in ipairs(dofile(DEV .. "toc.lua")(CA)) do
  if not f:find("^UI/") then FILES[#FILES + 1] = { CA .. f, "RavenquillExpedition_CraftAdvisor" } end
end

local function Setup(gear)
  return function(env, c)
    c.pos, c.gear = { 1429, 0.5, 0.5 }, gear
    env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end,
      GetItemInfoInstant = function() end, GetItemStats = function() return {} end }
    env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
    env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
    env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
    env.LOOT_ITEM_SELF, env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
    env.LOOT_ITEM, env.LOOT_ITEM_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d."
    env.RAID_CLASS_COLORS = {}
    env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k:lower() end })
    env.C_Map = {
      GetBestMapForUnit = function() return c.pos[1] end,
      GetPlayerMapPosition = function() local p = c.pos; return { GetXY = function() return p[2], p[3] end } end,
      GetMapInfo = function(id) return { name = "Map" .. id } end,
    }
    env.UnitOnTaxi, env.IsIndoors = function() return false end, function() return false end
    env.C_CVar = { GetCVar = function() return "0" end }
    local HBD = { GetPlayerZone = function() return c.pos[1], 3 end,
      GetPlayerZonePosition = function() return c.pos[2], c.pos[3], c.pos[1], 3 end,
      GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end }
    local Pins = { AddMinimapIconMap = function() return true end, RemoveMinimapIcon = function() end }
    env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
    env.LibStub = setmetatable({ minors = { ["HereBeDragons-2.0-RQE"] = 35, ["HereBeDragons-Pins-2.0-RQE"] = 17 } }, {
      __call = function(_, name) return name == "HereBeDragons-2.0-RQE" and HBD or Pins end })
    env.Enum = {}
    env.GetInventoryItemLink = function(u, slot) if u == "player" then return c.gear[slot] end end
    env.UnitGUID = function(u) if u == "player" then return "G-" .. c.name end end
    env.UnitIsPlayer = function(u) return u == "player" end
    env.UnitIsUnit = function(a, b) return a == b end
    env.C_SpellBook = { IsSpellKnown = function() return false end }
    env.GetNumSubgroupMembers = function() return 0 end
  end
end

local sched, bus = Kit.Setup()
local CLASSES = { ["Anna Stone"] = "ROGUE", ["Bert Hill"] = "DRUID", ["Cora Vale"] = "HUNTER" }
local clients = {}
for i, name in ipairs({ "Anna Stone", "Bert Hill", "Cora Vale" }) do
  clients[i] = Kit.Client(sched, bus, name, { class = CLASSES[name], level = 35, addons = { HL }, files = FILES,
    random = Kit.Random(i * 7), setup = Setup(copy(GEAR[i])) })
end
local A, B, Cc = clients[1], clients[2], clients[3]
for _, c in ipairs(clients) do c.login() end
sched:advance(60)

section("Three clients, all modules, 40 virtual minutes")
local loaded = true
for _, c in ipairs(clients) do
  if not (c.module("Highlights") and c.module("Map") and c.module("Craft")) then loaded = false end
end
check(loaded, "every client runs Highlights, Map and CraftAdvisor on its core")
local mapOnCore = A.ns["RavenquillExpedition_Map"] and A.RQ.Comm.prefixes["RQEMap1"] ~= nil
local caOnCore = A.RQ.Comm.prefixes["GCAdv1"] ~= nil
check(mapOnCore and caOnCore, "Map (RQEMap1, state lane) and CraftAdvisor (GCAdv1, record lane) send through the core")

local walkRand = Kit.Random(99)
sched:at(sched.t + 2, function()
  local p = A.pos
  local nx, ny = p[2] + (walkRand() - 0.5) * 0.004, p[3] + (walkRand() - 0.5) * 0.004
  A.pos = { p[1], math.min(0.9, math.max(0.1, nx)), math.min(0.9, math.max(0.1, ny)) }
end, 2)
local gearTurn = 0
sched:at(sched.t + 180, function()
  if sched.t > 40 * 60 + 60 then return end
  gearTurn = gearTurn + 1
  B.gear = copy(GEAR[(gearTurn % 2 == 1) and 4 or 2])
  B.fire("PLAYER_EQUIPMENT_CHANGED")
end, 180)
local H = Cc.module("Highlights")
H.db.settings.shareCap = 100
local ids = {}
local lvl = 30
sched:at(sched.t + 120, function()
  if sched.t > 40 * 60 + 60 then return end
  lvl = lvl + 1
  local t = Cc.RQ:Now()
  local e = { k = "level", t = t, who = "Cora Vale", lvl = lvl, cls = "HUNTER", id = H:NextID("Cora Vale", t) }
  if H:Add(e, "self") then ids[#ids + 1] = e.id end
end, 120)

sched:advance(40 * 60)
sched:advance(10 * 60)

section("Budget per client (all prefixes)")
local CC = A.RQ.CommConst
local CAP60, CAP600 = CC.BURST + 60 * CC.RATE, CC.BURST + 600 * CC.RATE
local MC = A.ns["RavenquillExpedition_Map"].Map.C
for _, c in ipairs(clients) do
  local m60, m600 = bus:maxPer(60, c.name), bus:maxPer(600, c.name)
  check(m60 <= CAP60 and m600 <= CAP600, ("%s: at most %d GUILD messages in any 60 s (<= %d), %d in any 600 s (<= %d)"):format(
    c.name, m60, CAP60, m600, CAP600))
end
local mapPer600 = bus:maxPer(600, "Anna Stone", { RQEMap1 = true })
check(mapPer600 <= 600 / MC.INTERVAL_MIN + 1, ("Anna's positions keep Map's %d s floor: %d in any 600 s (<= %d)"):format(
  MC.INTERVAL_MIN, mapPer600, 600 / MC.INTERVAL_MIN + 1))
for _, c in ipairs({ B, Cc }) do
  local m600 = bus:maxPer(600, c.name)
  check(m600 <= 22, ("%s (not walking): %d in any 600 s (<= 22: own events/records + heartbeats)"):format(c.name, m600))
end

section("Every module got through")
local walked = bus:count(function(e) return e.sender == "Anna Stone" and e.prefix == "RQEMap1" end)
check(walked >= 5, "Anna's positions went out on the state lane (" .. walked .. ")")
local function hasAll(c)
  local have = {}
  for _, e in ipairs((c.module("Highlights"):Log())) do have[e.id] = true end
  for _, id in ipairs(ids) do if not have[id] then return false end end
  return true
end
check(#ids == 20 and hasAll(A) and hasAll(B) and next(H.cdb.outbox) == nil,
  ("every highlight delivered: %d logged, at Anna and Bert, Cora's outbox empty"):format(#ids))
local recs, partial, total = {}, 0, 0
for _, e in ipairs(bus.log) do
  if e.prefix == "GCAdv1" then
    local subj, ts, i, n = e.msg:match("^G;([^;]*);[^;]*;[^;]*;([^;]*);[^;]*;(%d)/(%d);")
    if subj then
      local k = e.sender .. "|" .. subj .. "|" .. ts
      recs[k] = recs[k] or { n = tonumber(n), got = {} }
      recs[k].got[tonumber(i)] = true
    end
  end
end
for _, r in pairs(recs) do
  total = total + 1
  for i = 1, r.n do if not r.got[i] then partial = partial + 1 break end end
end
local bertRecs = 0
for k in pairs(recs) do if k:match("^Bert Hill||") then bertRecs = bertRecs + 1 end end
check(total > 0 and partial == 0 and bertRecs >= 5, ("every gear record went out whole (%d records, %d of Bert's, %d partial)"):format(total, bertRecs, partial))
local function sig(c, items) return c.ns["RavenquillExpedition_CraftAdvisor"].GCA:GearSignature(items) end
local GA, GC = A.ns["RavenquillExpedition_CraftAdvisor"].GCA, Cc.ns["RavenquillExpedition_CraftAdvisor"].GCA
local ra, rc = GA.db.members["Bert Hill"], GC.db.members["Bert Hill"]
check(ra and rc and sig(A, ra.items) == sig(A, B.gear) and sig(Cc, rc.items) == sig(Cc, B.gear), "Anna and Cora hold Bert's latest gear")
local errs = {}
for _, c in ipairs(clients) do for _, e in ipairs(c.errors) do errs[#errs + 1] = c.name .. ": " .. tostring(e) end end
check(#errs == 0, "no Lua errors (" .. tostring(errs[1]) .. ")")
for _, c in ipairs(clients) do
  local st = c.RQ:CommState()
  print(("  info: %s sent %d, delivered %d, lost %d, slow %s"):format(c.name, st.sent, st.delivered, st.lost, tostring(st.slow)))
end

Kit.finish()
