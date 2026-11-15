-- Ravenquill Expedition: Map – draws ns.Map.members as pins on the world map and minimap via HereBeDragons-Pins.
-- Always placed by map ID (AddWorldMapIconMap / AddMinimapIconMap), never world coordinates: Forever's added zones
-- overlap old ones in world coordinates (WarEffortScout MapPins.lua:1300-1303), plan section 2.
local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local SafeCall, IsSecret = M.SafeCall, M.IsSecret

local HBD = LibStub("HereBeDragons-2.0")
local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local REF = "RavenquillExpedition_Map"
local DOT = "Interface\\AddOns\\RavenquillExpedition_Map\\Media\\dot"
local SIZE = { world = 14, mini = 10 }
local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_WORLD or 3 -- zone, continent and world map

local pins = {}                       -- [key] = { world = frame, mini = frame }
local pool = { world = {}, mini = {} }

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
local function NewPin(kind)
  local f = table.remove(pool[kind])
  if f then return f end
  f = CreateFrame("Button", nil, kind == "mini" and Minimap or UIParent)
  f:Hide() -- HBD shows it once placed (Pins-2.0.lua:172, :475)
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
  if kind == "world" then SafeCall(HBDPins.RemoveWorldMapIcon, HBDPins, REF, f)
  else SafeCall(HBDPins.RemoveMinimapIcon, HBDPins, REF, f) end
  f:Hide()
  f.key, f.at = nil, nil
  p[kind] = nil
  pool[kind][#pool[kind] + 1] = f
end

-- Place (or move) a pin. The minimap updates an icon in place when it's added again (Pins-2.0.lua:575), but the
-- world map acquires a NEW canvas pin on every add (HandlePin -> AcquirePin, :768/:457), so a moved world pin is
-- removed first - otherwise the old one stays behind until the map is reopened (code review #1).
local function Place(p, kind, m)
  local f = p[kind]
  if not f then f = NewPin(kind); p[kind] = f end
  f.key = m.key
  local at = m.mapID .. ":" .. m.x .. ":" .. m.y
  if f.at ~= at then
    local ok, added
    if kind == "world" then
      if f.at then SafeCall(HBDPins.RemoveWorldMapIcon, HBDPins, REF, f) end
      ok, added = pcall(HBDPins.AddWorldMapIconMap, HBDPins, REF, f, m.mapID, m.x, m.y, SHOW_FLAG)
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

function M:RefreshPins()
  local s = self.settings
  if not s then return end
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
    local ok = Valid(m) and state ~= "gone"
    -- world map
    if ok and s.worldmap then
      local f = Place(p, "world", m)
      if f then Style(f, m, state) end
    else
      Release(p, "world")
    end
    -- minimap: only fresh (< 45 s) or stationary positions, plan section 3
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
