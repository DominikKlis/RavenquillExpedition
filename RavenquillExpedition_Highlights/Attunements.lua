local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.RAID_LEVEL = 55

H.ATTUNEMENTS = {
  { raid = "mc", steps = { { quest = 7848, label = "STEP_CORE_FRAGMENT" } } },
  { raid = "ony", faction = "Alliance", steps = { { quest = 4322, label = "STEP_WINDSOR" },
    { quest = 6403, label = "STEP_MASQUERADE" }, { quest = 6502, label = "STEP_AMULET" } } },
  { raid = "ony", faction = "Horde", steps = { { quest = 4974, label = "STEP_REND" },
    { quest = 6601, label = "STEP_SKULLS" }, { quest = 6602, label = "STEP_BLOOD" } } },
  { raid = "bwl", steps = { { quest = 4743, label = "STEP_SEAL" }, { quest = 7761, label = "STEP_ORB" } } },
}

H.RAID_KEYS, H.ATTUNEMENT_QUESTS = {}, {}
local RAID = {}
for _, a in ipairs(H.ATTUNEMENTS) do
  if not RAID[a.raid] then H.RAID_KEYS[#H.RAID_KEYS + 1] = a.raid end
  RAID[a.raid] = true
  for _, step in ipairs(a.steps) do H.ATTUNEMENT_QUESTS[step.quest] = true end
end

function H.RaidsFor(faction)
  local out, seen = {}, {}
  for _, a in ipairs(H.ATTUNEMENTS) do
    local ours = not (a.faction and faction) or a.faction == faction
    if ours and not seen[a.raid] then out[#out + 1] = a end
    seen[a.raid] = seen[a.raid] or ours
  end
  return out
end

local function StepsDone(a, facts)
  local done = 0
  for i, step in ipairs(a.steps) do
    if facts[step.quest] then done = i end
  end
  return done
end

function H.RaidStatus(a, facts)
  local m = #a.steps
  if facts[a.raid] then return { raid = a.raid, state = "done", n = m, m = m, declared = true } end
  local n = StepsDone(a, facts)
  local state = (n == m and "done") or (n == 0 and "none") or "partial"
  return { raid = a.raid, state = state, n = n, m = m, next = a.steps[n + 1] }
end

function H.Readiness(facts, raids)
  local out = {}
  for i, a in ipairs(raids) do out[i] = H.RaidStatus(a, facts or {}) end
  return out
end

local FACT = {
  quest = function(e) return H.ATTUNEMENT_QUESTS[e.qid] and e.qid or nil end,
  attune = function(e) return RAID[e.raid] and e.raid or nil end,
}

local function FactOf(e)
  local of = FACT[e.k]
  return of and of(e)
end

local function Note(facts, e)
  local fact = FactOf(e)
  if not fact then return end
  local own = facts[e.who] or {}
  facts[e.who] = own
  own[fact] = own[fact] or e.t
end

function H:KeepAttunement(gkey, e)
  if e.test or not FactOf(e) then return end
  local g = self.db.guilds[gkey]
  if type(g.attuned) ~= "table" then g.attuned = {} end
  Note(g.attuned, e)
end

local function CopyKept(kept)
  local out = {}
  for who, facts in pairs(type(kept) == "table" and kept or {}) do
    if type(facts) == "table" then
      out[who] = {}
      for fact, t in pairs(facts) do out[who][fact] = t end
    end
  end
  return out
end

function H:AttunementFacts()
  local events = self:Log()
  local facts = CopyKept(self.db.guilds[self:GuildKey()].attuned)
  for _, e in ipairs(events) do Note(facts, e) end
  return facts
end

function H.MyFaction() return Plain(SafeCall(UnitFactionGroup, "player"), "string") end

function H:MyRaidStatus(raid)
  local mine = self:AttunementFacts()[GS:PlayerKey() or ""] or {}
  for _, a in ipairs(H.RaidsFor(H.MyFaction())) do
    if a.raid == raid then return H.RaidStatus(a, mine) end
  end
end

function H:DeclareAttuned(raid)
  local status = self.db and self:MyRaidStatus(raid)
  if not status or status.state == "done" then return end
  return self:Add(ns.Own("attune", { raid = raid }), "self")
end

local function Listing(key, member, facts)
  if (member.level or 0) < H.RAID_LEVEL then return "low" end
  if not (facts[key] or GS:IsPeer(key)) then return "away" end
  return "rows"
end

local function Score(raids)
  local s = 0
  for _, st in ipairs(raids) do s = s + st.n / st.m end
  return s
end

local function Ahead(a, b)
  if a.score ~= b.score then return a.score > b.score end
  if a.level ~= b.level then return a.level > b.level end
  return a.who < b.who
end

function H:ReadinessModel()
  local raids, facts = H.RaidsFor(H.MyFaction()), self:AttunementFacts()
  local model = { raids = raids, rows = {}, low = 0, away = 0, mine = H.Readiness(facts[GS:PlayerKey() or ""], raids) }
  for key, member in GS:EachMember() do
    local list = Listing(key, member, facts)
    if list == "rows" then
      local status = H.Readiness(facts[key], raids)
      model.rows[#model.rows + 1] = { who = key, class = member.class, level = member.level, raids = status, score = Score(status) }
    else
      model[list] = model[list] + 1
    end
  end
  table.sort(model.rows, Ahead)
  return model
end

local function Column(model, raid)
  for i, a in ipairs(model.raids) do
    if a.raid == raid then return i end
  end
  return 1
end

local function MissingFirst(a, b)
  if a.n ~= b.n then return a.n > b.n end
  return a.i < b.i
end

function H.RaidSummary(model, raid)
  local col = Column(model, raid)
  local s = { raid = model.raids[col].raid, done = 0, almost = 0, total = #model.rows, missing = {} }
  for i, row in ipairs(model.rows) do
    local st = row.raids[col]
    if st.state == "done" then s.done = s.done + 1 end
    if st.state == "partial" then s.almost = s.almost + 1 end
    if st.state ~= "done" then
      s.missing[#s.missing + 1] = { who = row.who, class = row.class, step = st.next, n = st.n, i = i }
    end
  end
  table.sort(s.missing, MissingFirst)
  return s
end
