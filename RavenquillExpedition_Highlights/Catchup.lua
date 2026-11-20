local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L = ns.H, ns.L
local ch = H.channel

local C = {
  MAX = 20, WINDOW = 600, QUIET = 30,
  ASK_MIN = 20, ASK_JITTER = 20, ASK_RETRY = 10, ASK_TRIES = 60,
  ANSWER_MIN = 5, ANSWER_JITTER = 25,
}
local COUNTERS = { "asked", "heard", "relayed", "accepted", "rejected" }

local IDLE = { state = "idle" }
local round = IDLE
local listen = { closesAt = 0, perRelayer = {}, caughtUp = 0 }
local sinceAtLogin = {}

local function Counts()
  local d = H.db.diag
  if type(d.catchup) ~= "table" then d.catchup = {} end
  return d.catchup
end

local function Count(key)
  local c = Counts()
  c[key] = (c[key] or 0) + 1
end

local function Relayable(e) return not (e.test or e.act or e.held or H.cdb.outbox[e.id]) end

local function Newest(events)
  for i = #events, 1, -1 do
    if Relayable(events[i]) then return events[i].t end
  end
  return 0
end

local function NewestRelayable(since)
  local events, out = H:Log(), {}
  for i = #events, 1, -1 do
    local e = events[i]
    if e.t <= since or #out >= C.MAX then break end
    if Relayable(e) then out[#out + 1] = e end
  end
  return out
end

local function NextRelay(r)
  local list = NewestRelayable(r.since)
  for i = #list, 1, -1 do
    local e = list[i]
    if not r.seen[e.id] then
      r.seen[e.id] = true
      local typ, m = H.RelayMessage(e)
      if typ then return typ, m end
    end
  end
end

local function Stop(r) if round == r then round = IDLE end end

local function Step(r)
  if round ~= r then return end
  local typ, m
  if r.sent < C.MAX and H:Settings().share then typ, m = NextRelay(r) end
  if not typ then return Stop(r) end
  r.sent = r.sent + 1
  Count("relayed")
  ch:Send(typ, m, { onResult = function(status)
    if status == "dropped" then Stop(r) else Step(r) end
  end })
end

local function Start(r)
  if round ~= r then return end
  r.state = "streaming"
  Step(r)
end

local function Offer(since)
  if Newest(H:Log()) <= since then return end
  if round ~= IDLE then
    round.since = math.min(round.since, since)
    return
  end
  local r = { state = "waiting", since = since, seen = {}, sent = 0 }
  round = r
  C_Timer.After(C.ANSWER_MIN + math.random() * C.ANSWER_JITTER, function() GS:Call(Start, r) end)
end

local function NoteOtherRelay(sender, e)
  if round == IDLE then return end
  if e then round.seen[e.id] = true end
  if round.state == "waiting" or sender < (GS:PlayerKey() or "") then round = IDLE end
end

local function Summarize(at)
  if listen.lastAt ~= at or listen.caughtUp == 0 then return end
  local n = listen.caughtUp
  listen.caughtUp = 0
  if H:Settings().chat then H:Print(L.CAUGHT_UP:format(n)) end
end

local function NoteCaughtUp(added)
  if added then listen.caughtUp = listen.caughtUp + 1 end
  local at = GetTime()
  listen.lastAt = at
  C_Timer.After(C.QUIET, function() GS:Call(Summarize, at) end)
end

local function Admissible(sender, e)
  return e ~= nil and GetTime() < listen.closesAt and (listen.perRelayer[sender] or 0) < C.MAX
    and GS:IsGuildMember(e.who) == true
end

function H:OnRelay(sender, e)
  NoteOtherRelay(sender, e)
  if not Admissible(sender, e) then return Count("rejected") end
  listen.perRelayer[sender] = (listen.perRelayer[sender] or 0) + 1
  Count("accepted")
  NoteCaughtUp(self:Add(e, "relay") ~= nil)
end

ch:On("r", function(_, m)
  if not H.db then return end
  Count("heard")
  Offer(m.since)
end)

local function ReadyToAsk()
  return H:GuildKey() ~= "-" and GS:CanSend() and GS:RosterComplete() and GS:OnlineCount() > 1
end

local function Ask()
  listen.closesAt = GetTime() + C.WINDOW
  Count("asked")
  ch:Send("r", { since = sinceAtLogin[H:GuildKey()] or 0 })
end

local function TryAsk(tries)
  if ReadyToAsk() then return Ask() end
  if tries < C.ASK_TRIES then C_Timer.After(C.ASK_RETRY, function() GS:Call(TryAsk, tries + 1) end) end
end

function H:OnLoginCatchup()
  for gkey, g in pairs(self.db.guilds) do sinceAtLogin[gkey] = Newest(g.events) end
  C_Timer.After(C.ASK_MIN + math.random() * C.ASK_JITTER, function() GS:Call(TryAsk, 0) end)
end

local function WindowText()
  local left = math.floor(listen.closesAt - GetTime())
  if left <= 0 then return "closed" end
  return ("%d s"):format(left)
end

function H:CatchupLine()
  local c, parts = Counts(), {}
  for _, k in ipairs(COUNTERS) do parts[#parts + 1] = ("%s %d"):format(k, c[k] or 0) end
  return ("catch-up: %s · answering %s · window %s"):format(table.concat(parts, ", "), round.state, WindowText())
end
