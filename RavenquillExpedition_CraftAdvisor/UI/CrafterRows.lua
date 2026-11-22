local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local C, G, Label, SingleLine, SetTip = P.C, P.G, P.Label, P.SingleLine, P.SetTip
local ProfName, Ago, ItemIcon, ItemName, TextWidth = P.ProfName, P.Ago, P.ItemIcon, P.ItemName, P.TextWidth
local Hex, QualityColor, ClassColor, GainFont, FirstName = P.Hex, P.QualityColor, P.ClassColor, P.GainFont, P.FirstName
local AddQualityIcon, SetIconQuality, SafeCall, LevelTag, SlotName = P.AddQualityIcon, P.SetIconQuality, P.SafeCall, P.LevelTag, P.SlotName
local EMPTY = {}
local TEXT_X = P.MEMBER_TEXT_X
local COL = { ICON = 22, ASK = 56, GAIN = 46, COST = 92, SKILL = 30, GAP = 6 }

UI.CRAFTER_ROW_H = 28

function UI.ProfIcon(prof)
  local p = GCA.PROF_BY_KEY[prof]
  return "|T" .. (p and p.icon or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":14:14:0:0|t"
end

function UI.CrafterStatus(online)
  if online then return C.upgrade .. G("FRIENDS_LIST_ONLINE") .. "|r" end
  return C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"
end

local function ProfRanks(entry)
  local parts = {}
  for i, p in ipairs(entry.profs) do parts[i] = UI.ProfIcon(p.prof) .. " " .. p.rank end
  return table.concat(parts, "  ")
end

local function CrafterTip(self)
  local d = self.data
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(d.key, ClassColor(d.class))
  GameTooltip:AddLine(UI.CrafterStatus(d.online), 1, 1, 1)
  for _, p in ipairs(d.profs) do
    GameTooltip:AddDoubleLine(UI.ProfIcon(p.prof) .. " " .. ProfName(p.prof) .. " " .. p.rank,
      string.format(L.CRAFTERS_TIP_COUNT, p.count), 1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine(string.format(L.CRAFTERS_TIP_SYNCED, Ago(d.time)), 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function AllTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.CRAFTERS_ALL, 1, 1, 1)
  GameTooltip:AddLine(L.CRAFTERS_ALL_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end

local function CreateListRow(parent, onClick, tipName, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(P.MEMBER_ROW_H)
  UI.AddRowArt(b)
  b.right = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.right:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.right:SetJustifyH("RIGHT")
  SingleLine(b.right)
  b.name = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.name:SetPoint("LEFT", b, "LEFT", TEXT_X, 0)
  b.name:SetJustifyH("LEFT")
  SingleLine(b.name)
  b:SetScript("OnClick", onClick)
  SetTip(b, tipName, tip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function FitListRow(b, listW)
  local rightW = math.min(TextWidth(b.right), math.floor(listW / 2))
  b.right:SetWidth(rightW)
  b.name:SetWidth(math.max(40, listW - TEXT_X - rightW - 12))
end

local function UpdateCrafterRow(b, d, listW)
  b.name:SetText(UI.MemberName(d))
  b.right:SetText(ProfRanks(d))
  FitListRow(b, listW)
  b.sel:SetShown(UI.crafterSel == d.key)
end

local function UpdateAllRow(b, d, listW)
  b.name:SetText(L.CRAFTERS_ALL)
  b.right:SetText(C.muted .. tostring(d.count) .. "|r")
  FitListRow(b, listW)
  b.sel:SetShown(UI.crafterSel == nil)
end

UI.CRAFTER_LIST_KINDS = {
  default = { create = function(parent)
    return CreateListRow(parent, function(self) UI:SelectCrafter(self.data.key) end, "crafter row", CrafterTip)
  end, update = UpdateCrafterRow, height = P.MEMBER_ROW_H },
  all = { create = function(parent)
    return CreateListRow(parent, function() UI:SelectCrafter(nil) end, "all crafters row", AllTip)
  end, update = UpdateAllRow, height = P.MEMBER_ROW_H },
}

local function CraftLook(row)
  local info, failed = GCA:GetInfo(row.itemID)
  if not info and not failed then GCA:ScheduleLoadRetry() end
  info = info or EMPTY
  return { name = info.name or row.name, quality = info.quality or 1, icon = info.icon or ItemIcon(row.itemID), link = info.link }
end

local function EnchantLook(row)
  local data = GCA:EnchantData().bySpell[row.spellID]
  local info = data and GCA:EnchantInfo(data) or EMPTY
  return { name = info.name or row.name, quality = 1, icon = info.icon or "Interface\\Icons\\Trade_Engraving" }
end

function UI.RecipeLook(row)
  if row.kind == "enchant" then return EnchantLook(row) end
  return CraftLook(row)
end

local function RecipeCost(row)
  local A = GCA.Auction
  if not (A and A.Available()) then return nil, 0 end
  return A.CraftCost(row.regs)
end

function UI.CrafterAskTarget(row)
  local sel = UI.crafterSel
  for _, c in ipairs(row.crafters or EMPTY) do
    if c.online and (sel == nil or c.key == sel) then return c end
  end
end

local ASK_TEMPLATES = {
  craft = { plain = "WHISPER_ASK_CRAFT", cost = "WHISPER_ASK_CRAFT_COST" },
  enchant = { plain = "WHISPER_ASK_ENCHANT_ANY", cost = "WHISPER_ASK_ENCHANT_COST" },
}

local function ChatCost(cost, missing)
  if not cost or cost <= 0 or missing > 0 then return nil end
  if cost >= 10000 then cost = math.floor(cost / 100 + 0.5) * 100 end
  return UI.Src.PlainMoney(cost)
end

function UI.CrafterAskText(row, who)
  local look = UI.RecipeLook(row)
  local vals = { name = FirstName(who), item = look.link or look.name, cost = ChatCost(RecipeCost(row)) }
  local kind = ASK_TEMPLATES[row.kind] or ASK_TEMPLATES.craft
  local template = L[vals.cost and kind.cost or kind.plain]
  local msg = UI.FillTemplate(template, vals)
  if #msg > UI.WHISPER_MAX then
    vals.item = look.name
    msg = UI.FillTemplate(template, vals)
  end
  return UI.Utf8Cut(msg, UI.WHISPER_MAX)
end

function UI.AskCrafter(row)
  local target = row and UI.CrafterAskTarget(row)
  if not target then return false end
  local msg = UI.CrafterAskText(row, target.key)
  if P.ShiftDown() then P.SendWhisper(target.key, msg, string.format(L.ASK_SENT, target.key)) else P.OpenWhisper(target.key, msg) end
  return true
end

local function AskTip(owner, row)
  local target = row and UI.CrafterAskTarget(row)
  if not target then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.ASK, 1, 1, 1)
  GameTooltip:AddLine(string.format(L.ASK_TIP, FirstName(target.key)), 1, 0.82, 0)
  GameTooltip:AddLine(L.OFFER_TIP_CLICK, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_SHIFT, 1, 1, 1)
  GameTooltip:Show()
end

local function AddUpgradeLines(up)
  if not up then return end
  GameTooltip:AddLine(string.format(L.CRAFTERS_TIP_GAIN, UI.GainUnit(up), SlotName(up.slot)), 0.3, 1, 0.3)
  if up.future and up.wearAt then GameTooltip:AddLine(LevelTag(up), 0.94, 0.71, 0.3) end
  UI.AddStatChanges(up, nil)
end

local function ReagentPrice(reg)
  local A = GCA.Auction
  local unit = A and A.Available() and A.UnitPrice(reg[1])
  return unit and UI.Coins(unit * (reg[2] or 1)) or ""
end

local function AddReagentLines(row)
  if #row.regs == 0 then return end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.TIP_REAGENTS, 1, 0.82, 0)
  local count = GCA.ItemAPI.Count
  for _, reg in ipairs(row.regs) do
    local have = SafeCall(count, reg[1], true) or 0
    GameTooltip:AddDoubleLine(string.format("%d/%d %s", have, reg[2] or 0, ItemName(reg[1])), ReagentPrice(reg), 1, 1, 1, 1, 1, 1)
  end
  local cost = UI.CostText(row, row.regs)
  if cost then GameTooltip:AddLine(cost, 1, 0.82, 0) end
end

function UI.RecipeTip(owner, row)
  if not row then return end
  local look = UI.RecipeLook(row)
  if row.kind == "enchant" then
    UI.PlainItemTip(owner, nil, nil, look.name, row.spellID)
  else
    UI.PlainItemTip(owner, look.link, row.itemID, look.name)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(ProfName(row.prof) .. "  ·  " .. string.format(L.SRC_TIP_SKILL, row.skill), 1, 0.82, 0)
  AddUpgradeLines(row.upgrade)
  AddReagentLines(row)
  UI.AddCrafterList(row.crafters or EMPTY)
  GameTooltip:Show()
end

local function CreateAskButton(b)
  local ask = P.NewTextButton(b, COL.ASK, 20, L.ASK)
  ask.row = b
  ask:SetPoint("RIGHT", b, "RIGHT", -COL.GAP, 0)
  ask:SetScript("OnClick", function(self) UI.AskCrafter(self.row.data) end)
  SetTip(ask, "ask crafter", function(self) AskTip(self, self.row.data) end)
  ask:SetScript("OnLeave", GameTooltip_Hide)
  return ask
end

local function RightLabel(b, template, w)
  local fs = Label(b, template)
  fs:SetJustifyH("RIGHT")
  if w then fs:SetWidth(w) end
  return fs
end

local function CreateRecipeRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(UI.CRAFTER_ROW_H - 2)
  UI.AddRowArt(b)
  AddQualityIcon(b, COL.ICON, "LEFT", b, "LEFT", COL.GAP, 0)
  b.name = Label(b, "GameFontHighlight")
  b.name:SetPoint("LEFT", b.qual, "RIGHT", 8, 0)
  b.ask = CreateAskButton(b)
  b.gain = RightLabel(b, "GameFontHighlight", COL.GAIN)
  GainFont(b.gain)
  b.gain:SetPoint("RIGHT", b, "RIGHT", -(COL.GAP * 2 + COL.ASK), 0)
  b.cost = RightLabel(b, "GameFontHighlightSmall")
  b.cost:SetPoint("RIGHT", b.gain, "LEFT", -COL.GAP, 0)
  b.skill = RightLabel(b, "GameFontHighlightSmall", COL.SKILL)
  b.skill:SetPoint("RIGHT", b.cost, "LEFT", -COL.GAP, 0)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  P.OnItemClick(b, function(self) return nil, nil, self.data and UI.RecipeLook(self.data).link end)
  SetTip(b, "recipe row", function(self) UI.RecipeTip(self, self.data) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function CostCell(row)
  local cost, missing = RecipeCost(row)
  if not cost or cost <= 0 then return "" end
  return UI.Coins(cost) .. (missing > 0 and (C.muted .. "*|r") or "")
end

local function UpdateRecipeRow(b, row, listW)
  local look = UI.RecipeLook(row)
  b.icon:SetTexture(look.icon)
  SetIconQuality(b, look.quality)
  b.name:SetText(Hex(QualityColor(look.quality)) .. tostring(look.name) .. "|r")
  b.skill:SetText(C.muted .. tostring(row.skill) .. "|r")
  b.cost:SetText(CostCell(row))
  local up = row.upgrade
  b.gain:SetText(up and UI.GainNum(up.points) or "")
  b.gain:SetAlpha((up and up.future) and 0.55 or 1)
  b.ask:SetShown(UI.CrafterAskTarget(row) ~= nil)
  local costW = GCA.Auction.Available() and COL.COST or 0
  b.cost:SetWidth(costW)
  local used = COL.GAP + COL.ICON + 4 + 8 + COL.SKILL + costW + COL.GAIN + COL.ASK + COL.GAP * 5
  b.name:SetWidth(math.max(40, listW - used))
end

local function CatText(d)
  local t = ProfName(d.prof) .. " (" .. d.n .. ")"
  if d.upgrades == 0 then return t end
  local up = d.upgrades == 1 and L.CRAFTERS_CAT_UPGRADE_1 or string.format(L.CRAFTERS_CAT_UPGRADES, d.upgrades)
  return t .. "  " .. C.upgrade .. up .. "|r"
end

UI.RECIPE_KINDS = {
  default = { create = CreateRecipeRow, update = UpdateRecipeRow, height = UI.CRAFTER_ROW_H },
  cat = { create = function(parent)
    return UI.CreateCategoryRow(parent, function(self)
      local prof = self.data.prof
      UI.crafterCollapsed[prof] = not UI.crafterCollapsed[prof]
      UI:RefreshCrafters()
    end)
  end, update = function(b, d, listW) b:SetCategory(CatText(d), not UI.crafterCollapsed[d.prof], listW) end, height = P.GROUP_ROW_H },
}

local function Matches(row, q)
  if q == "" then return true end
  return GCA.MatchesSearch(row.name, q) or GCA.MatchesSearch(UI.RecipeLook(row).name, q)
end

local function AddToGroup(out, cat, row)
  if not cat or cat.prof ~= row.prof then
    cat = { rowKind = "cat", prof = row.prof, n = 0, upgrades = 0 }
    out[#out + 1] = cat
  end
  cat.n = cat.n + 1
  if row.upgrade then cat.upgrades = cat.upgrades + 1 end
  if not UI.crafterCollapsed[row.prof] then out[#out + 1] = row end
  return cat
end

function UI.CrafterRecipeRows(rows, query, upgradesOnly)
  local out, cat, shown = {}, nil, 0
  for _, row in ipairs(rows) do
    if (row.upgrade or not upgradesOnly) and Matches(row, query) then
      cat = AddToGroup(out, cat, row)
      shown = shown + 1
    end
  end
  return out, shown
end
