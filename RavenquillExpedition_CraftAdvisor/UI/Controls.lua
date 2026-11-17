local _, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SetAtlasSafe, FileOK, TexOK, SingleLine = P.SetAtlasSafe, P.FileOK, P.TexOK, P.SingleLine
local Guard, SetTip, TextWidth, NewEditBox = P.Guard, P.SetTip, P.TextWidth, P.NewEditBox
local HasAtlas, AddBorder, NativeFont, ProfLabel = P.HasAtlas, P.AddBorder, P.NativeFont, P.ProfLabel
local KeepNativeHover, NativeMenu, NewMenuPopup, OpenPopupOnClick = P.KeepNativeHover, P.NativeMenu, P.NewMenuPopup, P.OpenPopupOnClick
local NewDropdown, RefreshDropdown = UI.NewDropdown, UI.RefreshDropdown

UI.SYNC_COLORS = { ok = { 0.25, 0.9, 0.25 }, idle = { 1, 0.82, 0 }, paused = { 1, 0.3, 0.3 }, off = { 0.5, 0.5, 0.5 }, noguild = { 0.5, 0.5, 0.5 } }
function UI.SyncState()
  if GCA.SyncState then return GCA:SyncState() end
  return "off"
end
function UI.SyncLine()
  if GCA.SyncStatusLine then return GCA:SyncStatusLine() or "" end
  return L.CMD_SYNC_NOT_LOADED
end
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
    local tw = math.min(TextWidth(self.text), 200)
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

UI.PROF_BAR_W, UI.PROF_DROP, UI.PROF_BAR_H = 340, 19, 29
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
local function SplitProfessions()
  local own, trusted = GCA:OwnProfessions()
  local mine, others = {}, {}
  for _, p in ipairs(GCA.PROFESSIONS) do
    if not trusted or own[p.key] then mine[#mine + 1] = p.key else others[#others + 1] = p.key end
  end
  return mine, others
end

local function ProfItems()
  local mine, others = SplitProfessions()
  local items = {}
  local function radio(k)
    items[#items + 1] = { kind = "radio", label = ProfLabel(k, true), checked = function() return GCA:SelectedProfession() == k end,
      onClick = function() GCA:SelectProfession(k); UI:Refresh() end }
  end
  for _, k in ipairs(mine) do radio(k) end
  if #others > 0 then
    items[#items + 1] = { kind = "divider" }
    items[#items + 1] = { kind = "title", label = L.PROF_BROWSE_HEADER }
    for _, k in ipairs(others) do radio(k) end
  end
  return items
end

local Picker = { BAR_H = 18 }

function Picker.Frame(btn, track)
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  local top = CreateFrame("Frame", nil, btn)
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
  return top
end

function Picker.ClipHolder(btn, track, trackW)
  local clip = CreateFrame("Frame", nil, track)
  clip:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  clip:SetSize(trackW, Picker.BAR_H)
  if not (clip.SetClipsChildren and pcall(clip.SetClipsChildren, clip, true)) then
    clip:Hide()
    return track
  end
  btn.clip = clip
  local holder = CreateFrame("Frame", nil, clip)
  holder:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
  holder:SetSize(trackW, Picker.BAR_H)
  return holder
end

function Picker.FlipBook(btn)
  local R = UI.RANKBAR
  local ag = btn.fill:CreateAnimationGroup()
  local a = ag:CreateAnimation("FlipBook")
  a:SetFlipBookRows(R.rows); a:SetFlipBookColumns(R.cols); a:SetFlipBookFrames(R.frames); a:SetDuration(R.duration)
  if ag.SetLooping then ag:SetLooping("NONE") end
  if ag.SetScript then
    pcall(ag.SetScript, ag, "OnFinished", function()
      local tc = btn.stillTC
      if tc then btn.fill:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    end)
  end
  btn.anim = ag
end

function Picker.AtlasBar(btn, track, trackW)
  local holder = Picker.ClipHolder(btn, track, trackW)
  btn.fill = holder:CreateTexture(nil, "ARTWORK")
  btn.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  btn.fill:SetHeight(Picker.BAR_H)
  if btn.clip then btn.fill:SetWidth(trackW) end
  btn.flare = track:CreateTexture(nil, "ARTWORK", nil, 2)
  btn.flare:SetSize(53, 16)
  btn.flare:SetPoint("RIGHT", btn.clip or btn.fill, "RIGHT", 0, 0)
  if btn.clip and btn.fill.CreateAnimationGroup then
    if not pcall(Picker.FlipBook, btn) then btn.anim = nil end
  end
  if btn.flare.SetBlendMode then pcall(btn.flare.SetBlendMode, btn.flare, "ADD") end
  btn.barKind = "atlas"
end

function Picker.StatusBar(btn, track, ok, bar)
  if not (ok and bar and bar.SetMinMaxValues and bar.SetValue and bar.SetStatusBarTexture and TexOK("skillBar")
     and pcall(bar.SetStatusBarTexture, bar, UI.TEX.skillBar)) then
    return false
  end
  bar:SetAllPoints(track)
  bar:SetMinMaxValues(0, 1)
  local c = UI.SKIN.skillBar.tint
  if bar.SetStatusBarColor then pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3]) end
  btn.bar, btn.barKind = bar, "statusbar"
  return true
end

function Picker.PlainFill(btn, track, ok, bar)
  if ok and bar and bar.Hide then bar:Hide() end
  btn.fill = track:CreateTexture(nil, "ARTWORK")
  btn.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  btn.fill:SetHeight(Picker.BAR_H)
  local c = UI.SKIN.skillBar.color
  btn.fill:SetColorTexture(c[1], c[2], c[3], c[4])
  btn.barKind = "fill"
end

function Picker.Bar(btn, track, trackW)
  if btn.art == "atlas" and UI.RankBarAtlases(GCA:SelectedProfession()) then
    return Picker.AtlasBar(btn, track, trackW)
  end
  local ok, bar = pcall(CreateFrame, "StatusBar", nil, track)
  if not Picker.StatusBar(btn, track, ok, bar) then Picker.PlainFill(btn, track, ok, bar) end
end

function Picker.Label(btn, top, track, BW)
  if top.SetFrameLevel and btn.GetFrameLevel then top:SetFrameLevel((btn:GetFrameLevel() or 0) + 3) end
  btn.label = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NativeFont(btn.label, "Number12FontOutline")
  btn.label:SetPoint("CENTER", track, "CENTER", 0, 0)
  btn.label:SetWidth(BW - 20)
  btn.label:SetJustifyH("CENTER")
  SingleLine(btn.label)
end

function Picker.DropArrow(drop)
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
end

function Picker.Drop(btn, top)
  local drop = NewDropdown(top, nil, UI.PROF_DROP, UI.PROF_DROP)
  if drop then
    drop:SetupMenu(NativeMenu(ProfItems))
  else
    drop = CreateFrame("Button", nil, top)
    drop:SetSize(UI.PROF_DROP, UI.PROF_DROP)
  end
  drop:SetPoint("LEFT", btn, "RIGHT", 2, 0)
  Picker.DropArrow(drop)
  return drop
end

function Picker.SkillRatio(rank, maxRank)
  if type(rank) == "number" and type(maxRank) == "number" and maxRank > 0 then
    return math.max(0, math.min(1, rank / maxRank))
  end
  return 0
end

function Picker.PlayFill(self, fill, key, ratio)
  if not (self.anim and self.animKey ~= key and ratio > 0) then return end
  self.animKey = key
  if self.anim.Stop then pcall(self.anim.Stop, self.anim) end
  SetAtlasSafe(self.fill, fill)
  self.animPlayed = pcall(self.anim.Play, self.anim)
end

function Picker.AtlasFillCoords(self, info, ratio, trackW)
  local l, r, t = info.leftTexCoord, info.rightTexCoord, info.topTexCoord
  local fh = math.min(info.bottomTexCoord - t, 1 / UI.RANKBAR.rows)
  local fw = (r - l) / UI.RANKBAR.cols
  if self.clip then
    self.stillTC = { l, l + fw, t, t + fh }
    self.fill:SetTexCoord(l, l + fw, t, t + fh)
    self.clip:SetWidth(math.max(1, trackW * ratio))
  else
    self.fill:SetTexCoord(l, l + fw * math.max(ratio, 0.001), t, t + fh)
    self.fill:SetWidth(math.max(1, trackW * ratio))
  end
end

function Picker.SetAtlasSkill(self, ratio, rank, maxRank, prof, trackW)
  local fill, flare, info = UI.RankBarAtlases(prof or GCA:SelectedProfession())
  if fill then
    SetAtlasSafe(self.fill, fill)
    Picker.AtlasFillCoords(self, info, ratio, trackW)
    self.fillAtlas, self.flareAtlas = fill, flare
    if flare then SetAtlasSafe(self.flare, flare) end
    Picker.PlayFill(self, fill, tostring(prof) .. ":" .. tostring(rank) .. "/" .. tostring(maxRank), ratio)
  end
  self.fill:SetShown(ratio > 0 and fill ~= nil)
  self.flare:SetShown(ratio > 0 and ratio < 1 and self.flareAtlas ~= nil and fill ~= nil)
end

function Picker.AddSkillMethods(btn, trackW)
  function btn:SetSkill(text, rank, maxRank, prof)
    self.label:SetText(text)
    local ratio = Picker.SkillRatio(rank, maxRank)
    self.ratio = ratio
    if self.barKind == "atlas" then
      Picker.SetAtlasSkill(self, ratio, rank, maxRank, prof, trackW)
    elseif self.barKind == "statusbar" then
      self.bar:SetValue(ratio)
    else
      self.fill:SetWidth(math.max(1, trackW * ratio))
      self.fill:SetShown(ratio > 0)
    end
    if self.drop.native then RefreshDropdown(self.drop) end
  end
  function btn:SetLabel(t) self:SetSkill(t) end
end

function Picker.Tip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.PROF_TIP_TITLE, 1, 1, 1)
  GameTooltip:AddLine(L.PROF_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end

function Picker.Popup(parent, btn, drop, window)
  local pop = NewMenuPopup(parent, window, ProfItems, 260)
  pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
  for _, b in ipairs({ btn, drop }) do OpenPopupOnClick(b, pop, "profession button", Picker.Tip) end
  return pop
end

local function CreateProfessionPicker(parent, window)
  local BW, BH = UI.PROF_BAR_W, UI.PROF_BAR_H
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BW, BH)
  local track = CreateFrame("Frame", nil, btn)
  track:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -3)
  track:SetSize(BW - 10, Picker.BAR_H)
  btn.track = track
  local top = Picker.Frame(btn, track)
  Picker.Bar(btn, track, BW - 10)
  Picker.Label(btn, top, track, BW)
  local drop = Picker.Drop(btn, top)
  btn.drop = drop
  Picker.AddSkillMethods(btn, BW - 10)
  btn:SetLabel(L.PROF_TIP_TITLE)
  SetTip(btn, "profession button", Picker.Tip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  if drop.native then
    KeepNativeHover(drop, "profession button", Picker.Tip)
    return btn, nil
  end
  return btn, Picker.Popup(parent, btn, drop, window)
end

UI.CreateProfessionPicker = CreateProfessionPicker

P.CreateSyncDot = CreateSyncDot
P.CreateInfoIcon = CreateInfoIcon
P.CreateSearchBox = CreateSearchBox
P.CreateProfessionPicker = CreateProfessionPicker
