local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local L = GS.OverviewL

local KNOWN_ADDONS = {
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

local function TitleAndIcon(mod, k)
  k = k or {}
  return mod.title or k.title or mod.name, mod.icon or k.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ModuleRow(mod, k)
  local title, icon = TitleAndIcon(mod, k)
  local row = { name = mod.name, title = title, icon = icon, slash = "/rq " .. ns.SlashWord(mod), state = "loaded" }
  row.status = mod.OverviewStatus and GS:Call(mod.OverviewStatus, mod) or L.LOADED
  if type(row.status) ~= "string" then row.status = "" end
  if mod.Open then row.open = function() GS:Call(mod.Open, mod) end end
  row.openLabel = mod.openLabel
  if ns.ModuleOptions(mod) then row.options = true end
  if type(mod.BuildPage) == "function" then row.page = true end
  return row
end

local ADDON_WITHOUT_MODULE = {
  loaded = { status = "LEGACY" },
  disabled = { status = "ENABLE_HINT", note = "DISABLED" },
  missing = { status = "MISSING", note = "NOT_INSTALLED" },
}

local function AddonRow(k)
  local state = AddonState(k.addon)
  local look = ADDON_WITHOUT_MODULE[state]
  return { title = k.title or k.module, icon = k.icon, slash = "/rq " .. k.slash, state = state,
    status = L[look.status], note = look.note and L[look.note] }
end

function GS:OverviewRows()
  local rows, seen = {}, {}
  for _, k in ipairs(KNOWN_ADDONS) do
    local mod = self.modules[k.module]
    seen[k.module] = true
    rows[#rows + 1] = mod and ModuleRow(mod, k) or AddonRow(k)
  end
  for _, name in ipairs(self.moduleOrder) do
    if not seen[name] then rows[#rows + 1] = ModuleRow(self.modules[name]) end
  end
  return rows
end

local SYNC_STATES = {
  ok = { label = "SYNC_OK" }, paused = { label = "SYNC_PAUSED" }, slow = { label = "SYNC_SLOW" }, idle = { label = "SYNC_IDLE" },
}

function GS:OverviewSyncState()
  local st = self:CommState()
  if self:InInstance() then return "paused" end
  if st.slow then return "slow" end
  if st.sent == 0 then return "idle" end
  return "ok"
end

function GS:OverviewSyncLine()
  local st = self:CommState()
  local waiting = st.queued + st.chunks + st.inflight
  local line = L.SYNC:format(L[SYNC_STATES[self:OverviewSyncState()].label])
  if st.sent > 0 or waiting > 0 then line = line .. "  ·  " .. L.SYNC_DETAIL:format(st.delivered, waiting) end
  return line
end

function GS:OverviewPeersLine() return L.PEERS:format(ns.PeersOnRoster()) end

local function PlainText(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function PeerList(peers)
  local out = {}
  for k, t in pairs(peers or {}) do out[#out + 1] = k .. " (" .. date("%d.%m. %H:%M", t) .. ")" end
  table.sort(out)
  return out[1] and table.concat(out, ", ") or "-"
end

local function AppendLastError(out, e)
  if not e then return end
  out[#out + 1] = "last error: " .. date("%d.%m. %H:%M", e.t or 0) .. " " .. tostring(e.msg)
  if e.trace then out[#out + 1] = tostring(e.trace) end
end

function GS:DiagLines()
  local out = {
    "Ravenquill Expedition v" .. self.version .. "  build " .. tostring((select(4, GetBuildInfo()))),
    "player: " .. tostring(self:PlayerKey()) .. "  guild: " .. tostring(self:GuildKey()),
    "sync: " .. PlainText(self:CommStatus()),
    "roster members: " .. (function() local n = 0; for _ in pairs(self.roster) do n = n + 1 end; return n end)(),
  }
  out[#out + 1] = "peers: " .. PeerList(self:Peers())
  local names = {}
  for _, name in ipairs(self.moduleOrder) do names[#names + 1] = name .. "=" .. tostring(self.modules[name].addon) end
  out[#out + 1] = "modules: " .. table.concat(names, ", ")
  AppendLastError(out, (self.db or {}).lastError)
  out[#out + 1] = ""
  out[#out + 1] = "== minimap button"
  self:Call(self.LauncherDebug, self, function(line) out[#out + 1] = PlainText(line) end)
  for _, name in ipairs(self.moduleOrder) do self:AppendModuleDiagnostics(out, self.modules[name]) end
  return out
end

function GS:AppendModuleDiagnostics(out, mod)
  if not mod.OverviewDiagnostics then return end
  local lines = self:Call(mod.OverviewDiagnostics, mod)
  if type(lines) ~= "table" then return end
  out[#out + 1] = ""
  out[#out + 1] = "== " .. tostring(mod.title or mod.name)
  for _, line in ipairs(lines) do out[#out + 1] = tostring(line) end
end


local win
local WIDTH, HEIGHT, MAX_TABS = 673, 594, 7
local SUITE_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local WIDE_CARD, WIDE_W, WIDE_H = "Profession-overview-Card", 664, 142
local CARD_EDGE = 24
local Text = ns.Text

local function OpenPage(page)
  if page == "home" then GS:ShowHome() else GS:ShowModulePage(page) end
end

local function BuildTabs(f)
  f.tabs = {}
  local prev
  for i = 1, MAX_TABS do
    prev = ns.SideTab(f, prev, function(self) OpenPage(self.page) end)
    local tab = prev
    ns.Tip(tab, function() return tab.title or "" end, function() return { tab.status } end)
    f.tabs[i] = prev
  end
end

local function BuildGuildCard(home)
  local card = ns.Card(home, WIDE_CARD, WIDE_W, WIDE_H)
  card:SetPoint("TOPLEFT", 5, -41)
  home.guild = Text(card, "GameFontNormal")
  home.guild:SetPoint("TOPLEFT", 20, -24)
  home.version = Text(card, "GameFontDisableSmall", "RIGHT")
  home.version:SetPoint("TOPRIGHT", -24, -26)
  home.syncEntry = ns.IconEntry(card)
  home.syncEntry:SetPoint("TOPLEFT", 17, -52)
  home.syncEntry.icon:SetTexture(SUITE_ICON)
  home.syncEntry.name:SetText(L.SYNC_TITLE)
  home.sync = home.syncEntry.sub
  ns.Tip(home.syncEntry, L.SYNC_TITLE, function() return { GS:OverviewSyncLine(), GS:OverviewPeersLine() } end)
  home.peersBar = ns.ProgressBar(card, 441)
  home.peersBar:SetPoint("RIGHT", -40, 0)
  home.options = ns.BuildPanel(card, {
    { type = "toggle", label = L.SHOW_LAUNCHER,
      get = function() return GS:LauncherShown() end, set = function(on) GS:SetLauncherShown(on) end },
  })
  home.options:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 10, 38)
  home.options:Show()
  local diag = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  diag:SetSize(120, 22)
  diag:SetPoint("BOTTOMRIGHT", -40, 14)
  diag:SetText(L.DIAG)
  diag:SetScript("OnClick", function() GS:ShowCopyBox(L.TITLE .. " – " .. L.DIAG, GS:Call(GS.DiagLines, GS) or {}) end)
  home.replace = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  home.replace:SetSize(190, 22)
  home.replace:SetPoint("RIGHT", diag, "LEFT", -8, 0)
  home.replace:SetText(L.REPLACE_LAUNCHER)
  home.replace:SetScript("OnClick", function() GS.Print(nil, L.LAUNCHER_MOVED:format(GS:LauncherReplace() or 0)) end)
  return card
end

local function BuildRecentCard(home, above)
  local card = ns.SlicedCard(home, WIDE_CARD, CARD_EDGE)
  card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 5)
  card:SetPoint("BOTTOMRIGHT", -4, 5)
  home.recentHead = Text(card, "GameFontNormal")
  home.recentHead:SetPoint("TOPLEFT", 20, -24)
  home.recentHead:SetText(L.RECENT)
  local msg = CreateFrame("ScrollingMessageFrame", nil, card)
  msg:SetPoint("TOPLEFT", 20, -44)
  msg:SetPoint("BOTTOMRIGHT", -24, 16)
  msg:SetFontObject(GameFontHighlightSmall)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(100)
  msg:SetHyperlinksEnabled(true)
  msg:SetScript("OnHyperlinkClick", function(_, link, text, button) if SetItemRef then pcall(SetItemRef, link, text, button) end end)
  msg:SetScript("OnHyperlinkEnter", ns.ShowItemTooltip)
  msg:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  msg:EnableMouseWheel(true)
  msg:SetScript("OnMouseWheel", ns.WheelLines)
  home.recent = msg
  return card
end

local function BuildHome(f)
  local home = CreateFrame("Frame", nil, f)
  home:SetAllPoints()
  BuildRecentCard(home, BuildGuildCard(home))
  return home
end

local function BuildOptionsView(f)
  local opt = CreateFrame("Frame", nil, f)
  opt:SetAllPoints()
  opt:Hide()
  local inset = ns.SlicedCard(opt, WIDE_CARD, CARD_EDGE)
  inset:SetPoint("TOPLEFT", 5, -41)
  inset:SetPoint("BOTTOMRIGHT", -4, 5)
  opt.title = Text(inset, "GameFontNormal")
  opt.title:SetPoint("TOPLEFT", 20, -18)
  opt.status = Text(inset, "GameFontHighlightSmall")
  opt.status:SetPoint("TOPLEFT", opt.title, "BOTTOMLEFT", 0, -4)
  opt.status:SetPoint("RIGHT", inset, "RIGHT", -60, 0)
  opt.status:SetTextColor(0.8, 0.8, 0.8)
  opt.gear = ns.SmallIconButton(inset, 26)
  opt.gear:SetPoint("TOPRIGHT", -22, -16)
  opt.gear.icon:SetTexture(GEAR_ICON)
  ns.Tip(opt.gear, L.SETTINGS)
  opt.openWindow = ns.SmallIconButton(inset, 26)
  opt.openWindow:SetPoint("TOPRIGHT", -22, -16)
  ns.Tip(opt.openWindow, function() return opt.openWindow.label or "" end)
  local line = ns.Rule(inset, opt.title, -30)
  opt.body = CreateFrame("Frame", nil, inset)
  opt.body:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -4, -8)
  opt.body:SetPoint("BOTTOMRIGHT", -16, 10)
  local sf = CreateFrame("ScrollFrame", nil, opt.body)
  sf:SetAllPoints()
  ns.WheelScroll(sf)
  opt.scroll = sf
  opt.panels, opt.pages = {}, {}
  return opt
end

local function CreateWindow()
  local f = ns.PortraitWindow("RavenquillExpeditionOverview", L.TITLE, SUITE_ICON)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  ns.DragToMove(f)
  tinsert(UISpecialFrames, "RavenquillExpeditionOverview")
  BuildTabs(f)
  f.home = BuildHome(f)
  f.optView = BuildOptionsView(f)
  f:SetScript("OnShow", function() GS:Call(GS.RefreshOverview, GS) end)
  f:Hide()
  return f
end

local function TabItems(rows)
  local items = { { page = "home", title = L.OVERVIEW, icon = SUITE_ICON, status = GS:OverviewPeersLine() } }
  for _, d in ipairs(rows) do
    if d.options or d.page then items[#items + 1] = { page = d.name, title = d.title, icon = d.icon, status = d.status } end
  end
  return items
end

local function RenderTabs(f, rows, current)
  local items = TabItems(rows)
  for i, tab in ipairs(f.tabs) do
    local it = items[i]
    if it then
      tab.page, tab.title, tab.status = it.page, it.title, it.status
      tab.icon:SetTexture(it.icon)
      tab.selected:SetShown(it.page == current)
      tab.isSelected = it.page == current
      tab:Show()
      if it.page == current then
        ns.SetWindowTitle(f, it.page == "home" and L.TITLE or it.title)
        ns.SetPortrait(f, it.icon)
      end
    else
      tab:Hide()
    end
  end
end

local function RowFor(rows, name)
  for _, d in ipairs(rows) do if d.name == name then return d end end
end

local function RenderGear(gear, d, settings)
  gear:SetShown((d.page and d.options) and true or false)
  gear:SetAlpha(settings and 0.5 or 1)
  gear:SetScript("OnClick", function() if not GS.moduleSettings then GS:ShowModuleOptions(d.name) end end)
end

local function RenderModuleHeader(opt, d, settings)
  opt.title:SetText(d.title)
  opt.status:SetText(d.status)
  RenderGear(opt.gear, d, settings)
  local openWindow = opt.openWindow
  local windowOnly = not d.page and d.open
  openWindow:SetShown(windowOnly and true or false)
  if windowOnly then
    openWindow.icon:SetTexture(d.icon)
    openWindow.label = d.openLabel or L.OPEN
    openWindow:SetScript("OnClick", d.open)
  end
end

local function OptionsPanel(opt, name, mod)
  local p = opt.panels[name]
  if not p then
    p = ns.BuildPanel(opt.scroll, ns.ModuleOptions(mod))
    opt.panels[name] = p
  end
  return p
end

local function ModulePage(opt, name, mod)
  local page = opt.pages[name]
  if not page then
    page = CreateFrame("Frame", nil, opt.body)
    page:SetAllPoints()
    GS:Call(mod.BuildPage, mod, page)
    opt.pages[name] = page
  end
  return page
end

local function HideModuleBodies(opt)
  for _, p in pairs(opt.panels) do p:Hide() end
  for _, page in pairs(opt.pages) do page:Hide() end
end

local function ShowSettings(opt, name, mod)
  local p = OptionsPanel(opt, name, mod)
  opt.scroll:SetScrollChild(p)
  opt.scroll:SetVerticalScroll(0)
  opt.scroll:Show()
  p:Show()
end

local function ShowModuleView(name, settings)
  if not win then win = CreateWindow() end
  local mod = GS.modules[name]
  if not mod then return GS:ShowHome() end
  settings = settings or type(mod.BuildPage) ~= "function"
  if not win:IsShown() then win:Show() end
  win.home:Hide()
  local opt = win.optView
  HideModuleBodies(opt)
  if settings and ns.ModuleOptions(mod) then
    ShowSettings(opt, name, mod)
  else
    settings = false
    opt.scroll:Hide()
    ModulePage(opt, name, mod):Show()
  end
  opt:Show()
  GS.optionsModule, GS.moduleSettings = name, settings
  GS:RefreshOverview()
end

function GS:ShowModuleOptions(name) ShowModuleView(name, true) end
function GS:ShowModulePage(name) ShowModuleView(name, false) end

function GS:ShowHome()
  if not win then win = CreateWindow() end
  win.optView:Hide()
  win.home:Show()
  self.optionsModule = nil
  if win:IsShown() then self:RefreshOverview() end
end

local function RecentLines()
  for _, name in ipairs(GS.moduleOrder) do
    local mod = GS.modules[name]
    if mod.OverviewRecent then return GS:Call(mod.OverviewRecent, mod, 12) end
  end
end

local function RenderRecent(m)
  local lines = RecentLines()
  local has = type(lines) == "table" and lines[1] ~= nil
  local key = has and table.concat(lines, "\n") or ""
  if m.shownKey == key then return end
  m.shownKey = key
  m:Clear()
  if not has then m:AddMessage(L.NO_RECENT, 0.6, 0.6, 0.6) end
  for _, line in ipairs(has and lines or {}) do m:AddMessage(line) end
  if m.ScrollToBottom then m:ScrollToBottom() end
end

local function RenderGuildCard(home)
  local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
  home.guild:SetText(g or L.NO_GUILD)
  home.version:SetText("v" .. GS.version)
  home.sync:SetText(L[SYNC_STATES[GS:OverviewSyncState()].label])
  local known, online = ns.PeersOnRoster()
  home.peersBar:SetMinMaxValues(0, math.max(1, known))
  home.peersBar:SetValue(online)
  home.peersBar.text:SetText(GS:OverviewPeersLine())
end

function GS:RefreshOverview()
  if not (win and win:IsShown()) then return end
  local rows = self:OverviewRows()
  RenderTabs(win, rows, self.optionsModule or "home")
  if self.optionsModule then return self:RefreshModuleView(rows) end
  local home = win.home
  RenderGuildCard(home)
  RenderRecent(home.recent)
  home.options.refreshAll()
  if GS:LauncherShown() then home.replace:Enable() else home.replace:Disable() end
end

function GS:RefreshModuleView(rows)
  local name, opt = self.optionsModule, win.optView
  local d = RowFor(rows, name)
  if d then RenderModuleHeader(opt, d, self.moduleSettings) end
  local mod = self.modules[name]
  if self.moduleSettings then
    local p = opt.panels[name]
    if p then p.refreshAll() end
  elseif mod and mod.RefreshPage then
    self:Call(mod.RefreshPage, mod)
  end
end

local refreshTickPending = false
local function Tick()
  refreshTickPending = false
  if not (win and win:IsShown()) then return end
  if not GS.optionsModule then GS:Call(GS.RefreshOverview, GS) end
  refreshTickPending = true
  C_Timer.After(3, Tick)
end
local function StartTick()
  if refreshTickPending then return end
  refreshTickPending = true
  C_Timer.After(3, Tick)
end

function GS:ToggleOverview()
  if not win then win = CreateWindow() end
  if win:IsShown() and not self.optionsModule then win:Hide() return end
  self:ShowHome()
  if not win:IsShown() then win:Show(); StartTick() end
end

function GS:OverviewShown()
  return (win and win:IsShown()) and true or false, self.optionsModule
end

function GS:OpenModule(name)
  local wasShown = win and win:IsShown()
  self:ShowModuleOptions(name)
  if not wasShown then StartTick() end
end

function RavenquillExpedition_OnCompartmentClick() GS:Call(GS.ToggleOverview, GS) end
