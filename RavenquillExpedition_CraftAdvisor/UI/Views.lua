local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI

UI.VIEWS = {
  { id = "make", label = "VIEW_MAKE", icon = "Interface\\Icons\\INV_Hammer_20",
    scopes = { { id = "member", label = "SCOPE_MEMBER" }, { id = "all", label = "SCOPE_ALL", refresh = "RefreshNeeds" } } },
  { id = "commission", label = "VIEW_COMMISSION", icon = "Interface\\Icons\\INV_Scroll_03",
    refresh = "RefreshCrafters", layout = "LayoutCrafters", build = "BuildCrafterView" },
}
UI.DEFAULT_VIEW, UI.DEFAULT_SCOPE = "make", "member"
UI.OLD_VIEWS = { member = { "make", "member" }, needs = { "make", "all" }, crafters = { "commission" } }

local function Find(list, id)
  for _, def in ipairs(list or {}) do
    if def.id == id then return def end
  end
end

function UI.ViewDef(id) return Find(UI.VIEWS, id) end

function UI.Scopes() return UI.ViewDef("make").scopes end

function UI.ScopeDef(id) return Find(UI.Scopes(), id) end

function UI:Scope() return UI.ScopeDef(self.scope) or UI.Scopes()[1] end

function UI:Pane()
  local def = UI.ViewDef(self.view) or UI.VIEWS[1]
  return def.scopes and self:Scope() or def
end

function UI.Panes()
  local out = {}
  for _, def in ipairs(UI.VIEWS) do
    for _, pane in ipairs(def.scopes or { def }) do out[#out + 1] = pane end
  end
  return out
end

function UI:BuildViews(c, painted, listH, rw)
  local frames = { all = self.needsView, member = self.memberView }
  for _, pane in ipairs(UI.Panes()) do
    if pane.build then frames[pane.id] = self[pane.build](self, c, painted, listH, rw) end
  end
  return frames
end

local function CreateTemplatedTabs(f)
  local tabs = {}
  for i in ipairs(UI.VIEWS) do
    local ok, tab = pcall(CreateFrame, "Button", "RavenquillExpeditionCraftFrameTab" .. i, f, "PanelTabButtonTemplate")
    if not (ok and tab) then
      for _, made in ipairs(tabs) do made:Hide() end
      return nil
    end
    tabs[i] = tab
  end
  for i, tab in ipairs(tabs) do
    if tab.SetID then tab:SetID(i) end
    tab:SetText(L[UI.VIEWS[i].label])
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 3, 0) end
  end
  return tabs
end

local function WidestLabel(b, key)
  local fs, w = b.GetFontString and b:GetFontString() or b, 0
  for _, t in pairs(ns.Locales) do
    if t[key] then b:SetText(t[key]); w = math.max(w, UI.TextWidth(fs)) end
  end
  b:SetText(L[key])
  return w
end

local function CreatePlainTabs(c)
  local tabs = {}
  for i = #UI.VIEWS, 1, -1 do
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetSize(WidestLabel(b, UI.VIEWS[i].label) + 16, 22)
    if tabs[i + 1] then b:SetPoint("RIGHT", tabs[i + 1], "LEFT", -4, 0) else b:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -28, 10) end
    tabs[i] = b
  end
  return tabs
end

function UI.CreateViewTabs(f, c)
  local tabs = CreateTemplatedTabs(f)
  local templated = tabs ~= nil
  if not templated then tabs = CreatePlainTabs(c) end
  for i, tab in ipairs(tabs) do
    tab.view = UI.VIEWS[i].id
    tab:SetScript("OnClick", function(self) UI:SetView(self.view) end)
  end
  return tabs, templated
end

function UI:PaintTabs()
  for _, tab in ipairs(self.tabs or {}) do
    local on = tab.view == self.view
    tab.selected = on
    if self.tabsTemplated then
      local fn = on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab
      if type(fn) == "function" then pcall(fn, tab) end
    elseif tab.LockHighlight and tab.UnlockHighlight then
      if on then tab:LockHighlight() else tab:UnlockHighlight() end
    end
  end
end

function UI:ApplyView()
  local pane = self:Pane().id
  for key, frame in pairs(self.viewFrames) do frame:SetShown(key == pane) end
  self:PaintTabs()
end

function UI:ResetView()
  self.view, self.scope = UI.DEFAULT_VIEW, UI.DEFAULT_SCOPE
end

function UI:SetView(view, scope)
  local old = UI.OLD_VIEWS[view]
  if old then view, scope = old[1], old[2] end
  self.view = UI.ViewDef(view) and view or UI.DEFAULT_VIEW
  if Find(UI.ViewDef(self.view).scopes, scope) then self.scope = scope end
  if self.frame then
    self:ApplyView()
    self:Refresh()
  end
end
