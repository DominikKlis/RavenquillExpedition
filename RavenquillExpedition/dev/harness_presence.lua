local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local function Released(version)
  return function(env)
    env.C_AddOns.GetAddOnMetadata = function(_, field) if field == "Version" then return version end end
  end
end

local function Presence(c, key) return c.RQ.Presence and c.RQ:Presence(key) end
local function IsHello(e) return e.prefix == "RQE1" and e.msg:find("^V;1;v;") ~= nil end
local function IsReply(e) return e.prefix == "RQE1" and e.msg == "V;1;p" end

local function HelloOf(bus, who)
  for _, e in ipairs(bus.log) do if e.sender == who and IsHello(e) then return e end end
end

local function RepliesSince(bus, who, t0)
  return bus:sentBy(who, function(e) return IsReply(e) and e.t >= t0 end)
end

local function AdvanceUntil(sched, limit, done)
  for _ = 1, limit do
    if done() then return true end
    sched:advance(1)
  end
  return done()
end

local function Count(c, needle)
  local hits = 0
  for _, line in ipairs(c.printed) do if line.text:find(needle, 1, true) then hits = hits + 1 end end
  return hits
end

section("Presence: a login learns who runs Ravenquill from their answers")
local sched, bus = Kit.Setup()
local random = Kit.Random(11)
local bert = Kit.Client(sched, bus, "Bert Hill", { random = random, setup = Released("0.10.1-beta") })
local cora = Kit.Client(sched, bus, "Cora Vale", { random = random })
bus:member("Dora Plain", "HUNTER", 25, true)
bert.login(); cora.login()
sched:advance(1800)
local C = bert.RQ.CommConst
local anna = Kit.Client(sched, bus, "Anna Stone", { random = random, setup = Released("0.10.0-beta") })
local loginAt = sched.t
anna.login()
sched:advance(5)
check(#bus:sentBy("Bert Hill", function(e) return e.t >= loginAt end) == 0 and #bus:sentBy("Cora Vale", function(e) return e.t >= loginAt end) == 0,
  "Bert and Cora logged in 30 min before Anna and have sent nothing since")
check(Presence(anna, "Bert Hill") == "unknown" and Presence(anna, "Dora Plain") == "unknown",
  ("before Anna's own announcement nobody is known: %s, %s"):format(tostring(Presence(anna, "Bert Hill")), tostring(Presence(anna, "Dora Plain"))))
AdvanceUntil(sched, C.VERSION_DELAY + C.VERSION_JITTER + 10, function() return HelloOf(bus, "Anna Stone") ~= nil end)
local hello = HelloOf(bus, "Anna Stone")
sched:advance(2)
check(hello and hello.msg == "V;1;v;0.10.0-beta", "Anna announces her version as before: " .. tostring(hello and hello.msg))
check(Presence(anna, "Bert Hill") == "pending" and Presence(anna, "Dora Plain") == "pending",
  "after the announcement the silent guildmates are pending, not absent")
bert.fire("CHAT_MSG_ADDON", "RQE1", hello.msg, "GUILD", "Anna Stone-Realm")
sched:advance(C.REPLY_JITTER + 10)
local bertSaid, coraSaid = RepliesSince(bus, "Bert Hill", hello.t), RepliesSince(bus, "Cora Vale", hello.t)
check(#bertSaid == 1 and #coraSaid == 1,
  ("Bert and Cora answer once each, the same hello heard twice included (%d, %d)"):format(#bertSaid, #coraSaid))
check(bertSaid[1] and coraSaid[1] and bertSaid[1].t - hello.t <= C.REPLY_JITTER + 5 and coraSaid[1].t - hello.t <= C.REPLY_JITTER + 5
  and bertSaid[1].t ~= coraSaid[1].t,
  ("jittered within %d s of the hello: Bert after %.0f s, Cora after %.0f s"):format(C.REPLY_JITTER,
    bertSaid[1] and bertSaid[1].t - hello.t or -1, coraSaid[1] and coraSaid[1].t - hello.t or -1))
check(Presence(anna, "Bert Hill") == "confirmed" and Presence(anna, "Cora Vale") == "confirmed",
  "Anna now knows both run Ravenquill")
check(#bus:sentBy("Cora Vale", IsHello) == 0, "Cora's dev build answers as presence but never announces a version")
check(Presence(anna, "Dora Plain") == "pending",
  ("Dora (no addon) stays pending inside the %d s window"):format(C.REPLY_WINDOW))
sched:advance(hello.t + C.REPLY_WINDOW + 2 - sched.t)
check(Presence(anna, "Dora Plain") == "absent", "after a full window without an answer, Dora is absent")
check(Count(anna, "newer") == 0 and anna.RQ:PeerVersions()["Bert Hill"] == nil,
  "the answer carries no version: Bert's newer release is not announced to Anna, nothing is stored")
anna.guild = "Neue Gilde"
anna.fire("PLAYER_GUILD_UPDATE")
anna.fire("GUILD_ROSTER_UPDATE")
sched:advance(C.REPLY_WINDOW + 60)
check(Presence(anna, "Dora Plain") == "unknown" and Presence(anna, "Bert Hill") == "unknown",
  "after a guild change nobody is judged by the old guild's announcement: " .. tostring(Presence(anna, "Dora Plain")))
anna.guild = "Testgilde"
anna.fire("PLAYER_GUILD_UPDATE")

section("Presence: answered once per session, a known guildmate who stays silent is not called absent")
sched:advance(3 * 3600)
check(#RepliesSince(bus, "Bert Hill", hello.t) == 1 and #RepliesSince(bus, "Cora Vale", hello.t) == 1,
  "three hours later: still one answer each to Anna's session")
anna.online = false
bus:member("Gerd Quiet", "MAGE", 40, true)
anna.RQ:Peers()["Gerd Quiet"] = anna.RQ:Now() - 86400
local db = anna.env.RavenquillExpeditionDB
local anna2 = Kit.Client(sched, bus, "Anna Stone", { random = random, setup = Released("0.10.0-beta") })
anna2.env.RavenquillExpeditionDB = db
local reloadAt = sched.t
anna2.login()
sched:advance(C.VERSION_DELAY + C.VERSION_JITTER + C.REPLY_JITTER + 20)
check(#RepliesSince(bus, "Bert Hill", reloadAt) == 1 and #RepliesSince(bus, "Cora Vale", reloadAt) == 1
  and Presence(anna2, "Bert Hill") == "confirmed" and Presence(anna2, "Cora Vale") == "confirmed",
  "after Anna's /reload her new session's announcement is answered once more")
sched:advance(C.REPLY_WINDOW)
check(Presence(anna2, "Gerd Quiet") == "pending" and Presence(anna2, "Dora Plain") == "absent",
  "a guildmate heard yesterday who doesn't answer (instance, combat, an older release) stays pending, never absent")
check(#anna.errors + #anna2.errors + #bert.errors + #cora.errors == 0, "no Lua errors (" .. tostring(anna.errors[1] or bert.errors[1]) .. ")")

section("Presence: a guildmate in a dungeon can't answer, so they are not called absent")
local schedI, busI = Kit.Setup()
local randomI = Kit.Random(17)
local ZONES = { [36] = "The Deadmines", [489] = "Warsong Gulch" }
local function WithZones(env)
  Released("0.10.0-beta")(env)
  env.GetRealZoneText = function(map) return ZONES[map] end
end
busI:member("Erik Deep", "WARRIOR", 22, true, "The Deadmines")
busI:member("Wanda Field", "MAGE", 22, true, "Westfall")
local ina = Kit.Client(schedI, busI, "Ina Watch", { random = randomI, setup = WithZones })
ina.login()
AdvanceUntil(schedI, C.VERSION_DELAY + C.VERSION_JITTER + 10, function() return HelloOf(busI, "Ina Watch") ~= nil end)
schedI:advance(C.REPLY_WINDOW + 10)
check(Presence(ina, "Erik Deep") == "pending",
  "Erik is in The Deadmines, where the addon sends nothing: pending, not absent (" .. tostring(Presence(ina, "Erik Deep")) .. ")")
check(Presence(ina, "Wanda Field") == "absent", "Wanda in Westfall stays silent for a full window: absent")
check(#ina.errors == 0, "no Lua errors (" .. tostring(ina.errors[1]) .. ")")

section("Presence: several log in together without an answer storm")
local schedS, busS = Kit.Setup()
local randomS = Kit.Random(23)
local N = 8
local crowd = {}
for i = 1, N do crowd[i] = Kit.Client(schedS, busS, ("Crowd%d Field"):format(i), { random = randomS, setup = Released("0.10.0-beta") }) end
for _, c in ipairs(crowd) do c.login(); schedS:advance(2) end
schedS:advance(3600)
local hellos, replies = busS:count(IsHello), busS:count(IsReply)
check(hellos == N and replies <= 2 * N,
  ("%d log in within %d s: %d announcements, %d answers (at most %d; one answer per hello would be %d)"):format(N, 2 * N, hellos, replies, 2 * N, N * (N - 1)))
local known = 0
for _, a in ipairs(crowd) do for _, b in ipairs(crowd) do if a ~= b and Presence(a, b.name) == "confirmed" then known = known + 1 end end end
check(known == N * (N - 1), ("and every client knows every other runs Ravenquill (%d of %d pairs)"):format(known, N * (N - 1)))
local unprompted = 0
for _, c in ipairs(crowd) do
  local lastOwn = -1
  for _, e in ipairs(busS.log) do
    if e.sender == c.name and (IsHello(e) or IsReply(e)) then
      if IsReply(e) then
        local prompted = false
        for _, h in ipairs(busS.log) do if IsHello(h) and h.sender ~= c.name and h.t > lastOwn and h.t < e.t then prompted = true end end
        if not prompted then unprompted = unprompted + 1 end
      end
      lastOwn = e.t
    end
  end
end
check(unprompted == 0, "every answer follows an announcement the client had not answered yet (" .. unprompted .. " did not)")

section("Presence: what one login costs in a guild of 10 and of 40")
local function LoginCost(n, seed)
  local s, b = Kit.Setup()
  local rnd = Kit.Random(seed)
  for i = 1, n do
    local c = Kit.Client(s, b, ("Guild%02d Member"):format(i), { random = rnd, setup = Released("0.10.0-beta") })
    c.login()
    s:advance(3)
  end
  s:advance(1800)
  local t0 = s.t
  local newcomer = Kit.Client(s, b, "Nina New", { random = rnd, setup = Released("0.10.0-beta") })
  newcomer.login()
  s:advance(600)
  local times, last, sentBy, perSender = {}, 0, {}, 0
  for _, e in ipairs(b.log) do
    if e.t >= t0 and e.prefix == "RQE1" then
      times[#times + 1] = e.t
      sentBy[e.sender] = (sentBy[e.sender] or 0) + 1
      perSender = math.max(perSender, sentBy[e.sender])
    end
    if e.t >= t0 and IsReply(e) then last = math.max(last, e.t) end
  end
  local busiest = 0
  for i = 1, #times do
    local k = 0
    for j = i, #times do if times[j] - times[i] < 60 then k = k + 1 end end
    busiest = math.max(busiest, k)
  end
  local confirmed = 0
  for i = 1, n do if Presence(newcomer, ("Guild%02d Member"):format(i)) == "confirmed" then confirmed = confirmed + 1 end end
  local helloAt = (HelloOf(b, "Nina New") or { t = math.huge }).t
  return { total = #times, busiest = busiest, perSender = perSender, answeredIn = last - helloAt, confirmed = confirmed }
end
local cap = C.BURST + 60 * C.RATE
local ten = LoginCost(10, 31)
check(ten.total == 11 and ten.busiest < C.BUSY_HEARD and ten.confirmed == 10,
  ("guild of 10: one login costs %d messages, at most %d in any 60 s (busy hold at %d: never reached), all %d known %d s after the announcement")
    :format(ten.total, ten.busiest, C.BUSY_HEARD, ten.confirmed, math.floor(ten.answeredIn)))
local forty = LoginCost(40, 37)
check(forty.total == 41 and forty.confirmed == 40 and forty.answeredIn < C.REPLY_WINDOW,
  ("guild of 40: %d messages, up to %d in 60 s; the busy hold (%d heard per 60 s) spreads them, all %d known %d s after the announcement (window %d s)")
    :format(forty.total, forty.busiest, C.BUSY_HEARD, forty.confirmed, math.floor(forty.answeredIn), C.REPLY_WINDOW))
check(ten.perSender == 1 and forty.perSender == 1,
  ("each guildmate sends one message for it, far under its own cap (%d per 60 s) and the intake cap (%d per sender per minute)")
    :format(cap, C.INTAKE_PER_MIN))

Kit.finish()
