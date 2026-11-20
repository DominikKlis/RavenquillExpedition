local Kit = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check

local EPOCH = 1800000000
local SV_NAMES = { "RavenquillExpeditionDB", "RavenquillExpeditionHighlightsDB", "RavenquillExpeditionHighlightsCharDB" }

local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end

local function Stubs(env)
  env.RAID_CLASS_COLORS = {}
  env.Enum = { QuestTag = {} }
  env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  env.C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end }
  function env.GetInventoryItemLink() end
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
  env.LOOT_ITEM_SELF, env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
  env.LOOT_ITEM, env.LOOT_ITEM_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d."
end

local function NewWorld()
  local sched, bus = Kit.Setup()
  local w = { sched = sched, bus = bus, seed = 0 }

  function w.join(name, sv, random)
    w.seed = w.seed + 1
    local c = Kit.Client(sched, bus, name, { guild = "Die Gilde", realm = "Forever", class = "MAGE", level = 40, epoch = EPOCH,
      random = random or Kit.Random(w.seed * 7919), addons = { "RavenquillExpedition_Highlights" },
      setup = function(env)
        Stubs(env)
        for k, v in pairs(sv or {}) do env[k] = Copy(v) end
      end })
    c.H = c.ns.RavenquillExpedition_Highlights.H
    bus:setOnline(name, true)
    c.login()
    c.H.db.settings.chat = true
    return c
  end

  function w.leave(c)
    c.fire("PLAYER_LOGOUT")
    c.online = false
    bus:setOnline(c.name, false)
  end

  function w.relays(sender, after)
    local out = {}
    for _, x in ipairs(bus.log) do
      local t, seq, who = x.msg:match("^H;1;R%a;(%d+);([^;]*);([^;]*);")
      if t and (not sender or x.sender == sender) and x.t >= (after or 0) then
        out[#out + 1] = ("%s#%s#%s"):format(who, t, seq)
      end
    end
    return out
  end

  function w.requests(sender, after)
    return bus:count(function(x) return x.sender == sender and x.t >= (after or 0) and x.msg:find("^H;1;r;") ~= nil end)
  end

  return w
end

local function Saved(c)
  local out = {}
  for _, k in ipairs(SV_NAMES) do out[k] = c.env[k] end
  return out
end

local function Entry(who, t, n, fields)
  local e = { k = "level", t = t, who = who, lvl = 10 + n, cls = "WARRIOR", id = ("%s#%d#%d"):format(who, t, n) }
  for k, v in pairs(fields or {}) do e[k] = v end
  return e
end

local function Series(who, from, n, step)
  local out = {}
  for i = 1, n do out[i] = Entry(who, from + i * (step or 60), i) end
  return out
end

local function Hold(c, list)
  for _, e in ipairs(list) do c.H:Add(Copy(e), "wire") end
end

local function Author(c, fields, opts)
  local t = c.env.time()
  local e = { k = "level", t = t, who = c.RQ:PlayerKey(), lvl = 40, cls = "MAGE" }
  for k, v in pairs(fields) do e[k] = v end
  e.id = e.id or c.H:NextID(e.who, t)
  return c.H:Add(e, "self", opts)
end

local function Inject(c, e)
  local typ, m = c.H.RelayMessage(e)
  c.H.channel:Send(typ, m)
end

local function Ids(c)
  local out = {}
  for _, e in ipairs((c.H:Log())) do out[#out + 1] = e.id end
  return out
end

local function IdsOf(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.id end
  return out
end

local function Same(got, want)
  local a, b = Copy(got), Copy(want)
  table.sort(a); table.sort(b)
  return table.concat(a, "\n") == table.concat(b, "\n"), table.concat(a, ", ")
end

local function Has(c, id)
  local _, idx = c.H:Log()
  return idx[id] ~= nil
end

local function Lines(c, needle)
  local n = 0
  for _, p in ipairs(c.printed) do if p.text:find(needle, 1, true) then n = n + 1 end end
  return n
end

local function EachOnce(list)
  local seen = {}
  for _, id in ipairs(list) do
    if seen[id] then return false end
    seen[id] = true
  end
  return true
end

Kit.section("A member back from offline gets what was shared meanwhile, also from an author who left")
do
  local w = NewWorld()
  w.bus:member("Dora Dunn", "PRIEST", 30, false)
  local bert = w.join("Bert Hill")
  local cara = w.join("Cara Moss")
  local anna = w.join("Anna Stone")
  w.sched:advance(60)
  local e0 = Author(cara, { lvl = 20 })
  w.sched:advance(60)
  check(Has(anna, e0.id), "setup: Anna hears Cara's first highlight live")
  local saved = Saved(anna)
  w.leave(anna)
  w.sched:advance(600)
  local e1 = Author(cara, { lvl = 21 })
  w.sched:advance(300)
  local e2 = Author(cara, { k = "boss", enc = 1084, boss = "Onyxia", inst = "Onyxias Hort", first = true })
  w.sched:advance(300)
  local lootAt = bert.env.time()
  local loot = bert.H:Add({ k = "loot", t = lootAt, who = "Dora Dunn", by = "Bert Hill", cls = "PRIEST", lvl = 30, item = 19019,
    q = 5, id = bert.H.WitnessID("Dora Dunn", 19019, lootAt) }, "witness", { group = true, rank = 0 })
  w.sched:advance(300)
  check(Has(bert, e1.id) and Has(bert, e2.id) and Has(bert, loot.id), "setup: Bert holds what Anna missed")
  w.leave(cara)
  w.sched:advance(600)

  local back = w.sched.t
  local anna2 = w.join("Anna Stone", saved)
  w.sched:advance(5)
  local b1 = Author(bert, { lvl = 41 })
  w.sched:advance(10)
  check(Has(anna2, b1.id), "setup: a live highlight arrives before Anna asks")
  w.sched:advance(400)

  local ok, got = Same(Ids(anna2), { e0.id, e1.id, e2.id, loot.id, b1.id })
  check(ok, "Anna's log ends with exactly the missed entries plus what she had: " .. got)
  check(w.requests("Anna Stone", back) == 1, "Anna asked once after logging back in")
  local _, idx = anna2.H:Log()
  check(idx[loot.id] and not anna2.H:Format(idx[loot.id]):find("seen by", 1, true),
    "a relayed witnessed loot keeps its id and claims no witness")
  check(Lines(anna2, "Caught up on 3 highlights from while you were away.") == 1 and Lines(anna2, "Caught up on") == 1,
    "one summary line counts the 3 new entries")
  check(Lines(anna2, "Cara Moss") == 0 and Lines(anna2, "Dora Dunn") == 0, "no chat line per relayed entry")
  local diag = table.concat(anna2.H:DiagLines(), "\n")
  check(diag:find("catch-up: asked 2, heard 2, relayed 0, accepted 4, rejected 0", 1, true) ~= nil,
    "diagnostics show the catch-up counts: " .. (diag:match("catch%-up:[^\n]*") or "-"))

  w.leave(bert)
  w.sched:advance(60)
  local ella = w.join("Ella Fox")
  w.sched:advance(400)
  ok, got = Same(Ids(ella), { e0.id, e1.id, e2.id, loot.id, b1.id })
  check(ok, "a first-time member gets everything from a holder who learned part of it by relay: " .. got)
  check(Lines(ella, "Caught up on 5 highlights") == 1, "her summary counts all 5")
end

Kit.section("Two holders online, answering seconds apart: each missing entry goes out once")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local missing = Series("Dave Rook", EPOCH - 3600, 12)
  local bert = w.join("Bert Hill", nil, function() return 0.8 end)
  local cara = w.join("Cara Moss", nil, function() return 0.2 end)
  Hold(bert, missing); Hold(cara, missing)
  w.sched:advance(300)
  local asked = w.sched.t
  local anna = w.join("Anna Stone")
  w.sched:advance(400)
  local relays = w.relays(nil, asked)
  check(#relays == 12 and EachOnce(relays), ("each of the 12 entries relayed exactly once (%d relays)"):format(#relays))
  check(#w.relays("Bert Hill", asked) == 0, "the holder whose turn came later stayed quiet, though the stream was still running")
  check(Same(Ids(anna), IdsOf(missing)), "Anna has all 12")
end

Kit.section("Two holders answering in the same second: the lower name keeps going, the other stops")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local missing = Series("Dave Rook", EPOCH - 3600, 6)
  local function same() return 0.5 end
  local bert = w.join("Bert Hill", nil, same)
  local cara = w.join("Cara Moss", nil, same)
  Hold(bert, missing); Hold(cara, missing)
  w.sched:advance(300)
  local asked = w.sched.t
  local anna = w.join("Anna Stone")
  w.sched:advance(400)
  local fromBert, fromCara = #w.relays("Bert Hill", asked), #w.relays("Cara Moss", asked)
  check(fromBert == 6 and fromCara >= 1 and fromCara <= 2,
    ("Bert relays all 6, Cara stops after her first ones (Bert %d, Cara %d)"):format(fromBert, fromCara))
  check(Same(Ids(anna), IdsOf(missing)), "Anna has all 6")
end

Kit.section("Back after a reload with nothing missed: nobody relays")
do
  local w = NewWorld()
  local bert = w.join("Bert Hill")
  local anna = w.join("Anna Stone")
  w.sched:advance(60)
  local b1 = Author(bert, { lvl = 41 })
  w.sched:advance(300)
  local b2 = Author(bert, { lvl = 42 })
  w.sched:advance(300)
  check(Has(anna, b1.id) and Has(anna, b2.id), "setup: Anna heard both live")
  local saved = Saved(anna)
  w.leave(anna)
  local back = w.sched.t
  local anna2 = w.join("Anna Stone", saved)
  w.sched:advance(400)
  check(w.requests("Anna Stone", back) == 1, "Anna asked after the reload")
  check(#w.relays() == 0, "no relay went out")
  check(Lines(anna2, "Caught up on") == 0, "no summary line")
end

Kit.section("Relays nobody asked for, or about strangers, are not stored; one relayer gets 20 per request")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local bert = w.join("Bert Hill")
  w.sched:advance(60)
  local anna = w.join("Anna Stone")
  w.sched:advance(3)
  local unasked = Entry("Dave Rook", EPOCH - 500, 1)
  Inject(bert, unasked)
  w.sched:advance(10)
  check(w.requests("Anna Stone") == 0, "setup: Anna has not asked yet")
  check(not Has(anna, unasked.id), "a relay before any request is not stored")
  w.sched:advance(60)
  check(w.requests("Anna Stone") == 1, "setup: Anna asked")
  local stranger = Entry("Zed Nobody", EPOCH - 400, 2)
  Inject(bert, stranger)
  local flood = Series("Dave Rook", EPOCH - 3000, 21, 10)
  for _, e in ipairs(flood) do Inject(bert, e) end
  w.sched:advance(400)
  check(not Has(anna, stranger.id), "a relay about someone outside the guild is not stored")
  local stored = 0
  for _, e in ipairs(flood) do if Has(anna, e.id) then stored = stored + 1 end end
  check(stored == 20, ("of 21 relays from one relayer for one request, 20 are stored (%d)"):format(stored))
end

Kit.section("30 entries missed: all 30 arrive in two pages; a member who did not ask stores none")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local missing = Series("Dave Rook", EPOCH - 7200, 30)
  local bert = w.join("Bert Hill")
  local cara = w.join("Cara Moss")
  w.sched:advance(700)
  Hold(bert, missing)
  local asked = w.sched.t
  local anna = w.join("Anna Stone")
  w.sched:advance(600)
  local ok, got = Same(Ids(anna), IdsOf(missing))
  check(ok, "Anna has all 30: " .. got)
  check(w.requests("Anna Stone", asked) == 2, ("Anna asked for two pages (%d)"):format(w.requests("Anna Stone", asked)))
  local relays = #w.relays(nil, asked)
  check(relays >= 30 and relays <= 31, ("%d relays on the wire: each entry once, the page boundary at most twice"):format(relays))
  check(#Ids(cara) == 0, ("Cara, online all along, stored none of the relays (%d)"):format(#Ids(cara)))
  check(Lines(cara, "Caught up on") == 0 and Lines(anna, "Caught up on 30 highlights") == 1,
    "only the member who asked gets the summary line, once, counting all 30")
end

Kit.section("120 entries missed: at most 5 pages, the newest entries without a hole")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local missing = Series("Dave Rook", EPOCH - 86400, 120, 300)
  local bert = w.join("Bert Hill")
  w.sched:advance(300)
  Hold(bert, missing)
  local asked = w.sched.t
  local anna = w.join("Anna Stone")
  w.sched:advance(1800)
  local has, oldest = #Ids(anna), nil
  for i = #missing, 1, -1 do
    if not Has(anna, missing[i].id) then break end
    oldest = i
  end
  check(w.requests("Anna Stone", asked) == 5, ("Anna asked for 5 pages and stopped (%d)"):format(w.requests("Anna Stone", asked)))
  check(oldest and has == #missing - oldest + 1 and has >= 90 and has <= 100,
    ("she has the newest %d without a hole (from #%s)"):format(has, tostring(oldest)))
  check(#w.relays(nil, asked) <= 100, ("%d relays on the wire"):format(#w.relays(nil, asked)))
end

Kit.section("Nobody online at login: the gap fills once a member who holds it comes online")
do
  local w = NewWorld()
  local bert = w.join("Bert Hill")
  local cara = w.join("Cara Moss")
  local anna = w.join("Anna Stone")
  w.sched:advance(120)
  local saved = Saved(anna)
  w.leave(anna)
  w.sched:advance(600)
  local e1 = Author(cara, { lvl = 21 })
  w.sched:advance(300)
  check(Has(bert, e1.id), "setup: Bert holds Cara's highlight that Anna missed")
  local bertSaved = Saved(bert)
  w.leave(cara); w.leave(bert)
  w.sched:advance(600)
  local back = w.sched.t
  local anna2 = w.join("Anna Stone", saved)
  w.sched:advance(900)
  check(w.requests("Anna Stone", back) == 0, "setup: alone online, Anna has nobody to ask")
  local bert2 = w.join("Bert Hill", bertSaved)
  w.sched:advance(120)
  local b1 = Author(bert2, { lvl = 41 })
  w.sched:advance(400)
  check(Has(anna2, b1.id), "setup: Anna hears Bert's new highlight live")
  check(Has(anna2, e1.id), "15 minutes after her login Bert comes online, and Anna gets the highlight she missed")
end

Kit.section("Only a member without the addon online, then a live highlight: the gap stays open until a holder answers")
do
  local w = NewWorld()
  w.bus:member("Dora Dunn", "PRIEST", 30, false)
  local bert = w.join("Bert Hill")
  local cara = w.join("Cara Moss")
  local anna = w.join("Anna Stone")
  w.sched:advance(300)
  local saved = Saved(anna)
  w.leave(anna)
  w.sched:advance(600)
  local e1 = Author(cara, { lvl = 21 })
  w.sched:advance(300)
  local bertSaved = Saved(bert)
  w.leave(cara); w.leave(bert)
  w.bus:setOnline("Dora Dunn", true)
  local back = w.sched.t
  local anna2 = w.join("Anna Stone", saved)
  w.sched:advance(400)
  check(w.requests("Anna Stone", back) == 1, "setup: Anna asked while only Dora, who has no addon, was online")
  local ella = w.join("Ella Fox")
  w.sched:advance(5)
  local e2 = Author(ella, { lvl = 30 })
  w.sched:advance(5)
  w.leave(ella)
  w.sched:advance(60)
  check(Has(anna2, e2.id) and not Has(anna2, e1.id), "setup: Anna heard Ella's newer highlight live, Cara's older one is missing")
  local saved2 = Saved(anna2)
  w.leave(anna2)
  w.sched:advance(300)
  w.join("Bert Hill", bertSaved)
  w.sched:advance(60)
  local anna3 = w.join("Anna Stone", saved2)
  w.sched:advance(600)
  check(Has(anna3, e1.id), "back with Bert online, Anna gets Cara's highlight from before Ella's")
end

Kit.section("A guildmate who repeats requests and forges relays: only a member who asked stores them, 20 at most")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local anna = w.join("Anna Stone")
  local mal = w.join("Mal Ory")
  w.sched:advance(700)
  local cara = w.join("Cara Moss")
  w.sched:advance(60)
  check(w.requests("Cara Moss") == 1, "setup: Cara asked")
  local forged = Series("Dave Rook", EPOCH - 6000, 100, 10)
  for round = 0, 4 do
    mal.H.channel:Send("r", { since = 0 })
    w.sched:advance(2)
    for i = 1, 20 do Inject(mal, forged[round * 20 + i]) end
    w.sched:advance(60)
  end
  w.sched:advance(120)
  check(w.requests("Mal Ory") == 6, ("setup: Mal sent 5 requests after his own (%d)"):format(w.requests("Mal Ory")))
  local function Stored(c)
    local n = 0
    for _, e in ipairs(forged) do if Has(c, e.id) then n = n + 1 end end
    return n
  end
  check(Stored(anna) == 0, ("Anna, who did not ask, stored none of the 100 (%d)"):format(Stored(anna)))
  check(Stored(cara) == 20, ("Cara, who asked, stored 20 of the 100 (%d)"):format(Stored(cara)))
end

Kit.section("A holder who does not share sends nothing")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local bert = w.join("Bert Hill")
  Hold(bert, Series("Dave Rook", EPOCH - 3600, 3))
  for _, o in ipairs(bert.H.options) do if o.key == "share" then o.set(false) end end
  w.sched:advance(60)
  local anna = w.join("Anna Stone")
  w.sched:advance(400)
  check(w.requests("Anna Stone") == 1, "setup: Anna asked")
  check(#w.relays() == 0 and #Ids(anna) == 0, "no relay, nothing stored")
end

Kit.section("Own entries kept local (share off, local only) or waiting for the hourly cap are not relayed, also after a reload")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local bert = w.join("Bert Hill")
  w.sched:advance(60)
  local heard = Entry("Dave Rook", EPOCH - 600, 1)
  Hold(bert, { heard })
  local s = bert.H.db.settings
  local hour = {}
  for i = 1, 9 do hour[i] = Author(bert, { lvl = 40 + i }) end
  s.share = false
  local kept = { Author(bert, { lvl = 50 }) }
  s.share = true
  kept[2] = Author(bert, { lvl = 51 }, { localOnly = true })
  w.sched:advance(120)
  local waiting = {}
  for id in pairs(bert.H.cdb.outbox) do waiting[#waiting + 1] = id end
  check(#waiting == 1, ("setup: 8 of Bert's 9 highlights of the hour went out, %d waits"):format(#waiting))
  local saved = Saved(bert)
  w.leave(bert)
  local bert2 = w.join("Bert Hill", saved)
  w.sched:advance(60)
  check(Has(bert2, waiting[1]) and Has(bert2, kept[1].id) and Has(bert2, kept[2].id), "setup: the kept entries stay in Bert's log")
  local asked = w.sched.t
  local anna = w.join("Anna Stone")
  w.sched:advance(400)
  check(w.requests("Anna Stone") == 1, "setup: Anna asked")
  local want = { heard.id }
  for _, e in ipairs(hour) do if e.id ~= waiting[1] then want[#want + 1] = e.id end end
  local ok, got = Same(w.relays("Bert Hill", asked), want)
  check(ok, "Bert relays the entries he shared and heard, none he kept local or that still waits: " .. got)
  ok, got = Same(Ids(anna), want)
  check(ok, "Anna stores exactly those: " .. got)
  w.sched:advance(3600)
  want[#want + 1] = waiting[1]
  ok, got = Same(Ids(anna), want)
  check(ok, "the one that waited reaches Anna once the hour is over, the local ones never: " .. got)
end

Kit.section("Test entries are never relayed and never crowd out real ones")
do
  local w = NewWorld()
  w.bus:member("Dave Rook", "WARRIOR", 50, false)
  local real = Series("Dave Rook", EPOCH - 7200, 20)
  local bert = w.join("Bert Hill")
  Hold(bert, real)
  check(bert.H:AddTests() == 11, "setup: Bert has 11 test entries newer than the real ones")
  w.sched:advance(60)
  local anna = w.join("Anna Stone")
  w.sched:advance(600)
  local ok, got = Same(Ids(anna), IdsOf(real))
  check(ok, "Anna gets the 20 real entries and no test entry: " .. got)
  local tests = 0
  for _, id in ipairs(w.relays()) do if id:find("TEST", 1, true) then tests = tests + 1 end end
  check(tests == 0 and #w.relays() >= 20 and #w.relays() <= 21,
    ("only the 20 real entries went out, the page boundary at most twice (%d relays)"):format(#w.relays()))
end

Kit.finish()
