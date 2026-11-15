local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, G, MIN_W, MIN_H, DEFAULT_W = P.SafeCall, P.G, P.MIN_W, P.MIN_H, P.DEFAULT_W
local DEFAULT_H, LEFT_W, RIGHT_X, RightW = P.DEFAULT_H, P.LEFT_W, P.RIGHT_X, P.RightW
local PANEL_TOP, PANEL_BOTTOM, DETAIL_HEAD = P.PANEL_TOP, P.PANEL_BOTTOM, P.DETAIL_HEAD
local MEMBER_ROW_H, GROUP_ROW_H, NEED_ROW_H = P.MEMBER_ROW_H, P.GROUP_ROW_H, P.NEED_ROW_H
local MEMBER_LIST_TOP, COUNT_H, C, SUB_TINT = P.MEMBER_LIST_TOP, P.COUNT_H, P.C, P.SUB_TINT
local SetAtlasSafe, FileOK, TexOK, SingleLine = P.SetAtlasSafe, P.FileOK, P.TexOK, P.SingleLine
local Guard, SetTip, ClassColor, ClassName, Hex = P.Guard, P.SetTip, P.ClassColor, P.ClassName, P.Hex
local Ago, SourceText, ProfName, TextWidth = P.Ago, P.SourceText, P.ProfName, P.TextWidth
local NewInset, RaiseInsetBorder, ApplyLevels = P.NewInset, P.RaiseInsetBorder, P.ApplyLevels
local NewWindow, CreateScrollList, CreateMemberRow = P.NewWindow, P.CreateScrollList, P.CreateMemberRow
local UpdateMemberRow, CreateGroupRow, UpdateGroupRow = P.UpdateMemberRow, P.CreateGroupRow, P.UpdateGroupRow
local CreateCardRow, UpdateCardRow, SECTION_H = P.CreateCardRow, P.UpdateCardRow, P.SECTION_H
local CreateSectionRow, UpdateSectionRow = P.CreateSectionRow, P.UpdateSectionRow
local CreateFoldRow, UpdateFoldRow, FoldHeight = P.CreateFoldRow, P.UpdateFoldRow, P.FoldHeight
local CreateCraftGroupRow, UpdateCraftGroupRow = P.CreateCraftGroupRow, P.UpdateCraftGroupRow
local CreateSheet, CreateProfessionPicker, NewEditBox = P.CreateSheet, P.CreateProfessionPicker, P.NewEditBox
local SetEscCloses, CreateSurvivalSlider = P.SetEscCloses, P.CreateSurvivalSlider

---------------------------------------------------------------------------
-- Window size and position
---------------------------------------------------------------------------
local function Num(v)
  if type(v) ~= "number" or GCA.IsSecret(v) or v ~= v then return nil end
  return v
end

-- UIParent's size in UI units (our window is a scale-1 child of UIParent); nil when unknown
local function ScreenSize()
  local w = UIParent and UIParent.GetWidth and Num(SafeCall(UIParent.GetWidth, UIParent))
  local h = UIParent and UIParent.GetHeight and Num(SafeCall(UIParent.GetHeight, UIParent))
  return (w and w > 0) and w or nil, (h and h > 0) and h or nil
end

-- at least MIN, at most the screen (the minimum wins on a screen smaller than MIN)
function UI.ClampSize(w, h)
  local sw, sh = ScreenSize()
  w, h = Num(w) or DEFAULT_W, Num(h) or DEFAULT_H
  if sw then w = math.min(w, math.floor(sw)) end
  if sh then h = math.min(h, math.floor(sh)) end
  return math.max(MIN_W, math.floor(w + 0.5)), math.max(MIN_H, math.floor(h + 0.5))
end

-- top-left corner (UIParent BOTTOMLEFT coordinates) kept on the screen; nil when not a usable position
function UI.ClampPos(left, top, w, h)
  left, top = Num(left), Num(top)
  if not (left and top) then return nil end
  local sw, sh = ScreenSize()
  if sw then left = math.max(0, math.min(left, sw - w)) end
  if sh then top = math.min(sh, math.max(top, h)) end
  return math.floor(left + 0.5), math.floor(top + 0.5)
end

local function SavedWindow()
  local s = GCA.db and GCA.db.settings
  local win = s and s.window
  if type(win) == "table" then return win end
end

-- Size and position from db.settings.window (clamped), else the default size, centred.
function UI:RestoreGeometry()
  local f = self.frame
  local win = SavedWindow()
  local w, h = UI.ClampSize(win and win.w or DEFAULT_W, win and win.h or DEFAULT_H)
  f:SetSize(w, h)
  f:ClearAllPoints()
  local left, top
  if win then left, top = UI.ClampPos(win.left, win.top, w, h) end
  if left then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) else f:SetPoint("CENTER") end
  return w, h
end

function UI:SaveGeometry()
  local f = self.frame
  if not (f and GCA.db and GCA.db.settings) then return end
  local w, h = UI.ClampSize(f:GetWidth(), f:GetHeight())
  local win = { w = w, h = h }
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  win.left, win.top = UI.ClampPos(left, top, w, h)
  GCA.db.settings.window = win
  -- our SavedVariables hold the geometry: keep the client's layout cache (StartMoving/StartSizing mark the named
  -- frame "user placed") from restoring an older position over it
  if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
  return win
end

-- Anchor the window by its top-left corner where it is now, so sizing from the bottom-right corner keeps
-- the top-left in place (the first open is anchored at CENTER).
local function PinTopLeft(f)
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  if not (left and top) then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Engine resize limits: SetResizeBounds on 10.0+ clients (ForeverLFG_GroupQuest QuestMatchesUI.lua:345 calls it
-- on Forever), SetMinResize/SetMaxResize on older ones; neither -> nil and StopSizing clamps afterwards.
local function SetBounds(f)
  local sw, sh = ScreenSize()
  local maxW, maxH = math.max(MIN_W, math.floor(sw or 4096)), math.max(MIN_H, math.floor(sh or 4096))
  if f.SetResizeBounds and pcall(f.SetResizeBounds, f, MIN_W, MIN_H, maxW, maxH) then return "SetResizeBounds" end
  if f.SetMinResize and pcall(f.SetMinResize, f, MIN_W, MIN_H) then
    if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
    return "SetMinResize"
  end
  return nil
end
UI.SetBounds = SetBounds

-- Ends a corner drag: the size is clamped (needed when the client has no resize bounds), laid out at once
-- and saved with the position.
function UI:StopSizing()
  local f = self.frame
  if not (f and f.isSizing) then return end
  f:StopMovingOrSizing()
  f.isSizing = false
  local w, h = f:GetWidth(), f:GetHeight()
  local cw, ch = UI.ClampSize(w, h)
  if cw ~= w or ch ~= h then f:SetSize(cw, ch) end
  self:Layout()
  self:SaveGeometry()
end

-- Right-click on the grip: back to the default size (the top-left corner stays).
function UI:ResetSize()
  local f = self.frame
  if not f then return end
  PinTopLeft(f)
  f:SetSize(UI.ClampSize(DEFAULT_W, DEFAULT_H))
  self:Layout()
  self:SaveGeometry()
end

-- Bottom-right resize grip. No installed Forever addon uses a native grip template (PanelResizeButtonTemplate
-- appears nowhere under AddOns), so it is a small button with the chat frame's size-grabber art, as
-- GearQuestForever Tracker.lua:1363-1368 / CraftersJournal UI.lua:200-204 / ForeverLFG_GroupQuest
-- QuestMatchesUI.lua:435-437 do, and StartSizing("BOTTOMRIGHT") (GearQuestForever Tracker.lua:1147).
local GRIP_ART = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local function CreateResizeGrip(f)
  if not (f.SetResizable and f.StartSizing and pcall(f.SetResizable, f, true)) then return nil end
  UI.boundsVia = SetBounds(f)
  local g = CreateFrame("Button", nil, f)
  g:SetSize(16, 16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  if g.SetNormalTexture then g:SetNormalTexture(GRIP_ART .. "Up") end
  if g.SetHighlightTexture then g:SetHighlightTexture(GRIP_ART .. "Highlight") end
  if g.SetPushedTexture then g:SetPushedTexture(GRIP_ART .. "Down") end
  g:SetScript("OnMouseDown", Guard("resize grip", function(_, button)
    if button ~= "LeftButton" or f.isSizing then return end
    if f.isMoving then f:StopMovingOrSizing(); f.isMoving = false end
    UI.boundsVia = SetBounds(f) -- the screen size may have changed (UI scale)
    PinTopLeft(f)
    f.isSizing = true
    f:StartSizing("BOTTOMRIGHT")
  end))
  g:SetScript("OnMouseUp", Guard("resize grip", function(_, button)
    if button == "RightButton" and not f.isSizing then UI:ResetSize(); return end
    UI:StopSizing()
  end))
  SetTip(g, "resize grip", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(L.RESIZE_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.RESIZE_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  g:SetScript("OnLeave", GameTooltip_Hide)
  return g
end

---------------------------------------------------------------------------
-- Header strip and view controls
---------------------------------------------------------------------------
-- Sync status dot (K1: replaces the sync text in the header strip). Colour by GCA:SyncState() (Sync.lua); the
-- full status line is in its tooltip.
UI.SYNC_COLORS = { ok = { 0.25, 0.9, 0.25 }, idle = { 1, 0.82, 0 }, paused = { 1, 0.3, 0.3 }, off = { 0.5, 0.5, 0.5 }, noguild = { 0.5, 0.5, 0.5 } }
function UI.SyncState()
  if GCA.SyncState then return GCA:SyncState() end
  return "off"
end
function UI.SyncLine()
  if GCA.SyncStatusLine then return GCA:SyncStatusLine() or "" end
  return L.CMD_SYNC_NOT_LOADED
end
-- K5: a compact label "Guild sync · 9 recorded" (members with a gear record) with the K1 tooltip. K6: no coloured
-- dot any more: the label itself is coloured by the state (coloured text, as Blizzard colours status words).
local function CreateSyncDot(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.text:SetJustifyH("RIGHT")
  SingleLine(b.text)
  function b:Update(recorded)
    self.state = UI.SyncState()
    local c = UI.SYNC_COLORS[self.state] or UI.SYNC_COLORS.off
    self.text:SetTextColor(c[1], c[2], c[3])
    self.color = c
    if type(recorded) == "number" then self.recorded = recorded end
    self.text:SetText(string.format(L.SYNC_LABEL, self.recorded or 0))
    local tw = math.min(TextWidth(self.text), 200) -- K8: 200 (the centred rank bar ends 10 px left of it at 840)
    self.text:SetWidth(tw)
    self:SetWidth(tw)
  end
  SetTip(b, "sync status", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L.SYNC_DOT_TITLE, 1, 1, 1)
    GameTooltip:AddLine(UI.SyncLine(), 1, 1, 1, true)
    GameTooltip:AddLine(L.SYNC_DOT_TIP, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- (i) icon with the scoring source line in its tooltip (K1: replaces the source-line row). An atlas guarded by
-- GetAtlasInfo, else a file only when the client confirms it (GetFileIDFromPath), else the text "(i)".
UI.INFO_ATLAS = "glueannouncementpopup-icon-info"
UI.INFO_FILE = "Interface\\FriendsFrame\\InformationIcon"
local function CreateInfoIcon(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  if SetAtlasSafe(b.tex, UI.INFO_ATLAS) then
    b.kind = "atlas"
  elseif FileOK(UI.INFO_FILE) == true then
    b.tex:SetTexture(UI.INFO_FILE)
    b.kind = "file"
  else
    b.tex:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText("(i)")
    b.kind = "text"
  end
  SetTip(b, "source info", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.SOURCE_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(UI.sourceLine or "", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- Guild-needs search box: InputBoxTemplate (pcall, backdrop fallback; NewEditBox) with ForeverDungeonJournal's
-- search icon / clear button art (Journal.lua:8852-8869) and a placeholder text.
-- K5: also the member list's search (placeholder / tooltip / what to refresh are parameters)
-- K6: the client's SearchBoxTemplate first (the recipe list's own search box: common-search-border-*, magnifying
-- glass, "Search" instructions, clear button; probe; WhatsTraining Crafting\RecipeList.lua:480-484 on Forever), in
-- pcall; our text hook is added to the template's own OnTextChanged (HookScript), so its instructions / clear
-- button keep working. Fallback: the K2 box below.
local function SearchTip(placeholder, tipText)
  return function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(placeholder or L.NEEDS_SEARCH, 1, 1, 1)
    GameTooltip:AddLine(tipText or L.NEEDS_SEARCH_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end
end
local function CreateSearchBox(parent, width, placeholder, tipText, onChange)
  local ok, sb = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
  if ok and sb and type(sb.Instructions) == "table" and sb.HookScript then
    sb:SetSize(width or 230, 20)
    sb.native = true
    sb.Instructions:SetText(placeholder or L.NEEDS_SEARCH)
    sb.placeholder = sb.Instructions
    if sb.SetAutoFocus then sb:SetAutoFocus(false) end
    if sb.SetMaxLetters then sb:SetMaxLetters(40) end
    function sb:Changed()
      if onChange then onChange(self:GetText() or "") end
    end
    sb:HookScript("OnTextChanged", Guard("search", function() sb:Changed() end))
    sb:HookScript("OnHide", function(self) if self.ClearFocus then self:ClearFocus() end end)
    sb:HookScript("OnEnter", Guard("tooltip: search", SearchTip(placeholder, tipText)))
    sb:HookScript("OnLeave", GameTooltip_Hide)
    return sb
  end
  if ok and sb and sb.Hide then sb:Hide() end
  local eb = NewEditBox(parent, width or 230)
  eb:SetMaxLetters(40)
  if eb.SetTextInsets then pcall(eb.SetTextInsets, eb, 16, 18, 0, 0) end
  if TexOK("search") then
    eb.icon = eb:CreateTexture(nil, "OVERLAY")
    eb.icon:SetTexture(UI.TEX.search)
    eb.icon:SetSize(12, 12)
    eb.icon:SetPoint("LEFT", 1, 0)
    eb.icon:SetVertexColor(0.72, 0.70, 0.66)
  end
  eb.placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  eb.placeholder:SetPoint("LEFT", 17, 0)
  eb.placeholder:SetText(placeholder or L.NEEDS_SEARCH)
  SingleLine(eb.placeholder)
  eb.clear = CreateFrame("Button", nil, eb)
  eb.clear:SetSize(14, 14)
  eb.clear:SetPoint("RIGHT", -2, 0)
  if TexOK("clear") then
    eb.clear:SetNormalTexture(UI.TEX.clear)
  else
    eb.clear.text = eb.clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eb.clear.text:SetPoint("CENTER")
    eb.clear.text:SetText("x")
  end
  eb.clear:Hide()
  function eb:Changed()
    local text = self:GetText() or ""
    self.placeholder:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    if onChange then onChange(text) end
  end
  eb.clear:SetScript("OnClick", function()
    eb:SetText("")
    if eb.ClearFocus then eb:ClearFocus() end
    eb:Changed()
  end)
  eb:SetScript("OnTextChanged", Guard("search", function() eb:Changed() end))
  SetTip(eb, "search", SearchTip(placeholder, tipText))
  eb:SetScript("OnLeave", GameTooltip_Hide)
  return eb
end

-- K2: the two views. Tabs under the window (PanelTabButtonTemplate, in pcall, as BugSack sack.lua:518-545 and
-- Spoken UI\Compendium.lua:616-634 make them on Forever); where the template is missing, two plain buttons in
-- the header strip right of the profession selector. The view is never saved: every open starts on guild needs.
UI.VIEWS = { { "needs", "VIEW_NEEDS" }, { "member", "VIEW_MEMBER" } }
local function CreateViewTabs(f, c)
  local tabs, templated = {}, true
  for i in ipairs(UI.VIEWS) do
    local ok, tab = pcall(CreateFrame, "Button", "RavenquillExpeditionCraftFrameTab" .. i, f, "PanelTabButtonTemplate")
    if not (ok and tab) then templated = false; break end
    tabs[i] = tab
  end
  if templated then
    for i, tab in ipairs(tabs) do
      if tab.SetID then tab:SetID(i) end
      tab:SetText(L[UI.VIEWS[i][2]])
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
      if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 3, 0) end
    end
  else
    for _, tab in ipairs(tabs) do tab:Hide() end -- a half-made set
    tabs = {}
    for i, def in ipairs(UI.VIEWS) do
      local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
      b:SetSize(92, 22) -- K8: left of the centred rank bar (60..248 at 840)
      b:SetText(L[def[2]])
      b:SetPoint("TOPLEFT", c, "TOPLEFT", 60 + (i - 1) * 96, -32)
      tabs[i] = b
    end
  end
  for i, tab in ipairs(tabs) do
    tab.view = UI.VIEWS[i][1]
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
  local needs = self.view ~= "member"
  self.needsView:SetShown(needs)
  self.memberView:SetShown(not needs)
  self:PaintTabs()
end

function UI:SetView(view)
  self.view = view == "member" and "member" or "needs"
  if self.frame then
    self:ApplyView()
    self:Refresh()
  end
end

-- K2: a guild-needs row was clicked: that member in the member view, scrolled to the row's slot section. A member
-- in a collapsed group gets the group opened so the selection is visible.
-- K4: in the character sheet the row's slot is selected and the row's craft shown in the cards (sug).
function UI:OpenMember(key, slot, sug)
  self.selected, self.autoKey = key, nil
  for _, e in ipairs(self.lastMembers or {}) do
    if e.key == key and not e.isSelf then
      if e.online then self.collapsed.online = false else self.collapsed.offline = false end
    end
  end
  -- K5: a member search that hides them is cleared
  local ms = self.memberSearch
  local q = ms and tostring(ms:GetText() or ""):lower():match("^%s*(.-)%s*$") or ""
  if q ~= "" and not tostring(key):lower():find(q, 1, true) then ms:SetText(""); ms:Changed() end
  if slot then
    self.sheetFor = tostring(key) .. "|" .. tostring(GCA:SelectedProfession())
    self.sheetSlot, self.sheetAuto, self.sheetPickSug = slot, false, sug
  end
  self:SetView("member")
  local y = self.memberList:FindY(function(d) return d.key == key and d.rowKind == nil end)
  if y then
    local top = self.memberList:Offset()
    if y < top or y + MEMBER_ROW_H > top + (self.memberList.viewH or 0) then self.memberList:ScrollTo(y - MEMBER_ROW_H) end
  end
  if slot and UI.MemberMode() == "list" then
    local secKey = GCA.SECTION_OF[slot] or slot
    local sy = self.sugList:FindY(function(d) return d.rowKind == "section" and d.sec.key == secKey end)
    if sy then self.sugList:ScrollTo(sy) end
  end
end

-- the member list from the last member data (a group header click / the search: no recompute)
function UI:RefreshMemberList()
  local q = self.memberSearch and self.memberSearch:GetText() or ""
  self.memberList:SetData(UI.MemberRows(self.lastMembers or {}, q))
end

-- (K2 name kept) the guild-needs search changed
function UI:SearchChanged()
  if self.searchBox then self.searchBox:Changed() end
end

-- K8: the guild-needs count sits at the bottom of the left list panel (one line, as wide as the panel)
UI.SEARCH_W = LEFT_W - 21 - 90 - 12
function UI:LayoutFilterBar()
  if not (self.needsCount and self.frame) then return end
  self.needsCount:SetWidth(LEFT_W - 20)
end

-- the guild-needs view from the last member data (Core caches the groups; search and the offline toggle
-- only pick from them)
function UI:RefreshNeeds()
  if not (self.needsList and self.frame) then return end
  local prof = GCA:SelectedProfession()
  local s = GCA.db and GCA.db.settings or {}
  local needs = GCA:GuildNeeds(self.lastMembers or {})
  local query = self.searchBox and self.searchBox:GetText() or ""
  local data, crafts, members, offN, all = UI.NeedsRows(needs, query, s.needsOffline)
  -- K8: the selected craft (detail panel): kept while it is listed, else the first (= best) craft
  local sel
  for _, e in ipairs(all) do if e.group.key == UI.needSel then sel = e end end
  sel = sel or all[1]
  UI.needSel = sel and sel.group.key or nil
  self.needsData = data
  self.needsList:SetData(data)
  local who = members == 1 and L.NEEDS_MEMBERS_1 or string.format(L.NEEDS_MEMBERS, members)
  local count
  if prof == "Enchanting" then
    count = crafts == 1 and string.format(L.NEEDS_COUNT_ENCH_1, who) or string.format(L.NEEDS_COUNT_ENCH, crafts, who)
  else
    count = crafts == 1 and string.format(L.NEEDS_COUNT_1, who) or string.format(L.NEEDS_COUNT, crafts, who)
  end
  self.needsMissing = 0
  if GCA:IsBrowse(prof) then
    count = count .. "  " .. C.browse .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r"
  elseif s.showUnlearned then
    -- K7: how many of the listed crafts are recipes you don't know yet (only computed with "Show missing recipes")
    local missing = 0
    for _, e in ipairs(all) do if not e.group.sug.known then missing = missing + 1 end end
    self.needsMissing = missing
    if missing > 0 then
      count = count .. "  ·  " .. C.notLearned .. (missing == 1 and L.NEEDS_MISSING_1 or string.format(L.NEEDS_MISSING, missing)) .. "|r"
    end
  end
  self.needsCount:SetText(count)
  -- the Filter menu's "Include offline members (n)" entry shows this count
  if UI.offlineN ~= offN then
    UI.offlineN = offN
    self:RefreshFilters()
  end
  self:LayoutFilterBar()
  local q = query:match("^%s*(.-)%s*$") or ""
  local empty
  if crafts > 0 then
    empty = ""
  elseif q ~= "" then
    empty = string.format(L.NEEDS_NO_MATCH, q)
  elseif (GCA.knownCount or 0) == 0 and not GCA:IsBrowse(prof) then
    empty = string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof))
  elseif offN > 0 and not s.needsOffline then
    empty = string.format(L.NEEDS_EMPTY_OFFLINE, offN)
  else
    empty = L.NEEDS_EMPTY
  end
  -- K8: the empty text sits in the detail panel (where the craft would be shown)
  self:UpdateCraftDetail(sel, empty)
  local key = tostring(prof)
  if self.needsKey ~= key then
    self.needsKey = key
    self.needsList:ScrollTo(0)
  end
end

-- K5: "Include offline members (n)" (saved in db.settings.needsOffline); K6: a Filter menu entry
function UI:SetNeedsOffline(on)
  if not (GCA.db and GCA.db.settings) then return end
  GCA.db.settings.needsOffline = on and true or false
  self:RefreshNeeds()
  self:RefreshFilters()
end

-- Lays out everything that depends on the window size (J2). K8: both views = the left list panel (fixed width,
-- follows the height) and the detail panel right of it (fills the rest); positions are anchored, only sizes change.
function UI:Layout()
  local f = self.frame
  if not (f and self.sugList) then return end
  local w = math.max(MIN_W, Num(f:GetWidth()) or MIN_W)
  local h = math.max(MIN_H, Num(f:GetHeight()) or MIN_H)
  self.layoutCount = (self.layoutCount or 0) + 1
  self.layoutW, self.layoutH = w, h
  local rw = RightW(w)
  local listH = h + PANEL_TOP - PANEL_BOTTOM
  local dw = rw + 4               -- detail panel width (both views)
  local iw, ih = dw - 12, listH - DETAIL_HEAD - 6 -- the member detail's list / sheet area
  self.memberInset:SetSize(LEFT_W, listH)
  UI.memberListW = LEFT_W - 30
  self.memberList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, true) -- K5: below the member search
  self.memberDetail:SetSize(dw, listH)
  self.nameText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)  -- room for the spec button on its right
  self.subText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)
  self.sugHeader:SetWidth(dw - 34 - UI.TOGGLE_W - 22) -- right of the (i) icon, left of the K4 view switch
  self.sugInset:SetSize(iw, ih)
  UI.listW = iw - 34
  self.sugList:Resize(iw - 34, ih - 10, true)
  self.emptyText:SetWidth(iw - 60)
  -- K4: the character sheet fills the same area (4 px inside its edges)
  self.sheet:SetSize(iw, ih)
  self:LayoutSheet(iw, ih)
  -- K8: guild needs = the list panel (left) + the craft detail panel (right)
  self.needsInset:SetSize(LEFT_W, listH)
  UI.needsW = LEFT_W - 30
  self.needsList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, true)
  local nd = self.needDetail
  nd:SetSize(dw, listH)
  nd.w, nd.h = dw, listH
  self:UpdateCraftDetail(nd.entry, nd.empty:GetText())
  self:LayoutFilterBar()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function UI:Create()
  local f = NewWindow("RavenquillExpeditionCraftFrame", "Guild Craft Advisor")
  self.frame = f
  self:RestoreGeometry() -- J2: saved size/position (clamped), else 980x640 centred
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  -- ESC closes the window, except while the whisper editor is open (review L-1; it puts the window back)
  SetEscCloses("RavenquillExpeditionCraftFrame", not (self.whisperEditor and self.whisperEditor:IsShown()))
  f:Hide()

  -- everything we draw lives on one content frame above the art (H1 frame levels)
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  f.content = c
  ApplyLevels(f)
  self.view = "needs"

  f:SetScript("OnShow", function()
    -- U1: each open starts on the best guildie again, unless you picked someone yourself
    if UI.selected ~= nil and UI.selected == UI.autoKey then UI.selected = nil end
    -- K2: every open starts on guild needs with the groups collapsed (nothing of this is remembered);
    -- K5: the online group open, the crafts collapsed
    UI.view = "needs"
    UI.collapsed.online, UI.collapsed.offline = false, true
    UI.needsCollapsed, UI.needSel = {}, nil -- K8: every slot category open, the best craft selected
    UI:ApplyView()
    RavenquillExpedition:RequestRoster()
    GCA:RefreshKnown()
    UI:Refresh()
  end)

  -- Close with a plain Hide() so it works in combat (ForeverDungeonJournal Favourites.lua:553-560).
  if type(f.CloseButton) == "table" and f.CloseButton.SetScript then
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
  end

  -- Drag bar between the portrait and the close button (QuestieOptionsWindow.lua:38-61); J2: position saved.
  local dragBar = CreateFrame("Frame", nil, c)
  dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", f.templated and 55 or 0, 0)
  -- fallback close button sits at -10 and is 32 wide: keep the bar off it
  dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", f.templated and -30 or -44, 0)
  dragBar:SetHeight(24)
  dragBar:EnableMouse(true)
  dragBar:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and not f.isMoving and not f.isSizing then f:StartMoving(); f.isMoving = true end
  end)
  dragBar:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and f.isMoving then f:StopMovingOrSizing(); f.isMoving = false; UI:SaveGeometry() end
  end)
  self.dragBar = dragBar
  f:HookScript("OnHide", function()
    if f.isMoving then f:StopMovingOrSizing(); f.isMoving = false; UI:SaveGeometry() end
    UI:StopSizing()
  end)
  -- K17: the U6 Shift re-render of our suggestion tooltip is gone (item tooltips are plain Blizzard ones now)

  -- K8: the rank bar centred right under the title (the profession window's RankBar, with its dropdown arrow); the
  -- sync status ("Guild sync · n recorded", coloured by state) on the right of the same line.
  self.profButton, self.profPopup = CreateProfessionPicker(c, f)
  self.profButton:SetPoint("TOP", f, "TOP", 0, -27)
  self.syncDot = CreateSyncDot(c)
  self.syncDot:SetPoint("TOPRIGHT", -20, -36)

  -- Sizes below are placeholders for the minimum size; UI:Layout() sets the real ones (end of Create, J2).
  local listH = MIN_H + PANEL_TOP - PANEL_BOTTOM
  local painted = f.gcaArt and f.gcaArt.painted or false
  local rw = RightW(MIN_W)

  -- K8: guild-needs view (the default) = the recipe list (search | Filter on top, slot categories + craft rows, the
  -- count at the bottom) and the craft's detail panel on the right
  local nv = CreateFrame("Frame", nil, c)
  nv:SetAllPoints(c)
  self.needsView = nv
  local ni = NewInset(nv, painted)
  ni:SetPoint("TOPLEFT", 10, PANEL_TOP)
  ni:SetSize(LEFT_W, listH)
  self.needsInset = ni
  self.searchBox = CreateSearchBox(ni, UI.SEARCH_W, L.NEEDS_SEARCH, L.NEEDS_SEARCH_TIP, function() UI:RefreshNeeds() end)
  self.searchBox:SetPoint("TOPLEFT", ni, "TOPLEFT", 13, -8)
  self.filterButton, self.filterPopup = P.CreateFilterMenu(ni, f)
  self.filterButton:SetPoint("TOPRIGHT", ni, "TOPRIGHT", -8, -9)
  UI.needsW = LEFT_W - 30
  self.needsList = CreateScrollList(ni, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, NEED_ROW_H, CreateCraftGroupRow, UpdateCraftGroupRow,
    UI.NEEDS_KINDS)
  self.needsList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(ni, self.needsList)
  self.needsCount = ni:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.needsCount:SetPoint("BOTTOMLEFT", ni, "BOTTOMLEFT", 10, 6)
  self.needsCount:SetWidth(LEFT_W - 20)
  self.needsCount:SetJustifyH("LEFT")
  self.needsCount:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(self.needsCount)
  local nd = UI.CreateCraftDetail(nv)
  nd:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  nd:SetSize(rw + 4, listH)
  nd.w, nd.h = rw + 4, listH
  self.needDetail = nd
  self.needsEmpty = nd.empty

  -- K2: member view: the member list (left) and the selected member in the detail panel (right)
  local mv = CreateFrame("Frame", nil, c)
  mv:SetAllPoints(c)
  self.memberView = mv
  local left = NewInset(mv, painted)
  left:SetPoint("TOPLEFT", 10, PANEL_TOP)
  left:SetSize(LEFT_W, listH)
  self.memberInset = left
  -- K5: a member search on top of the list; K6: and the Filter dropdown at its right, as the recipe list has them
  -- (SearchBox TOPLEFT 13,-8; FilterDropdown TOPRIGHT -8,-9, probe)
  self.memberSearch = CreateSearchBox(left, UI.SEARCH_W, L.MEMBER_SEARCH, L.MEMBER_SEARCH_TIP, function() UI:RefreshMemberList() end)
  self.memberSearch:SetPoint("TOPLEFT", left, "TOPLEFT", 13, -8)
  self.memberFilter, self.memberFilterPopup = P.CreateFilterMenu(left, f)
  self.memberFilter:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -9)
  UI.memberListW = LEFT_W - 30
  self.memberList = CreateScrollList(left, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, MEMBER_ROW_H, CreateMemberRow, UpdateMemberRow,
    { group = { create = CreateGroupRow, update = UpdateGroupRow, height = GROUP_ROW_H } })
  self.memberList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(left, self.memberList)

  -- K8: the member's detail panel (detailBorder frame, the page art behind): name, sub-line, spec dropdown, (i) +
  -- list header + view dropdown, then the character sheet or the list
  local md = CreateFrame("Frame", nil, mv)
  md:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  md:SetSize(rw + 4, listH)
  UI.AddDetailBorder(md)
  self.memberDetail = md
  self.nameText = md:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  self.nameText:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -10)
  self.nameText:SetJustifyH("LEFT")
  SingleLine(self.nameText)
  self.subText = md:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.subText:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -32)
  self.subText:SetJustifyH("LEFT")
  SingleLine(self.subText) -- L2
  self.specButton, self.specPopup = P.CreateSpecPicker(md, f)
  self.specButton:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -8)

  -- suggestions: (i) icon with the scoring source (K1), the list header, then the list
  self.infoIcon = CreateInfoIcon(md)
  self.infoIcon:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -52)
  self.sugHeader = md:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.sugHeader:SetPoint("TOPLEFT", md, "TOPLEFT", 34, -54)
  self.sugHeader:SetJustifyH("LEFT")
  SingleLine(self.sugHeader)
  -- K4: the variant switch at the top right of the member panel, on the list header's line (K6: a dropdown)
  self.modeToggle = P.CreateModeSwitch(md)
  self.modeToggle:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -50)
  local right = CreateFrame("Frame", nil, md) -- K8: no own background / border: the detail panel frames it
  right:SetPoint("TOPLEFT", md, "TOPLEFT", 6, -DETAIL_HEAD)
  right:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sugInset = right
  self.sugList = CreateScrollList(right, rw - 42, listH - DETAIL_HEAD - 16, UI.CardHeight, CreateCardRow, UpdateCardRow,
    { section = { create = CreateSectionRow, update = UpdateSectionRow, height = SECTION_H },
      fold = { create = CreateFoldRow, update = UpdateFoldRow, height = FoldHeight } })
  self.sugList:SetPoint("TOPLEFT", 5, -5)
  self.emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.emptyText:SetPoint("CENTER")
  self.emptyText:SetWidth(rw - 68)
  -- K4: the character sheet, in the same area as the list (one of the two is shown)
  self.sheet = CreateSheet(right)
  self.sheet:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0) -- K8: the detail panel's padding replaces the 4 px inset
  self.sheet:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sheet:Hide()
  RaiseInsetBorder(md, self.sugList)

  -- bottom bar. K5: the "Inspect target" / "Scan group" buttons are gone (gear is read automatically; the
  -- /gca inspect and /gca scan commands stay). K6: the K1 "Options" button + popup are gone: the toggles are in
  -- the Filter dropdowns, the leveling-bonus slider is here.
  self.filters = { { button = self.filterButton, popup = self.filterPopup }, { button = self.memberFilter, popup = self.memberFilterPopup } }
  self.survival = CreateSurvivalSlider(c)
  self.survival:SetPoint("BOTTOMLEFT", 18, 13)
  -- K11 (user): with the native Filter menu the bonus is set there (submenu); the bottom slider stays only as the
  -- fallback for the non-native popup. The "?" help button is gone (/gca help lists the commands).
  if self.filterButton and self.filterButton.native then self.survival:Hide() end

  -- K2: view tabs (under the window; fallback: buttons in the header strip)
  self.tabs, self.tabsTemplated = CreateViewTabs(f, c)

  -- J2: resize grip in the bottom-right corner, above our content; relayout throttled while dragging
  self.resizeGrip = CreateResizeGrip(f)
  f.resizeGrip = self.resizeGrip
  if self.resizeGrip and self.resizeGrip.SetFrameLevel then
    self.resizeGrip:SetFrameLevel((c:GetFrameLevel() or 0) + 10)
  end
  self:ApplyView()
  self:ApplyMemberMode()
  self:Layout()
  f:HookScript("OnSizeChanged", function()
    if UI.layoutPending then return end
    UI.layoutPending = true
    C_Timer.After(UI.RESIZE_THROTTLE, function()
      UI.layoutPending = false
      UI:Layout()
    end)
  end)
end

function UI:Toggle()
  if not self.frame then self:Create() end
  self.frame:SetShown(not self.frame:IsShown())
end

-- U1: the best guildie (not you) with an upgrade you can craft; the list is already sorted that way.
function UI.PickDefault(members)
  for _, e in ipairs(members) do
    if not e.isSelf and e.best then return e end
  end
end

function UI:Refresh()
  pcall(UI.UpdateDetailCards)
  local f = self.frame
  if not (f and f:IsShown() and GCA.db) then return end

  if self.survival then self.survival:Sync() end
  self:RefreshFilters()

  local prof = GCA:SelectedProfession()
  local browse = GCA:IsBrowse(prof)
  -- K5: skill bar "Leatherworking 150 / 225" (browse: the name + "(browse)", empty bar)
  local rank, maxRank = GCA:GetSkill(prof)
  if browse then
    self.profButton:SetSkill(ProfName(prof) .. " " .. C.browse .. L.PROF_BROWSE_TAG .. "|r")
  elseif rank then
    self.profButton:SetSkill(string.format(L.PROF_SKILL_BAR, ProfName(prof), rank, maxRank or 300), rank, maxRank or 300, prof)
  else
    self.profButton:SetSkill(ProfName(prof))
  end
  if self.profPopup and self.profPopup:IsShown() then self.profPopup:Fill() end
  local pinfo = GCA.PROF_BY_KEY[prof]
  if f.templated and f.SetPortraitToAsset and pinfo and self.portraitFor ~= prof then
    SafeCall(f.SetPortraitToAsset, f, pinfo.icon)
    self.portraitFor = prof
  end

  local members = GCA:GetMemberList()
  local current
  for _, e in ipairs(members) do if e.key == self.selected then current = e end end
  -- U1: nothing picked yet (or the automatic pick has no upgrade): open on the best guildie, you stay listed
  local auto = current == nil or self.selected == self.autoKey
  if auto and not (current and current.best and not current.isSelf) then
    current = UI.PickDefault(members) or current or members[1]
    self.selected = current and current.key
    self.autoKey = self.selected
  end
  self.current = current
  self.lastMembers = members
  self.memberList:SetData(UI.MemberRows(members, self.memberSearch and self.memberSearch:GetText() or ""))
  local recorded = 0
  for _, e in ipairs(members) do if e.member and not e.isSelf then recorded = recorded + 1 end end
  self.syncDot:Update(recorded)
  -- K2: the guild-needs list only while it is shown (switching to it refreshes)
  if self.view ~= "member" then self:RefreshNeeds() end

  if not current then
    -- review L-4: nothing of the previously shown member may stay on screen
    self.nameText:SetText(L.NO_MEMBERS)
    self.subText:SetText("")
    self.sugHeader:SetText("")
    self.emptyText:SetText("")
    self.sugList:SetData({})
    self.sheet:Hide()
    self.specButton:Hide()
    if self.specPopup then self.specPopup:Hide() end
    UI.sourceLine = ""
    self.infoIcon:Hide()
    return
  end
  self.specButton:SetShown(current.class ~= nil)
  self.specButton:SetClass(current.class)
  if current.spec then
    self.specButton:SetText(GCA:SpecName(current.class, current.spec) .. (current.specAssumed and " *" or ""))
  else
    self.specButton:SetText(C.warn .. L.SPEC_PICK .. "|r")
  end
  if self.specPopup then
    if self.specPopup:IsShown() and self.specPopup.forKey ~= current.key then self.specPopup:Hide() end
    self.specPopup.forKey = current.key
  end

  self.nameText:SetText(Hex(ClassColor(current.class)) .. current.key .. "|r")
  local m = current.member
  local status = current.isSelf and L.STATUS_YOU
    or (current.online and (C.upgrade .. G("FRIENDS_LIST_ONLINE") .. "|r") or (C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"))
  if m then
    self.subText:SetText(string.format(L.SUB_LINE, G("LEVEL"), tostring(current.level or "?"), ClassName(current.class), status,
      SourceText(m), Ago(m.time)))
  else
    -- L2: the "not inspected" hint lives in the empty state below
    self.subText:SetText(string.format(L.SUB_LINE_NOGEAR, G("LEVEL"), tostring(current.level or "?"), ClassName(current.class), status))
  end

  local list = current.suggestions or {}
  local what = prof == "Enchanting" and L.HEAD_ENCHANTS or L.HEAD_CRAFTS
  if browse then
    self.sugHeader:SetText(string.format(what, #list) .. " " .. C.browse .. "– " .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r")
  else
    self.sugHeader:SetText(string.format(what, #list))
  end
  -- K1: the scoring source is the (i) icon's tooltip
  UI.sourceLine = current.weights and GCA:SourceLine(current.weights) or ""
  self.infoIcon:SetShown(UI.sourceLine ~= "")
  -- why the list is empty (empty-state text; K4: in the character sheet it goes into the middle panel)
  local why = ""
  if not m then
    why = L.EMPTY_NOGEAR
  elseif current.state == "no-spec" then
    why = L.EMPTY_NOSPEC
  elseif current.state == "no-level" then
    why = L.EMPTY_NOLEVEL
  elseif current.state == "no-weights" or current.state == "no-class" then
    why = L.EMPTY_NOWEIGHTS
  elseif #list == 0 and (current.pending or 0) > 0 then
    why = L.EMPTY_LOADING
  elseif #list == 0 and browse then
    why = string.format(L.EMPTY_BROWSE, ProfName(prof))
  elseif #list == 0 and (GCA.knownCount or 0) == 0 then
    why = string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof))
  elseif #list == 0 then
    why = prof == "Enchanting" and L.EMPTY_ENCHANT or L.EMPTY_NONE
  end
  -- K4: only the shown variant is filled. The sheet needs the slot sections (gear compared); without them
  -- (no gear, no spec, loading, ...) the empty-state text explains why, as in the list.
  if UI.MemberMode() == "sheet" then
    self.sugList:Hide()
    if list.sections then
      self.sheet:Show()
      self:UpdateSheet(current, list, prof, why)
      self.emptyText:SetText("")
    else
      self.sheet:Hide()
      self.emptyText:SetText(why)
    end
    return
  end
  self.sheet:Hide()
  self.sugList:Show()
  self.sugList:SetData(UI.SectionRows(list)) -- grouped per slot
  -- the list is now always longer than the view; another member or profession starts at the top
  local listKey = tostring(current.key) .. "|" .. tostring(prof)
  if self.listKey ~= listKey then
    self.listKey = listKey
    self.sugList:ScrollTo(0)
  end
  self.emptyText:SetText(#list == 0 and why or "")
end

-- Error reporter: Guard is defined at the top of this file.
UI.Refresh = Guard("UI:Refresh", UI.Refresh)
UI.Toggle = Guard("UI:Toggle", UI.Toggle)
UI.Layout = Guard("UI:Layout", UI.Layout)
UI.StopSizing = Guard("UI:StopSizing", UI.StopSizing)
UI.OpenWhisperEditor = Guard("UI:OpenWhisperEditor", UI.OpenWhisperEditor)
UI.RefreshNeeds = Guard("UI:RefreshNeeds", UI.RefreshNeeds)
UI.RefreshMemberList = Guard("UI:RefreshMemberList", UI.RefreshMemberList)
UI.OpenMember = Guard("UI:OpenMember", UI.OpenMember)
UI.SetView = Guard("UI:SetView", UI.SetView)
UI.SetMemberMode = Guard("UI:SetMemberMode", UI.SetMemberMode)
UI.SelectSheetSlot = Guard("UI:SelectSheetSlot", UI.SelectSheetSlot)
UI.PickSheetRow = Guard("UI:PickSheetRow", UI.PickSheetRow)
UI.UpdateSheet = Guard("UI:UpdateSheet", UI.UpdateSheet)
UI.LayoutSheet = Guard("UI:LayoutSheet", UI.LayoutSheet)
UI.SetNeedsOffline = Guard("UI:SetNeedsOffline", UI.SetNeedsOffline)
