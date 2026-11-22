local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local C, Label, SetTip, SafeCall, TextWidth = P.C, P.Label, P.SetTip, P.SafeCall, P.TextWidth
local Hex, ClassColor, QualityColor, FirstName, ItemName = P.Hex, P.ClassColor, P.QualityColor, P.FirstName, P.ItemName
local AddQualityIcon, SetIconQuality, NewTextButton = P.AddQualityIcon, P.SetIconQuality, P.NewTextButton
local LEFT_W, RIGHT_X, RightW, PANEL_TOP, PANEL_BOTTOM = P.LEFT_W, P.RIGHT_X, P.RightW, P.PANEL_TOP, P.PANEL_BOTTOM
local MEMBER_ROW_H, TEXT_X = P.MEMBER_ROW_H, P.MEMBER_TEXT_X
local CreateScrollList = RavenquillExpedition.CreateScrollList

UI.ORDER_CARD_H, UI.ORDER_HEAD_H, UI.ORDER_EMPTY_H = 76, 48, 26
UI.ORDER_LIST_TOP = 40
local CARD = { ICON = 32, PAD = 10, TEXT_X = 54, BUTTON_W = 96, BUTTON_H = 22, PILL_H = 18 }
UI.orderList = "tome"

UI.ORDER_LIST_DEFS = {
  tome = { label = "ORDERS_TO_ME", sub = "ORDERS_TO_ME_SUB" },
  mine = { label = "ORDERS_FROM_ME", sub = "ORDERS_FROM_ME_SUB" },
  guild = { label = "ORDERS_GUILD", sub = "ORDERS_GUILD_SUB" },
  finished = { label = "ORDERS_FINISHED", sub = "ORDERS_FINISHED_SUB" },
}
UI.ORDER_PILLS = {
  requested = { label = "ORDER_STATE_REQUESTED", rgb = { 0.55, 0.4, 0.06 } },
  accepted = { label = "ORDER_STATE_ACCEPTED", rgb = { 0.13, 0.32, 0.62 } },
  done = { label = "ORDER_STATE_DONE", rgb = { 0.12, 0.45, 0.17 } },
  declined = { label = "ORDER_STATE_DECLINED", rgb = { 0.52, 0.12, 0.1 } },
  withdrawn = { label = "ORDER_STATE_WITHDRAWN", rgb = { 0.32, 0.32, 0.32 } },
  received = { label = "ORDER_STATE_RECEIVED", rgb = { 0.1, 0.34, 0.13 } },
}
UI.ORDER_ACTION_LABELS = { accept = "ORDER_ACCEPT", done = "ORDER_DONE", receive = "ORDER_RECEIVE", decline = "ORDER_DECLINE",
  withdraw = "ORDER_WITHDRAW" }

local function PartyName(key)
  local r = GCA.RQ:RosterEntry(key)
  return Hex(ClassColor(r and r.class)) .. key .. "|r"
end

local function GainText(o)
  if not o.gain then return "" end
  return "  ·  " .. C.upgrade .. string.format("%+d", o.gain) .. " " .. GCA:UnitLabel(nil) .. "|r"
end

local function CrafterText(o)
  local profs = GCA:CrafterProfessions()[o.crafter]
  local rank = profs and profs[o.prof] and profs[o.prof].rank
  if rank then return string.format(L.ORDER_BY_RANK, PartyName(o.crafter), P.ProfName(o.prof), rank) end
  return string.format(L.ORDER_BY, PartyName(o.crafter))
end

function UI.OrderWhoLine(o)
  local role = GCA:OrderRole(o)
  if role == "crafter" then return string.format(L.ORDER_FOR, PartyName(o.requester)) .. GainText(o) end
  if role == "requester" then return CrafterText(o) .. GainText(o) end
  return string.format(L.ORDER_FOR, PartyName(o.requester)) .. "  ·  " .. CrafterText(o)
end

local function Reagent(reg)
  local count = GCA.ItemAPI.Count
  local have = tonumber(SafeCall(count, reg[1], true)) or 0
  local text = reg[2] .. "× " .. ItemName(reg[1])
  if have <= 0 then return text end
  return text .. " " .. C.muted .. "(" .. string.format(L.ORDER_HAVE, have) .. ")|r"
end

function UI.OrderMatsLine(o, recipe)
  if not (recipe and recipe.regs[1]) then return "" end
  local parts = {}
  for i, reg in ipairs(recipe.regs) do parts[i] = Reagent(reg) end
  local brings = GCA:OrderRole(o) == "requester" and L.ORDER_YOU_BRING or string.format(L.ORDER_BRINGS, FirstName(o.requester))
  return string.format(L.ORDER_MATS, table.concat(parts, ", ")) .. "  ·  " .. brings
end

local function OrderLook(o)
  local recipe = GCA:RecipeRow(o.prof, o.spell)
  return recipe, recipe and UI.RecipeLook(recipe) or { name = "?", quality = 1, icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
end

local function PaintPill(pill, state)
  local def = UI.ORDER_PILLS[state]
  pill.text:SetText(L[def.label])
  pill.bg:SetColorTexture(def.rgb[1], def.rgb[2], def.rgb[3], 0.9)
  pill:SetWidth(TextWidth(pill.text) + 18)
end

local function CreatePill(parent)
  local pill = CreateFrame("Frame", nil, parent)
  pill:SetHeight(CARD.PILL_H)
  pill.bg = pill:CreateTexture(nil, "BACKGROUND")
  pill.bg:SetAllPoints()
  UI.AddBorder(pill, 1, 1, 1, 0.25)
  pill.text = Label(pill, "GameFontHighlightSmall")
  pill.text:SetPoint("CENTER")
  pill.text:SetJustifyH("CENTER")
  return pill
end

local function OnAction(button)
  local o = button.card.data and button.card.data.order
  if o and GCA:OrderAction(o, button.action) then UI:RefreshOrders() end
end

local function CreateActionButton(card)
  local btn = NewTextButton(card, CARD.BUTTON_W, CARD.BUTTON_H, "")
  btn.card = card
  btn:SetScript("OnClick", OnAction)
  return btn
end

local function ShowAction(btn, action)
  btn.action = action
  btn:SetShown(action ~= nil)
  if action then btn:SetText(L[UI.ORDER_ACTION_LABELS[action]]) end
end

local function CardTip(self)
  local d = self.data
  local recipe = d and GCA:RecipeRow(d.order.prof, d.order.spell)
  if recipe then UI.RecipeTip(self, recipe) end
end

local function CardLink(self)
  local d = self.data
  local _, look = OrderLook(d.order)
  return nil, nil, look.link
end

local function CardTexts(b)
  b.name = Label(b, "GameFontNormalLarge")
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", CARD.TEXT_X, -8)
  b.who = Label(b, "GameFontNormal")
  b.who:SetPoint("TOPLEFT", b, "TOPLEFT", CARD.TEXT_X, -30)
  b.mats = Label(b, "GameFontHighlightSmall")
  b.mats:SetPoint("TOPLEFT", b, "TOPLEFT", CARD.TEXT_X, -52)
end

local function CreateCard(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(UI.ORDER_CARD_H - 6)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 0.35)
  UI.AddBorder(b, 0.5, 0.42, 0.28, 0.9)
  AddQualityIcon(b, CARD.ICON, "TOPLEFT", b, "TOPLEFT", CARD.PAD, -CARD.PAD)
  CardTexts(b)
  b.pill = CreatePill(b)
  b.pill:SetPoint("TOPRIGHT", b, "TOPRIGHT", -CARD.PAD, -8)
  b.primary = CreateActionButton(b)
  b.primary:SetPoint("TOPRIGHT", b, "TOPRIGHT", -CARD.PAD, -30)
  b.secondary = CreateActionButton(b)
  b.secondary:SetPoint("RIGHT", b.primary, "LEFT", -6, 0)
  P.OnItemClick(b, CardLink)
  SetTip(b, "order card", CardTip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateCard(b, d, listW)
  local o = d.order
  local recipe, look = OrderLook(o)
  b.icon:SetTexture(look.icon)
  SetIconQuality(b, look.quality)
  b.name:SetText(Hex(QualityColor(look.quality)) .. tostring(look.name) .. "|r")
  b.who:SetText(UI.OrderWhoLine(o))
  b.mats:SetText(UI.OrderMatsLine(o, recipe))
  PaintPill(b.pill, o.state)
  local actions = GCA:OrderActions(o)
  ShowAction(b.primary, actions[1])
  ShowAction(b.secondary, actions[2])
  local textW = listW - CARD.TEXT_X - CARD.PAD
  b.name:SetWidth(math.max(40, textW - b.pill:GetWidth() - 8))
  b.who:SetWidth(math.max(40, textW - #actions * (CARD.BUTTON_W + 6)))
  b.mats:SetWidth(math.max(40, textW))
end

local function CreateHead(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.title = Label(f, "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
  f.sub = Label(f, "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -29)
  return f
end

local function UpdateHead(f, d, listW)
  local def = UI.ORDER_LIST_DEFS[d.list]
  f.title:SetText(L[def.label] .. " (" .. d.n .. ")")
  f.sub:SetText(L[def.sub])
  f.title:SetWidth(listW - 8)
  f.sub:SetWidth(listW - 8)
end

local function CreateEmpty(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.text = Label(f, "GameFontDisable")
  f.text:SetPoint("LEFT", f, "LEFT", 8, 0)
  f.text:SetText(L.ORDERS_EMPTY)
  return f
end

UI.ORDER_KINDS = {
  default = { create = CreateCard, update = UpdateCard, height = UI.ORDER_CARD_H },
  head = { create = CreateHead, update = UpdateHead, height = UI.ORDER_HEAD_H },
  empty = { create = CreateEmpty, update = function() end, height = UI.ORDER_EMPTY_H },
}

function UI.OrderRows(lists)
  local out = {}
  for _, key in ipairs(GCA.ORDER_LISTS) do
    local list = lists[key]
    out[#out + 1] = { rowKind = "head", list = key, n = #list }
    if not list[1] then out[#out + 1] = { rowKind = "empty", list = key } end
    for _, o in ipairs(list) do out[#out + 1] = { order = o, list = key } end
  end
  return out
end

local function ScrollToList(self, key)
  local y = self.orderCards:FindY(function(d) return d.rowKind == "head" and d.list == key end)
  if y then self.orderCards:ScrollTo(y) end
end

function UI:SelectOrderList(key)
  UI.orderList = UI.ORDER_LIST_DEFS[key] and key or "tome"
  self:RefreshOrders()
  ScrollToList(self, UI.orderList)
end

local function CreateListRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(MEMBER_ROW_H)
  UI.AddRowArt(b)
  b.right = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.right:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b.right:SetJustifyH("RIGHT")
  b.name = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.name:SetPoint("LEFT", b, "LEFT", TEXT_X, 0)
  b.name:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(self) UI:SelectOrderList(self.data.list) end)
  return b
end

local function UpdateListRow(b, d, listW)
  b.name:SetText(L[UI.ORDER_LIST_DEFS[d.list].label])
  b.right:SetText(C.muted .. d.n .. "|r")
  b.name:SetWidth(math.max(40, listW - TEXT_X - 40))
  b.sel:SetShown(UI.orderList == d.list)
end

UI.ORDER_LIST_KINDS = { default = { create = CreateListRow, update = UpdateListRow, height = MEMBER_ROW_H } }

local function ListPanel(self, ov, painted, listH)
  local inset = P.NewInset(ov, painted)
  inset:SetPoint("TOPLEFT", 10, PANEL_TOP)
  inset:SetSize(LEFT_W, listH)
  self.ordersInset = inset
  self.ordersTitle = Label(inset, "GameFontNormalLarge")
  self.ordersTitle:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -12)
  self.ordersTitle:SetText(L.ORDERS_TITLE)
  self.orderLists = CreateScrollList(inset, LEFT_W - 30, 4 * MEMBER_ROW_H, UI.ORDER_LIST_KINDS)
  self.orderLists:SetPoint("TOPLEFT", 5, -UI.ORDER_LIST_TOP)
  self.ordersHint = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.ordersHint:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 12, 10)
  self.ordersHint:SetWidth(LEFT_W - 24)
  self.ordersHint:SetJustifyH("LEFT")
  self.ordersHint:SetText(L.ORDERS_HINT)
end

local function CardPanel(self, ov, listH, rw)
  local md = CreateFrame("Frame", nil, ov)
  md:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  md:SetSize(rw + 4, listH)
  UI.AddDetailBorder(md)
  self.ordersDetail = md
  self.orderCards = CreateScrollList(md, rw - 38, listH - 16, UI.ORDER_KINDS)
  self.orderCards:SetPoint("TOPLEFT", 11, -8)
  P.RaiseInsetBorder(md, self.orderCards)
end

function UI:BuildOrdersView(c, painted, listH, rw)
  local ov = CreateFrame("Frame", nil, c)
  ov:SetAllPoints(c)
  self.ordersView = ov
  ListPanel(self, ov, painted, listH)
  CardPanel(self, ov, listH, rw)
  return ov
end

function UI:LayoutOrders(w, h)
  if not self.orderCards then return end
  local listH, dw = h + PANEL_TOP - PANEL_BOTTOM, RightW(w) + 4
  self.ordersInset:SetSize(LEFT_W, listH)
  self.ordersDetail:SetSize(dw, listH)
  self.orderCards:Resize(dw - 42, listH - 16, true)
end

function UI:RefreshOrders()
  if not (self.orderCards and self.frame) then return end
  local lists = GCA:OrderLists()
  local rows = {}
  for i, key in ipairs(GCA.ORDER_LISTS) do rows[i] = { list = key, n = #lists[key] } end
  self.orderLists:SetData(rows)
  self.orderCards:SetData(UI.OrderRows(lists))
end

for _, name in ipairs({ "RefreshOrders", "SelectOrderList", "LayoutOrders" }) do UI[name] = P.Guard("UI:" .. name, UI[name]) end
