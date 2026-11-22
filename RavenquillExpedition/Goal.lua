local ADDON, ns = ...
local GS = ns.GS

local DAY = 86400
local C = { ANSWER_AFTER = 5, ANSWER_SLOT = 3, RETRY = 60, TARGET_MAX = 999, WEEK_MAX = 999999 }
GS.GoalConst = C

GS.GOAL_KINDS = {
  raid = { label = "GOAL_RAID", unit = "GOAL_UNIT_RAID", raid = true },
  runs = { label = "GOAL_RUNS", unit = "GOAL_UNIT_RUNS", min = 1, max = 50, step = 1, default = 10 },
  levels = { label = "GOAL_LEVELS", unit = "GOAL_UNIT_LEVELS", min = 5, max = 200, step = 5, default = 25 },
}
GS.GOAL_KIND_ORDER = { "raid", "runs", "levels" }
GS.GOAL_RAIDS = { "zg", "mc", "ony", "bwl", "aq20", "aq40", "naxx" }
local KINDS, RAID = GS.GOAL_KINDS, {}
for _, r in ipairs(GS.GOAL_RAIDS) do RAID[r] = true end

function GS.Week(t)
  local d = date("*t", t)
  local into = (d.wday + 5) % 7
  local midnight = t - d.hour * 3600 - d.min * 60 - d.sec
  local from = midnight - into * DAY
  return { id = math.floor((midnight + DAY / 2) / DAY) - into, from = from, to = from + 7 * DAY, left = 7 - into }
end

local function ThisWeek() return GS.Week(GS:Now()).id end

local function TargetProblem(kind, g)
  if kind.raid then return (not RAID[g.raid] or g.target ~= nil) and "raid" or nil end
  if g.raid ~= nil or type(g.target) ~= "number" or g.target < kind.min or g.target > kind.max then return "target" end
end

local function Problem(g, week)
  local kind = type(g) == "table" and KINDS[g.kind]
  if not kind then return "kind" end
  if g.week ~= week then return "week" end
  if type(g.setBy) ~= "string" or type(g.version) ~= "number" then return "record" end
  return TargetProblem(kind, g)
end

local function Newer(a, b)
  if not b then return true end
  if a.version ~= b.version then return a.version > b.version end
  return a.setBy > b.setBy
end

local function Store() return ns.GuildTable(GS, "goals") end

local function Keep(g)
  local store = Store()
  if not store or Problem(g, ThisWeek()) or GS:IsOfficer(g.setBy) == false then return false end
  if not Newer(g, store[g.setBy]) then return false end
  store[g.setBy] = g
  return true
end

function GS:Goal()
  local week, best = ThisWeek(), nil
  for by, g in pairs(Store() or {}) do
    if g.week == week and g.setBy == by and self:IsOfficer(by) and Newer(g, best) then best = g end
  end
  return best
end

function GS:OnLoginGoal()
  local store, week = Store(), ThisWeek()
  for by, g in pairs(store or {}) do
    if Problem(g, week) or g.setBy ~= by then store[by] = nil end
  end
end

local channel = ns.ModuleProto.NewChannel({ name = "core" }, { tag = "G" })
channel:Define("g", { fields = { { "kind", "enum", GS.GOAL_KIND_ORDER }, { "target", "int", 1, C.TARGET_MAX, opt = true },
  { "raid", "enum", GS.GOAL_RAIDS, opt = true }, { "by", "key" }, { "week", "int", 1, C.WEEK_MAX }, { "ver", "time" } } })

local function ToMessage(g)
  return { kind = g.kind, target = g.target, raid = g.raid, by = g.setBy, week = g.week, ver = g.version }
end

local function FromMessage(m)
  return { kind = m.kind, target = m.target, raid = m.raid, setBy = m.by, week = m.week, version = m.ver }
end

local onWire, answering = {}, false
local function WireId(g) return g.setBy .. "#" .. g.version end
local function NoteWire(g) onWire[WireId(g)] = GetTime() end

local function SendGoal(g, retry)
  channel:Send("g", ToMessage(g), { onResult = function(status)
    if status ~= "dropped" then return NoteWire(g) end
    if retry then C_Timer.After(C.RETRY, function() GS:Call(retry, g) end) end
  end })
end

local function Publish(g)
  if GS:Goal() == g then SendGoal(g, Publish) end
end

function GS:SetGoal(spec)
  local me = self:PlayerKey()
  if type(spec) ~= "table" or not (me and self:IsOfficer(me)) then return false end
  local mine = (Store() or {})[me]
  local g = { kind = spec.kind, target = spec.target, raid = spec.raid, setBy = me, week = ThisWeek(),
    version = math.max(self:Now(), mine and mine.version + 1 or 0) }
  if not Keep(g) then return false end
  Publish(g)
  self:RefreshOverview()
  return true
end

local function OnlineKeys()
  local out = {}
  for key, e in GS:EachMember() do if e.online then out[#out + 1] = key end end
  return out
end

local function Answer(since)
  answering = false
  local g = GS:Goal()
  if g and (onWire[WireId(g)] or -math.huge) < since then SendGoal(g) end
end

function ns.GoalHello()
  if answering or not GS:Goal() then return end
  answering = true
  local since = GetTime()
  local delay = C.ANSWER_AFTER + GS:ElectionRank(OnlineKeys()) * C.ANSWER_SLOT + math.random()
  C_Timer.After(delay, function() GS:Call(Answer, since) end)
end

channel:On("g", function(_, m)
  local g = FromMessage(m)
  NoteWire(g)
  if Keep(g) then GS:RefreshOverview() end
  local mine = GS:Goal()
  if mine and Newer(mine, g) then ns.GoalHello() end
end)

local function Count(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge end

function GS:GoalProgress(goal)
  for _, name in ipairs(self.moduleOrder) do
    local mod = self.modules[name]
    local current, total
    if mod.GoalProgress then current, total = self:Call(mod.GoalProgress, mod, goal) end
    if Count(current) and Count(total) and total >= 1 then return math.min(math.floor(current), math.floor(total)), math.floor(total) end
  end
end
