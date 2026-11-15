-- Ravenquill Expedition core: the overview window (/rq) and every module's options.
-- User decision 2026-11-14: all options live in this UI, not in chat commands. "/rq" opens the overview,
-- "/rq <key>" opens that module's options.
--
-- Home view: guild, sync state, guildies running Ravenquill, one row per Ravenquill addon (loaded modules and
-- known ones that are disabled / not installed), the latest highlights.
-- Options view: drawn from mod.options by Options.lua.
-- Other optional hooks: mod.icon, mod:Open(), mod:OverviewStatus(), mod:OverviewRecent(n). All calls go through GS:Call.
local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local L = GS.OverviewL


-- Ravenquill addons we know about, so a disabled or missing one still gets a row.
GS.KNOWN = {
  { module = "Highlights", addon = "RavenquillExpedition_Highlights", slash = "hl", icon = "Interface\\Icons\\INV_Misc_Note_01" },
  { module = "Map", addon = "RavenquillExpedition_Map", slash = "map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
  { module = "Craft", addon = "RavenquillExpedition_CraftAdvisor", slash = "craft", title = "Guild Craft Advisor",
    icon = "Interface\\Icons\\Trade_LeatherWorking" },
}

local function AddonState(name)
  local api = C_AddOns or {}
  if Plain(SafeCall(api.IsAddOnLoaded or IsAddOnLoaded, name)) then return "loaded" end
  local ok, _, title, _, _, reason = pcall(api.GetAddOnInfo or GetAddOnInfo, name)
  if not ok or Plain(title) == nil or Plain(reason) == "MISSING" then return "missing" end
  return "disabled"
end
GS.AddonState = AddonState

local function ModuleRow(mod, k)
  local row = { name = mod.name, title = mod.title or (k and k.title) or mod.name, icon = mod.icon or (k and k.icon)
    or "Interface\\Icons\\INV_Misc_QuestionMark", slash = "/rq " .. (mod.slash or mod.name:lower()), state = "loaded" }
  row.status = mod.OverviewStatus and GS:Call(mod.OverviewStatus, mod) or L.LOADED
  if type(row.status) ~= "string" then row.status = "" end
  if mod.Open then row.open = function() GS:Call(mod.Open, mod) end end
  if type(mod.options) == "table" and mod.options[1] then row.options = true end
  return row
end

-- The rows to show: { name, title, icon, status, slash, state, open, options }
function GS:OverviewRows()
  local rows, seen = {}, {}
  for _, k in ipairs(self.KNOWN) do
    local mod = k.module and self.modules[k.module]
    if mod then
      seen[k.module] = true
      rows[#rows + 1] = ModuleRow(mod, k)
    else
      local state = AddonState(k.addon)
      local row = { title = k.title or k.module, icon = k.icon, slash = "/rq " .. k.slash, state = state }
      if state == "loaded" then -- loaded, but not registered with the core (an older version)
        row.status = (k.legacyStatus and k.legacyStatus()) or L.LEGACY
        row.open = k.legacyOpen
      elseif state == "disabled" then row.status = L.ENABLE_HINT
      else row.status = L.MISSING end
      if type(row.status) ~= "string" then row.status = "" end
      rows[#rows + 1] = row
    end
  end
  for _, name in ipairs(self.moduleOrder) do -- modules we don't know yet (future ones)
    if not seen[name] then rows[#rows + 1] = ModuleRow(self.modules[name]) end
  end
  return rows
end

function GS:OverviewSyncLine()
  local st, state = self:CommState(), L.SYNC_OK
  local waiting = st.queued + st.chunks + st.inflight
  if self:InInstance() then state = L.SYNC_PAUSED
  elseif st.slow then state = L.SYNC_SLOW
  elseif st.sent == 0 then state = L.SYNC_IDLE end
  local line = L.SYNC:format(state)
  if st.sent > 0 or waiting > 0 then line = line .. "  ·  " .. L.SYNC_DETAIL:format(st.delivered, waiting) end
  return line
end

function GS:OverviewPeersLine()
  local total, online = 0, 0
  local now = self:Now()
  for key, t in pairs(self:Peers() or {}) do
    if now - t <= self.PEER_MAX_AGE and self.roster[key] then
      total = total + 1
      if self.roster[key].online then online = online + 1 end
    end
  end
  return L.PEERS:format(total, online)
end

-- Core diagnostics for the copy box (to paste to whoever debugs it).
function GS:DiagLines()
  local db = RavenquillExpeditionDB or {}
  local out = {
    "Ravenquill Expedition v" .. self.version .. "  build " .. tostring((select(4, GetBuildInfo()))),
    "player: " .. tostring(self:PlayerKey()) .. "  guild: " .. tostring(self:GuildKey()),
    "sync: " .. self:CommStatus():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
    "roster members: " .. (function() local n = 0; for _ in pairs(self.roster) do n = n + 1 end; return n end)(),
  }
  local peers = {}
  for k, t in pairs(self:Peers() or {}) do peers[#peers + 1] = k .. " (" .. date("%d.%m. %H:%M", t) .. ")" end
  table.sort(peers)
  out[#out + 1] = "peers: " .. (peers[1] and table.concat(peers, ", ") or "-")
  local names = {}
  for _, name in ipairs(self.moduleOrder) do names[#names + 1] = name .. "=" .. tostring(self.modules[name].addon) end
  out[#out + 1] = "modules: " .. table.concat(names, ", ")
  if db.lastError then
    out[#out + 1] = "last error: " .. date("%d.%m. %H:%M", db.lastError.t or 0) .. " " .. tostring(db.lastError.msg)
    if db.lastError.trace then out[#out + 1] = tostring(db.lastError.trace) end
  end
  return out
end


---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local win
local ROW_H, MAX_ROWS = 52, 6

local function Backdrop(f)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
end

local function BuildHome(f, top)
  local home = CreateFrame("Frame", nil, f)
  home:SetAllPoints()
  f.home = home
  home.guild = home:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  home.guild:SetPoint("TOPLEFT", 18, top)
  home.sync = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  home.sync:SetPoint("TOPLEFT", home.guild, "BOTTOMLEFT", 0, -4)
  home.sync:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  home.sync:SetJustifyH("LEFT")
  home.peers = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  home.peers:SetPoint("TOPLEFT", home.sync, "BOTTOMLEFT", 0, -2)

  local head = home:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  head:SetPoint("TOPLEFT", home.peers, "BOTTOMLEFT", 0, -10)
  head:SetText(L.MODULES)

  home.rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Frame", nil, home)
    r:SetHeight(ROW_H - 4)
    r:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(36, 36)
    r.icon:SetPoint("LEFT", 6, 0)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.cmd = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.cmd:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.status:SetPoint("RIGHT", r, "RIGHT", -176, 0)
    r.status:SetJustifyH("LEFT")
    if r.status.SetMaxLines then pcall(r.status.SetMaxLines, r.status, 2) end
    r.opt = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.opt:SetSize(80, 22)
    r.opt:SetPoint("RIGHT", -6, 0)
    r.opt:SetText(L.OPTIONS)
    r.button = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.button:SetSize(76, 22)
    r.button:SetPoint("RIGHT", r.opt, "LEFT", -4, 0)
    r.button:SetText(L.OPEN)
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.note:SetPoint("RIGHT", -10, 0)
    home.rows[i] = r
  end

  local recentHead = home:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  recentHead:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10 - MAX_ROWS * ROW_H)
  recentHead:SetText(L.RECENT)
  local msg = CreateFrame("ScrollingMessageFrame", nil, home)
  msg:SetPoint("TOPLEFT", recentHead, "BOTTOMLEFT", 0, -4)
  msg:SetPoint("BOTTOMRIGHT", -18, 34)
  msg:SetFontObject(GameFontHighlightSmall)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(50)
  msg:SetHyperlinksEnabled(true)
  msg:SetScript("OnHyperlinkClick", function(_, link, text, button) if SetItemRef then pcall(SetItemRef, link, text, button) end end)
  msg:SetScript("OnHyperlinkEnter", function(self, link)
    if type(link) == "string" and link:match("^item:") then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  msg:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  home.recent = msg

  local diag = CreateFrame("Button", nil, home, "UIPanelButtonTemplate")
  diag:SetSize(110, 22)
  diag:SetPoint("BOTTOMRIGHT", -16, 8)
  diag:SetText(L.DIAG)
  diag:SetScript("OnClick", function() GS:ShowCopyBox(L.TITLE .. " – " .. L.DIAG, GS:Call(GS.DiagLines, GS) or {}) end)
end

local function BuildOptionsView(f, top)
  local opt = CreateFrame("Frame", nil, f)
  opt:SetAllPoints()
  opt:Hide()
  f.optView = opt
  local back = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
  back:SetSize(90, 22)
  back:SetPoint("TOPLEFT", 14, top + 2)
  back:SetText(L.BACK)
  back:SetScript("OnClick", function() GS:ShowHome() end)
  opt.title = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  opt.title:SetPoint("LEFT", back, "RIGHT", 12, 0)
  local sf = CreateFrame("ScrollFrame", nil, opt)
  sf:SetPoint("TOPLEFT", 14, top - 30)
  sf:SetPoint("BOTTOMRIGHT", -16, 14)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local child = self:GetScrollChild()
    local max = math.max(0, ((child and child:GetHeight()) or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)
  opt.scroll = sf
  opt.panels = {}
end

local function CreateWindow()
  local ok, f = pcall(CreateFrame, "Frame", "RavenquillExpeditionOverview", UIParent, "ButtonFrameTemplate")
  local native = ok and f
  if not native then
    f = CreateFrame("Frame", "RavenquillExpeditionOverview", UIParent, "BackdropTemplate")
    Backdrop(f)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  f:SetSize(500, 170 + MAX_ROWS * ROW_H)
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
  if f.SetTitle then pcall(f.SetTitle, f, L.TITLE) else
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, native and -5 or -16)
    t:SetText(L.TITLE)
  end
  tinsert(UISpecialFrames, "RavenquillExpeditionOverview")
  local top = native and -30 or -40
  BuildHome(f, top)
  BuildOptionsView(f, top)
  f:SetScript("OnShow", function() GS:Call(GS.RefreshOverview, GS) end)
  f:Hide()
  return f
end

local function Panel(mod) return ns.Panel(win.optView, mod) end

function GS:ShowHome()
  if not win then win = CreateWindow() end
  win.optView:Hide()
  win.home:Show()
  self.optionsModule = nil
  if win:IsShown() then self:RefreshOverview() end
end

function GS:ShowModuleOptions(name)
  if not win then win = CreateWindow() end
  local mod = self.modules[name]
  if not mod then return self:ShowHome() end
  if not win:IsShown() then win:Show() end
  win.home:Hide()
  local opt = win.optView
  for _, p in pairs(opt.panels) do p:Hide() end
  local p = Panel(mod)
  opt.title:SetText(mod.title or name)
  opt.scroll:SetScrollChild(p)
  opt.scroll:SetVerticalScroll(0)
  p:Show()
  opt:Show()
  self.optionsModule = name
  p.refreshAll()
end

function GS:RefreshOverview()
  if not (win and win:IsShown()) then return end
  if self.optionsModule then
    local p = win.optView.panels[self.optionsModule]
    if p then p.refreshAll() end
    return
  end
  local home = win.home
  local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
  home.guild:SetText((g and ("<" .. g .. ">") or L.NO_GUILD) .. "  |cff888888v" .. self.version .. "|r")
  home.sync:SetText(self:OverviewSyncLine())
  home.peers:SetText(self:OverviewPeersLine())

  local rows = self:OverviewRows()
  for i, r in ipairs(home.rows) do
    local d = rows[i]
    if d then
      r:Show()
      r.icon:SetTexture(d.icon)
      r.icon:SetDesaturated(d.state ~= "loaded")
      r.title:SetText(d.title)
      r.cmd:SetText(d.slash)
      r.status:SetText(d.status)
      if d.state == "loaded" then
        r.note:Hide()
        if d.open then
          r.button:Show()
          r.button:SetScript("OnClick", function() d.open(); GS:Call(GS.RefreshOverview, GS) end)
        else r.button:Hide() end
        if d.options then
          r.opt:Show()
          r.opt:SetScript("OnClick", function() GS:ShowModuleOptions(d.name) end)
        else r.opt:Hide() end
      else
        r.button:Hide(); r.opt:Hide(); r.note:Show()
        r.note:SetText(d.state == "disabled" and L.DISABLED or d.state == "missing" and L.NOT_INSTALLED or "")
      end
    else
      r:Hide()
    end
  end

  local m = home.recent
  m:Clear()
  local lines
  for _, name in ipairs(self.moduleOrder) do
    local mod = self.modules[name]
    if mod.OverviewRecent then lines = self:Call(mod.OverviewRecent, mod, 8) break end
  end
  if type(lines) == "table" and lines[1] then
    for _, line in ipairs(lines) do m:AddMessage(line) end
  else
    m:AddMessage(L.NO_RECENT, 0.6, 0.6, 0.6)
  end
  if m.ScrollToBottom then m:ScrollToBottom() end
end

-- keeps the home view current while it is open (sync numbers, new highlights). One chain at most: closing and
-- reopening within 3 s used to start a second one.
local tickArmed = false
local function Tick()
  tickArmed = false
  if not (win and win:IsShown()) then return end
  if not GS.optionsModule then GS:Call(GS.RefreshOverview, GS) end
  tickArmed = true
  C_Timer.After(3, Tick)
end
local function StartTick()
  if tickArmed then return end
  tickArmed = true
  C_Timer.After(3, Tick)
end

function GS:ToggleOverview()
  if not win then win = CreateWindow() end
  if win:IsShown() and not self.optionsModule then win:Hide() return end
  self:ShowHome()
  if not win:IsShown() then win:Show(); StartTick() end
end

-- true while the /rq window is open; second value: the module whose options it shows (nil = home view)
function GS:OverviewShown()
  return (win and win:IsShown()) and true or false, self.optionsModule
end

function GS:OpenModule(name)
  local wasShown = win and win:IsShown()
  self:ShowModuleOptions(name)
  if not wasShown then StartTick() end
end

-- the AddOns compartment button (## AddonCompartmentFunc in the .toc) [U: compartment on Forever; GCA uses it too]
function RavenquillExpedition_OnCompartmentClick() GS:Call(GS.ToggleOverview, GS) end
