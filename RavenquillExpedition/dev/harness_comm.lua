local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local evt = setmetatable({}, { __mode = "k" })
local function EvtChannel(c)
  if not evt[c] then
    evt[c] = c.newModule("Evt" .. (c.name:gsub("%s", ""))):NewRawChannel({ prefix = "TstEvt", lane = "event" })
    c.prefixes.TstEvt = true
  end
  return evt[c]
end
local function Send(c, text, cb)
  for _, x in ipairs(c.bus.clients) do EvtChannel(x) end
  return EvtChannel(c):Send(text, cb and { onResult = cb })
end

section("Event lane: budget, order, echo results")
local sched, bus, a, b = Kit.Two()
local C = a.RQ.CommConst
local PACE = 1 / C.RATE
local CAP60 = C.BURST + 60 * C.RATE
local function minGapOf(list)
  local g = math.huge
  for i = 2, #list do g = math.min(g, list[i].t - list[i - 1].t) end
  return g
end
local results = {}
local N = 20
for i = 1, N do Send(a, "m" .. i, function(s) results[i] = s end) end
sched:advance(2)
check(#bus:sentBy("Anna Stone") == 1, "the first goes out on the first pump tick (1 s)")
sched:advance(58)
local inMinute = #bus:sentBy("Anna Stone")
check(inMinute >= 60 * C.RATE and inMinute <= CAP60,
  ("paced: %d in the first 60 s (%d..%d)"):format(inMinute, 60 * C.RATE, CAP60))
sched:advance(PACE * N + 60)
local sends = bus:sentBy("Anna Stone")
check(#sends == N and sends[1].msg == "m1" and sends[N].msg == "m" .. N, "all " .. N .. " in order (" .. #sends .. ")")
check(minGapOf(sends) >= PACE, ("queued at once: one per pump tick, never two within %d s (closest %s s)"):format(PACE, tostring(minGapOf(sends))))
check(bus:maxPer(60, "Anna Stone") <= CAP60, ("never more than %d in 60 s (burst %d + refill)"):format(CAP60, C.BURST))
check(results[1] == "delivered" and results[N] == "delivered", "every message reports its echo (delivered)")
sched:advance(60)
check(math.abs(a.RQ:CommState().tokens - C.BURST) < 1e-9, "idle: the bucket refills to the burst (" .. a.RQ:CommState().tokens .. ")")
for _ = 1, C.BURST - 1 do a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "x", "GUILD") end
local function ownEvt() return bus:sentBy("Anna Stone", function(e) return e.prefix == "TstEvt" end) end
local t0 = sched.t
Send(a, "after-small-burst")
sched:advance(2)
local last = ownEvt()[N + 1]
check(last and last.msg == "after-small-burst" and last.t - t0 <= 1, "a token left after another addon's small burst: sent at once")
sched:advance(60)
for _ = 1, C.BURST + 2 do a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "x", "GUILD") end
check(a.RQ:CommState().tokens == 0, "a bigger foreign burst empties the bucket, never below 0")
t0 = sched.t
Send(a, "after-big-burst")
sched:advance(PACE - 1)
check(#ownEvt() == N + 1, "then ours waits for the next token")
sched:advance(PACE + 1)
last = ownEvt()[N + 2]
check(last and last.msg == "after-big-burst" and last.t - t0 >= PACE and last.t - t0 <= PACE + 5,
  ("and goes out once one refilled (%s s, token every %d s)"):format(last and tostring(last.t - t0) or "-", PACE))
sched:advance(120)
t0 = sched.t
local K = C.BURST + 4
for i = 1, K do sched:at(t0 + i - 1, function() Send(a, "b" .. i) end) end
sched:advance(K + 60)
local bs = {}
for _, e in ipairs(ownEvt()) do if e.msg:match("^b%d+$") then bs[#bs + 1] = e end end
check(#bs == K, "all " .. K .. " of the second-by-second messages went out (" .. #bs .. ")")
local firstSpan = bs[C.BURST] and bs[C.BURST].t - bs[1].t or math.huge
check(firstSpan < (C.BURST - 1) * PACE, ("the first %d within %s s (burst, faster than one per %d s)"):format(C.BURST, tostring(firstSpan), PACE))
local paced = true
for i = C.BURST + 2, K do if bs[i].t - bs[i - 1].t < PACE - 1 then paced = false end end
check(paced and bs[K].t - bs[1].t >= (K - C.BURST - 1) * PACE,
  ("then paced by the refill (last one %s s after the first)"):format(tostring(bs[K].t - bs[1].t)))
check(bus:maxPer(60, "Anna Stone", { TstEvt = true }) <= CAP60, ("still within %d per 60 s"):format(CAP60))
local r1, r2
Send(a, "same", function(s) r1 = s end)
Send(a, "same", function(s) r2 = s end)
sched:advance(120)
check(r1 == "delivered" and r2 == "delivered", "two identical messages: both echoed (" .. tostring(r1) .. ", " .. tostring(r2) .. ")")

section("Holds: instance, combat, throttled, busy guild")
sched, bus, a, b = Kit.Two()
a.instance = true
local deferred
check(Send(a, "x", function(s) deferred = s end) == false, "inside an instance nothing is queued")
a.instance = false
Send(a, "y", function(s) deferred = s end)
a.instance = true
a.fire("PLAYER_ENTERING_WORLD")
sched:advance(5)
check(deferred == "dropped" and #bus:sentBy("Anna Stone") == 0, "entering an instance hands queued messages back")
a.instance = false
a.throttle = true
Send(a, "z")
sched:advance(3)
a.throttle = false
sched:advance(20)
check(#bus:sentBy("Anna Stone") == 0 and a.RQ:CommState().hold > 0, "a throttled result holds sending for 30 s")
sched:advance(40)
check(#bus:sentBy("Anna Stone") == 1, "after the hold it goes out")
local sched2, bus2 = Kit.Setup()
local cs = { Kit.Client(sched2, bus2, "Anna Stone") }
local noisy = math.ceil(C.BUSY_HEARD / C.HEARD_PER_SENDER)
for i = 1, noisy do cs[#cs + 1] = Kit.Client(sched2, bus2, "Noisy" .. i .. " Field") end
for _, c in ipairs(cs) do c.login() end
sched2:advance(5)
for _ = 1, C.HEARD_PER_SENDER + 4 do Send(cs[2], "noise") end
sched2:advance(PACE * (C.HEARD_PER_SENDER + 4) + 5)
Send(cs[1], "solo")
sched2:advance(5)
check(#bus2:sentBy("Anna Stone") == 1, ("one chatty client (%d messages) doesn't hold Anna"):format(C.HEARD_PER_SENDER + 4))
sched2:advance(90)
for i = 2, #cs do for _ = 1, C.HEARD_PER_SENDER do Send(cs[i], "noise") end end
sched2:advance(PACE * C.HEARD_PER_SENDER + 5)
check(#cs[1].RQ.Comm.heard >= C.BUSY_HEARD, ("%d senders x %d heard (counted %d)"):format(noisy, C.HEARD_PER_SENDER, #cs[1].RQ.Comm.heard))
Send(cs[1], "mine")
sched2:advance(5)
check(#bus2:sentBy("Anna Stone") == 1, ("busy guild (%d+ event messages heard in 60 s): Anna holds"):format(C.BUSY_HEARD))
sched2:advance(90)
check(#bus2:sentBy("Anna Stone") == 2, "and sends once it quiets down")

section("A chatty other addon can't silence the suite (in game: War Effort sends every 5-50 s)")
sched, bus, a, b = Kit.Two()
local every = PACE - 1
sched:at(sched.t + 1, function() a.env.C_ChatInfo.SendAddonMessage("WEFF1", "x", "GUILD") end, every)
sched:advance(60)
check(a.RQ:CommState().tokens < 1, ("the other addon (every %d s) keeps our bucket empty"):format(every))
local got3 = {}
local queuedAt = sched.t
for i = 1, 3 do Send(a, "starved" .. i, function(s) got3[i] = s end) end
local minTokens = math.huge
for _ = 1, C.STARVE + 120 do sched:advance(1); minTokens = math.min(minTokens, a.RQ:CommState().tokens) end
local own = bus:sentBy("Anna Stone", function(e) return e.prefix == "TstEvt" end)
local minGap = minGapOf(own)
check(#own == 3 and got3[3] == "delivered", ("all 3 of ours went out anyway (%d sent)"):format(#own))
check(own[1] and own[1].t - queuedAt >= C.STARVE and own[1].t - queuedAt <= C.STARVE + 5,
  ("the first only after waiting %d s (%s s)"):format(C.STARVE, own[1] and tostring(own[1].t - queuedAt) or "-"))
check(minGap >= PACE, ("our own messages stay >= %d s apart (closest %s s)"):format(PACE, minGap == math.huge and "-" or tostring(minGap)))
check(minTokens >= -1, ("the bucket never goes below -1 (lowest %.1f)"):format(minTokens))

section("Slow mode: our messages never come back")
sched, bus, a, b = Kit.Two()
bus.drop = function(sender) return sender == "Anna Stone" end
local lost = 0
for i = 1, 3 do Send(a, "lost" .. i, function(s) if s == "lost" then lost = lost + 1 end end) end
sched:advance(300)
check(lost >= 2 and a.RQ:CommState().slow, "no echo for 120 s: lost, then slow mode")
check(a.printedMatch("sending slowly") ~= nil, "the player is told once")
do
  local before = #bus:sentBy("Anna Stone")
  for i = 1, 10 do Send(a, "slow" .. i) end
  sched:advance(600)
  local n = #bus:sentBy("Anna Stone") - before
  check(a.RQ:CommState().slow and n <= 2, "while slow: 10 queued events, 600 s -> at most 2 sent (1 per 5 min), sent " .. n)
end
bus.drop = function() return false end
a.RQ:CommResume()
check(not a.RQ:CommState().slow, "CommResume leaves slow mode")
sched, bus, a, b = Kit.Two()
Send(a, "fine")
sched:advance(40)
check(a.RQ:CommState().delivered == 1 and not a.RQ:CommState().slow, "first message echoed")
bus.drop = function(sender) return sender == "Anna Stone" end
for i = 1, 2 do Send(a, "gone" .. i) end
sched:advance(400)
check(a.RQ:CommState().slow, "later echoes stop for 120 s after a loss: slow mode")
bus.drop = function() return false end
Send(a, "back")
sched:advance(700)
check(not a.RQ:CommState().slow, "the next echo ends slow mode")

section("Record lane: whole records, replace, drop")
sched, bus, a, b = Kit.Two()
local ra = a.newModule("RecA"):NewRawChannel({ prefix = "TstRec", lane = "record" })
local rb = b.newModule("RecB"):NewRawChannel({ prefix = "TstRec", lane = "record" })
a.fire("PLAYER_LOGIN"); b.fire("PLAYER_LOGIN")
local got = {}
rb:OnMessage(function(sender, text) got[#got + 1] = sender .. ":" .. text end)
local done
ra:SendRecord("self", { "c1", "c2", "c3" }, { onDone = function() done = true end })
ra:SendRecord("self", { "n1", "n2" }, { onDone = function() done = "new" end })
sched:advance(100)
check(table.concat(got, ",") == "Anna Stone:n1,Anna Stone:n2" and done == "new", "an unstarted record is replaced by a newer one with the same key")
Send(a, "evt")
ra:SendRecord("r:x", { "r1", "r2" })
sched:advance(2)
check(bus:sentBy("Anna Stone")[3].msg == "evt", "events go before record chunks")
sched:advance(120)
a.combat = true
local dropped
ra:SendRecord("late", { "x1" }, { onDrop = function(why) dropped = why end })
sched:advance(400)
check(dropped == "timeout", "a record not started within 5 min is dropped whole (" .. tostring(dropped) .. ")")
a.combat = false

section("State lane: now or never, lowest priority")
sched, bus, a, b = Kit.Two()
local sa = a.newModule("PosA"):NewRawChannel({ prefix = "TstPos", lane = "state" })
local sb = b.newModule("PosB"):NewRawChannel({ prefix = "TstPos", lane = "state" })
a.fire("PLAYER_LOGIN"); b.fire("PLAYER_LOGIN")
local heardPos = 0
sb:OnMessage(function() heardPos = heardPos + 1 end)
check(sa:TrySend("P;1") == true, "TrySend sends when nothing waits")
sched:advance(C.STATE_QUIET - 1)
local ok, why = sa:TrySend("P;2")
check(not ok and why:find("another addon sent", 1, true), ("not again within %d s: %s"):format(C.STATE_QUIET, tostring(why)))
sched:advance(2)
ok = sa:TrySend("P;2b")
check(ok, ("after %d s quiet it may send again (a token left)"):format(C.STATE_QUIET))
Send(a, "first")
sched:advance(20)
Send(a, "q1"); Send(a, "q2"); Send(a, "q3")
ok, why = sa:TrySend("P;3")
check(not ok and why:find("waiting", 1, true), "a queued event goes first: " .. tostring(why))
ok, why = sa:TrySend("P;4", { starving = true })
check(not ok, "even starving, a waiting event wins")
sched:advance(200)
for _ = 1, C.STATE_MAX_60 do a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "x", "GUILD") end
sched:advance(C.STATE_QUIET + 1)
ok, why = sa:TrySend("P;5")
check(not ok and why:find("in 60 s", 1, true), ("%d+ GUILD sends in 60 s: refused: %s"):format(C.STATE_MAX_60, tostring(why)))
ok = sa:TrySend("P;6", { starving = true })
check(ok, "starving waives the quiet rules once")
sched:advance(5)
check(heardPos == 3, "the receiver got the three state messages that were sent (" .. heardPos .. ")")
local sentBefore = sa:Status().sent
check(sa:SendNow("L;1") == true, "SendNow: best effort now")
check(sa:Status().sent == sentBefore + 1, ("SendNow counts in the channel's sent statistics (%d -> %d)"):format(sentBefore, sa:Status().sent))
sched:advance(200)
local wireBefore = #bus:sentBy("Anna Stone")
ok, why = sa:TrySend("P;\0x", { starving = true })
check(not ok and #bus:sentBy("Anna Stone") == wireBefore, "TrySend refuses a NUL byte: " .. tostring(why))
check(sa:SendNow("L;\0x") == false and #bus:sentBy("Anna Stone") == wireBefore, "SendNow refuses a NUL byte")

section("Intake caps and busy counting by lane")
sched, bus, a, b = Kit.Two()
sb = b.newModule("PosB2"):NewRawChannel({ prefix = "TstPos", lane = "state" })
b.fire("PLAYER_LOGIN")
local n = 0
sb:OnMessage(function() n = n + 1 end)
for i = 1, C.INTAKE_STATE_PER_MIN + 5 do b.fire("CHAT_MSG_ADDON", "TstPos", "x" .. i, "GUILD", "Cora Vale-Realm") end
check(n == C.INTAKE_STATE_PER_MIN, ("state prefixes: at most %d per sender per minute (%d)"):format(C.INTAKE_STATE_PER_MIN, n))
check(C.INTAKE_STATE_PER_MIN >= CAP60 and C.INTAKE_PER_MIN >= CAP60,
  ("intake caps (%d / %d) read everything one paced client can send (%d per 60 s)"):format(C.INTAKE_PER_MIN, C.INTAKE_STATE_PER_MIN, CAP60))
local heardBefore = #b.RQ.Comm.heard
check(heardBefore == 0, "state messages don't count towards the busy hold")
local m = 0
local zz = b.newModule("ZZ"):NewRawChannel({ prefix = "TstZZ", lane = "event" })
zz:OnMessage(function() m = m + 1 end)
for i = 1, C.INTAKE_PER_MIN + 5 do b.fire("CHAT_MSG_ADDON", "TstZZ", "x" .. i, "GUILD", "Dora Field-Realm") end
check(m == C.INTAKE_PER_MIN and #b.RQ.Comm.heard == C.HEARD_PER_SENDER,
  ("event prefix: %d per sender per minute, at most %d count as busy (%d, %d)"):format(C.INTAKE_PER_MIN, C.HEARD_PER_SENDER, m, #b.RQ.Comm.heard))
sched:advance(61)
for i = 1, 3 do b.fire("CHAT_MSG_ADDON", "TstZZ", "y" .. i, "GUILD", "Dora Field-Realm") end
check(m == C.INTAKE_PER_MIN + 3, "a minute later the same sender is read again")

section("Registration rules and the foreign-send hook")
local tm = a.newModule("Tags")
check(not pcall(tm.NewChannel, tm, { tag = "~T" }) == false, "a free tag works")
check(not pcall(tm.NewChannel, tm, { tag = "~T" }), "the same tag twice: error")
check(a.RQ.RegisterComm == nil and a.RQ.SendGuild == nil and a.RQ.CanSendGuild == nil, "the old sync API is gone (channels only)")
check(pcall(tm.NewRawChannel, tm, { prefix = "TstDup" }) and not pcall(tm.NewRawChannel, tm, { prefix = "TstDup" }), "a prefix twice: error")
check(not pcall(tm.NewRawChannel, tm, { prefix = "RQE1" }), "the core prefix can't be taken")
local before = a.RQ:CommState()
a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "hi", "GUILD")
local after = a.RQ:CommState()
check(after.foreign == before.foreign + 1, "another addon's GUILD send is counted (and costs a token)")
a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "hi", "WHISPER")
check(a.RQ:CommState().foreign == after.foreign, "a whisper is not")

section("Schema channels")
sched, bus, a, b = Kit.Two()
local function Fishing(c)
  local mod = c.newModule("Fish")
  local ch = mod:NewChannel({ tag = "F", version = 1 })
  ch:Define("catch", { lane = "event", from = "self", fields = { { "who", "key" }, { "item", "int", 1, 9999999 },
    { "q", "int", 0, 8, opt = true }, { "note", "text", 20 }, { "cls", "class" }, { "t", "time" }, { "big", "flag" },
    { "kind", "enum", { "fish", "junk" } }, { "w", "b36", 0, 46655 } } })
  return mod, ch
end
local _, cha = Fishing(a)
local _, chb = Fishing(b)
local caught = {}
chb:On("catch", function(sender, msg) caught[#caught + 1] = { sender = sender, msg = msg } end)
local status
cha:Send("catch", { who = "Anna Stone", item = 6522, note = "Großer |cffff0000Fisch|r; echt", cls = "MAGE", t = a.RQ:Now(),
  big = true, kind = "fish", w = 1234 }, { onResult = function(s) status = s end })
sched:advance(10)
local wire = bus:sentBy("Anna Stone")[1]
check(wire and wire.prefix == "RQE1" and wire.msg == "F;1;catch;Anna Stone;6522;;Großer Fisch echt;7;" .. a.RQ:Now() - 10 + 0 .. ";1;fish;ya"
  or (wire and wire.msg:match("^F;1;catch;Anna Stone;6522;;Großer Fisch echt;7;%d+;1;fish;ya$")), "wire format: " .. tostring(wire and wire.msg))
local c1 = caught[1]
check(c1 and c1.sender == "Anna Stone" and c1.msg.item == 6522 and c1.msg.q == nil and c1.msg.cls == "MAGE" and c1.msg.big == true
  and c1.msg.kind == "fish" and c1.msg.w == 1234 and c1.msg.note == "Großer Fisch echt", "decoded on the other client")
check(status == "delivered", "onResult: delivered (" .. tostring(status) .. ")")
local function inject(text, sender)
  b.RQ.Comm.intake = {}
  b.fire("CHAT_MSG_ADDON", "RQE1", text, "GUILD", (sender or "Anna Stone") .. "-Realm")
end
local now = a.RQ:Now()
inject("F;2;catch;Anna Stone;1;;x;1;" .. now .. ";0;fish;1")
inject("F;1;catch;Anna Stone;1;;x;1;" .. now .. ";0;fish")
inject("F;1;catch;Cora Vale;1;;x;1;" .. now .. ";0;fish;1")
inject("F;1;catch;Anna Stone;0;;x;1;" .. now .. ";0;fish;1")
inject("F;1;catch;Anna Stone;1;;x;1;" .. (now + 9999) .. ";0;fish;1")
inject("F;1;catch;Anna Stone;1;;x;1;" .. now .. ";0;shark;1")
inject("F;1;nope;1")
local rej = chb:Status().rejected
check(#caught == 1, "nothing invalid reached the handler")
check(rej["version"] == 1 and rej["field w"] == 1 and rej["not the sender"] == 1 and rej["field item"] == 1
  and rej["field t"] == 1 and rej["field kind"] == 1 and rej["unknown type"] == 1, "each rejection counted by reason")
for i = 1, 200 do inject("F;" .. (100 + i) .. ";catch") inject("F;1;bogus" .. i .. ";1") end
local keys = 0
for _ in pairs(chb:Status().rejected) do keys = keys + 1 end
check(keys <= 8 and chb:Status().rejected["version"] == 201, "400 malformed messages add no new keys (" .. keys .. " keys)")
for what, bad in pairs({ ["item 0"] = { item = 0 }, ["item inf"] = { item = math.huge }, ["item NaN"] = { item = 0 / 0 },
  ["w above hi"] = { w = 46656 }, ["w inf"] = { w = math.huge }, ["class unknown"] = { cls = "PIRATE" } }) do
  local m = { who = "Anna Stone", item = 1, note = "x", cls = "MAGE", t = now, big = false, kind = "fish", w = 1 }
  for k, v in pairs(bad) do m[k] = v end
  check(cha:Encode("catch", m) == nil, "encode refuses " .. what)
end
check(a.RQ.Wire.b36(math.huge) == "0" and a.RQ.Wire.b36(0 / 0) == "0" and a.RQ.Wire.b36(-5) == "0"
  and a.RQ.Wire.b36(2 ^ 60) == "0" and a.RQ.Wire.b36(46655) == "zzz", "b36: NaN, infinity, negative, huge -> 0; normal unchanged")
check(not pcall(function() a.newModule("StateType"):NewChannel({ tag = "ST", version = 1 }):Define("pos", { lane = "state",
  fields = {} }) end), "Define rejects lane = state (schema types are always event traffic)")
local dropped2
cha:Send("catch", { who = "Anna Stone", item = 1, note = "x", cls = "MAGE", t = now, big = false, kind = "nope", w = 1 },
  { onResult = function(s) dropped2 = s end })
check(dropped2 == "dropped", "a message that can't be encoded reports dropped")
local longCh = a.newModule("Long"):NewChannel({ tag = "LG", version = 1 })
longCh:Define("t", { fields = { { "a", "text", 200 }, { "b", "text", 200 } } })
local enc = longCh:Encode("t", { a = string.rep("x", 200), b = string.rep("y", 200) })
check(enc and #enc <= 250 and enc:find("x;y", 1, true), "too long: text fields are halved once")

section("Mixed versions: a released 0.2.0 client and a new one exchange highlights")
local OLD = DEV .. "fixtures/compat_0.2.0/"
local sched3, bus3 = Kit.Setup()
local function OldFiles()
  local list = {}
  for _, f in ipairs({ "Core.lua", "Comm.lua", "Overview.lua" }) do list[#list + 1] = { OLD .. "RavenquillExpedition/" .. f, "RavenquillExpedition" } end
  for _, f in ipairs({ "Locale.lua", "Highlights.lua", "Wire.lua", "Detectors.lua", "LogWindow.lua" }) do
    list[#list + 1] = { OLD .. "RavenquillExpedition_Highlights/" .. f, "RavenquillExpedition_Highlights" }
  end
  return list
end
local stub = function(env)
  env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
  env.GetInventoryItemLink = function() end
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  env.LOOT_ITEM_SELF, env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
  env.LOOT_ITEM, env.LOOT_ITEM_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d."
  env.RAID_CLASS_COLORS = {}
end
local new = Kit.Client(sched3, bus3, "Neu Mann", { addons = { "RavenquillExpedition_Highlights" }, setup = stub })
local old = Kit.Client(sched3, bus3, "Alt Frau", { noCore = true, files = OldFiles(), setup = stub })
new.login(); old.login()
sched3:advance(5)
local function H(c) return c.RQ:GetModule("Highlights") end
local tNow = new.RQ:Now() - 100
H(new).channel:Send(H(new).ToMessage({ k = "level", t = tNow, who = "Neu Mann", lvl = 40, cls = "MAGE", id = "Neu Mann#" .. tNow .. "#1" }))
old.RQ:SendGuild("H", H(old).Encode({ k = "level", t = tNow, who = "Alt Frau", lvl = 30, cls = "ROGUE", id = "Alt Frau#" .. tNow .. "#1" }))
sched3:advance(30)
local function has(c, who) for _, e in ipairs((H(c):Log())) do if e.who == who then return true end end end
check(has(old, "Neu Mann"), "the 0.2.0 client stores the new client's highlight")
check(has(new, "Alt Frau"), "the new client stores the 0.2.0 client's highlight")
check(#new.errors == 0 and #old.errors == 0, "no Lua errors on either (" .. tostring(new.errors[1] or old.errors[1]) .. ")")

section("Review 2026-11-15: bounded lists, a module that never loads")
sched, bus, a, b = Kit.Two()
a.combat = true
for _ = 1, 2000 do
  a.env.C_ChatInfo.SendAddonMessage("OtherAddon", "x", "GUILD")
  sched:advance(1)
end
check(#a.RQ.Comm.sends <= 61, "2000 foreign sends over 2000 s while idle: the send list keeps only 60 s (" .. #a.RQ.Comm.sends .. ")")
a.combat = false
do
  local s3 = Kit.Setup()
  local c = Kit.Client(s3, bus, "Cora Vale")
  c.RQ:NewModule("Typo", { addon = "RavenquillExpedition_Typo", sv = "TypoDB" })
  c.login()
  check(c.printedMatch("Typo never loaded") ~= nil, "a module whose addon never loads is named at login")
  check(c.printedMatch("Comm never loaded") == nil and c.printedMatch("Example never loaded") == nil,
    "loaded modules are not named")
end

Kit.finish()
