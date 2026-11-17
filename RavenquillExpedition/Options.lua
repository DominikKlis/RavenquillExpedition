local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL

local copy
local function CopyBox()
  if copy then return copy end
  local f = CreateFrame("Frame", "RavenquillExpeditionCopyBox", UIParent, "BackdropTemplate")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
  f:SetSize(560, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "RavenquillExpeditionCopyBox")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", 0, -18)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", 0, 16)
  hint:SetText(L.COPY_HINT)
  local sf = CreateFrame("ScrollFrame", nil, f)
  sf:SetPoint("TOPLEFT", 20, -40)
  sf:SetPoint("BOTTOMRIGHT", -20, 34)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  eb:SetWidth(510)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.text or "") self:HighlightText() end end)
  sf:SetScrollChild(eb)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (eb:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)
  f.eb = eb
  f:Hide()
  copy = f
  return f
end

function GS:ShowCopyBox(title, lines)
  local f = CopyBox()
  f.title:SetText(title or "")
  f.text = table.concat(type(lines) == "table" and lines or { tostring(lines) }, "\n")
  f.eb:SetText(f.text)
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

local function Tooltip(frame, title, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Get(o) local v = GS:Call(o.get); return v end
local function IsDisabled(o) return o.disabled and GS:Call(o.disabled) and true or false end

local function SetLabelEnabled(fs, on)
  if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.5, 0.5, 0.5) end
end

local Build = {}

function Build.header(parent, o, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 4, y - 8)
  fs:SetText(o.label or "")
  return 30, function() end, fs
end

function Build.toggle(parent, o, y, refreshAll)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", 8, y)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(o.label or "")
  cb:SetScript("OnClick", function(self)
    GS:Call(o.set, self:GetChecked() and true or false)
    refreshAll()
  end)
  Tooltip(cb, o.label, o.tooltip)
  return 26, function()
    cb:SetChecked(Get(o) and true or false)
    local off = IsDisabled(o)
    if off then cb:Disable() else cb:Enable() end
    SetLabelEnabled(fs, not off)
  end, cb
end

function Build.range(parent, o, y, refreshAll)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 12, y - 5)
  fs:SetText(o.label or "")
  local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  plus:SetSize(26, 22)
  plus:SetPoint("TOPRIGHT", -8, y)
  plus:SetText("+")
  local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  val:SetPoint("RIGHT", plus, "LEFT", -6, 0)
  val:SetWidth(44)
  val:SetJustifyH("CENTER")
  local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  minus:SetSize(26, 22)
  minus:SetPoint("RIGHT", val, "LEFT", -6, 0)
  minus:SetText("-")
  fs:SetPoint("RIGHT", minus, "LEFT", -8, 0)
  fs:SetJustifyH("LEFT")
  local step = o.step or 1
  local function Change(dir)
    local v = tonumber(Get(o)) or o.min or 0
    v = v + dir * step
    v = math.floor(v / step + 0.5) * step
    v = math.max(o.min or v, math.min(o.max or v, v))
    GS:Call(o.set, v)
    refreshAll()
  end
  minus:SetScript("OnClick", function() Change(-1) end)
  plus:SetScript("OnClick", function() Change(1) end)
  Tooltip(minus, o.label, o.tooltip)
  Tooltip(plus, o.label, o.tooltip)
  return 28, function()
    local v = tonumber(Get(o))
    val:SetText(v and (o.format or "%d"):format(v) or "?")
    local off = IsDisabled(o)
    if off or not v or v <= (o.min or -math.huge) then minus:Disable() else minus:Enable() end
    if off or not v or v >= (o.max or math.huge) then plus:Disable() else plus:Enable() end
    SetLabelEnabled(fs, not off)
  end, { minus = minus, plus = plus }
end

local function ButtonWidget(parent, o, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(220, 22)
  b:SetPoint("TOPLEFT", 10, y)
  b:SetText(o.label or "")
  b:SetScript("OnClick", onClick)
  Tooltip(b, o.label, o.tooltip)
  return 28, function() if IsDisabled(o) then b:Disable() else b:Enable() end end, b
end

function Build.button(parent, o, y, refreshAll)
  return ButtonWidget(parent, o, y, function() GS:Call(o.func); refreshAll() end)
end

function Build.text(parent, o, y)
  return ButtonWidget(parent, o, y, function()
    local lines = GS:Call(o.lines)
    GS:ShowCopyBox(o.label, type(lines) == "table" and lines or {})
  end)
end

function ns.Panel(opt, mod)
  local p = opt.panels[mod.name]
  if p then return p end
  p = CreateFrame("Frame", nil, opt.scroll)
  p:SetWidth(440)
  p.refreshers, p.controls = {}, {}
  local function refreshAll() for _, fn in ipairs(p.refreshers) do GS:Call(fn) end end
  p.refreshAll = refreshAll
  local y = 0
  local list = type(mod.options) == "table" and mod.options or {}
  for _, o in ipairs(list) do
    local build = type(o) == "table" and Build[o.type]
    if build then
      local h, refresh, control = build(p, o, y, refreshAll)
      y = y - h
      p.refreshers[#p.refreshers + 1] = refresh
      p.controls[#p.controls + 1] = control or false
    end
  end
  if not list[1] then
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    fs:SetPoint("TOPLEFT", 6, -6)
    fs:SetText(L.NO_OPTIONS)
    y = -30
  end
  p:SetHeight(-y + 10)
  p:Hide()
  opt.panels[mod.name] = p
  return p
end

