local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL
local Plain = GS.Plain

local CARD = { height = 60, gap = 12, icon = 40, inset = 12, button = 100 }
local ROW = { height = 22, icon = 18, title = 170, gap = 8, more = "›", dim = 0.55 }
local CARD_BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local function Texture(v)
  v = Plain(v)
  if type(v) == "string" or type(v) == "number" then return v end
end

local function Opener(v) return type(v) == "function" and v or nil end

function ns.Entries(raw, icon)
  local out = {}
  if type(raw) ~= "table" then return out end
  for _, e in ipairs(raw) do
    local title = type(e) == "table" and Plain(e.title, "string")
    if title then
      out[#out + 1] = { title = title, line = Plain(e.line, "string") or "", icon = Texture(e.icon) or icon, open = Opener(e.open),
        action = Plain(e.action, "string"), ends = Plain(e.ends, "number") }
    end
  end
  return out
end

function ns.Headline(mod)
  local h = mod and GS:Call(mod.OverviewHeadline, mod)
  local line = type(h) == "table" and Plain(h.line, "string")
  if line and line ~= "" then return line, Opener(h.open) end
end

local function Backdrop(card)
  if not card.SetBackdrop then return end
  card:SetBackdrop(CARD_BACKDROP)
  card:SetBackdropColor(0.05, 0.035, 0.02, 0.7)
  card:SetBackdropBorderColor(0.36, 0.28, 0.18, 1)
end

local Card = {}

function Card.Step(list) return list.size.height + list.size.gap end

function Card.New(list, i)
  local size = list.size
  local card = CreateFrame("Frame", nil, list, "BackdropTemplate")
  card:SetHeight(size.height)
  card:SetPoint("TOPLEFT", 0, -(i - 1) * Card.Step(list))
  card:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  Backdrop(card)
  card.icon = ns.Icon(card, size.icon)
  card.icon:SetPoint("LEFT", size.inset, 0)
  card.open = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  card.open:SetSize(size.button, 22)
  card.open:SetPoint("RIGHT", -size.inset, 0)
  card.open:SetText(L.OPEN)
  card.open:SetScript("OnClick", function(self) GS:Call(self.entry and self.entry.open, self) end)
  card.title = ns.Text(card, "GameFontNormalLarge")
  card.title:SetPoint("BOTTOMLEFT", card.icon, "RIGHT", size.inset, 1)
  card.title:SetPoint("RIGHT", card.open, "LEFT", -size.inset, 0)
  card.line = ns.Text(card, "GameFontHighlight")
  card.line:SetPoint("TOPLEFT", card.icon, "RIGHT", size.inset, -3)
  card.line:SetPoint("RIGHT", card.open, "LEFT", -size.inset, 0)
  card.line:SetMaxLines(1)
  return card
end

function Card.Fill(card, e)
  card.icon:SetTexture(e.icon)
  card.title:SetText(e.title)
  card.line:SetText(e.line)
  card.open.entry = e
  card.open:SetText(e.action or L.OPEN)
  card.open:SetShown(e.open ~= nil)
end

local Row = {}

function Row.Step() return ROW.height end

function Row.New(list, i)
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(ROW.height)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * Row.Step())
  row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  row.hover = row:CreateTexture(nil, "HIGHLIGHT")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], 0.12)
  row.icon = ns.Icon(row, ROW.icon)
  row.icon:SetPoint("LEFT", 2, 0)
  row.title = ns.Text(row, "GameFontNormal")
  row.title:SetPoint("LEFT", row.icon, "RIGHT", ROW.gap, 0)
  row.title:SetWidth(ROW.title)
  row.more = ns.Text(row, "GameFontNormalLarge", "RIGHT")
  row.more:SetPoint("RIGHT", -4, 0)
  row.more:SetText(ROW.more)
  row.line = ns.Text(row, "GameFontHighlight")
  row.line:SetPoint("LEFT", row.title, "RIGHT", ROW.gap, 0)
  row.line:SetPoint("RIGHT", row.more, "LEFT", -ROW.gap, 0)
  row:SetScript("OnClick", function(self) GS:Call(self.entry and self.entry.open) end)
  ns.Tip(row, function() return row.entry and row.entry.title or "" end, function() return row.entry and row.entry.tip or {} end)
  return row
end

function Row.Fill(row, e)
  local live = e.open ~= nil
  row.icon:SetTexture(e.icon)
  row.icon:SetDesaturated(e.dim and true or false)
  row.title:SetText(e.title)
  row.line:SetText(e.line)
  row.more:SetShown(live)
  row.hover:SetShown(live)
  row:SetAlpha(e.dim and ROW.dim or 1)
end

local function EntryList(parent, style, size)
  local list = CreateFrame("Frame", nil, parent)
  list.style, list.size, list.items = style, size, {}
  return list
end

function ns.EntryCards(parent, size) return EntryList(parent, Card, size or CARD) end
function ns.EntryRows(parent) return EntryList(parent, Row) end

function ns.RenderEntries(list, entries)
  local style, items = list.style, list.items
  for i, e in ipairs(entries) do
    items[i] = items[i] or style.New(list, i)
    items[i].entry = e
    style.Fill(items[i], e)
    items[i]:Show()
  end
  for i = #entries + 1, #items do
    items[i].entry = nil
    items[i]:Hide()
  end
  list:SetHeight(math.max(1, #entries * style.Step(list)))
end
