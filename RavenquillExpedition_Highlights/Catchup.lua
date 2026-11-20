local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L = ns.H, ns.L
local ch = H.channel

local C = {
  PAGE = 20, MAX_PAGES = 5, WINDOW = 600, QUIET = 30, SETTLE = 60,
  ASK_MIN = 20, ASK_JITTER = 20, ASK_RETRY = 10, ASK_TRIES = 60,
  ANSWER_MIN = 5, ANSWER_JITTER = 25,
}
local COUNTERS = { "asked", "heard", "relayed", "accepted", "rejected" }

local IDLE = { state = "idle" }
local round = IDLE
local ask = { state = "idle", pages = 0, polls = 0, added = 0, closesAt = 0, perRelayer = {} }

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

local function Page(since, before)
  local events, out = H:Log(), {}
  for i = #events, 1, -1 do
    local e = events[i]
    if e.t <= since or #out >= C.PAGE then break end
    if (not before or e.t <= before) and Relayable(e) then out[#out + 1] = e end
  end
  return out
end

local function NextRelay(r)
  local list = Page(r.since, r.before)
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
  if r.sent < C.PAGE and H:Settings().share then typ, m = NextRelay(r) end
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

local function Widen(r, since, before)
  r.since = math.min(r.since, since)
  r.before = r.before and before and math.max(r.before, before) or nil
end

local function Offer(since, before)
  if not Page(since, before)[1] then return end
  if round ~= IDLE then return Widen(round, since, before) end
  local r = { state = "waiting", since = since, before = before, seen = {}, sent = 0 }
  round = r
  C_Timer.After(C.ANSWER_MIN + math.random() * C.ANSWER_JITTER, function() GS:Call(Start, r) end)
end

local function NoteOtherRelay(sender, e)
  if round == IDLE then return end
  if e then round.seen[e.id] = true end
  if round.state == "waiting" or sender < (GS:PlayerKey() or "") then round = IDLE end
end

local function OnlinePeer()
  for key, m in GS:EachMember() do
    if m.online and not GS:IsMe(key) and GS:IsPeer(key) then return true end
  end
  return false
end

local function MarkCaughtUp()
  local g = H.db.guilds[ask.gkey]
  if g then g.caughtUp = GS:Now() end
end

local function Finish()
  ask.state = "done"
  MarkCaughtUp()
  if ask.added > 0 and H:Settings().chat then H:Print(L.CAUGHT_UP:format(ask.added)) end
  ask.added = 0
end

local Settle, Poll

local function Expect(page, delay)
  local at = GetTime() + delay
  page.settleAt = at
  C_Timer.After(delay, function() GS:Call(Settle, page, at) end)
end

local function SendPage(peer)
  ask.state, ask.pages, ask.heard, ask.askedAt = "asking", ask.pages + 1, false, GetTime()
  ask.closesAt, ask.perRelayer = ask.askedAt + C.WINDOW, {}
  ask.page = { ids = {}, n = 0, peer = peer }
  Count("asked")
  ch:Send("r", { since = ask.since, before = ask.before })
  Expect(ask.page, C.SETTLE)
end

local function Begin()
  ask.gkey = H:GuildKey()
  local g = H.db.guilds[ask.gkey]
  ask.since, ask.before, ask.pages = g and g.caughtUp or 0, nil, 0
  SendPage(ask.heard or OnlinePeer())
end

local function NextPage(page)
  if page.n < C.PAGE or ask.pages >= C.MAX_PAGES then return Finish() end
  if page.low and ask.before and page.low >= ask.before then return Finish() end
  ask.before = page.low or ask.before
  SendPage(true)
end

local function PollSoon(delay)
  if ask.polling then return end
  ask.polling = true
  C_Timer.After(delay, function() GS:Call(Poll) end)
end

local function AskDelay() return C.ASK_MIN + math.random() * C.ASK_JITTER end

Settle = function(page, at)
  if ask.page ~= page or page.settleAt ~= at or ask.state ~= "asking" then return end
  if page.n > 0 then return NextPage(page) end
  if page.peer then return Finish() end
  ask.state = "waiting"
  if ask.heard then PollSoon(AskDelay()) end
end

local function ReadyToAsk()
  if H:GuildKey() == "-" or not GS:CanSend() then return false end
  return ask.heard or (ask.pages == 0 and GS:RosterComplete() and GS:OnlineCount() > 1)
end

Poll = function()
  ask.polling = false
  if ask.state ~= "waiting" then return end
  if ReadyToAsk() then return Begin() end
  ask.polls = ask.polls + 1
  if ask.heard or (ask.pages == 0 and ask.polls < C.ASK_TRIES) then PollSoon(C.ASK_RETRY) end
end

local function NotePage(e)
  local page = ask.page
  if ask.state ~= "asking" or not e or page.ids[e.id] then return end
  page.ids[e.id] = true
  page.n = page.n + 1
  if e.t > ask.since and (not ask.before or e.t <= ask.before) then page.low = math.min(page.low or e.t, e.t) end
  Expect(page, C.QUIET)
end

local function Admissible(sender, e)
  return e ~= nil and GetTime() < ask.closesAt and (ask.perRelayer[sender] or 0) < C.PAGE
    and GS:IsGuildMember(e.who) == true
end

function H:OnRelay(sender, e)
  NoteOtherRelay(sender, e)
  NotePage(e)
  if not Admissible(sender, e) then return Count("rejected") end
  ask.perRelayer[sender] = (ask.perRelayer[sender] or 0) + 1
  Count("accepted")
  if self:Add(e, "relay") then ask.added = ask.added + 1 end
end

local function NoteAsker()
  if ask.state == "asking" and GetTime() < ask.askedAt + C.ASK_MIN then
    ask.page.peer = true
    return
  end
  ask.heard = true
  if ask.state == "waiting" then PollSoon(AskDelay()) end
end

ch:On("r", function(_, m)
  if not H.db then return end
  Count("heard")
  Offer(m.since, m.before)
  NoteAsker()
end)

function H:OnLoginCatchup()
  for _, g in pairs(self.db.guilds) do
    if type(g.caughtUp) ~= "number" then g.caughtUp = Newest(g.events) end
  end
  ask.state, ask.polls = "waiting", 0
  PollSoon(AskDelay())
end

H:RegisterEvent("PLAYER_LOGOUT", function()
  if H.db and ask.state == "done" then MarkCaughtUp() end
end)

local function WindowText()
  local left = math.floor(ask.closesAt - GetTime())
  if left <= 0 then return "closed" end
  return ("%d s"):format(left)
end

function H:CatchupLine()
  local c, parts = Counts(), {}
  for _, k in ipairs(COUNTERS) do parts[#parts + 1] = ("%s %d"):format(k, c[k] or 0) end
  return ("catch-up: %s · answering %s · own %s, %d pages · window %s"):format(table.concat(parts, ", "), round.state,
    ask.state, ask.pages, WindowText())
end
