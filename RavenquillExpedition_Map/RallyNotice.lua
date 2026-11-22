local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local GS = RavenquillExpedition
local SafeCall = GS.SafeCall

local NOTICE = { w = 400, h = 106, icon = 44, button = 104, inset = 16 }
local notice

function M:RallyHeadline(r)
  local place = r.label ~= "" and r.label or M.ZoneText(r) or L.ZONE_UNKNOWN
  return L.RALLY_WHO:format(r.caller, place)
end

function M:RallyDetails(r)
  local parts = {}
  if r.label ~= "" then parts[1] = M.ZoneText(r) or L.ZONE_UNKNOWN end
  parts[#parts + 1] = L.RALLY_COMING:format(M.RallyCount(r))
  parts[#parts + 1] = L.RALLY_LEFT:format(math.max(1, math.ceil((r.expires - GS:Now()) / 60)))
  return table.concat(parts, " · ")
end

function M.CanSetWaypoint(mapID)
  if not (UiMapPoint and UiMapPoint.CreateFromCoordinates and C_Map and C_Map.SetUserWaypoint) then return false end
  return not C_Map.CanSetUserWaypointOnMap or GS.Bool(SafeCall(C_Map.CanSetUserWaypointOnMap, mapID))
end

function M:SetRallyWaypoint(key)
  local r = self.rallies[key]
  if not (r and M.CanSetWaypoint(r.mapID)) then return end
  SafeCall(C_Map.SetUserWaypoint, SafeCall(UiMapPoint.CreateFromCoordinates, r.mapID, r.x, r.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    SafeCall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
end

function M:RallyAction(key)
  if key == GS:PlayerKey() then return self:CancelRally() end
  self:JoinRally(key)
end

function M:DismissRally(key)
  local r = self.rallies[key]
  if r then r.dismissed = true end
  self:RefreshRallyNotice()
end

function M:FocusRally(key)
  local r = self.rallies[key]
  if not r then return end
  r.dismissed, self.rallyFocus = nil, key
  self:RefreshRallyNotice()
end

local function Text(f, font, gray)
  local s = f:CreateFontString(nil, "OVERLAY", font)
  s:SetJustifyH("LEFT")
  if gray then s:SetTextColor(gray, gray, gray) end
  return s
end

local function Button(f, onClick)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(NOTICE.button, 22)
  b:SetScript("OnClick", function() GS:Call(onClick, M, f.key) end)
  return b
end

local function RoundMask(f, icon)
  local mask = f.CreateMaskTexture and icon.AddMaskTexture and f:CreateMaskTexture()
  if not mask then return end
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(icon)
  icon:AddMaskTexture(mask)
end

local function Icon(f)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(M.icon)
  icon:SetSize(NOTICE.icon, NOTICE.icon)
  icon:SetPoint("TOPLEFT", NOTICE.inset, -NOTICE.inset + 2)
  RoundMask(f, icon)
  local ring = f:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Common\\GoldRing")
  ring:SetSize(NOTICE.icon * 37 / 30, NOTICE.icon * 37 / 30)
  ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
  return icon
end

local function Frame(f)
  f:SetSize(NOTICE.w, NOTICE.h)
  f:SetPoint("TOP", UIParent, "TOP", 0, -200)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f:SetBackdropColor(0.06, 0.05, 0.04, 0.94)
  f:SetBackdropBorderColor(0.86, 0.66, 0.2, 1)
end

local function Build()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  Frame(f)
  local icon = Icon(f)
  f.title = Text(f, "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, 0)
  f.title:SetText(L.RALLY_TITLE)
  f.who = Text(f, "GameFontHighlight")
  f.who:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
  f.who:SetPoint("RIGHT", f, "RIGHT", -NOTICE.inset, 0)
  f.details = Text(f, "GameFontHighlight", 0.62)
  f.details:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -4)
  f.details:SetPoint("RIGHT", f, "RIGHT", -NOTICE.inset, 0)
  f.waypoint = Button(f, M.SetRallyWaypoint)
  f.waypoint:SetPoint("BOTTOMRIGHT", -NOTICE.inset + 2, 10)
  f.waypoint:SetText(L.RALLY_WAYPOINT)
  f.action = Button(f, M.RallyAction)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", -3, -3)
  f.close:SetScript("OnClick", function() GS:Call(M.DismissRally, M, f.key) end)
  f:Hide()
  return f
end

local function ActionText(r, own)
  if own then return L.RALLY_CANCEL end
  return r.joined and L.RALLY_JOINED or L.RALLY_JOIN
end

local function Render(f, r)
  local own = r.key == GS:PlayerKey()
  f.key = r.key
  f.who:SetText(M:RallyHeadline(r))
  f.details:SetText(M:RallyDetails(r))
  f.action:SetText(ActionText(r, own))
  f.action:SetEnabled(own or not r.joined)
  local way = not own and M.CanSetWaypoint(r.mapID)
  f.waypoint:SetShown(way)
  f.action:ClearAllPoints()
  if way then f.action:SetPoint("RIGHT", f.waypoint, "LEFT", -8, 0)
  else f.action:SetPoint("BOTTOMRIGHT", -NOTICE.inset + 2, 10) end
end

function M:NoticeRally()
  local list, focus = self:ShownRallies(), self.rallyFocus
  for _, r in ipairs(list) do
    if r.key == focus and not r.dismissed then return r end
  end
  for _, r in ipairs(list) do
    if not r.dismissed then return r end
  end
end

function M:RefreshRallyNotice()
  local r = self:NoticeRally()
  if not r then
    if notice then notice:Hide() end
    return
  end
  notice = notice or Build()
  self.rallyNotice = notice
  Render(notice, r)
  notice:Show()
end
