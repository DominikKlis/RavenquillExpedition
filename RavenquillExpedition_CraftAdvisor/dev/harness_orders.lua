local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local SKIP = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua", "RecipeSources.lua", "UI" }
local FILES = Files.kitFiles(Files.list({ except = SKIP }))
local OLD_FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua",
  "RecipeSources.lua", "UI", "SyncOrders.lua", "Core/Orders.lua" } }))

local GUILD = {
  { name = "Anna Stone", class = "ROGUE", level = 36 },
  { name = "Bert Hill", class = "DRUID", level = 35 },
  { name = "Cora Vale", class = "HUNTER", level = 31 },
  { name = "Dora Field", class = "WARRIOR", level = 35 },
}
local GUILD_BY = {}
for _, g in ipairs(GUILD) do GUILD_BY[g.name] = g end

local VEST, LW = 3762, "Leatherworking"
local sched = Kit.Scheduler({ trap = true })
local bus = Kit.Bus(sched)
bus.latency = 0.2
local clients = {}
local function advance(sec) sched:advance(sec) end

local function StubPlayer(env, name)
  local first, surname = name:match("^(%S+) (%S+)$")
  local g = GUILD_BY[name]
  env.UnitName = function(u) if u == "player" then return first, surname end end
  env.UnitNameUnmodified = env.UnitName
  env.UnitClass = function(u) if u == "player" then return g.class, g.class end end
  env.UnitLevel = function(u) if u == "player" then return g.level end end
  env.UnitGUID = function(u) if u == "player" then return "G-" .. name end end
  env.UnitIsPlayer = function(u) return u == "player" end
  env.UnitIsUnit = function(a, b) return a == b end
  env.GetInventoryItemLink = function() return nil end
  env.GetNumSubgroupMembers = function() return 0 end
  env.GetNumGuildMembers = function() return #GUILD end
  env.GetGuildRosterInfo = function(i)
    local m = GUILD[i]
    if not m then return end
    local c = clients[m.name]
    return m.name, "Member", 1, m.level, m.class, "Zone", "", "", (c and c.online) or false, 0, m.class
  end
  env.C_GuildInfo = { GuildRoster = function() end }
  env.C_Item = { GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end,
    GetItemStats = function() return {} end }
  env.C_SpellBook = { IsSpellKnown = function() return false end }
  env.IsPlayerSpell = function() return false end
  env.GetProfessions = function() return nil end
  local send = env.C_ChatInfo.SendAddonMessage
  env.C_ChatInfo.SendAddonMessage = function(prefix, msg, chan)
    assert(#msg <= 255, "message over 255 bytes: " .. #msg)
    assert(chan == "GUILD", "non-GUILD send: " .. tostring(chan))
    return send(prefix, msg, chan)
  end
end

local function Roster()
  for _, c in pairs(clients) do if c.online then c.fire("GUILD_ROSTER_UPDATE") end end
end

local function Login(name, opts)
  opts = opts or {}
  if clients[name] then clients[name].online = false end
  local g = GUILD_BY[name]
  local c = Kit.Client(sched, bus, name, { class = g.class, level = g.level, epoch = 1800000000, random = Kit.Random(#name),
    files = opts.files or FILES, setup = function(env)
      StubPlayer(env, name)
      env.RavenquillExpeditionCraftDB = opts.db or {}
    end })
  c.GCA = c.ns[CA].GCA
  c.db = function() return c.env.RavenquillExpeditionCraftDB end
  clients[name] = c
  c.login()
  Roster()
  return c
end

local function Logout(name)
  clients[name].online = false
  Roster()
end

local function orderMsgs(pred)
  return bus:count(function(e) return e.msg:match("^CO;") ~= nil and (not pred or pred(e)) end)
end
local function sentBy(name, typ)
  return orderMsgs(function(e) return e.sender == name and e.msg:match("^CO;1;" .. typ .. ";") ~= nil end)
end
local function printedSince(c, mark) return c.printedSince(mark) end
local function only(list) return #list == 1 and list[1] or nil end
local function actions(c, o) return table.concat(c.GCA:OrderActions(o), ",") end
local function stored(c, o) return c.GCA:Orders()[c.GCA.OrderKey(o.requester, o.id)] end

local A, B, Cc = Login("Anna Stone"), Login("Bert Hill"), Login("Cora Vale")
advance(60)

section("Ask: the order reaches the crafter, the requester keeps it, the guild sees it open")
local before = orderMsgs()
local markB = #B.printed
local o = A.GCA:PlaceOrder("Bert Hill", LW, VEST, 18.4)
check(o and o.state == "requested" and o.requester == "Anna Stone" and o.crafter == "Bert Hill" and o.gain == 18 and o.spell == VEST,
  "Anna's order: requested, for her, to Bert, the vest, gain rounded to 18")
check(A.GCA:OrderList(o) == "mine" and only(A.GCA:OrderLists().mine) == o, "on Anna's side under 'From me'")
advance(20)
local ob = stored(B, o)
check(ob and ob.state == "requested" and ob.requester == "Anna Stone" and ob.gain == 18 and ob.prof == LW and ob.spell == VEST,
  "Bert has the same order: requested, with Anna's gain")
check(B.GCA:OrderList(ob) == "tome" and only(B.GCA:OrderLists().tome) == ob, "on Bert's side under 'To me'")
check(printedSince(B, markB):find("Anna Stone asks you to craft", 1, true) ~= nil, "Bert is told in chat: " .. printedSince(B, markB))
local heard = only(Cc.GCA:OrderLists().guild)
check(heard and heard.requester == "Anna Stone" and heard.crafter == "Bert Hill" and heard.state == "requested"
  and next(Cc.GCA:Orders()) == nil, "Cora (not a party) lists it under 'Open in the guild' and saves nothing")
check(orderMsgs() - before == 2 and sentBy("Anna Stone", "o") == 1 and sentBy("Bert Hill", "k") == 1,
  "two messages: Anna's order and Bert's acknowledgement")
check(A.GCA:PlaceOrder("Bert Hill", LW, VEST, 18) == o and #A.GCA:OrderLists().mine == 1,
  "asking again while it is open gives the same order back")
advance(600)
check(orderMsgs() - before == 2, "no resends once acknowledged (10 minutes later still 2 messages)")

section("Only the allowed party moves the order, one step at a time")
check(actions(A, o) == "withdraw" and actions(B, ob) == "accept,decline", "Anna may withdraw; Bert may accept or decline")
check(not A.GCA:OrderAction(o, "accept") and not A.GCA:OrderAction(o, "done") and not A.GCA:OrderAction(o, "decline"),
  "the requester can't accept, finish or decline")
check(not B.GCA:OrderAction(ob, "withdraw") and not B.GCA:OrderAction(ob, "receive"), "the crafter can't withdraw or confirm receipt")
check(not B.GCA:OrderAction(ob, "done") and not A.GCA:OrderAction(o, "receive"), "nothing skips a step: done needs accepted, receipt needs done")
check(not Cc.GCA:OrderAction(heard, "accept") and not Cc.GCA:OrderAction(heard, "withdraw"), "a bystander can't touch it")
check(o.state == "requested" and ob.state == "requested", "both still requested")
local markA = #A.printed
check(B.GCA:OrderAction(ob, "accept") and ob.state == "accepted", "Bert accepts")
advance(20)
check(o.state == "accepted" and printedSince(A, markA):find("Bert Hill accepted your order", 1, true) ~= nil,
  "Anna sees accepted and is told: " .. printedSince(A, markA))
check(actions(A, o) == "withdraw" and actions(B, ob) == "done,decline", "now Bert may finish or decline, Anna may still withdraw")
check(B.GCA:OrderAction(ob, "done"), "Bert marks it done")
advance(20)
check(o.state == "done" and actions(A, o) == "receive" and actions(B, ob) == "", "Bert finished: Anna may confirm receipt")
check(A.GCA:OrderList(o) == "mine" and B.GCA:OrderList(ob) == "finished", "done: still 'From me' for Anna, 'Finished' for Bert")
check(A.GCA:OrderAction(o, "receive"), "Anna confirms receipt")
advance(20)
check(ob.state == "received" and A.GCA:OrderList(o) == "finished" and B.GCA:OrderList(ob) == "finished",
  "Anna confirmed: received on both sides, both under 'Finished'")
check(#Cc.GCA:OrderLists().guild == 0, "Cora stops listing it once it is no longer open")
check(sentBy("Anna Stone", "o") == 2 and sentBy("Bert Hill", "o") == 2 and sentBy("Anna Stone", "k") == 2
  and sentBy("Bert Hill", "k") == 2 and orderMsgs() - before == 8,
  "a whole order costs 8 messages: 4 state changes, each acknowledged once")

section("Declined and withdrawn")
local o2 = A.GCA:PlaceOrder("Bert Hill", LW, 3763, 5)
advance(20)
local ob2 = stored(B, o2)
check(B.GCA:OrderAction(ob2, "decline"), "Bert declines the second order")
advance(20)
check(o2.state == "declined" and A.GCA:OrderList(o2) == "finished" and actions(A, o2) == "", "declined: finished for Anna, nothing left to do")
local o3 = A.GCA:PlaceOrder("Bert Hill", LW, 3764)
advance(20)
local ob3 = stored(B, o3)
check(ob3 and ob3.gain == nil, "an order without a gain travels without one")
markB = #B.printed
check(A.GCA:OrderAction(o3, "withdraw"), "Anna withdraws the third order")
advance(20)
check(ob3.state == "withdrawn" and B.GCA:OrderList(ob3) == "finished" and printedSince(B, markB):find("Anna Stone withdrew", 1, true) ~= nil,
  "withdrawn: Bert sees it and is told")

section("Forged and stray messages change nothing")
local ch = A.GCA.orderChannel
local function wire(typ, fields) return assert(ch:Encode(typ, fields)) end
local function fields(ord, state)
  return { requester = ord.requester, id = ord.id, crafter = ord.crafter, line = 165, spell = ord.spell, state = state, gain = ord.gain }
end
local function deliver(c, from, msg)
  c.fire("CHAT_MSG_ADDON", "RQE1", msg, "GUILD", from .. "-Realm")
  c.RQ.Comm.intake = {}
end
local o4 = A.GCA:PlaceOrder("Bert Hill", LW, 2160, 3)
advance(20)
local ob4 = stored(B, o4)
deliver(B, "Anna Stone", wire("o", fields(o4, "accepted")))
deliver(B, "Anna Stone", wire("o", fields(o4, "done")))
check(ob4.state == "requested", "Anna can't send 'accepted' or 'done' for Bert")
deliver(A, "Bert Hill", wire("o", fields(o4, "withdrawn")))
deliver(A, "Bert Hill", wire("o", fields(o4, "received")))
check(o4.state == "requested", "Bert can't send 'withdrawn' or 'received' for Anna")
deliver(B, "Cora Vale", wire("o", fields(o4, "withdrawn")))
deliver(A, "Cora Vale", wire("o", fields(o4, "accepted")))
check(ob4.state == "requested" and o4.state == "requested", "Cora can't move someone else's order")
local bogus = fields(o4, "accepted")
bogus.spell = 999999
deliver(A, "Bert Hill", wire("o", bogus))
bogus = fields(o4, "accepted")
bogus.line = 129
deliver(A, "Bert Hill", wire("o", bogus))
check(o4.state == "requested", "unknown recipe or profession: ignored")
deliver(A, "Bert Hill", wire("k", { requester = "Anna Stone", id = o4.id + 1, state = "received" }))
check(#B.errors == 0 and #A.errors == 0 and #Cc.errors == 0, "no Lua errors")

section("Duplicates and reordering converge (state rank is the version: higher wins)")
local LIFE = { { "requested", "Anna Stone" }, { "accepted", "Bert Hill" }, { "done", "Bert Hill" }, { "received", "Anna Stone" } }
local function permutations(n)
  local out, idx = {}, {}
  for i = 1, n do idx[i] = i end
  local function rec(k)
    if k > n then local p = {} for i = 1, n do p[i] = idx[i] end out[#out + 1] = p return end
    for i = k, n do idx[k], idx[i] = idx[i], idx[k]; rec(k + 1); idx[k], idx[i] = idx[i], idx[k] end
  end
  rec(1)
  return out
end
local D = Login("Dora Field")
local lastOpen, perms, agree = 0, permutations(#LIFE), 0
for n, p in ipairs(perms) do
  local fake = { requester = "Anna Stone", id = 5000 + n, crafter = "Bert Hill", spell = VEST, gain = 7 }
  local key = D.GCA.OrderKey(fake.requester, fake.id)
  for _, i in ipairs(p) do
    local step = LIFE[i]
    deliver(D, step[2], wire("o", fields(fake, step[1])))
    deliver(D, step[2], wire("o", fields(fake, step[1])))
  end
  local h = D.GCA.heardOrders[key]
  if h and h.state == "received" then agree = agree + 1 end
  if h and D.GCA:OrderList(h) ~= nil then lastOpen = lastOpen + 1 end
end
check(agree == #perms and lastOpen == 0 and #D.GCA:OrderLists().guild == 0,
  ("a bystander, all %d orders of requested/accepted/done/received, each twice: always ends received, never listed open (%d/%d)")
    :format(#perms, agree, #perms))
local fake = { requester = "Anna Stone", id = 6000, crafter = "Bert Hill", spell = VEST }
deliver(D, "Bert Hill", wire("o", fields(fake, "accepted")))
deliver(D, "Anna Stone", wire("o", fields(fake, "requested")))
check(D.GCA.heardOrders[D.GCA.OrderKey("Anna Stone", 6000)].state == "accepted", "a late 'requested' doesn't undo 'accepted'")

local held = {}
local function Hold(sender, prefix, msg, to)
  if not msg:match("^CO;") or to.name == sender or not to.online then return false end
  held[#held + 1] = { from = sender, to = to, msg = msg }
  return true
end
local function Replay()
  bus.drop = function() return false end
  for i = #held, 1, -1 do
    local h = held[i]
    deliver(h.to, h.from, h.msg)
    deliver(h.to, h.from, h.msg)
  end
end
local o5 = A.GCA:PlaceOrder("Bert Hill", LW, 2161, 4)
advance(20)
local ob5 = stored(B, o5)
bus.drop = Hold
check(A.GCA:OrderAction(o5, "withdraw") and B.GCA:OrderAction(ob5, "accept"), "at the same moment: Anna withdraws, Bert accepts")
advance(200)
Replay()
advance(200)
check(o5.state == "withdrawn" and ob5.state == "withdrawn", "delivered late, backwards and twice: both sides end withdrawn")

local o6 = A.GCA:PlaceOrder("Bert Hill", LW, 2162, 4)
advance(20)
local ob6 = stored(B, o6)
check(B.GCA:OrderAction(ob6, "accept"), "Bert accepts")
advance(20)
held = {}
bus.drop = Hold
check(A.GCA:OrderAction(o6, "withdraw") and B.GCA:OrderAction(ob6, "done"), "at the same moment: Anna withdraws, Bert finishes")
advance(200)
Replay()
advance(200)
check(o6.state == "done" and ob6.state == "done" and actions(A, o6) == "receive",
  "both sides end done (the craft exists), Anna can confirm receipt")

section("An offline crafter gets the order when he comes online")
Logout("Bert Hill")
local bdb = B.db()
before = sentBy("Anna Stone", "o")
local o7 = A.GCA:PlaceOrder("Bert Hill", LW, 2163, 9)
advance(600)
check(sentBy("Anna Stone", "o") == before and o7.state == "requested", "Bert offline: nothing goes out for 10 minutes")
B = Login("Bert Hill", { db = bdb })
advance(30)
local ob7 = stored(B, o7)
check(ob7 and ob7.state == "requested" and sentBy("Anna Stone", "o") == before + 1, "Bert logs in: Anna sends it once, Bert has it")
check(stored(B, o6).state == "done" and stored(B, o5).state == "withdrawn", "Bert's earlier orders came back from his SavedVariables")

section("Orders survive a reload; an unacknowledged change is sent again")
bus.drop = function(sender, prefix, msg, to) return msg:match("^CO;") ~= nil and sender == "Anna Stone" and to.name == "Bert Hill" end
before = sentBy("Anna Stone", "o")
check(A.GCA:OrderAction(o7, "withdraw"), "Anna withdraws while Bert hears nothing")
advance(400)
local lostTries = sentBy("Anna Stone", "o") - before
check(lostTries == 3 and stored(B, o7).state == "requested", "Bert hears nothing: Anna tries 3 times, then waits (" .. lostTries .. ")")
bus.drop = function() return false end
local adb = A.db()
A = Login("Anna Stone", { db = adb })
advance(5)
local o7r = stored(A, o7)
check(o7r and o7r.state == "withdrawn" and stored(A, o6).state == "done" and stored(A, o).state == "received",
  "after the reload Anna still has every order and its state")
advance(60)
check(stored(B, o7).state == "withdrawn", "and the withdrawal reaches Bert after the reload")

section("Message budget: tries per state are bounded, also towards a client without orders")
Login("Bert Hill", { db = bdb, files = OLD_FILES })
advance(30)
before = sentBy("Anna Stone", "o")
local o8 = A.GCA:PlaceOrder("Bert Hill", LW, 2164, 2)
advance(1800)
local tries = sentBy("Anna Stone", "o") - before
check(tries == 3, "Bert runs an old version and never answers: 3 tries in 30 minutes (" .. tries .. ")")
Logout("Bert Hill")
Login("Bert Hill", { db = bdb, files = OLD_FILES })
advance(1800)
tries = sentBy("Anna Stone", "o") - before
check(tries == 6, "he logs in again: 3 more, never more per login (" .. tries .. ")")
check(bus:maxPer(60, "Anna Stone", { RQE1 = true }) <= 15, "within the core's send budget")
Logout("Bert Hill")
B = Login("Bert Hill", { db = bdb })
advance(60)
check(stored(B, o8) and stored(B, o8).state == "requested", "with the new version he gets it on his next login")

section("Finished orders age out, the store stays small")
local T = A.env.time()
local store = adb.guilds[A.RQ:GuildKey()].orders
local function aged(id, state, days)
  local rec = { id = id, requester = "Anna Stone", crafter = "Bert Hill", prof = LW, spell = VEST, state = state, t = T - days * 86400 }
  store[A.GCA.OrderKey("Anna Stone", id)] = rec
  return rec
end
aged(1, "received", 15); aged(2, "declined", 13); aged(3, "accepted", 31); aged(4, "requested", 29); aged(5, "done", 31)
store["Anna Stone#9"] = { id = "broken" }
A = Login("Anna Stone", { db = adb })
advance(5)
local ages = stored(A, { requester = "Anna Stone", id = 2 }) and stored(A, { requester = "Anna Stone", id = 4 })
  and not stored(A, { requester = "Anna Stone", id = 1 }) and not stored(A, { requester = "Anna Stone", id = 3 })
  and not stored(A, { requester = "Anna Stone", id = 5 }) and A.GCA:Orders()["Anna Stone#9"] == nil
check(ages, "login: finished > 14 days and open > 30 days removed, a damaged record too; younger ones kept")
store = A.GCA:Orders()
local n = 0
for _ in pairs(store) do n = n + 1 end
for i = n + 1, A.GCA.ORDER_MAX do aged(100 + i, "received", 1 + i / 1000) end
store[A.GCA.OrderKey("Anna Stone", 100 + A.GCA.ORDER_MAX)].t = T - 13.9 * 86400
local o9 = A.GCA:PlaceOrder("Dora Field", LW, VEST, 1)
n = 0
for _ in pairs(store) do n = n + 1 end
check(o9 and n == A.GCA.ORDER_MAX and store[A.GCA.OrderKey("Anna Stone", 100 + A.GCA.ORDER_MAX)] == nil,
  "at " .. A.GCA.ORDER_MAX .. " orders a new one replaces the oldest finished one (" .. n .. ")")
check(#A.errors == 0 and #B.errors == 0 and #Cc.errors == 0 and #D.errors == 0, "no Lua errors")
Kit.finish()
