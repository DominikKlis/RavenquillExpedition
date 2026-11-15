-- Offline sync harness: many virtual clients (each with the real core) on one simulated GUILD channel and clock.
-- Run: lua "<addon>/dev/harness_sync.lua"   (exit code 1 on failure)
local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness_sync%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end
package.path = DIR .. "/dev/?.lua;" .. package.path
local Mock = require("mock")
math.randomseed(1)

local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. what) end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local EPS = 2 / 46655

local function Setup()
  local sched = Mock.Scheduler()
  local bus = Mock.Bus(sched)
  return sched, bus
end

local function Client(sched, bus, name, opts)
  opts = opts or {}
  bus:member(name, opts.class or "SHAMAN", opts.level or 33)
  return Mock.NewWorld({ sched = sched, bus = bus, name = name, class = opts.class, level = opts.level,
    pos = opts.pos, dir = DIR })
end

-- random walk while w.moving is true
local function Walk(sched, w, step)
  step = step or 0.002
  sched:at(sched.t + 2, function()
    if w.moving and w.pos then
      local p = w.pos
      local nx, ny = p[2] + (math.random() - 0.5) * 2 * step, p[3] + (math.random() - 0.5) * 2 * step
      if nx < 0.1 or nx > 0.9 then nx = p[2] end
      if ny < 0.1 or ny > 0.9 then ny = p[3] end
      w.pos = { p[1], nx, ny }
    end
  end, 2)
end

local function MapSends(bus, sender, t0, t1, kind) return bus:count(t0, t1, sender, kind) end

local function MaxPer60(bus, sender, t0, t1)
  local times = {}
  for _, e in ipairs(bus.log) do
    if e.prefix == "RQEMap1" and e.t >= t0 and e.t < t1 and (not sender or e.sender == sender) then times[#times + 1] = e.t end
  end
  local best = 0
  for i = 1, #times do
    local n = 0
    for j = i, #times do if times[j] - times[i] < 60 then n = n + 1 end end
    best = math.max(best, n)
  end
  return best
end

local function LastMsg(bus, sender, kind)
  for i = #bus.log, 1, -1 do
    local e = bus.log[i]
    if e.prefix == "RQEMap1" and e.sender == sender and (not kind or e.msg:sub(1, 1) == kind) then return e end
  end
end

local function Inject(w, sender, msg) w.fire("CHAT_MSG_ADDON", "RQEMap1", msg, "GUILD", sender) end

local function NoErrors(worlds, what)
  local all = {}
  for _, w in ipairs(worlds) do
    for _, e in ipairs(w.errors) do all[#all + 1] = w.name .. ": " .. tostring(e) end
    local db = w.env.RavenquillExpeditionDB
    if db and db.lastError then all[#all + 1] = w.name .. ": " .. tostring(db.lastError.msg) end
  end
  check(#all == 0, what .. " (" .. tostring(all[1]) .. ")")
end

---------------------------------------------------------------------------
-- 1. Two clients: first send, notice, echo, positions, pacing
---------------------------------------------------------------------------
do
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha", { pos = { 1429, 0.40, 0.40 }, class = "MAGE", level = 42 })
  local B = Client(sched, bus, "Bert Beta", { pos = { 1429, 0.60, 0.60 } })
  A.login(); B.login()
  A.moving = true; Walk(sched, A)
  sched:advance(25)
  check(bus:count(0, 25) == 0, "nothing sent before the 30-90 s jitter")
  sched:advance(75) -- t = 100
  local firstA = nil
  for _, e in ipairs(bus.log) do if e.sender == "Anna Alpha" and e.prefix == "RQEMap1" then firstA = e.t; break end end
  check(firstA and firstA >= 30 and firstA <= 92, "A's first send within 30-90 s with 2 online (" .. tostring(firstA) .. ")")
  local notice = A.printedMatch("shares your position")
  check(notice and firstA and notice.t < firstA, "privacy notice before the first send")
  local mA = B.M.members["Anna Alpha"]
  check(mA and mA.class == "MAGE" and mA.level == 42 and mA.mapID == 1429, "B shows A with class, level, map")
  check(mA and math.abs(mA.x - A.M.sync.last.x) <= EPS and math.abs(mA.y - A.M.sync.last.y) <= EPS,
    "position survives encoding (sub-yard)")
  check(A.M.members["Bert Beta"] ~= nil, "A shows B")
  check(A.M.sync.echoed >= 1 and not A.RQ:CommState().slow and A.RQ:CommState().delivered >= 1, "A's echo seen, not slow")
  check(count(B.hbdWorld) == 1, "B has one world pin")

  sched:advance(600) -- t = 700, A moving all the time
  local MC, CC = A.M.C, A.RQ.CommConst
  -- two senders: the guild-wide interval is the floor, max(INTERVAL_MIN, 2 x 60 / GUILD_TARGET) = 5 s
  check(A.M:Interval(true) == MC.INTERVAL_MIN, ("2 active senders: interval = the %d s floor (%s)"):format(MC.INTERVAL_MIN, A.M:Interval(true)))
  local per60 = MaxPer60(bus, "Anna Alpha", 0, 700)
  check(per60 <= 60 / MC.INTERVAL_MIN and per60 <= CC.BURST + 60 * CC.RATE,
    ("A: at most %d map messages in any 60 s (%d)"):format(60 / MC.INTERVAL_MIN, per60))
  local prev, minGap = nil, math.huge
  for _, e in ipairs(bus.log) do
    if e.sender == "Anna Alpha" and e.prefix == "RQEMap1" then
      if prev then minGap = math.min(minGap, e.t - prev) end
      prev = e.t
    end
  end
  check(minGap >= MC.INTERVAL_MIN, ("A's sends at least %d s apart (min gap %s)"):format(MC.INTERVAL_MIN, tostring(minGap)))
  local walked = MapSends(bus, "Anna Alpha", 100, 700)
  check(walked >= 600 / 30, ("moving A (random walk) keeps updating, far more often than the old 30 s (%d in 600 s)"):format(walked))
  -- a lone walker going straight: about every 5 s (the 2 s tick rounds the gap up to 6 s)
  A.moving = false
  local tw = sched.t
  local straight = sched:at(sched.t + 2, function() A.pos = { A.pos[1], A.pos[2] + 0.002, A.pos[3] } end, 2)
  sched:advance(120)
  straight:Cancel()
  local n120 = MapSends(bus, "Anna Alpha", tw + 1, sched.t + 1)
  check(n120 >= 120 / (MC.INTERVAL_MIN + MC.TICK) - 1 and n120 <= 120 / MC.INTERVAL_MIN + 1,
    ("a lone walker sends about every %d s: %d in 120 s (mean gap %.1f s)"):format(MC.INTERVAL_MIN, n120, 120 / math.max(1, n120)))
  A.pos = { A.pos[1], 0.40, 0.40 }
  A.moving = true
  check(MapSends(bus, "Bert Beta", 200, 700) <= 2, "standing B only heartbeats (<= 2 in 500 s)")
  local lb = LastMsg(bus, "Bert Beta", "P")
  check(lb and lb.msg:match(";s;"), "standing B's message carries the stationary flag")
  check(B.M:State(B.M.members["Anna Alpha"]) == "fresh" and A.M:State(A.M.members["Bert Beta"]) == "fresh",
    "both pins fresh")
  check(A.M.members["Bert Beta"].flags.s, "A sees B as stationary")
  check(A.M:ActiveSenders() == 2, "active senders = 2")

  -- taxi: one message at take-off, none during, one at landing
  local t0 = sched.t
  A.taxi = true
  sched:advance(40)
  local takeoff = LastMsg(bus, "Anna Alpha", "P")
  check(takeoff and takeoff.t > t0 and takeoff.msg:match(";t;"), "taxi take-off sent with flag t")
  local t1 = sched.t
  sched:advance(200)
  check(MapSends(bus, "Anna Alpha", t1, sched.t) == 0, "nothing sent while on the taxi (heartbeat > 200 s)")
  check(B.M.members["Anna Alpha"].flags.t, "B sees A on a taxi")
  A.taxi = false
  local t2 = sched.t
  sched:advance(6)
  check(MapSends(bus, "Anna Alpha", t2, sched.t) == 1, "landing sent")

  -- combat
  A.combat = true
  local t3 = sched.t
  sched:advance(120)
  check(MapSends(bus, "Anna Alpha", t3, sched.t) == 0 and A.M.sync.skip == "combat", "nothing in combat")
  A.combat = false
  sched:advance(4)
  check(MapSends(bus, "Anna Alpha", sched.t - 4, sched.t) == 1, "sent right after combat")

  -- instance: no sending, no reading; echo wait cleared
  A.instance = true
  A.fire("PLAYER_ENTERING_WORLD")
  local recv = A.M.sync.received
  local t4 = sched.t
  sched:advance(120)
  check(MapSends(bus, "Anna Alpha", t4, sched.t) == 0, "nothing sent in an instance")
  check(A.M.sync.received == recv, "nothing read in an instance")
  check(not A.RQ:CommState().slow, "an instance trip doesn't count as lost echoes (no slow mode)")
  A.instance = false
  A.fire("PLAYER_ENTERING_WORLD")
  sched:advance(4)
  check(MapSends(bus, "Anna Alpha", sched.t - 4, sched.t) == 1, "sends again after the instance")

  -- share off -> L, receiver drops the pin at once
  sched:advance(2)
  A.set("share", false)
  local leave = LastMsg(bus, "Anna Alpha", "L")
  check(leave and sched.t - leave.t < 1, "share off sends L")
  sched:advance(2)
  check(B.M.members["Anna Alpha"] == nil and count(B.hbdWorld) == 0, "B drops A's pin on L")
  local t5 = sched.t
  sched:advance(200)
  check(MapSends(bus, "Anna Alpha", t5, sched.t, "P") == 0, "no P while sharing is off")
  A.set("share", true)
  sched:advance(4)
  check(MapSends(bus, "Anna Alpha", sched.t - 4, sched.t, "P") == 1, "share on: sends again soon")
  sched:advance(2)
  check(B.M.members["Anna Alpha"] ~= nil, "B shows A again")
  NoErrors({ A, B }, "two clients: no Lua errors")
end

---------------------------------------------------------------------------
-- 2. Lowest priority: yield to other addons' GUILD messages; starvation guard
---------------------------------------------------------------------------
do
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha")
  local B = Client(sched, bus, "Bert Beta")
  A.login(); B.login()
  A.moving = true; Walk(sched, A)
  sched:advance(120)
  check(A.RQ:CommState().hooked, "the core's hook on SendAddonMessage is installed (other addons' sends count)")
  local MC, CC = A.M.C, A.RQ.CommConst
  -- from here A walks steadily back and forth (wants to send on every tick), so the guard's own pace is what we see
  A.moving = false
  local dir = 1
  sched:at(sched.t + 1, function()
    local x = A.pos[2] + dir * 0.002
    if x > 0.8 or x < 0.2 then dir = -dir; x = A.pos[2] + dir * 0.002 end
    A.pos = { A.pos[1], x, A.pos[3] }
  end, 2)
  -- another addon on A sends more often than the core's quiet time (every 3 s < STATE_QUIET 4 s)
  local other = true
  local every = CC.STATE_QUIET - 1
  sched:at(sched.t + 1, function() if other then A.env.C_ChatInfo.SendAddonMessage("OtherX", "hi", "GUILD") end end, every)
  local t0 = sched.t + 1
  sched:advance(MC.STARVE - 2)
  check(MapSends(bus, "Anna Alpha", t0, sched.t) == 0, ("map yields while another addon sends every %d s"):format(every))
  check(A.M.sync.skip and A.M.sync.skip:find("another addon"), "skip reason names the other addon (" .. tostring(A.M.sync.skip) .. ")")
  sched:advance(600 - (MC.STARVE - 2)) -- starvation guard: one message per >= STARVE s gets through anyway (code review #2)
  local starved = MapSends(bus, "Anna Alpha", t0, sched.t)
  local sgap, sprev = math.huge, nil
  for _, e in ipairs(bus.log) do
    if e.sender == "Anna Alpha" and e.prefix == "RQEMap1" and e.t >= t0 then
      if sprev then sgap = math.min(sgap, e.t - sprev) end
      sprev = e.t
    end
  end
  check(starved >= 600 / (2 * MC.STARVE) and starved <= 600 / MC.STARVE + 1 and sgap >= MC.STARVE,
    ("starvation guard: 1 per >= %d s despite a %d s neighbour (%d in 600 s, closest %s s)"):format(MC.STARVE, every, starved, tostring(sgap)))
  other = false
  -- a neighbour at 7 s: passes the 4 s rule, trips the 10-in-60 s rule sometimes; the guard lets map through
  local every2 = 60 / CC.STATE_MAX_60 + 1
  sched:at(sched.t + 1, function() A.env.C_ChatInfo.SendAddonMessage("OtherY", "hi", "GUILD") end, every2)
  local t1 = sched.t
  sched:advance(400)
  local n = MapSends(bus, "Anna Alpha", t1, sched.t)
  check(n >= 400 / (2 * MC.STARVE), ("map still gets through (at least one per 2 x STARVE) with a %d s neighbour (%d in 400 s)"):format(every2, n))
  -- all GUILD messages of this client (map + other) in any 60 s window
  local times = {}
  for _, e in ipairs(bus.log) do if e.sender == "Anna Alpha" and e.t >= t1 then times[#times + 1] = e.t end end
  local worst = 0
  for i = 1, #times do
    local k = 0
    for j = i, #times do if times[j] - times[i] < 60 then k = k + 1 end end
    worst = math.max(worst, k)
  end
  local own = MaxPer60(bus, "Anna Alpha", t1, sched.t)
  check(worst <= CC.BURST + 60 * CC.RATE, ("client total (neighbour + map) stays <= %d per 60 s with a %d s neighbour (%d, map %d)"):format(
    CC.BURST + 60 * CC.RATE, every2, worst, own))
  NoErrors({ A, B }, "priority: no Lua errors")
end

---------------------------------------------------------------------------
-- 3. Echo loss -> slow mode -> recovery
---------------------------------------------------------------------------
do
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha")
  local B = Client(sched, bus, "Bert Beta")
  A.login(); B.login()
  A.moving = true; Walk(sched, A)
  local dropping = true
  bus.drop = function(sender) return dropping and sender == "Anna Alpha" end
  sched:advance(300)
  check(A.RQ:CommState().lost >= 1 and A.RQ:CommState().slow, "no echo -> lost and slow (the core's watchdog)")
  check(A.printedMatch("don't come back"), "slow mode is announced")
  local said = 0
  for _, l in ipairs(A.printed) do if l.text:find("come back", 1, true) then said = said + 1 end end
  check(said == 1, "slow mode is announced once, by the core only (" .. said .. ")")
  local t0 = sched.t
  sched:advance(600)
  check(MapSends(bus, "Anna Alpha", t0, sched.t) <= 3, "slow: about one probe per 5 min")
  dropping = false
  sched:advance(320)
  check(not A.RQ:CommState().slow and A.M.sync.echoed >= 1, "echo back -> normal again")
  check(B.M.members["Anna Alpha"] ~= nil, "B gets A after recovery")
  local t1 = sched.t
  sched:advance(300)
  check(MapSends(bus, "Anna Alpha", t1, sched.t) >= 6, "normal rate again after recovery")
end

---------------------------------------------------------------------------
-- 4. Receiving: validation, roster gate, offline, order, intake, realm echo, guild change
---------------------------------------------------------------------------
do
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha")
  bus:member("Bert Beta", "MAGE", 40)
  A.login()
  sched:advance(5)
  A.fire("GUILD_ROSTER_UPDATE") -- roster known
  local M = A.M
  local RQ = A.RQ
  local b36 = RQ.Wire.b36
  local now = RQ:Now()
  local function P(map, x, y, lvl, cls, ts, flags, n)
    return table.concat({ "P", b36(map), b36(x), b36(y), b36(lvl), b36(cls), b36(ts), flags, b36(n) }, ";")
  end
  local bad = {
    { P(1429, 100, 100, 40, 7, now, "", 2) .. ";x", "field count" },
    { P(999999, 100, 100, 40, 7, now, "", 2), "unknown map" },
    { P(1429, 46656, 100, 40, 7, now, "", 2), "position range" },
    { P(1429, 0, 0, 40, 7, now, "", 2), "position range" },
    { P(1429, 100, 100, 0, 7, now, "", 2), "level" },
    { P(1429, 100, 100, 40, 10, now, "", 2), "class" },
    { P(1429, 100, 100, 40, 7, now + 1000, "", 2), "future timestamp" },
    { P(1429, 100, 100, 40, 7, now, "x", 2), "flags" },
    { "P;1a;ZZ;1;1;1;1;;1", "not a number" },
    { P(1429, 100, 100, 40, 7, now, "", 0), "sender estimate" },
  }
  for _, b in ipairs(bad) do
    sched:advance(11) -- stay under the intake limit
    Inject(A, "Bert Beta", b[1])
    check(M.sync.rejected[b[2]] and M.members["Bert Beta"] == nil, "rejected: " .. b[2])
  end
  check(count(A.hbdWorld) == 0, "no pin from bad messages")
  sched:advance(61)
  Inject(A, "Bert Beta", P(1429, 23000, 23000, 40, 7, RQ:Now(), "g", 3))
  local mB = M.members["Bert Beta"]
  check(mB and mB.class == "MAGE" and mB.flags.g and math.abs(mB.x - 23000 / 46655) < 1e-9, "valid message stored")
  check(M:ActiveSenders() == 2, "sender estimate n=3 capped at the 2 online (code review #4)")
  Inject(A, "Bert Beta", P(1429, 100, 100, 40, 7, RQ:Now() - 50, "", 3))
  check(M.sync.rejected["older than shown"] and M.members["Bert Beta"].x > 0.4, "older message ignored")

  -- unknown sender: held, appears once the roster has them; another never does
  Inject(A, "Zed Zulu", P(1429, 300, 300, 20, 1, RQ:Now(), "", 2))
  Inject(A, "Yan Yeti", P(1429, 400, 400, 20, 1, RQ:Now(), "", 2))
  check(M.members["Zed Zulu"] == nil and M.sync.pending["Zed Zulu"], "unknown sender held, not shown")
  bus:member("Zed Zulu", "WARRIOR", 20)
  sched:advance(4)
  check(M.members["Zed Zulu"] ~= nil, "held sender shown after the roster update")
  sched:advance(62)
  check(M.members["Yan Yeti"] == nil and M.sync.pending["Yan Yeti"] == nil and M.sync.rejected["not in guild roster"],
    "never-member dropped after 60 s")

  -- offline in roster -> pin removed
  bus:setOnline("Zed Zulu", false)
  A.fire("GUILD_ROSTER_UPDATE")
  sched:advance(2)
  check(M.members["Zed Zulu"] == nil, "offline member's pin removed")

  -- intake limit
  local lim = RQ.CommConst.INTAKE_STATE_PER_MIN
  local before = M.raw:Status().rejected.intake or 0
  for i = 1, lim + 4 do Inject(A, "Bert Beta", P(1429, 23000 + i, 23000, 40, 7, RQ:Now(), "", 3)) end
  local over = (M.raw:Status().rejected.intake or 0) - before
  check(over >= 4 and over <= lim, ("intake limit per sender (the core's state-lane limit of %d per minute): %d not read"):format(lim, over))

  -- our own message with a realm suffix is an echo, not a member
  Inject(A, "Anna Alpha-Realm", P(1429, 100, 100, 33, 6, RQ:Now(), "", 2))
  check(M.members["Anna Alpha-Realm"] == nil and M.members["Anna Alpha"] == nil, "own '-Realm' echo not shown")

  -- L from B
  sched:advance(61)
  Inject(A, "Bert Beta", "L;" .. b36(RQ:Now()))
  check(M.members["Bert Beta"] == nil, "L removes the pin")

  -- guild change wipes
  sched:advance(61)
  Inject(A, "Bert Beta", P(1429, 500, 500, 40, 7, RQ:Now(), "", 2))
  A.set("fake", true)
  check(M.members["Bert Beta"] ~= nil, "B back")
  A.guild = "Andere Gilde"
  A.fire("PLAYER_GUILD_UPDATE")
  check(M.members["Bert Beta"] == nil and M.members["~fake1"] ~= nil, "guild change wipes remote pins, keeps test pins")
  local d = A.diag()
  check(d:find("Sync: prefix RQEMap1 registered", 1, true) and d:find("Rejected:", 1, true), "diagnostics show sync state")
  check(not (RavenquillExpeditionMapDB and RavenquillExpeditionMapDB.members), "positions are never saved")
  local saved = A.env.RavenquillExpeditionMapDB
  local keys = {}
  for k in pairs(saved) do keys[#keys + 1] = k end
  table.sort(keys)
  check(table.concat(keys, ",") == "noticeShown,settings,v", "SavedVariables hold only settings/notice (" .. table.concat(keys, ",") .. ")")
  NoErrors({ A }, "receive: no Lua errors")
end

---------------------------------------------------------------------------
-- 4b. Code review fixes: offline on a stale roster, n decay, hyphenated surnames, taxi zones, slow walker,
--     world-map pins not orphaned
---------------------------------------------------------------------------
do
  -- #3: B was offline at A's last roster read, then logs in and sends: A keeps B's pin
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha")
  bus:member("Bert Beta", "MAGE", 40, false)
  A.login()
  sched:advance(5)
  A.fire("GUILD_ROSTER_UPDATE")
  local M, RQ = A.M, A.RQ
  local b36 = RQ.Wire.b36
  bus:setOnline("Bert Beta", true)
  sched:advance(30)
  local P = table.concat({ "P", b36(1429), b36(9000), b36(9000), b36(40), b36(7), b36(RQ:Now()), "s", b36(2) }, ";")
  Inject(A, "Bert Beta", P)
  sched:advance(3)
  check(M.members["Bert Beta"] ~= nil, "stale 'offline' roster doesn't drop a guildmate who just logged in (#3)")
  bus:setOnline("Bert Beta", false)
  A.fire("GUILD_ROSTER_UPDATE")
  sched:advance(2)
  check(M.members["Bert Beta"] == nil, "a newer roster read showing offline drops the pin")

  -- #6: hyphenated surname stays whole; own realm suffix is stripped
  Inject(A, "Cara Müller-Lee", table.concat({ "P", b36(1429), b36(9100), b36(9100), b36(30), b36(2), b36(RQ:Now()), "", b36(2) }, ";"))
  bus:member("Cara Müller-Lee", "PALADIN", 30)
  A.fire("GUILD_ROSTER_UPDATE")
  sched:advance(3)
  local cara = M.members["Cara Müller-Lee"]
  check(cara and cara.name == "Cara Müller-Lee", "hyphenated surname kept whole (#6)")
  check(RQ:NormName("Anna Alpha-Realm") == "Anna Alpha" and RQ:NormName("Cara Müller-Lee") == "Cara Müller-Lee",
    "only our own '-Realm' suffix is stripped")
  NoErrors({ A }, "review fixes A: no Lua errors")
end

do
  -- #4: after most players leave, the estimate decays (no ratchet)
  local sched, bus = Setup()
  local ws = {}
  for i = 1, 12 do ws[i] = Client(sched, bus, ("Q%d Test"):format(i), { pos = { 1429, 0.2 + i * 0.05, 0.5 } }) end
  for _, w in ipairs(ws) do w.moving = true; Walk(sched, w); w.login() end
  sched:advance(900)
  check(ws[1].M:ActiveSenders() >= 11, "12 clients: estimate about 12 (" .. ws[1].M:ActiveSenders() .. ")")
  for i = 3, 12 do ws[i].set("share", false); bus:setOnline(ws[i].name, false) end
  sched:advance(1500)
  local a1, a2 = ws[1].M:ActiveSenders(), ws[2].M:ActiveSenders()
  check(a1 <= 3 and a2 <= 3, "estimate decays after 10 leave (" .. a1 .. ", " .. a2 .. ") (#4)")
  check(ws[1].M:Interval(true) == ws[1].M.C.INTERVAL_MIN, "interval back to the " .. ws[1].M.C.INTERVAL_MIN .. " s floor")
  NoErrors(ws, "decay: no Lua errors")
end

do
  -- taxi across zones: no zone message mid-flight; slow walker isn't 'stationary'; world pins not orphaned
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha", { pos = { 1429, 0.5, 0.5 } })
  local B = Client(sched, bus, "Bert Beta", { pos = { 1429, 0.6, 0.6 } })
  A.login(); B.login()
  A.moving = true; Walk(sched, A)
  sched:advance(200)
  A.taxi = true
  sched:advance(40)
  local t0 = sched.t
  A.pos = { 1436, 0.5, 0.5 } -- flew into another zone
  sched:advance(120)
  check(MapSends(bus, "Anna Alpha", t0, sched.t) == 0, "no zone message while on a taxi")
  A.taxi = false
  sched:advance(4)
  check(B.M.members["Anna Alpha"].mapID == 1436, "landing message has the new zone")
  -- slow walker: 0.0004 per 2 s (below the old per-tick threshold)
  A.moving = false
  local t1 = sched.t
  sched:at(sched.t + 2, function() if A.slow then A.pos = { A.pos[1], A.pos[2] + 0.0004, A.pos[3] } end end, 2)
  A.slow = true
  sched:advance(300)
  local lm = LastMsg(bus, "Anna Alpha", "P")
  check(MapSends(bus, "Anna Alpha", t1, sched.t) >= 3 and not lm.msg:match(";s;"), "slow walker keeps updating, not flagged stationary")
  A.slow = false
  -- world pins: many moves, still one canvas pin per icon (code review #1)
  check(B.maxCanvas() == 1, "world map: one canvas pin per guildmate after many moves (" .. B.maxCanvas() .. ")")
  NoErrors({ A, B }, "taxi/walker: no Lua errors")
end

---------------------------------------------------------------------------
-- 5. The core's scheduler and Map side by side
---------------------------------------------------------------------------
do
  -- roster gate, routing, and the shared budget: the suite's other messages go first
  local sched, bus = Setup()
  local A = Client(sched, bus, "Anna Alpha")
  local B = Client(sched, bus, "Bert Beta")
  A.login(); B.login()
  A.moving = true; Walk(sched, A)
  local GS = A.env.RavenquillExpedition
  check(GS and GS.modules and GS.modules.Map and GS.modules.Map.addon == "RavenquillExpedition_Map", "real core: module registered")
  local queued = 0
  local tch = GS:NewModule("EvtTest", { addon = "EvtTest" }):NewChannel({ tag = "T", version = 1 })
  tch:Define("x", { fields = {} })
  sched:at(sched.t + 5, function() tch:Send("x", {}); queued = queued + 1 end, 60)
  sched:advance(900)
  local coreSent = 0
  for _, e in ipairs(bus.log) do if e.sender == "Anna Alpha" and e.prefix == GS.COMM_PREFIX then coreSent = coreSent + 1 end end
  local mapSent = MapSends(bus, "Anna Alpha", 0, 900)
  local st = GS:CommState()
  print(("  real core, 15 min: core queued %d, sent %d, queue now %d; map sent %d"):format(queued, coreSent, st.queued, mapSent))
  check(coreSent >= queued - 1 and st.queued <= 1, "core modules get through while the map runs")
  check(st.foreign == 0, "Map sends only through the core's scheduler (no foreign sends: " .. tostring(st.foreign) .. ")")
  check(st.sent >= coreSent + mapSent, "the core counts every map message it sent")
  -- the state lane yields: no map message within STATE_QUIET after any other GUILD message of the same client
  local quiet = GS.CommConst.STATE_QUIET
  local lastAny, tooSoon = nil, 0
  for _, e in ipairs(bus.log) do
    if e.sender == "Anna Alpha" then
      if e.prefix == "RQEMap1" and lastAny and e.t - lastAny < quiet then tooSoon = tooSoon + 1 end
      lastAny = e.t
    end
  end
  check(tooSoon <= 1, ("map yields %d s to the client's other messages (%d starving exceptions)"):format(quiet, tooSoon))
  check(mapSent >= 900 / 30, "map still updates alongside the core, more than the old 30 s pace allowed (" .. mapSent .. ")")
  check(B.M.members["Anna Alpha"] ~= nil, "real core: B sees A")
  local mod = GS.modules.Map
  check(mod == A.M.mod and #mod.options >= 10 and mod.OnSlash == nil, "real core: options handed over, no subcommands")
  check(A.diag():find("Sync: prefix RQEMap1", 1, true), "real core: diagnostics")
  check(A.env.SlashCmdList.RAVENQUILLMAP == nil and A.env.SlashCmdList.RAVENQUILL ~= nil, "only the core registers /rq")
  NoErrors({ A, B }, "real core: no Lua errors")
end

---------------------------------------------------------------------------
-- 6. 40 clients, mass login, 30 minutes
---------------------------------------------------------------------------
do
  local sched, bus = Setup()
  local worlds = {}
  for i = 1, 40 do
    local w = Client(sched, bus, ("P%d Test"):format(i), { pos = { 1429, 0.2 + (i % 8) * 0.08, 0.2 + math.floor(i / 8) * 0.12 } })
    w.moving = i <= 30
    Walk(sched, w)
    worlds[i] = w
  end
  for _, w in ipairs(worlds) do w.login() end
  sched:advance(1800)
  local peak = MaxPer60(bus, nil, 0, 1800)
  local steady = bus:count(600, 1800) / 20
  local worstClient = 0
  for _, w in ipairs(worlds) do worstClient = math.max(worstClient, MaxPer60(bus, w.name, 0, 1800)) end
  local MC, CC = worlds[1].M.C, worlds[1].RQ.CommConst
  local TARGET = MC.GUILD_TARGET
  local steadyWorst = 0
  for _, w in ipairs(worlds) do steadyWorst = math.max(steadyWorst, MaxPer60(bus, w.name, 600, 1800)) end
  print(("  40 clients: peak %d msgs/60 s (mass login), steady %.1f msgs/min (min 10-30), worst client %d/60 s (steady %d)"):format(
    peak, steady, worstClient, steadyWorst))
  -- 30 of 40 move: each sends every 40 x 60 / TARGET = 40 s, the 10 standing ones heartbeat -> about 3/4 of the target
  check(steady <= TARGET and steady >= TARGET * 30 / 40 * 0.9,
    ("guild-wide steady rate near the target: %.1f/min (%.1f..%d)"):format(steady, TARGET * 30 / 40 * 0.9, TARGET))
  -- early senders still use the 5 s floor until they hear the others; accepted: brief, at most 2 x target
  check(peak <= 2 * TARGET, ("mass login spread out: peak <= 2 x target per 60 s (%d)"):format(peak))
  local interval = 40 * 60 / TARGET
  check(worlds[1].M:Interval(true) == interval, ("40 active senders: interval 40 x 60 / %d = %d s (%s)"):format(TARGET, interval,
    tostring(worlds[1].M:Interval(true))))
  check(steadyWorst <= math.ceil(60 / interval), ("steady: no client over %d map messages per 60 s (interval %d s, worst %d)"):format(
    math.ceil(60 / interval), interval, steadyWorst))
  check(worstClient <= CC.BURST + 60 * CC.RATE, ("mass login included: no client over the core's %d per 60 s (%d)"):format(
    CC.BURST + 60 * CC.RATE, worstClient))
  local minSeen, staleTotal, activeMin, activeMax = math.huge, 0, math.huge, 0
  for _, w in ipairs(worlds) do
    local seen = 0
    for key, m in pairs(w.M.members) do
      if not m.fake and not m.isSelf then
        seen = seen + 1
        if w.M:State(m) == "stale" then staleTotal = staleTotal + 1 end
      end
    end
    minSeen = math.min(minSeen, seen)
    local a = w.M:ActiveSenders()
    activeMin, activeMax = math.min(activeMin, a), math.max(activeMax, a)
  end
  print(("  every client sees >= %d of 39 others; stale pins in total %d; active-sender estimates %d-%d"):format(
    minSeen, staleTotal, activeMin, activeMax))
  check(minSeen >= 38, "each client sees (almost) everyone")
  check(staleTotal == 0, "no stale pins in steady state")
  check(activeMin >= 38 and activeMax <= 41, "active-sender estimate about 40")
  NoErrors(worlds, "40 clients: no Lua errors")
end

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
