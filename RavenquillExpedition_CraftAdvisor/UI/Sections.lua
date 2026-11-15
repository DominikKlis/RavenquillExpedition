local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, MIN_W, RightW, C, SUB_TINT = P.SafeCall, P.MIN_W, P.RightW, P.C, P.SUB_TINT
local SingleLine, SetTip, SlotName, SlotTexture = P.SingleLine, P.SetTip, P.SlotName, P.SlotTexture
local QualityColor, Hex, ItemIcon, TextWidth = P.QualityColor, P.Hex, P.ItemIcon, P.TextWidth
local AddQualityIcon, SetIconQuality = P.AddQualityIcon, P.SetIconQuality

---------------------------------------------------------------------------
-- Slot sections: per slot with an upgrade, the worn item and that slot's craft cards under it; every
-- slot without an upgrade is folded into ONE box at the end ("No craftable upgrade: Head, Neck, …").
-- K5 (latest MemberCards mockup): the section starts with the worn item as its own 48 px row: 34 px icon in its
-- quality frame, gold slot name + small "EQUIPPED", the worn name(s) in quality colour (empty: dim "Slot empty"),
-- "n upgrades" on the right. Rings and trinkets stay one section (both worn items named).
---------------------------------------------------------------------------
local SECTION_H = 56 -- 6 px space above + the 48 px worn row + the 2 px gap
local WORN_ICON = 34
-- width of the suggestion list's content: follows the window (J2, set by UI:Layout)
UI.listW = RightW(MIN_W) - 30
UI.SECTION_H = SECTION_H

-- W6: the weapon sections / guild-needs categories "Main Hand / Off Hand / Ranged" (deDE "Haupthand / Nebenhand /
-- Distanz"; the client's MAINHANDSLOT etc. read differently there)
UI.HAND_SECTION = { [16] = "SECTION_MAINHAND", [17] = "SECTION_OFFHAND", [18] = "SECTION_RANGED" }
local function SectionTitle(sec)
  if #sec.slots > 1 and sec.key == 11 then return L.SECTION_RINGS end
  if #sec.slots > 1 and sec.key == 13 then return L.SECTION_TRINKETS end
  if UI.HAND_SECTION[sec.key] then return L[UI.HAND_SECTION[sec.key]] end
  return SlotName(sec.key)
end
UI.SectionTitle = SectionTitle

-- the worn item's real hyperlink (synced gear is a bare "item:" string; chat linking needs the full link)
local function WornHyperlink(x)
  local link = x and x.info and x.info.link
  if type(link) == "string" and link:find("|H", 1, true) then return link end
  if x and type(x.link) == "string" and x.link:find("|H", 1, true) then return x.link end
end

-- tooltip lines for the worn item(s) of a section: "Slot: name  12.3 AP-eq"
local function WornTipLines(sec, unit)
  for _, x in ipairs(sec.worn) do
    local name = x.info and x.info.name or (x.link and "?") or L.SECTION_NOTHING
    if x.score then
      GameTooltip:AddDoubleLine(SlotName(x.slot) .. ": " .. name, string.format(L.SECTION_SCORE, x.score, unit), 1, 1, 1, 0.6, 0.8, 1)
    else
      GameTooltip:AddLine(SlotName(x.slot) .. ": " .. name, 1, 1, 1)
    end
  end
end

-- the first worn item of a section that is there (has a link)
local function FirstWorn(sec)
  for _, x in ipairs(sec.worn or {}) do if x.link then return x end end
end

local function CreateSectionRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SECTION_H - 2)
  local box = CreateFrame("Frame", nil, b)
  box:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -6)
  box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.box = box
  -- K6: no box: a 1 px separator above the slot (WhatsTraining's recipe-row separator), as a list category
  box.line = box:CreateTexture(nil, "ARTWORK")
  box.line:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  box.line:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  box.line:SetHeight(1)
  UI.Skin(box.line, "separator")
  b.hl = box:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  UI.Skin(b.hl, "rowHover")
  AddQualityIcon(box, WORN_ICON, "LEFT", box, "LEFT", 8, 0)
  -- User 2026-11-15, strict rule for every item icon in the window: the item's name right next to the icon. The slot
  -- header is just that: icon + worn name (centred, 12 px gap) + the count on the right; no slot name, no "Equipped"
  -- (only an empty slot names its slot: "Chest (empty)").
  b.wornName = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.wornName:SetPoint("LEFT", box.qual, "RIGHT", 12, 0)
  b.wornName:SetJustifyH("LEFT")
  SingleLine(b.wornName)
  b.count = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("RIGHT", box, "RIGHT", -14, 0)
  b.count:SetJustifyH("RIGHT")
  b.count:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(b.count)
  SetTip(b, "section", function(self)
    local sec = self.data and self.data.sec
    if not sec then return end
    local unit = GCA:UnitLabel(UI.current and UI.current.weights)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local first = FirstWorn(sec)
    if #sec.worn == 1 and first and first.link then
      UI.PlainItemTip(self, first.link) -- K17: an item: the plain Blizzard tooltip only
      return
    else
      GameTooltip:SetText(SectionTitle(sec), 1, 0.82, 0)
      WornTipLines(sec, unit)
    end
    if sec.unknown and #sec.rows == 0 then
      GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true)
    elseif #sec.rows == 0 then
      GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine(string.format(L.SECTION_TIP_SHOWN, #sec.rows, sec.total or #sec.rows), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  -- the equipped item: a plain click does nothing (user 2026-11-15); Shift/Ctrl-click links it (the first one of a
  -- ring/trinket pair)
  b:SetScript("OnClick", function(self)
    if not UI.ModifiedDown() then return end
    local sec = self.data and self.data.sec
    local link = sec and WornHyperlink(FirstWorn(sec))
    if link then SafeCall(HandleModifiedItemClick, link) end
  end)
  return b
end

local function UpdateSectionRow(b, d)
  local sec = d.sec
  local parts, first = {}, nil
  for _, wx in ipairs(sec.worn) do
    if wx.info then
      parts[#parts + 1] = Hex(QualityColor(wx.info.quality)) .. (wx.info.name or "?") .. "|r"
    elseif wx.link then
      parts[#parts + 1] = C.dim .. "?|r" -- worn but not loaded
    else
      parts[#parts + 1] = C.dim .. L.CARDS_EMPTY .. "|r"
    end
    if wx.link and not first then first = wx end
  end
  local empty = first == nil
  b.wornName:SetText(empty and (C.dim .. string.format(L.SECTION_EMPTY_NAMED, SectionTitle(sec)) .. "|r")
    or table.concat(parts, C.muted .. "  ·  |r"))
  local box = b.box
  box.icon:SetTexture(first and ItemIcon(first.link) or SlotTexture(sec.key))
  box.icon:SetDesaturated(empty)
  box.icon:SetAlpha(empty and 0.45 or 1)
  if empty then SetIconQuality(box, nil, 0.35, 0.31, 0.26) else SetIconQuality(box, first.info and first.info.quality) end
  local n = #sec.rows
  b.count:SetText(n == 1 and string.format(L.CARDS_COUNT_1, n) or string.format(L.CARDS_COUNT, n))
  local countW = TextWidth(b.count)
  b.textW = math.max(40, UI.listW - (8 + WORN_ICON + 4 + 12) - countW - 14 - 12)
  b.wornName:SetWidth(b.textW)
  b.empty = empty
end
-- K1: one wrapped grey line for every slot without an upgrade (K4: "No craftable upgrade: …" in a box)
local function FoldText(secs)
  local names = {}
  for _, sec in ipairs(secs) do
    names[#names + 1] = SectionTitle(sec) .. (sec.unknown and (" " .. L.FOLD_NOT_LOADED) or "")
  end
  if GCA:SelectedProfession() == "Enchanting" then return string.format(L.CARDS_NONE_ENCH, table.concat(names, ", ")) end
  return string.format(L.CARDS_NONE, table.concat(names, ", "))
end
UI.FoldText = FoldText

local function CreateFoldRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SECTION_H - 2)
  -- K6: plain grey text under a separator (the K4 bordered box is gone)
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2)
  b.line:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -2)
  b.line:SetHeight(1)
  UI.Skin(b.line, "separator")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.text:SetPoint("TOPLEFT", 10, -9)
  b.text:SetJustifyH("LEFT")
  if b.text.SetWordWrap then b.text:SetWordWrap(true) end
  SetTip(b, "no-upgrade line", function(self)
    local secs = self.data and self.data.secs
    if not secs then return end
    local unit = GCA:UnitLabel(UI.current and UI.current.weights)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.FOLD_TIP_TITLE, 1, 0.82, 0)
    local unknown = false
    for _, sec in ipairs(secs) do
      WornTipLines(sec, unit)
      if sec.unknown then unknown = true end
    end
    GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    if unknown then GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateFoldRow(b, d)
  b.text:SetWidth(UI.listW - 20)
  b.text:SetText(FoldText(d.secs))
end

-- height of the folded line: the client's measure of the wrapped text; without one (offline harness) an estimate
-- of ~5.5 px per byte of GameFontDisableSmall (umlauts are 2 bytes, so it errs on the tall side). K4: + the box
-- padding (9 px above and below the text; the scroll list leaves a 2 px gap under each row).
local function FoldHeight(b)
  local h = b.text.GetStringHeight and SafeCall(b.text.GetStringHeight, b.text)
  if type(h) ~= "number" or GCA.IsSecret(h) or h <= 0 then
    local perLine = math.max(20, math.floor((UI.listW - 20) / 5.5))
    h = math.ceil(#(b.text:GetText() or "") / perLine) * 12
  end
  return math.max(SECTION_H, math.ceil(h) + 20)
end
UI.FoldHeight = FoldHeight

-- The list entries for one member: per section with an upgrade a header and its rows, then one
-- folded line for all slots without an upgrade. With no suggestion at all the list stays empty, so the
-- empty-state text explains why (no recipes known, …).
function UI.SectionRows(list)
  local out = {}
  if not list or #list == 0 then return out end
  if not list.sections then
    for i, s in ipairs(list) do out[i] = s end
    return out
  end
  local none = {}
  for _, sec in ipairs(list.sections) do
    if #sec.rows > 0 then
      out[#out + 1] = { rowKind = "section", sec = sec }
      for _, s in ipairs(sec.rows) do out[#out + 1] = s end
    else
      none[#none + 1] = sec -- BuildSections lists them in character order
    end
  end
  if #none > 0 then out[#out + 1] = { rowKind = "fold", secs = none } end
  return out
end

-- shared with the files loaded after this one (P)
P.CreateFoldRow = CreateFoldRow
P.CreateSectionRow = CreateSectionRow
P.FoldHeight = FoldHeight
P.SECTION_H = SECTION_H
P.UpdateFoldRow = UpdateFoldRow
P.UpdateSectionRow = UpdateSectionRow
P.WornHyperlink = WornHyperlink
