local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section

local realSets, allLinks, seen = {}, {}, {}
for i, items in ipairs(dofile(ROOT .. "dev/fixtures/gear_sets.lua")) do
  realSets[#realSets + 1] = { key = ("Member%02d"):format(i), items = items }
  for _, l in pairs(items) do if not seen[l] then seen[l] = true; allLinks[#allLinks + 1] = l end end
end
table.sort(realSets, function(a, b) return a.key < b.key end)
table.sort(allLinks)
local function setSize(items) local n, b = 0, 0 for _, l in pairs(items) do n = n + 1; b = b + #l end return n * 1000 + b end
table.sort(realSets, function(a, b) return setSize(a.items) > setSize(b.items) end)
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
local function withViewer(items, lvl)
  local o = {}
  for k, l in pairs(items) do o[k] = (l:gsub("(item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:)36:", "%1" .. lvl .. ":")) end
  return o
end
local GEAR = {}
for i, s in ipairs(realSets) do GEAR[i] = s.items end
io.write(("fixtures: %d real gear sets, %d distinct links\n"):format(#realSets, #allLinks))

local sched = Kit.Scheduler({ trap = true })
local function advance(sec) sched:advance(sec) end

local GUILD = {
  { name = "Anna Stone", class = "ROGUE", level = 36 },
  { name = "Bert Hill", class = "DRUID", level = 35 },
  { name = "Cora Vale", class = "HUNTER", level = 31 },
  { name = "Dora Field", class = "WARRIOR", level = 35 },
  { name = "Emil Brook", class = "MAGE", level = 33 },
  { name = "Finn Moor", class = "PRIEST", level = 34 },
  { name = "Gina Reed", class = "SHAMAN", level = 32 },
}
local GUILD_BY = {}
for _, g in ipairs(GUILD) do GUILD_BY[g.name] = g end

local clients = {}
local bus = Kit.Bus(sched)
bus.latency = 0.2
local sendResult

local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua", "RecipeSources.lua", "UI" } }))

local LegacyFrame = {}
LegacyFrame.__index = LegacyFrame
function LegacyFrame:SetScript(ev, fn) self._scripts[ev] = fn end
function LegacyFrame:RegisterEvent(ev) self._events[ev] = true end
function LegacyFrame:UnregisterEvent(ev) self._events[ev] = nil end

local function NewClient(name, gear, db, opts)
  opts = opts or {}
  local first, surname = name:match("^(%S+) (%S+)$")
  local g = GUILD_BY[name]
  local c = Kit.Client(sched, bus, name, { class = g.class, level = g.level, files = opts.files and Files.kitFiles(opts.files) or FILES,
    noCore = opts.files ~= nil, epoch = 1800000000,
    random = math.random, setup = function(env, kc)
    kc.gear, kc.units, kc.rosterReady = gear, {}, opts.rosterReady ~= false
    env.GetNumSubgroupMembers = function() return 0 end
    local function U(u)
      if u == "player" then return { first = first, surname = surname, class = g.class, level = kc.level or g.level, guid = "G-" .. name, items = kc.gear } end
      return kc.units[u]
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
    env.GetNumGuildMembers = function() return kc.rosterReady and #GUILD or 0 end
    env.GetGuildRosterInfo = function(i)
      local m = GUILD[i]
      if not m then return end
      local online = clients[m.name] and clients[m.name].online or (m.name:match("^[DEFG]") ~= nil)
      return m.name, "Member", 1, m.level, m.class, "Zone", "", "", online, 0, m.class
    end
    env.C_GuildInfo = { GuildRoster = function() end }
    env.C_Item = {
      GetItemInfoInstant = function() return nil end,
      GetItemInfo = function() return nil end,
      GetItemStats = function() return {} end,
    }
    env.C_SpellBook = { IsSpellKnown = function() return false end }
    if opts.knownSpells then
      env.IsPlayerSpell = function(id) for _, k in ipairs(opts.knownSpells) do if k == id then return true end end return false end
    end
    if opts.talents then
      kc.talents = opts.talents
      env.C_ClassTalents = { GetActiveConfigID = function() return 7 end }
      env.C_Traits = {
        GetConfigInfo = function(id) if id == 7 then return { treeIDs = { 70 } } end end,
        GetTreeNodes = function() local ids = {} for i in ipairs(kc.talents) do ids[i] = i end return ids end,
        GetNodeInfo = function(_, i) local n = kc.talents[i]; if n then return { posX = n[1], ranksPurchased = n[2] } end end,
      }
    end
    local send = env.C_ChatInfo.SendAddonMessage
    env.C_ChatInfo.SendAddonMessage = function(prefix, msg, chan)
      assert(#msg <= 255, "message over 255 bytes: " .. #msg)
      assert(chan == "GUILD", "non-GUILD send: " .. tostring(chan))
      if sendResult then local r = sendResult(msg, kc); if r ~= nil and r ~= 0 then return r end end
      return send(prefix, msg, chan)
    end
    env.RavenquillExpeditionCraftDB = db
    if opts.files then kc.newFrame = function() return setmetatable({ _scripts = {}, _events = {} }, LegacyFrame) end end
  end })
  local ns = c.ns[CA]
  c.GCA = ns.GCA
  c.S = ns.GCA.Sync
  c.C = ns.GCA.SyncConst
  return c
end

local function Login(name, gear, db, opts)
  if clients[name] then clients[name].online = false end
  local c = NewClient(name, gear, db or {}, opts)
  clients[name] = c
  c.login()
  return c
end
local function Logout(c) c.online = false end

local function rec(c, key) return c.GCA.db.members[key] end
local function sameGear(a, b, GCA) return GCA:GearSignature(a) == GCA:GearSignature(b) end
local function busSince(t0, pred) return bus:count(function(e) return e.t >= t0 and pred(e) end) end

section("Encoding: every real link round-trips; real sets fit")
local A = Login("Anna Stone", copy(GEAR[1]))
local GCA = A.GCA
local bad = 0
for _, l in ipairs(allLinks) do
  local e = GCA:EncodeItem(l)
  local d = e and GCA:DecodeItem(e)
  if not d or GCA:NormItem(d) ~= GCA:NormItem(l) then bad = bad + 1; print("    round trip failed: " .. l) end
end
check(bad == 0, ("%d/%d real links round-trip losslessly"):format(#allLinks - bad, #allLinks))
check(GCA:NormItem("item:10406::::::::36:1488::1:1:12721:1:28:5242") == GCA:NormItem("item:10406::::::::40:1488::1:1:12721:1:28:5242"),
  "viewer level (field 9) ignored by NormItem")
check(GCA:NormItem("|cnIQ3:|Hitem:10406::::::::36:1488::1:1:12721:1:28:5242:::::|h[X]|h|r") ==
  "10406:::::::::::1:1:12721:1:28:5242", "NormItem of a full hyperlink")
check(GCA:NormItem("item:10406::::::::36:1488::1:1:12721") ~= GCA:NormItem("item:10406::::::::36:1488:::1:12751"),
  "different random-suffix bonus = different item")
local maxChunks, maxLen = 0, 0
for _, s in ipairs(realSets) do
  for _, subj in ipairs({ "", "Ängis Waldbach-Langername" }) do
    local m = { items = s.items, class = "HUNTER", level = 35, ts = 1800000000 }
    local chunks = GCA:EncodeRecord(m, subj)
    maxChunks = math.max(maxChunks, #chunks)
    for _, msg in ipairs(chunks) do maxLen = math.max(maxLen, #msg) end
  end
end
check(maxChunks <= 4 and maxLen <= 255, ("real sets: max %d chunks, longest message %d bytes"):format(maxChunks, maxLen))
local longest = copy(allLinks); table.sort(longest, function(a, b) return #a > #b end)
local worstSet = {}
for i, slot in ipairs(GCA.SYNC_SLOTS) do worstSet[slot] = (longest[i] or longest[1]):gsub("item:(%d+):(%d*):", "item:%1:8483:") end
local wc = GCA:EncodeRecord({ items = worstSet, class = "HUNTER", level = 35, ts = 1800000000 }, "Ängis Waldbach")
check(wc and #wc <= 6, "worst-case 17-slot set encodes in " .. (wc and #wc or "nil") .. " chunks (limit 6)")

section("Login: first player alone sends only Q; no gear without listeners")
advance(60)
check(bus:count(function(e) return e.sender == "Anna Stone" and e.msg:sub(1, 2) == "Q;" end) == 1, "Anna sent one Q")
check(bus:count(function(e) return e.sender == "Anna Stone" and e.msg:sub(1, 2) == "G;" end) == 0, "Anna sent no gear (nobody listening)")
check(A.S.echoSeen ~= nil, "Anna saw her own echo")

section("Second login: Bert gets Anna's gear, Anna gets Bert's")
advance(240)
local B = Login("Bert Hill", copy(GEAR[2]))
advance(120)
check(rec(B, "Anna Stone") and sameGear(rec(B, "Anna Stone").items, GEAR[1], B.GCA), "Bert has Anna's gear")
check(rec(A, "Bert Hill") and sameGear(rec(A, "Bert Hill").items, GEAR[2], A.GCA), "Anna has Bert's gear")
check(rec(B, "Anna Stone") and rec(B, "Anna Stone").source == "self", "stored as self-reported")

section("Third login within 10 min (F#2): Cora still gets both")
advance(60)
local t0 = sched.t
local Cc = Login("Cora Vale", copy(GEAR[3]))
advance(150)
check(rec(Cc, "Anna Stone") and rec(Cc, "Bert Hill"), "Cora has Anna's and Bert's gear")
check(rec(A, "Cora Vale") and rec(B, "Cora Vale"), "Anna and Bert have Cora's gear")
local annaSelf = busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;;") and e.msg:match(";1/%d;") end)
check(annaSelf == 1, "Anna answered with exactly one broadcast (" .. annaSelf .. ")")

section("Repeated Qs are absorbed by one pending answer")
advance(600)
t0 = sched.t
A.fire("CHAT_MSG_ADDON", "GCAdv1", "Q;2", "GUILD", "Bert Hill")
advance(2)
A.fire("CHAT_MSG_ADDON", "GCAdv1", "Q;2", "GUILD", "Cora Vale")
advance(120)
annaSelf = busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;;") and e.msg:match(";1/%d;") end)
check(annaSelf == 1, "two Qs -> one broadcast (" .. annaSelf .. ")")

section("Own gear change is broadcast (debounced) and replaces older data")
advance(200)
t0 = sched.t
local oldTs = rec(B, "Anna Stone").ts
A.gear[5] = GEAR[4][5] or GEAR[2][5]
A.fire("PLAYER_EQUIPMENT_CHANGED")
advance(10)
check(busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;;") end) == 0, "not sent before the 20 s debounce")
advance(120)
check(rec(B, "Anna Stone").ts > oldTs and sameGear(rec(B, "Anna Stone").items, A.gear, B.GCA), "Bert has Anna's new gear")
check(sameGear(rec(Cc, "Anna Stone").items, A.gear, Cc.GCA), "Cora has Anna's new gear")

section("Gear change inside an instance is sent after leaving (F#3)")
advance(200)
A.instance = true
A.fire("PLAYER_ENTERING_WORLD", false, false)
A.gear[8] = GEAR[3][8] or GEAR[2][8]
A.fire("PLAYER_EQUIPMENT_CHANGED")
t0 = sched.t
advance(200)
check(busSince(t0, function(e) return e.sender == "Anna Stone" end) == 0, "nothing sent from the instance")
A.instance = false
A.fire("PLAYER_ENTERING_WORLD", false, false)
advance(120)
check(sameGear(rec(B, "Anna Stone").items, A.gear, B.GCA), "sent after leaving the instance")

section("Inspect: viewer level doesn't count as a change (F#1); partial read; lost unit (F#7)")
advance(200)
local doraGear = copy(GEAR[4])
local function inspect(c, uname, items, opts)
  local g = GUILD_BY[uname]
  local f, s = uname:match("^(%S+) (%S+)$")
  c.units.target = { first = f, surname = s, class = g.class, level = g.level, guid = "G-" .. uname, items = items }
  c.GCA:OnInspectReady("G-" .. uname)
  if opts and opts.loseAt then advance(opts.loseAt); c.units.target = nil end
  advance(2)
  c.units.target = nil
end
local relaysBefore = bus:count(function(e) return e.sender == "Anna Stone" and e.msg:match("^G;Dora") end)
inspect(A, "Dora Field", doraGear)
local doraTs = rec(A, "Dora Field") and rec(A, "Dora Field").ts
check(doraTs ~= nil and rec(A, "Dora Field").source == "inspect", "Dora stored from inspect")
advance(5)
A.level = 40
inspect(A, "Dora Field", withViewer(doraGear, 40))
check(rec(A, "Dora Field").ts == doraTs, "re-inspect after level-up: same ts (no change)")
local partial = {}
local n = 0
for k, v in pairs(doraGear) do n = n + 1; if n <= 3 then partial[k] = v end end
inspect(A, "Dora Field", partial)
check(rec(A, "Dora Field").ts == doraTs, "partial read of the same gear: no change")
local cnt = 0 for _ in pairs(rec(A, "Dora Field").items) do cnt = cnt + 1 end
check(cnt == n, "partial read didn't shrink the stored set")
advance(5)
inspect(A, "Emil Brook", copy(GEAR[1]), { loseAt = 0.7 })
check(rec(A, "Emil Brook") ~= nil, "target lost before the final pass: still stored")
advance(400)
local relaysDora = bus:count(function(e) return e.sender == "Anna Stone" and e.msg:match("^G;Dora Field;") and e.msg:match(";1/%d;") end) - relaysBefore
check(relaysDora == 1, "Dora relayed once (" .. relaysDora .. ")")
check(rec(B, "Dora Field") and rec(B, "Dora Field").from == "Anna Stone", "Bert has Dora via Anna")

section("Group scan: 3 inspects in a row -> 3 relays, one per ~60 s (F#5)")
advance(100)
t0 = sched.t
inspect(A, "Finn Moor", copy(GEAR[2]))
inspect(A, "Gina Reed", copy(GEAR[3]))
GUILD_BY["Emil Brook"].level = 33
inspect(A, "Emil Brook", copy(GEAR[4]))
advance(30)
check(busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;%a") and e.msg:match(";1/%d;") end) <= 1, "not all at once")
advance(300)
check(rec(B, "Finn Moor") and rec(B, "Gina Reed") and rec(B, "Emil Brook") and sameGear(rec(B, "Emil Brook").items, GEAR[4], B.GCA),
  "Bert got all three relays")
check(busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;%a") and e.msg:match(";1/%d;") end) == 3, "exactly 3 relays")

section("Relay cancel: someone else relays the same subject first")
advance(30)
local dora2 = copy(GEAR[1])
inspect(A, "Gina Reed", copy(GEAR[1]))
inspect(B, "Dora Field", dora2)
inspect(A, "Dora Field", withViewer(dora2, 40))
t0 = sched.t
advance(400)
local annaDora = busSince(t0, function(e) return e.sender == "Anna Stone" and e.msg:match("^G;Dora Field;") end)
local bertDora = busSince(t0 - 5, function(e) return e.sender == "Bert Hill" and e.msg:match("^G;Dora Field;") end)
check(bertDora >= 1 and annaDora == 0, ("Bert relayed Dora (%d msgs), Anna cancelled hers (%d msgs)"):format(bertDora, annaDora))
check(sameGear(rec(Cc, "Dora Field").items, dora2, Cc.GCA), "Cora has Dora's new gear")

section("Lost chunk: record not applied; applied on the next broadcast")
advance(200)
local cora0 = rec(Cc, "Bert Hill").ts
bus.drop = function(sender, _, msg, to) return sender == "Bert Hill" and to.name == "Cora Vale" and msg:match("^G;;.-;2/%d;") ~= nil end
B.gear[1] = GEAR[1][1] or GEAR[3][1]; B.gear[3] = GEAR[3][3] or GEAR[1][3]
B.fire("PLAYER_EQUIPMENT_CHANGED")
advance(200)
check(rec(Cc, "Bert Hill").ts == cora0, "Cora didn't apply Bert's record with a missing chunk")
check(rec(A, "Bert Hill").ts > cora0, "Anna (no loss) applied it")
bus.drop = function() return false end
B.fire("CHAT_MSG_ADDON", "GCAdv1", "Q;2", "GUILD", "Cora Vale")
advance(200)
check(rec(Cc, "Bert Hill").ts > cora0, "applied on the next broadcast")

section("Throttled sends (result 3/8) are held and sent whole")
advance(200)
local throttles = 0
sendResult = function(_, c) if c == A and throttles < 3 then throttles = throttles + 1; return 3 end end
A.gear[10] = GEAR[2][10] or GEAR[3][10]
A.fire("PLAYER_EQUIPMENT_CHANGED")
advance(400)
sendResult = nil
check(throttles == 3 and sameGear(rec(B, "Anna Stone").items, A.gear, B.GCA), "after 3 throttles the record arrives whole")

section("Merge rules")
local M = Cc.GCA
local base = M:Now()
M.db.members["Finn Moor"] = { items = copy(GEAR[1]), ts = base, source = "self", class = "PRIEST", level = 34 }
check(not M:ApplyRecord("Bert Hill", { subject = "Finn Moor", class = "PRIEST", level = 34, ts = base - 10, items = copy(GEAR[2]) }), "older relay rejected")
check(not M:ApplyRecord("Bert Hill", { subject = "Finn Moor", class = "PRIEST", level = 34, ts = base, items = copy(GEAR[2]) }), "same-age inspect doesn't beat self")
check(M:ApplyRecord("Bert Hill", { subject = "Finn Moor", class = "PRIEST", level = 34, ts = base + 10, items = copy(GEAR[2]) }), "newer relay wins")
check(M:ApplyRecord("Finn Moor", { subject = "", class = "PRIEST", level = 34, ts = base + 10, items = copy(GEAR[3]) }), "same-age self beats inspect")
check(not M:ApplyRecord("Bert Hill", { subject = "Cora Vale", class = "HUNTER", level = 31, ts = base + 99, items = {} }), "record about ourselves rejected")
check(not M:ApplyRecord("Bert Hill", { subject = "Stranger Danger", class = "HUNTER", level = 31, ts = base + 99, items = {} }), "relayed non-guildie rejected")
local now0 = M:Now()
M.db.members["Gina Reed"] = { items = copy(GEAR[1]), ts = now0 - 50, time = Cc.env.time(), source = "self", class = "SHAMAN", level = 32 }
check(not M:ApplyRecord("Bert Hill", { subject = "Gina Reed", class = "SHAMAN", level = 32, ts = now0, items = copy(GEAR[2]) }),
  "a relay never overwrites the member's own fresh record, even with a newer stamp")
M.db.members["Gina Reed"].time = Cc.env.time() - 31 * 86400
check(M:ApplyRecord("Bert Hill", { subject = "Gina Reed", class = "SHAMAN", level = 32, ts = now0, items = copy(GEAR[2]) }),
  "an own record older than 30 days can be replaced by a newer relay")
M.db.members["Gina Reed"] = nil
check(M:ApplyRecord("Bert Hill", { subject = "Gina Reed", class = "SHAMAN", level = 32, ts = now0 + 100, items = copy(GEAR[2]) })
  and M.db.members["Gina Reed"].ts == M:Now(), "a relay stamped in the future is stored as now")
check(M:ApplyRecord("Gina Reed", { subject = "", class = "SHAMAN", level = 32, ts = now0 - 500, items = copy(GEAR[3]) })
  and M.db.members["Gina Reed"].source == "self" and M.db.members["Gina Reed"].from == nil,
  "the member's own record replaces a relayed one even when its stamp is older")
M.db.members["Gina Reed"] = nil

do
  local wornSlot, wornLink
  for slot, l in pairs(GEAR[1]) do if not wornSlot or slot < wornSlot then wornSlot, wornLink = slot, l end end
  local wornID = tonumber(wornLink:match("item:(%d+)"))
  local noWorn = copy(GEAR[1]); noWorn[wornSlot] = nil
  for slot, l in pairs(noWorn) do if tonumber(l:match("item:(%d+)")) == wornID then noWorn[slot] = nil end end
  M:SetCrafted("Finn Moor", "Leatherworking", { kind = "item", cand = { spellID = 424242, itemID = wornID }, slot = wornSlot }, true)
  M:SetCrafted("Finn Moor", "Enchanting", { kind = "enchant", cand = { spellID = 7779 }, enchant = { enchant = 247 }, slot = 9 }, true)
  local sentBefore = Cc.S.sent
  check(M:ApplyRecord("Finn Moor", { subject = "", class = "PRIEST", level = 34, ts = base + 20, items = noWorn })
    and M:CraftedMark("Finn Moor", "Leatherworking", 424242) ~= nil, "synced record without the crafted item keeps the mark")
  check(M:ApplyRecord("Finn Moor", { subject = "", class = "PRIEST", level = 34, ts = base + 30, items = copy(GEAR[1]) })
    and M:CraftedMark("Finn Moor", "Leatherworking", 424242) == nil, "synced record wearing it clears the mark")
  local ench = copy(noWorn); ench[9] = "item:12345:247"
  check(M:ApplyRecord("Finn Moor", { subject = "", class = "PRIEST", level = 34, ts = base + 40, items = ench })
    and M:CraftedMark("Finn Moor", "Enchanting", 7779) == nil, "synced record with enchant 247 on the wrist clears the enchant mark")
  local leaked = false
  for _, e in ipairs(bus.log) do if e.msg:find("424242", 1, true) then leaked = true end end
  check(Cc.S.sent == sentBefore and not leaked, "marks are never sent")
end

section("Malformed messages are dropped without errors (F#6)")
local before = Cc.S.received
local junk = {
  "G;;4;z;" .. M.b36(base + 5000) .. ";s;1/1;1=abc",
  "G;;0;z;" .. M.b36(base) .. ";s;1/1;1=4j",
  "G;;4;1o;" .. M.b36(base) .. ";s;1/1;1=4j",
  "G;;4;1p;" .. M.b36(base) .. ";s;1/1;1=4j",
  "G;;4;z;" .. M.b36(base) .. ";s;2/1;1=4j",
  "G;;4;z;" .. M.b36(base) .. ";s;1/7;1=4j",
  "G;;4;z;" .. M.b36(base) .. ";s;1/1;4=4j",
  "G;;4;z;" .. M.b36(base) .. ";s;1/1;1=4j|cff",
  "G;;4;z;" .. M.b36(base) .. ";s;1/1;1=" .. string.rep("1", 90),
  "G;;4;z;" .. M.b36(base) .. ";s;1/1;1=~Player|x",
  "G;;4;z;" .. M.b36(base) .. ";i;1/1;1=4j",
  "G;Dora Field;4;z;" .. M.b36(base) .. ";s;1/1;1=4j",
  "G;;4;z",
  "X;whatever", "", ";;;;;;;;", "G;;;;;;;",
}
local errs, errs0 = 0, #Cc.errors
for i, msg in ipairs(junk) do
  if i ~= 3 then
    local ok = pcall(Cc.fire, "CHAT_MSG_ADDON", "GCAdv1", msg, "GUILD", "Gina Reed")
    if not ok then errs = errs + 1 end
    Cc.RQ.Comm.intake = {}
  end
end
errs = errs + #Cc.errors - errs0
check(errs == 0 and Cc.S.received == before, ("no errors, nothing stored (%d stored)"):format(Cc.S.received - before))
local ginaOwn = M.db.members["Gina Reed"]
check(not ginaOwn or ginaOwn.source ~= "self", "no self record for Gina from junk")

section("No echo: the core's slow mode (1 per 5 min, one warning) is our 'paused'; Retry sync leaves it")
advance(300)
bus.drop = function(sender, _, _, to) return to.name == sender end
A.gear[6] = GEAR[2][6] or GEAR[3][6]
A.fire("PLAYER_EQUIPMENT_CHANGED")
advance(600)
local warn = 0 for _, p in ipairs(A.printed) do if p.text:find("sending slowly", 1, true) then warn = warn + 1 end end
check(A.RQ:CommState().slow and A.GCA:SyncState() == "paused" and warn == 1,
  "nothing echoed for 120 s after a loss: slow mode, sync state 'paused', the core warns once (" .. warn .. ")")
local lines = {}
A.GCA:SyncStatus(function(l) lines[#lines + 1] = l end)
check(lines[1] == A.GCA.L.SYNC_STOPPED_MSG and lines[1]:find("sending continues slowly", 1, true), "sync status says sending continues slowly")
local t1 = sched.t
A.gear[6] = GEAR[3][6] or GEAR[1][6]
A.fire("PLAYER_EQUIPMENT_CHANGED")
advance(900)
local slowSent = busSince(t1, function(e) return e.sender == "Anna Stone" end)
check(slowSent >= 1 and slowSent <= 4, "while slow, sending continues at 1 per 5 min (" .. slowSent .. " in 15 min)")
bus.drop = function() return false end
A.GCA:SyncRetry()
advance(300)
check(not A.RQ:CommState().slow and A.GCA:SyncState() ~= "paused" and sameGear(rec(B, "Anna Stone").items, A.gear, B.GCA),
  "Retry sync: normal pace again, the own record arrives")

section("Roster not loaded yet: Q deferred until it is")
Logout(Cc)
advance(30)
t0 = sched.t
local D = Login("Cora Vale", copy(GEAR[3]), Cc.GCA.db, { rosterReady = false })
D.GCA.db.sync["Cora Vale-Realm"].lastQ = nil
advance(90)
check(busSince(t0, function(e) return e.sender == "Cora Vale" and e.msg:sub(1, 2) == "Q;" end) == 0, "no Q while the roster is empty")
D.rosterReady = true; D.fire("GUILD_ROSTER_UPDATE")
advance(30)
check(busSince(t0, function(e) return e.sender == "Cora Vale" and e.msg:sub(1, 2) == "Q;" end) == 1, "Q sent once the roster loaded")

section("/reload within 15 min doesn't resend Q; an alt does (F#11)")
advance(60)
t0 = sched.t
local D2 = Login("Cora Vale", copy(GEAR[3]), D.GCA.db)
advance(90)
check(busSince(t0, function(e) return e.sender == "Cora Vale" and e.msg:sub(1, 2) == "Q;" end) == 0, "/reload: no second Q")
Logout(D2)
local sharedDB = D2.GCA.db
t0 = sched.t
GUILD[#GUILD + 1] = { name = "Cora Alt", class = "MAGE", level = 20 }; GUILD_BY["Cora Alt"] = GUILD[#GUILD]
local E = Login("Cora Alt", copy(GEAR[2]), sharedDB)
advance(90)
check(busSince(t0, function(e) return e.sender == "Cora Alt" and e.msg:sub(1, 2) == "Q;" end) == 1, "alt on the same account sends its own Q")

section("Review fixes: realm-suffixed echo, own record retried after expiry, relay without level")
local R1 = E.GCA
local peersBefore = 0 for _ in pairs(E.S.peers) do peersBefore = peersBefore + 1 end
E.S.echoSeen = nil
E.fire("CHAT_MSG_ADDON", "GCAdv1", "Q;2", "GUILD", "Cora Alt-Realm")
local peersAfter = 0 for _ in pairs(E.S.peers) do peersAfter = peersAfter + 1 end
check(E.S.echoSeen == sched.t and peersAfter == peersBefore, "realm-suffixed own echo recognised")
check(R1.db.members["Cora Alt-Realm"] == nil, "no member record for ourselves under another name")
advance(300)
local busyUntil = sched.t + 400
local function busy() if sched.t < busyUntil then for _ = 1, 10 do E.RQ.Comm.heard[#E.RQ.Comm.heard + 1] = sched.t end; sched:at(sched.t + 10, busy) end end
busy()
E.gear[7] = GEAR[1][7] or GEAR[4][7]
E.fire("PLAYER_EQUIPMENT_CHANGED")
t0 = sched.t
advance(380)
check(busSince(t0, function(e) return e.sender == "Cora Alt" and e.msg:match("^G;;") end) == 0, "nothing sent while the guild channel is busy")
check(E.S.pending.self == nil and E.RQ:CommState().records == 0, "own record dropped from the core's record lane after 300 s unsent")
advance(400)
check(sameGear(rec(A, "Cora Alt").items, E.gear, A.GCA), "own record went out after the busy period (retried)")
advance(100)
local f, sn = "Gina", "Reed"
A.units.target = { first = f, surname = sn, class = "SHAMAN", level = nil, guid = "G-Gina Reed", items = copy(GEAR[4]) }
A.GCA.db.members["Gina Reed"].level = nil
A.GCA:OnInspectReady("G-Gina Reed"); advance(2); A.units.target = nil
advance(200)
check(rec(B, "Gina Reed") and rec(B, "Gina Reed").level == 32 and sameGear(rec(B, "Gina Reed").items, GEAR[4], B.GCA),
  "relay without unit level used the roster level (32) and arrived")

section("Spec sync (F8.4): S;<index>;<ts> between 0.3 clients; a 0.2.0 client ignores it")
for _, g in ipairs({ { name = "Ivy Lake", class = "ROGUE", level = 40 }, { name = "Jon Ash", class = "DRUID", level = 44 },
  { name = "Kai Old", class = "MAGE", level = 30 } }) do
  GUILD[#GUILD + 1] = g; GUILD_BY[g.name] = g
end
advance(100)
local legacyFiles = { "Data/Leatherworking.lua", "dev/fixtures/compat_0.2.0/Core.lua", "dev/fixtures/compat_0.2.0/Sync.lua" }
local K = Login("Kai Old", copy(GEAR[1]), {}, { files = legacyFiles })
advance(120)
t0 = sched.t
local I = Login("Ivy Lake", copy(GEAR[2]), {}, { talents = { { 5020, 15 }, { 1020, 5 } } })
local J = Login("Jon Ash", copy(GEAR[3]), {}, { talents = { { 5020, 20 } }, knownSpells = { 768 } })
advance(400)
local sMsgs = busSince(t0, function(e) return e.msg:sub(1, 2) == "S;" end)
check(sMsgs >= 2, "spec messages sent (" .. sMsgs .. ")")
local ivyIdx = I.GCA.SPEC_INDEX["ROGUE/COMBAT"]
check(busSince(t0, function(e) return e.sender == "Ivy Lake" and e.msg:match("^S;" .. I.GCA.b36(ivyIdx) .. ";%w+$") end) >= 1, "Ivy sent S;<Combat>;<ts>")
check(J.GCA:MemberSpec("Ivy Lake", "ROGUE", {}) == "COMBAT", "Jon knows Ivy is Combat (synced)")
local js, jhow = I.GCA:MemberSpec("Jon Ash", "DRUID", {})
check(js == "FERAL_CAT" and jhow == "synced", "Ivy knows Jon's spec: " .. tostring(js) .. " (" .. tostring(jhow) .. ")")
check(A.GCA:MemberSpec("Ivy Lake", "ROGUE", {}) == "COMBAT", "Anna (0.3) got it too")
check(rec(K, "Ivy Lake") ~= nil and K.GCA.db.specs == nil, "0.2.0 client: S ignored, Ivy's gear still applied")
local kErr = 0
for _, msg in ipairs({ "S;1;" .. K.GCA.b36(K.GCA:Now()), "S;zz;1", "S;", "S;1;2;3" }) do
  if not pcall(K.fire, "CHAT_MSG_ADDON", "GCAdv1", msg, "GUILD", "Gina Reed") then kErr = kErr + 1 end
end
check(kErr == 0, "0.2.0 parser: S messages of any shape cause no error")
local tsBefore = J.GCA.db.specs["Ivy Lake"].ts
advance(130)
I.talents[1] = { 9080, 25 }; I.talents[2] = { 1020, 1 }
I.fire("TRAIT_CONFIG_UPDATED")
advance(200)
check(J.GCA:MemberSpec("Ivy Lake", "ROGUE", {}) == "SUBTLETY" and J.GCA.db.specs["Ivy Lake"].ts >= tsBefore, "respec arrives (Subtlety)")
I.GCA:SetManualSpec("Ivy Lake", "ROGUE", "ASSASSINATION")
advance(200)
check(J.GCA:MemberSpec("Ivy Lake", "ROGUE", {}) == "ASSASSINATION", "own manual pick is announced")
local JG = J.GCA
local specBefore = JG.db.specs["Ivy Lake"].spec
J.fire("CHAT_MSG_ADDON", "GCAdv1", "S;" .. JG.b36(JG.SPEC_INDEX["MAGE/FIRE"]) .. ";" .. JG.b36(JG:Now()), "GUILD", "Ivy Lake")
check(JG.db.specs["Ivy Lake"].spec == specBefore, "spec of another class than the roster says: ignored")
J.RQ.Comm.intake = {}
J.fire("CHAT_MSG_ADDON", "GCAdv1", "S;" .. JG.b36(JG.SPEC_INDEX["ROGUE/COMBAT"]) .. ";" .. JG.b36(JG:Now() + 9999), "GUILD", "Ivy Lake")
check(JG.db.specs["Ivy Lake"].spec == specBefore, "future timestamp: ignored")
J.fire("CHAT_MSG_ADDON", "GCAdv1", "S;" .. JG.b36(99) .. ";" .. JG.b36(JG:Now()), "GUILD", "Ivy Lake")
check(JG.db.specs["Ivy Lake"].spec == specBefore, "unknown index: ignored")
JG:SetManualSpec("Ivy Lake", "ROGUE", "COMBAT")
check(JG:MemberSpec("Ivy Lake", "ROGUE", {}) == "COMBAT", "manual pick on the receiver wins over the synced spec")
check(JG.SPEC_INDEX["DRUID/BALANCE"] == 1 and JG.SPEC_INDEX["SHAMAN/ENHANCEMENT_DW"] == 24 and JG.SPEC_INDEX["WARRIOR/PROTECTION"] == 31 and #JG.SPEC_LIST == 31,
  "spec index table unchanged (1 Balance, 24 Enh DW, 31 Warrior Prot)")

section("one chatty sender can't hold everyone's sending; several busy senders still do")
do
  advance(900)
  A.RQ:CommResume()
  local spamUntil = sched.t + 900
  local function spam()
    if sched.t < spamUntil then
      A.fire("CHAT_MSG_ADDON", "GCAdv1", "X;junk", "GUILD", "Spam Bot")
      sched:at(sched.t + 1, spam)
    end
  end
  spam()
  A.gear[7] = GEAR[2][7] ~= A.gear[7] and GEAR[2][7] or GEAR[3][7]
  A.fire("PLAYER_EQUIPMENT_CHANGED")
  local gearAt = sched.t
  advance(840)
  local sent = busSince(gearAt, function(e) return e.sender == A.name and e.msg:match("^G;;") end)
  local recent = 0
  for _, t in ipairs(A.RQ.Comm.heard) do if sched.t - t <= 60 then recent = recent + 1 end end
  check(sent >= 1 and recent <= A.RQ.CommConst.HEARD_PER_SENDER,
    ("own gear goes out while one guildie sends 1 msg/s (%d chunk(s) sent, %d heard in the last 60 s)"):format(sent, recent))
  advance(200)
  local CC = A.RQ.CommConst
  local busyNames = {}
  for i = 1, math.ceil(CC.BUSY_HEARD / CC.HEARD_PER_SENDER) + 2 do busyNames[i] = "Busy" .. i .. " Guildie" end
  A.RQ.Comm.heard = {}
  local busyUntil2 = sched.t + 300
  local function chatter()
    if sched.t < busyUntil2 then
      for _, who in ipairs(busyNames) do
        A.fire("CHAT_MSG_ADDON", "GCAdv1", "X;busy", "GUILD", who)
      end
      sched:at(sched.t + 15, chatter)
    end
  end
  chatter()
  advance(50)
  A.gear[7] = GEAR[2][7] ~= A.gear[7] and GEAR[2][7] or GEAR[3][7]
  A.fire("PLAYER_EQUIPMENT_CHANGED")
  local t2 = sched.t
  advance(200)
  check(busSince(t2, function(e) return e.sender == A.name and e.msg:match("^G;;") end) == 0,
    ("%d busy senders (%d heard/min, hold at %d): our send is held (%d heard)"):format(#busyNames, #busyNames * 4, CC.BUSY_HEARD, #A.RQ.Comm.heard))
  advance(600)
  check(busSince(t2, function(e) return e.sender == A.name and e.msg:match("^G;;") end) >= 1, "held send goes out once it is quiet")
end

section("the inspect queue waits for the final storing read before the next NotifyInspect")
do
  local G = A.GCA
  local notifies, stores = {}, {}
  local answerDelay = { ["G-Dora Field"] = 0.3, ["G-Emil Brook"] = 0.3, ["G-Finn Moor"] = false, ["G-Gina Reed"] = 2.9 }
  A.env.NotifyInspect = function(u)
    local x = A.units[u]
    notifies[#notifies + 1] = { t = sched.t, guid = x and x.guid }
    local d = x and answerDelay[x.guid]
    if d then sched:at(sched.t + d, function() A.fire("INSPECT_READY", x.guid) end) end
  end
  local realStore = G.StoreRecord
  G.StoreRecord = function(self, key, ...) stores[#stores + 1] = { t = sched.t, key = key }; return realStore(self, key, ...) end
  local function unit(token, uname, items)
    local g = GUILD_BY[uname]
    local firstName, lastName = uname:match("^(%S+) (%S+)$")
    A.units[token] = { first = firstName, surname = lastName, class = g.class, level = g.level, guid = "G-" .. uname, items = items }
  end
  unit("party1", "Dora Field", copy(GEAR[4])); unit("party2", "Emil Brook", copy(GEAR[1]))
  unit("party3", "Finn Moor", copy(GEAR[2])); unit("party4", "Gina Reed", copy(GEAR[3]))
  G.inspecting = nil; G.queue = {}; G.lastInspect = {}
  for _, u in ipairs({ "party1", "party2", "party3", "party4" }) do G:QueueInspect(u, true) end
  advance(30)
  local function at(guid) for _, note in ipairs(notifies) do if note.guid == guid then return note.t end end end
  local function storedAt(key) for _, s in ipairs(stores) do if s.key == key then return s.t end end end
  local tD, tE, tF, tG = at("G-Dora Field"), at("G-Emil Brook"), at("G-Finn Moor"), at("G-Gina Reed")
  local sD, sG = storedAt("Dora Field"), storedAt("Gina Reed")
  print(("  info: notify D %.1f E %.1f F %.1f G %.1f; stored D %.1f G %s"):format(tD or -1, tE or -1, tF or -1, tG or -1, sD or -1, tostring(sG)))
  check(#notifies == 4 and sD and tE and tE > sD, "next NotifyInspect only after the previous member's final read was stored")
  check(tF and tE and math.abs((tF - tE) - (0.3 + G.INSPECT_FINAL_READ + G.INSPECT_GAP)) < 0.01, "answered inspect: next one after answer + final read + gap")
  check(tG and tF and math.abs((tG - tF) - G.INSPECT_NO_ANSWER) < 0.01, "no INSPECT_READY: queue moves on after " .. G.INSPECT_NO_ANSWER .. " s")
  check(sG and tG and sG >= tG + 2.9 + G.INSPECT_FINAL_READ - 0.01 and G.inspecting == nil, "late answer (2.9 s): stored, queue not cut off by the no-answer timer")
  notifies, stores = {}, {}
  G.StoreRecord = function() error("boom") end
  G.lastInspect = {}
  G:QueueInspect("party1", true); G:QueueInspect("party2", true)
  advance(30)
  check(#notifies == 2 and G.inspecting == nil, "an error in the final read doesn't hang the queue")
  G.StoreRecord = realStore
  notifies = {}
  A.env.NotifyInspect = function(u) notifies[#notifies + 1] = { t = sched.t }; G.inspectAnswered = G.inspecting end
  G.lastInspect = {}
  G:QueueInspect("party2", true)
  advance(G.INSPECT_NO_ANSWER + 1)
  check(G.inspecting ~= nil, "answered inspect is not cut off by the no-answer timer")
  advance(G.INSPECT_HARD_LIMIT)
  check(G.inspecting == nil, "... but the hard limit (" .. G.INSPECT_HARD_LIMIT .. " s) frees the queue")
  A.env.NotifyInspect = function() end
  for _, u in ipairs({ "party1", "party2", "party3", "party4" }) do A.units[u] = nil end
end

section("automatic gear reading (group roster, mouseover): rules, combat, throttle, option")
do
  local G = A.GCA
  local notified = {}
  A.env.NotifyInspect = function(u) local x = A.units[u]; notified[#notified + 1] = x and x.guid end
  local function unit(token, uname, items)
    local g = GUILD_BY[uname]
    local firstName, lastName = uname:match("^(%S+) (%S+)$")
    A.units[token] = { first = firstName, surname = lastName, class = g.class, level = g.level, guid = "G-" .. uname, items = items }
  end
  unit("party1", "Dora Field", copy(GEAR[4])); unit("party2", "Emil Brook", copy(GEAR[1]))
  A.env.GetNumSubgroupMembers = function() return 2 end
  local function reset()
    advance(30)
    notified = {}
    G.inspecting, G.queue, G.lastInspect, G.lastAutoMouseover = nil, {}, {}, nil
    G.db.members["Dora Field"] = { time = A.env.time(), items = {} }
    G.db.members["Emil Brook"] = { time = A.env.time() - G.AUTO_FRESH - 5, items = {} }
  end
  reset()
  check(G.db.settings.autoInspect == true, "'autoInspect' defaults to on")
  A.fire("GROUP_ROSTER_UPDATE"); A.fire("GROUP_ROSTER_UPDATE"); A.fire("GROUP_ROSTER_UPDATE")
  check(#notified == 0, "GROUP_ROSTER_UPDATE is debounced (" .. G.AUTO_GROUP_DELAY .. " s), nothing at once")
  advance(G.AUTO_GROUP_DELAY + 0.1)
  check(#notified == 1 and notified[1] == "G-Emil Brook", "one scan for the burst: only the member without a recent record is read (Dora is fresh)")
  check(select(2, G:AutoInspectCheck("party1")) == "fresh" and select(2, G:AutoInspectCheck("party2")) == "recent",
    "reasons: fresh record (< 30 min) / tried within " .. G.AUTO_RETRY .. " s")
  reset()
  A.combat = true
  A.fire("GROUP_ROSTER_UPDATE"); advance(G.AUTO_GROUP_DELAY + 1)
  check(#notified == 0 and G.autoGroupPending and select(2, G:AutoInspectCheck("party2")) == "combat", "in combat: no inspect, scan remembered")
  A.combat = false
  A.fire("PLAYER_REGEN_ENABLED")
  check(#notified == 1 and notified[1] == "G-Emil Brook" and not G.autoGroupPending, "combat over: the remembered scan runs at once")
  reset()
  A.env.CanInspect = function() return false end
  check(select(2, G:AutoInspectCheck("party2")) == "caninspect" and G:AutoScanGroup() == 0, "CanInspect false: skipped")
  A.env.CanInspect = function() return true end
  A.env.CheckInteractDistance = function(u, i) return i == 1 and false end
  check(select(2, G:AutoInspectCheck("party2")) == "range", "CheckInteractDistance(unit, 1) == false: out of range, skipped")
  A.env.CheckInteractDistance = function() error("restricted") end
  check(G:AutoInspectCheck("party2") == true, "CheckInteractDistance erroring: not treated as out of range")
  A.env.CheckInteractDistance = nil
  A.env.InspectFrame = { IsShown = function() return true end }
  check(select(2, G:AutoInspectCheck("party2")) == "inspectframe" and G:AutoScanGroup() == 0 and #notified == 0, "your inspect window open: never taken over")
  A.env.InspectFrame = nil
  G.db.settings.autoInspect = false
  A.fire("GROUP_ROSTER_UPDATE"); advance(G.AUTO_GROUP_DELAY + 1)
  check(#notified == 0 and select(2, G:AutoInspectCheck("party2")) == "off" and not G:AutoMouseover(), "option off: no group scan, no mouseover read")
  G.db.settings.autoInspect = true
  reset()
  unit("mouseover", "Finn Moor", copy(GEAR[2]))
  G.db.members["Finn Moor"] = nil
  A.fire("UPDATE_MOUSEOVER_UNIT")
  check(#notified == 1 and notified[1] == "G-Finn Moor", "mouseover on a guildie without a record: read")
  unit("mouseover", "Gina Reed", copy(GEAR[3]))
  G.db.members["Gina Reed"] = nil
  advance(G.INSPECT_NO_ANSWER + G.INSPECT_GAP + 0.1)
  A.fire("UPDATE_MOUSEOVER_UNIT")
  check(#notified == 1, "a second mouseover within " .. G.AUTO_MOUSEOVER_GAP .. " s: throttled")
  advance(G.AUTO_MOUSEOVER_GAP)
  G.queue = { "G-Someone" }
  A.fire("UPDATE_MOUSEOVER_UNIT")
  check(#notified == 1, "queue busy (group reads waiting): mouseover is low priority, skipped")
  G.queue = {}
  A.fire("UPDATE_MOUSEOVER_UNIT")
  check(#notified == 2 and notified[2] == "G-Gina Reed", "idle again after the gap: read")
  G.db.settings.autoInspect = false
  unit("target", "Dora Field", copy(GEAR[4])); G.lastInspect = {}
  advance(30)
  A.fire("PLAYER_TARGET_CHANGED")
  check(#notified == 2, "option off: targeting doesn't read either (one option for target, group, mouseover)")
  G.db.settings.autoInspect = true
  advance(30)
  A.env.NotifyInspect = function() end
  A.env.GetNumSubgroupMembers = function() return 0 end
  for _, u in ipairs({ "party1", "party2", "mouseover", "target" }) do A.units[u] = nil end
end

section("own spec persisted for alts; receive time; resume message only when paused")
do
  local IG = I.GCA
  local own = IG.db.specs[IG.playerKey]
  local announced = select(2, IG:OwnAnnouncedSpec())
  check(own and own.src == "self" and own.spec == announced, "own spec stored in db.specs[me] as src 'self' (" .. tostring(own and own.spec) .. ")")
  local savedKey, savedManual = IG.playerKey, IG.db.specManual["Ivy Lake"]
  IG.playerKey = "Ivy Alt"; IG.db.specManual["Ivy Lake"] = nil
  local sp, how = IG:MemberSpec("Ivy Lake", "ROGUE", {})
  IG.playerKey = savedKey; IG.db.specManual["Ivy Lake"] = savedManual
  check(sp == announced and how == "own", "an alt on the account sees the main's spec (" .. tostring(sp) .. ", " .. tostring(how) .. ")")
  local r = rec(B, "Anna Stone")
  check(r and r.time and r.ts and r.time > r.ts and B.env.time() - r.time < 3600,
    "received record: time is our receive time (" .. tostring(r and r.time) .. "), ts kept (" .. tostring(r and r.ts) .. ")")
  local function resumed() local count = 0 for _, p in ipairs(A.printed) do if p.text:find("Guild sync resumed", 1, true) then count = count + 1 end end return count end
  local n0 = resumed()
  A.RQ:CommResume()
  A.GCA:SyncRetry()
  check(resumed() == n0, "SyncRetry while not paused: no 'resumed' message")
  A.RQ.Comm.slow = true
  A.GCA:SyncRetry()
  check(resumed() == n0 + 1 and not A.RQ:CommState().slow, "SyncRetry while paused: resumed + message, slow mode left")
end

section("Relay rules: our own inspect reads of guildies without the addon, not heard yet, never from an instance")
do
  local G, S, db = A.GCA, A.S, A.GCA.db
  local key = "Finn Moor"
  local savedFinn = db.members[key]
  advance(300)
  local function relays(t0)
    return busSince(t0, function(e)
      return e.sender == "Anna Stone" and e.msg:find("G;" .. key .. ";", 1, true) == 1 and e.msg:match(";1/%d;") ~= nil
    end)
  end
  local function inspected(extra)
    local r = { class = "PRIEST", level = 34, items = copy(GEAR[2]), ts = G:Now(), time = A.env.time(), source = "inspect" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local function try(r, setup)
    db.members[key] = r
    S.relayHeard[key], S.relayHeardSig[key], S.addonUsers[key] = nil, nil, nil
    if setup then setup(r) end
    local t0 = sched.t
    G:RelayInspect(key)
    advance(150)
    return relays(t0)
  end
  local now = A.env.GetTime
  check(try(inspected()) == 1, "control: our fresh inspect read of a guildie without the addon is relayed once")
  check(try(inspected({ source = "sync" })) == 0 and try(inspected({ from = "Bert Hill" })) == 0,
    "a record that came over sync, or one relayed to us, isn't relayed")
  check(try(inspected(), function() S.addonUsers[key] = now() - 60 end) == 0
    and try(inspected(), function() S.addonUsers[key] = now() - A.C.ADDON_USER_FRESH - 1 end) == 1,
    "a guildie heard using the addon within the hour sends their own gear; one silent for longer is relayed")
  check(try(inspected(), function(r) S.relayHeard[key] = r.ts end) == 0
    and try(inspected(), function(r) S.relayHeardSig[key] = G:GearSignature(r.items) end) == 0,
    "someone already relayed this read (same or newer stamp, or the same gear): not again")
  A.instance = true
  A.fire("PLAYER_ENTERING_WORLD", false, false)
  local inInstance = try(inspected())
  A.instance = false
  A.fire("PLAYER_ENTERING_WORLD", false, false)
  local t0 = sched.t
  advance(150)
  check(inInstance == 0 and relays(t0) == 1, "inside an instance the relay waits, and goes out after leaving")
  local cs = db.sync[G.charKey]
  local savedPeers, savedPeerAt = S.peers, cs.peerAt
  S.peers, cs.peerAt = {}, nil
  local noPeer = try(inspected())
  S.peers, cs.peerAt = savedPeers, savedPeerAt
  t0 = sched.t
  advance(150)
  check(noPeer == 0 and relays(t0) == 1, "with no other addon user known the relay waits for one")
  db.members[key] = nil
  for i = 1, A.C.RELAY_MAX do S.relayPending["Queued " .. i] = now() - 100 + i end
  G:RelayInspect(key)
  local kept = 0
  for i = 2, A.C.RELAY_MAX do if S.relayPending["Queued " .. i] then kept = kept + 1 end end
  check(S.relayPending["Queued 1"] == nil and kept == A.C.RELAY_MAX - 1 and S.relayPending[key] ~= nil,
    "more than " .. A.C.RELAY_MAX .. " waiting relays: the oldest is dropped")
  advance(300)
  check(next(S.relayPending) == nil, "the queue drains (subjects without a record send nothing)")
  db.members[key] = savedFinn
end

section("pruning characters that left the guild (conservative)")
do
  local G, db = A.GCA, A.GCA.db
  local T = A.env.time()
  local old, recent = T - 40 * 86400, T - 5 * 86400
  local roster = {
    { "Anna Stone", true }, { "Bert Hill", true }, { "Cora Vale", false }, { "Dora Field", true },
    { "Emil Brook", false }, { "Finn Moor", true }, { "Gina Reed", true },
  }
  local rosterN = #roster
  local hole = nil
  A.env.GetNumGuildMembers = function() return rosterN end
  A.env.GetGuildRosterInfo = function(i)
    local m = roster[i]; if not m or i == hole then return end
    local g = GUILD_BY[m[1]]
    return m[1], "Member", 1, g.level, g.class, "Zone", "", "", m[2], 0, g.class
  end
  db.members["Gone Away"] = { class = "MAGE", level = 30, time = old, ts = old, items = {} }
  db.specs["Gone Away"] = { class = "MAGE", spec = "FIRE", src = "sync", ts = old }
  db.crafted = db.crafted or {}
  db.crafted[G.charKey] = db.crafted[G.charKey] or {}
  db.crafted[G.charKey]["Gone Away"] = { Leatherworking = { [1] = { item = 1, t = old } } }
  db.crafted["Other Main-Realm"] = { ["Gone Away"] = { Leatherworking = { [2] = { item = 2, t = old } } } }
  db.members["Just Left"] = { class = "MAGE", level = 30, time = recent, ts = old, items = {} }
  db.members["No Stamp"] = { class = "MAGE", level = 30, items = {} }
  db.specs["Spec Only"] = { class = "MAGE", spec = "FIRE", src = "sync", ts = old }
  local doraTime = db.members["Dora Field"] and db.members["Dora Field"].time
  if db.members["Dora Field"] then db.members["Dora Field"].time, db.members["Dora Field"].ts = old, old end
  db.known["My Alt-Realm"] = {}
  db.members["My Alt"] = { class = "MAGE", level = 10, time = old, ts = old, items = {}, source = "self" }
  db.members["Other Main"] = { class = "MAGE", level = 60, time = old, ts = old, items = {}, source = "self" }
  local function try()
    G.pruneDone = nil
    A.fire("GUILD_ROSTER_UPDATE")
  end
  G.loginTime = sched.t
  db.rosterLast = 7
  try()
  check(db.members["Gone Away"] and not G.pruneDone, "too soon after login: nothing pruned")
  G.loginTime = sched.t - 120
  db.rosterLast = nil
  try()
  check(db.members["Gone Away"] and db.rosterLast == 7, "first session that records a roster size: nothing pruned")
  rosterN = 0
  try()
  check(db.members["Gone Away"] and not G.pruneDone, "roster count 0: nothing pruned, tried again on the next update")
  rosterN = 3
  try()
  check(db.members["Gone Away"], "roster suspiciously small (3, under 5): nothing pruned")
  rosterN = 7; db.rosterLast = 20
  try()
  check(db.members["Gone Away"], "roster less than half of last session's (7 vs 20): nothing pruned")
  for _, m in ipairs(roster) do m.on = m[2]; m[2] = true end
  db.rosterLast = 7
  try()
  check(db.members["Gone Away"], "no offline member in the roster (online-only list?): nothing pruned")
  for _, m in ipairs(roster) do m[2] = m.on end
  hole = 4
  try()
  check(db.members["Gone Away"], "incomplete roster read (an index without a name): nothing pruned")
  hole = nil
  local p0 = #A.printed
  try()
  check(db.members["Gone Away"] == nil and db.specs["Gone Away"] == nil and db.crafted[G.charKey]["Gone Away"] == nil
    and db.crafted["Other Main-Realm"]["Gone Away"] == nil and db.specs["Spec Only"] == nil,
    "left the guild + older than 30 days: gear, spec and crafted marks (every character) removed")
  check(db.members["Just Left"] and db.members["No Stamp"] and db.members["Dora Field"] and db.members[G.playerKey]
    and db.members["My Alt"] and db.members["Other Main"], "kept: recent, no timestamp, still in the guild, own characters")
  local lastLine = A.printed[#A.printed] and A.printed[#A.printed].text
  check(#A.printed == p0 + 1 and lastLine:find("Removed 2 character", 1, true) ~= nil, "one chat line: " .. tostring(lastLine))
  db.members["Gone Away"] = { class = "MAGE", level = 30, time = old, items = {} }
  A.fire("GUILD_ROSTER_UPDATE")
  check(db.members["Gone Away"] ~= nil, "once per session")
  for _, k in ipairs({ "Gone Away", "Just Left", "No Stamp", "My Alt", "Other Main" }) do db.members[k] = nil end
  db.known["My Alt-Realm"] = nil; db.crafted["Other Main-Realm"] = nil; db.crafted[G.charKey] = nil
  if db.members["Dora Field"] then db.members["Dora Field"].time = doraTime end
end

section("Pacing: nobody sent more than the core's budget allows (4 per 60 s, 22 per 600 s)")
local function worst(window)
  local w, senders = 0, {}
  for _, e in ipairs(bus.log) do senders[e.sender] = true end
  for name in pairs(senders) do w = math.max(w, bus:maxPer(window, name)) end
  return w
end
local w60, w600 = worst(60), worst(600)
check(w60 <= 4 and w600 <= 22, ("max messages by one client: %d in any 60 s (<= 4), %d in any 600 s (<= 22)"):format(w60, w600))
io.write(("  info: %d messages on the bus over %.0f simulated minutes\n"):format(#bus.log, sched.t / 60))
Kit.finish()
