local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua",
  "RecipeSources.lua", "UI" } }))
local LEGACY = { "Data/Leatherworking.lua", "dev/fixtures/compat_0.2.0/Core.lua", "dev/fixtures/compat_0.2.0/Sync.lua" }

local GUILD = {
  { name = "Anna Stone", class = "ROGUE", level = 36 },
  { name = "Bert Hill", class = "DRUID", level = 35 },
  { name = "Cora Vale", class = "HUNTER", level = 31 },
  { name = "Dora Field", class = "WARRIOR", level = 35 },
  { name = "Emil Brook", class = "MAGE", level = 33 },
  { name = "Finn Moor", class = "PRIEST", level = 34 },
}
local GUILD_BY = {}
for _, g in ipairs(GUILD) do GUILD_BY[g.name] = g end
local PROF_NAME = { [165] = "Leatherworking", [164] = "Blacksmithing", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting" }

local sched = Kit.Scheduler({ trap = true })
local bus = Kit.Bus(sched)
bus.latency = 0.2
local clients = {}
local function advance(sec) sched:advance(sec) end

local function StubPlayer(env, kc, name, opts)
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
    return m.name, "Member", 1, m.level, m.class, "Zone", "", "", (c and c.online) or m.name == "Finn Moor", 0, m.class
  end
  env.C_GuildInfo = { GuildRoster = function() end }
  env.C_Item = { GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end,
    GetItemStats = function() return {} end }
  env.C_SpellBook = { IsSpellKnown = function() return false end }
  kc.known, kc.profs = {}, opts.profs or {}
  for _, id in ipairs(opts.known or {}) do kc.known[id] = true end
  env.IsPlayerSpell = function(id) return kc.known[id] == true end
  env.GetProfessions = function()
    local idx = {}
    for i in ipairs(kc.profs) do idx[i] = i end
    return (table.unpack or unpack)(idx)
  end
  env.GetProfessionInfo = function(i)
    local p = kc.profs[i]
    if p then return PROF_NAME[p[1]], nil, p[2], 300, nil, nil, p[1] end
  end
  local send = env.C_ChatInfo.SendAddonMessage
  env.C_ChatInfo.SendAddonMessage = function(prefix, msg, chan)
    assert(#msg <= 255, "message over 255 bytes: " .. #msg)
    assert(chan == "GUILD", "non-GUILD send: " .. tostring(chan))
    return send(prefix, msg, chan)
  end
end

local LegacyFrame = {}
LegacyFrame.__index = LegacyFrame
function LegacyFrame:SetScript(ev, fn) self._scripts[ev] = fn end
function LegacyFrame:RegisterEvent(ev) self._events[ev] = true end
function LegacyFrame:UnregisterEvent(ev) self._events[ev] = nil end

local function Login(name, opts)
  opts = opts or {}
  if clients[name] then clients[name].online = false end
  local g = GUILD_BY[name]
  local c = Kit.Client(sched, bus, name, { class = g.class, level = g.level, epoch = 1800000000, random = Kit.Random(#name),
    noCore = opts.files ~= nil, files = opts.files and Files.kitFiles(opts.files) or FILES, setup = function(env, kc)
      StubPlayer(env, kc, name, opts)
      env.RavenquillExpeditionCraftDB = opts.db or {}
      if opts.files then kc.newFrame = function() return setmetatable({ _scripts = {}, _events = {} }, LegacyFrame) end end
    end })
  c.GCA = c.ns[CA].GCA
  clients[name] = c
  c.login()
  return c
end

local function recipeIDs(GCA, prof)
  local ids = {}
  for id in pairs(GCA:KnowableSpells(prof)) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end
local function sameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function crafterKeys(list)
  local out = {}
  for i, c in ipairs(list) do out[i] = c.key .. (c.online and "+" or "-") end
  return table.concat(out, ",")
end

section("Recipe ID codec: every real recipe list round-trips and stays compact")
local A = Login("Anna Stone")
local GCA = A.GCA
local sizes = {}
for _, p in ipairs(GCA.PROFESSIONS) do
  local ids = recipeIDs(GCA, p.key)
  local half = {}
  for i, id in ipairs(ids) do if i % 2 == 1 then half[#half + 1] = id end end
  local full, part = GCA.EncodeIDs(ids), GCA.EncodeIDs(half)
  check(sameList(GCA.DecodeIDs(full), ids) and sameList(GCA.DecodeIDs(part), half),
    p.key .. ": all " .. #ids .. " and every second recipe decode to the same sorted IDs")
  sizes[#sizes + 1] = ("%s %d recipes %d bytes"):format(p.key, #ids, #full)
  check(#full <= #ids * 1.5, p.key .. ": at most 1.5 bytes per recipe for the full list (" .. #full .. " for " .. #ids .. ")")
end
io.write("  info: " .. table.concat(sizes, "; ") .. "\n")
check(GCA.EncodeIDs({ 1, 35, 71, 2149, 1306545 }) == "1yB0CFqCBPP8" and sameList(GCA.DecodeIDs("1yB0CFqCBPP8"), { 1, 35, 71, 2149, 1306545 }),
  "known vector: 1, 35, 71, 2149, 1306545 (deltas 1, 34, 36, 2078, 1304396) <-> '1yB0CFqCBPP8'")
check(GCA.EncodeIDs({}) == "" and sameList(GCA.DecodeIDs(""), {}), "empty list <-> empty string")
local bad = {}
for _, s in ipairs({ "0", "20", "A", "2A", "2;3", "2,3", "2-3", "2 3", "ZZZZZZZZZz", "\1", false }) do
  if GCA.DecodeIDs(s or nil) ~= nil then bad[#bad + 1] = tostring(s) end
end
check(#bad == 0, "rejected: zero, repeated ID, dangling high digit, separators, IDs >= 10,000,000, control bytes, nil: " .. table.concat(bad, " "))

section("Storage: a newer set replaces, an older one is ignored, an empty one clears")
local db = GCA.db
check(db.crafters == nil, "no crafters table before the first stored set (SavedVariables unchanged)")
local gen0 = GCA.crafterGen
check(GCA:StoreCrafter("Bert Hill", 100, { Leatherworking = { rank = 250, ids = { 2160, 2149, 2160 } } })
  and db.crafters["Bert Hill"].ts == 100 and db.crafters["Bert Hill"].profs.Leatherworking.ids == GCA.EncodeIDs({ 2149, 2160 })
  and db.crafters["Bert Hill"].profs.Leatherworking.rank == 250 and GCA.crafterGen == gen0 + 1,
  "stored: sorted, duplicates dropped, rank kept, index generation bumped")
check(not GCA:StoreCrafter("Bert Hill", 99, { Tailoring = { rank = 1, ids = { 2385 } } }) and db.crafters["Bert Hill"].profs.Tailoring == nil,
  "an older stamp is ignored")
check(GCA:StoreCrafter("Bert Hill", 100, { Leatherworking = { rank = 251, ids = { 2149 } } }) and db.crafters["Bert Hill"].profs.Leatherworking.rank == 251,
  "the same stamp again replaces (idempotent re-send)")
check(GCA:StoreCrafter("Bert Hill", 101, {}) and db.crafters["Bert Hill"] == nil, "an empty newer set removes the crafter")
check(not GCA:StoreCrafter("Nobody Here", 5, {}), "clearing someone unknown changes nothing")

section("Lookup: who can craft a recipe, roster members only, online first, self excluded")
advance(30)
GCA:StoreCrafter("Bert Hill", 200, { Leatherworking = { rank = 200, ids = { 2149, 2153 } } })
GCA:StoreCrafter("Finn Moor", 200, { Leatherworking = { rank = 150, ids = { 2149 } }, Tailoring = { rank = 90, ids = { 2385 } } })
GCA:StoreCrafter("Cora Vale", 200, { Leatherworking = { rank = 300, ids = { 2149 } } })
GCA:StoreCrafter("Left Guild", 200, { Leatherworking = { rank = 300, ids = { 2149 } } })
GCA:StoreCrafter(GCA.playerKey, 200, { Leatherworking = { rank = 300, ids = { 2149 } } })
check(crafterKeys(GCA:CraftersOf("Leatherworking", 2149)) == "Finn Moor+,Cora Vale-,Bert Hill-",
  "2149: online Finn first, then offline by rank (Cora 300, Bert 200); left-guild and own key left out: " .. crafterKeys(GCA:CraftersOf("Leatherworking", 2149)))
check(crafterKeys(GCA:CraftersOf("Leatherworking", 2153)) == "Bert Hill-" and crafterKeys(GCA:CraftersOf("Tailoring", 2385)) == "Finn Moor+",
  "per recipe and per profession")
check(#GCA:CraftersOf("Leatherworking", 9999) == 0 and #GCA:CraftersOf("Engineering", 2149) == 0, "nobody: empty list")
db.crafters["Cora Vale"].profs.Leatherworking.ids = "garbage;"
GCA:StoreCrafter("Dora Field", 200, { Blacksmithing = { rank = 1, ids = { 2660 } } })
check(crafterKeys(GCA:CraftersOf("Leatherworking", 2149)) == "Finn Moor+,Bert Hill-", "a damaged saved list is skipped, not an error")
GCA:ForgetCrafter(GCA.playerKey)

section("Pruning: crafters who left the guild go with their gear; members stay")
do
  local T = A.env.time()
  db.crafters["Left Guild"].time = T - 40 * 86400
  db.crafters["Just Left"] = { ts = 1, time = T - 5 * 86400, profs = {} }
  db.crafters["Crafter Only"] = { ts = 1, time = T - 40 * 86400, profs = {} }
  db.members["Left Guild"] = { class = "MAGE", level = 30, time = T - 40 * 86400, items = {} }
  db.crafters["Dora Field"].time = T - 40 * 86400
  db.rosterLast = #GUILD
  GCA.pruneDone, GCA.loginTime = nil, sched.t - 120
  A.fire("GUILD_ROSTER_UPDATE")
  check(db.crafters["Left Guild"] == nil and db.members["Left Guild"] == nil and db.crafters["Crafter Only"] == nil,
    "left the guild + 40 days: crafter entry removed with the gear, and one with no gear record too")
  check(db.crafters["Just Left"] ~= nil and db.crafters["Dora Field"] ~= nil and db.crafters["Bert Hill"] ~= nil,
    "kept: left 5 days ago, still in the guild (even if old)")
  db.crafters["Just Left"] = nil
end

section("Wire: K chunks stay under 250 bytes and give the same set back, in any order")
local LW, BS = recipeIDs(GCA, "Leatherworking"), recipeIDs(GCA, "Blacksmithing")
local halfLW = {}
for i, id in ipairs(LW) do if i % 2 == 1 then halfLW[#halfLW + 1] = id end end
local function chunksOf(set) return GCA:EncodeRecipeSet(set, GCA:Now() - 10) end
local fullChunks = chunksOf({ { line = 165, rank = 300, ids = LW }, { line = 164, rank = 275, ids = BS } })
local halfChunks = chunksOf({ { line = 165, rank = 250, ids = halfLW } })
local longest = 0
for _, m in ipairs(fullChunks) do longest = math.max(longest, #m) end
check(#fullChunks <= 8 and longest <= 250 and fullChunks[1]:match("^K;%w+;1/%d;4l;8c;") ~= nil,
  ("every LW and BS recipe (%d): %d messages, longest %d bytes"):format(#LW + #BS, #fullChunks, longest))
io.write(("  info: messages per set: every second LW recipe (%d) %d, all LW + all BS (%d) %d\n"):format(#halfLW, #halfChunks,
  #LW + #BS, #fullChunks))
for i = #fullChunks, 1, -1 do A.fire("CHAT_MSG_ADDON", "GCAdv1", fullChunks[i], "GUILD", "Emil Brook") end
local emil = db.crafters["Emil Brook"]
check(emil and sameList(GCA.DecodeIDs(emil.profs.Leatherworking.ids), LW) and sameList(GCA.DecodeIDs(emil.profs.Blacksmithing.ids), BS)
  and emil.profs.Leatherworking.rank == 300 and emil.profs.Blacksmithing.rank == 275, "received backwards: both professions, every ID, ranks")

local function NewWorld()
  for _, c in pairs(clients) do c.online = false end
  clients = {}
  sched = Kit.Scheduler({ start = sched.t, trap = true })
  bus = Kit.Bus(sched)
  bus.latency = 0.2
end
local function sent(t0, who, prefix) return bus:count(function(e) return e.t >= t0 and e.sender == who and e.msg:sub(1, #prefix) == prefix end) end
local function setTimes(t0, who)
  local out = {}
  for _, e in ipairs(bus.log) do
    if e.t >= t0 and e.sender == who and e.msg:match("^K;[^;]*;1/%d;") then out[#out + 1] = e.t end
  end
  return out
end
local function minGap(times)
  local gap = math.huge
  for i = 2, #times do gap = math.min(gap, times[i] - times[i - 1]) end
  return gap
end
local function canCraft(c, id) return crafterKeys(c.GCA:CraftersOf("Leatherworking", id)) end

section("Login: a crafter announces its set once; guildmates can look it up")
NewWorld()
A = Login("Anna Stone")
advance(120)
local t0 = sched.t
local B = Login("Bert Hill", { profs = { { 165, 250 } }, known = halfLW })
A.fire("GUILD_ROSTER_UPDATE")
advance(400)
check(#setTimes(t0, "Bert Hill") == 1 and sent(t0, "Bert Hill", "K;") == #halfChunks,
  ("Bert sent his set once: %d messages"):format(sent(t0, "Bert Hill", "K;")))
check(canCraft(A, halfLW[3]) == "Bert Hill+" and canCraft(A, LW[2]) == "", "Anna: Bert (online) crafts what he knows, nothing else")
check(sent(t0, "Anna Stone", "K;") == 0 and sent(t0, "Anna Stone", "R;") == 0, "Anna (no profession, window closed) sends no K and no R")

section("Relog with the same recipes: nothing sent")
local bdb = B.env.RavenquillExpeditionCraftDB
t0 = sched.t
B = Login("Bert Hill", { profs = { { 165, 250 } }, known = halfLW, db = bdb })
advance(900)
check(sent(t0, "Bert Hill", "K;") == 0, "15 min after relogging: no K")

section("Learning recipes: one broadcast for a burst, then at most one set per 300 s")
t0 = sched.t
for i = 1, 3 do B.known[LW[2 * i]] = true; B.fire("NEW_RECIPE_LEARNED", LW[2 * i]); advance(4) end
advance(60)
check(#setTimes(t0, "Bert Hill") == 1 and canCraft(A, LW[2]) == "Bert Hill+" and canCraft(A, LW[6]) == "Bert Hill+",
  "three recipes learned within 8 s: one set, Anna sees all three")
local t1 = sched.t
B.known[LW[8]] = true
B.fire("NEW_RECIPE_LEARNED", LW[8])
advance(150)
check(#setTimes(t1, "Bert Hill") == 0, "another recipe 60 s later: held back by the 300 s spacing")
advance(250)
check(#setTimes(t1, "Bert Hill") == 1 and canCraft(A, LW[8]) == "Bert Hill+", "sent once the spacing is over")

section("Opening the window asks once; only crafters the asker lacks answer")
local Cc = Login("Cora Vale")
advance(120)
t0 = sched.t
Cc.GCA:RequestCrafters()
advance(120)
check(#bus:sentBy("Cora Vale", function(e) return e.t >= t0 and e.msg == "R;" end) == 1 and sent(t0, "Cora Vale", "R;") == 1,
  "Cora (nothing stored) sends one empty request")
check(#setTimes(t0, "Bert Hill") == 1 and canCraft(Cc, LW[8]) == "Bert Hill+", "Bert answers with one set; Cora sees him")
Cc.GCA:RequestCrafters()
advance(60)
check(sent(t0, "Cora Vale", "R;") == 1, "opening again within 15 min: no second request")
advance(900)
t0 = sched.t
Cc.GCA:RequestCrafters()
advance(120)
local rMsg = bus:sentBy("Cora Vale", function(e) return e.t >= t0 and e.msg:sub(1, 2) == "R;" end)[1]
check(rMsg and rMsg.msg == "R;" .. GCA.b36(Cc.GCA.db.crafters["Bert Hill"].ts) and #setTimes(t0, "Bert Hill") == 0,
  "15 min later: the request lists Bert's stamp, Bert stays quiet: " .. tostring(rMsg and rMsg.msg))

section("A burst of requests: one set per 300 s at most")
advance(400)
t0 = sched.t
for i, who in ipairs({ "Dora Field", "Emil Brook", "Dora Field", "Emil Brook" }) do
  B.fire("CHAT_MSG_ADDON", "GCAdv1", "R;", "GUILD", who .. "-Realm")
  advance(i * 10)
end
advance(600)
local times = setTimes(t0, "Bert Hill")
check(#times >= 1 and #times <= 2 and minGap(times) >= 300,
  ("4 requests in 60 s: %d set(s), at least 300 s apart"):format(#times))

section("Old clients ignore K and R")
local Old = Login("Emil Brook", { files = LEGACY })
advance(180)
t0 = sched.t
local oldErr = 0
local probe = { "R;", "R;" .. GCA.b36(GCA:Now()), "K;", "K;1;1/1;0;0;" }
for _, m in ipairs(fullChunks) do probe[#probe + 1] = m end
for _, m in ipairs(probe) do
  if not pcall(Old.fire, "CHAT_MSG_ADDON", "GCAdv1", m, "GUILD", "Finn Moor") then oldErr = oldErr + 1 end
  Old.GCA.Sync.intake = {}
end
advance(120)
check(oldErr == 0 and #Old.errors == 0 and sent(t0, "Emil Brook", "") == 0 and Old.GCA.db.crafters == nil,
  "0.2.0 client: " .. #probe .. " K/R messages, no error, nothing sent, nothing stored")

section("Malformed K and R: dropped without errors, nothing stored, nothing sent")
local now36 = GCA.b36(A.GCA:Now())
local malformed = { "K;", "K;!!;1/1;4l;8c;2", "K;" .. now36 .. ";0/1;4l;8c;2", "K;" .. now36 .. ";2/1;4l;8c;2",
  "K;" .. now36 .. ";1/9;4l;8c;2", "K;" .. GCA.b36(A.GCA:Now() + 9999) .. ";1/1;4l;8c;2", "K;" .. now36 .. ";1/1;4l;zzzz;2",
  "K;" .. now36 .. ";1/1;4l;8c;20", "K;" .. now36 .. ";1/1;4l;8c;2;x", "K;" .. now36 .. ";1/1;4r;8c;2", "R;!!", "R;a;b" }
local errs = 0
t0 = sched.t
for _, m in ipairs(malformed) do
  if not pcall(A.fire, "CHAT_MSG_ADDON", "GCAdv1", m, "GUILD", "Dora Field-Realm") then errs = errs + 1 end
  if not pcall(B.fire, "CHAT_MSG_ADDON", "GCAdv1", m, "GUILD", "Dora Field-Realm") then errs = errs + 1 end
  A.RQ.Comm.intake, B.RQ.Comm.intake = {}, {}
end
advance(400)
check(errs == 0 and #A.errors == 0 and A.GCA:CrafterEntries()["Dora Field"] == nil and #setTimes(t0, "Bert Hill") == 0,
  #malformed .. " bad messages (an unknown profession among them): no error, nothing stored, Bert sends nothing")
A.fire("CHAT_MSG_ADDON", "GCAdv1", "K;" .. now36 .. ";1/2;4l;8c;2", "GUILD", "Dora Field-Realm")
A.fire("CHAT_MSG_ADDON", "GCAdv1", "K;" .. now36 .. ";2/2;4r;1;2", "GUILD", "Dora Field-Realm")
check(canCraft(A, 2) == "Dora Field-", "a set from a newer version with an unknown profession: the known one is kept")

section("Dropping the profession: one clear; an asker holding the old set gets it too")
Cc.online = false
advance(60)
t0 = sched.t
B.profs = {}
B.fire("SKILL_LINES_CHANGED")
advance(400)
local clears = bus:sentBy("Bert Hill", function(e) return e.t >= t0 and e.msg:match("^K;%w+;1/1;0;0;$") end)
check(#clears == 1 and #setTimes(t0, "Bert Hill") == 1 and canCraft(A, LW[8]) == "", "Bert sends one clear; Anna forgets him")
local cdb = Cc.env.RavenquillExpeditionCraftDB
Cc = Login("Cora Vale", { db = cdb })
advance(120)
check(canCraft(Cc, LW[8]) == "Bert Hill+", "Cora was offline: still has Bert's old set")
t0 = sched.t
Cc.GCA:RequestCrafters()
advance(120)
check(#setTimes(t0, "Bert Hill") == 1 and canCraft(Cc, LW[8]) == "", "Cora asks, Bert answers with the clear, Cora forgets him")
local Df = Login("Dora Field")
advance(120)
t0 = sched.t
Df.GCA:RequestCrafters()
advance(120)
check(sent(t0, "Dora Field", "R;") == 1 and #setTimes(t0, "Bert Hill") == 0, "a fresh asker: Bert (no profession) stays quiet")

section("Pacing: nobody sent more than the core's budget allows (4 per 60 s, 22 per 600 s)")
local w60, w600 = 0, 0
for _, g in ipairs(GUILD) do w60, w600 = math.max(w60, bus:maxPer(60, g.name)), math.max(w600, bus:maxPer(600, g.name)) end
check(w60 <= 4 and w600 <= 22, ("max messages by one client: %d in any 60 s, %d in any 600 s"):format(w60, w600))

Kit.finish()
