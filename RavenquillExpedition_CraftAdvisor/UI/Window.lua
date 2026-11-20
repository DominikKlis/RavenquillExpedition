local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local Label = P.Label
local G, MIN_W, MIN_H = P.G, P.MIN_W, P.MIN_H
local LEFT_W, RIGHT_X, RightW = P.LEFT_W, P.RIGHT_X, P.RightW
local PANEL_TOP, PANEL_BOTTOM, DETAIL_HEAD = P.PANEL_TOP, P.PANEL_BOTTOM, P.DETAIL_HEAD
local MEMBER_ROW_H = P.MEMBER_ROW_H
local MEMBER_LIST_TOP, COUNT_H, C, SUB_TINT = P.MEMBER_LIST_TOP, P.COUNT_H, P.C, P.SUB_TINT
local Guard = P.Guard
local ProfName = P.ProfName
local NewInset, RaiseInsetBorder = P.NewInset, P.RaiseInsetBorder
local CreateScrollList = P.CreateScrollList
local Num = P.Num
local CreateSearchBox = P.CreateSearchBox
local ViewKey = P.ViewKey

UI.VIEWS = { { "member", "VIEW_MEMBER" }, { "needs", "VIEW_NEEDS" } }
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
    tab:SetText(L[UI.VIEWS[i][2]])
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 3, 0) end
  end
  return tabs
end

local function CreateViewTabs(f, c)
  local tabs = CreateTemplatedTabs(f)
  local templated = tabs ~= nil
  if not templated then
    tabs = {}
    for i, def in ipairs(UI.VIEWS) do
      local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
      b:SetSize(92, 22)
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

local function ExpandGroupOf(self, key)
  for _, e in ipairs(self.lastMembers or {}) do
    if e.key == key and not e.isSelf then
      if e.online then self.collapsed.online = false else self.collapsed.offline = false end
    end
  end
end

local function ClearSearchHiding(self, key)
  local ms = self.memberSearch
  if ms and not GCA.MatchesSearch(key, ms:GetText()) then ms:SetText(""); ms:Changed() end
end

local function ScrollMemberIntoView(self, key)
  local list = self.memberList
  local y = list:FindY(function(d) return d.key == key and d.rowKind == nil end)
  if not y then return end
  local top = list:Offset()
  if y < top or y + MEMBER_ROW_H > top + (list.viewH or 0) then list:ScrollTo(y - MEMBER_ROW_H) end
end

local function ScrollToSlotSection(self, slot)
  local secKey = GCA.SECTION_OF[slot] or slot
  local sy = self.sugList:FindY(function(d) return d.rowKind == "section" and d.sec.key == secKey end)
  if sy then self.sugList:ScrollTo(sy) end
end

function UI:SelectMember(key, slot, pick)
  self:Select(key)
  if slot then self:FocusSheet(key, slot, pick) end
end

function UI:OpenMember(key, slot, sug)
  self:SelectMember(key, slot, sug)
  ExpandGroupOf(self, key)
  ClearSearchHiding(self, key)
  self:SetView("member")
  ScrollMemberIntoView(self, key)
  if slot and UI.MemberMode() == "list" then ScrollToSlotSection(self, slot) end
end

function UI:RefreshMemberList()
  local q = self.memberSearch and self.memberSearch:GetText() or ""
  self.memberList:SetData(UI.MemberRows(self.lastMembers or {}, q))
end

UI.SEARCH_W = LEFT_W - 21 - 90 - 12
function UI:LayoutFilterBar()
  if not (self.needsCount and self.frame) then return end
  self.needsCount:SetWidth(LEFT_W - 20)
end

local function Trim(s)
  return s:match("^%s*(.-)%s*$") or ""
end

local function FindNeedSelection(all)
  local sel
  for _, e in ipairs(all) do if e.group.key == UI.needSel then sel = e end end
  return sel or all[1]
end

local function NeedsCountText(prof, crafts, members)
  local who = members == 1 and L.NEEDS_MEMBERS_1 or string.format(L.NEEDS_MEMBERS, members)
  if prof == "Enchanting" then
    return crafts == 1 and string.format(L.NEEDS_COUNT_ENCH_1, who) or string.format(L.NEEDS_COUNT_ENCH, crafts, who)
  end
  return crafts == 1 and string.format(L.NEEDS_COUNT_1, who) or string.format(L.NEEDS_COUNT, crafts, who)
end

local function NeedsCountSuffix(prof, settings, all)
  if GCA:IsBrowse(prof) then return "  " .. C.browse .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r" end
  if not settings.showUnlearned then return "" end
  local missing = 0
  for _, e in ipairs(all) do if not e.group.sug.known then missing = missing + 1 end end
  if missing == 0 then return "" end
  return "  ·  " .. C.notLearned .. (missing == 1 and L.NEEDS_MISSING_1 or string.format(L.NEEDS_MISSING, missing)) .. "|r"
end

local function NeedsEmptyText(prof, crafts, q, offN, settings)
  if crafts > 0 then return "" end
  if q ~= "" then return string.format(L.NEEDS_NO_MATCH, q) end
  if GCA:KnownCount(prof) == 0 and not GCA:IsBrowse(prof) then
    return string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof))
  end
  if offN > 0 and not settings.needsOffline then return string.format(L.NEEDS_EMPTY_OFFLINE, offN) end
  return L.NEEDS_EMPTY
end

function UI:RefreshNeeds()
  if not (self.needsList and self.frame) then return end
  local prof = GCA:SelectedProfession()
  local s = GCA.db and GCA.db.settings or {}
  local needs = GCA:GuildNeeds(self.lastMembers or {})
  local query = self.searchBox and self.searchBox:GetText() or ""
  local data, crafts, members, offN, all = UI.NeedsRows(needs, query, s.needsOffline)
  local sel = FindNeedSelection(all)
  UI.needSel = sel and sel.group.key or nil
  self.needsList:SetData(data)
  self.needsCount:SetText(NeedsCountText(prof, crafts, members) .. NeedsCountSuffix(prof, s, all))
  if UI.offlineN ~= offN then
    UI.offlineN = offN
    self:RefreshFilters()
  end
  self:LayoutFilterBar()
  self:UpdateCraftDetail(sel, NeedsEmptyText(prof, crafts, Trim(query), offN, s))
  local key = tostring(prof)
  if self.needsKey ~= key then
    self.needsKey = key
    self.needsList:ScrollTo(0)
  end
end

function UI:SetNeedsOffline(on)
  if not (GCA.db and GCA.db.settings) then return end
  GCA:SetSetting("needsOffline", on and true or false)
  self:RefreshNeeds()
  self:RefreshFilters()
end

function UI:Layout()
  local f = self.frame
  if not (f and self.sugList) then return end
  local w = math.max(MIN_W, Num(f:GetWidth()) or MIN_W)
  local h = math.max(MIN_H, Num(f:GetHeight()) or MIN_H)
  self.layoutCount = (self.layoutCount or 0) + 1
  self.layoutW, self.layoutH = w, h
  local rw = RightW(w)
  local listH = h + PANEL_TOP - PANEL_BOTTOM
  local dw = rw + 4
  local iw, ih = dw - 12, listH - DETAIL_HEAD - 6
  self.memberInset:SetSize(LEFT_W, listH)
  self.memberList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, true)
  self.memberDetail:SetSize(dw, listH)
  self.nameText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)
  self.subText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)
  self.sugHeader:SetWidth(dw - 34 - UI.TOGGLE_W - 22)
  self.sugInset:SetSize(iw, ih)
  self.sugList:Resize(iw - 34, ih - 10, true)
  self.emptyText:SetWidth(iw - 60)
  self.sheet:SetSize(iw, ih)
  self:LayoutSheet(iw, ih)
  self.needsInset:SetSize(LEFT_W, listH)
  self.needsList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, true)
  local nd = self.needDetail
  nd:SetSize(dw, listH)
  nd.w, nd.h = dw, listH
  self:UpdateCraftDetail(nd.entry, nd.empty:GetText())
  self:LayoutFilterBar()
end

local Build = {}

function Build.OnShow()
  if UI.selected ~= nil and UI.selected == UI.autoKey then UI:Select(nil) end
  UI.view = "member"
  UI.collapsed.online, UI.collapsed.offline = false, true
  UI.needsCollapsed, UI.needSel = {}, nil
  UI:ApplyView()
  RavenquillExpedition:RequestRoster()
  GCA:OnAdvisorShown()
  UI:Refresh()
end

function Build.StopMoving(f)
  f:StopMovingOrSizing()
  f.isMoving = false
  UI:SaveGeometry()
end

function Build.DragBar(f, c)
  local dragBar = CreateFrame("Frame", nil, c)
  dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", f.templated and 55 or 0, 0)
  dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", f.templated and -30 or -44, 0)
  dragBar:SetHeight(24)
  dragBar:EnableMouse(true)
  dragBar:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and not f.isMoving and not f.isSizing then f:StartMoving(); f.isMoving = true end
  end)
  dragBar:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and f.isMoving then Build.StopMoving(f) end
  end)
  return dragBar
end

function Build.Window(self)
  local f = P.NewWindow("RavenquillExpeditionCraftFrame", L.ADDON_TITLE)
  self.frame = f
  self:RestoreGeometry()
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  P.SetEscCloses("RavenquillExpeditionCraftFrame", not (self.whisperEditor and self.whisperEditor:IsShown()))
  f:Hide()
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  f.content = c
  P.ApplyLevels(f)
  return f, c
end

function Build.ListInset(view, painted, listH)
  local inset = NewInset(view, painted)
  inset:SetPoint("TOPLEFT", 10, PANEL_TOP)
  inset:SetSize(LEFT_W, listH)
  return inset
end

function Build.SearchAndFilter(inset, f, label, tip, onChange)
  local search = CreateSearchBox(inset, UI.SEARCH_W, label, tip, onChange)
  search:SetPoint("TOPLEFT", inset, "TOPLEFT", 13, -8)
  local filter, popup = P.CreateFilterMenu(inset, f)
  filter:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -9)
  return search, filter, popup
end

function Build.NeedsCount(ni)
  local fs = Label(ni, "GameFontHighlightSmall")
  fs:SetPoint("BOTTOMLEFT", ni, "BOTTOMLEFT", 10, 6)
  fs:SetWidth(LEFT_W - 20)
  fs:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  return fs
end

function Build.NeedsView(self, f, c, painted, listH, rw)
  local nv = CreateFrame("Frame", nil, c)
  nv:SetAllPoints(c)
  self.needsView = nv
  local ni = Build.ListInset(nv, painted, listH)
  self.needsInset = ni
  self.searchBox, self.filterButton, self.filterPopup = Build.SearchAndFilter(ni, f, L.NEEDS_SEARCH, L.NEEDS_SEARCH_TIP,
    function() UI:RefreshNeeds() end)
  self.needsList = CreateScrollList(ni, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, UI.NEEDS_KINDS)
  self.needsList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(ni, self.needsList)
  self.needsCount = Build.NeedsCount(ni)
  local nd = UI.CreateCraftDetail(nv)
  nd:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  nd:SetSize(rw + 4, listH)
  nd.w, nd.h = rw + 4, listH
  self.needDetail = nd
  self.needsEmpty = nd.empty
end

function Build.MemberListPanel(self, f, mv, painted, listH)
  local left = Build.ListInset(mv, painted, listH)
  self.memberInset = left
  self.memberSearch, self.memberFilter, self.memberFilterPopup = Build.SearchAndFilter(left, f, L.MEMBER_SEARCH,
    L.MEMBER_SEARCH_TIP, function() UI:RefreshMemberList() end)
  self.memberList = CreateScrollList(left, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5,
    { default = { create = P.CreateMemberRow, update = P.UpdateMemberRow, height = MEMBER_ROW_H },
      group = { create = P.CreateGroupRow, update = P.UpdateGroupRow, height = P.GROUP_ROW_H } })
  self.memberList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(left, self.memberList)
end

function Build.LeftText(md, template, x, y)
  local fs = Label(md, template)
  fs:SetPoint("TOPLEFT", md, "TOPLEFT", x, y)
  return fs
end

function Build.MemberHeader(self, f, md)
  self.nameText = Build.LeftText(md, "GameFontNormalLarge", 14, -10)
  self.subText = Build.LeftText(md, "GameFontHighlightSmall", 14, -32)
  self.specButton, self.specPopup = P.CreateSpecPicker(md, f)
  self.specButton:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -8)
  self.infoIcon = P.CreateInfoIcon(md)
  self.infoIcon:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -52)
  self.sugHeader = Build.LeftText(md, "GameFontNormal", 34, -54)
  self.modeToggle = P.CreateModeSwitch(md)
  self.modeToggle:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -50)
end

function Build.SuggestionPanel(self, md, listH, rw)
  local right = CreateFrame("Frame", nil, md)
  right:SetPoint("TOPLEFT", md, "TOPLEFT", 6, -DETAIL_HEAD)
  right:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sugInset = right
  self.sugList = CreateScrollList(right, rw - 42, listH - DETAIL_HEAD - 16,
    { default = { create = P.CreateCardRow, update = P.UpdateCardRow, height = UI.CardHeight },
      section = { create = P.CreateSectionRow, update = P.UpdateSectionRow, height = P.SECTION_H },
      fold = { create = P.CreateFoldRow, update = P.UpdateFoldRow, height = P.FoldHeight } })
  self.sugList:SetPoint("TOPLEFT", 5, -5)
  self.emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.emptyText:SetPoint("CENTER")
  self.emptyText:SetWidth(rw - 68)
  self.sheet = P.CreateSheet(right)
  self.sheet:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
  self.sheet:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sheet:Hide()
  RaiseInsetBorder(md, self.sugList)
end

function Build.MemberView(self, f, c, painted, listH, rw)
  local mv = CreateFrame("Frame", nil, c)
  mv:SetAllPoints(c)
  self.memberView = mv
  Build.MemberListPanel(self, f, mv, painted, listH)
  local md = CreateFrame("Frame", nil, mv)
  md:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  md:SetSize(rw + 4, listH)
  UI.AddDetailBorder(md)
  self.memberDetail = md
  Build.MemberHeader(self, f, md)
  Build.SuggestionPanel(self, md, listH, rw)
end

function Build.ResizeGrip(self, f, c)
  self.resizeGrip = P.CreateResizeGrip(f)
  f.resizeGrip = self.resizeGrip
  if self.resizeGrip and self.resizeGrip.SetFrameLevel then
    self.resizeGrip:SetFrameLevel((c:GetFrameLevel() or 0) + 10)
  end
end

function Build.ScheduleLayout()
  if UI.layoutPending then return end
  UI.layoutPending = true
  C_Timer.After(UI.RESIZE_THROTTLE, function()
    UI.layoutPending = false
    UI:Layout()
  end)
end

function UI:Create()
  local f, c = Build.Window(self)
  self.view = "member"
  f:SetScript("OnShow", Build.OnShow)
  if type(f.CloseButton) == "table" and f.CloseButton.SetScript then
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
  end
  self.dragBar = Build.DragBar(f, c)
  f:HookScript("OnHide", function()
    if f.isMoving then Build.StopMoving(f) end
    UI:StopSizing()
  end)
  self.profButton, self.profPopup = P.CreateProfessionPicker(c, f)
  self.profButton:SetPoint("TOP", f, "TOP", 0, -27)
  self.syncDot = P.CreateSyncDot(c)
  self.syncDot:SetPoint("TOPRIGHT", -20, -36)
  local listH = MIN_H + PANEL_TOP - PANEL_BOTTOM
  local painted = f.gcaArt and f.gcaArt.painted or false
  local rw = RightW(MIN_W)
  Build.NeedsView(self, f, c, painted, listH, rw)
  Build.MemberView(self, f, c, painted, listH, rw)
  self.filters = { { button = self.filterButton, popup = self.filterPopup }, { button = self.memberFilter, popup = self.memberFilterPopup } }
  self.survival = P.CreateSurvivalSlider(c)
  self.survival:SetPoint("BOTTOMLEFT", 18, 13)
  if self.filterButton and self.filterButton.native then self.survival:Hide() end
  self.tabs, self.tabsTemplated = CreateViewTabs(f, c)
  Build.ResizeGrip(self, f, c)
  self:ApplyView()
  self:ApplyMemberMode()
  self:Layout()
  f:HookScript("OnSizeChanged", Build.ScheduleLayout)
end

function UI:Toggle()
  if not self.frame then self:Create() end
  self.frame:SetShown(not self.frame:IsShown())
end

local function UpdateProfessionButton(self, prof, browse)
  local rank, maxRank = GCA:GetSkill(prof)
  if browse then
    self.profButton:SetSkill(ProfName(prof) .. " " .. C.browse .. L.PROF_BROWSE_TAG .. "|r")
  elseif rank then
    self.profButton:SetSkill(string.format(L.PROF_SKILL_BAR, ProfName(prof), rank, maxRank or 300), rank, maxRank or 300, prof)
  else
    self.profButton:SetSkill(ProfName(prof))
  end
  if self.profPopup and self.profPopup:IsShown() then self.profPopup:Fill() end
end

local function UpdatePortrait(self, f, prof)
  local pinfo = GCA.PROF_BY_KEY[prof]
  if f.templated and f.SetPortraitToAsset and pinfo and self.portraitFor ~= prof then
    P.SafeCall(f.SetPortraitToAsset, f, pinfo.icon)
    self.portraitFor = prof
  end
end

local function FindLastMember(members, key)
  local found
  for _, e in ipairs(members) do if e.key == key then found = e end end
  return found
end

local function SelectCurrentMember(self, members)
  local current = FindLastMember(members, self.selected)
  local auto = current == nil or self.selected == self.autoKey
  local keepCurrent = current and current.best and not current.isSelf
  if auto and not keepCurrent then
    current = GCA.DefaultMember(members) or current or members[1]
    self:Select(current and current.key, true)
  end
  return current
end

local function CountRecorded(members)
  local recorded = 0
  for _, e in ipairs(members) do if e.member and not e.isSelf then recorded = recorded + 1 end end
  return recorded
end

local function ShowNoMember(self)
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
end

local function UpdateSpecButton(self, current)
  self.specButton:SetShown(current.class ~= nil)
  self.specButton:SetClass(current.class)
  if current.spec then
    self.specButton:SetText(GCA:SpecName(current.class, current.spec) .. (current.specAssumed and " *" or ""))
  else
    self.specButton:SetText(C.warn .. L.SPEC_PICK .. "|r")
  end
  local popup = self.specPopup
  if not popup then return end
  if popup:IsShown() and popup.forKey ~= current.key then popup:Hide() end
  popup.forKey = current.key
end

local function MemberStatusText(current)
  if current.isSelf then return L.STATUS_YOU end
  if current.online then return C.upgrade .. G("FRIENDS_LIST_ONLINE") .. "|r" end
  return C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"
end

local function UpdateMemberHeader(self, current)
  self.nameText:SetText(P.Hex(P.ClassColor(current.class)) .. current.key .. "|r")
  local m = current.member
  local level, class, status = tostring(current.level or "?"), P.ClassName(current.class), MemberStatusText(current)
  if m then
    self.subText:SetText(string.format(L.SUB_LINE, G("LEVEL"), level, class, status, P.SourceText(m, current.isSelf), P.Ago(m.time)))
  else
    self.subText:SetText(string.format(L.SUB_LINE_NOGEAR, G("LEVEL"), level, class, status))
  end
end

local function SuggestionHeaderText(prof, count, browse)
  local what = prof == "Enchanting" and L.HEAD_ENCHANTS or L.HEAD_CRAFTS
  local text = string.format(what, count)
  if not browse then return text end
  return text .. " " .. C.browse .. "– " .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r"
end

local EMPTY_TEXT = {
  ["no-gear"] = function() return L.EMPTY_NOGEAR end,
  ["no-spec"] = function() return L.EMPTY_NOSPEC end,
  ["no-level"] = function() return L.EMPTY_NOLEVEL end,
  ["no-weights"] = function() return L.EMPTY_NOWEIGHTS end,
  loading = function() return L.EMPTY_LOADING end,
  browse = function(prof) return string.format(L.EMPTY_BROWSE, ProfName(prof)) end,
  ["no-known"] = function(prof) return string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof)) end,
  none = function(prof) return prof == "Enchanting" and L.EMPTY_ENCHANT or L.EMPTY_NONE end,
}

local function EmptyReason(current, count, prof, browse)
  local reason = GCA:EmptyReason(current, count, prof, browse)
  return reason and EMPTY_TEXT[reason](prof) or ""
end

local function ShowSuggestionSheet(self, current, list, prof, why)
  self.sugList:Hide()
  if not list.sections then
    self.sheet:Hide()
    self.emptyText:SetText(why)
    return
  end
  self.sheet:Show()
  self:UpdateSheet(current, list, prof, why)
  self.emptyText:SetText("")
end

local function ShowSuggestionList(self, current, list, prof, why)
  self.sheet:Hide()
  self.sugList:Show()
  self.sugList:SetData(UI.SectionRows(list))
  local listKey = ViewKey(current.key, prof)
  if self.listKey ~= listKey then
    self.listKey = listKey
    self.sugList:ScrollTo(0)
  end
  self.emptyText:SetText(#list == 0 and why or "")
end

local function UpdateMemberDetail(self, current, prof, browse)
  UpdateSpecButton(self, current)
  UpdateMemberHeader(self, current)
  local list = current.suggestions or {}
  self.sugHeader:SetText(SuggestionHeaderText(prof, #list, browse))
  UI.sourceLine = current.weights and GCA:SourceLine(current.weights) or ""
  self.infoIcon:SetShown(UI.sourceLine ~= "")
  local why = EmptyReason(current, #list, prof, browse)
  if UI.MemberMode() == "sheet" then
    ShowSuggestionSheet(self, current, list, prof, why)
  else
    ShowSuggestionList(self, current, list, prof, why)
  end
end

function UI:Refresh()
  pcall(UI.UpdateDetailCards)
  local f = self.frame
  if not (f and f:IsShown() and GCA.db) then return end
  if self.survival then self.survival:Sync() end
  self:RefreshFilters()
  GCA:ReadProfessions()
  local prof = GCA:SelectedProfession()
  local browse = GCA:IsBrowse(prof)
  UpdateProfessionButton(self, prof, browse)
  UpdatePortrait(self, f, prof)
  local members = GCA:GetMemberList()
  local current = SelectCurrentMember(self, members)
  self.current = current
  self.lastMembers = members
  self.memberList:SetData(UI.MemberRows(members, self.memberSearch and self.memberSearch:GetText() or ""))
  self.syncDot:Update(CountRecorded(members))
  if self.view ~= "member" then self:RefreshNeeds() end
  if not current then return ShowNoMember(self) end
  UpdateMemberDetail(self, current, prof, browse)
end

local GUARDED = "Refresh Toggle Layout OpenWhisperEditor RefreshNeeds RefreshMemberList OpenMember SetView SetMemberMode"
  .. " SelectSheetSlot PickSheetRow UpdateSheet LayoutSheet SetNeedsOffline"
GUARDED:gsub("%S+", function(name) UI[name] = Guard("UI:" .. name, UI[name]) end)
