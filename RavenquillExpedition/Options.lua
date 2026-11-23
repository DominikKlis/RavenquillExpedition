local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL

function ns.DialogBackdrop(f)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
end

function ns.DragToMove(f)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

local GOLD = { 1, 0.82, 0 }
ns.GOLD = GOLD

function ns.Fill(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetAllPoints()
  t:SetColorTexture(r, g, b, a)
  return t
end

function ns.Rule(parent, anchor, y)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
  t:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
  return t
end

function ns.Icon(parent, size, path)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if path then t:SetTexture(path) end
  return t
end

function ns.Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function ns.TextLink(parent, label, onClick)
  local text = ns.Text(parent, "GameFontDisable", "RIGHT")
  text:SetText(label)
  local link = CreateFrame("Button", nil, parent)
  link:SetAllPoints(text)
  link:SetScript("OnClick", onClick)
  link:SetScript("OnEnter", function() text:SetTextColor(1, 1, 1) end)
  link:SetScript("OnLeave", function() text:SetTextColor(0.5, 0.5, 0.5) end)
  link.text = text
  return link
end

function ns.Tip(frame, title, lines)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title, GOLD[1], GOLD[2], GOLD[3])
    for _, line in ipairs(lines and lines() or {}) do
      if line ~= "" then GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.SetAtlas(tex, atlas)
  local info = C_Texture and C_Texture.GetAtlasInfo and GS.SafeCall(C_Texture.GetAtlasInfo, atlas)
  if type(info) ~= "table" or type(tex.SetAtlas) ~= "function" then return false end
  return (pcall(tex.SetAtlas, tex, atlas))
end

local function AtlasOr(tex, atlas, r, g, b, a)
  if not ns.SetAtlas(tex, atlas) then tex:SetColorTexture(r, g, b, a) end
end

function ns.SetPortrait(f, icon)
  if type(f.SetPortraitToAsset) == "function" then pcall(f.SetPortraitToAsset, f, icon) end
end

function ns.SetWindowTitle(f, title)
  if type(f.SetTitle) == "function" then pcall(f.SetTitle, f, title) elseif f.fallbackTitle then f.fallbackTitle:SetText(title) end
end

function ns.PortraitWindow(name, title, icon)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
  if not (ok and f and type(f.SetTitle) == "function") then
    f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    ns.DialogBackdrop(f)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    f.fallbackTitle = ns.Text(f, "GameFontNormal", "CENTER")
    f.fallbackTitle:SetPoint("TOP", 0, -16)
  end
  if type(f.CloseButton) == "table" then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
  local art = f:CreateTexture(nil, "BACKGROUND", nil, -6)
  art:SetPoint("TOPLEFT", 2, -21)
  art:SetPoint("BOTTOMRIGHT", -2, 2)
  if ns.SetAtlas(art, "Profession-Background-Overview") then
    if type(f.Bg) == "table" and f.Bg.Hide then f.Bg:Hide() end
  else
    art:Hide()
  end
  ns.SetWindowTitle(f, title)
  ns.SetPortrait(f, icon)
  return f
end

local SLICE_X = { { "LEFT", 0 }, { "LEFT", 1 }, { "RIGHT", -1 } }
local SLICE_X_END = { { "LEFT", 1 }, { "RIGHT", -1 }, { "RIGHT", 0 } }
local SLICE_Y = { { "TOP", 0 }, { "TOP", -1 }, { "BOTTOM", 1 } }
local SLICE_Y_END = { { "TOP", -1 }, { "BOTTOM", 1 }, { "BOTTOM", 0 } }

local function SliceCoords(info, x0, x1, y0, y1)
  local du = (info.rightTexCoord - info.leftTexCoord) / info.width
  local dv = (info.bottomTexCoord - info.topTexCoord) / info.height
  return info.leftTexCoord + x0 * du, info.leftTexCoord + x1 * du, info.topTexCoord + y0 * dv, info.topTexCoord + y1 * dv
end

local function PlaceSlice(t, c, col, row, edge)
  local x0, x1, y0, y1 = SLICE_X[col], SLICE_X_END[col], SLICE_Y[row], SLICE_Y_END[row]
  t:SetPoint("TOPLEFT", c, y0[1] .. x0[1], x0[2] * edge, y0[2] * edge)
  t:SetPoint("BOTTOMRIGHT", c, y1[1] .. x1[1], x1[2] * edge, y1[2] * edge)
end

function ns.SlicedCard(parent, atlas, edge)
  local c = CreateFrame("Frame", nil, parent)
  local info = C_Texture and C_Texture.GetAtlasInfo and GS.SafeCall(C_Texture.GetAtlasInfo, atlas)
  local file = type(info) == "table" and (info.file or info.filename)
  if not (file and info.width and info.height) then
    ns.Fill(c, "BACKGROUND", 0, 0, 0, 0.4)
    return c
  end
  local xs, ys = { 0, edge, info.width - edge, info.width }, { 0, edge, info.height - edge, info.height }
  for row = 1, 3 do
    for col = 1, 3 do
      local t = c:CreateTexture(nil, "BACKGROUND")
      t:SetTexture(file)
      t:SetTexCoord(SliceCoords(info, xs[col], xs[col + 1], ys[row], ys[row + 1]))
      PlaceSlice(t, c, col, row, edge)
    end
  end
  return c
end

local SIDETAB_W, SIDETAB_H, SIDETAB_ART_H = 55, 55, 60

local function SideTabTexture(b, layer, atlas, r, g, bl, a)
  local t = b:CreateTexture(nil, layer)
  t:SetSize(SIDETAB_W, SIDETAB_ART_H)
  t:SetPoint("CENTER")
  AtlasOr(t, atlas, r, g, bl, a)
  return t
end

local function MaskIcon(b)
  local mask = b.CreateMaskTexture and b:CreateMaskTexture()
  if not mask then return end
  mask:SetSize(SIDETAB_W, SIDETAB_ART_H)
  mask:SetPoint("CENTER")
  if ns.SetAtlas(mask, "common-sidetab-mask") and b.icon.AddMaskTexture then b.icon:AddMaskTexture(mask) end
end

function ns.SideTab(f, prev, onClick)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(SIDETAB_W, SIDETAB_H)
  if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2) else b:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -60) end
  SideTabTexture(b, "BACKGROUND", "common-sidetab", 0, 0, 0, 0.6)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(50, 50)
  b.icon:SetPoint("CENTER", -4, 0)
  b.icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
  MaskIcon(b)
  b.selected = SideTabTexture(b, "OVERLAY", "common-sidetab-selected", GOLD[1], GOLD[2], GOLD[3], 0.3)
  SideTabTexture(b, "HIGHLIGHT", "common-sidetab-hover", 1, 1, 1, 0.15)
  b:SetScript("OnClick", onClick)
  ns.Tip(b, function() return b.title or "" end)
  return b
end

local copy
local function CopyBox()
  if copy then return copy end
  local f = CreateFrame("Frame", "RavenquillExpeditionCopyBox", UIParent, "BackdropTemplate")
  ns.DialogBackdrop(f)
  f:SetSize(560, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  ns.DragToMove(f)
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
  ns.WheelScroll(sf)
  ns.SetScrollPage(sf, eb)
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

local function RangeText(o, v)
  if not v then return "?" end
  if o.display then return GS:Call(o.display, v) or "?" end
  return (o.format or "%d"):format(v)
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
  val:SetWidth(o.valueWidth or 44)
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
    val:SetText(RangeText(o, v))
    local off = IsDisabled(o)
    if off or not v or v <= (o.min or -math.huge) then minus:Disable() else minus:Enable() end
    if off or not v or v >= (o.max or math.huge) then plus:Disable() else plus:Enable() end
    SetLabelEnabled(fs, not off)
  end, { minus = minus, plus = plus, value = val }
end

local function ButtonWidget(parent, o, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(220, 22)
  b:SetPoint("TOPLEFT", 10, y)
  b:SetText(o.label or "")
  b:SetScript("OnClick", function() onClick(b) end)
  Tooltip(b, o.label, o.tooltip)
  return 28, function() if IsDisabled(o) then b:Disable() else b:Enable() end end, b
end

local CONFIRM_SECONDS = 5

local function ConfirmedClick(o, refreshAll)
  return function(b)
    if o.confirm and not b.armed then
      b.armed = true
      b:SetText(o.confirm)
      C_Timer.After(CONFIRM_SECONDS, function() b.armed = nil; b:SetText(o.label or "") end)
      return
    end
    b.armed = nil
    b:SetText(o.label or "")
    GS:Call(o.func)
    refreshAll()
  end
end

function Build.button(parent, o, y, refreshAll)
  return ButtonWidget(parent, o, y, ConfirmedClick(o, refreshAll))
end

local NOTE_WIDTH, NOTE_GAP = 412, 6

function Build.note(parent, o, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 12, y - 2)
  fs:SetWidth(NOTE_WIDTH)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetText(o.label or "")
  return fs:GetStringHeight() + NOTE_GAP, function() SetLabelEnabled(fs, not IsDisabled(o)) end, fs
end

function Build.text(parent, o, y)
  return ButtonWidget(parent, o, y, function()
    local lines = GS:Call(o.lines)
    GS:ShowCopyBox(o.label, type(lines) == "table" and lines or {})
  end)
end

function ns.BuildPanel(parent, options)
  local p = CreateFrame("Frame", nil, parent)
  p:SetWidth(440)
  p.refreshers, p.controls = {}, {}
  local function refreshAll() for _, fn in ipairs(p.refreshers) do GS:Call(fn) end end
  p.refreshAll = refreshAll
  local y = 0
  for _, o in ipairs(options or {}) do
    local build = type(o) == "table" and Build[o.type]
    if build then
      local h, refresh, control = build(p, o, y, refreshAll)
      y = y - h
      p.refreshers[#p.refreshers + 1] = refresh
      p.controls[#p.controls + 1] = control or false
    end
  end
  if not options then
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    fs:SetPoint("TOPLEFT", 6, -6)
    fs:SetText(L.NO_OPTIONS)
    y = -30
  end
  p:SetHeight(-y + 10)
  p:Hide()
  return p
end

