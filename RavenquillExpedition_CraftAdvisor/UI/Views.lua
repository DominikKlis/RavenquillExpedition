local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI

UI.VIEWS = {
  { key = "member", label = "VIEW_MEMBER" },
  { key = "needs", label = "VIEW_NEEDS", refresh = "RefreshNeeds" },
}
UI.DEFAULT_VIEW = "member"

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

function UI.CreateViewTabs(f, c)
  local tabs = CreateTemplatedTabs(f)
  local templated = tabs ~= nil
  if not templated then
    tabs = {}
    for i, def in ipairs(UI.VIEWS) do
      local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
      b:SetSize(92, 22)
      b:SetText(L[def.label])
      b:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -28 - (#UI.VIEWS - i) * 96, 10)
      tabs[i] = b
    end
  end
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
