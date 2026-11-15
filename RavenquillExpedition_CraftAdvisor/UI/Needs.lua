local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, LEFT_W, GROUP_ROW_H, NEED_ROW_H = P.SafeCall, P.LEFT_W, P.GROUP_ROW_H, P.NEED_ROW_H
local NEED_SUB_H, C, HasAtlas, SetAtlasSafe = P.NEED_SUB_H, P.C, P.HasAtlas, P.SetAtlasSafe
local FileOK, SingleLine, SetTip, SlotName = P.FileOK, P.SingleLine, P.SetTip, P.SlotName
local QualityColor, Hex, ItemIcon, ItemName = P.QualityColor, P.Hex, P.ItemIcon, P.ItemName
local TextWidth, NativeFont, GainFont, LevelTag = P.TextWidth, P.NativeFont, P.GainFont, P.LevelTag
local Tag, RaiseInsetBorder, CreateScrollList = P.Tag, P.RaiseInsetBorder, P.CreateScrollList
local MEMBER_TEXT_X, Src, ShowSuggestionTooltip = P.MEMBER_TEXT_X, P.Src, P.ShowSuggestionTooltip
local ShiftDown, RowCtx, HideTip, LayoutRight = P.ShiftDown, P.RowCtx, P.HideTip, P.LayoutRight
local RightState, CreateOfferButton, CreateCraftedBox = P.RightState, P.CreateOfferButton, P.CreateCraftedBox
local AddQualityIcon, SetIconQuality = P.AddQualityIcon, P.SetIconQuality

---------------------------------------------------------------------------
-- Guild needs. K5 grouped the list by craft; K8 (native profession window): the LEFT list is the recipe list -
-- category headers per gear slot (rings / trinkets one each), under them one plain text row per craft ("Name [n]",
-- n = members it is an upgrade for, best gain right); the RIGHT detail panel shows the selected craft (round icon,
-- name, slot + tags, "Would be an upgrade for:" with one row per member - class-coloured name, what they wear, gain,
-- the red Offer button, the crafted box; click = that member in "By member" on that slot - then the reagents with
-- have/need and, for a recipe you don't know, where to get it). Offline members only with "Include offline members
-- (n)" (Filter menu; db.settings.needsOffline). Shift/Ctrl-click links the item; right-click = K7 source menu.
---------------------------------------------------------------------------
local function ModifiedDown()
  if ShiftDown() then return true end
  return IsControlKeyDown and SafeCall(IsControlKeyDown) and true or false
end
UI.ModifiedDown = ModifiedDown -- (the cards, created above this, call it through UI)

UI.needsCollapsed = {} -- category (slot section) -> collapsed (per open, not saved)
UI.NEED_GAIN_W = 46

-- the gain of a member under a craft: "+8.4" (that member's AP/SP-equivalents)
-- the gain of a member under a craft: "+8.4" (that member's AP/SP-equivalents)
local function ChipGain(s) return UI.GainNum(s.points) end
UI.ChipGain = ChipGain

local function CraftGroupTip(owner, e)
  local g = e and e.group
  if not g then return end
  ShowSuggestionTooltip(owner, g.sug, g.best and g.best.member) -- K17: plain item tooltip + that member's worn item
end
UI.CraftGroupTip = CraftGroupTip

-- K8: a craft = a recipe-list row: the name (GameFontHighlight_NoShadow, white; a recipe you don't know grey, browse
-- teal), its Count " [n]" right after it, the best gain right; the recipe row's hover / selected art. Too-high-level
-- only crafts dimmed. Click = show it in the detail panel.
local function CreateCraftGroupRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NEED_ROW_H)
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

local function UpdateCraftGroupRow(b, e)
  local g = e.group
  local d = g.sug
  local cur = g.best and g.best.member
  local colour = (cur and cur.browse) and C.browse or ((not d.known) and C.notLearned or nil)
  b.label:SetText(Tag(d.info.name or "?", colour))
  b.count:SetText(" [" .. #e.rows .. "]")
  b.gain:SetText(e.rows[1] and ChipGain(e.rows[1].sug) or "")
  local avail = math.max(40, (UI.needsW or (LEFT_W - 30)) - MEMBER_TEXT_X - UI.NEED_GAIN_W - 10)
  local countW = TextWidth(b.count)
  b.label:SetWidth(math.max(20, math.min(TextWidth(b.label) + 2, avail - countW)))
  b.textW = avail
  local a = g.future and 0.55 or 1
  for _, f in ipairs({ b.label, b.count, b.gain }) do f:SetAlpha(a) end
  b.dimmed = g.future
  b.sel:SetShown(UI.needSel == g.key)
end

-- K8: the slot categories of the needs list (the recipe list's category header)
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
local function UpdateNeedsCatRow(b, d)
  b.rowW = UI.needsW
  b:SetCategory(CatTitle(d.cat), not UI.needsCollapsed[d.cat])
end
UI.NEEDS_KINDS = { cat = { create = CreateNeedsCatRow, update = UpdateNeedsCatRow, height = GROUP_ROW_H } }

-- a member of the selected craft (detail panel)
local NEED_SUB_X = 8
local NEED_SUB_NAME_W = 130
UI.NEED_MEMBER_W = 110 -- the member-name column of the detail rows (user 2026-11-15); longer names end in "…"
local function CreateNeedMemberRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NEED_SUB_H - 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hlKind = UI.Skin(b.hl, "rowHover")
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.name:SetPoint("LEFT", b, "LEFT", NEED_SUB_X, 0)
  b.name:SetWidth(NEED_SUB_NAME_W)
  b.name:SetJustifyH("LEFT")
  SingleLine(b.name)
  -- K10: line 1 = the member's name (class colour; offline = grey, no "offline" text), line 2 = what they wear
  -- now: a small item icon in the profession slot frame (quality coloured, tooltip/Shift-click = the worn item)
  -- and its name in quality colour; an empty slot / the current enchant as grey text.
  -- K10b (user): the worn item's icon is the row's big left icon (32 px, both lines tall); name + item name beside it
  -- User 2026-11-15: one line. Member name in its own column on the left (class colour), then the worn item's icon
  -- with its name right beside it (strict rule), then gain / Offer / box. Nothing under the item name.
  b.name:ClearAllPoints()
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
  b.state = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.state:SetPoint("LEFT", b.wornBtn, "RIGHT", 8, 0)
  b.state:SetJustifyH("LEFT")
  SingleLine(b.state)
  b.offer = CreateOfferButton(b)
  b.crafted = CreateCraftedBox(b, b) -- K6: the same (MinimalCheckboxTemplate) box as the cards and the sheet
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  LayoutRight(b, true, true)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self, button)
    local e = self.data
    if not (e and e.sug) then return end
    if UI.SourceClick(self, button, e.sug, e.member) then return end
    -- the row shows the member's equipped item: a plain click does nothing (user 2026-11-15; it used to jump to
    -- "Nach Mitglied"); Shift/Ctrl-click links the craft, right-click the source menu
    if ModifiedDown() and e.sug.info.link then HandleModifiedItemClick(e.sug.info.link) end
  end)
  SetTip(b, "need member", function(self)
    local d, cur = RowCtx(self)
    if d then ShowSuggestionTooltip(self, d, cur) end
  end)
  b:SetScript("OnLeave", HideTip)
  return b
end

-- "online · wears [X]" / "offline · slot empty"; enchants: what the enchant replaces
local function NeedState(d, m)
  local parts = { m.online and L.NEEDS_STATE_ON or L.NEEDS_STATE_OFF }
  local pair = UI.RowPair(d)
  local wear
  if d.kind == "enchant" then
    local item = d.item and d.item.name or "?"
    wear = d.equipped and string.format(L.REPLACES_ON, d.equipped.name or "?", item) or string.format(L.NO_ENCHANT_ON, item)
  elseif d.equipped then
    wear = string.format(L.NEEDS_WEARS, Hex(QualityColor(d.equipped.quality)) .. (d.equipped.name or "?") .. "|r")
  else
    wear = L.CARDS_EMPTY
  end
  parts[#parts + 1] = (pair and (pair .. ": ") or "") .. wear
  return table.concat(parts, "  ·  ")
end
UI.NeedState = NeedState

UI.NEED_GAIN_SUB_W = 60
local function UpdateNeedMemberRow(b, e)
  local d, m = e.sug, e.member
  -- user 2026-11-15: member column | icon + the worn item's name (quality colour; empty slot dim) followed, as on the
  -- cards' titles, by the muted pair slot "(Ring 1)" and the orange level tag; an enchant: what it replaces, muted
  b.name:SetText(UI.MemberName(m)) -- user 2026-11-15: class colour always + online/offline dot
  local eq = d.kind ~= "enchant" and d.equipped or nil
  local pair = UI.RowPair(d)
  local text
  if d.kind == "enchant" then
    eq = d.item
    text = eq and (Hex(QualityColor(eq.quality)) .. (eq.name or "?") .. "|r") or "?"
    text = text .. "  " .. C.muted .. (d.equipped and string.format(L.REPLACES, d.equipped.name or "?") or L.NO_ENCHANT) .. "|r"
  elseif eq then
    text = Hex(QualityColor(eq.quality)) .. (eq.name or "?") .. "|r"
  else
    text = C.dim .. L.CARDS_EMPTY .. "|r"
  end
  if pair then text = text .. " " .. C.muted .. "(" .. pair .. ")|r" end
  if d.future and d.wearAt then text = text .. "  " .. Tag(LevelTag(d), C.levelTag) end
  b.state:SetText(text)
  if eq and eq.icon then
    b.wornBtn.icon:SetTexture(eq.icon)
    b.wornBtn.icon:Show()
    SetIconQuality(b.wornBtn, eq.quality)
    b.wornBtn.link = eq.link
    b.wornBtn:SetAlpha(1)
  else
    b.wornBtn.icon:SetTexture(nil)
    SetIconQuality(b.wornBtn, 0, 0.3, 0.3, 0.3)
    b.wornBtn.link = nil
    b.wornBtn:SetAlpha(0.5)
  end
  b.gain:SetText(ChipGain(d))
  local showOffer, showCheck, mark = RightState(d, m)
  b.offer:SetShown(showOffer)
  b.crafted:SetShown(showCheck)
  b.crafted:SetChecked(mark ~= nil)
  LayoutRight(b, showOffer, showCheck)
  local rightW = 6 + (showOffer and (UI.OFFER_SMALL_W + 4) or 0) + (showCheck and 28 or 0) + UI.NEED_GAIN_SUB_W
  local avail = math.max(40, (UI.detailListW or 300) - (NEED_SUB_X + UI.NEED_MEMBER_W + 8 + 42) - rightW - 8)
  b.gain:SetWidth(UI.NEED_GAIN_SUB_W)
  b.state:SetWidth(avail)
  b.stateW = avail
  b.name:SetAlpha(1)
  b.state:SetAlpha(1)
  b.wornBtn:SetAlpha(b.wornBtn.link and 1 or 0.5)
  local f = d.future and 0.55 or 1
  b.gain:SetAlpha(f)
  b.dimmed = d.future and true or false
end

-- entries for the needs list (K8): per slot category (order of its best craft) a header and, unless collapsed, its
-- crafts; search = item name (the whole craft) or member name (only those members), plain text, ASCII
-- case-insensitive. Returns the entries, the number of crafts and members shown, how many offline members have
-- upgrades (the Filter entry's count) and every matching craft entry (also those under a collapsed header).
function UI.NeedsRows(needs, query, withOffline)
  local q = tostring(query or ""):lower():match("^%s*(.-)%s*$") or ""
  local groups = needs and (withOffline and needs.craftsAll or needs.crafts) or {}
  local crafts, members, seen = 0, 0, {}
  local cats, byCat, all = {}, {}, {}
  for _, g in ipairs(groups) do
    local rows = g.rows
    if q ~= "" and not tostring(g.sug.info and g.sug.info.name or ""):lower():find(q, 1, true) then
      rows = {}
      for _, r in ipairs(g.rows) do
        if tostring(r.member.key):lower():find(q, 1, true) then rows[#rows + 1] = r end
      end
    end
    if #rows > 0 then
      crafts = crafts + 1
      for _, r in ipairs(rows) do
        if not seen[r.member.key] then seen[r.member.key] = true; members = members + 1 end
      end
      local key = GCA.SECTION_OF[g.sug.slot] or g.sug.slot
      if not byCat[key] then byCat[key] = {}; cats[#cats + 1] = key end
      local e = { group = g, rows = rows, cat = key }
      table.insert(byCat[key], e)
      all[#all + 1] = e
    end
  end
  local out = {}
  for _, key in ipairs(cats) do
    out[#out + 1] = { rowKind = "cat", cat = key, n = #byCat[key] }
    if not UI.needsCollapsed[key] then
      for _, e in ipairs(byCat[key]) do out[#out + 1] = e end
    end
  end
  local off, offN = {}, 0
  for _, r in ipairs(needs and needs.offline or {}) do
    if not off[r.member.key] then off[r.member.key] = true; offN = offN + 1 end
  end
  return out, crafts, members, offN, all
end

-- K8: the detail panel of the selected craft (the schematic form's place): framed by the skin role detailBorder,
-- the window's page art shows through (no own background, as the client's form).
local CD_ICON = 46
UI.CD_ICON = CD_ICON
local function DetailTitle(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  SingleLine(fs)
  return fs
end
-- a round item icon (K8): the icon masked round (TempPortraitAlphaMask, as ForeverDungeonJournal LFGButton.lua:386-390
-- does on Forever) with the bronze ring (UI.SKIN.detailRing) around it; where masks / the files are missing: the
-- square icon in the reagent-slot frame. f.iconShape = "round" / "square".
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
      local rs = math.floor(size * 37 / 30 + 0.5) -- FDJ: a 37 px ring around a 30 px icon
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
  ib:SetScript("OnClick", function(self, button)
    local e = p.entry
    if not (e and e.group) then return end
    if UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) then return end
    -- user 2026-11-15: the craft's own item (this icon) opens the recipe, as in "Nach Mitglied"; the member rows
    -- (their equipped items) and the craft list rows don't. Shift/Ctrl-click links it.
    if ModifiedDown() then
      if e.group.sug.info.link then HandleModifiedItemClick(e.group.sug.info.link) end
      return
    end
    UI.OpenRecipe(e.group.sug, e.group.best and e.group.best.member)
  end)
  SetTip(ib, "craft icon", function(self) CraftGroupTip(self, p.entry) end)
  ib:SetScript("OnLeave", GameTooltip_Hide)
  p.iconBtn = ib
  p.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  NativeFont(p.name, "GameFontHighlightLarge")
  p.name:SetPoint("TOPLEFT", ib, "TOPRIGHT", 12, -4)
  p.name:SetJustifyH("LEFT")
  SingleLine(p.name)
  p.desc = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.desc:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -6)
  p.desc:SetJustifyH("LEFT")
  SingleLine(p.desc)
  p.learn = UI.CreateLearnButton(p)
  p.forTitle = DetailTitle(p, L.DETAIL_FOR)
  p.forTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -76)
  p.members = CreateScrollList(p, 300, NEED_SUB_H * 3, NEED_SUB_H, CreateNeedMemberRow, UpdateNeedMemberRow)
  p.members:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -92)
  RaiseInsetBorder(p, p.members)
  p.reagTitle = DetailTitle(p, L.TIP_REAGENTS)
  p.reag = {}
  -- user 2026-11-15: Auctionator's "Zum herstellen" / "Gewinn" under the reagents (only with Auctionator)
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
    UI.NotLearnedTip(self, e.group.sug, e.group.best and e.group.best.member) -- the same tooltip as everywhere
  end)
  p.srcBox:SetScript("OnLeave", GameTooltip_Hide)
  -- K14: each source line is its own button: click = waypoint + world map on that spot (when our data has
  -- coordinates; a map pin marks those), right-click = the source menu, Shift-click = link the pattern
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
      if HasAtlas(a) and SetAtlasSafe(b.pin, a) then b.pinOK = true; break end
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    SingleLine(fs)
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
      UI.NotLearnedTip(self, e.group.sug, e.group.best and e.group.best.member) -- the same tooltip as everywhere
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    p.srcBtn[i] = b
    p.src[i] = fs
  end
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("CENTER")
  return p
end

-- one reagent: the item in the reagent slot frame, "have/need Name" (wraps to two lines), item tooltip on hover,
-- (Shift-)click links it
UI.REAGENT_STEP = 46 -- one reagent row (40 px) + gap, as spaced in the crafting window

-- Auctionator (user 2026-11-15): "Zum herstellen: 38s" and "Gewinn: -4s 75c" as Auctionator writes them in the
-- crafting window (its own localized labels when it has them; gold label, white amount, red when negative).
-- Returns text, number of lines (0 = nothing: Auctionator missing or no reagents).
function UI.Coins(c)
  if type(GetMoneyString) == "function" then
    local ok, s = pcall(GetMoneyString, c, true)
    if ok and type(s) == "string" then return s end
  end
  return UI.Src.Money(c) or "0"
end
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
  -- the crafting window's reagent text: GameFontHighlight, "0/5 Name", one line
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("LEFT", f.qual, "RIGHT", 10, 0)
  f.text:SetJustifyH("LEFT")
  SingleLine(f.text)
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

-- fills and stacks the detail panel for one craft entry (nil = nothing to show: the empty text)
function UI:UpdateCraftDetail(e, emptyText)
  local p = self.needDetail
  if not p then return end
  p.entry = e
  local w, h = p.w or 400, p.h or 400
  local shown = e ~= nil
  for _, x in ipairs({ p.iconBtn, p.name, p.desc, p.forTitle, p.members, p.reagTitle, p.srcTitle, p.srcBox }) do x:SetShown(shown) end
  p.empty:SetText(shown and "" or (emptyText or ""))
  p.empty:SetWidth(math.max(40, w - 60))
  if not shown then
    UI.UpdateLearnButton(p.learn, nil)
    for _, f in ipairs(p.reag) do f:Hide() end
    p.members:SetData({})
    return
  end
  local g, d = e.group, e.group.sug
  local cur = g.best and g.best.member
  local ib = p.iconBtn
  ib.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  if ib.iconShape == "square" then SetIconQuality(ib, d.info.quality) end
  local textW = math.max(60, w - 18 - CD_ICON - 12 - 16)
  p.name:SetText(d.info.name or "?")
  p.name:SetWidth(textW)
  local parts = { d.kind == "enchant" and SlotName(d.slot) or CatTitle(e.cat) }
  if g.future and d.wearAt then parts[#parts + 1] = Tag(LevelTag(d), C.levelTag) end
  if d.hint then parts[#parts + 1] = Tag(d.hint, C.set) end
  p.desc:SetText(table.concat(parts, "  ·  ") .. ((not d.known) and "  ·" or ""))
  -- user 2026-11-15: the shared source button right after the slot line (as on the cards and the sheet)
  local descW = math.min(TextWidth(p.desc) + 2, textW)
  p.desc:SetWidth(descW)
  p.learn:ClearAllPoints()
  p.learn:SetPoint("LEFT", p.desc, "RIGHT", 6, 0)
  UI.UpdateLearnButton(p.learn, d, cur, math.max(10, textW - descW - 6))
  p.forTitle:SetText(#e.rows == 1 and L.DETAIL_FOR or string.format(L.DETAIL_FOR_N, #e.rows))
  p.forTitle:SetWidth(math.max(40, w - 36))
  -- bottom blocks first (their heights decide how much room the member list gets)
  local regs = d.cand.recipe and d.cand.recipe.r or {}
  -- user 2026-11-15: reagents exactly as the crafting window lists them: one column, "0/5 Dickes Leder" beside the
  -- icon (grey while you have too few), UI.REAGENT_STEP px per reagent
  local cols = 1
  local colW = math.floor(w - 36)
  local reagH = #regs > 0 and (18 + #regs * UI.REAGENT_STEP) or 0
  local costText, costLines = UI.CostText(d, regs)
  local costH = costLines > 0 and (costLines * 15 + 8) or 0
  reagH = reagH + costH
  local info = (not d.known) and UI.SourceInfo(d, cur) or nil
  local lines = {}
  if info then
    local list = info.list or {}
    p.srcNpc = {}
    for i = 1, math.min(#list, 4) do
      local s = list[i]
      lines[#lines + 1] = Src.Icon(s.kind) .. " " .. Src.LineOf(s, info) -- prices: in the tooltip
      local n = s.npc
      p.srcNpc[#lines] = (n and n.map and n.x and n.y) and n or nil
    end
    if #list > 4 then lines[#lines + 1] = C.muted .. string.format(L.SRC_LINE_MORE, #list - 4) .. "|r" end
    if #list == 0 then lines[1] = Src.Line(info) end
  end
  if not info then p.srcNpc = {} end
  local srcH = #lines > 0 and (18 + #lines * 16 + 4) or 0
  local listTop = 92
  local room = h - listTop - 8 - reagH - srcH - 12
  local listH = math.max(NEED_SUB_H, math.min(#e.rows * NEED_SUB_H, room))
  UI.detailListW = math.max(100, w - 44)
  p.members:Resize(UI.detailListW, listH)
  p.members:SetData(e.rows)
  p.listH = listH
  local y = listTop + listH + 10
  p.reagTitle:ClearAllPoints()
  p.reagTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.reagTitle:SetShown(#regs > 0)
  for i, reg in ipairs(regs) do
    local f = ReagentRow(p, i)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p, "TOPLEFT", 16 + col * colW, -(y + 18 + row * UI.REAGENT_STEP))
    f:SetWidth(colW - 8)
    f.itemID = reg[1]
    f.icon:SetTexture(ItemIcon(reg[1]))
    local count = GCA.ItemAPI.Count; local have = SafeCall(count, reg[1], true) or 0
    local enough = have >= (reg[2] or 0)
    f.text:SetText(string.format("%d/%d %s", have, reg[2] or 0, ItemName(reg[1])))
    f.text:SetWidth(math.max(20, colW - 8 - 46))
    if enough then f.text:SetTextColor(1, 1, 1) else f.text:SetTextColor(0.62, 0.62, 0.62) end
    SetIconQuality(f, 1)
    f.enough = enough
    f:Show()
  end
  for i = #regs + 1, #p.reag do p.reag[i]:Hide() end
  p.cost:ClearAllPoints()
  p.cost:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(y + reagH - costH + 2))
  p.cost:SetWidth(math.max(40, w - 36))
  p.cost:SetText(costText or "")
  p.cost:SetShown(costLines > 0)
  y = y + reagH
  p.srcTitle:ClearAllPoints()
  p.srcTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.srcTitle:SetShown(#lines > 0)
  p.srcBox:ClearAllPoints()
  p.srcBox:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(y + 16))
  p.srcBox:SetSize(math.max(40, w - 36), math.max(1, #lines * 16))
  p.srcBox:SetShown(#lines > 0)
  for i, b in ipairs(p.srcBtn) do
    local fs, npc = b.text, p.srcNpc and p.srcNpc[i] or nil
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p.srcBox, "TOPLEFT", 0, -(i - 1) * 16)
    b:SetWidth(math.max(40, w - 36))
    b.npc = npc
    local pin = npc and b.pinOK
    b.pin:SetShown(pin and true or false)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", pin and 17 or 0, 0)
    fs:SetWidth(math.max(40, w - 36) - (pin and 17 or 0))
    fs:SetText(lines[i] or "")
    -- clickable lines (coordinates known) in the client's link colour; the rest stays plain
    if npc then fs:SetTextColor(0.40, 0.73, 1.00) else fs:SetTextColor(1, 1, 1) end
    fs:SetShown(lines[i] ~= nil)
    b:SetShown(lines[i] ~= nil)
  end
  p.contentH = y + srcH
end

-- shared with the files loaded after this one (P)
P.CreateCraftGroupRow = CreateCraftGroupRow
P.ModifiedDown = ModifiedDown
P.UpdateCraftGroupRow = UpdateCraftGroupRow
