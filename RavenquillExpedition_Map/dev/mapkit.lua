local DEV = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local MapKit = { Kit = Kit, DIR = DEV .. "../" }
local ADDON = "RavenquillExpedition_Map"
local FILES = {}
for i, f in ipairs({ "Locale.lua", "Map.lua", "Pins.lua", "Sync.lua" }) do FILES[i] = { MapKit.DIR .. f, ADDON } end

local NOOP = { ClearAllPoints = true, EnableMouse = true, RegisterForClicks = true, SetTexture = true, SetTextColor = true,
  SetFrameStrata = true, UnregisterEvent = true }

local function FrameFactory(c)
  local methods = {
    Hide = function(s) s.shown = false end, Show = function(s) s.shown = true end, IsShown = function(s) return s.shown end,
    SetAlpha = function(s, a) s.alpha = a end, SetScript = function(s, k, fn) s._scripts[k] = fn end,
    RegisterEvent = function(s, e) s._events[e] = true end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetText = function(s, t) s.text = t end,
    SetVertexColor = function(s, r, g, b, a) s.color = { r, g, b, a } end,
    GetZoom = function() return 2 end,
    SetParent = function(s, p) s.parent = p end,
    SetPoint = function(s, ...) s.point = { ... }; s.points = (s.points or 0) + 1 end,
    SetScale = function(s, v) s.scale = v end,
    SetAllPoints = function(s, o) s.allPoints = o end,
    GetWidth = function(s) return s.w or (s.allPoints and s.allPoints:GetWidth()) or 0 end,
    GetHeight = function(s) return s.h or (s.allPoints and s.allPoints:GetHeight()) or 0 end,
    GetFrameLevel = function(s) return s.level or 1 end,
    SetFrameLevel = function(s, l) s.level = l end,
    GetParent = function(s) return s.parent end,
    GetChildren = function(s)
      local out = {}
      for _, x in ipairs(c.frames) do if x.parent == s then out[#out + 1] = x end end
      return table.unpack(out)
    end,
  }
  local function NewFrame(_, _, parent)
    local f = { shown = true, alpha = 1, _scripts = {}, _events = {}, parent = parent }
    return setmetatable(f, { __index = function(_, k)
      if methods[k] then return methods[k] end
      if NOOP[k] then return function() end end
      if type(k) == "string" and k:match("^%u") then error("mock: unknown frame method " .. k, 2) end
      return nil
    end })
  end
  methods.CreateTexture = function() return NewFrame() end
  methods.CreateFontString = function() return NewFrame() end
  return NewFrame
end

local function InstallMapApis(env, c, opts)
  local first, surname = c.name:match("^(%S+) (.+)$")
  env.GetBuildInfo = function() return "1.60.1", "99999", "Nov 2026", 16001 end
  env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CLASSIC = 15, 15, 1, 2
  env.UnitName = function() return first or c.name, surname end
  env.UnitNameUnmodified = env.UnitName
  env.UnitClass = function() return "x", opts.class or "SHAMAN" end
  env.UnitLevel = function() return opts.level or 33 end
  env.UnitOnTaxi = function() return c.taxi end
  env.IsIndoors = function() return false end
  env.C_CVar = { GetCVar = function() return "0" end }
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0 } end })
  env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k:lower() end })
  env.C_Map = {
    GetBestMapForUnit = function() if c.pos then return c.pos[1] end end,
    GetPlayerMapPosition = function()
      local p = c.pos
      if not p then return nil end
      return { GetXY = function() return p[2], p[3] end }
    end,
    GetMapInfo = function(id) if id ~= 999999 then return { name = "Map" .. id } end end,
  }
  env.ChatFrameUtil = { SendTell = function(n) c.tells[#c.tells + 1] = n end }
  env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
  local HBD = {
    GetPlayerZone = function() return c.pos and c.pos[1], 3 end,
    GetPlayerZonePosition = function() local p = c.pos; if p then return p[2] + 0.001, p[3], p[1], 3 end end,
    mapData = { [1429] = { parent = 1415, mapType = 3 }, [1411] = { parent = 1415, mapType = 3 },
      [1415] = { parent = 947, mapType = 2 } },
    GetWorldCoordinatesFromZone = function(_, x, y, mapID)
      if mapID == 999999 then return nil, nil, nil end
      return x * 1000, y * 1000, 0
    end,
    GetZoneCoordinatesFromWorldInstance = function(_, wx, wy, inst, mapID)
      if inst ~= 0 then return end
      if mapID == 1429 then return wx / 1000, wy / 1000 end
      if mapID == 1415 then return 0.4 + wx / 1000 * 0.2, 0.2 + wy / 1000 * 0.2 end
    end,
    GetAzerothWorldMapCoordinatesFromWorld = function(_, wx, wy, inst)
      if inst == 0 then return 0.5 + wx / 1000 * 0.1, 0.5 + wy / 1000 * 0.1 end
    end,
  }
  local function noWorldMapApi() c.hbdWorldCalls = c.hbdWorldCalls + 1; error("mock: HBD world map API used (taints the world map)", 2) end
  local Pins = {
    AddMinimapIconMap = function(_, ref, icon, mapID, x, y)
      assert(ref and type(icon) == "table" and type(mapID) == "number" and type(x) == "number" and type(y) == "number",
        "HBD would raise: bad args")
      if mapID == 999999 then return false end
      c.hbdAdds = c.hbdAdds + 1
      c.hbdMini[icon] = { mapID = mapID, x = x, y = y }
      icon.shown = true
      return true
    end,
    RemoveMinimapIcon = function(_, _, icon) c.hbdMini[icon] = nil; icon.shown = false end,
    AddWorldMapIconMap = noWorldMapApi, AddWorldMapIconWorld = noWorldMapApi,
    RemoveWorldMapIcon = noWorldMapApi, RemoveAllWorldMapIcons = noWorldMapApi,
  }
  env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
  env.LibStub = setmetatable({ minors = { ["HereBeDragons-2.0-RQE"] = 35, ["HereBeDragons-Pins-2.0-RQE"] = 17 } }, {
    __call = function(_, name) return name == "HereBeDragons-2.0-RQE" and HBD or Pins end })
end

function MapKit.Client(sched, bus, name, opts)
  opts = opts or {}
  local c = Kit.Client(sched, bus, name, { class = opts.class, level = opts.level, locale = opts.locale, guild = opts.guild,
    random = opts.random, files = FILES, setup = function(env, kc)
      kc.pos = opts.pos or { 1429, 0.5, 0.5 }
      kc.taxi, kc.tells, kc.hbdMini, kc.hbdAdds, kc.hbdWorldCalls = false, {}, {}, 0, 0
      kc.newFrame = FrameFactory(kc)
      env.UIParent, env.Minimap = kc.newFrame(), kc.newFrame()
      InstallMapApis(env, kc, opts)
      if opts.setup then opts.setup(env, kc) end
    end })
  c.M, c.L = c.ns[ADDON].Map, c.ns[ADDON].L
  c.hbdWorld = c.M.worldPlaced or {}
  function c.set(id, v)
    local o = c.M:Option(id)
    assert(o and o.set, "no option " .. tostring(id))
    o.set(v)
  end
  function c.diag() return table.concat(c.M:Option("diag").lines(), "\n") end
  function c.maxCanvas()
    local per, m = {}, 0
    for f in pairs(c.hbdWorld) do per[f.key] = (per[f.key] or 0) + 1; m = math.max(m, per[f.key]) end
    return m
  end
  return c
end

return MapKit
