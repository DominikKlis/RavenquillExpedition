local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local G, C, HasAtlas, SetAtlasSafe, TexOK = P.G, P.C, P.HasAtlas, P.SetAtlasSafe, P.TexOK
local SingleLine, SetTip, SpecHowText, ProfLabel = P.SingleLine, P.SetTip, P.SpecHowText, P.ProfLabel
local AddBorder, NewTextButton, NativeFont = P.AddBorder, P.NewTextButton, P.NativeFont
local NewPopup, KeepNativeHover = P.NewPopup, P.KeepNativeHover

-- K6: native dropdowns. A DropdownButton made from the client's WowStyle1DropdownTemplate /
-- WowStyle1FilterDropdownTemplate (both confirmed by the probe; the profession recipe list's "Filter" button IS the
-- filter template, 90x18, common-dropdown-b-button), created in pcall as BugSack config.lua:47 and WhatsTraining
-- Crafting\SkillsRecipeList.lua:30 do, driven by SetupMenu(generator) with the menu description calls Forever
-- addons use: CreateRadio / CreateCheckbox (BugSack config.lua:107-131, ForeverLFG FilterUI.lua:57-115),
-- CreateButton / CreateDivider / CreateTitle (ForeverLFG FilterUI.lua:95-114), OverrideText (Leatrix_Plus
-- .lua:17094). nil where the client can't make one; every caller then builds a plain fallback.
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
-- rebuild an open menu / the shown text after a setting changed
local function RefreshDropdown(dd, text)
  if not (dd and dd.native) then return end
  if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end
  if text and dd.OverrideText then pcall(dd.OverrideText, dd, text) end
end
UI.RefreshDropdown = RefreshDropdown

-- The member view's variant (K4: "Character sheet | List"). K6: NOT a custom segmented control any more but a
-- WowStyle1DropdownTemplate "View: Character sheet" with one radio per variant - what Blizzard does for a display
-- mode inside a panel (a dropdown in the panel's header line; the window's own tabs already switch the two
-- views, and side tabs are the profession window's PROFESSION switch). Fallback: one red button that switches
-- to the other variant (its text names the shown one).
UI.MEMBER_MODES = { { "sheet", "MVIEW_SHEET" }, { "list", "MVIEW_LIST" } }
UI.TOGGLE_W = 170
function UI.ModeMenu(_, root)
  for _, def in ipairs(UI.MEMBER_MODES) do
    root:CreateRadio(L[def[2]], function(mode) return UI.MemberMode() == mode end, function(mode) UI:SetMemberMode(mode) end, def[1])
  end
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
    dd:SetupMenu(UI.ModeMenu)
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

-- Switches the member view's variant; the selected member (and the sheet's slot) stay.
function UI:SetMemberMode(mode)
  if not (GCA.db and GCA.db.settings) then return end
  GCA.db.settings.memberView = mode == "list" and "list" or "sheet"
  self:ApplyMemberMode()
  self:Refresh()
end

function UI:ApplyMemberMode()
  local mode = UI.MemberMode()
  if self.modeToggle then self.modeToggle:Paint(mode) end
  if self.sugList then self.sugList:SetShown(mode == "list") end
  if self.sheet and mode ~= "sheet" then self.sheet:Hide() end
end

---------------------------------------------------------------------------
-- Pickers, menus, dialogs
---------------------------------------------------------------------------
-- top: y of the first row (default 6; the options menu has the slider above its rows)
local function PopupRow(pop, i, width, top)
  local b = pop.buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, pop)
  b:SetSize(width, 18)
  b:SetPoint("TOPLEFT", 6, -(top or 6) - (i - 1) * 18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 4, 0)
  SingleLine(b.text)
  pop.buttons[i] = b
  return b
end

-- K1: the picked entry of a popup gets the check-mark texture instead of an ASCII "> ". Returns a text prefix
-- (only where the texture can't be drawn).
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
UI.SetRowMark = SetRowMark

-- Spec picker: a plain popup list (no dropdown API needed), manual pick saved per member (F4).
-- K5 (Member mockup): the spec control = icon, small "Spec." label above the spec name, caret. No spec icon is
-- known on this client (Spec.lua has none), so the icon is the class icon: the "classicon-<class>" atlas when
-- GetAtlasInfo has it, else the class-circles file with CLASS_ICON_TCOORDS (ForeverLFG_GroupQuest
-- QuestMatchesUI.lua:163-169), else no icon (text only). Returns "atlas" / "file" / nil.
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
-- K6: the spec picker = the class icon + a native WowStyle1DropdownTemplate (radios "Automatic" + the class's specs,
-- the shown text = the member's spec via OverrideText). The K5 custom box (button art, "SPEC." label, caret) is
-- gone. Fallback: the class icon + a red button that opens the 0.5.0 popup list.
local function ChooseSpec(spec)
  local cur = UI.current
  if not (cur and cur.class) then return end
  GCA:SetManualSpec(cur.key, cur.class, spec)
  UI:Refresh()
end
function UI.SpecMenu(_, root)
  local d = UI.current
  if not (d and d.class) then return end
  root:CreateRadio(L.SPEC_AUTOMATIC, function() return not GCA.db.specManual[d.key] end, function() ChooseSpec(nil) end)
  for _, spec in ipairs(GCA.SPECS_OF[d.class] or {}) do
    root:CreateRadio(GCA:SpecName(d.class, spec), function(v)
      local m = GCA.db.specManual[d.key]
      return m ~= nil and m.spec == v
    end, function(v) ChooseSpec(v) end, spec)
  end
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
    dd:SetupMenu(UI.SpecMenu)
    KeepNativeHover(dd, "spec button", SpecTip)
  else
    dd = NewTextButton(btn, UI.SPEC_BTN_W - 28, 22, "?")
    pop = NewPopup(parent)
    pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    pop.buttons = {}
    function pop:Fill(d)
      local list = { { nil, L.SPEC_AUTOMATIC } }
      for _, spec in ipairs(GCA.SPECS_OF[d.class or ""] or {}) do list[#list + 1] = { spec, GCA:SpecName(d.class, spec) } end
      for i, item in ipairs(list) do
        local b = self.buttons[i]
        if not b then
          b = PopupRow(self, i, 190)
          b:SetScript("OnClick", function(selfBtn) self:Hide(); ChooseSpec(selfBtn.spec) end)
        end
        b.spec = item[1]
        local manual = GCA.db.specManual[d.key]
        local picked = (item[1] == nil and not manual) or (manual and manual.spec == item[1])
        b.text:SetText(SetRowMark(b, picked) .. item[2])
        b:Show()
      end
      for i = #list + 1, #self.buttons do self.buttons[i]:Hide() end
      self:SetSize(202, 12 + #list * 18)
    end
    dd:SetScript("OnClick", function()
      if pop:IsShown() then pop:Hide() return end
      if not (UI.current and UI.current.class) then return end
      pop:Fill(UI.current)
      pop:Show()
    end)
    SetTip(dd, "spec button", SpecTip)
    dd:SetScript("OnLeave", GameTooltip_Hide)
    window:HookScript("OnHide", function() pop:Hide() end)
  end
  dd:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
  btn.dropdown = dd
  function btn:SetText(t)
    self.text = t
    if self.dropdown.native then RefreshDropdown(self.dropdown, t) else self.dropdown:SetText(t) end
  end
  function btn:GetText() return self.text end
  -- icon for this class (or none); the dropdown keeps its place
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

-- Profession selector: your professions, then "browse" the other gear professions.
-- K6: the profession window's own rank bar (probe: ProfessionsFrame.CraftingPage.RankBar - Background =
-- Professions-skillbar-bg 451x29 and Border = Professions-skillbar-frame 451x29 at TOPLEFT 0,0, Fill 441x18 at 5,-3,
-- the rank text in Number12FontOutline centred, ExpansionDropdownButton 19x19 at RIGHT -6,-3 whose arrow is
-- common-dropdown-a-button 27x27 at RIGHT 2,-3). Our fill is a StatusBar with the proven skill-bar file (the
-- client's own Fill draws through a mask texture we don't copy). The arrow is an intrinsic DropdownButton
-- (ForeverLFG SettingsUI.lua:14) whose menu has a radio per profession; without it a plain button with the same
-- arrow opens the 0.5.0 popup (as does a click on the bar then). Missing bar atlases: a dark track, 1 px border.
-- The K5 round button / disc is gone.
UI.PROF_BAR_W, UI.PROF_DROP, UI.PROF_BAR_H = 340, 19, 29 -- K8: 300 -> 340 (centred under the title)
-- K7 (lead): the client's RankBar fill is per profession (probe: ProfessionsFrame.CraftingPage.RankBar.Fill = atlas
-- Skillbar_Fill_Flipbook_Leatherworking 441x18 at 5,-3, a flipbook sheet: texcoords 0.733..0.767 = row 23 of 30;
-- .Flare = Skillbar_Flare_Leatherworking 53x16, ADD, at the fill's right end; the client cuts the fill with the
-- MaskTexture Professions-skillbar-mask). Ours: one still frame of the sheet (row 1), cut by SetWidth + texcoords
-- like a status bar; the other professions' names follow the same pattern and are checked with GetAtlasInfo,
-- else Leatherworking's, else the status bar / plain fill.
-- K8 (probe.rankbar): the client animates the fill with a FlipBook (rows 30, columns 2, 60 frames, 2 s, played once on a
-- change, RankBar.BarAnimation) and fades the flare (Alpha, 1 s). Ours: the fill at its FULL width inside a clipping
-- frame as wide as rank/max (instead of the client's MaskTexture), so the FlipBook can run on it; one still frame
-- (row 1, column 1) at rest; the animation plays once when the window shows a new rank / profession. Without
-- SetClipsChildren: the K7 cut by width + texcoords, no animation. Animation API missing: still frame only.
UI.RANKBAR = { fill = "Skillbar_Fill_Flipbook_", flare = "Skillbar_Flare_", rows = 30, cols = 2, frames = 60, duration = 2,
  defaultFill = { atlas = "Skillbar_Fill_Flipbook_Leatherworking" }, defaultFlare = { atlas = "Skillbar_Flare_Leatherworking" } }
function UI.RankBarAtlases(prof)
  local R = UI.RANKBAR
  local fill, flare = R.fill .. tostring(prof), R.flare .. tostring(prof)
  if not HasAtlas(fill) then fill = R.defaultFill.atlas end
  if not HasAtlas(flare) then flare = R.defaultFlare.atlas end
  local info = HasAtlas(fill) and C_Texture.GetAtlasInfo(fill)
  if type(info) ~= "table" or type(info.leftTexCoord) ~= "number" or type(info.rightTexCoord) ~= "number"
     or type(info.topTexCoord) ~= "number" or type(info.bottomTexCoord) ~= "number" then
    return nil
  end
  return fill, HasAtlas(flare) and flare or nil, info
end
function UI.ProfMenu(_, root)
  local own, trusted = GCA:OwnProfessions()
  local mine, others = {}, {}
  for _, p in ipairs(GCA.PROFESSIONS) do
    if not trusted or own[p.key] then mine[#mine + 1] = p.key else others[#others + 1] = p.key end
  end
  local function radio(k)
    root:CreateRadio(ProfLabel(k, true), function(v) return GCA:SelectedProfession() == v end,
      function(v) GCA:SelectProfession(v); UI:Refresh() end, k)
  end
  for _, k in ipairs(mine) do radio(k) end
  if #others > 0 then
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateTitle then root:CreateTitle(L.PROF_BROWSE_HEADER) end
    for _, k in ipairs(others) do radio(k) end
  end
end
local function CreateProfessionPicker(parent, window)
  local BW, BH = UI.PROF_BAR_W, UI.PROF_BAR_H
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BW, BH)
  -- the fill area (5,-3, 18 px high, as the client's Fill)
  local track = CreateFrame("Frame", nil, btn)
  track:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -3)
  track:SetSize(BW - 10, 18)
  btn.track = track
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  local top = CreateFrame("Frame", nil, btn) -- border + text above the fill
  top:SetAllPoints(btn)
  btn.top = top
  btn.border = top:CreateTexture(nil, "ARTWORK")
  if SetAtlasSafe(btn.bg, "Professions-skillbar-bg") and SetAtlasSafe(btn.border, "Professions-skillbar-frame") then
    btn.bg:SetAllPoints(btn)
    btn.border:SetAllPoints(btn)
    btn.art = "atlas"
  else
    btn.bg:SetAllPoints(track)
    btn.bg:SetColorTexture(0.04, 0.05, 0.1, 1)
    btn.border:Hide()
    AddBorder(track, 0.54, 0.46, 0.34, 1)
    btn.art = "plain"
  end
  local ok, bar
  if btn.art == "atlas" and UI.RankBarAtlases(GCA:SelectedProfession()) then
    -- K7: the client's per-profession fill + flare (see UI.RANKBAR); K8: inside a clipping frame, animated
    local clip = CreateFrame("Frame", nil, track)
    clip:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    clip:SetSize(BW - 10, 18)
    local holder = track
    if clip.SetClipsChildren and pcall(clip.SetClipsChildren, clip, true) then
      btn.clip = clip
      holder = CreateFrame("Frame", nil, clip)
      holder:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
      holder:SetSize(BW - 10, 18)
    else
      clip:Hide()
    end
    btn.fill = holder:CreateTexture(nil, "ARTWORK")
    btn.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    btn.fill:SetHeight(18)
    if btn.clip then btn.fill:SetWidth(BW - 10) end
    btn.flare = track:CreateTexture(nil, "ARTWORK", nil, 2)
    btn.flare:SetSize(53, 16)
    btn.flare:SetPoint("RIGHT", btn.clip or btn.fill, "RIGHT", 0, 0)
    -- the FlipBook (every call guarded: animation API names as the probe read them back)
    if btn.clip and btn.fill.CreateAnimationGroup then
      local R = UI.RANKBAR
      local animOk = pcall(function()
        local ag = btn.fill:CreateAnimationGroup()
        local a = ag:CreateAnimation("FlipBook")
        a:SetFlipBookRows(R.rows); a:SetFlipBookColumns(R.cols); a:SetFlipBookFrames(R.frames); a:SetDuration(R.duration)
        if ag.SetLooping then ag:SetLooping("NONE") end
        -- back to the still frame when it ends (unverified whether the client keeps the last frame itself)
        if ag.SetScript then
          pcall(ag.SetScript, ag, "OnFinished", function()
            local tc = btn.stillTC
            if tc then btn.fill:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
          end)
        end
        btn.anim = ag
      end)
      if not animOk then btn.anim = nil end
    end
    if btn.flare.SetBlendMode then pcall(btn.flare.SetBlendMode, btn.flare, "ADD") end
    btn.barKind = "atlas"
  else
    ok, bar = pcall(CreateFrame, "StatusBar", nil, track)
  end
  if btn.barKind == "atlas" then
    -- done above
  elseif ok and bar and bar.SetMinMaxValues and bar.SetValue and bar.SetStatusBarTexture and TexOK("skillBar")
     and pcall(bar.SetStatusBarTexture, bar, UI.TEX.skillBar) then
    bar:SetAllPoints(track)
    bar:SetMinMaxValues(0, 1)
    local c = UI.SKIN.skillBar.tint
    if bar.SetStatusBarColor then pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3]) end
    btn.bar, btn.barKind = bar, "statusbar"
  else
    if ok and bar and bar.Hide then bar:Hide() end
    btn.fill = track:CreateTexture(nil, "ARTWORK")
    btn.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    btn.fill:SetHeight(18)
    local c = UI.SKIN.skillBar.color
    btn.fill:SetColorTexture(c[1], c[2], c[3], c[4])
    btn.barKind = "fill"
  end
  if top.SetFrameLevel and btn.GetFrameLevel then top:SetFrameLevel((btn:GetFrameLevel() or 0) + 3) end
  btn.label = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NativeFont(btn.label, "Number12FontOutline")
  btn.label:SetPoint("CENTER", track, "CENTER", 0, 0)
  btn.label:SetWidth(BW - 20)
  btn.label:SetJustifyH("CENTER")
  SingleLine(btn.label)
  -- the arrow (ExpansionDropdownButton look)
  local okd, drop = pcall(CreateFrame, "DropdownButton", nil, top)
  if okd and drop and type(drop.SetupMenu) == "function" then
    drop.native = true
    drop:SetupMenu(UI.ProfMenu)
  else
    if okd and drop and drop.Hide then drop:Hide() end
    drop = CreateFrame("Button", nil, top)
  end
  drop:SetSize(UI.PROF_DROP, UI.PROF_DROP)
  -- outside the bar, just right of its frame (inside it overlapped the fill and the rank text)
  drop:SetPoint("LEFT", btn, "RIGHT", 2, 0)
  drop.arrow = drop:CreateTexture(nil, "ARTWORK")
  if SetAtlasSafe(drop.arrow, "common-dropdown-a-button") then
    drop.arrow:SetSize(27, 27)
    drop.arrow:SetPoint("CENTER", drop, "CENTER", 0, 0)
    drop.hl = drop:CreateTexture(nil, "HIGHLIGHT")
    SetAtlasSafe(drop.hl, "common-dropdown-a-button")
    drop.hl:SetAllPoints(drop.arrow)
    if drop.hl.SetBlendMode then pcall(drop.hl.SetBlendMode, drop.hl, "ADD") end
    drop.hl:SetAlpha(0.4)
    drop.arrowKind = "atlas"
  elseif TexOK("caretDown") then
    drop.arrow:SetTexture(UI.TEX.caretDown)
    drop.arrow:SetSize(12, 12)
    drop.arrow:SetPoint("CENTER", drop, "CENTER", 0, -1)
    drop.arrowKind = "file"
  else
    drop.arrow:Hide()
    drop.text = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    drop.text:SetPoint("CENTER")
    drop.text:SetText("v")
    drop.arrowKind = "text"
  end
  btn.drop = drop
  -- text, fill = rank / maxRank (0 when unknown / browsing)
  function btn:SetSkill(text, rank, maxRank, prof)
    self.label:SetText(text)
    local ratio = 0
    if type(rank) == "number" and type(maxRank) == "number" and maxRank > 0 then ratio = math.max(0, math.min(1, rank / maxRank)) end
    self.ratio = ratio
    if self.barKind == "atlas" then
      local fill, flare, info = UI.RankBarAtlases(prof or GCA:SelectedProfession())
      if fill then
        SetAtlasSafe(self.fill, fill)
        -- one frame of the sheet: 1 of 30 rows, 1 of 2 columns
        local l, r, t = info.leftTexCoord, info.rightTexCoord, info.topTexCoord
        local fh = math.min(info.bottomTexCoord - t, 1 / UI.RANKBAR.rows)
        local fw = (r - l) / UI.RANKBAR.cols
        if self.clip then
          self.stillTC = { l, l + fw, t, t + fh }
          self.fill:SetTexCoord(l, l + fw, t, t + fh)
          self.clip:SetWidth(math.max(1, (BW - 10) * ratio))
        else
          self.fill:SetTexCoord(l, l + fw * math.max(ratio, 0.001), t, t + fh)
          self.fill:SetWidth(math.max(1, (BW - 10) * ratio))
        end
        self.fillAtlas, self.flareAtlas = fill, flare
        if flare then SetAtlasSafe(self.flare, flare) end
        -- K8: play the FlipBook once per new rank / profession (as the client does on a change)
        local key = tostring(prof) .. ":" .. tostring(rank) .. "/" .. tostring(maxRank)
        if self.anim and self.animKey ~= key and ratio > 0 then
          self.animKey = key
          if self.anim.Stop then pcall(self.anim.Stop, self.anim) end
          SetAtlasSafe(self.fill, fill) -- the whole sheet for the FlipBook (it steps through its 30x2 frames)
          self.animPlayed = pcall(self.anim.Play, self.anim)
        end
      end
      self.fill:SetShown(ratio > 0 and fill ~= nil)
      self.flare:SetShown(ratio > 0 and ratio < 1 and self.flareAtlas ~= nil and fill ~= nil)
    elseif self.barKind == "statusbar" then
      self.bar:SetValue(ratio)
    else
      self.fill:SetWidth(math.max(1, (BW - 10) * ratio))
      self.fill:SetShown(ratio > 0)
    end
    if self.drop.native then RefreshDropdown(self.drop) end
  end
  function btn:SetLabel(t) self:SetSkill(t) end
  btn:SetLabel(L.PROF_TIP_TITLE)
  local function tip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.PROF_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.PROF_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end
  SetTip(btn, "profession button", tip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  if drop.native then
    KeepNativeHover(drop, "profession button", tip)
    return btn, nil
  end
  -- fallback: the 0.5.0 popup list, opened by the arrow and the bar
  local pop = NewPopup(parent)
  pop.buttons = {}
  function pop:Fill()
    local own, trusted = GCA:OwnProfessions()
    local mine, others = {}, {}
    for _, p in ipairs(GCA.PROFESSIONS) do
      if not trusted or own[p.key] then mine[#mine + 1] = p.key else others[#others + 1] = p.key end
    end
    local list = {}
    for _, k in ipairs(mine) do list[#list + 1] = { prof = k } end
    if #others > 0 then
      list[#list + 1] = { header = L.PROF_BROWSE_HEADER }
      for _, k in ipairs(others) do list[#list + 1] = { prof = k } end
    end
    local sel = GCA:SelectedProfession()
    for i, item in ipairs(list) do
      local b = self.buttons[i]
      if not b then
        b = PopupRow(self, i, 260)
        b:SetScript("OnClick", function(selfBtn)
          if not selfBtn.prof then return end
          GCA:SelectProfession(selfBtn.prof)
          pop:Hide()
          UI:Refresh()
        end)
      end
      b.prof = item.prof
      if item.header then
        SetRowMark(b, false)
        b.text:SetText(C.dim .. item.header .. "|r")
      else
        b.text:SetText(SetRowMark(b, item.prof == sel) .. ProfLabel(item.prof, true))
      end
      b:Show()
    end
    for i = #list + 1, #self.buttons do self.buttons[i]:Hide() end
    self:SetSize(272, 12 + #list * 18)
  end
  pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
  local function toggle()
    if pop:IsShown() then pop:Hide() return end
    pop:Fill()
    pop:Show()
  end
  for _, b in ipairs({ btn, drop }) do
    b:SetScript("OnClick", toggle)
    SetTip(b, "profession button", tip)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  window:HookScript("OnHide", function() pop:Hide() end)
  return btn, pop
end

UI.CreateProfessionPicker = CreateProfessionPicker -- K7: for the rank bar test

-- Filter / options menu (H2 L5: replaces the five bottom checkboxes).
UI.FILTERS = {
  { key = "showUnlearned", label = "FILTER_UNLEARNED", tip = "FILTER_UNLEARNED_TIP" },
  { key = "lookahead", label = "FILTER_LOOKAHEAD", tip = "FILTER_LOOKAHEAD_TIP" },
  -- K5: "Read gear automatically" (target, group, mouseover) replaces "Auto-inspect target"; "Hide offline" is gone
  -- (it only hid offline members without gear, and those are no longer listed at all)
  { key = "autoInspect", label = "FILTER_AUTOINSPECT", tip = "FILTER_AUTOINSPECT_TIP" },
  { key = "sync", label = "FILTER_SYNC", tip = "FILTER_SYNC_TIP" },
}
function UI.ToggleSetting(key)
  local s = GCA.db.settings
  s[key] = not s[key]
  if key == "sync" and s.sync and GCA.CheckOwn then GCA:CheckOwn(false) end -- sync back on: own gear if owed
  UI:Refresh()
  return s[key]
end

-- K6: the toggles live in the profession window's own "Filter" dropdown (WowStyle1FilterDropdownTemplate): one in
-- the guild-needs filter bar (right of the search), one at the top right of the member list (where the recipe
-- list has its Filter, TOPRIGHT -8,-9, 90x18). Menu: a check box per toggle (with its tooltip), "Include offline
-- members (n)", a divider, "Edit whisper text...". The leveling-bonus slider is no menu entry: it sits in the
-- bottom bar (CreateSurvivalSlider). Fallback: a red "Filter" button opening the 0.5.0 popup with the same rows.
UI.FILTER_W, UI.FILTER_H = 90, 18
local OPTIONS_W = 300
local function FilterEntries()
  local entries = {}
  for _, def in ipairs(UI.FILTERS) do entries[#entries + 1] = def end
  entries[#entries + 1] = { needsOffline = true, label = "NEEDS_OFFLINE", tip = "NEEDS_OFFLINE_TIP" }
  entries[#entries + 1] = { action = "whisper", label = "EDIT_WHISPER", tip = "EDIT_WHISPER_TIP" }
  return entries
end
local function EntryLabel(def)
  if def.needsOffline then return string.format(L.NEEDS_OFFLINE, UI.offlineN or 0) end
  return L[def.label]
end
local function EntryOn(def)
  local s = GCA.db and GCA.db.settings or {}
  if def.needsOffline then return s.needsOffline and true or false end
  return def.key ~= nil and s[def.key] and true or false
end
local function EntryDo(def)
  if def.action == "whisper" then UI:OpenWhisperEditor(); return end
  if def.needsOffline then UI:SetNeedsOffline(not EntryOn(def)); return end
  UI.ToggleSetting(def.key)
end
UI.FilterEntryDo = EntryDo
-- K11 (user): the leveling-bonus slider moved out of the bottom bar into the Filter menu: a submenu with the
-- values 0/25/50/75/100 % as radio entries (the menu can't hold a slider). Applied like the slider did.
UI.SURVIVAL_STEPS = { 0, 25, 50, 75, 100 }
function UI.SetSurvival(v)
  if not (GCA.db and GCA.db.settings) then return end
  if math.abs(GCA:SurvivalShare() * 100 - v) < 0.5 then return end
  GCA.db.settings.survival = v / 100
  GCA:InvalidateScores()
  UI:Refresh()
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
function UI.FilterMenu(_, root)
  for _, def in ipairs(FilterEntries()) do
    local e
    if def.action then
      if root.CreateDivider then root:CreateDivider() end
      local ok, made = pcall(SurvivalSubmenu, root)
      UI.survivalInMenu = ok and made == true
      e = root:CreateButton(EntryLabel(def), function() EntryDo(def) end)
    else
      e = root:CreateCheckbox(EntryLabel(def), function() return EntryOn(def) end, function() EntryDo(def) end)
    end
    -- entry tooltips as WarEffortScout MapPins.lua:2004 sets them (guarded)
    if type(e) == "table" and e.SetTooltip then
      pcall(e.SetTooltip, e, function(tooltip)
        tooltip:SetText(EntryLabel(def), 1, 1, 1)
        tooltip:AddLine(L[def.tip], nil, nil, nil, true)
      end)
    end
  end
end
local function FilterTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.FILTER_BUTTON, 1, 1, 1)
  GameTooltip:AddLine(L.OPTIONS_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end
-- K8: the Filter button's reset badge (the profession list shows a small red x at its top-right corner while a
-- filter differs from its default; probe: auctionhouse-ui-filter-redx in ProfessionsFrame). Filters = the list
-- filters (missing recipes, look-ahead, offline members), not the options (auto-read, sync). The template's own
-- reset API (SetIsDefaultCallback / SetDefaultCallback, unverified on Forever) when it has it, else our badge.
UI.FILTER_DEFAULTS = { showUnlearned = false, lookahead = true, needsOffline = false }
function UI.FiltersAtDefault()
  local s = GCA.db and GCA.db.settings or {}
  for k, v in pairs(UI.FILTER_DEFAULTS) do
    if (s[k] and true or false) ~= v then return false end
  end
  return true
end
function UI.ResetFilters()
  local s = GCA.db and GCA.db.settings
  if not s then return end
  for k, v in pairs(UI.FILTER_DEFAULTS) do s[k] = v end
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
    dd:SetupMenu(UI.FilterMenu)
    KeepNativeHover(dd, "filter button", FilterTip)
    UI.AddFilterReset(dd)
    return dd, nil
  end
  local btn = NewTextButton(parent, UI.FILTER_W, 22, L.FILTER_BUTTON)
  UI.AddFilterReset(btn)
  local pop = NewPopup(parent)
  pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -4)
  pop.buttons = {}
  local entries = FilterEntries()
  function pop:Fill()
    for i, def in ipairs(entries) do
      local b = self.buttons[i]
      if not b then
        b = PopupRow(self, i, OPTIONS_W - 12)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 22, 0)
        b.check = b:CreateTexture(nil, "ARTWORK")
        b.check:SetSize(16, 16)
        b.check:SetPoint("LEFT", 3, 0)
        b.check:SetTexture(UI.TEX.check)
        b:SetScript("OnClick", function(selfBtn)
          if selfBtn.def.action == "whisper" then pop:Hide() end
          EntryDo(selfBtn.def)
          if pop:IsShown() then pop:Fill() end
        end)
        SetTip(b, "options row", function(selfBtn)
          GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
          GameTooltip:SetText(EntryLabel(selfBtn.def), 1, 1, 1)
          GameTooltip:AddLine(L[selfBtn.def.tip], nil, nil, nil, true)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
      end
      b.def = def
      b.text:SetText(EntryLabel(def))
      b.check:SetShown(EntryOn(def))
      b:Show()
    end
    self:SetSize(OPTIONS_W, 12 + #entries * 18)
  end
  btn:SetScript("OnClick", function()
    if pop:IsShown() then pop:Hide() return end
    pop:Fill()
    pop:Show()
  end)
  SetTip(btn, "filter button", FilterTip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  window:HookScript("OnHide", function() pop:Hide() end)
  return btn, pop
end

-- every Filter dropdown / popup shows the current settings again (after a toggle or a refresh)
function UI:RefreshFilters()
  local atDefault = UI.FiltersAtDefault()
  for _, f in ipairs(self.filters or {}) do
    if f.button.native then RefreshDropdown(f.button) elseif f.popup and f.popup:IsShown() then f.popup:Fill() end
    if f.button.resetButton then f.button.resetButton:SetShown(not atDefault) end
    if f.button.resetKind == "native" and f.button.ValidateResetState then pcall(f.button.ValidateResetState, f.button) end
  end
end

-- shared with the files loaded after this one (P)
P.CreateProfessionPicker = CreateProfessionPicker
