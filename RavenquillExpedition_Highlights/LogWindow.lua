local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local L = ns.L

local win, refreshArmed
local views = {}
local WINDOW = { log = { 24, -36, -24, 40 }, paper = { 0, 0, 0, 0 }, nav = { 14, 6, ink = true, reserve = 30 } }
local PAGE = { log = { 4, -2, -4, 30 }, paper = { 4, -2, -4, 30 }, nav = { 4, 2 } }
local MODE_BUTTON_SPACE = 100
local SHADOW_RINGS, SHADOW_ALPHA = 10, 0.4
local LOG_PANEL = { 0.10, 0.08, 0.06, 0.94 }
H.WINDOW_W, H.WINDOW_H, H.WINDOW_SHARE = 900, 780, 0.9

local function Within(size, room)
  room = GS.Plain(room, "number")
  if room and room > 0 then return math.min(size, math.floor(room * H.WINDOW_SHARE)) end
  return size
end

local function WindowSize()
  local w, h = GS.SafeCall(UIParent.GetWidth, UIParent), GS.SafeCall(UIParent.GetHeight, UIParent)
  return Within(H.WINDOW_W, w), Within(H.WINDOW_H, h)
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

local function CloseMark(f)
  local close = H.InkButton(f.inkLayer, "×", 24, 20)
  close:SetPoint("TOPRIGHT", -6, -4)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
end

local function InkLog(f)
  local panel = f.msg:CreateTexture(nil, "BACKGROUND")
  panel:SetPoint("TOPLEFT", -8, 8)
  panel:SetPoint("BOTTOMRIGHT", 8, -8)
  panel:SetColorTexture(LOG_PANEL[1], LOG_PANEL[2], LOG_PANEL[3], LOG_PANEL[4])
  f.logPanel = panel
  f.footer:SetTextColor(H.INK_SOFT[1], H.INK_SOFT[2], H.INK_SOFT[3])
  f.onlyHLText:SetTextColor(H.INK[1], H.INK[2], H.INK[3])
  f.onlyHLText:SetShadowOffset(0, 0)
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

local function Footer(f, inPage, right)
  right = right or 0
  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", inPage and 6 or 18, inPage and 6 or 12)
  footer:SetPoint("BOTTOMRIGHT", -170 - right, inPage and 6 or 12)
  footer:SetJustifyH("LEFT")
  f.footer = footer

  local cb = CreateFrame("CheckButton", nil, f)
  cb:SetSize(22, 22)
  cb:SetPoint("BOTTOMRIGHT", -130 - right, inPage and 0 or 6)
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

local function ShowLog(view)
  view.firstUnseen = H.db and FirstUnseen(H:Log())
  view.opening = true
  H:Refresh()
end

local function OpenView(view)
  view.mode, view.issueDay = "paper", nil
  H:ApplyWindowMode(view)
  ShowLog(view)
end

local function Views(f, inPage)
  local layout = inPage and PAGE or WINDOW
  MessageArea(f, layout.log)
  Footer(f, inPage, MODE_BUTTON_SPACE)
  f.logWidgets = { f.msg, f.footer, f.onlyHL, f.onlyHLText }
  H:AttachPaper(f, layout.paper, layout.nav)
  f:SetScript("OnShow", function() GS:Call(OpenView, f) end)
  views[#views + 1] = f
end

local function CreateWindow()
  local f = CreateFrame("Frame", "RavenquillExpeditionHighlightsFrame", UIParent)
  Chrome(f)
  Views(f, false)
  CloseMark(f)
  InkLog(f)
  f:Hide()
  return f
end

function H:BuildPage(parent) Views(parent, true) end

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
    if view:IsVisible() and view.mode == "paper" then
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

function H:SetViewMode(view, mode)
  view.mode = mode
  if mode == "log" then view.opening = true end
  self:ApplyWindowMode(view)
  self:Refresh()
end

function H:SetWindowMode(mode)
  if win then self:SetViewMode(win, mode) end
end

function H:ShowWindow()
  if not win then win = CreateWindow() end
  win:Show()
  if win.Raise then win:Raise() end
end
