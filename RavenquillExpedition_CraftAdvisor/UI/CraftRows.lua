local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local Label = P.Label
local SUG_ROW_H, C, SUB_TINT, HasAtlas = P.SUG_ROW_H, P.C, P.SUB_TINT, P.HasAtlas
local SetAtlasSafe, TexOK, SingleLine, SetTip = P.SetAtlasSafe, P.TexOK, P.SingleLine, P.SetTip
local SlotName, QualityColor, ColoredItemName, FirstName = P.SlotName, P.QualityColor, P.ColoredItemName, P.FirstName
local PairSlotName, TagLine, Ago, ItemIcon = P.PairSlotName, P.TagLine, P.Ago, P.ItemIcon
local OpenWhisper, SendWhisper, TextWidth = P.OpenWhisper, P.SendWhisper, P.TextWidth
local NewTextButton, NewCheck, GainFont, LevelTag = P.NewTextButton, P.NewCheck, P.GainFont, P.LevelTag
local CardGain, ShowSuggestionTooltip = P.CardGain, P.ShowSuggestionTooltip

local function RowCtx(b)
  local d = b and b.data
  if d and d.rowKind == "need" then return d.sug, d.member end
  return d, UI.current
end
UI.RowCtx = RowCtx

local function HideTip() GameTooltip_Hide() end

local CRAFTED_BOX, CRAFTED_GAP, CRAFTED_TAIL = 22, 4, 6

local function LayoutRight(b, showOffer, showCheck, gainY)
  b.offer:ClearAllPoints()
  b.offer:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local anchor, point, x = b, "RIGHT", -6
  if showOffer then anchor, point, x = b.offer, "LEFT", -4 end
  b.crafted:ClearAllPoints()
  if showCheck then
    b.crafted:SetPoint("RIGHT", anchor, point, x - b.crafted.trailW, 0)
    anchor, point, x = b.crafted, "LEFT", -6
  end
  b.gain:ClearAllPoints()
  b.gain:SetPoint("RIGHT", anchor, point, x, gainY or 0)
  b.gainAnchor = anchor
end

function UI.DoOffer(d, cur)
  if UI.DoAsk(d, cur) then return true end
  local who = cur and cur.key
  if not (d and who and UI.CanOffer(cur, d)) then return false end
  local msg = UI.OfferText(cur.prof or GCA:SelectedProfession(), d, who)
  if IsShiftKeyDown() then SendWhisper(who, msg) else OpenWhisper(who, msg) end
  return true
end

local function OfferTip(owner, d, cur)
  if UI.AskTarget(cur, d) then return UI.AskTip(owner, d, cur) end
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

local function RightState(d, cur)
  local showOffer = UI.RowAction(cur, d) ~= nil
  local prof = cur and cur.prof or GCA:SelectedProfession()
  local mark = cur and d.cand and GCA:CraftedMark(cur.key, prof, d.cand.spellID)
  local showCheck = cur ~= nil and not cur.browse and (d.known or mark ~= nil)
  return showOffer, showCheck, mark
end
UI.RightState = RightState

UI.OFFER_SMALL_W = 80
local function CreateOfferButton(b)
  return P.CreateOfferTextButton(b, b, UI.OFFER_SMALL_W, 20)
end

P.CreateOfferTextButton = function(parent, row, w, h)
  local o = NewTextButton(parent, w or 84, h or 22, L.OFFER)
  o.row = row
  o:SetScript("OnClick", function(self) UI.DoOffer(RowCtx(self.row)) end)
  SetTip(o, "offer", function(self) OfferTip(self, RowCtx(self.row)) end)
  o:SetScript("OnLeave", GameTooltip_Hide)
  return o
end

local function SetCraft(cb, d, shown, mark)
  local text, on = d.kind == "enchant" and L.ENCHANTED or L.CRAFTED, mark and true or false
  cb.label:SetText(on and text or (C.muted .. text .. "|r"))
  local labelW = TextWidth(cb.label)
  cb.label:SetWidth(labelW)
  cb.trailW = CRAFTED_GAP + labelW + CRAFTED_TAIL
  if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -cb.trailW, 0, 0) end
  cb:SetChecked(on)
  cb:SetShown(shown)
  cb.fullW = shown and (CRAFTED_BOX + cb.trailW) or 0
end

local function CreateCraftedBox(parent, row)
  local cb = NewCheck(parent, CRAFTED_BOX)
  cb.row = row
  cb.label = Label(cb, "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", CRAFTED_GAP, 0)
  cb.trailW, cb.fullW, cb.SetCraft = 0, 0, SetCraft
  cb:SetScript("OnClick", function(self)
    local d, cur = RowCtx(self.row)
    UI.DoCrafted(d, cur, self:GetChecked())
  end)
  SetTip(cb, "crafted box", function(self) CraftedTip(self, RowCtx(self.row)) end)
  cb:SetScript("OnLeave", GameTooltip_Hide)
  return cb
end

local function AddQualityIcon(f, size, point, rel, relPoint, x, y, itemButton)
  f.qual = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.qual:SetSize(size + 4, size + 4)
  f.qual:SetPoint(point, rel, relPoint, x, y)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(size, size)
  f.icon:SetPoint("CENTER", f.qual)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.iconBorder = f:CreateTexture(nil, "OVERLAY")
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
local function AddGearSlotArt(b, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
  if SetAtlasSafe(b.bg, "UI-Character-Info-GearSlot") then
    local art = math.floor(size * 55 / 37 + 0.5)
    b.bg:SetSize(art, art)
    b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.gearArt = true
  else
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
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

function UI.RowPair(d)
  if d.kind == "enchant" then return nil end
  if d.hand == "off" then return L.HAND_OFF end
  return PairSlotName(d.slot)
end
local Tags = {}

function Tags.Replaces(d)
  if d.kind == "enchant" then
    local item = d.item and d.item.name or "?"
    return { d.equipped and string.format(L.REPLACES_ON, d.equipped.name or "?", item) or string.format(L.NO_ENCHANT_ON, item) }
  end
  if UI.RowPair(d) and d.equipped then return { string.format(L.REPLACES, d.equipped.name or "?") } end
  return nil
end

function Tags.Hands(d)
  if d.status == "needs-partner" then return { d.slot == 17 and L.NEEDS_MAIN_HAND or L.NEEDS_OFF_HAND, C.future } end
  if d.bothHands then return { L.REPLACES_BOTH } end
  return nil
end

function Tags.Set(d)
  if d.sets and d.setDelta and d.setDelta ~= 0 then
    return d.setDelta > 0 and { L.SET_PLUS, C.set } or { L.SET_BREAKS, C.setLoss }
  end
  if d.hint then return { d.hint, C.set } end
  return nil
end

function Tags.Rough(d)
  if d.e and GCA.Scoring.isPlaceholder(d.e.raw) then return { L.ROUGH } end
  return nil
end

Tags.ORDER = { Tags.Replaces, Tags.Hands, Tags.Set, Tags.Rough }

local function CraftTags(d, withLevel)
  local tags = {}
  if withLevel and d.future and d.wearAt then tags[#tags + 1] = { LevelTag(d), C.levelTag } end
  for _, tagOf in ipairs(Tags.ORDER) do
    local tag = tagOf(d)
    if tag then tags[#tags + 1] = tag end
  end
  return tags
end

UI.CraftTags = CraftTags

function UI.LearnText(d, cur)
  local crafters = UI.CrafterBadge(d, cur)
  if crafters then return crafters end
  local colour = (cur and cur.browse) and C.browse or C.notLearnedTag
  return colour .. (UI.SourceBadge(d, cur) or L.NOT_LEARNED) .. "|r"
end
function UI.CreateLearnButton(parent)
  local nl = CreateFrame("Button", nil, parent)
  nl:SetHeight(14)
  nl.text = Label(nl, "GameFontNormalSmall")
  nl.text:SetPoint("LEFT", nl, "LEFT", 0, 0)
  if nl.RegisterForClicks then nl:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  SetTip(nl, "not learned", function(self) UI.NotLearnedTip(self, self.data, self.cur) end)
  nl:SetScript("OnLeave", function() GameTooltip_Hide() end)
  nl:SetScript("OnClick", function(self, button) UI.NotLearnedClick(self, button, self.data, self.cur) end)
  nl:Hide()
  return nl
end
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
  b.title = Label(b, "GameFontNormal")
  b.sub = Label(b, "GameFontHighlightSmall")
  b.sub:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  b.nl = UI.CreateLearnButton(b)
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
  P.OnItemClick(b, function(self)
    local d, cur = RowCtx(self)
    return d, cur, d and d.info.link
  end, UI.OpenRecipe)
  return b
end

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

local Card = {}

function Card.Title(d)
  local pair = UI.RowPair(d)
  local name = ColoredItemName(d.info)
  if not pair then return name end
  return name .. " " .. C.muted .. "(" .. pair .. ")|r"
end

function Card.TextWidth(showOffer, craftedW, listW)
  local textL = CARD_INDENT + 4 + CARD_ICON + 4 + 10
  local rightW = 6 + (showOffer and (CARD_OFFER_W + 4) or 0) + (craftedW > 0 and (craftedW + 6) or 0) + CARD_GAIN_W + 10
  return math.max(40, listW - textL - rightW)
end

function Card.PlaceSub(b, learned, avail, nlW)
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
end

function Card.PlaceTitle(b, avail)
  b.title:ClearAllPoints()
  if b.hasSub then
    b.title:SetPoint("TOPLEFT", b.qual, "TOPRIGHT", 10, -3)
  else
    b.title:SetPoint("LEFT", b.qual, "RIGHT", 10, 0)
  end
  b.title:SetWidth(avail)
end

local function UpdateCardRow(b, d, listW)
  local cur = UI.current
  b.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(b, d.info.quality)
  b.title:SetText(Card.Title(d))
  local tags = CraftTags(d, true)
  local learned = d.known
  b.sub:SetText(((not learned and #tags > 0) and "·  " or "") .. TagLine(tags))
  local nlW = UI.UpdateLearnButton(b.nl, d, cur, math.floor(listW * 0.6))
  local big, small = CardGain(d)
  b.gain:SetText(big)
  b.points:SetText(small)
  local showOffer, showCheck, mark = RightState(d, cur)
  UI.ShowRowAction(b.offer, cur, d)
  b.crafted:SetCraft(d, showCheck, mark)
  LayoutRight(b, showOffer, showCheck, 7)
  local avail = Card.TextWidth(showOffer, b.crafted.fullW, listW)
  b.textW = avail
  Card.PlaceSub(b, learned, avail, nlW)
  b.hasSub = #tags > 0 or not learned
  Card.PlaceTitle(b, avail)
  P.Dim(b, d.future, { b.qual, b.iconBorder, b.icon, b.title, b.sub, b.nl, b.gain, b.points })
end

UI.UpdateCardRow = UpdateCardRow
function UI.CardHeight() return SUG_ROW_H end

P.AddGearSlotArt = AddGearSlotArt
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
P.UpdateCardRow = UpdateCardRow
