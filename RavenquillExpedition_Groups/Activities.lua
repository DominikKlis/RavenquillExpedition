local ADDON, ns = ...
local GS = RavenquillExpedition
local L = ns.L

local A = {}
ns.Activities = A

A.LIST = {
  { id = "rfc", map = 389, min = 13, max = 18 },
  { id = "wc", map = 43, min = 17, max = 24 },
  { id = "dead", map = 36, min = 17, max = 26 },
  { id = "sfk", map = 33, min = 22, max = 30 },
  { id = "bfd", map = 48, min = 24, max = 32 },
  { id = "stocks", map = 34, min = 24, max = 32 },
  { id = "gnomer", map = 90, min = 29, max = 38 },
  { id = "rfk", map = 47, min = 29, max = 38 },
  { id = "smgy", map = 189, wing = "GRAVEYARD", min = 28, max = 38 },
  { id = "smlib", map = 189, wing = "LIBRARY", min = 29, max = 39 },
  { id = "smarm", map = 189, wing = "ARMORY", min = 32, max = 42 },
  { id = "smcath", map = 189, wing = "CATHEDRAL", min = 35, max = 45 },
  { id = "rfd", map = 129, min = 37, max = 46 },
  { id = "ulda", map = 70, min = 41, max = 51 },
  { id = "zf", map = 209, min = 44, max = 54 },
  { id = "mara", map = 349, min = 46, max = 55 },
  { id = "st", map = 109, min = 50, max = 56 },
  { id = "brd", map = 230, min = 52, max = 60 },
  { id = "lbrs", map = 229, name = "LBRS", min = 55, max = 60 },
  { id = "ubrs", map = 229, name = "UBRS", min = 55, max = 60, size = 10 },
  { id = "dme", map = 429, wing = "EAST", min = 55, max = 60 },
  { id = "dmw", map = 429, wing = "WEST", min = 57, max = 60 },
  { id = "dmn", map = 429, wing = "NORTH", min = 57, max = 60 },
  { id = "strat", map = 329, min = 58, max = 60 },
  { id = "scholo", map = 289, min = 58, max = 60 },
  { id = "zg", map = 309, min = 60, max = 60, size = 20, raid = true },
  { id = "aq20", map = 509, min = 60, max = 60, size = 20, raid = true },
  { id = "mc", map = 409, min = 60, max = 60, size = 40, raid = true },
  { id = "ony", map = 249, min = 60, max = 60, size = 40, raid = true },
  { id = "bwl", map = 469, min = 60, max = 60, size = 40, raid = true },
  { id = "aq40", map = 531, min = 60, max = 60, size = 40, raid = true },
  { id = "naxx", map = 533, min = 60, max = 60, size = 40, raid = true },
}

A.LAYOUT = {
  [5] = { tank = 1, heal = 1, dps = 3 },
  [10] = { tank = 2, heal = 2, dps = 6 },
  [20] = { tank = 2, heal = 4, dps = 14 },
  [40] = { tank = 4, heal = 8, dps = 28 },
}

local byId = {}
for _, a in ipairs(A.LIST) do byId[a.id] = a end

function A.Get(id) return byId[id] end

function A.Needs(a) return A.LAYOUT[a.size or 5] end

function A.Fits(a, level)
  return type(level) == "number" and level >= a.min and level <= a.max
end

local function ClientZone(map)
  local name = GS.Plain(GS.SafeCall(GetRealZoneText, map), "string")
  if name and name ~= "" then return name end
end

function A.ShortName(a)
  if a.name then return L["ACT_" .. a.name] end
  return ClientZone(a.map) or L["ZONE_" .. a.map]
end

function A.Name(a)
  if a.wing then return A.ShortName(a) .. ": " .. L["WING_" .. a.wing] end
  return A.ShortName(a)
end

function A.Title(a)
  if a.raid then return L.RAID_TITLE:format(A.Name(a)) end
  return A.Name(a)
end

function A.Range(a) return L.LEVEL_RANGE:format(a.min, a.max) end
