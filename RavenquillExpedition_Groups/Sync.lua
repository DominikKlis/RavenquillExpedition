local ADDON, ns = ...
local GS = RavenquillExpedition
local G, P = ns.G, ns.Posts

local Sync = {}
ns.Sync = Sync

Sync.C = {
  ASK_AFTER = 20, ASK_JITTER = 20, ASK_QUIET = 120,
  OWN_ANSWER = 2, ANSWER_AFTER = 5, ANSWER_SLOT = 3, FRESH = 60,
  TICK = 30, NOTE_MAX = 60, ROLE_MAX = 40, TIME_MAX = 4102444800,
}
local C = Sync.C

local S = { onWire = {}, rejected = {}, busy = false, answering = false, ask = "done", askAt = 0 }
Sync.state = S

local ch = G:NewChannel({ tag = "GF", version = 1 })
Sync.channel = ch

local function Count(name) return { name, "int", 0, C.ROLE_MAX } end
local ROLE_CODES = {}
for i, r in ipairs(P.ROLES) do ROLE_CODES[i] = r.code end
local CODE_OF = {}
for _, r in ipairs(P.ROLES) do CODE_OF[r.key] = r.code end

ch:Define("p", { from = "guild", fields = {
  { "poster", "key" }, { "id", "time" }, { "t", "time" }, { "act", "word", 8 }, { "when", "int", 1, C.TIME_MAX, opt = true },
  Count("tn"), Count("th"), Count("hn"), Count("hh"), Count("dn"), Count("dh"), { "note", "text", C.NOTE_MAX } } })
ch:Define("s", { from = "guild", fields = { { "poster", "key" }, { "id", "time" }, { "role", "enum", ROLE_CODES },
  { "again", "flag" } } })
ch:Define("x", { from = "self", fields = { { "id", "time" } } })
ch:Define("q", { from = "self", fields = {} })

function Sync.ToMessage(p)
  local m = { poster = p.poster, id = p.id, t = p.t, act = p.activity, when = p.when, note = p.note or "" }
  for _, r in ipairs(P.ROLES) do
    m[r.code .. "n"], m[r.code .. "h"] = p.roles[r.key].need, p.roles[r.key].have
  end
  return m
end

local function RolesOf(m)
  local roles, total = {}, 0
  for _, r in ipairs(P.ROLES) do
    local need, have = m[r.code .. "n"], m[r.code .. "h"]
    if have > need then return nil end
    roles[r.key] = { need = need, have = have }
    total = total + need
  end
  if total > 0 then return roles end
end

local function Problem(m, now)
  if not ns.Activities.Get(m.act) then return "activity" end
  if m.t < m.id then return "version" end
  if m.when and m.when > now + P.PLAN_AHEAD then return "too far ahead" end
  if GS:IsGuildMember(m.poster) == false then return "not in guild" end
end

function Sync.FromMessage(m, now)
  local why = Problem(m, now)
  if why then return nil, why end
  local roles = RolesOf(m)
  if not roles then return nil, "roles" end
  local p = P.New({ id = m.id, t = m.t, poster = m.poster, activity = m.act, when = m.when, note = m.note, roles = roles })
  if p.expires <= now then return nil, "expired" end
  return p
end

local function Reject(why) S.rejected[why] = (S.rejected[why] or 0) + 1 end

local function MarkOnWire(p)
  S.onWire[p.poster] = { id = p.id, t = p.t, have = (P.Filled(p)), at = GetTime() }
end

local function Fresh(p)
  local w = S.onWire[p.poster]
  return w ~= nil and w.id == p.id and w.t == p.t and w.have >= P.Filled(p) and GetTime() - w.at < C.FRESH
end

local function Due(p) return p.expires > GS:Now() and not Fresh(p) end

local function SendEach(list, i)
  while list[i] and not Due(list[i]) do i = i + 1 end
  local p = list[i]
  if not p then return end
  ch:Send("p", Sync.ToMessage(p), { onResult = function(status)
    if status == "dropped" then return end
    MarkOnWire(p)
    SendEach(list, i + 1)
  end })
end

local function OnlineMembers()
  local out = {}
  for key, e in GS:EachMember() do if e.online then out[#out + 1] = key end end
  return out
end

local function RelayDelay()
  return C.ANSWER_AFTER + GS:ElectionRank(OnlineMembers()) * C.ANSWER_SLOT + math.random()
end

function Sync.Answer()
  if S.answering then return end
  S.answering = true
  if G:OwnPost() then G:After(C.OWN_ANSWER * math.random(), function() SendEach({ G:OwnPost() }, 1) end) end
  G:After(RelayDelay(), function()
    S.answering = false
    SendEach(G:OthersPosts(), 1)
  end)
end

local function AloneOnline()
  return (GS:RosterComplete()) and GS:OnlineCount() <= 1
end

local function AskHeardLately() return S.heardAsk ~= nil and GetTime() - S.heardAsk < C.ASK_QUIET end

function Sync.TryAsk()
  if S.ask ~= "due" or GetTime() < S.askAt or not G.db then return end
  if AskHeardLately() or AloneOnline() then S.ask = "done" return end
  S.ask = "sending"
  ch:Send("q", {}, { onResult = function(status)
    if status == "dropped" then S.ask = "due" return end
    S.ask = "done"
    Sync.Answer()
  end })
end

local function CloseJob(out)
  local id = out.close
  return "x", { id = id }, function() if out.close == id then out.close = nil end end
end

local function PostJob(out, p)
  return "p", Sync.ToMessage(p), function()
    if out.post == p.t then out.post = nil end
    MarkOnWire(p)
  end
end

local function SignupJob(poster, m)
  return "s", { poster = poster, id = m.id, role = CODE_OF[m.role], again = m.again or false }, function()
    local online, first = G:PosterOnline(poster), not m.again
    m.pending, m.again, m.undelivered = nil, nil, (first and not online) or nil
    local p = G:GuildStore("posts")[poster]
    if online and first and p then G:Whisper(p, m.role) end
  end
end

local function NextJob()
  local out = G:GuildStore("outbox")
  if out.close then return CloseJob(out) end
  local own = G:GuildStore("posts")[GS:PlayerKey()]
  if out.post and own and own.t == out.post then return PostJob(out, own) end
  out.post = nil
  for poster, m in pairs(G:GuildStore("mine")) do
    if m.pending then return SignupJob(poster, m) end
  end
end

function Sync.Flush()
  if S.busy or not G.db then return end
  local typ, msg, done = NextJob()
  if not typ then return end
  S.busy = true
  ch:Send(typ, msg, { onResult = function(status)
    S.busy = false
    if status == "dropped" then return end
    done()
    Sync.Flush()
  end })
end

ch:On("p", function(sender, m)
  local p, why = Sync.FromMessage(m, GS:Now())
  if not p then return Reject(why) end
  MarkOnWire(p)
  G:Receive(p)
  G:HeardFrom(sender)
end)

ch:On("s", function(sender, m)
  G:ReceiveSignup(sender, m.poster, m.id, P.ROLE_BY_CODE[m.role], m.again)
  G:HeardFrom(sender)
end)

ch:On("x", function(sender, m) G:ReceiveClose(sender, m.id) end)

ch:On("q", function(sender)
  S.heardAsk = GetTime()
  G:HeardFrom(sender)
  Sync.Answer()
end)

local function Tick()
  G:Prune(GS:Now())
  Sync.Flush()
  Sync.TryAsk()
  G:Refresh()
end

local function AskLater()
  S.ask, S.askAt = "due", GetTime() + C.ASK_AFTER + C.ASK_JITTER * math.random()
  G:After(S.askAt - GetTime(), Sync.TryAsk)
end

function G:OnLogin()
  AskLater()
  self:Every(C.TICK, Tick)
  Sync.Flush()
end

function G:OnGuildChanged()
  S.onWire, S.busy, S.answering = {}, false, false
  AskLater()
end

function G:OverviewDiagnostics()
  local st, rej = ch:Status(), {}
  for k, v in pairs(S.rejected) do rej[#rej + 1] = k .. "=" .. v end
  table.sort(rej)
  return {
    ("posts: %d active, own %s"):format(#self:ActivePosts(), self:OwnPost() and "yes" or "no"),
    ("channel GF: sent %d, received %d; ask %s"):format(st.sent, st.received, S.ask),
    "rejected: " .. (rej[1] and table.concat(rej, ", ") or "none"),
  }
end

G:RegisterEvent("PLAYER_ENTERING_WORLD", function() Sync.Flush() Sync.TryAsk() end)
G:RegisterEvent("PLAYER_REGEN_ENABLED", function() Sync.Flush() Sync.TryAsk() end)
