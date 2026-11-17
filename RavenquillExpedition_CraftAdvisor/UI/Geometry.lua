local _, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = P.SafeCall, P.MIN_W, P.MIN_H, P.DEFAULT_W, P.DEFAULT_H
local Guard, SetTip = P.Guard, P.SetTip

local function Num(v)
  if type(v) ~= "number" or GCA.IsSecret(v) or v ~= v then return nil end
  return v
end

local function ScreenSize()
  local w = UIParent and UIParent.GetWidth and Num(SafeCall(UIParent.GetWidth, UIParent))
  local h = UIParent and UIParent.GetHeight and Num(SafeCall(UIParent.GetHeight, UIParent))
  return (w and w > 0) and w or nil, (h and h > 0) and h or nil
end

function UI.ClampSize(w, h)
  local sw, sh = ScreenSize()
  w, h = Num(w) or DEFAULT_W, Num(h) or DEFAULT_H
  if sw then w = math.min(w, math.floor(sw)) end
  if sh then h = math.min(h, math.floor(sh)) end
  return math.max(MIN_W, math.floor(w + 0.5)), math.max(MIN_H, math.floor(h + 0.5))
end

function UI.ClampPos(left, top, w, h)
  left, top = Num(left), Num(top)
  if not (left and top) then return nil end
  local sw, sh = ScreenSize()
  if sw then left = math.max(0, math.min(left, sw - w)) end
  if sh then top = math.min(sh, math.max(top, h)) end
  return math.floor(left + 0.5), math.floor(top + 0.5)
end

local function SavedWindow()
  local s = GCA.db and GCA.db.settings
  local win = s and s.window
  if type(win) == "table" then return win end
end

function UI:RestoreGeometry()
  local f = self.frame
  local win = SavedWindow()
  local w, h = UI.ClampSize(win and win.w or DEFAULT_W, win and win.h or DEFAULT_H)
  f:SetSize(w, h)
  f:ClearAllPoints()
  local left, top
  if win then left, top = UI.ClampPos(win.left, win.top, w, h) end
  if left then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) else f:SetPoint("CENTER") end
  return w, h
end

function UI:SaveGeometry()
  local f = self.frame
  if not (f and GCA.db and GCA.db.settings) then return end
  local w, h = UI.ClampSize(f:GetWidth(), f:GetHeight())
  local win = { w = w, h = h }
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  win.left, win.top = UI.ClampPos(left, top, w, h)
  GCA:SetSetting("window", win)
  if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
  return win
end

local function PinTopLeft(f)
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  if not (left and top) then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function SetBounds(f)
  local sw, sh = ScreenSize()
  local maxW, maxH = math.max(MIN_W, math.floor(sw or 4096)), math.max(MIN_H, math.floor(sh or 4096))
  if f.SetResizeBounds and pcall(f.SetResizeBounds, f, MIN_W, MIN_H, maxW, maxH) then return "SetResizeBounds" end
  if f.SetMinResize and pcall(f.SetMinResize, f, MIN_W, MIN_H) then
    if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
    return "SetMinResize"
  end
  return nil
end
UI.SetBounds = SetBounds

function UI:StopSizing()
  local f = self.frame
  if not (f and f.isSizing) then return end
  f:StopMovingOrSizing()
  f.isSizing = false
  local w, h = f:GetWidth(), f:GetHeight()
  local cw, ch = UI.ClampSize(w, h)
  if cw ~= w or ch ~= h then f:SetSize(cw, ch) end
  self:Layout()
  self:SaveGeometry()
end

function UI:ResetSize()
  local f = self.frame
  if not f then return end
  PinTopLeft(f)
  f:SetSize(UI.ClampSize(DEFAULT_W, DEFAULT_H))
  self:Layout()
  self:SaveGeometry()
end

local GRIP_ART = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local function CreateResizeGrip(f)
  if not (f.SetResizable and f.StartSizing and pcall(f.SetResizable, f, true)) then return nil end
  UI.boundsVia = SetBounds(f)
  local g = CreateFrame("Button", nil, f)
  g:SetSize(16, 16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  if g.SetNormalTexture then g:SetNormalTexture(GRIP_ART .. "Up") end
  if g.SetHighlightTexture then g:SetHighlightTexture(GRIP_ART .. "Highlight") end
  if g.SetPushedTexture then g:SetPushedTexture(GRIP_ART .. "Down") end
  g:SetScript("OnMouseDown", Guard("resize grip", function(_, button)
    if button ~= "LeftButton" or f.isSizing then return end
    if f.isMoving then f:StopMovingOrSizing(); f.isMoving = false end
    UI.boundsVia = SetBounds(f)
    PinTopLeft(f)
    f.isSizing = true
    f:StartSizing("BOTTOMRIGHT")
  end))
  g:SetScript("OnMouseUp", Guard("resize grip", function(_, button)
    if button == "RightButton" and not f.isSizing then UI:ResetSize(); return end
    UI:StopSizing()
  end))
  SetTip(g, "resize grip", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(L.RESIZE_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.RESIZE_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  g:SetScript("OnLeave", GameTooltip_Hide)
  return g
end

UI.StopSizing = Guard("UI:StopSizing", UI.StopSizing)
P.Num = Num
P.CreateResizeGrip = CreateResizeGrip
