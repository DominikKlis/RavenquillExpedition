local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, SUG_ROW_H, C, SUB_TINT, HasAtlas = P.SafeCall, P.SUG_ROW_H, P.C, P.SUB_TINT, P.HasAtlas
local SetAtlasSafe, TexOK, SingleLine, SetTip = P.SetAtlasSafe, P.TexOK, P.SingleLine, P.SetTip
local SlotName, QualityColor, Hex, FirstName = P.SlotName, P.QualityColor, P.Hex, P.FirstName
local PairSlotName, TagLine, Ago, ItemIcon = P.PairSlotName, P.TagLine, P.Ago, P.ItemIcon
local OpenWhisper, SendWhisper, TextWidth = P.OpenWhisper, P.SendWhisper, P.TextWidth
local NewTextButton, NewCheck, GainFont, LevelTag = P.NewTextButton, P.NewCheck, P.GainFont, P.LevelTag
local CardGain, ShowSuggestionTooltip = P.CardGain, P.ShowSuggestionTooltip

---------------------------------------------------------------------------
-- Craft rows: the suggestion rows of the member view and the rows of the guild-needs view share one build
-- (icon, title, tinted sub-line, gain, Offer icon, crafted box). RowCtx tells a row's suggestion and member.
---------------------------------------------------------------------------
local function ShiftDown()
  return IsShiftKeyDown and SafeCall(IsShiftKeyDown) and true or false
end

local function RowCtx(b)
  local d = b and b.data
  if d and d.rowKind == "need" then return d.sug, d.member end
  return d, UI.current
end
UI.RowCtx = RowCtx

local function HideTip() GameTooltip_Hide() end

-- L6: the gain text sits left of whatever is shown on the right (crafted box, Offer), never over a gap.
-- gainY (K4 cards): the gain sits that much above the middle (the points line goes under it)
local function LayoutRight(b, showOffer, showCheck, gainY)
  b.offer:ClearAllPoints()
  b.offer:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local anchor, point, x = b, "RIGHT", -6
  if showOffer then anchor, point, x = b.offer, "LEFT", -4 end
  b.crafted:ClearAllPoints()
  if showCheck then
    b.crafted:SetPoint("RIGHT", anchor, point, x, 0)
    anchor, point, x = b.crafted, "LEFT", -6
  end
  b.gain:ClearAllPoints()
  b.gain:SetPoint("RIGHT", anchor, point, x, gainY or 0)
  b.gainAnchor = anchor
end

-- K4: the Offer / crafted-mark actions and their tooltips, shared by the guild-needs rows, the list cards and
-- the character sheet (one implementation; the widgets only differ in look). d = suggestion, cur = member entry.
function UI.DoOffer(d, cur)
  local who = cur and cur.key
  if not (d and who and UI.CanOffer(cur, d)) then return false end
  local msg = UI.OfferText(cur.prof or GCA:SelectedProfession(), d, who)
  if IsShiftKeyDown() then SendWhisper(who, msg) else OpenWhisper(who, msg) end
  return true
end

local function OfferTip(owner, d)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.OFFER, 1, 1, 1)
  GameTooltip:AddLine(d and d.kind == "enchant" and L.OFFER_TIP_ENCHANT or L.OFFER_TIP_CRAFT, 1, 0.82, 0)
  GameTooltip:AddLine(L.OFFER_TIP_CLICK, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_SHIFT, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_EDIT, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function UI.DoCrafted(d, cur, on)
  if not (d and cur) then return end
  GCA:SetCrafted(cur.key, cur.prof or GCA:SelectedProfession(), d, on and true or false)
  UI:Refresh()
end

local function CraftedTip(owner, d, cur)
  if not (d and cur) then return end
  local who = FirstName(cur.key)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(d.kind == "enchant" and L.ENCHANTED or L.CRAFTED, 1, 1, 1)
  GameTooltip:AddLine(string.format(L.CRAFTED_TIP_TITLE, cur.key), 1, 0.82, 0)
  GameTooltip:AddLine(L.CRAFTED_TIP, nil, nil, nil, true)
  if d.kind == "enchant" then
    GameTooltip:AddLine(string.format(L.CRAFTED_TIP_CLEAR_ENCHANT, who, SlotName(d.slot)), nil, nil, nil, true)
  else
    GameTooltip:AddLine(string.format(L.CRAFTED_TIP_CLEAR, who), nil, nil, nil, true)
  end
  local mark = d.cand and GCA:CraftedMark(cur.key, cur.prof, d.cand.spellID)
  if mark then GameTooltip:AddLine(string.format(L.CRAFTED_TIP_SINCE, Ago(mark.t)), 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

-- what the right side of a craft shows: Offer (online, known, not you, not browse), the crafted box (known
-- recipe or an existing mark) and the mark itself
local function RightState(d, cur)
  local showOffer = UI.CanOffer(cur, d)
  local prof = cur and cur.prof or GCA:SelectedProfession()
  local mark = cur and d.cand and GCA:CraftedMark(cur.key, prof, d.cand.spellID)
  local showCheck = cur ~= nil and not cur.browse and (d.known or mark ~= nil)
  return showOffer, showCheck, mark
end
UI.RightState = RightState

-- K6: Offer everywhere = the red UIPanelButtonTemplate button "Offer" (as the profession window's Create button;
-- K1's whisper icon is gone). Small rows (guild-needs members, the sheet's alternatives): 80 x 20.
UI.OFFER_SMALL_W = 80
-- below
local function CreateOfferButton(b)
  return P.CreateOfferTextButton(b, b, UI.OFFER_SMALL_W, 20)
end

-- K4: the list cards' and the sheet's Offer = a text button "Offer"; same action and tooltip
P.CreateOfferTextButton = function(parent, row, w, h)
  local o = NewTextButton(parent, w or 84, h or 22, L.OFFER)
  o.row = row
  o:SetScript("OnClick", function(self) UI.DoOffer(RowCtx(self.row)) end)
  SetTip(o, "offer", function(self) OfferTip(self, (RowCtx(self.row))) end)
  o:SetScript("OnLeave", GameTooltip_Hide)
  return o
end

-- K4: crafted box for the list cards and the sheet (the same mark as the guild-needs rows)
local function CreateCraftedBox(parent, row)
  local cb = NewCheck(parent, 22)
  cb.row = row
  cb:SetScript("OnClick", function(self)
    local d, cur = RowCtx(self.row)
    UI.DoCrafted(d, cur, self:GetChecked())
  end)
  SetTip(cb, "crafted box", function(self) CraftedTip(self, RowCtx(self.row)) end)
  cb:SetScript("OnLeave", GameTooltip_Hide)
  return cb
end

-- K4: an item icon with a quality-coloured frame. K6: the profession window's reagent slot (probe:
-- SlotBackground = Professions-Slot-bg, IconBorder = Professions-Slot-Frame; WhatsTraining Crafting\RecipeList.lua:109-113
-- anchors) with the frame tinted by quality, as the client tints an item button's IconBorder; without those atlases
-- GearQuestForever's WhiteIconFrame (= file 651080, the client's own item-slot IconBorder) tinted by quality; without
-- that a quality-coloured square behind the icon (2 px of it show). Fields: qual (slot background / square), icon,
-- iconBorder, frameArt ("atlas" / "file" / nil). SetIconQuality(f, quality) colours it.
local function AddQualityIcon(f, size, point, rel, relPoint, x, y, itemButton)
  f.qual = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.qual:SetSize(size + 4, size + 4)
  f.qual:SetPoint(point, rel, relPoint, x, y)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(size, size)
  f.icon:SetPoint("CENTER", f.qual)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.iconBorder = f:CreateTexture(nil, "OVERLAY")
  -- itemButton (the sheet's gear slots): the item-button frame first, as the client's own character slots
  if not itemButton and HasAtlas("Professions-Slot-Frame") and SetAtlasSafe(f.iconBorder, "Professions-Slot-Frame") then
    f.iconBorder:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -2, 2)
    f.iconBorder:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 2, -2)
    f.frameArt = "atlas"
    f.slotBg = SetAtlasSafe(f.qual, "Professions-Slot-bg")
  elseif TexOK("iconFrame") then
    f.iconBorder:SetTexture(UI.TEX.iconFrame)
    f.iconBorder:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -2, 2)
    f.iconBorder:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 2, -2)
    f.frameArt = "file"
  else
    f.iconBorder:Hide()
  end
end
local function SetIconQuality(f, quality, r, g, b)
  if not r then r, g, b = QualityColor(quality) end
  if f.frameArt then
    f.iconBorder:SetVertexColor(r, g, b)
    if not f.slotBg then f.qual:SetColorTexture(0, 0, 0, 0.6) end
  else
    f.qual:SetColorTexture(r, g, b, 1)
  end
end

-- Sub-line tags of a craft (K1 rules): what an enchant replaces / which ring or trinket a craft replaces, not
-- learned, set bonus, rough weights. withLevel: the "from level N · X to go" tag first (the sheet; the list
-- cards show it as a chip instead).
-- the disambiguator after a row's name: "Ring 2" / "Trinket 1", W4: "off hand" for a dual-wield one-hander scored in
-- the off hand
function UI.RowPair(d)
  if d.kind == "enchant" then return nil end
  if d.hand == "off" then return L.HAND_OFF end
  return PairSlotName(d.slot)
end
local function CraftTags(d, cur, withLevel, noLearned)
  local tags = {}
  if withLevel and d.future and d.wearAt then tags[#tags + 1] = { LevelTag(d), C.levelTag } end
  local pair = UI.RowPair(d)
  if d.kind == "enchant" then
    local item = d.item and d.item.name or "?"
    tags[#tags + 1] = { d.equipped and string.format(L.REPLACES_ON, d.equipped.name, item) or string.format(L.NO_ENCHANT_ON, item) }
  elseif pair and d.equipped then
    tags[#tags + 1] = { string.format(L.REPLACES, d.equipped.name or "?") }
  end
  -- weapons: next to a worn two-hander (scored alone) / a two-hander replacing both hands
  if d.status == "needs-partner" then
    tags[#tags + 1] = { d.slot == 17 and L.NEEDS_MAIN_HAND or L.NEEDS_OFF_HAND, C.future }
  elseif d.bothHands then
    tags[#tags + 1] = { L.REPLACES_BOTH }
  end
  -- (an unlearned recipe is shown by the shared source button, UI.CreateLearnButton, in every view - not as a tag)
  if d.sets and d.setDelta and d.setDelta ~= 0 then
    tags[#tags + 1] = d.setDelta > 0 and { L.SET_PLUS, C.set } or { L.SET_BREAKS, C.setLoss }
  elseif d.hint then
    tags[#tags + 1] = { d.hint, C.set }
  end
  if d.e and GCA.Scoring.isPlaceholder(d.e.raw) then tags[#tags + 1] = { L.ROUGH } end
  return tags
end
UI.CraftTags = CraftTags

-- User 2026-11-15 ("always update all the views so it looks everywhere exactly the same"): ONE component for a
-- recipe you haven't learned, used by the "Nach Mitglied" cards, the character sheet and Gildenbedarf's detail
-- panel: red text = source icon + best source + "1g beim Händler · 2g im AH" (UI.SourceBadge; "Not learned" without
-- source data; browse mode teal); hover = every source (UI.NotLearnedTip), click = map marker, right-click = menu.
function UI.LearnText(d, cur)
  local colour = (cur and cur.browse) and C.browse or C.notLearnedTag
  return colour .. (UI.SourceBadge(d, cur) or L.NOT_LEARNED) .. "|r"
end
function UI.CreateLearnButton(parent)
  local nl = CreateFrame("Button", nil, parent)
  nl:SetHeight(14)
  nl.text = nl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nl.text:SetPoint("LEFT", nl, "LEFT", 0, 0)
  nl.text:SetJustifyH("LEFT")
  SingleLine(nl.text)
  if nl.RegisterForClicks then nl:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  SetTip(nl, "not learned", function(self) UI.NotLearnedTip(self, self.data, self.cur) end)
  nl:SetScript("OnLeave", function() GameTooltip_Hide() end)
  nl:SetScript("OnClick", function(self, button) UI.NotLearnedClick(self, button, self.data, self.cur) end)
  nl:Hide()
  return nl
end
-- fills it for d (hidden for a known recipe); returns the width it takes (0 when hidden)
function UI.UpdateLearnButton(nl, d, cur, maxW)
  nl.data, nl.cur = d, cur
  if not d or d.known then
    nl.text:SetText("")
    nl:SetWidth(1)
    nl:Hide()
    return 0
  end
  nl.text:SetText(UI.LearnText(d, cur))
  local w = math.max(10, math.min(TextWidth(nl.text) + 2, maxW or 300))
  nl.text:SetWidth(w)
  nl:SetWidth(w)
  nl:Show()
  return w
end

-- K4 variant "List": one 50 px row per craft: 38 px icon in the reagent-slot frame, name in quality colour
-- (+ "(Ring 2)" on pair slots), second line = the stat differences (when both sides have stat data) + the K1 tags
-- (K6: the "from level N" tag is orange text in that line, no chip box); right: the gain in the client's green
-- font over the points, the crafted box, the red "Offer" button. Too-high-level rows are dimmed (Offer and the box
-- stay at full alpha). K6: indented a little under their slot's worn row, no tree lines, no row shading.
local CARD_ICON = 38
local CARD_GAIN_W = 84
local CARD_OFFER_W = 84
local CARD_INDENT = 16
UI.CARD_INDENT = CARD_INDENT
local function CreateCardRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SUG_ROW_H - 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetPoint("TOPLEFT", b, "TOPLEFT", CARD_INDENT, 0)
  b.hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  UI.Skin(b.hl, "rowHover")
  AddQualityIcon(b, CARD_ICON, "LEFT", b, "LEFT", CARD_INDENT + 4, 0)
  b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.title:SetJustifyH("LEFT")
  SingleLine(b.title)
  b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.sub:SetJustifyH("LEFT")
  b.sub:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(b.sub)
  -- User 2026-11-15: a missing recipe = a red "Not learned" button at the start of the second line (replaces the K7
  -- third "where to get it" line): hover = the sources, click = map marker (UI.NotLearnedTip / NotLearnedClick)
  b.nl = UI.CreateLearnButton(b) -- the shared source button (same in every view)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b.offer = P.CreateOfferTextButton(b, b, CARD_OFFER_W)
  b.crafted = CreateCraftedBox(b, b)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.gain:SetJustifyH("RIGHT")
  b.gain:SetWidth(CARD_GAIN_W)
  GainFont(b.gain, true)
  SingleLine(b.gain)
  b.points = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.points:SetJustifyH("RIGHT")
  b.points:SetWidth(CARD_GAIN_W)
  b.points:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  b.points:SetPoint("TOPRIGHT", b.gain, "BOTTOMRIGHT", 0, -2)
  SingleLine(b.points)
  LayoutRight(b, true, true, 7)
  SetTip(b, "suggestion", function(self)
    local d, cur = RowCtx(self)
    if d then ShowSuggestionTooltip(self, d, cur) end
  end)
  b:SetScript("OnLeave", HideTip)
  b:SetScript("OnClick", function(self, button)
    if UI.SourceClick(self, button, RowCtx(self)) then return end
    if UI.ModifiedDown() then
      if self.data and self.data.info.link then HandleModifiedItemClick(self.data.info.link) end
      return
    end
    UI.OpenRecipe(RowCtx(self)) -- user 2026-11-15: a click opens the recipe in Blizzard's profession window
  end)
  return b
end

-- User 2026-11-15: clicking a craft opens Blizzard's profession window on that recipe (C_TradeSkillUI.OpenRecipe,
-- as CraftersJournal does on this client; only from a click, not in combat). Recipes you don't know / professions
-- you only browse can't be opened: a chat line says why. Only the "Nach Mitglied" cards and the sheet's featured
-- craft do this (not Gildenbedarf, user). Our window stays open (user); while the profession window is shown, ours
-- drops from HIGH to MEDIUM strata so the profession window can be on top (UI.StepBehindProfessions).
function UI.StepBehindProfessions()
  local f = UI.frame
  if not f then return end
  for _, pf in ipairs({ rawget(_G, "ProfessionsFrame"), rawget(_G, "TradeSkillFrame") }) do
    if type(pf) == "table" and pf.HookScript and not pf.gcaStepHooked then
      pf.gcaStepHooked = true
      pcall(pf.HookScript, pf, "OnShow", function() f:SetFrameStrata("MEDIUM") end)
      pcall(pf.HookScript, pf, "OnHide", function() f:SetFrameStrata("HIGH") end)
    end
    if type(pf) == "table" and pf.IsShown and pf:IsShown() then f:SetFrameStrata("MEDIUM") end
  end
end
function UI.OpenRecipe(d, cur)
  local spell = d and d.cand and d.cand.spellID
  if type(spell) ~= "number" then return false end
  if (cur and cur.browse) or not d.known then GCA:Print(L.OPEN_NOT_KNOWN); return false end
  if InCombatLockdown and InCombatLockdown() then GCA:Print(L.OPEN_COMBAT); return false end
  local T = C_TradeSkillUI
  if not (T and type(T.OpenRecipe) == "function" and pcall(T.OpenRecipe, spell)) then
    GCA:Print(L.OPEN_FAIL)
    return false
  end
  UI.StepBehindProfessions()
  return true
end

local function UpdateCardRow(b, d)
  local cur = UI.current
  b.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(b, d.info.quality)
  local pair = UI.RowPair(d)
  b.title:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r" .. (pair and (" " .. C.muted .. "(" .. pair .. ")|r") or ""))
  -- second line: the "Not learned" button (red), then the K1 tags (level tag first, orange). No stat differences
  -- any more (user 2026-11-15; the character sheet keeps them).
  local tags = CraftTags(d, cur, true, true)
  local learned = d.known
  b.sub:SetText(((not learned and #tags > 0) and "·  " or "") .. TagLine(tags))
  local nlW = UI.UpdateLearnButton(b.nl, d, cur, math.floor((UI.listW or 400) * 0.6))
  local big, small = CardGain(d)
  b.gain:SetText(big)
  b.points:SetText(small)
  local showOffer, showCheck, mark = RightState(d, cur)
  b.offer:SetShown(showOffer)
  b.crafted:SetShown(showCheck)
  b.crafted:SetChecked(mark ~= nil)
  LayoutRight(b, showOffer, showCheck, 7)
  -- texts: one anchor each + an explicit width (the room between the icon and the gain), so they never run
  -- under the gain / box / Offer and need no second anchor with another vertical centre
  local textL = CARD_INDENT + 4 + CARD_ICON + 4 + 10
  local rightW = 6 + (showOffer and (CARD_OFFER_W + 4) or 0) + (showCheck and (22 + 6) or 0) + CARD_GAIN_W + 10
  local avail = math.max(40, UI.listW - textL - rightW)
  b.textW = avail
  -- second line: [Not learned]  ·  tags (the K7 third source line is gone: its content is the button's tooltip)
  b.hasSource = false
  b.nl:ClearAllPoints()
  b.nl:SetPoint("BOTTOMLEFT", b.qual, "BOTTOMRIGHT", 10, 3)
  b.sub:ClearAllPoints()
  if learned then
    b.sub:SetPoint("BOTTOMLEFT", b.qual, "BOTTOMRIGHT", 10, 4)
    b.sub:SetWidth(avail)
  else
    b.sub:SetPoint("LEFT", b.nl, "RIGHT", 6, 0)
    b.sub:SetWidth(math.max(10, avail - nlW - 6))
  end
  b.hasSub = #tags > 0 or not learned
  -- title on the top line when there is a second line, else centred on the row
  b.title:ClearAllPoints()
  if b.hasSub then
    b.title:SetPoint("TOPLEFT", b.qual, "TOPRIGHT", 10, -3)
  else
    b.title:SetPoint("LEFT", b.qual, "RIGHT", 10, 0)
  end
  b.title:SetWidth(avail)
  local a = d.future and 0.55 or 1
  for _, x in ipairs({ b.qual, b.iconBorder, b.icon, b.title, b.sub, b.nl, b.gain, b.points }) do x:SetAlpha(a) end
  b.dimmed = d.future and true or false
end
UI.UpdateCardRow = UpdateCardRow
-- K7: card height (scroll list height function): +10 px for the source line
UI.SOURCE_EXTRA_H = 10
function UI.CardHeight(b) return SUG_ROW_H + (b.hasSource and UI.SOURCE_EXTRA_H or 0) end

-- shared with the files loaded after this one (P)
P.AddQualityIcon = AddQualityIcon
P.CraftTags = CraftTags
P.CreateCardRow = CreateCardRow
P.CreateCraftedBox = CreateCraftedBox
P.CreateOfferButton = CreateOfferButton
P.HideTip = HideTip
P.LayoutRight = LayoutRight
P.RightState = RightState
P.RowCtx = RowCtx
P.SetIconQuality = SetIconQuality
P.ShiftDown = ShiftDown
P.UpdateCardRow = UpdateCardRow
