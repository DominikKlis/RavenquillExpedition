local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local Label = P.Label
local SafeCall = P.SafeCall
local NEED_SUB_H, C = P.NEED_SUB_H, P.C
local FileOK, SingleLine, SetTip, SlotName = P.FileOK, P.SingleLine, P.SetTip, P.SlotName
local ColoredItemName, ItemIcon = P.ColoredItemName, P.ItemIcon
local TextWidth, GainFont, LevelTag = P.TextWidth, P.GainFont, P.LevelTag
local Tag = P.Tag
local MEMBER_TEXT_X, Src, ShowSuggestionTooltip = P.MEMBER_TEXT_X, P.Src, P.ShowSuggestionTooltip
local ShiftDown, ModifiedDown, LayoutRight = P.ShiftDown, P.ModifiedDown, P.LayoutRight
local AddQualityIcon, SetIconQuality = P.AddQualityIcon, P.SetIconQuality

UI.needsCollapsed = {}
UI.NEED_GAIN_W = 46

local function ChipGain(s) return UI.GainNum(s.points) end
UI.ChipGain = ChipGain

local function CraftGroupTip(owner, e)
  local g = e and e.group
  if not g then return end
  ShowSuggestionTooltip(owner, g.sug, g.best and g.best.member)
end
UI.CraftGroupTip = CraftGroupTip

local function CreateCraftGroupRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(P.NEED_ROW_H)
  UI.AddRowArt(b)
  b.label = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.label:SetPoint("LEFT", b, "LEFT", MEMBER_TEXT_X, 0)
  b.label:SetJustifyH("LEFT")
  SingleLine(b.label)
  b.count = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.count:SetPoint("LEFT", b.label, "RIGHT", 0, 0)
  b.count:SetJustifyH("LEFT")
  SingleLine(b.count)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.gain:SetWidth(UI.NEED_GAIN_W)
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self, button)
    local e = self.data
    if not (e and e.group) then return end
    if UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) then return end
    if ModifiedDown() and e.group.sug.info.link then HandleModifiedItemClick(e.group.sug.info.link); return end
    UI.needSel = e.group.key
    UI:RefreshNeeds()
  end)
  SetTip(b, "craft row", function(self) CraftGroupTip(self, self.data) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateCraftGroupRow(b, e, listW)
  local g = e.group
  local d = g.sug
  local cur = g.best and g.best.member
  local colour = (cur and cur.browse) and C.browse or ((not d.known) and C.notLearned or nil)
  b.label:SetText(Tag(d.info.name or "?", colour))
  b.count:SetText(" [" .. #e.rows .. "]")
  b.gain:SetText(e.rows[1] and ChipGain(e.rows[1].sug) or "")
  local avail = math.max(40, listW - MEMBER_TEXT_X - UI.NEED_GAIN_W - 10)
  local countW = TextWidth(b.count)
  b.label:SetWidth(math.max(20, math.min(TextWidth(b.label) + 2, avail - countW)))
  b.textW = avail
  P.Dim(b, g.future, { b.label, b.count, b.gain })
  b.sel:SetShown(UI.needSel == g.key)
end

local function CatTitle(key)
  if key == 11 then return L.SECTION_RINGS end
  if key == 13 then return L.SECTION_TRINKETS end
  if UI.HAND_SECTION[key] then return L[UI.HAND_SECTION[key]] end
  return SlotName(key)
end
UI.NeedsCatTitle = CatTitle
local function CreateNeedsCatRow(parent)
  local b = UI.CreateCategoryRow(parent, function(self)
    local d = self.data
    UI.needsCollapsed[d.cat] = not UI.needsCollapsed[d.cat]
    UI:RefreshNeeds()
  end)
  SetTip(b, "needs category", function(self)
    local d = self.data
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(CatTitle(d.cat), 1, 0.82, 0)
    GameTooltip:AddLine(d.n == 1 and L.NEEDS_CAT_TIP_1 or string.format(L.NEEDS_CAT_TIP, d.n), 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end
local function UpdateNeedsCatRow(b, d, listW)
  b:SetCategory(CatTitle(d.cat), not UI.needsCollapsed[d.cat], listW)
end
UI.NEEDS_KINDS = {
  default = { create = CreateCraftGroupRow, update = UpdateCraftGroupRow, height = P.NEED_ROW_H },
  cat = { create = CreateNeedsCatRow, update = UpdateNeedsCatRow, height = P.GROUP_ROW_H },
}

local NEED_SUB_X = 8
UI.NEED_MEMBER_W = 110
local function CreateNeedMemberRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NEED_SUB_H - 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hlKind = UI.Skin(b.hl, "rowHover")
  b.name = Label(b, "GameFontHighlight")
  b.name:SetPoint("LEFT", b, "LEFT", NEED_SUB_X, 0)
  b.name:SetWidth(UI.NEED_MEMBER_W)
  b.wornBtn = CreateFrame("Button", nil, b)
  b.wornBtn:SetSize(34, 34)
  b.wornBtn:SetPoint("LEFT", b, "LEFT", NEED_SUB_X + UI.NEED_MEMBER_W + 8, 0)
  AddQualityIcon(b.wornBtn, 30, "CENTER", b.wornBtn, "CENTER", 0, 0)
  b.wornBtn:SetScript("OnEnter", function(self)
    local link = self.link
    if type(link) == "string" and link:find("|H", 1, true) then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  b.wornBtn:SetScript("OnLeave", GameTooltip_Hide)
  b.wornBtn:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") then HandleModifiedItemClick(self.link) end
  end)
  b.state = Label(b, "GameFontHighlight")
  b.state:SetPoint("LEFT", b.wornBtn, "RIGHT", 8, 0)
  b.offer = P.CreateOfferButton(b)
  b.crafted = P.CreateCraftedBox(b, b)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  LayoutRight(b, true, true)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  P.OnItemClick(b, function(self)
    local e = self.data
    if e and e.sug then return e.sug, e.member, e.sug.info.link end
  end)
  SetTip(b, "need member", function(self)
    local d, cur = P.RowCtx(self)
    if d then ShowSuggestionTooltip(self, d, cur) end
  end)
  b:SetScript("OnLeave", P.HideTip)
  return b
end

UI.NEED_GAIN_SUB_W = 60
local function NeedItemText(d)
  if d.kind == "enchant" then
    local item = d.item
    local replaces = d.equipped and string.format(L.REPLACES, d.equipped.name or "?") or L.NO_ENCHANT
    return (item and ColoredItemName(item) or "?") .. "  " .. C.muted .. replaces .. "|r", item
  end
  local eq = d.equipped
  if eq then return ColoredItemName(eq), eq end
  return C.dim .. L.CARDS_EMPTY .. "|r", nil
end

local function NeedRowText(d)
  local text, item = NeedItemText(d)
  local pair = UI.RowPair(d)
  if pair then text = text .. " " .. C.muted .. "(" .. pair .. ")|r" end
  if d.future and d.wearAt then text = text .. "  " .. Tag(LevelTag(d), C.levelTag) end
  return text, item
end

local function FillWornButton(btn, item)
  if item and item.icon then
    btn.icon:SetTexture(item.icon)
    btn.icon:Show()
    SetIconQuality(btn, item.quality)
    btn.link = item.link
  else
    btn.icon:SetTexture(nil)
    SetIconQuality(btn, 0, 0.3, 0.3, 0.3)
    btn.link = nil
  end
  btn:SetAlpha(btn.link and 1 or 0.5)
end

local function NeedRowStateWidth(showOffer, showCheck, listW)
  local rightW = 6 + (showOffer and (UI.OFFER_SMALL_W + 4) or 0) + (showCheck and 28 or 0) + UI.NEED_GAIN_SUB_W
  return math.max(40, listW - (NEED_SUB_X + UI.NEED_MEMBER_W + 8 + 42) - rightW - 8)
end

local function UpdateNeedMemberRow(b, e, listW)
  local d, m = e.sug, e.member
  b.name:SetText(UI.MemberName(m))
  local text, item = NeedRowText(d)
  b.state:SetText(text)
  FillWornButton(b.wornBtn, item)
  b.gain:SetText(ChipGain(d))
  local showOffer, showCheck, mark = P.RightState(d, m)
  b.offer:SetShown(showOffer)
  b.crafted:SetShown(showCheck)
  b.crafted:SetChecked(mark ~= nil)
  LayoutRight(b, showOffer, showCheck)
  local avail = NeedRowStateWidth(showOffer, showCheck, listW)
  b.gain:SetWidth(UI.NEED_GAIN_SUB_W)
  b.state:SetWidth(avail)
  b.stateW = avail
  b.name:SetAlpha(1)
  b.state:SetAlpha(1)
  P.Dim(b, d.future, { b.gain })
end

local function CategoryRows(entries)
  local cats, byCat = {}, {}
  for _, e in ipairs(entries) do
    if not byCat[e.cat] then byCat[e.cat] = {}; cats[#cats + 1] = e.cat end
    table.insert(byCat[e.cat], e)
  end
  local out = {}
  for _, key in ipairs(cats) do
    out[#out + 1] = { rowKind = "cat", cat = key, n = #byCat[key] }
    if not UI.needsCollapsed[key] then
      for _, e in ipairs(byCat[key]) do out[#out + 1] = e end
    end
  end
  return out
end

function UI.NeedsRows(needs, query, withOffline)
  local all, members, offN = GCA:MatchNeeds(needs, query, withOffline)
  return CategoryRows(all), #all, members, offN, all
end

local CD_ICON = 46
UI.CD_ICON = CD_ICON
local function DetailTitle(parent, text)
  local fs = Label(parent, "GameFontNormalSmall")
  fs:SetText(text)
  return fs
end
function UI.AddRoundIcon(f, size)
  local ring = UI.SKIN.detailRing
  if f.CreateMaskTexture and FileOK(ring.mask) ~= false and FileOK(ring.file) ~= false then
    local icon = f:CreateTexture(nil, "ARTWORK")
    local ok, mask = pcall(f.CreateMaskTexture, f)
    if icon.AddMaskTexture and ok and mask and pcall(mask.SetTexture, mask, ring.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
      icon:SetSize(size, size)
      icon:SetPoint("CENTER", f, "CENTER", 0, 0)
      mask:SetAllPoints(icon)
      icon:AddMaskTexture(mask)
      f.icon, f.mask = icon, mask
      f.ring = f:CreateTexture(nil, "OVERLAY")
      f.ring:SetTexture(ring.file)
      local rs = math.floor(size * 37 / 30 + 0.5)
      f.ring:SetSize(rs, rs)
      f.ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
      f.iconShape = "round"
      return
    end
    icon:Hide()
  end
  AddQualityIcon(f, size - 4, "CENTER", f, "CENTER", 0, 0)
  f.iconShape = "square"
end
function UI.CreateCraftDetail(parent)
  local p = CreateFrame("Frame", nil, parent)
  UI.AddDetailBorder(p)
  local ib = CreateFrame("Button", nil, p)
  ib:SetSize(CD_ICON, CD_ICON)
  ib:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -16)
  UI.AddRoundIcon(ib, CD_ICON)
  if ib.RegisterForClicks then ib:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  P.OnItemClick(ib, function()
    local e = p.entry
    if e and e.group then return e.group.sug, e.group.best and e.group.best.member, e.group.sug.info.link end
  end, UI.OpenRecipe)
  SetTip(ib, "craft icon", function(self) CraftGroupTip(self, p.entry) end)
  ib:SetScript("OnLeave", GameTooltip_Hide)
  p.iconBtn = ib
  p.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  P.NativeFont(p.name, "GameFontHighlightLarge")
  p.name:SetPoint("TOPLEFT", ib, "TOPRIGHT", 12, -4)
  p.name:SetJustifyH("LEFT")
  SingleLine(p.name)
  p.desc = Label(p, "GameFontHighlight")
  p.desc:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -6)
  p.learn = UI.CreateLearnButton(p)
  p.forTitle = DetailTitle(p, L.DETAIL_FOR)
  p.forTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -76)
  p.members = RavenquillExpedition.CreateScrollList(p, 300, NEED_SUB_H * 3,
    { default = { create = CreateNeedMemberRow, update = UpdateNeedMemberRow, height = NEED_SUB_H } })
  p.members:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -92)
  P.RaiseInsetBorder(p, p.members)
  p.reagTitle = DetailTitle(p, L.TIP_REAGENTS)
  p.reag = {}
  p.cost = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.cost:SetJustifyH("LEFT")
  if p.cost.SetWordWrap then p.cost:SetWordWrap(true) end
  p.cost:Hide()
  p.srcTitle = DetailTitle(p, L.SRC_TIP_HEAD .. ":")
  p.srcBox = CreateFrame("Button", nil, p)
  if p.srcBox.RegisterForClicks then p.srcBox:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  p.srcBox:SetScript("OnClick", function(self, button)
    local e = p.entry
    if e and e.group then UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) end
  end)
  SetTip(p.srcBox, "craft sources", function(self)
    local e = p.entry
    if not (e and e.group) then return end
    UI.NotLearnedTip(self, e.group.sug, e.group.best and e.group.best.member)
  end)
  p.srcBox:SetScript("OnLeave", GameTooltip_Hide)
  p.src, p.srcBtn = {}, {}
  local PIN = { "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Tracked" }
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, p.srcBox)
    b:SetHeight(16)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    UI.Skin(b.hl, "rowHover")
    b.pin = b:CreateTexture(nil, "ARTWORK")
    b.pin:SetSize(14, 14)
    b.pin:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.pinOK = false
    for _, a in ipairs(PIN) do
      if P.HasAtlas(a) and P.SetAtlasSafe(b.pin, a) then b.pinOK = true; break end
    end
    local fs = Label(b, "GameFontHighlightSmall")
    b.text = fs
    b:SetScript("OnClick", function(self, button)
      local e = p.entry
      if not (e and e.group) then return end
      if button == "RightButton" or ShiftDown() then
        UI.SourceClick(self, "RightButton", e.group.sug, e.group.best and e.group.best.member)
      elseif self.npc then
        Src.ShowOnMap(self.npc)
      end
    end)
    SetTip(b, "craft source", function(self)
      local e = p.entry
      if not (e and e.group) then return end
      UI.NotLearnedTip(self, e.group.sug, e.group.best and e.group.best.member)
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    p.srcBtn[i] = b
    p.src[i] = fs
  end
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("CENTER")
  return p
end

UI.REAGENT_STEP = 46

function UI.CostText(d, regs)
  local A = GCA.Auction
  if not (A and A.Available()) then return nil, 0 end
  local cost, missing = A.CraftCost(regs)
  if not cost then return nil, 0 end
  local toCraft = rawget(_G, "AUCTIONATOR_L_TO_CRAFT_COLON") or L.AH_TO_CRAFT
  local lines = { toCraft .. " |cffffffff" .. UI.Coins(cost) .. "|r" .. (missing > 0 and (" " .. C.muted .. string.format(L.AH_MISSING, missing) .. "|r") or "") }
  local profit = d.kind ~= "enchant" and d.cand and A.Profit(d.cand.itemID, cost) or nil
  if profit then
    local label = rawget(_G, "AUCTIONATOR_L_PROFIT_COLON") or L.AH_PROFIT
    local amount = profit >= 0 and ("|cffffffff" .. UI.Coins(profit) .. "|r") or ("|cffff2020-" .. UI.Coins(-profit) .. "|r")
    lines[#lines + 1] = label .. " " .. amount
  end
  return table.concat(lines, "\n"), #lines
end
local function ReagentRow(p, i)
  local f = p.reag[i]
  if f then return f end
  f = CreateFrame("Button", nil, p)
  f:SetSize(160, 40)
  AddQualityIcon(f, 36, "LEFT", f, "LEFT", 2, 0)
  f.text = Label(f, "GameFontHighlight")
  f.text:SetPoint("LEFT", f.qual, "RIGHT", 10, 0)
  SetTip(f, "reagent", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.itemID)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  f:SetScript("OnClick", function(self)
    local info = self.itemID and GCA:GetInfo(self.itemID)
    if info and info.link then SafeCall(HandleModifiedItemClick, info.link) end
  end)
  p.reag[i] = f
  return f
end

local Detail = { LIST_TOP = 92, SRC_MAX = 4, SRC_LINE_H = 16 }

function Detail.Clear(p)
  UI.UpdateLearnButton(p.learn, nil)
  for _, f in ipairs(p.reag) do f:Hide() end
  p.cost:Hide()
  p.members:SetData({})
end

function Detail.DescText(e, d)
  local parts = { d.kind == "enchant" and SlotName(d.slot) or CatTitle(e.cat) }
  if e.group.future and d.wearAt then parts[#parts + 1] = Tag(LevelTag(d), C.levelTag) end
  if d.hint then parts[#parts + 1] = Tag(d.hint, C.set) end
  return table.concat(parts, "  ·  ") .. ((not d.known) and "  ·" or "")
end

function Detail.Header(p, e, d, cur, w)
  local ib = p.iconBtn
  ib.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  if ib.iconShape == "square" then SetIconQuality(ib, d.info.quality) end
  local textW = math.max(60, w - 18 - CD_ICON - 12 - 16)
  p.name:SetText(d.info.name or "?")
  p.name:SetWidth(textW)
  p.desc:SetText(Detail.DescText(e, d))
  local descW = math.min(TextWidth(p.desc) + 2, textW)
  p.desc:SetWidth(descW)
  p.learn:ClearAllPoints()
  p.learn:SetPoint("LEFT", p.desc, "RIGHT", 6, 0)
  UI.UpdateLearnButton(p.learn, d, cur, math.max(10, textW - descW - 6))
  p.forTitle:SetText(#e.rows == 1 and L.DETAIL_FOR or string.format(L.DETAIL_FOR_N, #e.rows))
  p.forTitle:SetWidth(math.max(40, w - 36))
end

function Detail.MappableNpc(n)
  return (n and n.map and n.x and n.y) and n or nil
end

function Detail.SourceLines(p, d, cur)
  local lines = {}
  p.srcNpc = {}
  local info = (not d.known) and UI.SourceInfo(d, cur) or nil
  if not info then return lines end
  local list = info.list or {}
  for i = 1, math.min(#list, Detail.SRC_MAX) do
    local s = list[i]
    lines[#lines + 1] = Src.Icon(s.kind) .. " " .. Src.LineOf(s, info)
    p.srcNpc[#lines] = Detail.MappableNpc(s.npc)
  end
  if #list > Detail.SRC_MAX then lines[#lines + 1] = C.muted .. string.format(L.SRC_LINE_MORE, #list - Detail.SRC_MAX) .. "|r" end
  if #list == 0 then lines[1] = Src.Line(info) end
  return lines
end

function Detail.FillReagent(f, reg, colW)
  f.itemID = reg[1]
  f.icon:SetTexture(ItemIcon(reg[1]))
  local need = reg[2] or 0
  local count = GCA.ItemAPI.Count; local have = SafeCall(count, reg[1], true) or 0
  local enough = have >= need
  f.text:SetText(string.format("%d/%d %s", have, need, P.ItemName(reg[1])))
  f.text:SetWidth(math.max(20, colW - 8 - 46))
  if enough then f.text:SetTextColor(1, 1, 1) else f.text:SetTextColor(0.62, 0.62, 0.62) end
  SetIconQuality(f, 1)
  f.enough = enough
  f:Show()
end

function Detail.Reagents(p, regs, y, colW)
  p.reagTitle:ClearAllPoints()
  p.reagTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.reagTitle:SetShown(#regs > 0)
  for i, reg in ipairs(regs) do
    local f = ReagentRow(p, i)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -(y + 18 + (i - 1) * UI.REAGENT_STEP))
    f:SetWidth(colW - 8)
    Detail.FillReagent(f, reg, colW)
  end
  for i = #regs + 1, #p.reag do p.reag[i]:Hide() end
end

function Detail.Cost(p, y, w, costText, costLines)
  p.cost:ClearAllPoints()
  p.cost:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(y + 2))
  p.cost:SetWidth(math.max(40, w - 36))
  p.cost:SetText(costText or "")
  p.cost:SetShown(costLines > 0)
end

function Detail.SourceButton(box, b, i, lines, npc, boxW)
  local fs = b.text
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(i - 1) * Detail.SRC_LINE_H)
  b:SetWidth(boxW)
  b.npc = npc
  local pinW = (npc and b.pinOK) and 17 or 0
  b.pin:SetShown(pinW > 0)
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", b, "LEFT", pinW, 0)
  fs:SetWidth(boxW - pinW)
  fs:SetText(lines[i] or "")
  if npc then fs:SetTextColor(0.40, 0.73, 1.00) else fs:SetTextColor(1, 1, 1) end
  fs:SetShown(lines[i] ~= nil)
  b:SetShown(lines[i] ~= nil)
end

function Detail.Sources(p, lines, y, w)
  local boxW = math.max(40, w - 36)
  p.srcTitle:ClearAllPoints()
  p.srcTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.srcTitle:SetShown(#lines > 0)
  p.srcBox:ClearAllPoints()
  p.srcBox:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(y + 16))
  p.srcBox:SetSize(boxW, math.max(1, #lines * Detail.SRC_LINE_H))
  p.srcBox:SetShown(#lines > 0)
  for i, b in ipairs(p.srcBtn) do Detail.SourceButton(p.srcBox, b, i, lines, p.srcNpc and p.srcNpc[i] or nil, boxW) end
end

function Detail.Members(p, e, room, w)
  local listH = math.max(NEED_SUB_H, math.min(#e.rows * NEED_SUB_H, room))
  p.members:Resize(math.max(100, w - 44), listH)
  p.members:SetData(e.rows)
  p.listH = listH
  return listH
end

function UI:UpdateCraftDetail(e, emptyText)
  local p = self.needDetail
  if not p then return end
  p.entry = e
  local w, h = p.w or 400, p.h or 400
  local shown = e ~= nil
  for _, x in ipairs({ p.iconBtn, p.name, p.desc, p.forTitle, p.members, p.reagTitle, p.srcTitle, p.srcBox }) do x:SetShown(shown) end
  p.empty:SetText(shown and "" or (emptyText or ""))
  p.empty:SetWidth(math.max(40, w - 60))
  if shown then Detail.Fill(p, e, w, h) else Detail.Clear(p) end
end

function Detail.Fill(p, e, w, h)
  local d = e.group.sug
  local cur = e.group.best and e.group.best.member
  Detail.Header(p, e, d, cur, w)
  local regs = d.cand.recipe and d.cand.recipe.r or {}
  local costText, costLines = UI.CostText(d, regs)
  local costH = costLines > 0 and (costLines * 15 + 8) or 0
  local reagH = (#regs > 0 and (18 + #regs * UI.REAGENT_STEP) or 0) + costH
  local lines = Detail.SourceLines(p, d, cur)
  local srcH = #lines > 0 and (18 + #lines * Detail.SRC_LINE_H + 4) or 0
  local listH = Detail.Members(p, e, h - Detail.LIST_TOP - 8 - reagH - srcH - 12, w)
  local y = Detail.LIST_TOP + listH + 10
  Detail.Reagents(p, regs, y, math.floor(w - 36))
  Detail.Cost(p, y + reagH - costH, w, costText, costLines)
  y = y + reagH
  Detail.Sources(p, lines, y, w)
  p.contentH = y + srcH
end

