local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local L = ns.L
local T = GS.NewLocale(ns.NewsLocales)

local win, refreshArmed
local views = {}
local WINDOW_NAV, PAGE_LOG = { 32, 8, reserve = 26, rule = 34 }, { 4, -2, -4, 30 }
local SHADOW_RINGS, SHADOW_ALPHA = 10, 0.4
local INK_DARK, INK_FADED = { 0.04, 0.03, 0.02 }, { 0.62, 0.56, 0.46 }
local GRAIN_ALPHA = 0.5
H.WINDOW_W, H.WINDOW_H, H.WINDOW_SHARE, H.WINDOW_MIN_H = 900, 780, 0.9, 480

local function Within(size, room)
  room = GS.Plain(room, "number")
  if room and room > 0 then return math.min(size, math.floor(room * H.WINDOW_SHARE)) end
  return size
end

local function WindowSize()
  local w, h = GS.SafeCall(UIParent.GetWidth, UIParent), GS.SafeCall(UIParent.GetHeight, UIParent)
  return Within(H.WINDOW_W, w), Within(H.WINDOW_H, h)
end

local function InkStyle(b)
  local enabled = b:IsEnabled() and true or false
  local c = (not enabled and INK_FADED) or (b.hover and INK_DARK) or H.INK
  b.label:SetTextColor(c[1], c[2], c[3])
  b.underline:SetShown(enabled and (b.link or b.hover) or false)
end

local function Label(b, text)
  if not b.link then return b:SetText(text) end
  b:SetText(H.Upper(text))
  b:SetWidth(math.ceil(GS.Plain(b.label:GetStringWidth(), "number") or 0) + 4)
end

function H.InkButton(parent, text, size, link)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size + 4, size + 8)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  H.SetFontSize(fs, size)
  fs:SetShadowOffset(0, 0)
  fs:SetPoint("CENTER")
  if b.SetFontString then b:SetFontString(fs) end
  local line = b:CreateTexture(nil, "ARTWORK")
  local c = link and H.RULE or INK_DARK
  line:SetColorTexture(c[1], c[2], c[3], 1)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
  line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -2)
  b.label, b.underline, b.restyle, b.link = fs, line, InkStyle, link
  Label(b, text)
  b:SetScript("OnEnter", function() b.hover = true; InkStyle(b) end)
  b:SetScript("OnLeave", function() b.hover = false; InkStyle(b) end)
  InkStyle(b)
  return b
end

function H.SetEnabled(b, on)
  if on then b:Enable() else b:Disable() end
  if b.restyle then b.restyle(b) end
end

function H.InkLayer(f, paper)
  local layer = CreateFrame("Frame", nil, f)
  layer:SetAllPoints()
  layer:SetFrameLevel((GS.Plain(paper:GetFrameLevel(), "number") or 0) + 3)
  f.inkLayer = layer
  return layer
end

local function FileOK(path)
  if type(GetFileIDFromPath) ~= "function" then return true end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and GS.Plain(id) ~= nil
end

function H.PaperSheet(paper)
  local base = paper:CreateTexture(nil, "BACKGROUND", nil, -8)
  base:SetAllPoints()
  base:SetColorTexture(H.PAPER[1], H.PAPER[2], H.PAPER[3], 1)
  local grain = paper:CreateTexture(nil, "BACKGROUND", nil, -7)
  grain:SetAllPoints()
  local loaded = FileOK(H.PARCHMENT) and grain:SetTexture(H.PARCHMENT) ~= false
  local crop = H.PARCHMENT_CROP
  if loaded then
    grain:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
    grain:SetAlpha(GRAIN_ALPHA)
  end
  grain:SetShown(loaded)
  local vignette = paper:CreateTexture(nil, "BACKGROUND", nil, -6)
  vignette:SetAllPoints()
  vignette:SetShown(vignette:SetTexture(H.VIGNETTE) ~= false)
  paper.parchment = { base = base, texture = grain, vignette = vignette, source = loaded and "texture" or "color" }
end

local function FooterRules(host, nav)
  local rules = H.DoubleRule(host)
  rules.thin:SetPoint("BOTTOMLEFT", nav[1], nav.rule + 4)
  rules.thin:SetPoint("BOTTOMRIGHT", -nav[1], nav.rule + 4)
  rules.thick:SetPoint("BOTTOMLEFT", nav[1], nav.rule)
  rules.thick:SetPoint("BOTTOMRIGHT", -nav[1], nav.rule)
  return rules
end

local function OpenChronicle(f)
  f:Hide()
  GS:ShowModulePage(H.name)
end

function H.NavButtons(f, nav, ink)
  f.prev = H.InkButton(ink, T.PREV, 12, true)
  f.prev:SetPoint("BOTTOMLEFT", nav[1], nav[2])
  f.chronicle = H.InkButton(ink, T.CHRONICLE, 12, true)
  f.chronicle:SetPoint("BOTTOMRIGHT", -nav[1], nav[2])
  f.next = H.InkButton(ink, T.NEXT, 12, true)
  f.next:SetPoint("RIGHT", f.chronicle, "LEFT", -24, 0)
  f.issueLabel = ink:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.issueLabel:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
  f.issueLabel:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
  f.issueLabel:SetJustifyH("CENTER")
  f.issueLabel:SetTextColor(H.INK_SOFT[1], H.INK_SOFT[2], H.INK_SOFT[3])
  f.footerRules = FooterRules(ink, nav)
  f.prev:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, -1) end)
  f.next:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, 1) end)
  f.chronicle:SetScript("OnClick", function() GS:Call(OpenChronicle, f) end)
end

local function ShadowStrip(f, alpha, rel1, x1, y1, rel2, x2, y2)
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetColorTexture(0, 0, 0, alpha)
  t:SetPoint("TOPLEFT", f, rel1, x1, y1)
  t:SetPoint("BOTTOMRIGHT", f, rel2, x2, y2)
end

local function Shadow(f)
  f.shadow = SHADOW_RINGS
  for i = 1, SHADOW_RINGS do
    local a, o = SHADOW_ALPHA * (SHADOW_RINGS + 1 - i) / SHADOW_RINGS, i - 1
    ShadowStrip(f, a, "TOPLEFT", -i, i, "TOPRIGHT", i, o)
    ShadowStrip(f, a, "BOTTOMLEFT", -i, -o, "BOTTOMRIGHT", i, -i)
    ShadowStrip(f, a, "TOPLEFT", -i, o, "BOTTOMLEFT", -o, -o)
    ShadowStrip(f, a, "TOPRIGHT", o, o, "BOTTOMRIGHT", i, -o)
  end
end

local function Chrome(f)
  f:SetSize(WindowSize())
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  Shadow(f)
  H.PaperSheet(f)
  tinsert(UISpecialFrames, "RavenquillExpeditionHighlightsFrame")
end

local function FitSheet(f)
  local w, full = WindowSize()
  f:SetSize(w, full)
  f.paper.room = full
  local used, shape = H.FlowPaper(f.paper, w, full)
  local h = math.min(full, math.max(H.WINDOW_MIN_H, math.ceil(used)))
  if h >= full then return end
  f:SetHeight(h)
  local _, again = H.FlowPaper(f.paper, w, h)
  if again ~= shape then
    f:SetHeight(full)
    H.FlowPaper(f.paper, w, full)
  end
end

local function CloseMark(f)
  local close = H.InkButton(f.inkLayer, "×", 20)
  close:SetPoint("TOPRIGHT", -6, -4)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
end

local function MessageArea(f, insets)
  local msg = CreateFrame("ScrollingMessageFrame", nil, f)
  msg:SetPoint("TOPLEFT", insets[1], insets[2])
  msg:SetPoint("BOTTOMRIGHT", insets[3], insets[4])
  msg:SetFontObject(GameFontHighlightSmall)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(2000)
  if msg.SetIndentedWordWrap then pcall(msg.SetIndentedWordWrap, msg, true) end
  msg:SetHyperlinksEnabled(true)
  msg:SetScript("OnHyperlinkClick", function(_, link, text, button)
    if SetItemRef then pcall(SetItemRef, link, text, button) end
  end)
  msg:SetScript("OnHyperlinkEnter", function(self, link)
    if type(link) == "string" and link:match("^item:") then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  msg:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  msg:EnableMouseWheel(true)
  msg:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
      if IsShiftKeyDown() then self:ScrollToTop() else for _ = 1, 3 do self:ScrollUp() end end
    else
      if IsShiftKeyDown() then self:ScrollToBottom() else for _ = 1, 3 do self:ScrollDown() end end
    end
  end)
  f.msg = msg
end

local function Footer(f)
  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 6, 6)
  footer:SetPoint("BOTTOMRIGHT", -170, 6)
  footer:SetJustifyH("LEFT")
  f.footer = footer

  local cb = CreateFrame("CheckButton", nil, f)
  cb:SetSize(22, 22)
  cb:SetPoint("BOTTOMRIGHT", -130, 0)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  local cbText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbText:SetText(L.LOG_ONLY_HL)
  cb:SetScript("OnClick", function(self)
    H:Settings().logOnlyHighlights = self:GetChecked() and true or false
    GS:Call(H.Refresh, H)
  end)
  f.onlyHL, f.onlyHLText = cb, cbText
end

local function FirstUnseen(events)
  for _, e in ipairs(events) do if e.unseen then return e end end
end

local function OpenLog(view)
  view.firstUnseen = H.db and FirstUnseen(H:Log())
  view.opening = true
  H:Refresh()
end

local function OpenPaper(view)
  view.issueDay = nil
  H:Refresh()
end

local function CreateWindow()
  local f = CreateFrame("Frame", "RavenquillExpeditionHighlightsFrame", UIParent)
  Chrome(f)
  H:AttachPaper(f, WINDOW_NAV)
  CloseMark(f)
  f.fit = FitSheet
  f:SetScript("OnShow", function() GS:Call(OpenPaper, f) end)
  views[#views + 1] = f
  f:Hide()
  return f
end

function H:BuildPage(parent)
  MessageArea(parent, PAGE_LOG)
  Footer(parent)
  parent:SetScript("OnShow", function() GS:Call(OpenLog, parent) end)
  views[#views + 1] = parent
end

function H:RefreshPage() self:Refresh() end

local SHOW_MAX = 1500
local HL_MARK = "|cffffd100»|r "
local ACT_MARK = "|cff555555·|r "
local NEW_COLOR = { 0.25, 1, 0.4 }

function H:LogLines()
  local events = self:Log()
  local act = (not self:Settings().logOnlyHighlights and self.cdb and self.cdb.activity) or {}
  local out, i, j = {}, 1, 1
  while events[i] or act[j] do
    local e, a = events[i], act[j]
    if a and (not e or a.t < e.t) then out[#out + 1] = a; j = j + 1
    else out[#out + 1] = e; i = i + 1 end
  end
  return out, #events, #act
end

local function LogMessages(self, list, firstUnseen)
  local out, lastDay = {}, nil
  for k = math.max(1, #list - SHOW_MAX + 1), #list do
    local e = list[k]
    local day = date("%Y-%m-%d", e.t)
    if day ~= lastDay then
      out[#out + 1] = { text = " " }
      out[#out + 1] = { text = date(L.FMT_DAY, e.t), color = { 1, 0.82, 0 } }
      lastDay = day
    end
    if e == firstUnseen then out[#out + 1] = { text = L.LOG_NEW, color = NEW_COLOR } end
    local line = "|cff888888" .. date("%H:%M", e.t) .. "|r  " .. (e.act and ACT_MARK or HL_MARK) .. self:Format(e)
    out[#out + 1] = { text = line, color = e.act and { 0.75, 0.75, 0.75 } or nil, entry = e }
  end
  return out
end

local function LinesAfter(messages, entry)
  if not entry then return nil end
  for i = #messages, 1, -1 do
    if messages[i].entry == entry then return #messages - i end
  end
end

local function KeepReadingPosition(m, offset, newLines)
  if offset > 0 and newLines and m.SetScrollOffset then
    m:SetScrollOffset(offset + newLines)
  else
    m:ScrollToBottom()
  end
end

local function ScrollToFirstNew(m, messages, entry)
  local below = LinesAfter(messages, entry)
  local visible = m.GetNumVisibleLines and m:GetNumVisibleLines()
  m:ScrollToBottom()
  if below and visible and visible > 1 and m.SetScrollOffset and below + 2 > visible then
    m:SetScrollOffset(below + 2 - visible)
  end
end

local function FooterText(self, nHL, nAct)
  return L.FOOTER:format(nHL, self:Settings().share and L.ON or L.OFF)
    .. (nAct > 0 and ("  ·  " .. L.FOOTER_ACT:format(nAct)) or "")
end

local function RenderLog(self, view, list, nHL, nAct)
  local m = view.msg
  local offset = m.GetScrollOffset and m:GetScrollOffset() or 0
  local messages = LogMessages(self, list, view.firstUnseen)
  m:Clear()
  view.onlyHL:SetChecked(self:Settings().logOnlyHighlights and true or false)
  if not list[1] then m:AddMessage(L.EMPTY, 0.7, 0.7, 0.7) end
  for _, line in ipairs(messages) do
    if line.color then m:AddMessage(line.text, line.color[1], line.color[2], line.color[3]) else m:AddMessage(line.text) end
  end
  if view.opening and view.firstUnseen then
    ScrollToFirstNew(m, messages, view.firstUnseen)
  else
    KeepReadingPosition(m, offset, LinesAfter(messages, view.newest))
  end
  view.opening = nil
  view.newest = list[#list]
  view.footer:SetText(FooterText(self, nHL, nAct))
end

local function AnyViewShown()
  for _, view in ipairs(views) do if view:IsVisible() then return true end end
  return false
end

function H:Refresh()
  if not (self.db and AnyViewShown()) then return end
  local list, nHL, nAct = self:LogLines()
  for _, view in ipairs(views) do
    if view:IsVisible() and view.paper then
      self:RenderPaper(view)
    elseif view:IsVisible() then
      RenderLog(self, view, list, nHL, nAct)
    end
  end
  for _, e in ipairs(self:Log()) do e.unseen = nil end
end

function H:RefreshSoon()
  if refreshArmed or not AnyViewShown() then return end
  refreshArmed = true
  C_Timer.After(0.5, function() refreshArmed = false; GS:Call(H.Refresh, H) end)
end

function H:ToggleWindow()
  if not win then win = CreateWindow() end
  if win:IsShown() then win:Hide() else win:Show() end
end

function H:ShowWindow()
  if not win then win = CreateWindow() end
  win:Show()
  if win.Raise then win:Raise() end
end
