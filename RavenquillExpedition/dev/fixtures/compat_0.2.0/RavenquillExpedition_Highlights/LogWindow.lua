-- Ravenquill Expedition: Highlights – a simple log window (/rq hl). Newest at the bottom, item links clickable.
-- Native template in pcall with a plain fallback (the pattern GuildCraftAdvisor uses on Forever).
local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local L = ns.L

local win

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
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end -- also works in combat
  end
  if f.SetTitle then
    pcall(f.SetTitle, f, L.TITLE)
  else
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, native and -5 or -16)
    title:SetText(L.TITLE)
  end
  tinsert(UISpecialFrames, "RavenquillExpeditionHighlightsFrame")

  local msg = CreateFrame("ScrollingMessageFrame", nil, f)
  msg:SetPoint("TOPLEFT", 16, -32)
  msg:SetPoint("BOTTOMRIGHT", -16, 32)
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

  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 18, 12)
  footer:SetPoint("BOTTOMRIGHT", -170, 12)
  footer:SetJustifyH("LEFT")
  f.footer = footer

  -- "Nur Highlights": hide the plain activity (same setting as in the options)
  local cb = CreateFrame("CheckButton", nil, f)
  cb:SetSize(22, 22)
  cb:SetPoint("BOTTOMRIGHT", -130, 6)
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

  f:SetScript("OnShow", function() GS:Call(H.Refresh, H) end)
  f:Hide()
  return f
end

local SHOW_MAX = 1500 -- lines handed to the frame (the newest)
local HL_MARK = "|cffffd100»|r "  -- a highlight (shared ones and guildies')
local ACT_MARK = "|cff555555·|r "  -- plain activity (only mine, never sent)

-- highlights + (unless "only highlights") this character's activity, merged by time
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

function H:Refresh()
  if not (win and win:IsShown() and self.db) then return end
  local list, nHL, nAct = self:LogLines()
  local m = win.msg
  m:Clear()
  win.onlyHL:SetChecked(self:Settings().logOnlyHighlights and true or false)
  if not list[1] then m:AddMessage(L.EMPTY, 0.7, 0.7, 0.7) end
  local lastDay
  for k = math.max(1, #list - SHOW_MAX + 1), #list do
    local e = list[k]
    local day = date("%Y-%m-%d", e.t)
    if day ~= lastDay then
      m:AddMessage(" ")
      m:AddMessage(date(GetLocale() == "deDE" and "%d.%m.%Y" or "%Y-%m-%d", e.t), 1, 0.82, 0)
      lastDay = day
    end
    local line = "|cff888888" .. date("%H:%M", e.t) .. "|r  " .. (e.act and ACT_MARK or HL_MARK) .. self:Format(e)
    if e.act then m:AddMessage(line, 0.75, 0.75, 0.75) else m:AddMessage(line) end
  end
  m:ScrollToBottom()
  win.footer:SetText(L.FOOTER:format(nHL, self:Settings().share and L.ON or L.OFF)
    .. (nAct > 0 and ("  ·  " .. L.FOOTER_ACT:format(nAct)) or "") .. "  ·  " .. (GS:GuildKey() or L.NO_GUILD))
end

-- many loot lines in a row: redraw once
function H:RefreshSoon()
  if self.refreshArmed or not (win and win:IsShown()) then return end
  self.refreshArmed = true
  C_Timer.After(0.5, function() self.refreshArmed = false; GS:Call(H.Refresh, H) end)
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
