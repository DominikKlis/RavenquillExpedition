local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua",
  "RecipeSources.lua", "UI" } }))

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

Kit.finish()
