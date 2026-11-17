local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local C, SUB_TINT, SetAtlasSafe, TexOK = P.C, P.SUB_TINT, P.SetAtlasSafe, P.TexOK
local SingleLine, SetTip, ColoredItemName = P.SingleLine, P.SetTip, P.ColoredItemName
local RowGainText, ShortSlotName = P.RowGainText, P.ShortSlotName
local TagLine, ItemIcon, TextWidth, NativeFont = P.TagLine, P.ItemIcon, P.TextWidth, P.NativeFont
local GAIN_RGB, GainFont, LevelTag, CardGain, Tag = P.GAIN_RGB, P.GainFont, P.LevelTag, P.CardGain, P.Tag
local ShowSuggestionTooltip, HideTip, RightState = P.ShowSuggestionTooltip, P.HideTip, P.RightState
local CreateOfferButton, CreateCraftedBox = P.CreateOfferButton, P.CreateCraftedBox
local AddQualityIcon, SetIconQuality, CraftTags = P.AddQualityIcon, P.SetIconQuality, P.CraftTags
local WornHyperlink, OnItemClick = P.WornHyperlink, P.OnItemClick
local WornTip, FillWornIcon, SheetCountText = P.WornTip, P.FillWornIcon, P.SheetCountText

local SHEET_S = 40
local SHEET_COL_X = 8
local SHEET_GAP_X = 10
local SHEET_PAD = 10
local SHEET_CARD_H = 46
local SHEET_ARROW_W = 14
local SHEET_GAIN_W = 74
local SHEET_ALT_H = 26
local SHEET_STAT_H = 16
local SHEET_OFFER_W = 100
UI.SHEET_S, UI.SHEET_PAD, UI.SHEET_CARD_H, UI.SHEET_ALT_H = SHEET_S, SHEET_PAD, SHEET_CARD_H, SHEET_ALT_H
UI.SHEET_LEFT = { 1, 2, 3, 15, 5, 9, 10 }
UI.SHEET_RIGHT = { 6, 7, 8, 11, 12, 13, 14 }
UI.SHEET_BOTTOM = { 16, 17, 18 }

local function UseHighlightFile(tex)
  tex:SetTexture(UI.TEX.iconHL)
  if tex.SetBlendMode then pcall(tex.SetBlendMode, tex, "ADD") end
end

local function CreateSheetSlot(sheet, slot)
  local b = CreateFrame("Button", nil, sheet)
  b:SetSize(SHEET_S, SHEET_S)
  b.slot = slot
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b.sel = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  b.sel:SetPoint("TOPLEFT", -3, 3)
  b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
  b.sel:SetColorTexture(1, 0.82, 0, 0.9)
  b.sel:Hide()
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
    UseHighlightFile(b.hl)
    b.sel:ClearAllPoints()
    b.sel:SetAllPoints()
    if b.sel.SetDrawLayer then b.sel:SetDrawLayer("OVERLAY", 6) end
    UseHighlightFile(b.sel)
    b.selKind = "file"
  else
    b.hl:SetColorTexture(1, 1, 1, 0.15)
  end
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
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NativeFont(b.gain, "NumberFontNormalSmall")
  b.gain:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
  b.gain:SetJustifyH("RIGHT")
  b.gain:SetTextColor(GAIN_RGB[1], GAIN_RGB[2], GAIN_RGB[3])
  b.gain:Hide()
  OnItemClick(b, function(self) return nil, nil, WornHyperlink(self.worn) end, function(_, _, self) UI:SelectSheetSlot(self.slot) end)
  SetTip(b, "sheet slot", function(self) WornTip(self, self.worn, self.slot, self.unit, self.rows or {}) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function CreateSheetCard(parent, best)
  local k = CreateFrame("Button", nil, parent)
  k:SetHeight(SHEET_CARD_H)
  k.isBest = best
  AddQualityIcon(k, 36, "LEFT", k, "LEFT", 4, 0)
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
  if best then
    if k.RegisterForClicks then k:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    OnItemClick(k, function(self) return self.data, UI.current, self.data and self.data.info.link end, UI.OpenRecipe)
  else
    OnItemClick(k, function(self) return nil, nil, WornHyperlink(self.worn) end)
  end
  return k
end

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
    ShowSuggestionTooltip(self, self.data, UI.current)
  end)
  r:SetScript("OnLeave", HideTip)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  OnItemClick(r, function(self)
    local d = self.data
    if d then return d, UI.current, d.info.link end
  end, function(d)
    if d then UI:PickSheetRow(d) end
  end)
  return r
end

local Fill, Place = {}, {}

function Fill.AltTag(d, cur)
  if d.future and d.wearAt then return Tag(LevelTag(d), C.levelTag) end
  if d.kind == "enchant" then return Tag(L.ENCHANT_TAG, C.known) end
  if not d.known then return UI.LearnText(d, cur) end
  return nil
end
function Fill.OfferWidth(r, showOffer)
  if not showOffer then return 0 end
  local w = r.offer.GetWidth and r.offer:GetWidth() or UI.OFFER_SMALL_W
  return w + 4
end
function Fill.AltTagWidth(r, tag)
  r.tag:SetText(tag or "")
  local cw = 0
  if tag then
    cw = math.min(TextWidth(r.tag), 160)
    r.tag:SetWidth(cw)
    cw = cw + 8
  end
  r.tag:SetShown(tag ~= nil)
  return cw
end

local function FillSheetAlt(r, d, cur, width)
  r.data = d
  r.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(r, d.info.quality)
  r.name:SetText(ColoredItemName(d.info))
  local showOffer = UI.CanOffer(cur, d)
  r.offer:SetShown(showOffer)
  r.offer:ClearAllPoints()
  r.offer:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.gain:ClearAllPoints()
  if showOffer then r.gain:SetPoint("RIGHT", r.offer, "LEFT", -6, 0) else r.gain:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
  r.gain:SetText(RowGainText(d))
  local cw = Fill.AltTagWidth(r, Fill.AltTag(d, cur))
  local offerW = Fill.OfferWidth(r, showOffer)
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
  sh.centre = c
  c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.header:SetJustifyH("LEFT")
  SingleLine(c.header)
  c.count = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.count:SetJustifyH("LEFT")
  c.count:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.count)
  c.sepTop = c:CreateTexture(nil, "ARTWORK")
  c.sepTop:SetHeight(1)
  UI.Skin(c.sepTop, "separator")
  c.worn = CreateSheetCard(c, false)
  c.best = CreateSheetCard(c, true)
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
  c.source = UI.CreateLearnButton(c)
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
  sh.wornW, sh.bestW = sh.iw, sh.iw
  self:PlaceSheet()
end

Place.INDENT = 52

function Place.Header(c, pad, iw, y)
  local headerW = math.min(TextWidth(c.header) + 2, math.floor(iw / 2))
  c.header:ClearAllPoints()
  c.header:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  c.header:SetWidth(headerW)
  c.count:ClearAllPoints()
  c.count:SetPoint("TOPRIGHT", c, "TOPRIGHT", -pad, -(y + 1))
  c.count:SetWidth(math.max(1, iw - headerW - 10))
  c.count:SetJustifyH("RIGHT")
  y = y + 20
  Place.Separator(c, c.sepTop, pad, y)
  return y + 6
end
function Place.Separator(c, sep, pad, y)
  sep:ClearAllPoints()
  sep:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  sep:SetPoint("TOPRIGHT", c, "TOPRIGHT", -pad, -y)
end
function Place.Card(c, card, pad, y, w)
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", c, "TOPLEFT", pad, -y)
  card:SetWidth(w)
  card:FitLabel()
end
function Place.Worn(sh, c, pad, y)
  Place.Card(c, c.worn, pad, y, sh.wornW)
  y = y + SHEET_CARD_H
  c.arrow:ClearAllPoints()
  c.arrow:SetPoint("TOPLEFT", c, "TOPLEFT", pad + 4 + 20 - 7, -(y + 1))
  c.none:ClearAllPoints()
  c.none:SetPoint("TOPLEFT", c, "TOPLEFT", pad + Place.INDENT, -(y + 4))
  c.none:SetWidth(math.max(1, sh.iw - Place.INDENT))
  return y
end
function Place.Actions(c, pad, y)
  local right = pad
  c.offer:ClearAllPoints()
  c.offer:SetPoint("TOPRIGHT", c, "TOPRIGHT", -right, -y)
  if c.offer:IsShown() then right = right + SHEET_OFFER_W + 14 end
  local labelW = TextWidth(c.craftedLabel)
  c.craftedLabel:SetWidth(labelW)
  c.crafted:ClearAllPoints()
  c.crafted:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(right + labelW + 4), -y)
  c.craftedLabel:ClearAllPoints()
  c.craftedLabel:SetPoint("LEFT", c.crafted, "RIGHT", 4, 0)
  if c.crafted:IsShown() then right = right + labelW + 4 + 26 end
  return right
end
function Place.Stats(c, pad, iw, y, right)
  local y0 = y
  local hasActions = c.offer:IsShown() or c.crafted:IsShown()
  local statW = math.max(60, iw - Place.INDENT - (right - pad) - 8)
  local n = c.nStats or 0
  for i, fs in ipairs(c.stats) do
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", c, "TOPLEFT", pad + Place.INDENT, -(y + (i - 1) * SHEET_STAT_H))
    fs:SetWidth(statW)
  end
  if n > 0 then y = y + n * SHEET_STAT_H + 2 end
  if hasActions then y = math.max(y, y0 + 26) end
  return y
end
function Place.TagsAndSource(c, pad, iw, y)
  local dw = iw - Place.INDENT
  c.tags:ClearAllPoints()
  c.tags:SetPoint("TOPLEFT", c, "TOPLEFT", pad + Place.INDENT, -y)
  c.tags:SetWidth(dw)
  if c.hasTags then y = y + SHEET_STAT_H end
  c.source:ClearAllPoints()
  c.source:SetPoint("TOPLEFT", c, "TOPLEFT", pad + Place.INDENT, -y)
  c.sourceW = dw
  if c.hasSource then y = y + SHEET_STAT_H end
  return y
end
function Place.AltsThatFit(sh, nAlts, pad, y)
  if nAlts <= 0 then return 0 end
  local free = (sh.ch or math.huge) - (y + 12 + 16 + pad - 10)
  return math.max(0, math.min(nAlts, math.floor((free + 2) / (SHEET_ALT_H + 2))))
end
function Place.Alts(sh, c, pad, y)
  local iw, nAlts = sh.iw, c.nAlts or 0
  local fit = Place.AltsThatFit(sh, nAlts, pad, y)
  c.nAltsShown = fit
  c.sep:SetShown(fit > 0)
  c.moreTitle:SetShown(fit > 0)
  for i = 1, nAlts do c.alts[i]:SetShown(i <= fit) end
  if fit == 0 then return y end
  y = y + 6
  Place.Separator(c, c.sep, pad, y)
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
  return y
end
function Place.Upgrade(sh, c, pad, y)
  y = y + SHEET_ARROW_W + 2
  Place.Card(c, c.best, pad, y, sh.bestW)
  y = y + SHEET_CARD_H + 4
  local right = Place.Actions(c, pad, y)
  y = Place.Stats(c, pad, sh.iw, y, right)
  y = Place.TagsAndSource(c, pad, sh.iw, y)
  return Place.Alts(sh, c, pad, y + 4)
end

function UI:PlaceSheet()
  local sh = self.sheet
  if not sh then return end
  local c, pad = sh.centre, SHEET_PAD
  local y = Place.Header(c, pad, sh.iw, pad)
  y = Place.Worn(sh, c, pad, y)
  if c.mode == "upgrade" then
    y = Place.Upgrade(sh, c, pad, y)
  else
    y = y + 24
  end
  c.contentH = y + pad - 10
end

function Fill.AllFuture(rows)
  if #rows == 0 then return false end
  for _, r in ipairs(rows) do if not r.future then return false end end
  return true
end
function Fill.SlotUpgrade(b, rows)
  b.hasUpgrade = #rows > 0
  local alpha = Fill.AllFuture(rows) and 0.5 or 1
  b.badge:SetShown(b.hasUpgrade)
  b.badge:SetAlpha(alpha)
  b.gain:SetText(b.hasUpgrade and UI.GainNum(rows[1].points) or "")
  b.gain:SetShown(b.hasUpgrade)
  b.gain:SetAlpha(alpha)
end
function Fill.SlotButton(b, list, slot, unit, selectedSlot)
  local rows, _, worn = UI.SheetRows(list, slot)
  b.worn, b.rows, b.unit = worn, rows, unit
  FillWornIcon(b, worn, slot)
  b.empty = not (worn and worn.link)
  b.selected = slot == selectedSlot
  b.sel:SetShown(b.selected)
  Fill.SlotUpgrade(b, rows)
  local dimIcon = not b.hasUpgrade and worn and worn.info and not b.selected
  if dimIcon then b.icon:SetAlpha(0.5) end
end
function Fill.WornName(worn)
  if worn and worn.info then return ColoredItemName(worn.info) end
  return C.dim .. (worn and worn.link and "?" or L.SECTION_NOTHING) .. "|r"
end
function Fill.WornCard(card, worn, slot, scoreText)
  FillWornIcon(card, worn, slot)
  card.worn = worn
  card.label:SetText(L.SHEET_WORN)
  card.name:SetText(Fill.WornName(worn))
  card.score:SetText(scoreText)
end
function Fill.BestLabel(d, rows)
  if d ~= rows[1] then return L.SHEET_PICKED end
  if d.kind == "enchant" then return L.SHEET_BEST_ENCH end
  return L.SHEET_BEST
end
function Fill.BestCard(k, d, rows, dUnit)
  k.data = d
  k.label:SetText(Fill.BestLabel(d, rows))
  k.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(k, d.info.quality)
  k.name:SetText(ColoredItemName(d.info))
  k.score:SetText(string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.newScore or 0), dUnit))
  local big, small = CardGain(d)
  k.gain:SetText(big)
  k.points:SetText(small)
  local a = d.future and 0.55 or 1
  for _, x in ipairs({ k.qual, k.iconBorder, k.icon, k.name, k.gain }) do x:SetAlpha(a) end
  k.dimmed = d.future and true or false
  k:Show()
end
function Fill.Stats(c, d)
  local diffs, partial = UI.StatDiff(d)
  c.nStats = 0
  for i, fs in ipairs(c.stats) do
    local r = diffs and diffs[i]
    if r then fs:SetText(UI.StatText(r, true)); fs:Show(); c.nStats = i else fs:SetText(""); fs:Hide() end
  end
  c.diffs = diffs
  return diffs, partial
end
function Fill.Tags(c, d, diffs, partial)
  local tags = CraftTags(d, true)
  if diffs and #diffs > #c.stats then tags[#tags + 1] = { string.format(L.STATS_MORE, #diffs - #c.stats) } end
  if partial then tags[#tags + 1] = { L.STATS_PARTIAL } end
  c.tags:SetText(TagLine(tags))
  c.hasTags = #tags > 0
  c.tags:SetShown(c.hasTags)
end
function Fill.Actions(c, d, cur)
  local showOffer, showCheck, mark = RightState(d, cur)
  c.offer:SetShown(showOffer)
  c.crafted:SetShown(showCheck)
  c.crafted:SetChecked(mark ~= nil)
  c.craftedLabel:SetText(d.kind == "enchant" and L.ENCHANTED or L.CRAFTED)
  c.craftedLabel:SetShown(showCheck)
end
function Fill.Alts(c, rows, d)
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
end
function Fill.Upgrade(c, cur, rows, d, worn, slot)
  c.mode = "upgrade"
  local dUnit = GCA:UnitLabel(d.e)
  local wornScore = d.status ~= "empty-slot" and string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.oldScore or 0), dUnit) or ""
  Fill.WornCard(c.worn, worn, slot, wornScore)
  Fill.BestCard(c.best, d, rows, dUnit)
  c.arrow:Show()
  local diffs, partial = Fill.Stats(c, d)
  Fill.Tags(c, d, diffs, partial)
  c.hasSource = UI.UpdateLearnButton(c.source, d, cur, c.sourceW) > 0
  Fill.Actions(c, d, cur)
  c.none:Hide()
  Fill.Alts(c, rows, d)
end
function Fill.ClearUpgrade(c)
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
end
function Fill.NoneMessage(list, why, worn, enchanting)
  if #list == 0 and why and why ~= "" then return why end
  if worn and worn.unknown then return L.SECTION_TIP_UNKNOWN end
  if enchanting then return L.SHEET_NONE_ENCH end
  return L.SHEET_NONE
end
function Fill.NoUpgrade(c, list, why, worn, slot, unit, enchanting)
  c.mode = "none"
  Fill.WornCard(c.worn, worn, slot, worn and worn.score and string.format(L.SECTION_SCORE, worn.score, unit) or "")
  Fill.ClearUpgrade(c)
  c.none:SetText(Fill.NoneMessage(list, why, worn, enchanting))
  c.none:Show()
end
function Fill.FeaturedRow(rows, pick)
  if not pick then return rows[1] end
  local d = rows[1]
  for _, r in ipairs(rows) do if r == pick then d = r end end
  return d
end

function UI:UpdateSheet(cur, list, prof, why)
  local sh = self.sheet
  local forKey = tostring(cur.key) .. "|" .. tostring(prof)
  if self.sheetFor ~= forKey then self.sheetFor, self.sheetAuto, self.sheetPickSug = forKey, true, nil end
  if self.sheetAuto or not self.sheetSlot then self.sheetSlot = UI.SheetDefaultSlot(list) end
  local unit = GCA:UnitLabel(cur.weights)
  local enchanting = prof == "Enchanting"
  for slot, b in pairs(sh.slots) do Fill.SlotButton(b, list, slot, unit, self.sheetSlot) end
  local c = sh.centre
  local slot = self.sheetSlot
  local rows, _, worn = UI.SheetRows(list, slot)
  local d = Fill.FeaturedRow(rows, self.sheetPickSug)
  c.slot, c.rows, c.featured = slot, rows, d
  c.header:SetText(ShortSlotName(slot))
  c.count:SetText(SheetCountText(#rows, enchanting))
  c.worn.slot, c.worn.unit = slot, unit
  if d then
    Fill.Upgrade(c, cur, rows, d, worn, slot)
  else
    Fill.NoUpgrade(c, list, why, worn, slot, unit, enchanting)
  end
  self:PlaceSheet()
end

function UI:SelectSheetSlot(slot)
  self.sheetSlot, self.sheetAuto, self.sheetPickSug = slot, false, nil
  self:Refresh()
end

function UI:PickSheetRow(d)
  self.sheetPickSug, self.sheetAuto = d, false
  self:Refresh()
end

P.CreateSheet = CreateSheet
