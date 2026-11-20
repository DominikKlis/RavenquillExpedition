local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local GS = RavenquillExpedition
local SafeCall, IsSecret = GS.SafeCall, GS.IsSecret

local HBD = LibStub("HereBeDragons-2.0-RQE")
local HBDPins = LibStub("HereBeDragons-Pins-2.0-RQE")
local REF = "RavenquillExpedition_Map"
local DOT = "Interface\\AddOns\\RavenquillExpedition_Map\\Media\\dot"
local SIZE = { world = 14, mini = 10 }
local WORLD_MAP_ID = 947
local LAYER_LEVEL = 500

local pins = {}
local pool = { world = {}, mini = {} }
local placed = {}
M.worldPlaced = placed
local layer
local drawn = {}
local dirty = true

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
  if m.isSelf then f.bg:SetVertexColor(1, 1, 1, 1)
  elseif m.flags and m.flags.t then f.bg:SetVertexColor(1, 0.82, 0, 1)
  else f.bg:SetVertexColor(0, 0, 0, 0.9) end
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

local function AgeText(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec < 120 then return L.TT_AGE_S:format(sec) end
  return L.TT_AGE_M:format(math.floor(sec / 60))
end

local function AddIdentityLines(m)
  local r, g, b = ClassColor(m.class)
  GameTooltip:AddLine(m.name or "?", r, g, b)
  if type(m.level) == "number" and m.level > 0 then
    GameTooltip:AddLine(L.TT_LEVEL_CLASS:format(m.level, ClassName(m.class)), 1, 1, 1)
  end
  local info = m.mapID and SafeCall(C_Map.GetMapInfo, m.mapID)
  if info and type(info.name) == "string" and not IsSecret(info.name) then
    GameTooltip:AddLine(info.name, 0.8, 0.8, 0.8)
  end
end

local function AddFlagLines(f)
  if f.g then GameTooltip:AddLine(L.TT_GHOST, 1, 0.3, 0.3) end
  if f.t then GameTooltip:AddLine(L.TT_TAXI, 1, 0.82, 0) end
  if f.s then GameTooltip:AddLine(L.TT_STATIONARY, 0.7, 0.7, 0.7) end
end

local function AddFooterLines(m)
  if m.isSelf then return GameTooltip:AddLine(L.TT_YOU, 0.5, 0.8, 1) end
  GameTooltip:AddLine(AgeText(M:Age(m)), 0.7, 0.7, 0.7)
  if M:State(m) == "stale" then GameTooltip:AddLine(L.TT_STALE, 1, 0.5, 0.2) end
  if m.fake then return GameTooltip:AddLine(L.TT_TEST, 0.5, 0.8, 1) end
  GameTooltip:AddLine(L.TT_RIGHT_CLICK, 0.5, 1, 0.5)
end

local function OnEnter(self)
  local m = M.members[self.key] or self.unshared
  if not m then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  AddIdentityLines(m)
  if m.unshared then
    GameTooltip:AddLine(L.TT_NOT_SHARING, 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L.TT_RIGHT_CLICK, 0.5, 1, 0.5)
  else
    AddFlagLines(m.flags or {})
    AddFooterLines(m)
  end
  GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

local function OnClick(self)
  local m = M.members[self.key] or self.unshared
  if not m or m.fake or m.isSelf or type(m.name) ~= "string" then return end
  M:Contact(self, m)
end

function M.MemberButton(f)
  f:EnableMouse(true)
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnEnter", OnEnter)
  f:SetScript("OnLeave", OnLeave)
  f:SetScript("OnClick", OnClick)
end
M.ClassColor, M.AgeText = ClassColor, AgeText

local function IsInsideMap(mapData, mapID, uiMapID)
  local parent = mapData[mapID] and mapData[mapID].parent
  while parent and parent ~= uiMapID do parent = mapData[parent] and mapData[parent].parent end
  return parent == uiMapID
end

local function ShowsGuildmates(mapType)
  local UT = Enum and Enum.UIMapType
  return not UT or mapType == UT.Zone or mapType == UT.Dungeon or mapType == UT.Micro or mapType == UT.Continent
end

local function Project(d, uiMapID)
  if uiMapID == WORLD_MAP_ID then return HBD:GetAzerothWorldMapCoordinatesFromWorld(d.wx, d.wy, d.inst) end
  local mapData = HBD.mapData
  if not (mapData and mapData[uiMapID]) then return end
  if uiMapID ~= d.mapID then
    if not IsInsideMap(mapData, d.mapID, uiMapID) then return end
    if not ShowsGuildmates(mapData[uiMapID].mapType) then return end
  end
  return HBD:GetZoneCoordinatesFromWorldInstance(d.wx, d.wy, d.inst, uiMapID)
end

local function MapView()
  local map = WorldMapFrame
  local mapID = SafeCall(map.GetMapID, map)
  local scale = SafeCall(map.GetCanvasScale, map) or 1
  return mapID, scale, layer:GetWidth(), layer:GetHeight()
end

local function UsableView(mapID, scale, w, h)
  return type(mapID) == "number" and type(scale) == "number" and scale > 0 and type(w) == "number" and w > 0
    and type(h) == "number" and h > 0
end

local function ProjectedXY(d, mapID)
  local okP, px, py = pcall(Project, d, mapID)
  if okP and type(px) == "number" and type(py) == "number" then return px, py end
end

local function DrawWorld()
  local mapID, scale, w, h = MapView()
  dirty = false
  drawn.mapID, drawn.scale, drawn.w, drawn.h = mapID, scale, w, h
  local ok = UsableView(mapID, scale, w, h)
  for f, d in pairs(placed) do
    local x, y
    if ok then x, y = ProjectedXY(d, mapID) end
    if x then
      f:SetScale(1 / scale)
      f:ClearAllPoints()
      f:SetPoint("CENTER", layer, "TOPLEFT", x * w * scale, -y * h * scale)
      f:Show()
    else
      f:Hide()
    end
  end
end

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
M.TopCanvasLevel = TopCanvasLevel

local function RaiseLayer()
  local top = TopCanvasLevel()
  local want = math.min(top + 10, 9000)
  if (layer:GetFrameLevel() or 0) < want then
    layer:SetFrameLevel(want)
    for f in pairs(placed) do f:SetFrameLevel(want + 1) end
  end
end

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
  f:Hide()
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
  M.MemberButton(f)
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
      ok, added = pcall(HBDPins.AddMinimapIconMap, HBDPins, REF, f, m.mapID, m.x, m.y, true, false)
    end
    if not ok or not added then Release(p, kind); return end
    f.at = at
  end
  return f
end

local function Valid(m)
  return type(m.mapID) == "number" and type(m.x) == "number" and type(m.y) == "number"
    and m.x >= 0 and m.x <= 1 and m.y >= 0 and m.y <= 1
end

local function GroupSet(s)
  local set = {}
  if not s.hideGroup then return set end
  local keys = GS:Call(GS.GroupGuildies, GS)
  if type(keys) == "table" then
    for _, k in ipairs(keys) do set[k] = true end
  end
  return set
end

local function ReleaseVanished(members)
  for key, p in pairs(pins) do
    if not members[key] then
      Release(p, "world"); Release(p, "mini")
      pins[key] = nil
    end
  end
end

local function ShowOrRelease(p, kind, m, state, show)
  if not show then return Release(p, kind) end
  local f = Place(p, kind, m)
  if f then Style(f, m, state) end
end

local function HiddenAsGroupmate(inGroup, key, m) return inGroup[key] and not m.fake and not m.isSelf end

local function FreshForMinimap(self, m)
  return m.isSelf or (m.flags and m.flags.s) or self:Age(m) < self.C.MINIMAP_FRESH
end

function M:RefreshPins()
  local s = self.settings
  if not s then return end
  local inGroup = GroupSet(s)
  ReleaseVanished(self.members)
  for key, m in pairs(self.members) do
    local p = pins[key] or {}
    pins[key] = p
    local state = self:State(m)
    local ok = Valid(m) and state ~= "gone" and not HiddenAsGroupmate(inGroup, key, m)
    ShowOrRelease(p, "world", m, state, ok and s.worldmap)
    ShowOrRelease(p, "mini", m, state, ok and s.minimap and FreshForMinimap(self, m))
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
