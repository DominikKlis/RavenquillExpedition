local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local RECORD = arg[1] == "--record"
local Golden = dofile(Kit.ADDONS .. "RavenquillExpedition/dev/golden.lua")
local gold = Golden.open(DEV .. "fixtures/compat_golden.lua", RECORD)

local GEAR = dofile(DEV .. "fixtures/gear_sets.lua")
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

local GUILD = {
  { name = "Anna Stone", class = "ROGUE", level = 36 },
  { name = "Bert Hill", class = "DRUID", level = 35 },
  { name = "Cora Vale", class = "HUNTER", level = 31 },
  { name = "Dora Field", class = "WARRIOR", level = 35 },
}
local GUILD_BY = {}
for _, g in ipairs(GUILD) do GUILD_BY[g.name] = g end

local clients = {}
local sched, bus
local function NewWorld()
  sched = Kit.Scheduler({ start = sched and sched.t or 0, trap = true })
  bus = Kit.Bus(sched)
  bus.latency = 0.2
end
NewWorld()

local Files = dofile(DEV .. "files.lua")
local CA = "RavenquillExpedition_CraftAdvisor"
local FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua",
  "RecipeSources.lua", "UI" } }))
local LEGACY = Files.kitFiles({ "Data/Leatherworking.lua", "dev/fixtures/compat_0.2.0/Core.lua", "dev/fixtures/compat_0.2.0/Sync.lua" })

local function NewClient(name, gear, opts)
  opts = opts or {}
  local first, surname = name:match("^(%S+) (%S+)$")
  local g = GUILD_BY[name]
  local c = Kit.Client(sched, bus, name, { class = g.class, level = g.level, epoch = 1800000000, random = Kit.Random(opts.seed or #name),
    noCore = opts.files ~= nil, files = opts.files or FILES, setup = function(env, kc)
      kc.gear = gear
      env.GetNumSubgroupMembers = function() return 0 end
      local function U(u)
        if u == "player" then return { first = first, surname = surname, class = g.class, level = g.level, guid = "G-" .. name, items = kc.gear } end
      end
      env.UnitName = function(u) local x = U(u); if x then return x.first, x.surname end end
      env.UnitNameUnmodified = env.UnitName
      env.UnitClass = function(u) local x = U(u); if x then return x.class, x.class end end
      env.UnitLevel = function(u) local x = U(u); return x and x.level end
      env.UnitGUID = function(u) local x = U(u); return x and x.guid end
      env.UnitIsPlayer = function(u) return U(u) ~= nil end
      env.UnitIsUnit = function(a, b) local x, y = U(a), U(b); return x ~= nil and y ~= nil and x.guid == y.guid end
      env.UnitIsInMyGuild = function(u) return U(u) ~= nil end
      env.CanInspect = function() return true end
      env.NotifyInspect = function() end
      env.GetInventoryItemLink = function(u, slot) local x = U(u); return x and x.items and x.items[slot] end
      env.GetNumGuildMembers = function() return #GUILD end
      env.GetGuildRosterInfo = function(i)
        local m = GUILD[i]
        return m.name, "Member", 1, m.level, m.class, "Zone", "", "", clients[m.name] ~= nil, 0, m.class
      end
      env.C_GuildInfo = { GuildRoster = function() end }
      env.C_Item = { GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end,
        GetItemStats = function() return {} end }
      env.C_SpellBook = { IsSpellKnown = function() return false end }
      local send = env.C_ChatInfo.SendAddonMessage
      env.C_ChatInfo.SendAddonMessage = function(prefix, msg, chan)
        assert(#msg <= 255, "message over 255 bytes: " .. #msg)
        assert(chan == "GUILD", "non-GUILD send: " .. tostring(chan))
        return send(prefix, msg, chan)
      end
      env.RavenquillExpeditionCraftDB = {}
    end })
  c.GCA = c.ns[CA].GCA
  c.setDB = function(db) c.env.RavenquillExpeditionCraftDB = db end
  c.getDB = function() return c.env.RavenquillExpeditionCraftDB end
  return c
end

local function Login(name, gear, opts)
  local c = NewClient(name, gear, opts)
  clients[name] = c
  c.login()
  return c
end
section("Encoder layer: EncodeRecord / EncodeItem are byte-identical")
local A = Login("Anna Stone", copy(GEAR[1]))
local GCA = A.GCA
local items, records = {}, {}
for i, set in ipairs(GEAR) do
  local slots = {}
  for slot in pairs(set) do slots[#slots + 1] = slot end
  table.sort(slots)
  for _, slot in ipairs(slots) do items[#items + 1] = tostring(GCA:EncodeItem(set[slot])) end
  local m = { items = set, class = "HUNTER", level = 35, ts = 1800000000 + i }
  for _, subj in ipairs({ "", "Dora Field" }) do
    local chunks = GCA:EncodeRecord(m, subj) or { "<nil>" }
    for _, msg in ipairs(chunks) do records[#records + 1] = msg end
  end
end
gold:compare("ca.items", items, check)
gold:compare("ca.records", records, check)

section("Decoder layer: golden G messages give the original gear back")
local goldRecords = RECORD and records or (gold.data["ca.records"] or {})
local B = Login("Bert Hill", copy(GEAR[2]))
local okSets = 0
for i, set in ipairs(GEAR) do
  B.GCA.db.members["Cora Vale"] = nil
  B.GCA.db.members["Dora Field"] = nil
  for _, msg in ipairs(goldRecords) do
    local ts = msg:match("^G;[^;]*;[^;]*;[^;]*;([^;]*);")
    if ts == GCA.b36(1800000000 + i) then
      B.fire("CHAT_MSG_ADDON", "GCAdv1", msg, "GUILD", msg:match("^G;;") and "Cora Vale" or "Anna Stone")
      B.RQ.Comm.intake = {}
    end
  end
  local own, relay = B.GCA.db.members["Cora Vale"], B.GCA.db.members["Dora Field"]
  if own and relay and B.GCA:GearSignature(own.items) == B.GCA:GearSignature(set)
    and B.GCA:GearSignature(relay.items) == B.GCA:GearSignature(set) then okSets = okSets + 1 end
end
check(okSets == #GEAR, ("%d/%d sets decoded from the golden messages (own and relay)"):format(okSets, #GEAR))

section("Compat layer: a 0.2.0 client understands the golden messages")
local K = Login("Cora Vale", copy(GEAR[3]), { files = LEGACY })
local okOld = 0
for i, set in ipairs(GEAR) do
  K.GCA.db.members["Dora Field"] = nil
  for _, msg in ipairs(goldRecords) do
    if msg:match("^G;Dora Field;") and msg:match("^G;[^;]*;[^;]*;[^;]*;([^;]*);") == GCA.b36(1800000000 + i) then
      K.fire("CHAT_MSG_ADDON", "GCAdv1", msg, "GUILD", "Anna Stone")
      K.GCA.Sync.intake = {}
    end
  end
  local r = K.GCA.db.members["Dora Field"]
  if r and K.GCA:GearSignature(r.items) == K.GCA:GearSignature(set) then okOld = okOld + 1 end
end
check(okOld == #GEAR, ("0.2.0 client stored %d/%d relayed sets"):format(okOld, #GEAR))

section("Scenario layer: two clients log in (time stamps masked)")
for name, c in pairs(clients) do c.online = false; clients[name] = nil end
NewWorld()
local t0 = sched.t
Login("Anna Stone", copy(GEAR[1]), { seed = 7 })
sched:advance(5)
Login("Bert Hill", copy(GEAR[2]), { seed = 11 })
sched:advance(900)
local seen = {}
for _, e in ipairs(bus.log) do
  local f = { Kit.strsplit(";", e.msg) }
  if f[1] == "G" then f[5] = "<ts>" elseif f[1] == "S" then f[3] = "<ts>" end
  seen[#seen + 1] = ("%s|%s"):format(e.sender, table.concat(f, ";"))
end
check(#seen > 0, ("scenario sent %d messages in %d s"):format(#seen, sched.t - t0))
gold:compare("ca.scenario", seen, check)

section("SavedVariables layer: old shapes load into the same tables as before")
local function splitLines(s) local out = {} for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end return out end
local SV_CASES = {
  fresh = {},
  noFlags = { members = { ["Dora Field"] = { time = 5, class = "WARRIOR", level = 35, items = {} } },
    settings = { inspectTalents = true }, known = { ["Anna-Realm"] = { 2149 } } },
  keysV1 = { members = { ["Dora-Field"] = { time = 5, items = {} }, ["Dora Field"] = { time = 3, items = {} },
    ["Emil-Brook"] = { time = 9, items = {} } } },
  keysV2Done = { keysV2 = true, inspectTalentsOffV1 = true, members = { ["Odd-Name"] = { time = 1 } },
    settings = { inspectTalents = true } },
  autoTargetOff = { settings = { autoTarget = false } },
}
for _, name in ipairs({ "fresh", "noFlags", "keysV1", "keysV2Done", "autoTargetOff" }) do
  for n, c in pairs(clients) do c.online = false; clients[n] = nil end
  NewWorld()
  local c = NewClient("Anna Stone", copy(GEAR[1]))
  clients["Anna Stone"] = c
  c.setDB(SV_CASES[name])
  c.fire("ADDON_LOADED", "RavenquillExpedition")
  c.fire("ADDON_LOADED", CA)
  c.fire("PLAYER_LOGIN")
  local db, shown = c.getDB(), {}
  for k, v in pairs(db) do if k ~= "v" and k ~= "vLogin" then shown[k] = v end end
  check(db.v == 3 and db.vLogin == 2, "sv." .. name .. ": core migration counters v = 3, vLogin = 2")
  gold:compare("sv." .. name, splitLines(Golden.Serialize(shown)), check)
end

section("Orders layer: order messages and the saved order stay byte-identical")
local orderGold = Golden.open(DEV .. "fixtures/compat_orders.lua", arg[1] == "--record-orders")
for n, c in pairs(clients) do c.online = false; clients[n] = nil end
NewWorld()
local OA = Login("Anna Stone", copy(GEAR[1]))
local OB = Login("Bert Hill", copy(GEAR[2]))
for _, c in pairs(clients) do c.fire("GUILD_ROSTER_UPDATE") end
sched:advance(60)
local och = OA.GCA.orderChannel
local fixed = { requester = "Anna Stone", id = 1800000123, crafter = "Bert Hill", line = 165, spell = 3762 }
local function with(state, gain)
  local m = {}
  for k, v in pairs(fixed) do m[k] = v end
  m.state, m.gain = state, gain
  return m
end
local encoded = { och:Encode("o", with("requested", 18)), och:Encode("o", with("accepted")), och:Encode("o", with("received", 9999)),
  och:Encode("k", { requester = "Anna Stone", id = 1800000123, state = "done" }) }
orderGold:compare("orders.wire", encoded, check)
local mark = #bus.log
local oa = OA.GCA:PlaceOrder("Bert Hill", "Leatherworking", 3762, 18)
sched:advance(30)
local ob = OB.GCA:Orders()[OB.GCA.OrderKey("Anna Stone", oa.id)]
OB.GCA:OrderAction(ob, "accept"); sched:advance(30)
OB.GCA:OrderAction(ob, "done"); sched:advance(30)
OA.GCA:OrderAction(oa, "receive"); sched:advance(30)
local lifecycle = {}
for i = mark + 1, #bus.log do
  local e = bus.log[i]
  if e.msg:match("^CO;") then lifecycle[#lifecycle + 1] = e.sender .. "|" .. e.msg:gsub(OA.GCA.b36(oa.id), "<id>") end
end
orderGold:compare("orders.lifecycle", lifecycle, check)
local function savedOrders(c)
  local shown = {}
  for key, rec in pairs(c.getDB().guilds[c.RQ:GuildKey()].orders) do
    local copyRec = {}
    for k, v in pairs(rec) do copyRec[k] = v end
    copyRec.t, copyRec.id = "<t>", "<id>"
    shown[(key:gsub("#%d+$", "#<id>"))] = copyRec
  end
  return splitLines(Golden.Serialize(shown))
end
orderGold:compare("orders.sv.requester", savedOrders(OA), check)
orderGold:compare("orders.sv.crafter", savedOrders(OB), check)
local goldWire = orderGold.data["orders.wire"] or encoded
local OC = Login("Cora Vale", copy(GEAR[3]))
OC.fire("CHAT_MSG_ADDON", "RQE1", goldWire[1], "GUILD", "Anna Stone-Realm")
local heard = OC.GCA.heardOrders[OC.GCA.OrderKey("Anna Stone", 1800000123)]
check(heard and heard.crafter == "Bert Hill" and heard.prof == "Leatherworking" and heard.spell == 3762 and heard.state == "requested"
  and heard.gain == 18, "the golden 'requested' message decodes to the same order")
orderGold:finish()

gold:finish()
Kit.finish()
