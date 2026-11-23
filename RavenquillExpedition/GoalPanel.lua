local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL
local Text = ns.Text

local BAR = { width = 410, height = 18 }
local HEIGHT = { goal = 78, none = 56 }
local FILL = { going = { 0.62, 0.43, 0.08 }, done = { 0.2, 0.52, 0.22 } }
local RAIDS = GS.GOAL_RAIDS

local function IAmOfficer() return GS:IsOfficer(GS:PlayerKey()) == true end

function ns.GoalLabel(goal)
  local kind = GS.GOAL_KINDS[goal.kind]
  if kind.raid then return L[kind.label]:format(L["RAID_" .. goal.raid]) end
  return L[kind.label]:format(goal.target)
end

local function Bar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(BAR.width, BAR.height)
  local edge = bar:CreateTexture(nil, "BACKGROUND")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(ns.GOLD[1] * 0.6, ns.GOLD[2] * 0.6, ns.GOLD[3] * 0.6, 1)
  local bg = bar:CreateTexture(nil, "BORDER")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.03, 0.03, 1)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  bar.text = Text(bar, "GameFontHighlight", "CENTER")
  bar.text:SetPoint("CENTER")
  return bar
end

local function BuildProgress(s)
  s.label = Text(s, "GameFontHighlightMedium")
  s.label:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 12, -8)
  s.bar = Bar(s)
  s.bar:SetPoint("TOPLEFT", s.label, "BOTTOMLEFT", 0, -8)
  s.left = Text(s, "GameFontDisable")
  s.left:SetPoint("LEFT", s.bar, "RIGHT", 18, 0)
  s.about = CreateFrame("Frame", nil, s)
  s.about:SetAllPoints(s.label)
  s.about:EnableMouse(true)
  ns.Tip(s.about, L.GOAL_TITLE, function() return { s.goal and L.GOAL_SET_BY:format(s.goal.setBy) } end)
end

local function BuildEmpty(s, onPick)
  s.none = Text(s, "GameFontHighlight")
  s.none:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 12, -10)
  s.set = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
  s.set:SetSize(150, 22)
  s.set:SetPoint("TOPRIGHT", 0, -2)
  s.set:SetText(L.GOAL_SET)
  s.set:SetScript("OnClick", onPick)
end

function ns.BuildGoalSection(parent, onPick)
  local s = CreateFrame("Frame", nil, parent)
  s.title = Text(s, "GameFontNormalLarge")
  s.title:SetPoint("TOPLEFT", 0, 0)
  s.title:SetText(L.GOAL_TITLE)
  s.change = ns.TextLink(s, L.GOAL_CHANGE, onPick)
  s.change.text:SetPoint("TOPRIGHT", -4, -3)
  BuildProgress(s)
  BuildEmpty(s, onPick)
  s.none:SetText(L.GOAL_NONE)
  local rule = s:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(ns.GOLD[1], ns.GOLD[2], ns.GOLD[3], 0.25)
  return s
end

local function RenderBar(bar, goal, current, total)
  bar.fill:SetShown((current or 0) > 0)
  if not current then return bar.text:SetText(L.GOAL_NO_PROGRESS) end
  local done = current >= total
  local c = done and FILL.done or FILL.going
  bar.fill:SetColorTexture(c[1], c[2], c[3], 1)
  bar.fill:SetWidth(math.max(1, BAR.width * current / total))
  local text = L[GS.GOAL_KINDS[goal.kind].unit]:format(current, total)
  bar.text:SetText(done and L.GOAL_DONE:format(text) or text)
end

local function DaysLeft(left) return left <= 1 and L.GOAL_LAST_DAY or L.GOAL_DAYS_LEFT:format(left) end

local function ShowParts(s, goal, officer)
  for _, part in ipairs({ s.label, s.bar, s.left, s.about }) do part:SetShown(goal ~= nil) end
  s.none:SetShown(goal == nil)
  s.set:SetShown(goal == nil)
  s.change:SetShown(goal ~= nil and officer)
  s.change.text:SetShown(goal ~= nil and officer)
  s:SetHeight(goal and HEIGHT.goal or HEIGHT.none)
end

function ns.RenderGoalSection(s)
  local goal, officer = GS:Goal(), IAmOfficer()
  s.goal = goal
  s:SetShown(goal ~= nil or officer)
  if not (goal or officer) then return nil end
  ShowParts(s, goal, officer)
  if goal then
    s.label:SetText(ns.GoalLabel(goal))
    RenderBar(s.bar, goal, GS:GoalProgress(goal))
    s.left:SetText(DaysLeft(GS.Week(GS:Now()).left))
  end
  return goal and HEIGHT.goal or HEIGHT.none
end

local function IndexOf(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
end

local function Choice(pick, kind, label, range)
  local spec = GS.GOAL_KINDS[kind]
  local o = { type = "range", label = label, min = spec.min, max = spec.max, step = spec.step, valueWidth = range and range.width,
    display = range and range.display, get = function() return pick[kind] end, set = function(v) pick[kind] = v end }
  if range then o.min, o.max = 1, range.n end
  return o
end

local function Apply(pick, kind, onDone)
  return { type = "button", label = L.GOAL_APPLY, func = function()
    local raid = kind == "raid" and RAIDS[pick.raid] or nil
    if GS:SetGoal({ kind = kind, raid = raid, target = not raid and pick[kind] or nil }) then onDone() end
  end }
end

local function PickerOptions(pick, onDone)
  local raids = { n = #RAIDS, width = 170, display = function(i) return L["RAID_" .. RAIDS[i]] end }
  return {
    { type = "header", label = L.GOAL_PICK_RAID }, Choice(pick, "raid", L.GOAL_RAID_LABEL, raids), Apply(pick, "raid", onDone),
    { type = "header", label = L.GOAL_PICK_RUNS }, Choice(pick, "runs", L.GOAL_COUNT_LABEL), Apply(pick, "runs", onDone),
    { type = "header", label = L.GOAL_PICK_LEVELS }, Choice(pick, "levels", L.GOAL_COUNT_LABEL), Apply(pick, "levels", onDone),
  }
end

function ns.BuildGoalPicker(parent, onDone)
  local p = CreateFrame("Frame", nil, parent)
  p.title = Text(p, "GameFontNormalLarge")
  p.title:SetPoint("TOPLEFT", 16, -14)
  p.title:SetText(L.GOAL_PICK_TITLE)
  p.back = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.back:SetSize(110, 22)
  p.back:SetPoint("TOPRIGHT", -20, -12)
  p.back:SetText(L.BACK)
  p.back:SetScript("OnClick", onDone)
  p.hint = Text(p, "GameFontHighlightSmall")
  p.hint:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
  p.hint:SetPoint("RIGHT", p, "RIGHT", -20, 0)
  p.hint:SetTextColor(0.8, 0.8, 0.8)
  p.hint:SetText(L.GOAL_PICK_HINT)
  p.pick = {}
  p.panel = ns.BuildPanel(p, PickerOptions(p.pick, onDone))
  p.panel:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", -4, -10)
  p.panel:Show()
  p:Hide()
  return p
end

function ns.SeedGoalPicker(p)
  local goal, kinds = GS:Goal(), GS.GOAL_KINDS
  p.pick.raid = IndexOf(RAIDS, goal and goal.raid or "mc")
  p.pick.runs = goal and goal.kind == "runs" and goal.target or kinds.runs.default
  p.pick.levels = goal and goal.kind == "levels" and goal.target or kinds.levels.default
end

function ns.RenderGoalPicker(p) p.panel.refreshAll() end
