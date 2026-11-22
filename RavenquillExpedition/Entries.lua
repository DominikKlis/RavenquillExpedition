local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL
local Plain = GS.Plain

local CARD = { height = 60, gap = 12, icon = 40, inset = 12, button = 100 }
local CARD_BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local function Texture(v)
  v = Plain(v)
  if type(v) == "string" or type(v) == "number" then return v end
end

function ns.Entries(raw, icon)
  local out = {}
  if type(raw) ~= "table" then return out end
  for _, e in ipairs(raw) do
    local title = type(e) == "table" and Plain(e.title, "string")
    if title then
      out[#out + 1] = { title = title, line = Plain(e.line, "string") or "", icon = Texture(e.icon) or icon,
        open = type(e.open) == "function" and e.open or nil }
    end
  end
  return out
end

local function Backdrop(card)
  if not card.SetBackdrop then return end
  card:SetBackdrop(CARD_BACKDROP)
  card:SetBackdropColor(0.05, 0.035, 0.02, 0.7)
  card:SetBackdropBorderColor(0.36, 0.28, 0.18, 1)
end

local function NewCard(list, i)
  local card = CreateFrame("Frame", nil, list, "BackdropTemplate")
  card:SetHeight(CARD.height)
  card:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD.height + CARD.gap))
  card:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  Backdrop(card)
  card.icon = ns.Icon(card, CARD.icon)
  card.icon:SetPoint("LEFT", CARD.inset, 0)
  card.open = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  card.open:SetSize(CARD.button, 22)
  card.open:SetPoint("RIGHT", -CARD.inset, 0)
  card.open:SetText(L.OPEN)
  card.open:SetScript("OnClick", function(self) GS:Call(self.entry and self.entry.open) end)
  card.title = ns.Text(card, "GameFontNormalLarge")
  card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", CARD.inset, -2)
  card.title:SetPoint("RIGHT", card.open, "LEFT", -CARD.inset, 0)
  card.line = ns.Text(card, "GameFontHighlight")
  card.line:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", CARD.inset, 3)
  card.line:SetPoint("RIGHT", card.open, "LEFT", -CARD.inset, 0)
  return card
end

function ns.EntryCards(parent)
  local list = CreateFrame("Frame", nil, parent)
  list.cards = {}
  return list
end

function ns.RenderEntryCards(list, entries)
  for i, e in ipairs(entries) do
    local card = list.cards[i] or NewCard(list, i)
    list.cards[i] = card
    card.icon:SetTexture(e.icon)
    card.title:SetText(e.title)
    card.line:SetText(e.line)
    card.open.entry = e
    card.open:SetShown(e.open ~= nil)
    card:Show()
  end
  for i = #entries + 1, #list.cards do list.cards[i]:Hide() end
  list:SetHeight(math.max(1, #entries * (CARD.height + CARD.gap)))
end
