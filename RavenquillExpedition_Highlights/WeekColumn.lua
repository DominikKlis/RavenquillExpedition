local ADDON, ns = ...
local GS = RavenquillExpedition
local H, News = ns.H, ns.News
local T = GS.NewLocale(ns.NewsLocales)
local Ink = H.PaperInk
local GAP = { title = 10, row = 2, figure = 56, label = 14, rule = 12, honor = 12, kicker = 2 }

function H.WeekColumn(paper)
  local box = CreateFrame("Frame", nil, paper)
  box:SetAllPoints()
  local function Line(role, color, justify) return Ink.Text(paper, role, { parent = box, color = color, justify = justify }) end
  local col = { box = box, title = Line("briefTitle", nil, "CENTER"), rule = Ink.Rule(box, 1, H.INK), rows = {}, honors = {} }
  col.title:SetText(T.WEEK_TITLE)
  for i = 1, #News.WEEK_COUNTS do col.rows[i] = { figure = Line("figure", H.ACCENT, "CENTER"), label = Line("figureLabel") } end
  for i = 1, News.HONOR_MAX do col.honors[i] = { title = Line("kicker", H.ACCENT), who = Line("honor"), why = Line("brief") } end
  box:Hide()
  return col
end

local function SetRow(row, count)
  row.figure:SetText(count and tostring(count.n) or "")
  row.label:SetText(count and count.label or "")
end

local function SetHonor(slot, honor)
  slot.title:SetText(honor and H.Upper(honor.title) or "")
  slot.who:SetText(honor and honor.who or "")
  slot.why:SetText(honor and honor.why or "")
end

function H.FillWeekColumn(paper, week)
  local col = paper.week
  col.shown = week ~= nil
  col.box:SetShown(col.shown)
  paper.brief.box:SetShown(not col.shown)
  for i, row in ipairs(col.rows) do SetRow(row, week and week.counts[i]) end
  for i, slot in ipairs(col.honors) do SetHonor(slot, week and week.honors[i]) end
end

local function Show(slot, on)
  for _, fs in pairs(slot) do fs:SetShown(on) end
end

local function FigureWidth(paper, rows)
  local widest = Ink.U(paper, GAP.figure)
  for _, row in ipairs(rows) do widest = math.max(widest, Ink.Unbounded(row.figure)) end
  return widest
end

local function FlowRow(paper, row, x, y, width, figW)
  local shown = row.label:GetText() ~= ""
  Show(row, shown)
  if not shown then return y end
  local figEnd, labelX = Ink.Place(paper, row.figure, x, y, figW), x + figW + Ink.U(paper, GAP.label)
  Ink.Anchor(paper, row.label, labelX, y, x + width - labelX)
  local labelH = Ink.Height(row.label)
  Ink.Anchor(paper, row.label, labelX, y + math.max(0, (figEnd - y - labelH) / 2))
  return math.max(figEnd, y + labelH) + Ink.U(paper, GAP.row)
end

local function FlowHonor(paper, slot, x, y, width)
  y = Ink.Place(paper, slot.title, x, y, width) + Ink.U(paper, GAP.kicker)
  y = Ink.Place(paper, slot.who, x, y, width)
  return Ink.Place(paper, slot.why, x, y, width)
end

local function FlowHonors(paper, honors, x, top, width, bottom)
  local kept, ends = 0, top
  for i, slot in ipairs(honors) do
    local start = i == 1 and top or ends + Ink.U(paper, GAP.honor)
    local last = kept == i - 1 and slot.who:GetText() ~= "" and FlowHonor(paper, slot, x, start, width)
    local fits = last and last <= bottom or false
    Show(slot, fits)
    if fits then kept, ends = i, last end
  end
  return kept, ends
end

function H.FlowWeekColumn(paper, x, top, width, bottom)
  local col = paper.week
  local y = Ink.Place(paper, col.title, x, top, width) + Ink.U(paper, GAP.title)
  local figW = FigureWidth(paper, col.rows)
  for _, row in ipairs(col.rows) do y = FlowRow(paper, row, x, y, width, figW) end
  local ruleY = y + Ink.U(paper, GAP.rule)
  Ink.Anchor(paper, col.rule, x, ruleY, width)
  local kept, ends = FlowHonors(paper, col.honors, x, ruleY + 1 + Ink.U(paper, GAP.rule), width, bottom)
  col.rule:SetShown(kept > 0)
  return kept > 0 and ends or y, kept
end
