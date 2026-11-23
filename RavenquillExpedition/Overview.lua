local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local L = GS.OverviewL

local KNOWN_ADDONS = {
  { module = "Highlights", addon = "RavenquillExpedition_Highlights", slash = "hl", icon = "Interface\\Icons\\INV_Misc_Note_01" },
  { module = "Map", addon = "RavenquillExpedition_Map", slash = "map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
  { module = "Craft", addon = "RavenquillExpedition_CraftAdvisor", slash = "craft", title = L.CRAFT_TITLE,
    icon = "Interface\\Icons\\Trade_BlackSmithing" },
}
local TAB_ORDER = { "home", "Readiness", "Highlights", "Map", "Craft" }

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

local function HasModulePage(mod)
  return type(mod.BuildPage) == "function" or type(mod.Open) == "function" or type(mod.OverviewEntries) == "function"
end

local function KnownAddon(name)
  for _, k in ipairs(KNOWN_ADDONS) do if k.module == name then return k end end
end

local function ModuleRow(mod, k)
  local title, icon = TitleAndIcon(mod, k)
  local row = { name = mod.name, title = title, icon = icon, slash = "/rq " .. ns.SlashWord(mod), state = "loaded" }
  row.status = mod.OverviewStatus and GS:Call(mod.OverviewStatus, mod) or L.LOADED
  if type(row.status) ~= "string" then row.status = "" end
  if mod.Open then row.open = function() GS:Call(mod.Open, mod) end end
  row.openLabel, row.openInHeader = mod.openLabel, mod.openInHeader
  if ns.ModuleOptions(mod) then row.options = true end
  if HasModulePage(mod) then row.page = true end
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


local win
local WIDTH, HEIGHT, MAX_TABS = 673, 594, 7
local SUITE_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local WIDE_CARD = "Profession-overview-Card"
local SIZE = { edge = 24 }
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

local SETTINGS_BUTTON_WIDTH = 150

local function IconButton(parent, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(height - 8, height - 8)
  b.icon:SetPoint("LEFT", 6, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return b
end

local function BuildOptionsView(f)
  local opt = CreateFrame("Frame", nil, f)
  opt:SetAllPoints()
  opt:Hide()
  local inset = ns.SlicedCard(opt, WIDE_CARD, SIZE.edge)
  inset:SetPoint("TOPLEFT", 5, -41)
  inset:SetPoint("BOTTOMRIGHT", -4, 5)
  opt.status = Text(inset, "GameFontHighlightSmall")
  opt.status:SetPoint("TOPLEFT", 20, -23)
  opt.status:SetPoint("RIGHT", inset, "RIGHT", -(SETTINGS_BUTTON_WIDTH + 30), 0)
  opt.status:SetTextColor(0.8, 0.8, 0.8)
  opt.gear = IconButton(inset, SETTINGS_BUTTON_WIDTH, 26)
  opt.gear:SetPoint("TOPRIGHT", -20, -14)
  opt.gear.icon:SetTexture(GEAR_ICON)
  opt.gear:SetText(L.SETTINGS)
  opt.openWindow = IconButton(inset, SETTINGS_BUTTON_WIDTH, 26)
  opt.openWindow:SetPoint("RIGHT", opt.gear, "LEFT", -10, 0)
  opt.openWindow:Hide()
  local line = ns.Rule(inset, opt.status, -14)
  opt.body = CreateFrame("Frame", nil, inset)
  opt.body:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -4, -8)
  opt.body:SetPoint("BOTTOMRIGHT", -16, 10)
  local sf = CreateFrame("ScrollFrame", nil, opt.body)
  sf:SetAllPoints()
  ns.PageScroll(sf)
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
  f.home = ns.BuildHome(f)
  f.optView = BuildOptionsView(f)
  f:SetScript("OnShow", function() GS:Call(GS.RefreshOverview, GS) end)
  f:Hide()
  return f
end

local function ExtraPage(row, p)
  if not (type(p) == "table" and type(p.id) == "string" and type(p.build) == "function") then return nil end
  return { id = p.id, module = row.name, title = p.title or row.title, icon = p.icon or row.icon, build = p.build,
    refresh = p.refresh, extra = true }
end

local function PagesOf(row)
  local out = {}
  if row.options or row.page then
    out[1] = { id = row.name, module = row.name, title = row.title, icon = row.icon, status = row.status }
  end
  local mod = row.name and GS.modules[row.name]
  for _, p in ipairs(mod and type(mod.pages) == "table" and mod.pages or {}) do out[#out + 1] = ExtraPage(row, p) end
  return out
end

local function Rank(id, i)
  for r, known in ipairs(TAB_ORDER) do if known == id then return r end end
  return #TAB_ORDER + i
end

local function Ordered(pages)
  for i, p in ipairs(pages) do p.rank = Rank(p.id, i) end
  table.sort(pages, function(a, b) return a.rank < b.rank end)
  return pages
end

function GS:OverviewPages(rows)
  local pages = { { id = "home", title = L.OVERVIEW, icon = SUITE_ICON, status = self:OverviewPeersLine() } }
  for _, row in ipairs(rows or self:OverviewRows()) do
    for _, p in ipairs(PagesOf(row)) do pages[#pages + 1] = p end
  end
  return Ordered(pages)
end

local function PageById(pages, id)
  for _, p in ipairs(pages) do if p.id == id then return p end end
end

local function RenderTabs(f, pages, current)
  for i, tab in ipairs(f.tabs) do
    local it = pages[i]
    tab:SetShown(it ~= nil)
    if it then
      tab.page, tab.title, tab.status = it.id, it.title, it.status
      tab.icon:SetTexture(it.icon)
      tab.selected:SetShown(it.id == current)
    end
  end
  local page = PageById(pages, current) or pages[1]
  ns.SetWindowTitle(f, page.id == "home" and L.TITLE or page.title)
  ns.SetPortrait(f, page.icon)
end

local function RowFor(rows, name)
  for _, d in ipairs(rows) do if d.name == name then return d end end
end

local function RenderGear(gear, d, settings)
  gear:SetShown((d.page and d.options) and true or false)
  gear:SetText(settings and L.BACK or L.SETTINGS)
  gear.icon:SetShown(not settings)
  gear:SetScript("OnClick", function()
    if GS.moduleSettings then GS:ShowModulePage(d.name) else GS:ShowModuleOptions(d.name) end
  end)
end

local function RenderOpenWindow(opt, d)
  local b, shown = opt.openWindow, (d.openInHeader and d.open) and true or false
  b:SetShown(shown)
  opt.status:SetPoint("RIGHT", shown and b or opt.gear, "LEFT", -10, 0)
  if not shown then return end
  b.icon:SetTexture(d.icon)
  b:SetText(d.openLabel and L.OPEN_WINDOW:format(d.openLabel) or L.OPEN)
  b:SetScript("OnClick", function() d.open() end)
end

local function RenderModuleHeader(opt, d, settings)
  opt.status:SetText(d.status)
  RenderGear(opt.gear, d, settings)
  RenderOpenWindow(opt, d)
end

local function OptionsPanel(opt, name, mod)
  local p = opt.panels[name]
  if not p then
    p = ns.BuildPanel(opt.scroll, ns.ModuleOptions(mod))
    opt.panels[name] = p
  end
  return p
end

local function ModuleIcon(mod) return select(2, TitleAndIcon(mod, KnownAddon(mod.name))) end

local function BuildHint(mod, page)
  local hint = Text(page, "GameFontHighlightSmall")
  hint:SetPoint("RIGHT", page, "RIGHT", -16, 0)
  hint:SetTextColor(0.8, 0.8, 0.8)
  hint:SetText(mod.openHint or "")
  page.hint = hint
  return hint
end

local function BuildEntriesPage(mod, page)
  local hint = BuildHint(mod, page)
  hint:SetPoint("TOPLEFT", 16, -12)
  page.entries = ns.EntryCards(page)
  page.entries:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -10, -16)
  page.entries:SetPoint("RIGHT", page, "RIGHT", -2, 0)
end

local function BuildOpenPage(mod, page)
  if type(mod.OverviewEntries) == "function" then return BuildEntriesPage(mod, page) end
  local b = IconButton(page, SETTINGS_BUTTON_WIDTH + 30, 26)
  b:SetPoint("TOPLEFT", 16, -8)
  b.icon:SetTexture(ModuleIcon(mod))
  b:SetText(mod.openLabel and L.OPEN_WINDOW:format(mod.openLabel) or L.OPEN)
  b:SetScript("OnClick", function() GS:Call(mod.Open, mod) end)
  page.open = b
  BuildHint(mod, page):SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -10)
end

local function RenderEntries(page, mod)
  if not (page and page.entries) then return end
  ns.RenderEntries(page.entries, ns.Entries(GS:Call(mod.OverviewEntries, mod), ModuleIcon(mod)))
end

local function BuildPageBody(page, mod, frame)
  if page.extra then return GS:Call(page.build, frame) end
  GS:Call(type(mod.BuildPage) == "function" and mod.BuildPage or BuildOpenPage, mod, frame)
end

local function PageFrame(opt, page, mod)
  local frame = opt.pages[page.id]
  if not frame then
    frame = CreateFrame("Frame", nil, opt.body)
    frame:SetAllPoints()
    BuildPageBody(page, mod, frame)
    opt.pages[page.id] = frame
  end
  return frame
end

local function HideModuleBodies(opt)
  for _, p in pairs(opt.panels) do p:Hide() end
  for _, page in pairs(opt.pages) do page:Hide() end
end

local function ShowSettings(opt, name, mod)
  local p = OptionsPanel(opt, name, mod)
  ns.SetScrollPage(opt.scroll, p)
  opt.scroll:Show()
  p:Show()
end

local function WantsSettings(page, mod, settings)
  if page.extra or not ns.ModuleOptions(mod) then return false end
  return settings or not HasModulePage(mod)
end

local function ShowPageView(id, settings)
  if not win then win = CreateWindow() end
  local page = PageById(GS:OverviewPages(), id)
  local mod = page and GS.modules[page.module]
  if not mod then return GS:ShowHome() end
  settings = WantsSettings(page, mod, settings)
  if not win:IsShown() then win:Show() end
  win.home:Hide()
  local opt = win.optView
  HideModuleBodies(opt)
  if settings then
    ShowSettings(opt, mod.name, mod)
  else
    opt.scroll:Hide()
    PageFrame(opt, page, mod):Show()
  end
  opt:Show()
  GS.overviewPage, GS.optionsModule, GS.moduleSettings = page.id, mod.name, settings
  GS:RefreshOverview()
end

function GS:ShowModuleOptions(name) ShowPageView(name, true) end
function GS:ShowModulePage(id) ShowPageView(id, false) end

function GS:ShowHome()
  if not win then win = CreateWindow() end
  win.optView:Hide()
  win.home.mode = nil
  win.home:Show()
  self.overviewPage, self.optionsModule = nil, nil
  if win:IsShown() then self:RefreshOverview() end
end

local NO_HEADER = { status = "" }

local function RefreshPageView(rows, page)
  local opt, mod = win.optView, GS.modules[page.module]
  local d = page.extra and NO_HEADER or RowFor(rows, page.module)
  if d then RenderModuleHeader(opt, d, GS.moduleSettings) end
  if GS.moduleSettings then
    local p = opt.panels[page.module]
    if p then p.refreshAll() end
  elseif page.extra then
    GS:Call(page.refresh)
  else
    RenderEntries(opt.pages[page.id], mod)
    if mod.RefreshPage then GS:Call(mod.RefreshPage, mod) end
  end
end

function GS:RefreshOverview()
  if not (win and win:IsShown()) then return end
  local rows = self:OverviewRows()
  local pages = self:OverviewPages(rows)
  local page = self.overviewPage and PageById(pages, self.overviewPage)
  RenderTabs(win, pages, page and page.id or "home")
  if page then return RefreshPageView(rows, page) end
  ns.RenderHome(win.home, rows)
end

local refreshTickPending = false
local function Tick()
  refreshTickPending = false
  if not (win and win:IsShown()) then return end
  if not GS.overviewPage then GS:Call(GS.RefreshOverview, GS) end
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
  if win:IsShown() and not self.overviewPage then win:Hide() return end
  self:ShowHome()
  if not win:IsShown() then win:Show(); StartTick() end
end

function GS:OverviewShown()
  return (win and win:IsShown()) and true or false, self.overviewPage
end

function GS:OpenModule(name)
  local wasShown = win and win:IsShown()
  self:ShowModuleOptions(name)
  if not wasShown then StartTick() end
end

function RavenquillExpedition_OnCompartmentClick() GS:Call(GS.ToggleOverview, GS) end
