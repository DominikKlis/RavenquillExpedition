local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local L = ns.L

local win, refreshArmed
local views = {}
local WINDOW_INSETS = { 16, -32, -16, 32 }
local PAGE_INSETS = { 4, -2, -4, 30 }

local function Chrome(f, native)
  f:SetSize(560, 420)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if native then
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
  end
  if f.SetTitle then
    pcall(f.SetTitle, f, L.TITLE)
  else
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, native and -5 or -16)
    title:SetText(L.TITLE)
  end
  tinsert(UISpecialFrames, "RavenquillExpeditionHighlightsFrame")
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

local function Footer(f, inPage)
  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", inPage and 6 or 18, inPage and 6 or 12)
  footer:SetPoint("BOTTOMRIGHT", -170, inPage and 6 or 12)
  footer:SetJustifyH("LEFT")
  f.footer = footer

  local cb = CreateFrame("CheckButton", nil, f)
  cb:SetSize(22, 22)
  cb:SetPoint("BOTTOMRIGHT", -130, inPage and 0 or 6)
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
  f.onlyHL = cb
end

local function CreateWindow()
  local ok, f = pcall(CreateFrame, "Frame", "RavenquillExpeditionHighlightsFrame", UIParent, "ButtonFrameTemplate")
  local native = ok and f
  if not native then
    f = CreateFrame("Frame", "RavenquillExpeditionHighlightsFrame", UIParent, "BackdropTemplate")
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  Chrome(f, native)
  MessageArea(f, WINDOW_INSETS)
  Footer(f, false)
  f:SetScript("OnShow", function() GS:Call(H.Refresh, H) end)
  views[#views + 1] = f
  f:Hide()
  return f
end

function H:BuildPage(parent)
  MessageArea(parent, PAGE_INSETS)
  Footer(parent, true)
  parent:SetScript("OnShow", function() GS:Call(H.Refresh, H) end)
  views[#views + 1] = parent
end

function H:RefreshPage() self:Refresh() end

local SHOW_MAX = 1500
local HL_MARK = "|cffffd100»|r "
local ACT_MARK = "|cff555555·|r "

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

local function LogMessages(self, list)
  local out, lastDay = {}, nil
  for k = math.max(1, #list - SHOW_MAX + 1), #list do
    local e = list[k]
    local day = date("%Y-%m-%d", e.t)
    if day ~= lastDay then
      out[#out + 1] = { text = " " }
      out[#out + 1] = { text = date(L.FMT_DAY, e.t), color = { 1, 0.82, 0 } }
      lastDay = day
    end
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

local function FooterText(self, nHL, nAct)
  local gkey = self:GuildKey()
  return L.FOOTER:format(nHL, self:Settings().share and L.ON or L.OFF)
    .. (nAct > 0 and ("  ·  " .. L.FOOTER_ACT:format(nAct)) or "") .. "  ·  " .. (gkey ~= "-" and gkey or L.NO_GUILD)
end

local function RenderLog(self, view, list, nHL, nAct)
  local m = view.msg
  local offset = m.GetScrollOffset and m:GetScrollOffset() or 0
  local messages = LogMessages(self, list)
  m:Clear()
  view.onlyHL:SetChecked(self:Settings().logOnlyHighlights and true or false)
  if not list[1] then m:AddMessage(self:EmptyText(), 0.7, 0.7, 0.7) end
  for _, line in ipairs(messages) do
    if line.color then m:AddMessage(line.text, line.color[1], line.color[2], line.color[3]) else m:AddMessage(line.text) end
  end
  KeepReadingPosition(m, offset, LinesAfter(messages, view.newest))
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
    if view:IsVisible() then RenderLog(self, view, list, nHL, nAct) end
  end
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
