local ADDON, ns = ...
local News = ns.News

News.HONOR_MAX, News.DAY = 3, 86400

function News.DayOf(t) return date("%Y-%m-%d", t) end

function News.Sunday(t)
  local d = date("*t", t)
  if d.wday ~= 1 then return nil end
  local noon = t + (12 - d.hour) * 3600 - d.min * 60 - d.sec
  return { from = News.DayOf(noon - 6 * News.DAY), no = math.floor((date("*t", noon - 3 * News.DAY).yday - 1) / 7) + 1 }
end

local function Kills(g)
  if g.kind == "run" then return g.first.n or 1 end
  if g.kind ~= "raid" and g.kind ~= "boss" then return 0 end
  local last, n = {}, 0
  for _, e in ipairs(g.entries) do
    local id = tostring(e.enc or e.boss)
    if not (last[id] and e.t - last[id] <= News.SAME_OUTING) then n = n + 1 end
    last[id] = e.t
  end
  return n
end

local function Epic(g) return g.kind == "epic" and 1 or 0 end

local function Sum(groups, of)
  local n = 0
  for _, g in ipairs(groups) do n = n + of(g) end
  return n
end

local function Spans(entries)
  local spans = {}
  for _, e in ipairs(entries) do
    local s = e.lvl and (spans[e.who] or { lo = e.lvl, hi = e.lvl })
    if s then s.lo, s.hi, spans[e.who] = math.min(s.lo, e.lvl), math.max(s.hi, e.lvl), s end
  end
  return spans
end

local function Gained(spans)
  local n = 0
  for _, s in pairs(spans) do n = n + s.hi - s.lo end
  return n
end

function News.LevelsGained(entries) return Gained(Spans(entries)) end

local TOGETHER = { run = true, group = true }
local function Together(g) return TOGETHER[g.kind] and #g.people >= 2 end

function News.RunsTogether(entries, ctx)
  local n = 0
  for _, g in ipairs(News.Groups(entries, ctx)) do
    if Together(g) then n = n + 1 end
  end
  return n
end

News.WEEK_COUNTS = {
  { key = "levels", count = function(w) return Gained(w.spans) end },
  { key = "bosses", count = function(w) return Sum(w.groups, Kills) end },
  { key = "epics", count = function(w) return Sum(w.groups, Epic) end },
}

local function BestSkill(w, T)
  local out = {}
  for _, e in ipairs(w.entries) do
    local rank, had = e.rank or 0, out[e.who]
    if e.k == "skill" and rank > (had and had.n or 0) then
      out[e.who] = { n = rank, vars = { skill = News.LocalName(e.skill, T.LOCALE), rank = rank } }
    end
  end
  return out
end

local function Climb(w)
  local out = {}
  for who, s in pairs(w.spans) do out[who] = { n = s.hi - s.lo, vars = { from = s.lo, to = s.hi } } end
  return out
end

local function SharedRuns(w)
  local out = {}
  for _, g in ipairs(w.groups) do
    if Together(g) then
      for _, who in ipairs(g.people) do out[who] = { n = (out[who] and out[who].n or 0) + 1 } end
    end
  end
  return out
end

local function EpicName(g, ctx)
  local facts = ctx.item(g.first.item) or {}
  return facts.name and News.ItemName(facts.name, g.first.q or 4)
end

local function Finds(w, _, ctx)
  local out = {}
  for _, g in ipairs(w.groups) do
    local had = g.kind == "epic" and (out[g.first.who] or { n = 0 })
    if had then out[g.first.who] = { n = had.n + 1, vars = { item = had.n == 0 and EpicName(g, ctx) or nil } } end
  end
  return out
end

News.HONORS = {
  { key = "crafter", score = BestSkill },
  { key = "climber", score = Climb },
  { key = "companion", score = SharedRuns },
  { key = "lucky", score = Finds },
}

local function Ahead(who, s, best) return not best or s.n > best.n or (s.n == best.n and who < best.who) end

local function Best(scores, honored)
  local best
  for who, s in pairs(scores) do
    if s.n > 0 and not honored[who] and Ahead(who, s, best) then best = { who = who, n = s.n, vars = s.vars or {} } end
  end
  return best
end

local function Honor(rule, best, T)
  local text, vars = T.HONORS[rule.key], best.vars
  vars.n, vars.one = News.Count(best.n, T), best.n == 1 and "" or nil
  return { key = rule.key, who = best.who, title = text.title, why = News.Fit(text.why, vars) }
end

local function Honors(w, T, ctx)
  local honors, honored = {}, {}
  for _, rule in ipairs(News.HONORS) do
    local best = #honors < News.HONOR_MAX and Best(rule.score(w, T, ctx), honored)
    if best then
      honored[best.who] = true
      honors[#honors + 1] = Honor(rule, best, T)
    end
  end
  return honors
end

function News.Week(entries, T, ctx)
  local w = { entries = entries, groups = News.Groups(entries, ctx), spans = Spans(entries) }
  local counts = {}
  for _, c in ipairs(News.WEEK_COUNTS) do
    local n = c.count(w)
    if n > 0 then counts[#counts + 1] = { key = c.key, n = n, label = News.Counted(T.WEEK_COUNTS[c.key], n, T) } end
  end
  if not counts[1] then return nil end
  return { counts = counts, honors = Honors(w, T, ctx) }
end

local function AllEntries(days)
  local out = {}
  for _, rec in ipairs(days) do
    for _, e in ipairs(rec.entries) do out[#out + 1] = e end
  end
  return out
end

local function WeekOf(days, i)
  local sunday = News.Sunday(days[i].entries[1].t)
  if not sunday then return nil end
  local week = {}
  for j = 1, i do
    if days[j].day >= sunday.from then week[#week + 1] = days[j] end
  end
  return week, sunday.no
end

local function Review(week, no, T, ctx)
  local review = News.Week(AllEntries(week), T, ctx)
  if review then review.no = no end
  return review
end

function News.Edition(days, i, T, ctx)
  if not days[i] then return nil end
  local week, no = WeekOf(days, i)
  local review = week and Review(week, no, T, ctx)
  local issue = News.Issue(days[i], T, ctx, review and week)
  issue.week = review
  return issue
end
