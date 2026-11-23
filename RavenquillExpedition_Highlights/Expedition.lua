local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L, News = ns.H, ns.L, ns.News
local T = GS.NewLocale(ns.NewsLocales)
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.RAID_ENCOUNTERS = { zg = { 784, 793 }, mc = { 663, 672 }, ony = { 1084, 1084 }, bwl = { 610, 617 },
  aq20 = { 718, 723 }, aq40 = { 709, 717 }, naxx = { 1107, 1121 } }

local function ThisWeek(self)
  local week, out = GS.Week(GS:Now()), {}
  for _, e in ipairs(self:Log()) do
    if not e.test and e.t >= week.from and e.t < week.to then out[#out + 1] = e end
  end
  return out
end

local function BossesKilled(entries, range)
  local seen, n = {}, 0
  for _, e in ipairs(entries) do
    local enc = e.k == "boss" and e.enc
    if enc and enc >= range[1] and enc <= range[2] and not seen[enc] then seen[enc], n = true, n + 1 end
  end
  return n
end

local PROGRESS = {
  raid = function(_, entries, goal)
    local range = H.RAID_ENCOUNTERS[goal.raid]
    if range then return BossesKilled(entries, range), range[2] - range[1] + 1 end
  end,
  runs = function(self, entries, goal) return News.RunsTogether(entries, self:NewsContext()), goal.target end,
  levels = function(_, entries, goal) return News.LevelsGained(entries), goal.target end,
}

function H:GoalProgress(goal)
  local measure = self.db and PROGRESS[goal.kind]
  if measure then return measure(self, ThisWeek(self), goal) end
end

function H:ShowRaid(raid)
  self:Settings().raidFocus = raid
  GS:ShowModulePage(H.READINESS)
end

local function Column(model, raid)
  for i, a in ipairs(model.raids) do
    if a.raid == raid then return i end
  end
end

local function AtRaidLevel() return (Plain(SafeCall(UnitLevel, "player"), "number") or 0) >= H.RAID_LEVEL end

local function ReadinessLine(model, raid, i)
  local mine = model.mine[i]
  if mine.state ~= "done" and mine.next then return L.NOW_MISSING:format(L[mine.next.label]) end
  local s = H.RaidSummary(model, raid)
  if s.total > 0 then return L.NOW_READY:format(s.done, s.total, L["RAID_" .. raid]) end
end

local function ReadinessRow(self)
  local goal = GS:Goal()
  if not (goal and goal.kind == "raid" and AtRaidLevel()) then return nil end
  local model = self:ReadinessModel()
  local i = Column(model, goal.raid)
  local line = i and ReadinessLine(model, goal.raid, i)
  if not line then return nil end
  return { icon = H.RAID_ICON, title = L.VIEW_RAID, line = line, open = function() self:ShowRaid(goal.raid) end }
end

local function PaperRow(self)
  local lead = self:NewSinceLastLook() > 0 and self:PaperLead()
  if not lead then return nil end
  local section = lead.kicker and lead.kicker ~= "" and T.MASTHEAD .. " · " .. lead.kicker or T.MASTHEAD
  return { icon = H.StoryImage(lead), kicker = section, title = lead.head, open = function() self:ShowWindow() end }
end

function H:OverviewFeed(max)
  if not self.db then return end
  local events, rows = self:Log(), {}
  for i = #events, math.max(1, #events - max + 1), -1 do
    local e = events[i]
    rows[#rows + 1] = { t = e.t, text = self:Format(e), highlight = (self.KINDS[e.k] or {}).gold == true }
  end
  return { title = L.HOME_FEED, rows = rows }
end

function H:OverviewNow()
  if not self.db then return end
  local out = {}
  for _, row in ipairs({ ReadinessRow(self) or false, PaperRow(self) or false }) do
    if row then out[#out + 1] = row end
  end
  return out
end
