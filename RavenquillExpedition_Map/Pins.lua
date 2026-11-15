-- Ravenquill Expedition: Map – draws ns.Map.members as pins on the world map (our own layer on the map canvas) and
-- the minimap (HereBeDragons-Pins). Always placed from the member's map ID, never from raw world coordinates: Forever's
-- added zones overlap old ones in world coordinates (WarEffortScout MapPins.lua:1300-1303).
--
-- World map and taint (BugGrabber, 2026-11: ADDON_ACTION_BLOCKED 'Button:SetPassThroughButtons()' on opening the
-- map): we no longer use HBDPins:AddWorldMapIcon*. That registers a data provider on WorldMapFrame, and Blizzard
-- calls every provider's RefreshAllData inside the secure show path (ToggleWorldMap -> ShowUIPanel ->
-- RefreshAllDataProviders). Our (addon) code there tainted the rest of that execution, so Blizzard's own quest pins,
-- acquired after us, were blocked when AcquirePin -> CheckMouseButtonPassthrough called SetPassThroughButtons.
-- Now Blizzard's map code never calls into us: our pins sit on a plain child frame of the canvas that draws them
-- from its own OnUpdate (a separate execution, only while the map is visible). We only read from WorldMapFrame
-- (GetCanvas, GetMapID, GetCanvasScale); no AddDataProvider, AcquirePin, pinPools, hooks or SetPassThroughButtons.
local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local SafeCall, IsSecret = RavenquillExpedition.SafeCall, RavenquillExpedition.IsSecret

-- our own copies under private names (libs/HereBeDragons): Map never writes into the copy other addons share,
-- whose world-map provider runs inside Blizzard's map show (in-game ADDON_ACTION_BLOCKED, 2026-11-15)
local HBD = LibStub("HereBeDragons-2.0-RQE")
local HBDPins = LibStub("HereBeDragons-Pins-2.0-RQE")
local REF = "RavenquillExpedition_Map"
local DOT = "Interface\\AddOns\\RavenquillExpedition_Map\\Media\\dot"
local SIZE = { world = 14, mini = 10 }
local WORLD_MAP_ID = 947 -- the Azeroth world map (HereBeDragons-Pins-2.0.lua WORLD_MAP_ID)
local LAYER_LEVEL = 500  -- frame levels above the canvas: over the map's own pins [VERIFY IN GAME]

local pins = {}                       -- [key] = { world = frame, mini = frame }
local pool = { world = {}, mini = {} }
-- [world pin frame] = { mapID, x, y (as received), wx, wy, inst (HBD world coordinates) }; read by the harnesses
local placed = {}
M.worldPlaced = placed
local layer                           -- our frame on the world map canvas (created with the first world pin)
local drawn = {}                      -- the view the layer last drew: mapID, scale, w, h
local dirty = true

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local function ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end

local function ClassName(class)
  return (class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
end

local function ApplyFrameSize(f)
  local s = SIZE[f.kind] * (M.settings and M.settings.size or 1)
  f:SetSize(s, s)
  f.bg:SetSize(s, s)
  f.fg:SetSize(math.max(2, s - 3), math.max(2, s - 3))
end

local function Style(f, m, state)
  -- ring: black; gold on a taxi; white for your own test pin
  if m.isSelf then f.bg:SetVertexColor(1, 1, 1, 1)
  elseif m.flags and m.flags.t then f.bg:SetVertexColor(1, 0.82, 0, 1)
  else f.bg:SetVertexColor(0, 0, 0, 0.9) end
  -- fill: class color; grey when dead/ghost
  if m.flags and m.flags.g then f.fg:SetVertexColor(0.55, 0.55, 0.55, 1)
  else f.fg:SetVertexColor(ClassColor(m.class)) end
  f:SetAlpha(state == "stale" and 0.45 or 1)
  if f.label then
    if M.settings.names then
      f.label:SetText(m.name or "")
      f.label:SetTextColor(ClassColor(m.class))
      f.label:Show()
    else
      f.label:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Tooltip and click
---------------------------------------------------------------------------
local function AgeText(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec < 120 then return L.TT_AGE_S:format(sec) end
  return L.TT_AGE_M:format(math.floor(sec / 60))
end

local function OnEnter(self)
  local m = M.members[self.key]
  if not m then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local r, g, b = ClassColor(m.class)
  GameTooltip:AddLine(m.name or "?", r, g, b)
  if type(m.level) == "number" and m.level > 0 then
    GameTooltip:AddLine(L.TT_LEVEL_CLASS:format(m.level, ClassName(m.class)), 1, 1, 1)
  end
  local info = m.mapID and SafeCall(C_Map.GetMapInfo, m.mapID)
  if info and type(info.name) == "string" and not IsSecret(info.name) then
    GameTooltip:AddLine(info.name, 0.8, 0.8, 0.8)
  end
  local f = m.flags or {}
  if f.g then GameTooltip:AddLine(L.TT_GHOST, 1, 0.3, 0.3) end
  if f.t then GameTooltip:AddLine(L.TT_TAXI, 1, 0.82, 0) end
  if f.s then GameTooltip:AddLine(L.TT_STATIONARY, 0.7, 0.7, 0.7) end
  if not m.isSelf then
    GameTooltip:AddLine(AgeText(M:Age(m)), 0.7, 0.7, 0.7)
    if M:State(m) == "stale" then GameTooltip:AddLine(L.TT_STALE, 1, 0.5, 0.2) end
  end
  if m.isSelf then GameTooltip:AddLine(L.TT_YOU, 0.5, 0.8, 1)
  elseif m.fake then GameTooltip:AddLine(L.TT_TEST, 0.5, 0.8, 1)
  else GameTooltip:AddLine(L.TT_CLICK, 0.5, 1, 0.5) end
  GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

local function OnClick(self)
  local m = M.members[self.key]
  if not m or m.fake or m.isSelf or type(m.name) ~= "string" then return end
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell -- Forever: ChatFrameUtil.* (GCA UI.lua:407)
  SafeCall(tell, m.whisper or m.name) -- the raw sender name, as the server gave it
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- World map layer
---------------------------------------------------------------------------
-- A world pin's position on the map being shown (0-1), or nil when it isn't on that map. The same rules as
-- HereBeDragons-Pins' HandlePin with HBD_PINS_WORLDMAP_SHOW_WORLD: its own map, any map above it (parent zone,
-- continent) and the Azeroth world map.
local function Project(d, uiMapID)
  if uiMapID == WORLD_MAP_ID then return HBD:GetAzerothWorldMapCoordinatesFromWorld(d.wx, d.wy, d.inst) end
  local mapData = HBD.mapData
  if not (mapData and mapData[uiMapID]) then return end
  if uiMapID ~= d.mapID then
    local parent = mapData[d.mapID] and mapData[d.mapID].parent
    while parent and parent ~= uiMapID do parent = mapData[parent] and mapData[parent].parent end
    if parent ~= uiMapID then return end
    local t, UT = mapData[uiMapID].mapType, Enum and Enum.UIMapType
    if UT and t ~= UT.Zone and t ~= UT.Dungeon and t ~= UT.Micro and t ~= UT.Continent then return end
  end
  return HBD:GetZoneCoordinatesFromWorldInstance(d.wx, d.wy, d.inst, uiMapID)
end

local function MapView()
  local map = WorldMapFrame
  local mapID = SafeCall(map.GetMapID, map)
  local scale = SafeCall(map.GetCanvasScale, map) or 1
  return mapID, scale, layer:GetWidth(), layer:GetHeight()
end

local function DrawWorld()
  local mapID, scale, w, h = MapView()
  dirty = false
  drawn.mapID, drawn.scale, drawn.w, drawn.h = mapID, scale, w, h
  local ok = type(mapID) == "number" and type(scale) == "number" and scale > 0 and type(w) == "number" and w > 0
    and type(h) == "number" and h > 0
  for f, d in pairs(placed) do
    local x, y
    if ok then
      local okP, px, py = pcall(Project, d, mapID)
      if okP and type(px) == "number" and type(py) == "number" then x, y = px, py end
    end
    if x then
      -- the same size at every zoom level; SetPoint offsets are in the pin's own (scaled) units
      f:SetScale(1 / scale)
      f:ClearAllPoints()
      f:SetPoint("CENTER", layer, "TOPLEFT", x * w * scale, -y * h * scale)
      f:Show()
    else
      f:Hide()
    end
  end
end

-- Our layer must sit above everything else on the map canvas: the map's own art and Blizzard's pins are frames there
-- too, with frame levels the map assigns as it builds them. A fixed offset was not enough in game (the pins were
-- "visible" but drawn under the map art), so the layer goes above the highest level it finds. Read-only on Blizzard's
-- frames; only our own frame levels change.
local function TopCanvasLevel()
  local canvas = layer and layer:GetParent()
  if not canvas then return 0 end
  local top = canvas:GetFrameLevel() or 0
  local kids = { canvas:GetChildren() }
  for i = 1, #kids do
    local k = kids[i]
    if k ~= layer and k.GetFrameLevel then
      local lvl = k:GetFrameLevel()
      if type(lvl) == "number" and lvl > top then top = lvl end
    end
  end
  return top
end
M.TopCanvasLevel = TopCanvasLevel -- (diagnostics)

local function RaiseLayer()
  local top = TopCanvasLevel()
  local want = math.min(top + 10, 9000)
  if (layer:GetFrameLevel() or 0) < want then
    layer:SetFrameLevel(want)
    for f in pairs(placed) do f:SetFrameLevel(want + 1) end
  end
end

-- Runs only while the map is visible (the layer is a child of the canvas), once per frame: redraws when our pins
-- changed or the map shows another map or zoom level; checks twice a second that nothing new sits above us.
local sinceRaise = 1
local function OnLayerUpdate(_, elapsed)
  sinceRaise = sinceRaise + (elapsed or 0)
  if sinceRaise >= 0.5 then sinceRaise = 0; RaiseLayer() end
  if not dirty then
    local mapID, scale, w, h = MapView()
    if mapID == drawn.mapID and scale == drawn.scale and w == drawn.w and h == drawn.h then return end
  end
  RaiseLayer()
  DrawWorld()
end

local function Layer()
  if layer then return layer end
  local map = WorldMapFrame
  local canvas = map and map.GetCanvas and SafeCall(map.GetCanvas, map)
  if not canvas then return end
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel((canvas:GetFrameLevel() or 0) + LAYER_LEVEL)
  layer:SetScript("OnUpdate", OnLayerUpdate)
  for f in pairs(placed) do f:SetParent(layer) end
  for _, f in ipairs(pool.world) do f:SetParent(layer) end
  M.worldLayer = layer
  return layer
end

local function NewPin(kind)
  local f = table.remove(pool[kind])
  if f then return f end
  f = CreateFrame("Button", nil, kind == "mini" and Minimap or Layer() or UIParent)
  f:Hide() -- shown once placed: by HBD on the minimap (Pins-2.0.lua:172), by DrawWorld on the world map
  f.kind = kind
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetTexture(DOT)
  f.bg:SetPoint("CENTER")
  f.fg = f:CreateTexture(nil, "ARTWORK")
  f.fg:SetTexture(DOT)
  f.fg:SetPoint("CENTER")
  if kind == "world" then
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
  end
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp")
  f:SetScript("OnEnter", OnEnter)
  f:SetScript("OnLeave", OnLeave)
  f:SetScript("OnClick", OnClick)
  ApplyFrameSize(f)
  return f
end

local function Release(p, kind)
  local f = p[kind]
  if not f then return end
  if kind == "world" then placed[f] = nil; dirty = true
  else SafeCall(HBDPins.RemoveMinimapIcon, HBDPins, REF, f) end
  f:Hide()
  f.key, f.at = nil, nil
  p[kind] = nil
  pool[kind][#pool[kind] + 1] = f
end

-- A world pin: remember where it is in world coordinates (the layer draws it); false when HBD doesn't know the map.
local function PlaceWorld(f, m)
  local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(m.x, m.y, m.mapID)
  if type(wx) ~= "number" or type(wy) ~= "number" then return false end
  local l = Layer()
  if l then
    f:SetParent(l)
    f:SetFrameLevel((l:GetFrameLevel() or 0) + 1)
  end
  placed[f] = { mapID = m.mapID, x = m.x, y = m.y, wx = wx, wy = wy, inst = inst }
  dirty = true
  return true
end

-- Place (or move) a pin. The minimap updates an icon in place when it's added again (Pins-2.0.lua:575); a world pin
-- is one frame per member that the layer moves (no orphan pins after a move).
local function Place(p, kind, m)
  local f = p[kind]
  if not f then f = NewPin(kind); p[kind] = f end
  f.key = m.key
  local at = m.mapID .. ":" .. m.x .. ":" .. m.y
  if f.at ~= at then
    local ok, added
    if kind == "world" then
      ok, added = pcall(PlaceWorld, f, m)
    else
      -- showInParentZone: someone in a cave/sub-map still shows for a viewer in the zone around it
      ok, added = pcall(HBDPins.AddMinimapIconMap, HBDPins, REF, f, m.mapID, m.x, m.y, true, false)
    end
    if not ok or not added then Release(p, kind); return end -- map HBD doesn't know: no pin
    f.at = at
  end
  return f
end

---------------------------------------------------------------------------
-- Called by M:Refresh() every tick and after any change
---------------------------------------------------------------------------
local function Valid(m)
  return type(m.mapID) == "number" and type(m.x) == "number" and type(m.y) == "number"
    and m.x >= 0 and m.x <= 1 and m.y >= 0 and m.y <= 1
end

-- Guildmates in my party/raid (keys), when the option hides them; else an empty set.
local function GroupSet(s)
  local set = {}
  if not s.hideGroup then return set end
  local ok, keys = pcall(RavenquillExpedition.GroupGuildies, RavenquillExpedition)
  if ok and type(keys) == "table" then
    for _, k in ipairs(keys) do set[k] = true end
  end
  return set
end

function M:RefreshPins()
  local s = self.settings
  if not s then return end
  local inGroup = GroupSet(s)
  for key, p in pairs(pins) do
    if not self.members[key] then
      Release(p, "world"); Release(p, "mini")
      pins[key] = nil
    end
  end
  for key, m in pairs(self.members) do
    local p = pins[key] or {}
    pins[key] = p
    local state = self:State(m)
    local ok = Valid(m) and state ~= "gone" and not (inGroup[key] and not m.fake and not m.isSelf)
    -- world map
    if ok and s.worldmap then
      local f = Place(p, "world", m)
      if f then Style(f, m, state) end
    else
      Release(p, "world")
    end
    -- minimap: only fresh (< 45 s) or stationary positions (older ones would be in the wrong place)
    local miniOk = ok and s.minimap and (m.isSelf or (m.flags and m.flags.s) or self:Age(m) < self.C.MINIMAP_FRESH)
    if miniOk then
      local f = Place(p, "mini", m)
      if f then Style(f, m, state) end
    else
      Release(p, "mini")
    end
  end
end

function M:ApplySize()
  for _, p in pairs(pins) do
    if p.world then ApplyFrameSize(p.world) end
    if p.mini then ApplyFrameSize(p.mini) end
  end
  for _, list in pairs(pool) do for _, f in ipairs(list) do ApplyFrameSize(f) end end
end

function M:CountPins()
  local w, mm = 0, 0
  for _, p in pairs(pins) do
    if p.world then w = w + 1 end
    if p.mini then mm = mm + 1 end
  end
  return w, mm
end
