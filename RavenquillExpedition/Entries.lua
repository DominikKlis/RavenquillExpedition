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

local FEED = { height = 18, glow = 0.2, edge = 0.75, time = "|cff888888%s|r |cffffd100»|r %s" }

local function Clock(t)
  local today = date("%Y%m%d", GS:Now()) == date("%Y%m%d", t)
  return date(today and "%H:%M" or "%d.%m.", t)
end

local function FeedRow(e, open)
  if type(e) ~= "table" then return nil end
  local t, text = Plain(e.t, "number"), Plain(e.text, "string")
  if t and text then return { clock = Clock(t), text = text, highlight = e.highlight == true, open = open } end
end

function ns.Feed(mod, max, open)
  local raw = mod and GS:Call(mod.OverviewFeed, mod, max)
  local title = type(raw) == "table" and Plain(raw.title, "string")
  if not (title and type(raw.rows) == "table") then return nil end
  local rows = {}
  for _, e in ipairs(raw.rows) do
    if #rows < max then rows[#rows + 1] = FeedRow(e, open) end
  end
  return rows[1] and { title = title, rows = rows } or nil
end

local function Outline(row, c)
  local edges = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
  local out = {}
  for i, e in ipairs(edges) do
    local t = row:CreateTexture(nil, "BORDER")
    t:SetColorTexture(c[1], c[2], c[3], FEED.edge)
    t:SetPoint(e[1])
    t:SetPoint(e[2])
    if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
    out[i] = t
  end
  return out
end

local Feed = {}

function Feed.Step() return FEED.height end

function Feed.New(list, i)
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(FEED.height)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * FEED.height)
  row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  row.hover = row:CreateTexture(nil, "HIGHLIGHT")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], 0.12)
  row.glow = { ns.Fill(row, "BACKGROUND", ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], FEED.glow) }
  for _, t in ipairs(Outline(row, ns.GOLD)) do row.glow[#row.glow + 1] = t end
  row.text = ns.Text(row, "GameFontHighlight")
  row.text:SetPoint("LEFT", 2, 0)
  row.text:SetPoint("RIGHT", -2, 0)
  row.text:SetMaxLines(1)
  row:SetScript("OnClick", function(self) GS:Call(self.entry and self.entry.open, self) end)
  return row
end

function Feed.Fill(row, e)
  row.text:SetText(FEED.time:format(e.clock, e.text))
  for _, t in ipairs(row.glow) do t:SetShown(e.highlight) end
end

local ROSTER = { height = 20, name = 160, level = 46, more = { 0.6, 0.6, 0.6 } }

local function ClassColor(class)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and colors and colors[class]
  if c and c.r then return c.r, c.g, c.b end
  return 1, 1, 1
end

local Roster = {}

function Roster.Step() return ROSTER.height end

function Roster.New(list, i)
  local row = CreateFrame("Frame", nil, list)
  row:SetHeight(ROSTER.height)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROSTER.height)
  row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  row.name = ns.Text(row, "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", 6, 0)
  row.name:SetWidth(ROSTER.name)
  row.level = ns.Text(row, "GameFontHighlightSmall")
  row.level:SetPoint("LEFT", row.name, "RIGHT", 0, 0)
  row.level:SetWidth(ROSTER.level)
  row.zone = ns.Text(row, "GameFontHighlightSmall")
  row.zone:SetPoint("LEFT", row.level, "RIGHT", 0, 0)
  row.zone:SetPoint("RIGHT", -4, 0)
  row.zone:SetMaxLines(1)
  return row
end

function Roster.Fill(row, e)
  row.name:SetText(e.name)
  if e.more then row.name:SetTextColor(ROSTER.more[1], ROSTER.more[2], ROSTER.more[3]) else row.name:SetTextColor(ClassColor(e.class)) end
  row.level:SetText(e.level and tostring(e.level) or "")
  row.zone:SetText(e.zone or "")
end

local function EntryList(parent, style, size)
  local list = CreateFrame("Frame", nil, parent)
  list.style, list.size, list.items = style, size, {}
  return list
end

function ns.EntryCards(parent, size) return EntryList(parent, Card, size or CARD) end
function ns.EntryRows(parent) return EntryList(parent, Row) end
function ns.FeedRows(parent) return EntryList(parent, Feed) end
function ns.RosterRows(parent) return EntryList(parent, Roster) end

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
