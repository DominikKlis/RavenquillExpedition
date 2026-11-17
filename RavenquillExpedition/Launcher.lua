local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain

local L = GS.NewLocale({
  enUS = {
    LEFT = "Left-click: overview (/rq)", RIGHT = "Right-click: Craft Advisor window", DRAG = "Drag: move this button",
    NO_STATUS = "no status",
  },
  deDE = {
    LEFT = "Linksklick: Übersicht (/rq)", RIGHT = "Rechtsklick: Fenster des Craft Advisors", DRAG = "Ziehen: Knopf verschieben",
    NO_STATUS = "kein Status",
  },
})
ns.LauncherL = L

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local CRAFT_V01_DEFAULT_ANGLE = 200
local ANGLE_WITHOUT_OTHER_BUTTONS = 225
local RIM_TOLERANCE = 12
local MIN_BUTTON_W, MAX_BUTTON_W = 24, 40
local PLACE_DELAY_AFTER_WORLD = 5
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local btn

function GS:LauncherSettings()
  local db = self.db
  if not db then return {} end
  if type(db.launcher) ~= "table" then
    local s = {}
    local craft = rawget(_G, "RavenquillExpeditionCraftDB")
    local old = type(craft) == "table" and type(craft.settings) == "table" and craft.settings or nil
    if old then
      s.hide = old.minimapHide and true or nil
      s.angle = type(old.minimapAngle) == "number" and old.minimapAngle or nil
      s.dragged = old.minimapDragged and true or nil
    end
    db.launcher = s
  end
  return db.launcher
end

local function Radius()
  local w, h = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140
  return math.min(w, h) / 2 + 5
end

local function UpdatePosition()
  if not btn then return end
  local angle = math.rad(GS:LauncherSettings().angle or ANGLE_WITHOUT_OTHER_BUTTONS)
  local r = Radius()
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function ProbeMethod(obj, method, ...)
  local fn = obj and SafeCall(function() return obj[method] end)
  if type(fn) ~= "function" then return end
  return SafeCall(fn, obj, ...)
end

local function MinimapGeometry()
  local scale = Plain(ProbeMethod(Minimap, "GetEffectiveScale"), "number") or 1
  local x, y = ProbeMethod(Minimap, "GetCenter")
  x, y = Plain(x, "number"), Plain(y, "number")
  if not (x and y) then return nil end
  local w = Plain(ProbeMethod(Minimap, "GetWidth"), "number") or 140
  local h = Plain(ProbeMethod(Minimap, "GetHeight"), "number") or 140
  return { x = x * scale, y = y * scale, scale = scale, rim = math.min(w, h) / 2 }
end

local EXCLUSIONS = {
  function(e) return e.type ~= "Button" and "not a button" end,
  function(e) return not e.visible and "hidden" end,
  function(e) return (e.w < MIN_BUTTON_W or e.w > MAX_BUTTON_W) and "size " .. math.floor(e.w + 0.5) end,
  function(e) return not e.dist and "no position" end,
  function(e, geo) return e.dist < geo.rim - RIM_TOLERANCE and "not on rim" end,
}

local function ExclusionReason(e, geo)
  for _, excluded in ipairs(EXCLUSIONS) do
    local why = excluded(e, geo)
    if why then return why end
  end
end

local function MeasureChild(c, geo)
  local e = { name = Plain(ProbeMethod(c, "GetName"), "string") or "?", type = Plain(ProbeMethod(c, "GetObjectType"), "string") or "?" }
  if ProbeMethod(c, "IsForbidden") then
    e.why = "forbidden"
    return e
  end
  local cx, cy = ProbeMethod(c, "GetCenter")
  cx, cy = Plain(cx, "number"), Plain(cy, "number")
  local cs = Plain(ProbeMethod(c, "GetEffectiveScale"), "number") or 1
  e.w = Plain(ProbeMethod(c, "GetWidth"), "number") or 0
  e.visible = Plain(ProbeMethod(c, "IsVisible")) and true or false
  if cx and cy then
    local dx, dy = (cx * cs - geo.x) / geo.scale, (cy * cs - geo.y) / geo.scale
    e.dist = math.sqrt(dx * dx + dy * dy)
    e.angle = math.deg(atan2(dy, dx)) % 360
  end
  e.why = ExclusionReason(e, geo)
  if not e.why then e.counted = true end
  return e
end

local function ScanChildren()
  local out = {}
  local children = { ProbeMethod(Minimap, "GetChildren") }
  local geo = MinimapGeometry()
  if not geo then return out end
  for _, c in ipairs(children) do
    if c ~= btn and type(c) == "table" then out[#out + 1] = MeasureChild(c, geo) end
  end
  return out
end

function GS:LauncherFreeAngle()
  local angles = {}
  for _, e in ipairs(ScanChildren()) do if e.counted then angles[#angles + 1] = e.angle end end
  if #angles == 0 then return ANGLE_WITHOUT_OTHER_BUTTONS end
  table.sort(angles)
  local bestGap, bestMid = -1, ANGLE_WITHOUT_OTHER_BUTTONS
  for i, a in ipairs(angles) do
    local gap = (angles[i + 1] or (angles[1] + 360)) - a
    if gap > bestGap then bestGap, bestMid = gap, (a + gap / 2) % 360 end
  end
  return bestMid
end

function GS:LauncherReplace()
  local s = self:LauncherSettings()
  s.dragged = nil
  s.angle = self:LauncherFreeAngle()
  UpdatePosition()
  return s.angle
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  local s = GS:LauncherSettings()
  s.angle = math.deg(atan2(py - my, px - mx)) % 360
  s.dragged = true
  UpdatePosition()
end

local function LauncherTooltip(tip)
  tip:AddLine(GS.OverviewL.TITLE)
  for _, name in ipairs(GS.moduleOrder) do
    local m = GS.modules[name]
    if m.loaded then
      local status = m.OverviewStatus and Plain(GS:Call(m.OverviewStatus, m), "string")
      tip:AddLine((m.title or name) .. ": " .. (status or L.NO_STATUS), 1, 1, 1)
    end
  end
  tip:AddLine(" ")
  tip:AddLine(L.LEFT, 0.8, 0.8, 0.8)
  local craft = GS:GetModule("Craft")
  if craft and craft.loaded and craft.Open then tip:AddLine(L.RIGHT, 0.8, 0.8, 0.8) end
  tip:AddLine(L.DRAG, 0.8, 0.8, 0.8)
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  LauncherTooltip(GameTooltip)
  GameTooltip:Show()
end

local function LauncherClick(button)
  if button == "RightButton" then
    local craft = GS:GetModule("Craft")
    if craft and craft.loaded and craft.Open then GS:Call(craft.Open, craft) return end
  end
  GS:Call(GS.ToggleOverview, GS)
end

local function Create()
  btn = CreateFrame("Button", "RavenquillExpeditionLauncher", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")
  btn:SetScript("OnClick", function(_, button) LauncherClick(button) end)
  btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
  btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)
  btn:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function() GS:Call(OnDragUpdate) end)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    icon:SetPoint("TOPLEFT", 7, -6)
  end)
  btn:SetScript("OnEnter", function(self) GS:Call(ShowTooltip, self) end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", UpdatePosition) end
  UpdatePosition()
end

function GS:UpdateLauncher()
  if not (self.db and Minimap) then return end
  if self:LauncherSettings().hide then
    if btn then btn:Hide() end
    return
  end
  if not btn then
    local ok, err = pcall(Create)
    if not ok then
      btn = nil
      GS:Trace("err", "launcher: no minimap button: " .. tostring(err))
      return
    end
  end
  btn:Show()
end

function GS:LauncherShown() return not self:LauncherSettings().hide end
function GS:SetLauncherShown(on)
  self:LauncherSettings().hide = (not on) or nil
  self:UpdateLauncher()
end
function ns.LauncherButton() return btn end

local function Whole(x) return x and ("%.0f"):format(x) or "-" end

local function ChildLine(e)
  return ("  %s %s  angle=%s dist=%s w=%s  %s"):format(e.counted and "[x]" or "[ ]", e.name,
    Whole(e.angle), Whole(e.dist), Whole(e.w), e.why or "")
end

function GS:LauncherDebug(P)
  P = P or function(line) GS.Print(nil, line) end
  local s = self:LauncherSettings()
  if not btn then
    P("Launcher button not created" .. (s.hide and " (hidden by its option)." or "."))
  else
    P(("Launcher: shown=%s angle=%.0f dragged=%s"):format(tostring(btn:IsShown()), s.angle or -1, tostring(s.dragged and true or false)))
  end
  local list = ScanChildren()
  table.sort(list, function(a, b) return (a.angle or -1) < (b.angle or -1) end)
  for _, e in ipairs(list) do
    if e.counted or e.type == "Button" then P(ChildLine(e)) end
  end
  P(("Largest free gap centre: %.0f."):format(self:LauncherFreeAngle()))
end

local function NeedsPlace(s)
  if s.dragged then return false end
  return s.angle == nil or s.angle == CRAFT_V01_DEFAULT_ANGLE
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    GS:Call(GS.UpdateLauncher, GS)
  else
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(PLACE_DELAY_AFTER_WORLD, function()
      if btn and NeedsPlace(GS:LauncherSettings()) then GS:Call(GS.LauncherReplace, GS) end
    end)
  end
end)
