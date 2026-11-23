local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local L = ns.L
local T = GS.NewLocale(ns.NewsLocales)

local win, refreshArmed
local views = {}
local WINDOW_NAV, PAGE_LOG = { 34, 14, reserve = 57, rule = 41, size = 13 }, { 4, -2, -4, 30 }
local SHADOW_RINGS, SHADOW_ALPHA = 10, 0.4
local INK_DARK, INK_FADED = { 0.04, 0.03, 0.02 }, { 0.663, 0.58, 0.455 }
local GRAIN_ALPHA = 0.5
local BOX = { outer = 2, inner = 1, gap = 3, hover = 0.08 }
local BOX_EDGES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT", tall = true },
  { "TOPRIGHT", "BOTTOMRIGHT", tall = true } }
local EMPTY_BUTTON, EMPTY_GAP = { 220, 22 }, 12
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
  b.underline:SetShown(enabled and b.hover or false)
end

function H.InkButton(parent, text, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size + 4, size + 8)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  H.SetFontSize(fs, size)
  fs:SetShadowOffset(0, 0)
  fs:SetPoint("CENTER")
  if b.SetFontString then b:SetFontString(fs) end
  local line = b:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(INK_DARK[1], INK_DARK[2], INK_DARK[3], 1)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
  line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -2)
  b.label, b.underline, b.restyle = fs, line, InkStyle
  b:SetText(text)
  b:SetWidth(math.ceil(GS.Plain(fs:GetStringWidth(), "number") or 0) + 4)
  b:SetScript("OnEnter", function() b.hover = true; InkStyle(b) end)
  b:SetScript("OnLeave", function() b.hover = false; InkStyle(b) end)
  InkStyle(b)
  return b
end

local function BoxInset(point, inset)
  return point:find("LEFT") and inset or -inset, point:find("TOP") and -inset or inset
end

local function BoxRule(b, inset, thickness)
  for _, edge in ipairs(BOX_EDGES) do
    local t = b:CreateTexture(nil, "BORDER")
    t:SetColorTexture(H.INK[1], H.INK[2], H.INK[3], 1)
    for i = 1, 2 do t:SetPoint(edge[i], b, edge[i], BoxInset(edge[i], inset)) end
    if edge.tall then t:SetWidth(thickness) else t:SetHeight(thickness) end
  end
end

function H.InkBox(b)
  BoxRule(b, 0, BOX.outer)
  BoxRule(b, BOX.outer + BOX.gap, BOX.inner)
  local hover = b:CreateTexture(nil, "BACKGROUND")
  hover:SetAllPoints()
  hover:SetColorTexture(H.INK[1], H.INK[2], H.INK[3], BOX.hover)
  hover:Hide()
  b:SetScript("OnEnter", function() hover:Show() end)
  b:SetScript("OnLeave", function() hover:Hide() end)
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

local function FooterRule(host, nav)
  local rule = host:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(H.INK[1], H.INK[2], H.INK[3], 1)
  rule:SetHeight(2)
  rule:SetPoint("BOTTOMLEFT", nav[1], nav.rule)
  rule:SetPoint("BOTTOMRIGHT", -nav[1], nav.rule)
  return rule
end

local function OpenChronicle(f)
  f:Hide()
  GS:ShowModulePage(H.name)
end

function H.SpreadNav(f)
  local nav, items, used = f.nav, { f.prev, f.issueLabel, f.next, f.chronicle }, 0
  f.issueLabel:SetWidth(math.ceil(GS.Plain(f.issueLabel:GetStringWidth(), "number") or 0) + 4)
  for _, item in ipairs(items) do used = used + (GS.Plain(item:GetWidth(), "number") or 0) end
  local x = nav[1]
  local gap = ((GS.Plain(f:GetWidth(), "number") or H.WINDOW_W) - 2 * nav[1] - used) / 3
  for _, item in ipairs(items) do
    item:ClearAllPoints()
    item:SetPoint("LEFT", f, "BOTTOMLEFT", x, nav[2] + (nav.size + 8) / 2)
    x = x + (GS.Plain(item:GetWidth(), "number") or 0) + gap
  end
end

function H.NavButtons(f, nav, ink)
  f.nav = nav
  f.prev = H.InkButton(ink, T.PREV, nav.size)
  f.next = H.InkButton(ink, T.NEXT, nav.size)
  f.chronicle = H.InkButton(ink, T.CHRONICLE, nav.size)
  f.issueLabel = ink:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  H.SetFontSize(f.issueLabel, nav.size)
  f.issueLabel:SetShadowOffset(0, 0)
  f.issueLabel:SetTextColor(H.INK[1], H.INK[2], H.INK[3])
  f.footerRule = FooterRule(ink, nav)
  H.SpreadNav(f)
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
  local close = H.InkButton(f.inkLayer, "×", 22)
  close:SetPoint("TOPRIGHT", -12, -6)
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

local function EmptyLog(f)
  local empty = CreateFrame("Frame", nil, f)
  empty:SetAllPoints(f.msg)
  local text = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT")
  text:SetPoint("TOPRIGHT")
  text:SetJustifyH("LEFT")
  text:SetTextColor(0.7, 0.7, 0.7)
  text:SetText(L.EMPTY)
  local tests = CreateFrame("Button", nil, empty, "UIPanelButtonTemplate")
  tests:SetSize(EMPTY_BUTTON[1], EMPTY_BUTTON[2])
  tests:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -EMPTY_GAP)
  tests:SetText(L.OPT_TEST)
  tests:SetScript("OnClick", function() GS:Call(H.AddTestEntries, H) end)
  empty.text, empty.tests = text, tests
  empty:Hide()
  f.empty = empty
end

function H.CheckBox(parent, label)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(22, 22)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  text:SetText(label)
  return cb, text
end

local function Footer(f)
  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 6, 6)
  footer:SetPoint("BOTTOMRIGHT", -170, 6)
  footer:SetJustifyH("LEFT")
  f.footer = footer

  local cb, cbText = H.CheckBox(f, L.LOG_ONLY_HL)
  cb:SetPoint("BOTTOMRIGHT", -130, 0)
  cb:SetScript("OnClick", function(self)
    H:Settings().logOnlyHighlights = self:GetChecked() and true or false
    GS:Call(H.Refresh, H)
  end)
  f.onlyHL, f.onlyHLText = cb, cbText
end

local function FirstUnseen(events)
  for _, e in ipairs(events) do if e.unseen then return e end end
end

function H:OpenLog(view)
  view.firstUnseen = self.db and FirstUnseen(self:Log())
  view.opening = true
  self:Refresh()
end

local function OpenPaper(view)
  view.issueDay = nil
  H:Refresh()
end

function H:AddView(view) views[#views + 1] = view end

local function CreateWindow()
  local f = CreateFrame("Frame", "RavenquillExpeditionHighlightsFrame", UIParent)
  Chrome(f)
  H:AttachPaper(f, WINDOW_NAV)
  CloseMark(f)
  f.fit = FitSheet
  f:SetScript("OnShow", function() GS:Call(OpenPaper, f) end)
  H:AddView(f)
  f:Hide()
  return f
end

function H:BuildPage(parent)
  MessageArea(parent, PAGE_LOG)
  EmptyLog(parent)
  Footer(parent)
  parent:SetScript("OnShow", function() GS:Call(H.OpenLog, H, parent) end)
  self:AddView(parent)
end

function H:RefreshPage() self:Refresh() end

local SHOW_MAX = 1500
local HL_MARK = "|cffffd100»|r "
local ACT_MARK = "|cff555555·|r "
local NEW_COLOR = { 0.25, 1, 0.4 }

function H:LogLines()
  local events = self:ShownLog()
  local all = (self.cdb and self.cdb.activity) or {}
  local act = self:Settings().logOnlyHighlights and {} or all
  local out, i, j = {}, 1, 1
  while events[i] or act[j] do
    local e, a = events[i], act[j]
    if a and (not e or a.t < e.t) then out[#out + 1] = a; j = j + 1
    else out[#out + 1] = e; i = i + 1 end
  end
  return out, #events, #act, #all - #act
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

local function HiddenText(hidden)
  return hidden == 1 and L.ONE_HIDDEN or L.N_HIDDEN:format(hidden)
end

local function RenderLog(self, view, list, hidden)
  local m = view.msg
  local offset = m.GetScrollOffset and m:GetScrollOffset() or 0
  local messages = LogMessages(self, list, view.firstUnseen)
  m:Clear()
  view.onlyHL:SetChecked(self:Settings().logOnlyHighlights and true or false)
  view.empty:SetShown(not list[1])
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
  view.footer:SetText(HiddenText(hidden))
  view.footer:SetShown(hidden > 0)
end

local function AnyViewShown()
  for _, view in ipairs(views) do if view:IsVisible() then return true end end
  return false
end

local function RenderView(self, view, list, hidden)
  if view.paper then self:RenderPaper(view) return true end
  if view.readiness then self:RenderRaid(view) return false end
  RenderLog(self, view, list, hidden)
  return true
end

function H:Refresh()
  if not (self.db and AnyViewShown()) then return end
  local list, _, _, hidden = self:LogLines()
  local read = false
  for _, view in ipairs(views) do
    if view:IsVisible() and RenderView(self, view, list, hidden) then read = true end
  end
  if read then for _, e in ipairs(self:Log()) do e.unseen = nil end end
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

function H:NewSinceLastLook()
  local n, newest = 0, nil
  for _, e in ipairs(self:Log()) do
    if e.unseen then n, newest = n + 1, e end
  end
  return n, newest
end

function H:OverviewHeadline()
  if not self.db then return end
  local n, newest = self:NewSinceLastLook()
  if n > 0 then return { line = L.OV_HEAD_NEW:format(n, newest.who), open = function() self:ShowWindow() end } end
  local events = self:ShownLog()
  local last = events[#events]
  return { line = last and L.OV_HEAD_QUIET:format(last.who) or L.OV_HEAD_EMPTY }
end
