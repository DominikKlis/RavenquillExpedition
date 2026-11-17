local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local ROOT = DEV .. "../"
local RECORD = arg[1] == "--record"
local Golden = dofile(DEV .. "../../RavenquillExpedition/dev/golden.lua")
local gold = Golden.open(DEV .. "fixtures/compat_golden.lua", RECORD)

local fails, passes = 0, 0
local function check(cond, label)
  if cond then passes = passes + 1; print("  ok   " .. label)
  else fails = fails + 1; print("  FAIL " .. label) end
end
local function section(s) print("== " .. s) end

local GEAR = dofile(DEV .. "fixtures/gear_sets.lua")
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

local now = 0
local timers, tseq = {}, 0
local function addTimer(d, fn) tseq = tseq + 1; timers[#timers + 1] = { at = now + d, seq = tseq, fn = fn } end
local function advance(sec)
  local target = now + sec
  while true do
    table.sort(timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    local t = timers[1]
    if not t or t.at > target then break end
    table.remove(timers, 1); now = t.at
    local ok, err = pcall(t.fn)
    if not ok then fails = fails + 1; print("  FAIL timer error: " .. tostring(err)) end
  end
  now = target
end

local GUILD = {
  { name = "Anna Stone", class = "ROGUE", level = 36 },
  { name = "Bert Hill", class = "DRUID", level = 35 },
  { name = "Cora Vale", class = "HUNTER", level = 31 },
  { name = "Dora Field", class = "WARRIOR", level = 35 },
}
local GUILD_BY = {}
for _, g in ipairs(GUILD) do GUILD_BY[g.name] = g end

local clients, busLog = {}, {}
local function deliver(from, prefix, msg)
  busLog[#busLog + 1] = { t = now, from = from.name, msg = msg }
  for _, c in pairs(clients) do
    if c.online then
      addTimer(0.2, function() if c.online then c.fire("CHAT_MSG_ADDON", prefix, msg, "GUILD", from.name) end end)
    end
  end
end

local function strsplit(sep, s)
  local out, pos = {}, 1
  while true do
    local i = s:find(sep, pos, true)
    if not i then out[#out + 1] = s:sub(pos) break end
    out[#out + 1] = s:sub(pos, i - 1); pos = i + 1
  end
  return table.unpack(out)
end

local FILES = dofile(DEV .. "files.lua").list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Auction.lua",
  "RecipeSources.lua", "UI" } })
local LEGACY = { "Data/Leatherworking.lua", "dev/fixtures/compat_0.2.0/Core.lua", "dev/fixtures/compat_0.2.0/Sync.lua" }

local function NewClient(name, gear, opts)
  opts = opts or {}
  local first, surname = name:match("^(%S+) (%S+)$")
  local g = GUILD_BY[name]
  local c = { name = name, online = true, gear = gear, prints = {} }
  local env = setmetatable({}, { __index = _G })
  env.math = setmetatable({ random = Golden.Random(opts.seed or #name) }, { __index = math })
  local frames = {}
  local Frame = {}
  Frame.__index = Frame
  function Frame:SetScript(ev, fn) self.scripts[ev] = fn end
  function Frame:RegisterEvent(ev) self.events[ev] = true end
  function Frame:UnregisterEvent(ev) self.events[ev] = nil end
  env.CreateFrame = function()
    local f = setmetatable({ scripts = {}, events = {} }, Frame)
    frames[#frames + 1] = f
    return f
  end
  c.fire = function(ev, ...)
    if ev == "ADDON_LOADED" and ... == "RavenquillExpedition_CraftAdvisor" and c.core and not c.coreLoaded then
      c.coreLoaded = true
      c.fire("ADDON_LOADED", "RavenquillExpedition")
    end
    for _, f in ipairs(frames) do
      if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
    end
  end
  env.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end c.prints[#c.prints + 1] = table.concat(t, " ") end
  env.unpack = table.unpack
  env.strsplit = strsplit
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.tinsert = table.insert
  env.time = function() return 1800000000 + math.floor(now) end
  env.GetTime = function() return now end
  env.GetServerTime = env.time
  env.C_Timer = { After = function(d, fn) addTimer(d, function() if c.online then fn() end end) end }
  env.GetBuildInfo = function() return "1.60.1", "70938", "", 16001 end
  env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
  env.Ambiguate = function(n) return n end
  env.SlashCmdList = {}
  env.IsInGuild = function() return true end
  env.IsInInstance = function() return false end
  env.InCombatLockdown = function() return false end
  env.GetRealmName = function() return "Realm" end
  env.IsInRaid = function() return false end
  env.GetNumSubgroupMembers = function() return 0 end
  local function U(u)
    if u == "player" then return { first = first, surname = surname, class = g.class, level = g.level, guid = "G-" .. name, items = c.gear } end
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
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, chan)
      assert(#msg <= 255, "message over 255 bytes: " .. #msg)
      assert(chan == "GUILD", "non-GUILD send: " .. tostring(chan))
      deliver(c, prefix, msg)
      return 0
    end,
  }
  env.RavenquillExpeditionCraftDB = {}
  c.setDB = function(db) env.RavenquillExpeditionCraftDB = db end
  c.getDB = function() return env.RavenquillExpeditionCraftDB end
  local ns = {}
  if not opts.files then c.core = dofile(ROOT .. "dev/corekit.lua")(env); c.core.done(); c.RQ = c.core.RQ end
  for _, f in ipairs(opts.files or FILES) do
    assert(loadfile(ROOT .. f, "t", env))("RavenquillExpedition_CraftAdvisor", ns)
  end
  c.GCA = ns.GCA
  return c
end

local function Login(name, gear, opts)
  local c = NewClient(name, gear, opts)
  clients[name] = c
  c.fire("ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
  c.fire("PLAYER_LOGIN")
  c.fire("PLAYER_ENTERING_WORLD", true, false)
  c.fire("GUILD_ROSTER_UPDATE")
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
timers, busLog = {}, {}
local t0 = now
Login("Anna Stone", copy(GEAR[1]), { seed = 7 })
advance(5)
Login("Bert Hill", copy(GEAR[2]), { seed = 11 })
advance(900)
local seen = {}
for _, e in ipairs(busLog) do
  local f = { strsplit(";", e.msg) }
  if f[1] == "G" then f[5] = "<ts>" elseif f[1] == "S" then f[3] = "<ts>" end
  seen[#seen + 1] = ("%s|%s"):format(e.from, table.concat(f, ";"))
end
check(#seen > 0, ("scenario sent %d messages in %d s"):format(#seen, now - t0))
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
  timers = {}
  local c = NewClient("Anna Stone", copy(GEAR[1]))
  clients["Anna Stone"] = c
  c.setDB(SV_CASES[name])
  c.fire("ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
  c.fire("PLAYER_LOGIN")
  local db, shown = c.getDB(), {}
  for k, v in pairs(db) do if k ~= "v" and k ~= "vLogin" then shown[k] = v end end
  check(db.v == 3 and db.vLogin == 2, "sv." .. name .. ": core migration counters v = 3, vLogin = 2")
  gold:compare("sv." .. name, splitLines(Golden.Serialize(shown)), check)
end

gold:finish()
print(("%d passed, %d failed, 0 skipped"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
