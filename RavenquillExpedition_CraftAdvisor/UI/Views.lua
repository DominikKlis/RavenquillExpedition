local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI

UI.VIEWS = {
  { key = "member", label = "VIEW_MEMBER" },
  { key = "needs", label = "VIEW_NEEDS", refresh = "RefreshNeeds" },
  { key = "crafters", label = "VIEW_CRAFTERS", refresh = "RefreshCrafters", layout = "LayoutCrafters", build = "BuildCrafterView" },
  { key = "orders", label = "VIEW_ORDERS", refresh = "RefreshOrders", layout = "LayoutOrders", build = "BuildOrdersView" },
}
UI.DEFAULT_VIEW = "member"

function UI:BuildViews(c, painted, listH, rw)
  local frames = { needs = self.needsView, member = self.memberView }
  for _, def in ipairs(UI.VIEWS) do
    if def.build then frames[def.key] = self[def.build](self, c, painted, listH, rw) end
  end
  return frames
end

function UI.ViewDef(key)
  for _, def in ipairs(UI.VIEWS) do
    if def.key == key then return def end
  end
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
    tab.view = UI.VIEWS[i].key
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
  for key, frame in pairs(self.viewFrames) do frame:SetShown(key == self.view) end
  self:PaintTabs()
end

function UI:SetView(view)
  self.view = UI.ViewDef(view) and view or UI.DEFAULT_VIEW
  if self.frame then
    self:ApplyView()
    self:Refresh()
  end
end
