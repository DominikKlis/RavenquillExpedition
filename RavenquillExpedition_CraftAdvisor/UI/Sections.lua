local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local Label = P.Label
local SafeCall, C, SUB_TINT = P.SafeCall, P.C, P.SUB_TINT
local SingleLine, SetTip, SlotName, SlotTexture = P.SingleLine, P.SetTip, P.SlotName, P.SlotTexture
local ColoredItemName, ItemIcon, TextWidth = P.ColoredItemName, P.ItemIcon, P.TextWidth
local AddQualityIcon, SetIconQuality = P.AddQualityIcon, P.SetIconQuality
local ShortSlotName, GainText = P.ShortSlotName, P.GainText

local SECTION_H = 56
local WORN_ICON = 34
UI.SECTION_H = SECTION_H

UI.HAND_SECTION = { [16] = "SECTION_MAINHAND", [17] = "SECTION_OFFHAND", [18] = "SECTION_RANGED" }
local function SectionTitle(sec)
  if #sec.slots > 1 and sec.key == 11 then return L.SECTION_RINGS end
  if #sec.slots > 1 and sec.key == 13 then return L.SECTION_TRINKETS end
  if UI.HAND_SECTION[sec.key] then return L[UI.HAND_SECTION[sec.key]] end
  return SlotName(sec.key)
end
UI.SectionTitle = SectionTitle

local function WornHyperlink(x)
  local link = x and x.info and x.info.link
  if type(link) == "string" and link:find("|H", 1, true) then return link end
  if x and type(x.link) == "string" and x.link:find("|H", 1, true) then return x.link end
end

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
  box.line = box:CreateTexture(nil, "ARTWORK")
  box.line:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  box.line:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  box.line:SetHeight(1)
  UI.Skin(box.line, "separator")
  b.hl = box:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  UI.Skin(b.hl, "rowHover")
  AddQualityIcon(box, WORN_ICON, "LEFT", box, "LEFT", 8, 0)
  b.wornName = Label(box, "GameFontNormal")
  b.wornName:SetPoint("LEFT", box.qual, "RIGHT", 12, 0)
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
      UI.PlainItemTip(self, first.link)
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
  P.OnItemClick(b, function(self)
    local sec = self.data and self.data.sec
    return nil, nil, sec and WornHyperlink(FirstWorn(sec))
  end)
  return b
end

local function WornPart(wx)
  if wx.info then return ColoredItemName(wx.info) end
  if wx.link then return C.dim .. "?|r" end
  return C.dim .. L.CARDS_EMPTY .. "|r"
end

local function WornSummary(sec, first)
  if not first then return C.dim .. string.format(L.SECTION_EMPTY_NAMED, SectionTitle(sec)) .. "|r" end
  local parts = {}
  for _, wx in ipairs(sec.worn) do parts[#parts + 1] = WornPart(wx) end
  return table.concat(parts, C.muted .. "  ·  |r")
end

local function PaintSectionIcon(box, sec, first)
  local empty = first == nil
  box.icon:SetTexture(first and ItemIcon(first.link) or SlotTexture(sec.key))
  box.icon:SetDesaturated(empty)
  box.icon:SetAlpha(empty and 0.45 or 1)
  if empty then SetIconQuality(box, nil, 0.35, 0.31, 0.26) else SetIconQuality(box, first.info and first.info.quality) end
end

local function UpdateSectionRow(b, d, listW)
  local sec = d.sec
  local first = FirstWorn(sec)
  b.wornName:SetText(WornSummary(sec, first))
  PaintSectionIcon(b.box, sec, first)
  local n = #sec.rows
  b.count:SetText(n == 1 and string.format(L.CARDS_COUNT_1, n) or string.format(L.CARDS_COUNT, n))
  local countW = TextWidth(b.count)
  b.textW = math.max(40, listW - (8 + WORN_ICON + 4 + 12) - countW - 14 - 12)
  b.wornName:SetWidth(b.textW)
  b.empty = first == nil
end
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

local function UpdateFoldRow(b, d, listW)
  b.text:SetWidth(listW - 20)
  b.text:SetText(FoldText(d.secs))
end

local function FoldHeight(b, _, listW)
  local h = b.text.GetStringHeight and SafeCall(b.text.GetStringHeight, b.text)
  if type(h) ~= "number" or GCA.IsSecret(h) or h <= 0 then
    local perLine = math.max(20, math.floor((listW - 20) / 5.5))
    h = math.ceil(#(b.text:GetText() or "") / perLine) * 12
  end
  return math.max(SECTION_H, math.ceil(h) + 20)
end
UI.FoldHeight = FoldHeight

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
      none[#none + 1] = sec
    end
  end
  if #none > 0 then out[#out + 1] = { rowKind = "fold", secs = none } end
  return out
end

function UI.MemberMode()
  local s = GCA.db and GCA.db.settings
  return (s and s.memberView == "list") and "list" or "sheet"
end

function UI.SheetDefaultSlot(list)
  return GCA.TopUpgradeSlot(list) or UI.SHEET_LEFT[1]
end

local function SheetCountText(n, enchanting)
  if enchanting then
    if n == 1 then return L.SHEET_COUNT_ENCH_1 end
    return string.format(L.SHEET_COUNT_ENCH, n)
  end
  if n == 1 then return L.SHEET_COUNT_1 end
  return string.format(L.SHEET_COUNT, n)
end
UI.SheetCountText = SheetCountText

local function WornTip(owner, x, slot, unit, rows)
  slot = slot or (x and x.slot)
  if not slot then return end
  if x and x.link then return UI.PlainItemTip(owner, x.link) end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(string.format(L.SLOT_EMPTY, ShortSlotName(slot)))
  if rows then
    if #rows > 0 then
      GameTooltip:AddLine(SheetCountText(#rows, GCA:SelectedProfession() == "Enchanting"), 0.3, 1, 0.3)
      GameTooltip:AddLine(string.format(L.SHEET_SLOT_BEST, rows[1].info.name or "?", GainText(rows[1])), 1, 1, 1, true)
    elseif x and x.unknown then
      GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(L.SHEET_SLOT_CLICK, 0.5, 0.5, 0.5, true)
  end
  GameTooltip:Show()
end

local function FillWornIcon(f, x, slot)
  if x and x.info then
    f.icon:SetTexture(x.info.icon or ItemIcon(x.link))
    f.icon:SetDesaturated(false)
    f.icon:SetAlpha(1)
    SetIconQuality(f, x.info.quality)
  elseif x and x.link then
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:SetDesaturated(true)
    f.icon:SetAlpha(0.6)
    SetIconQuality(f, nil, 0.3, 0.3, 0.3)
  else
    f.icon:SetTexture(SlotTexture(slot))
    f.icon:SetDesaturated(true)
    f.icon:SetAlpha(0.45)
    SetIconQuality(f, nil, 0.23, 0.2, 0.17)
  end
end

P.WornTip, P.FillWornIcon, P.SheetCountText = WornTip, FillWornIcon, SheetCountText
P.CreateFoldRow = CreateFoldRow
P.CreateSectionRow = CreateSectionRow
P.FoldHeight = FoldHeight
P.SECTION_H = SECTION_H
P.UpdateFoldRow = UpdateFoldRow
P.UpdateSectionRow = UpdateSectionRow
P.WornHyperlink = WornHyperlink
