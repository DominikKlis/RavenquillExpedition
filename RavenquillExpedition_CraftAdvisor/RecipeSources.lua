local _, ns = ...
local W = { world = {} }
local G = _G
ns.RecipeSources = W

local SafeCall = ns.GCA.SafeCall

function W.DB()
  local db = ns.Sources
  if type(db) == "table" and type(db.recipes) == "table" and type(db.npcs) == "table" then return db end
  return nil
end

local SIDE = { Alliance = "A", Horde = "H" }
function W.Side()
  return SIDE[SafeCall(UnitFactionGroup, "player") or ""]
end

local function Num01(v) return type(v) == "number" and v >= 0 and v <= 1 end

local function MapCoords(row)
  if type(row[3]) == "number" and row[3] ~= 0 and Num01(row[4]) and Num01(row[5]) then return row[3], row[4], row[5] end
end

local function ZoneName(map, area)
  if not C_Map then return nil end
  local zone = map and SafeCall(C_Map.GetMapInfo, map)
  if type(zone) == "table" then zone = zone.name
  elseif (tonumber(area) or 0) > 0 then zone = SafeCall(C_Map.GetAreaInfo, area) end
  if type(zone) == "string" and zone ~= "" then return zone end
end

local function LevelLabel(lv)
  if type(lv) ~= "table" or not (tonumber(lv[1]) and tonumber(lv[2])) then return nil end
  return lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. "-" .. lv[2])
end

function W.NpcInfo(db, id)
  local row = type(id) == "number" and db.npcs[id]
  if type(row) ~= "table" or type(row[1]) ~= "string" then return nil end
  local n = { id = id, name = row[1], side = row[2] }
  n.map, n.x, n.y = MapCoords(row)
  n.zone = ZoneName(n.map, row[6])
  n.level = LevelLabel(type(db.levels) == "table" and db.levels[id])
  return n
end
local NpcInfo = W.NpcInfo

local function Usable(n, side) return n.side == "" or (side ~= nil and n.side == side) end

local function WorldPosition(n)
  if not (n.map and C_Map and C_Map.GetWorldPosFromMapPos and G.CreateVector2D) then return false end
  local ok, inst, x, y = pcall(function()
    local i, pos = C_Map.GetWorldPosFromMapPos(n.map, G.CreateVector2D(n.x, n.y))
    return i, pos:GetXY()
  end)
  if ok and inst and x and y then return { inst, x, y } end
  return false
end

function W.Distance(n)
  local w = W.world[n.id]
  if w == nil then
    w = WorldPosition(n)
    W.world[n.id] = w
  end
  if not (w and G.UnitPosition) then return math.huge end
  local ok, px, py, _, inst = pcall(G.UnitPosition, "player")
  if not (ok and px and py) or inst ~= w[1] then return math.huge end
  return (px - w[2]) ^ 2 + (py - w[3]) ^ 2
end

function W.NearestNpc(db, ids, side)
  if type(ids) ~= "table" or type(ids[1]) ~= "number" then return nil end
  local best, bestD = nil, math.huge
  for _, id in ipairs(ids) do
    local n = NpcInfo(db, id)
    if n and Usable(n, side) then
      local d = W.Distance(n)
      if not best or d < bestD then best, bestD = n, d end
    end
  end
  return best or NpcInfo(db, ids[1])
end
local NearestNpc = W.NearestNpc

function W.Trainers(db, prof, level)
  local rank = level <= 75 and 1 or level <= 150 and 2 or level <= 225 and 4 or 8
  local out = {}
  local list = type(db.trainers) == "table" and db.trainers[prof]
  for _, row in ipairs(type(list) == "table" and list or {}) do
    if type(row) == "table" and math.floor((tonumber(row[2]) or 0) / rank) % 2 == 1 then out[#out + 1] = row[1] end
  end
  return out
end

function W.Standing(id)
  local d = C_Reputation and SafeCall(C_Reputation.GetFactionDataByID, id)
  if type(d) == "table" and tonumber(d.reaction) then return d.reaction, d.name end
  if G.GetFactionInfoByID then
    local ok, name, _, st = pcall(G.GetFactionInfoByID, id)
    if ok and tonumber(st) then return st, name end
  end
  return 4, nil
end

local Secret = ns.GCA.IsSecret
local function StandingName(n)
  local v = type(n) == "number" and _G["FACTION_STANDING_LABEL" .. n]
  if type(v) == "string" and v ~= "" and not Secret(v) then return v end
  return tostring(n)
end
local function FactionName(db, id)
  local _, name = W.Standing(id)
  if type(name) == "string" and name ~= "" and not Secret(name) then return name end
  local en = type(db.factions) == "table" and db.factions[id]
  return type(en) == "string" and en or ("#" .. tostring(id))
end

local function Append(list, source)
  if source then list[#list + 1] = source end
end

local function TrainerSource(db, r, info, prof, side)
  local skill = (info.skill or 0) > 0 and info.skill or 1
  return { kind = "trainer", cost = tonumber(r.fee), npc = NearestNpc(db, W.Trainers(db, prof, skill), side) }
end

local function QuestSource(db, qid, side)
  local q = type(db.quests) == "table" and db.quests[qid]
  if type(q) ~= "table" or type(q[1]) ~= "string" then return nil end
  if q[2] ~= "" and q[2] ~= side then return nil end
  return { kind = "quest", name = q[1], level = tonumber(q[3]), npc = NearestNpc(db, q[4], side) }
end

local function VendorSource(db, r, side)
  if type(r.v) ~= "table" or not r.v[1] then return nil end
  local usable = {}
  for _, id in ipairs(r.v) do
    local n = NpcInfo(db, id)
    if n and Usable(n, side) then usable[#usable + 1] = id end
  end
  local s = { kind = "vendor", cost = tonumber(r.p), favor = tonumber(r.fv), count = #usable }
  s.npc = NearestNpc(db, usable, side)
  s.otherSide = s.npc == nil
  return s
end

local function DropSource(db, r, side)
  local s = { kind = "drop", count = #r.d, npc = NearestNpc(db, r.d, side), npcs = {} }
  for i = 1, math.min(#r.d, 6) do s.npcs[#s.npcs + 1] = NpcInfo(db, r.d[i]) end
  s.npc = s.npc or s.npcs[1]
  if s.npc then return s end
end

local function LootSource(db, r, side)
  if type(r.d) == "table" and type(r.d[1]) == "number" then return DropSource(db, r, side) end
  if tonumber(r.w) then
    local lv = type(r.wl) == "table" and tonumber(r.wl[1]) and tonumber(r.wl[2]) and r.wl or nil
    return { kind = "world", count = tonumber(r.w), levels = lv }
  end
  if tonumber(r.o) then return { kind = "objects", count = tonumber(r.o) } end
end

local function AddScrollSources(list, db, r, side)
  for _, qid in ipairs(type(r.q) == "table" and r.q or {}) do Append(list, QuestSource(db, qid, side)) end
  Append(list, VendorSource(db, r, side))
  Append(list, LootSource(db, r, side))
end

local function Reputation(db, rep)
  if type(rep) ~= "table" or not tonumber(rep[1]) or not tonumber(rep[2]) then return nil end
  return { standing = StandingName(rep[2]), name = FactionName(db, rep[1]), met = (W.Standing(rep[1])) >= rep[2] }
end

function W.Collect(info, prof, spellID)
  local db = W.DB()
  local r = db and db.recipes[spellID]
  if type(r) ~= "table" then return false end
  local list, side = info.list, W.Side()
  if r.t then list[#list + 1] = TrainerSource(db, r, info, prof, side) end
  info.scroll = tonumber(r.s)
  if info.scroll then AddScrollSources(list, db, r, side) end
  local rep = Reputation(db, r.rep)
  if rep then info.rep = rep end
  return true
end

return W
