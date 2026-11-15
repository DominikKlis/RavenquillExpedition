-- Ravenquill Expedition core: the suite's minimap button (the launcher). Left-click opens the /rq overview,
-- right-click the Craft Advisor window (when that module is loaded); the tooltip lists every module's status line
-- (mod:OverviewStatus()). Drag it around the minimap; until it is dragged it sits in the largest free gap between the
-- other addons' minimap buttons (placed 5 s after entering the world, when late addons have made theirs).
-- Settings: RavenquillExpeditionDB.launcher = { hide, angle, dragged }. The button used to be the Craft Advisor's own:
-- its minimapHide / minimapAngle / minimapDragged are copied once.
-- API: GS:LauncherShown() / GS:SetLauncherShown(on) / GS:LauncherReplace() -> angle / GS:LauncherDebug(P) / GS:LauncherFreeAngle()
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
GS.LauncherL = L

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local OLD_DEFAULT = 200  -- the Craft Advisor's v0.1 default: treated as "never placed"
local EMPTY_ANGLE = 225  -- no other buttons on the rim
local RIM_SLACK = 12     -- how far inside the rim a button may sit and still count
local MIN_W, MAX_W = 24, 40 -- size of a minimap button (map pins are smaller)
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local btn

-- RavenquillExpeditionDB.launcher, with the one-time copy of the Craft Advisor's settings
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
  local angle = math.rad(GS:LauncherSettings().angle or EMPTY_ANGLE)
  local r = Radius()
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

---------------------------------------------------------------------------
-- Other addons' buttons on the rim (client frames: every call probed)
---------------------------------------------------------------------------
local function Call(obj, method, ...)
  local fn = obj and SafeCall(function() return obj[method] end) -- even the lookup may raise on a forbidden frame
  if type(fn) ~= "function" then return end
  return SafeCall(fn, obj, ...)
end

-- { name, angle, dist, w, type, counted, why } for every Minimap child
local function ScanChildren()
  local out = {}
  local children = { Call(Minimap, "GetChildren") }
  local ms = Plain(Call(Minimap, "GetEffectiveScale"), "number") or 1
  local mx, my = Call(Minimap, "GetCenter")
  mx, my = Plain(mx, "number"), Plain(my, "number")
  if not (mx and my) then return out end
  mx, my = mx * ms, my * ms
  local rim = math.min(Plain(Call(Minimap, "GetWidth"), "number") or 140, Plain(Call(Minimap, "GetHeight"), "number") or 140) / 2
  for _, c in ipairs(children) do
    if c ~= btn and type(c) == "table" then
      local e = { name = Plain(Call(c, "GetName"), "string") or "?", type = Plain(Call(c, "GetObjectType"), "string") or "?" }
      out[#out + 1] = e
      if Call(c, "IsForbidden") then
        e.why = "forbidden"
      else
        local cx, cy = Call(c, "GetCenter")
        cx, cy = Plain(cx, "number"), Plain(cy, "number")
        local cs = Plain(Call(c, "GetEffectiveScale"), "number") or 1
        e.w = Plain(Call(c, "GetWidth"), "number") or 0
        e.visible = Plain(Call(c, "IsVisible")) and true or false
        if cx and cy then
          local dx, dy = (cx * cs - mx) / ms, (cy * cs - my) / ms
          e.dist = math.sqrt(dx * dx + dy * dy)
          e.angle = math.deg(atan2(dy, dx)) % 360
        end
        if e.type ~= "Button" then e.why = "not a button"
        elseif not e.visible then e.why = "hidden"
        elseif e.w < MIN_W or e.w > MAX_W then e.why = "size " .. math.floor(e.w + 0.5)
        elseif not e.dist then e.why = "no position"
        elseif e.dist < rim - RIM_SLACK then e.why = "not on rim"
        else e.counted = true end
      end
    end
  end
  return out
end

-- middle of the largest gap between the counted buttons' angles
function GS:LauncherFreeAngle()
  local angles = {}
  for _, e in ipairs(ScanChildren()) do if e.counted then angles[#angles + 1] = e.angle end end
  if #angles == 0 then return EMPTY_ANGLE end
  table.sort(angles)
  local bestGap, bestMid = -1, EMPTY_ANGLE
  for i, a in ipairs(angles) do
    local gap = (angles[i + 1] or (angles[1] + 360)) - a
    if gap > bestGap then bestGap, bestMid = gap, (a + gap / 2) % 360 end
  end
  return bestMid
end

-- forget a drag and move the button into the largest free gap; returns the new angle
function GS:LauncherReplace()
  local s = self:LauncherSettings()
  s.dragged = nil
  s.angle = self:LauncherFreeAngle()
  UpdatePosition()
  return s.angle
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
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

-- every module's status line (mod:OverviewStatus) in the tooltip
function GS:LauncherTooltip(tip)
  tip:AddLine(GS.OverviewL.TITLE)
  for _, name in ipairs(self.moduleOrder) do
    local m = self.modules[name]
    if m.loaded then
      local status = m.OverviewStatus and Plain(self:Call(m.OverviewStatus, m), "string")
      tip:AddLine((m.title or name) .. ": " .. (status or L.NO_STATUS), 1, 1, 1)
    end
  end
  tip:AddLine(" ")
  tip:AddLine(L.LEFT, 0.8, 0.8, 0.8)
  local craft = self:GetModule("Craft")
  if craft and craft.loaded and craft.Open then tip:AddLine(L.RIGHT, 0.8, 0.8, 0.8) end
  tip:AddLine(L.DRAG, 0.8, 0.8, 0.8)
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GS:LauncherTooltip(GameTooltip)
  GameTooltip:Show()
end

function GS:LauncherClick(button)
  if button == "RightButton" then
    local craft = self:GetModule("Craft")
    if craft and craft.loaded and craft.Open then self:Call(craft.Open, craft) return end
  end
  if self.ToggleOverview then self:Call(self.ToggleOverview, self) end
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
  btn:SetScript("OnClick", function(_, button) GS:LauncherClick(button) end)
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

-- shows or hides the button by the setting (made on first show)
function GS:UpdateLauncher()
  if not (self.db and Minimap) then return end
  if self:LauncherSettings().hide then
    if btn then btn:Hide() end
    return
  end
  if not btn then
    -- the button is client frame API only (probed like any client API): a client that lacks one of these methods
    -- gets no button rather than an error at every login
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
function GS:LauncherButton() return btn end

-- diagnostics: the button and every minimap child the free-gap search looked at; P(line), default chat
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
    if e.counted or e.type == "Button" then
      P(("  %s %s  angle=%s dist=%s w=%s  %s"):format(e.counted and "[x]" or "[ ]", e.name,
        e.angle and ("%.0f"):format(e.angle) or "-", e.dist and ("%.0f"):format(e.dist) or "-",
        e.w and ("%.0f"):format(e.w) or "-", e.why or ""))
    end
  end
  P(("Largest free gap centre: %.0f."):format(self:LauncherFreeAngle()))
end

local function NeedsPlace(s)
  if s.dragged then return false end
  return s.angle == nil or s.angle == OLD_DEFAULT
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    GS:Call(GS.UpdateLauncher, GS)
  else
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- other addons create their minimap buttons late: look for the free gap 5 s later
    C_Timer.After(5, function()
      if btn and NeedsPlace(GS:LauncherSettings()) then GS:Call(GS.LauncherReplace, GS) end
    end)
  end
end)
