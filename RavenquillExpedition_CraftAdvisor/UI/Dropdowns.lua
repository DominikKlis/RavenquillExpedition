local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local G, C, SetAtlasSafe, TexOK = P.G, P.C, P.SetAtlasSafe, P.TexOK
local SingleLine, SetTip, SpecHowText = P.SingleLine, P.SetTip, P.SpecHowText
local NewTextButton = P.NewTextButton
local NewPopup, KeepNativeHover = P.NewPopup, P.KeepNativeHover

local function NewDropdown(parent, template, w, h)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, template)
  if not (ok and dd and type(dd.SetupMenu) == "function") then
    if ok and dd and dd.Hide then dd:Hide() end
    return nil
  end
  dd:SetSize(w, h)
  dd.native = true
  return dd
end
UI.NewDropdown = NewDropdown
local function RefreshDropdown(dd, text)
  if not (dd and dd.native) then return end
  if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end
  if text and dd.OverrideText then pcall(dd.OverrideText, dd, text) end
end
UI.RefreshDropdown = RefreshDropdown

local NATIVE_ITEM = {}
function NATIVE_ITEM.radio(root, it) return root:CreateRadio(it.label, it.checked, it.onClick) end
function NATIVE_ITEM.check(root, it) return root:CreateCheckbox(it.label, it.checked, it.onClick) end
function NATIVE_ITEM.button(root, it) return root:CreateButton(it.label, it.onClick) end
function NATIVE_ITEM.title(root, it) if root.CreateTitle then root:CreateTitle(it.label) end end
function NATIVE_ITEM.divider(root) if root.CreateDivider then root:CreateDivider() end end
function NATIVE_ITEM.native(root, it) pcall(it.build, root) end

local function NativeMenu(items)
  return function(_, root)
    for _, it in ipairs(items()) do
      local e = NATIVE_ITEM[it.kind](root, it)
      if it.tip and type(e) == "table" and e.SetTooltip then
        pcall(e.SetTooltip, e, function(tooltip)
          tooltip:SetText(it.label, 1, 1, 1)
          tooltip:AddLine(it.tip, nil, nil, nil, true)
        end)
      end
    end
  end
end

local function SetRowMark(b, on)
  if not b.mark then
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetSize(14, 14)
    b.mark:SetPoint("LEFT", 2, 0)
    b.markOK = TexOK("check")
    if b.markOK then b.mark:SetTexture(UI.TEX.check) end
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 18, 0)
  end
  b.mark:SetShown(on and b.markOK or false)
  return (on and not b.markOK) and "> " or ""
end

local function SetRowCheck(b, on)
  if not b.check then
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 22, 0)
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetSize(16, 16)
    b.check:SetPoint("LEFT", 3, 0)
    b.check:SetTexture(UI.TEX.check)
  end
  b.check:SetShown(on and true or false)
end

local PAINT_ROW = {}
function PAINT_ROW.radio(b, it) b.text:SetText(SetRowMark(b, it.checked()) .. it.label) end
function PAINT_ROW.title(b, it)
  SetRowMark(b, false)
  b.text:SetText(C.dim .. it.label .. "|r")
end
function PAINT_ROW.check(b, it)
  SetRowCheck(b, it.checked())
  b.text:SetText(it.label)
end
function PAINT_ROW.button(b, it)
  SetRowCheck(b, false)
  b.text:SetText(it.label)
end

local function ClickPopupRow(b)
  local it, pop = b.item, b.pop
  if it.kind == "title" then return end
  if it.kind == "check" then
    it.onClick()
    if pop:IsShown() then pop:Fill() end
    return
  end
  pop:Hide()
  it.onClick()
end

local function PopupRowTip(b)
  local it = b.item
  if not (it and it.tip) then return end
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  GameTooltip:SetText(it.label, 1, 1, 1)
  GameTooltip:AddLine(it.tip, nil, nil, nil, true)
  GameTooltip:Show()
end

local function PopupRow(pop, i, width)
  local b = CreateFrame("Button", nil, pop)
  b:SetSize(width, 18)
  b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 4, 0)
  SingleLine(b.text)
  b.pop = pop
  b:SetScript("OnClick", ClickPopupRow)
  SetTip(b, "menu row", PopupRowTip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  pop.buttons[i] = b
  return b
end

local function NewMenuPopup(parent, window, items, rowW)
  local pop = NewPopup(parent)
  pop.buttons = {}
  function pop:Fill()
    local n = 0
    for _, it in ipairs(items()) do
      local paint = PAINT_ROW[it.kind]
      if paint then
        n = n + 1
        local b = self.buttons[n] or PopupRow(self, n, rowW)
        b.item = it
        paint(b, it)
        b:Show()
      end
    end
    for i = n + 1, #self.buttons do self.buttons[i]:Hide() end
    self:SetSize(rowW + 12, 12 + n * 18)
    return n
  end
  function pop:Toggle()
    if self:IsShown() then self:Hide() return end
    if self:Fill() > 0 then self:Show() end
  end
  window:HookScript("OnHide", function() pop:Hide() end)
  return pop
end

local function OpenPopupOnClick(b, pop, tipName, tip)
  b:SetScript("OnClick", function() pop:Toggle() end)
  SetTip(b, tipName, tip)
  b:SetScript("OnLeave", GameTooltip_Hide)
end

UI.MEMBER_MODES = { { "sheet", "MVIEW_SHEET" }, { "list", "MVIEW_LIST" } }
UI.TOGGLE_W = 170
local function ModeItems()
  local items = {}
  for _, def in ipairs(UI.MEMBER_MODES) do
    local mode = def[1]
    items[#items + 1] = { kind = "radio", label = L[def[2]], checked = function() return UI.MemberMode() == mode end,
      onClick = function() UI:SetMemberMode(mode) end }
  end
  return items
end
local function ModeLabel(mode)
  return string.format(L.MVIEW_LABEL, L[mode == "list" and "MVIEW_LIST" or "MVIEW_SHEET"])
end
UI.ModeLabel = ModeLabel
local function ModeTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
  GameTooltip:SetText(ModeLabel(UI.MemberMode()), 1, 1, 1)
  GameTooltip:AddLine(L.MVIEW_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end
P.CreateModeSwitch = function(parent)
  local dd = NewDropdown(parent, "WowStyle1DropdownTemplate", UI.TOGGLE_W, 22)
  if dd then
    dd:SetupMenu(NativeMenu(ModeItems))
    KeepNativeHover(dd, "member view", ModeTip)
  else
    dd = NewTextButton(parent, UI.TOGGLE_W, 22, ModeLabel("sheet"))
    dd:SetScript("OnClick", function() UI:SetMemberMode(UI.MemberMode() == "list" and "sheet" or "list") end)
    SetTip(dd, "member view", ModeTip)
    dd:SetScript("OnLeave", GameTooltip_Hide)
  end
  function dd:Paint(mode)
    self.mode = mode
    if self.native then RefreshDropdown(self, ModeLabel(mode)) else self:SetText(ModeLabel(mode)) end
  end
  return dd
end

function UI:SetMemberMode(mode)
  if not (GCA.db and GCA.db.settings) then return end
  GCA:SetSetting("memberView", mode == "list" and "list" or "sheet")
  self:ApplyMemberMode()
  self:Refresh()
end

function UI:ApplyMemberMode()
  local mode = UI.MemberMode()
  if self.modeToggle then self.modeToggle:Paint(mode) end
  if self.sugList then self.sugList:SetShown(mode == "list") end
  if self.sheet and mode ~= "sheet" then self.sheet:Hide() end
end

function UI.SetClassIcon(tex, class)
  if type(class) ~= "string" then return nil end
  if SetAtlasSafe(tex, "classicon-" .. class:lower()) then
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    return "atlas"
  end
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if type(c) == "table" and c[4] and TexOK("classIcons") then
    tex:SetTexture(UI.TEX.classIcons)
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
    return "file"
  end
  return nil
end
UI.SPEC_BTN_W = 200
local function ChooseSpec(spec)
  local cur = UI.current
  if not (cur and cur.class) then return end
  GCA:SetManualSpec(cur.key, cur.class, spec)
  UI:Refresh()
end
local function SpecItems()
  local d = UI.current
  if not (d and d.class) then return {} end
  local items = { { kind = "radio", label = L.SPEC_AUTOMATIC, checked = function() return not GCA.db.specManual[d.key] end,
    onClick = function() ChooseSpec(nil) end } }
  for _, spec in ipairs(GCA.SPECS_OF[d.class] or {}) do
    items[#items + 1] = { kind = "radio", label = GCA:SpecName(d.class, spec), onClick = function() ChooseSpec(spec) end,
      checked = function()
        local m = GCA.db.specManual[d.key]
        return m ~= nil and m.spec == spec
      end }
  end
  return items
end
local function SpecTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.SPEC_TIP_TITLE, 1, 1, 1)
  GameTooltip:AddLine(L.SPEC_TIP, nil, nil, nil, true)
  if UI.current and UI.current.member then GameTooltip:AddLine(SpecHowText(UI.current), 1, 1, 1, true) end
  GameTooltip:Show()
end
P.CreateSpecPicker = function(parent, window)
  local btn = CreateFrame("Frame", nil, parent)
  btn:SetSize(UI.SPEC_BTN_W, 32)
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetSize(22, 22)
  btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
  local dd = NewDropdown(btn, "WowStyle1DropdownTemplate", UI.SPEC_BTN_W - 28, 22)
  local pop
  if dd then
    dd:SetupMenu(NativeMenu(SpecItems))
    KeepNativeHover(dd, "spec button", SpecTip)
  else
    dd = NewTextButton(btn, UI.SPEC_BTN_W - 28, 22, "?")
    pop = NewMenuPopup(parent, window, SpecItems, 190)
    pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    OpenPopupOnClick(dd, pop, "spec button", SpecTip)
  end
  dd:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
  btn.dropdown = dd
  function btn:SetText(t)
    self.text = t
    if self.dropdown.native then RefreshDropdown(self.dropdown, t) else self.dropdown:SetText(t) end
  end
  function btn:GetText() return self.text end
  function btn:SetClass(class)
    if self.iconClass == class and self.iconKind ~= nil then return end
    self.iconClass = class
    self.iconKind = UI.SetClassIcon(self.icon, class)
    self.icon:SetShown(self.iconKind ~= nil)
  end
  btn:SetClass(nil)
  btn:SetText("?")
  return btn, pop
end

UI.FILTERS = {
  { key = "showUnlearned", label = "FILTER_UNLEARNED", tip = "FILTER_UNLEARNED_TIP" },
  { key = "lookahead", label = "FILTER_LOOKAHEAD", tip = "FILTER_LOOKAHEAD_TIP" },
  { key = "autoInspect", label = "FILTER_AUTOINSPECT", tip = "FILTER_AUTOINSPECT_TIP" },
  { key = "sync", label = "FILTER_SYNC", tip = "FILTER_SYNC_TIP" },
}
function UI.ToggleSetting(key)
  local on = not GCA.db.settings[key]
  GCA:SetSetting(key, on)
  UI:Refresh()
  return on
end

UI.FILTER_W, UI.FILTER_H = 90, 18
local function SettingOn(key)
  local s = GCA.db and GCA.db.settings or {}
  return s[key] and true or false
end
UI.SURVIVAL_STEPS = { 0, 25, 50, 75, 100 }
function UI.SetSurvival(v)
  if GCA:SetSurvival(v) then UI:Refresh() end
end
local function SurvivalSubmenu(root)
  local a, b = G("SPELL_STAT3_NAME"), G("SPELL_STAT5_NAME")
  local cur = math.floor(GCA:SurvivalShare() * 100 + 0.5)
  local sub = root:CreateButton(string.format(L.SLIDER_LABEL, a, b, cur))
  if type(sub) ~= "table" or not sub.CreateRadio then return false end
  if sub.SetTooltip then
    pcall(sub.SetTooltip, sub, function(tooltip)
      tooltip:SetText(string.format(L.SLIDER_TIP_TITLE, a, b), 1, 1, 1)
      tooltip:AddLine(string.format(L.SLIDER_TIP, a, b), nil, nil, nil, true)
    end)
  end
  for _, v in ipairs(UI.SURVIVAL_STEPS) do
    sub:CreateRadio(v .. " %", function(x) return math.floor(GCA:SurvivalShare() * 100 + 0.5) == x end,
      function(x) UI.SetSurvival(x) end, v)
  end
  return true
end
local function FilterItems()
  local items = {}
  for _, def in ipairs(UI.FILTERS) do
    local key = def.key
    items[#items + 1] = { kind = "check", label = L[def.label], tip = L[def.tip], checked = function() return SettingOn(key) end,
      onClick = function() UI.ToggleSetting(key) end }
  end
  items[#items + 1] = { kind = "check", label = string.format(L.NEEDS_OFFLINE, UI.offlineN or 0), tip = L.NEEDS_OFFLINE_TIP,
    checked = function() return SettingOn("needsOffline") end, onClick = function() UI:SetNeedsOffline(not SettingOn("needsOffline")) end }
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "native", build = SurvivalSubmenu }
  items[#items + 1] = { kind = "button", label = L.EDIT_WHISPER, tip = L.EDIT_WHISPER_TIP, onClick = function() UI:OpenWhisperEditor() end }
  items[#items + 1] = { kind = "button", label = L.OPT_INSPECT_NOW, tip = L.OPT_INSPECT_NOW_TIP,
    onClick = function() if GCA.db then GCA:InspectTarget() end end }
  items[#items + 1] = { kind = "button", label = L.OPT_SCAN_NOW, tip = L.OPT_SCAN_NOW_TIP,
    onClick = function() if GCA.db then GCA:ScanGroup() end end }
  if UI.SyncState() == "paused" then
    items[#items + 1] = { kind = "button", label = L.OPT_SYNC_RETRY, tip = L.OPT_SYNC_RETRY_TIP,
      onClick = function() GCA:SyncRetry(); GCA:RefreshUI() end }
  end
  return items
end
local function FilterTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.FILTER_BUTTON, 1, 1, 1)
  GameTooltip:AddLine(L.OPTIONS_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end
UI.FILTER_DEFAULTS = {}
for _, k in ipairs({ "showUnlearned", "lookahead", "needsOffline" }) do UI.FILTER_DEFAULTS[k] = GCA.defaults[k] and true or false end
function UI.FiltersAtDefault()
  local s = GCA.db and GCA.db.settings or {}
  for k, v in pairs(UI.FILTER_DEFAULTS) do
    if (s[k] and true or false) ~= v then return false end
  end
  return true
end
function UI.ResetFilters()
  if not (GCA.db and GCA.db.settings) then return end
  for k, v in pairs(UI.FILTER_DEFAULTS) do GCA:SetSetting(k, v) end
  UI:Refresh()
  UI:RefreshFilters()
end
function UI.AddFilterReset(dd)
  if dd.native and type(dd.SetIsDefaultCallback) == "function" and type(dd.SetDefaultCallback) == "function"
    and pcall(dd.SetIsDefaultCallback, dd, UI.FiltersAtDefault) and pcall(dd.SetDefaultCallback, dd, UI.ResetFilters) then
    dd.resetKind = "native"
    return
  end
  local rb = CreateFrame("Button", nil, dd)
  rb:SetSize(20, 20)
  rb:SetPoint("CENTER", dd, "TOPRIGHT", -3, -1)
  rb.icon = rb:CreateTexture(nil, "ARTWORK")
  rb.icon:SetAllPoints()
  if SetAtlasSafe(rb.icon, "auctionhouse-ui-filter-redx") then
    rb.kind = "atlas"
  else
    rb.icon:Hide()
    rb.text = rb:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    rb.text:SetPoint("CENTER")
    rb.text:SetText("x")
    rb.text:SetTextColor(1, 0.2, 0.2)
    rb.kind = "text"
  end
  rb:SetScript("OnClick", function() UI.ResetFilters() end)
  SetTip(rb, "filter reset", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.FILTER_RESET, 1, 1, 1)
    GameTooltip:Show()
  end)
  rb:SetScript("OnLeave", GameTooltip_Hide)
  rb:SetShown(not UI.FiltersAtDefault())
  dd.resetButton, dd.resetKind = rb, "own"
end
P.CreateFilterMenu = function(parent, window)
  local dd = NewDropdown(parent, "WowStyle1FilterDropdownTemplate", UI.FILTER_W, UI.FILTER_H)
  if dd then
    dd:SetupMenu(NativeMenu(FilterItems))
    KeepNativeHover(dd, "filter button", FilterTip)
    UI.AddFilterReset(dd)
    return dd, nil
  end
  local btn = NewTextButton(parent, UI.FILTER_W, 22, L.FILTER_BUTTON)
  UI.AddFilterReset(btn)
  local pop = NewMenuPopup(parent, window, FilterItems, 288)
  pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -4)
  OpenPopupOnClick(btn, pop, "filter button", FilterTip)
  return btn, pop
end

function UI:RefreshFilters()
  local atDefault = UI.FiltersAtDefault()
  for _, f in ipairs(self.filters or {}) do
    if f.button.native then RefreshDropdown(f.button) elseif f.popup and f.popup:IsShown() then f.popup:Fill() end
    if f.button.resetButton then f.button.resetButton:SetShown(not atDefault) end
    if f.button.resetKind == "native" and f.button.ValidateResetState then pcall(f.button.ValidateResetState, f.button) end
  end
end

P.NativeMenu = NativeMenu
P.NewMenuPopup = NewMenuPopup
P.OpenPopupOnClick = OpenPopupOnClick
