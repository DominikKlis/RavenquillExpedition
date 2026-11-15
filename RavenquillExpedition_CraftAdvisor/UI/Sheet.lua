local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, C, SUB_TINT, SetAtlasSafe, TexOK = P.SafeCall, P.C, P.SUB_TINT, P.SetAtlasSafe, P.TexOK
local SingleLine, SetTip, SlotTexture, QualityColor = P.SingleLine, P.SetTip, P.SlotTexture, P.QualityColor
local Hex, GainText, RowGainText, ShortSlotName = P.Hex, P.GainText, P.RowGainText, P.ShortSlotName
local TagLine, ItemIcon, TextWidth, NativeFont = P.TagLine, P.ItemIcon, P.TextWidth, P.NativeFont
local GAIN_RGB, GainFont, LevelTag, CardGain, Tag = P.GAIN_RGB, P.GainFont, P.LevelTag, P.CardGain, P.Tag
local ShowSuggestionTooltip, HideTip, RightState = P.ShowSuggestionTooltip, P.HideTip, P.RightState
local CreateOfferButton, CreateCraftedBox = P.CreateOfferButton, P.CreateCraftedBox
local AddQualityIcon, SetIconQuality, CraftTags = P.AddQualityIcon, P.SetIconQuality, P.CraftTags
local WornHyperlink, ModifiedDown = P.WornHyperlink, P.ModifiedDown

---------------------------------------------------------------------------
-- K4 variant "Character sheet" (Member mockup): the member's gear slots as square buttons in two columns like
-- the character window, plus the weapon row under the middle (shields, held off-hands, relics and weapon/shield
-- enchants live there; weapons since step W). The middle panel compares the selected slot: worn item ->
-- best craft (gain, stat differences, crafted box, Offer), then the slot's other crafts. Everything comes from
-- the same list.sections the list variant shows (top 3 per slot).
---------------------------------------------------------------------------
local SHEET_S = 40         -- slot button
local SHEET_COL_X = 8      -- slot columns from the panel edge
local SHEET_GAP_X = 10     -- slot column to the middle panel
local SHEET_PAD = 10       -- middle panel padding
-- user 2026-11-15 rework: the middle compares vertically (Equipped card, a down arrow, the craft card, both full
-- width); stats / tags / source sit indented under the craft card's text; slots show their best gain.
local SHEET_CARD_H = 46
local SHEET_ARROW_W = 14   -- (now the height of the arrow row between the two cards)
local SHEET_GAIN_W = 74
local SHEET_ALT_H = 26
local SHEET_STAT_H = 16
local SHEET_OFFER_W = 100
UI.SHEET_S, UI.SHEET_PAD, UI.SHEET_CARD_H, UI.SHEET_ALT_H = SHEET_S, SHEET_PAD, SHEET_CARD_H, SHEET_ALT_H
UI.SHEET_LEFT = { 1, 2, 3, 15, 5, 9, 10 }
UI.SHEET_RIGHT = { 6, 7, 8, 11, 12, 13, 14 }
UI.SHEET_BOTTOM = { 16, 17, 18 }

-- K4: which member-view variant is shown ("sheet" by default; db.settings.memberView)
function UI.MemberMode()
  local s = GCA.db and GCA.db.settings
  return (s and s.memberView == "list") and "list" or "sheet"
end

-- The rows of one sheet slot (its section's rows; rings/trinkets: only those that replace THIS ring/trinket),
-- the section and this slot's worn entry.
function UI.SheetRows(list, slot)
  local key = GCA.SECTION_OF[slot] or slot
  for _, sec in ipairs(list and list.sections or {}) do
    if sec.key == key then
      local rows, worn = {}, nil
      for _, r in ipairs(sec.rows) do
        if #sec.slots < 2 or r.slot == slot then rows[#rows + 1] = r end
      end
      for _, x in ipairs(sec.worn) do if x.slot == slot then worn = x end end
      return rows, sec, worn
    end
  end
  return {}, nil, nil
end

-- The slot with the biggest upgrade: BuildSections sorts the sections by their first row (the comparison of the
-- member order), so it is the first section's first row. No upgrade anywhere: the head.
function UI.SheetDefaultSlot(list)
  for _, sec in ipairs(list and list.sections or {}) do
    if sec.rows[1] then return sec.rows[1].slot end
  end
  return UI.SHEET_LEFT[1]
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

-- worn item tooltip (a slot button or the worn card): the item, its score, and for a slot button the upgrades
local function WornTip(owner, x, slot, unit, rows)
  slot = slot or (x and x.slot)
  if not slot then return end -- nothing filled in yet
  -- K17: a worn item = the plain Blizzard tooltip only
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

-- worn item look on a slot button / card: icon + quality frame; not loaded = question mark; empty = the slot art
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

local function CreateSheetSlot(sheet, slot)
  local b = CreateFrame("Button", nil, sheet)
  b:SetSize(SHEET_S, SHEET_S)
  b.slot = slot
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  -- selected: a gold square 3 px larger behind the button
  b.sel = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  b.sel:SetPoint("TOPLEFT", -3, 3)
  b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
  b.sel:SetColorTexture(1, 0.82, 0, 0.9)
  b.sel:Hide()
  -- K6: the character window's own gear slot (probe: CharacterHeadSlot = 37 px button, UI-Character-Info-GearSlot
  -- 55x55 behind it, IconBorder = WhiteIconFrame tinted by quality, HighlightTexture = ButtonHilight-Square ADD);
  -- scaled to our 40 px slot. Without the atlas: the K4 dark square.
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
  if SetAtlasSafe(b.bg, "UI-Character-Info-GearSlot") then
    b.bg:SetSize(math.floor(SHEET_S * 55 / 37 + 0.5), math.floor(SHEET_S * 55 / 37 + 0.5))
    b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.gearArt = true
  else
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
  end
  AddQualityIcon(b, SHEET_S - 4, "CENTER", b, "CENTER", 0, 0, true)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  if TexOK("iconHL") then
    b.hl:SetTexture(UI.TEX.iconHL)
    if b.hl.SetBlendMode then pcall(b.hl.SetBlendMode, b.hl, "ADD") end
  else
    b.hl:SetColorTexture(1, 1, 1, 0.15)
  end
  -- selected: the same highlight, kept on (as a checked item button); the gold square only without the file
  if TexOK("iconHL") then
    b.sel:ClearAllPoints()
    b.sel:SetAllPoints()
    if b.sel.SetDrawLayer then b.sel:SetDrawLayer("OVERLAY", 6) end
    b.sel:SetTexture(UI.TEX.iconHL)
    if b.sel.SetBlendMode then pcall(b.sel.SetBlendMode, b.sel, "ADD") end
    b.selKind = "file"
  end
  -- upgrade badge: the green up arrow GearQuestForever draws (Indicator.lua:5, tinted :731), else a green "+"
  if TexOK("caretUp") then
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.badge:SetTexture(UI.TEX.caretUp)
    b.badge:SetSize(14, 18)
    b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 5, 6)
    b.badge:SetVertexColor(0.12, 1, 0.12)
    b.badgeKind = "file"
  else
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 4)
    b.badge:SetText("+")
    b.badge:SetTextColor(0.3, 1, 0.3)
    b.badgeKind = "text"
  end
  b.badge:Hide()
  -- the slot's best gain on the icon's bottom edge (outlined number, as the client's item counts)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NativeFont(b.gain, "NumberFontNormalSmall")
  b.gain:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
  b.gain:SetJustifyH("RIGHT")
  b.gain:SetTextColor(GAIN_RGB[1], GAIN_RGB[2], GAIN_RGB[3])
  b.gain:Hide()
  b:SetScript("OnClick", function(self)
    if ModifiedDown() then
      local link = WornHyperlink(self.worn)
      if link then SafeCall(HandleModifiedItemClick, link) end
      return
    end
    UI:SelectSheetSlot(self.slot)
  end)
  SetTip(b, "sheet slot", function(self) WornTip(self, self.worn, self.slot, self.unit, self.rows or {}) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- comparison card: worn (left) or the featured craft (right: green tint, big gain)
local function CreateSheetCard(parent, best)
  local k = CreateFrame("Button", nil, parent)
  k:SetHeight(SHEET_CARD_H)
  k.isBest = best
  -- K6: no box, no green tint: the item in its reagent-slot frame and text on the page, as the profession
  -- window's schematic shows its output item
  AddQualityIcon(k, 36, "LEFT", k, "LEFT", 4, 0)
  -- two lines beside the icon: the item name, then "Equipped · 112 pts" (label dim, score after it); the craft
  -- card's big gain on the right
  local right = best and -(SHEET_GAIN_W + 12) or -8
  k.name = k:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  k.name:SetPoint("TOPLEFT", k.qual, "TOPRIGHT", 8, -3)
  k.name:SetPoint("RIGHT", k, "RIGHT", right, 0)
  k.name:SetJustifyH("LEFT")
  SingleLine(k.name)
  k.label = k:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  k.label:SetPoint("BOTTOMLEFT", k.qual, "BOTTOMRIGHT", 8, 4)
  k.label:SetJustifyH("LEFT")
  SingleLine(k.label)
  k.score = k:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  k.score:SetPoint("LEFT", k.label, "RIGHT", 8, 0)
  k.score:SetPoint("RIGHT", k, "RIGHT", right, 0)
  k.score:SetJustifyH("LEFT")
  k.score:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(k.score)
  -- the label is as wide as its text so the score follows it on the same line
  function k:FitLabel()
    self.label:SetWidth(math.min(TextWidth(self.label) + 2, 160))
  end
  if best then
    k.gain = k:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    GainFont(k.gain, true)
    k.gain:SetPoint("TOPRIGHT", k, "TOPRIGHT", -8, -7)
    k.gain:SetWidth(SHEET_GAIN_W)
    k.gain:SetJustifyH("RIGHT")
    SingleLine(k.gain)
    k.points = k:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k.points:SetPoint("BOTTOMRIGHT", k, "BOTTOMRIGHT", -8, 6)
    k.points:SetWidth(SHEET_GAIN_W)
    k.points:SetJustifyH("RIGHT")
    k.points:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
    SingleLine(k.points)
  end
  SetTip(k, best and "sheet craft" or "sheet worn", function(self)
    if self.isBest then
      if self.data then ShowSuggestionTooltip(self, self.data, UI.current) end
    else
      WornTip(self, self.worn, self.slot, self.unit)
    end
  end)
  k:SetScript("OnLeave", HideTip)
  if best and k.RegisterForClicks then k:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  k:SetScript("OnClick", function(self, button)
    if self.isBest and UI.SourceClick(self, button, self.data, UI.current) then return end
    if not ModifiedDown() then
      if self.isBest then UI.OpenRecipe(self.data, UI.current) end -- user 2026-11-15
      return
    end
    local link
    if self.isBest then link = self.data and self.data.info.link else link = WornHyperlink(self.worn) end
    if link then SafeCall(HandleModifiedItemClick, link) end
  end)
  return k
end

-- one of the slot's other crafts ("More options"): icon, name, level/enchant/not-learned tag (K6: coloured text),
-- gain, the red Offer button. Click: compare it in the cards above; Shift-click: link.
local function CreateSheetAlt(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(SHEET_ALT_H)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  UI.Skin(r.hl, "rowHover")
  AddQualityIcon(r, 20, "LEFT", r, "LEFT", 3, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.name:SetPoint("LEFT", r.qual, "RIGHT", 8, 0)
  r.name:SetJustifyH("LEFT")
  SingleLine(r.name)
  r.offer = CreateOfferButton(r)
  r.gain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.gain:SetWidth(90)
  r.gain:SetJustifyH("RIGHT")
  SingleLine(r.gain)
  r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.tag:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
  r.tag:SetJustifyH("RIGHT")
  SingleLine(r.tag)
  SetTip(r, "sheet alternative", function(self)
    if not self.data then return end
    ShowSuggestionTooltip(self, self.data, UI.current) -- K17: plain item tooltip
  end)
  r:SetScript("OnLeave", HideTip)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r:SetScript("OnClick", function(self, button)
    local d = self.data
    if not d then return end
    if UI.SourceClick(self, button, d, UI.current) then return end
    if ModifiedDown() then
      if d.info.link then SafeCall(HandleModifiedItemClick, d.info.link) end
      return
    end
    UI:PickSheetRow(d)
  end)
  return r
end

local function FillSheetAlt(r, d, cur, width)
  r.data = d
  r.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(r, d.info.quality)
  r.name:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r")
  local showOffer = UI.CanOffer(cur, d)
  r.offer:SetShown(showOffer)
  r.offer:ClearAllPoints()
  r.offer:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.gain:ClearAllPoints()
  if showOffer then r.gain:SetPoint("RIGHT", r.offer, "LEFT", -6, 0) else r.gain:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
  r.gain:SetText(RowGainText(d))
  local tag
  if d.future and d.wearAt then
    tag = Tag(LevelTag(d), C.levelTag)
  elseif d.kind == "enchant" then
    tag = Tag(L.ENCHANT_TAG, C.known)
  elseif not d.known then
    tag = UI.LearnText(d, cur) -- the same red source text as everywhere (user 2026-11-15)
  end
  r.tag:SetText(tag or "")
  local cw = 0
  if tag then
    cw = math.min(TextWidth(r.tag), 160)
    r.tag:SetWidth(cw)
    cw = cw + 8
  end
  r.tag:SetShown(tag ~= nil)
  local offerW = showOffer and ((r.offer.GetWidth and r.offer:GetWidth() or UI.OFFER_SMALL_W) + 4) or 0
  r.name:SetWidth(math.max(20, width - (3 + 24 + 8) - cw - 90 - 6 - offerW - 6))
  local a = d.future and 0.55 or 1
  for _, x in ipairs({ r.qual, r.iconBorder, r.icon, r.name, r.gain, r.tag }) do x:SetAlpha(a) end
  r.dimmed = d.future and true or false
end

local function CreateSheet(parent)
  local sh = CreateFrame("Frame", nil, parent)
  sh.slots = {}
  for _, list in ipairs({ UI.SHEET_LEFT, UI.SHEET_RIGHT, UI.SHEET_BOTTOM }) do
    for _, slot in ipairs(list) do sh.slots[slot] = CreateSheetSlot(sh, slot) end
  end
  local c = CreateFrame("Frame", nil, sh)
  sh.centre = c -- K6: no box of its own: it sits on the list panel's art like the schematic on the page
  c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.header:SetJustifyH("LEFT")
  SingleLine(c.header)
  c.count = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.count:SetJustifyH("LEFT")
  c.count:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.count)
  c.sepTop = c:CreateTexture(nil, "ARTWORK") -- hairline under the header line
  c.sepTop:SetHeight(1)
  UI.Skin(c.sepTop, "separator")
  c.worn = CreateSheetCard(c, false)
  c.best = CreateSheetCard(c, true)
  -- down arrow under the Equipped icon, pointing at the craft (the proven caret file; else a "v")
  if TexOK("caretDown") then
    c.arrow = c:CreateTexture(nil, "ARTWORK")
    c.arrow:SetTexture(UI.TEX.caretDown)
    c.arrow:SetSize(14, SHEET_ARROW_W)
    c.arrow:SetVertexColor(GAIN_RGB[1], GAIN_RGB[2], GAIN_RGB[3])
    c.arrowKind = "file"
  else
    c.arrow = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.arrow:SetSize(14, SHEET_ARROW_W)
    c.arrow:SetJustifyH("CENTER")
    c.arrow:SetText("v")
    c.arrowKind = "text"
  end
  c.stats = {}
  for i = 1, 6 do
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    SingleLine(fs)
    c.stats[i] = fs
  end
  c.tags = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.tags:SetJustifyH("LEFT")
  c.tags:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.tags)
  c.source = UI.CreateLearnButton(c) -- user 2026-11-15: the shared source button (same as cards / Gildenbedarf)
  c.offer = P.CreateOfferTextButton(c, c.best, SHEET_OFFER_W)
  c.crafted = CreateCraftedBox(c, c.best)
  c.craftedLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.craftedLabel:SetJustifyH("LEFT")
  SingleLine(c.craftedLabel)
  c.none = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  c.none:SetJustifyH("LEFT")
  c.sep = c:CreateTexture(nil, "ARTWORK")
  c.sep:SetHeight(1)
  UI.Skin(c.sep, "separator")
  c.moreTitle = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.moreTitle:SetJustifyH("LEFT")
  SingleLine(c.moreTitle)
  c.alts = {}
  function c:Alt(i)
    if not self.alts[i] then self.alts[i] = CreateSheetAlt(self) end
    return self.alts[i]
  end
  sh.iw, sh.wornW, sh.bestW = 300, 110, 166
  return sh
end

-- Positions everything that depends on the panel size (UI:Layout): slot columns (spacing follows the height,
-- 4..12 px), weapon row centred under the middle panel, middle panel between the columns, card widths.
-- w, h = the sheet's size (the suggestion inset minus 4 px on each side).
function UI:LayoutSheet(w, h)
  local sh = self.sheet
  if not sh then return end
  sh.w, sh.h = w, h
  local S = SHEET_S
  local gapY = math.max(4, math.min(12, math.floor((h - 16 - 7 * S) / 6)))
  sh.gapY = gapY
  for i, slot in ipairs(UI.SHEET_LEFT) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", sh, "TOPLEFT", SHEET_COL_X, -(8 + (i - 1) * (S + gapY)))
  end
  for i, slot in ipairs(UI.SHEET_RIGHT) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", sh, "TOPRIGHT", -SHEET_COL_X, -(8 + (i - 1) * (S + gapY)))
  end
  local rowW = #UI.SHEET_BOTTOM * S + (#UI.SHEET_BOTTOM - 1) * 12
  for i, slot in ipairs(UI.SHEET_BOTTOM) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", sh, "BOTTOMLEFT", math.floor((w - rowW) / 2) + (i - 1) * (S + 12), 8)
  end
  local side = SHEET_COL_X + S + SHEET_GAP_X
  local c = sh.centre
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", sh, "TOPLEFT", side, -8)
  c:SetPoint("BOTTOMRIGHT", sh, "BOTTOMRIGHT", -side, 8 + S + 8)
  sh.cw, sh.ch = w - 2 * side, h - 8 - (8 + S + 8)
  sh.iw = sh.cw - 2 * SHEET_PAD
  sh.wornW, sh.bestW = sh.iw, sh.iw -- user 2026-11-15: stacked, both full width
  self:PlaceSheet()
end

-- Stacks the middle panel's parts from the top (only the shown ones take room). c.contentH = the height used.
function UI:PlaceSheet()
  local sh = self.sheet
  if not sh then return end
  local c, pad, iw = sh.centre, SHEET_PAD, sh.iw
  local y = pad
  local headerW = math.min(TextWidth(c.header) + 2, math.floor(iw / 2))
  c.header:ClearAllPoints()
  c.header:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  c.header:SetWidth(headerW)
  -- the count right-aligned on the header line (the slot name left), a hairline under both
  c.count:ClearAllPoints()
  c.count:SetPoint("TOPRIGHT", c, "TOPRIGHT", -pad, -(y + 1))
  c.count:SetWidth(math.max(1, iw - headerW - 10))
  c.count:SetJustifyH("RIGHT")
  y = y + 20
  c.sepTop:ClearAllPoints()
  c.sepTop:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  c.sepTop:SetPoint("TOPRIGHT", c, "TOPRIGHT", -pad, -y)
  y = y + 6
  c.worn:ClearAllPoints()
  c.worn:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  c.worn:SetWidth(sh.wornW)
  c.worn:FitLabel()
  y = y + SHEET_CARD_H
  -- the arrow row, centred under the Equipped icon (icon frame: 4 px in, 40 px wide)
  c.arrow:ClearAllPoints()
  c.arrow:SetPoint("TOPLEFT", c, "TOPLEFT", pad + 4 + 20 - 7, -(y + 1))
  c.none:ClearAllPoints()
  c.none:SetPoint("TOPLEFT", c, "TOPLEFT", pad + 52, -(y + 4))
  c.none:SetWidth(math.max(1, iw - 52))
  if c.mode ~= "upgrade" then y = y + 24 end
  if c.mode == "upgrade" then
    y = y + SHEET_ARROW_W + 2
    c.best:ClearAllPoints()
    c.best:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
    c.best:SetWidth(sh.bestW)
    c.best:FitLabel()
    y = y + SHEET_CARD_H + 4
    -- the details belong to the craft: indented to its text column
    local ind = 52
    local dw = iw - ind
    -- actions at the top right of the details: Offer at the right, the crafted box + its label left of it
    local y0 = y
    local right = pad
    c.offer:ClearAllPoints()
    c.offer:SetPoint("TOPRIGHT", c, "TOPRIGHT", -right, -y0)
    if c.offer:IsShown() then right = right + SHEET_OFFER_W + 14 end
    local labelW = TextWidth(c.craftedLabel)
    c.craftedLabel:SetWidth(labelW)
    c.crafted:ClearAllPoints()
    c.crafted:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(right + labelW + 4), -y0)
    c.craftedLabel:ClearAllPoints()
    c.craftedLabel:SetPoint("LEFT", c.crafted, "RIGHT", 4, 0)
    if c.crafted:IsShown() then right = right + labelW + 4 + 26 end
    local hasActions = c.offer:IsShown() or c.crafted:IsShown()
    -- user 2026-11-15: the stat changes one per line, as in the item tooltip, left of the actions
    local statW = math.max(60, iw - ind - (right - pad) - 8)
    local n = c.nStats or 0
    for i, fs in ipairs(c.stats) do
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", c, "TOPLEFT", pad + ind, -(y + (i - 1) * SHEET_STAT_H))
      fs:SetWidth(statW)
    end
    if n > 0 then y = y + n * SHEET_STAT_H + 2 end
    if hasActions then y = math.max(y, y0 + 26) end
    c.tags:ClearAllPoints()
    c.tags:SetPoint("TOPLEFT", c, "TOPLEFT", pad + ind, -y)
    c.tags:SetWidth(dw)
    if c.hasTags then y = y + SHEET_STAT_H end
    c.source:ClearAllPoints()
    c.source:SetPoint("TOPLEFT", c, "TOPLEFT", pad + ind, -y)
    c.sourceW = dw -- the learn button sizes itself up to this (UI.UpdateLearnButton)
    if c.hasSource then y = y + SHEET_STAT_H end
    y = y + 4
    -- "More options": only as many as fit the panel (sh.ch); the title says how many more ("(+2)")
    local avail = sh.ch or math.huge
    local nAlts = c.nAlts or 0
    local fit = 0
    if nAlts > 0 then
      local free = avail - (y + 12 + 16 + pad - 10)
      fit = math.max(0, math.min(nAlts, math.floor((free + 2) / (SHEET_ALT_H + 2))))
    end
    c.nAltsShown = fit
    c.sep:SetShown(fit > 0)
    c.moreTitle:SetShown(fit > 0)
    for i = 1, nAlts do c.alts[i]:SetShown(i <= fit) end
    if fit > 0 then
      y = y + 6
      c.sep:ClearAllPoints()
      c.sep:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
      c.sep:SetPoint("TOPRIGHT", c, "TOPRIGHT", -pad, -y)
      y = y + 6
      c.moreTitle:ClearAllPoints()
      c.moreTitle:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
      c.moreTitle:SetWidth(iw)
      c.moreTitle:SetText(L.SHEET_MORE .. (fit < nAlts and string.format(" (+%d)", nAlts - fit) or ""))
      y = y + 16
      for i = 1, fit do
        local r = c.alts[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
        r:SetWidth(iw)
        FillSheetAlt(r, r.data, UI.current, iw)
        y = y + SHEET_ALT_H + 2
      end
    end
  end
  c.contentH = y + pad - 10
end

-- Fills the sheet for one member. Selected slot: kept while the same member + profession is shown and you
-- picked it; else the slot with the biggest upgrade (recomputed on every refresh until you pick one).
-- why: the empty-state reason when the member has no suggestion at all (shown in the middle panel).
function UI:UpdateSheet(cur, list, prof, why)
  local sh = self.sheet
  local forKey = tostring(cur.key) .. "|" .. tostring(prof)
  if self.sheetFor ~= forKey then self.sheetFor, self.sheetAuto, self.sheetPickSug = forKey, true, nil end
  if self.sheetAuto or not self.sheetSlot then self.sheetSlot = UI.SheetDefaultSlot(list) end
  local unit = GCA:UnitLabel(cur.weights)
  local enchanting = prof == "Enchanting"
  for slot, b in pairs(sh.slots) do
    local rows, _, worn = UI.SheetRows(list, slot)
    b.worn, b.rows, b.unit = worn, rows, unit
    FillWornIcon(b, worn, slot)
    b.empty = not (worn and worn.link)
    b.selected = slot == self.sheetSlot
    b.sel:SetShown(b.selected)
    local allFuture = #rows > 0
    for _, r in ipairs(rows) do if not r.future then allFuture = false end end
    b.hasUpgrade = #rows > 0
    b.badge:SetShown(b.hasUpgrade)
    b.badge:SetAlpha(allFuture and 0.5 or 1) -- only too-high-level crafts: a dimmed arrow
    -- user 2026-11-15: the best gain on the slot; a worn item without an upgrade recedes
    b.gain:SetText(b.hasUpgrade and UI.GainNum(rows[1].points) or "")
    b.gain:SetShown(b.hasUpgrade)
    b.gain:SetAlpha(allFuture and 0.5 or 1)
    if not b.hasUpgrade and worn and worn.info and not b.selected then b.icon:SetAlpha(0.5) end
  end
  local c = sh.centre
  local slot = self.sheetSlot
  local rows, _, worn = UI.SheetRows(list, slot)
  local d = rows[1]
  if self.sheetPickSug then
    for _, r in ipairs(rows) do if r == self.sheetPickSug then d = r end end
  end
  c.slot, c.rows, c.featured = slot, rows, d
  c.header:SetText(ShortSlotName(slot))
  c.count:SetText(SheetCountText(#rows, enchanting))
  c.worn.slot, c.worn.unit = slot, unit
  if d then
    c.mode = "upgrade"
    local dUnit = GCA:UnitLabel(d.e)
    FillWornIcon(c.worn, worn, slot)
    c.worn.worn = worn
    c.worn.label:SetText(L.SHEET_WORN)
    c.worn.name:SetText(worn and worn.info and (Hex(QualityColor(worn.info.quality)) .. (worn.info.name or "?") .. "|r")
      or (C.dim .. (worn and worn.link and "?" or L.SECTION_NOTHING) .. "|r"))
    c.worn.score:SetText(d.status ~= "empty-slot" and string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.oldScore or 0), dUnit) or "")
    local k = c.best
    k.data = d
    local label
    if d ~= rows[1] then label = L.SHEET_PICKED elseif d.kind == "enchant" then label = L.SHEET_BEST_ENCH else label = L.SHEET_BEST end
    k.label:SetText(label)
    k.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
    SetIconQuality(k, d.info.quality)
    k.name:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r")
    k.score:SetText(string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.newScore or 0), dUnit))
    local big, small = CardGain(d)
    k.gain:SetText(big)
    k.points:SetText(small)
    local a = d.future and 0.55 or 1
    for _, x in ipairs({ k.qual, k.iconBorder, k.icon, k.name, k.gain }) do x:SetAlpha(a) end
    k.dimmed = d.future and true or false
    k:Show()
    c.arrow:Show()
    -- stat differences (only when both sides have stat data) + the tags
    local diffs, partial = UI.StatDiff(d)
    c.nStats = 0
    for i, fs in ipairs(c.stats) do
      local r = diffs and diffs[i]
      if r then fs:SetText(UI.StatText(r, true)); fs:Show(); c.nStats = i else fs:SetText(""); fs:Hide() end
    end
    c.diffs = diffs
    local tags = CraftTags(d, cur, true, true)
    if diffs and #diffs > #c.stats then tags[#tags + 1] = { string.format(L.STATS_MORE, #diffs - #c.stats) } end
    if partial then tags[#tags + 1] = { L.STATS_PARTIAL } end
    c.tags:SetText(TagLine(tags))
    c.hasTags = #tags > 0
    c.tags:SetShown(c.hasTags)
    c.hasSource = UI.UpdateLearnButton(c.source, d, cur, c.sourceW) > 0
    local showOffer, showCheck, mark = RightState(d, cur)
    c.offer:SetShown(showOffer)
    c.crafted:SetShown(showCheck)
    c.crafted:SetChecked(mark ~= nil)
    c.craftedLabel:SetText(d.kind == "enchant" and L.ENCHANTED or L.CRAFTED)
    c.craftedLabel:SetShown(showCheck)
    c.none:Hide()
    local others = {}
    for _, r in ipairs(rows) do if r ~= d then others[#others + 1] = r end end
    for i, r in ipairs(others) do
      local alt = c:Alt(i)
      alt.data = r
      alt:Show()
    end
    for i = #others + 1, #c.alts do c.alts[i]:Hide(); c.alts[i].data = nil end
    c.nAlts = #others
    c.sep:SetShown(#others > 0)
    c.moreTitle:SetText(L.SHEET_MORE)
    c.moreTitle:SetShown(#others > 0)
  else
    c.mode = "none"
    FillWornIcon(c.worn, worn, slot)
    c.worn.worn = worn
    c.worn.label:SetText(L.SHEET_WORN)
    c.worn.name:SetText(worn and worn.info and (Hex(QualityColor(worn.info.quality)) .. (worn.info.name or "?") .. "|r")
      or (C.dim .. (worn and worn.link and "?" or L.SECTION_NOTHING) .. "|r"))
    c.worn.score:SetText(worn and worn.score and string.format(L.SECTION_SCORE, worn.score, unit) or "")
    c.best:Hide(); c.best.data = nil
    c.arrow:Hide()
    for _, fs in ipairs(c.stats) do fs:SetText(""); fs:Hide() end
    c.nStats, c.diffs, c.hasTags = 0, nil, false
    c.tags:SetText(""); c.tags:Hide()
    c.hasSource = false
    UI.UpdateLearnButton(c.source, nil)
    c.offer:Hide(); c.crafted:Hide(); c.craftedLabel:Hide()
    for _, r in ipairs(c.alts) do r:Hide(); r.data = nil end
    c.nAlts = 0
    c.sep:Hide(); c.moreTitle:Hide()
    local msg
    if #list == 0 and why and why ~= "" then
      msg = why
    elseif worn and worn.unknown then
      msg = L.SECTION_TIP_UNKNOWN
    elseif enchanting then
      msg = L.SHEET_NONE_ENCH
    else
      msg = L.SHEET_NONE
    end
    c.none:SetText(msg)
    c.none:Show()
  end
  self:PlaceSheet()
end

function UI:SelectSheetSlot(slot)
  self.sheetSlot, self.sheetAuto, self.sheetPickSug = slot, false, nil
  self:Refresh()
end

-- an alternative clicked: compare it in the cards (the slot stays, now as your pick)
function UI:PickSheetRow(d)
  self.sheetPickSug, self.sheetAuto = d, false
  self:Refresh()
end

-- shared with the files loaded after this one (P)
P.CreateSheet = CreateSheet
