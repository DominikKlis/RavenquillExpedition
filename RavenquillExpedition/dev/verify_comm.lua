local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")

local ME = "Anna Stone"
local PREFIXES = { VfEvt = true, VfRec = true }
local SETTLE_SECONDS = 4000

local ACTIONS = {
  { id = "E", say = "a module queues an event (Raw:Send)" },
  { id = "B", say = "a module queues one event every second for 20 s (burst)" },
  { id = "Ra", say = "a module queues record 'a' with 2 chunks (Raw:SendRecord)" },
  { id = "Rb", say = "a module queues record 'b' with 1 chunk (Raw:SendRecord)" },
  { id = "Xa", say = "a module cancels record 'a' (Raw:Cancel)" },
  { id = "I", say = "the player enters or leaves an instance (PLAYER_ENTERING_WORLD)" },
  { id = "K", say = "the player enters or leaves combat (PLAYER_REGEN_ENABLED on leaving)" },
  { id = "T", say = "the server starts or stops throttling SendAddonMessage (returns 3)" },
  { id = "L", say = "guild chat starts or stops losing our messages (no echo comes back)" },
  { id = "F", say = "another addon sends a guild addon message" },
  { id = "H", say = "a guildmate announces its version (the core answers once, jittered)" },
  { id = "t1", say = "1 s pass", dt = 1 },
  { id = "t5", say = "5 s pass", dt = 5 },
  { id = "t40", say = "40 s pass", dt = 40 },
  { id = "t130", say = "130 s pass (past ECHO_TIMEOUT)", dt = 130 },
  { id = "t310", say = "310 s pass (past RECORD_MAX_WAIT)", dt = 310 },
  { id = "t620", say = "620 s pass (past RECORD_MAX_AGE)", dt = 620 },
  { id = "t1900", say = "1900 s pass (past QUEUE_MAX_WAIT)", dt = 1900 },
}
local BY_ID = {}
for _, a in ipairs(ACTIONS) do BY_ID[a.id] = a end

local function NewWorld(reenter)
  local sched, bus = Kit.Setup()
  local c = Kit.Client(sched, bus, ME, { random = Kit.Random(7), setup = function(env)
    env.C_AddOns.GetAddOnMetadata = function(_, field) if field == "Version" then return "0.10.0-beta" end end
  end })
  c.login()
  sched:advance(5)
  local mod = c.RQ:NewModule("Verify", { addon = "Verify" })
  local w = { sched = sched, bus = bus, c = c, reenter = reenter, lossy = false,
    ev = mod:NewRawChannel({ prefix = "VfEvt", lane = "event" }),
    rec = mod:NewRawChannel({ prefix = "VfRec", lane = "record" }),
    sends = {}, records = {}, nextId = 0 }
  bus.drop = function(_, prefix) return w.lossy and PREFIXES[prefix] end
  return w
end

local function NewId(w) w.nextId = w.nextId + 1 return w.nextId end

local SendEvent
local function OnEventResult(w, s, status)
  s.outcomes[#s.outcomes + 1] = status
  if w.reenter and not s.retry and status ~= "delivered" then SendEvent(w, true) end
end

SendEvent = function(w, retry)
  local s = { id = NewId(w), outcomes = {}, retry = retry }
  w.sends[#w.sends + 1] = s
  w.ev:Send("e" .. s.id, { onResult = function(status) OnEventResult(w, s, status) end })
end

local function ChunkSent(w, r)
  for _, e in ipairs(w.bus.log) do
    if e.sender == ME and e.prefix == "VfRec" and e.msg:match("^r" .. r.id .. "c") then return true end
  end
  return false
end

local function MarkReplaced(w, key)
  for _, r in ipairs(w.records) do
    if r.key == key and not r.cancelled and #r.ends == 0 and not ChunkSent(w, r) then r.replaced = true end
  end
end

local SendRecord
local function OnRecordDrop(w, r, why)
  r.ends[#r.ends + 1] = "drop:" .. tostring(why)
  if w.reenter and not r.retry then SendRecord(w, r.key, r.n, true) end
end

SendRecord = function(w, key, n, retry)
  MarkReplaced(w, key)
  local r = { id = NewId(w), key = key, n = n, ends = {}, retry = retry }
  w.records[#w.records + 1] = r
  local chunks = {}
  for j = 1, n do chunks[j] = "r" .. r.id .. "c" .. j end
  w.rec:SendRecord(key, chunks, {
    onDone = function() r.ends[#r.ends + 1] = "done" end,
    onDrop = function(why) OnRecordDrop(w, r, why) end,
  })
end

local function Cancel(w, key)
  for _, r in ipairs(w.records) do if r.key == key and #r.ends == 0 then r.cancelled = true end end
  w.rec:Cancel(key)
end

local function Toggle(w, field, event)
  w.c[field] = not w.c[field]
  if event then w.c.fire(event) end
end

local DO = {
  E = function(w) SendEvent(w, false) end,
  B = function(w)
    for _ = 1, 20 do
      SendEvent(w, false)
      w.sched:advance(1)
    end
  end,
  Ra = function(w) SendRecord(w, "a", 2, false) end,
  Rb = function(w) SendRecord(w, "b", 1, false) end,
  Xa = function(w) Cancel(w, "a") end,
  I = function(w) Toggle(w, "instance", "PLAYER_ENTERING_WORLD") end,
  K = function(w) Toggle(w, "combat", w.c.combat and "PLAYER_REGEN_ENABLED" or nil) end,
  T = function(w) Toggle(w, "throttle") end,
  L = function(w) w.lossy = not w.lossy end,
  F = function(w) w.c.env.C_ChatInfo.SendAddonMessage("OtherAddon", "x", "GUILD") end,
  H = function(w) w.c.fire("CHAT_MSG_ADDON", "RQE1", "V;1;v;0.10.0-beta", "GUILD", "Bert Hill-Realm") end,
}

local function Step(w, id)
  local a = BY_ID[id]
  if a.dt then w.sched:advance(a.dt) else DO[id](w) end
end

local function Settle(w)
  w.c.instance, w.c.combat, w.c.throttle, w.lossy = false, false, false, false
  w.sched:advance(SETTLE_SECONDS)
end

local function CheckOnce(w, phase)
  for _, s in ipairs(w.sends) do
    if #s.outcomes > 1 then return ("event e%d got %d outcomes (%s) %s"):format(s.id, #s.outcomes, table.concat(s.outcomes, ", "), phase) end
  end
  for _, r in ipairs(w.records) do
    if #r.ends > 1 then return ("record r%d got %d endings (%s) %s"):format(r.id, #r.ends, table.concat(r.ends, ", "), phase) end
  end
end

local function CheckErrors(w, phase)
  if w.c.errors[1] then return "Lua error reported to the player " .. phase .. ": " .. tostring(w.c.errors[1]) end
end

local function CheckRate(w, phase)
  local C = w.c.RQ.CommConst
  local cap = C.BURST + 60 * C.RATE
  local most = w.bus:maxPer(60, ME, PREFIXES)
  if most > cap then return ("%d of our messages within 60 s, cap is %d %s"):format(most, cap, phase) end
end

local function CheckSafety(w, phase)
  return CheckOnce(w, phase) or CheckErrors(w, phase) or CheckRate(w, phase)
end

local function CheckSettled(w)
  for _, s in ipairs(w.sends) do
    if #s.outcomes == 0 then return ("event e%d never got an outcome after %d s with nothing in the way"):format(s.id, SETTLE_SECONDS) end
  end
  for _, r in ipairs(w.records) do
    if #r.ends == 0 and not (r.cancelled or r.replaced) then
      return ("record r%d (key %s) never ended after %d s with nothing in the way"):format(r.id, r.key, SETTLE_SECONDS)
    end
  end
  local st = w.c.RQ:CommState()
  if st.queued + st.records + st.inflight > 0 then
    return ("scheduler stalled: %d queued, %d records, %d waiting for echo after settling"):format(st.queued, st.records, st.inflight)
  end
end

local function Run(seq, reenter)
  local w = NewWorld(reenter)
  for i, id in ipairs(seq) do
    local ok, err = pcall(Step, w, id)
    if not ok then return "Lua error escaped after step " .. i .. ": " .. tostring(err) end
    local bad = CheckSafety(w, "after step " .. i)
    if bad then return bad end
  end
  local ok, err = pcall(Settle, w)
  if not ok then return "Lua error escaped while settling: " .. tostring(err) end
  return CheckSafety(w, "while settling") or CheckSettled(w)
end

local function Shrink(seq, reenter)
  local cur = { table.unpack(seq) }
  local changed = true
  while changed do
    changed = false
    for i = #cur, 1, -1 do
      local try = { table.unpack(cur) }
      table.remove(try, i)
      if Run(try, reenter) then cur, changed = try, true end
    end
  end
  return cur
end

local function Report(seq, reenter, why)
  io.write("\nVIOLATION: ", why, "\n")
  io.write("callbacks: ", reenter and "resend from inside onResult/onDrop (once)" or "record only", "\n")
  io.write("steps (", table.concat(seq, " "), "):\n")
  for i, id in ipairs(seq) do io.write(("  %2d. %s\n"):format(i, BY_ID[id].say)) end
  io.write("  then: instance, combat, throttle and loss clear; ", SETTLE_SECONDS, " s pass\n")
end

local function Fail(seq, reenter)
  local small = Shrink(seq, reenter)
  Report(small, reenter, Run(small, reenter))
  return false
end

local function Exhaustive(depth, reenter)
  local seq, runs = {}, 0
  local function dfs(d)
    if d > depth then
      runs = runs + 1
      return not Run(seq, reenter) or Fail(seq, reenter)
    end
    for _, a in ipairs(ACTIONS) do
      seq[d] = a.id
      if not dfs(d + 1) then return false end
    end
    seq[d] = nil
    return true
  end
  local ok = dfs(1)
  return ok, runs
end

local function Walks(count, len, seed, reenter)
  local rnd = Kit.Random(seed)
  for _ = 1, count do
    local seq = {}
    for i = 1, len do seq[i] = ACTIONS[rnd(#ACTIONS)].id end
    if Run(seq, reenter) then return Fail(seq, reenter) end
  end
  return true
end

local function Arg(name, default)
  for i = 1, #arg do if arg[i] == "--" .. name then return tonumber(arg[i + 1]) end end
  return default
end

local function Replay(spec)
  local seq = {}
  for id in spec:gmatch("[^,%s]+") do assert(BY_ID[id], "unknown action " .. id) seq[#seq + 1] = id end
  for _, reenter in ipairs({ false, true }) do
    local why = Run(seq, reenter)
    if why then Report(seq, reenter, why) os.exit(1) end
  end
  io.write("replay ok in both callback modes: ", table.concat(seq, " "), "\n")
  os.exit(0)
end

local function Main()
  for i = 1, #arg do if arg[i] == "--replay" then Replay(arg[i + 1] or "") end end
  local depth, walks, len, seed = Arg("depth", 3), Arg("walks", 1500), Arg("len", 24), Arg("seed", 20261117)
  local t0 = os.clock()
  local total = 0
  for _, reenter in ipairs({ false, true }) do
    local ok, runs = Exhaustive(depth, reenter)
    total = total + runs
    if not ok then os.exit(1) end
    if not Walks(walks, len, seed + (reenter and 1 or 0), reenter) then os.exit(1) end
    total = total + walks
  end
  io.write(("verify_comm: ok, %d runs (all %d-step sequences of %d actions + %d walks of %d steps, x2 callback modes), seed %d, %.0f s\n")
    :format(total, depth, #ACTIONS, walks, len, seed, os.clock() - t0))
end

Main()
