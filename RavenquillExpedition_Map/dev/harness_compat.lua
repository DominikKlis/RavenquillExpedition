local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness_compat%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end
local MapKit = dofile(DIR .. "/dev/mapkit.lua")
local Kit = MapKit.Kit
local check = Kit.check
local Golden = dofile(DIR .. "/../RavenquillExpedition/dev/golden.lua")
local RECORD = arg[1] == "--record"
local gold = Golden.open(DIR .. "/dev/fixtures/compat_golden.lua", RECORD)
local random = Kit.Random(4242)

local sched, bus = Kit.Setup()
local function Client(name, class, level, pos)
  return MapKit.Client(sched, bus, name, { class = class, level = level, pos = pos, random = random })
end

Kit.section("Encoder layer")
local W = Client("Anna Stone", "ROGUE", 36, { 1429, 0.4, 0.4 })
W.login()
local M = W.M
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local FLAGS = { "", "s", "t", "g", "st", "sg", "tg", "stg" }
local cases, encoded = {}, {}
for i, cls in ipairs(CLASSES) do
  for j, fl in ipairs(FLAGS) do
    local x = ({ 0.0001, 0.5, 0.9999, 0.123456 })[(i + j) % 4 + 1]
    local y = ({ 0.9999, 0.25, 0.0001, 0.654321 })[(i * j) % 4 + 1]
    local c = { mapID = 1400 + i * 7 + j, x = x, y = y, level = (i * 7 + j) % 60 + 1, class = cls, ts = 1763000000 + i * 100 + j,
      flags = fl, n = (i + j) % 40 + 1 }
    cases[#cases + 1] = c
    encoded[#encoded + 1] = M:EncodePosition(c.mapID, c.x, c.y, c.level, c.class, c.ts, c.flags, c.n)
  end
end
local b36 = W.RQ.Wire.b36
encoded[#encoded + 1] = "L;" .. b36(1763100000)
encoded[#encoded + 1] = "L;" .. b36(0)
gold:compare("map.encode", encoded, check)

Kit.section("Decoder layer")
local goldEnc = RECORD and encoded or (gold.data["map.encode"] or {})
local okDec = 0
for i, c in ipairs(cases) do
  local msg = goldEnc[i]
  local f = {}
  for v in ((msg or "") .. ";"):gmatch("([^;]*);") do f[#f + 1] = v end
  local m = msg and M:DecodePosition(f)
  local flagsOk = true
  if m then for ch in c.flags:gmatch(".") do if not m.flags[ch] then flagsOk = false end end end
  if m and m.mapID == c.mapID and math.abs(m.x - c.x) < 1 / 46655 and math.abs(m.y - c.y) < 1 / 46655
    and m.level == c.level and m.class == c.class and m.ts == c.ts and m.n == c.n and flagsOk then okDec = okDec + 1 end
end
check(okDec == #cases, ("%d/%d golden positions decode to their inputs"):format(okDec, #cases))

Kit.section("Scenario layer")
local B = Client("Bert Hill", "DRUID", 35, { 1429, 0.6, 0.6 })
B.login()
local t0 = sched.t
W.moving = true
sched:at(sched.t + 2, function()
  if W.moving and W.pos then
    local p = W.pos
    W.pos = { p[1], math.min(0.9, math.max(0.1, p[2] + (random() - 0.5) * 0.004)),
      math.min(0.9, math.max(0.1, p[3] + (random() - 0.5) * 0.004)) }
  end
end, 2)
sched:advance(600)
W.moving = false
sched:advance(400)
local lines = {}
for _, e in ipairs(bus.log) do
  if e.prefix == "RQEMap1" and e.t >= t0 then
    local f = {}
    for v in (e.msg .. ";"):gmatch("([^;]*);") do f[#f + 1] = v end
    if f[1] == "P" then f[7] = "<ts>" elseif f[1] == "L" then f[2] = "<ts>" end
    lines[#lines + 1] = ("%07.1f %s|%s"):format(e.t - t0, e.sender, table.concat(f, ";"))
  end
end
check(#lines > 3, ("scenario: %d map messages in 1000 s"):format(#lines))
gold:compare("map.scenario", lines, check)

Kit.section("SavedVariables layer: old shapes load into the same tables as before")
local function splitLines(s) local out = {} for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end return out end
local SV_CASES = {
  fresh = nil,
  v1 = { v = 1, settings = { share = false, size = 1.5 } },
  badSize = { v = 1, settings = { size = 9 } },
  wrongTypes = { settings = { share = "yes", size = "big" } },
}
for _, name in ipairs({ "fresh", "v1", "badSize", "wrongTypes" }) do
  W.env.RavenquillExpeditionMapDB = SV_CASES[name]
  W.coreNs.SetupModuleDB(W.M)
  W.M:OnLoad()
  gold:compare("sv." .. name, splitLines(Golden.Serialize(W.env.RavenquillExpeditionMapDB)), check)
end

Kit.section("Rally encoder layer")
local RALLIES = {
  { id = 1763100000, mapID = 1428, x = 0.5, y = 0.5, base = 0, label = "Schwarzfelsspitze" },
  { id = 1763100900, mapID = 1429, x = 0.0001, y = 0.9999, base = 3, label = "" },
  { id = 1763101234, mapID = 1411, x = 0.123456, y = 0.654321, base = 40, label = "Brücke über den Fluss" },
  { id = 1763199999, mapID = 1415, x = 0.9999, y = 0.0001, base = 1000, label = "Blackrock Spire" },
}
local rallyEnc = {}
for _, r in ipairs(RALLIES) do
  r.since = {}
  rallyEnc[#rallyEnc + 1] = M.EncodeRally(r)
end
rallyEnc[#rallyEnc + 1] = M.EncodeJoin("Rika Steinbeck", 1763100000)
rallyEnc[#rallyEnc + 1] = M.EncodeJoin("Anna Stone-Other Realm", 1763101234)
rallyEnc[#rallyEnc + 1] = M.EncodeCancel(1763100000)
gold:compare("map.rally.encode", rallyEnc, check)

Kit.section("Rally decoder layer")
local goldRally = RECORD and rallyEnc or (gold.data["map.rally.encode"] or {})
local okRally = 0
for i, r in ipairs(RALLIES) do
  local f = {}
  for v in ((goldRally[i] or "") .. ";"):gmatch("([^;]*);") do f[#f + 1] = v end
  local ev = M.DecodeRally(f, r.id + 1)
  if ev and ev.id == r.id and ev.mapID == r.mapID and math.abs(ev.x - r.x) < 1 / 46655 and math.abs(ev.y - r.y) < 1 / 46655
    and ev.n == r.base and ev.label == r.label then okRally = okRally + 1 end
end
check(okRally == #RALLIES, ("%d/%d golden rally calls decode to their inputs"):format(okRally, #RALLIES))

Kit.section("Rally scenario layer")
local rs, rb = Kit.Setup()
local rrandom = Kit.Random(777)
local function RallyClient(name, pos, subzone)
  return MapKit.Client(rs, rb, name, { pos = pos, random = rrandom,
    setup = function(env) env.GetSubZoneText = function() return subzone or "" end end })
end
local RA = RallyClient("Rika Steinbeck", { 1428, 0.5, 0.5 }, "Schwarzfelsspitze")
local RB = RallyClient("Bert Hill", { 1428, 0.55, 0.52 })
RA.login(); RB.login()
rs:advance(120)
local r0 = rs.t
RA.M:CallRally()
rs:advance(20)
RB.M:JoinRally("Rika Steinbeck")
rs:advance(200)
local RD = RallyClient("Dora Late", { 1428, 0.4, 0.6 })
RD.login()
rs:advance(200)
RA.M:CancelRally()
rs:advance(20)
local RALLY_ID = { R = 2, J = 3, X = 2 }
local rallyLines = {}
for _, e in ipairs(rb.log) do
  local kind = e.msg:sub(1, 1)
  if e.prefix == "RQEMap1" and e.t >= r0 and RALLY_ID[kind] and e.msg:sub(2, 2) == ";" then
    local f = {}
    for v in (e.msg .. ";"):gmatch("([^;]*);") do f[#f + 1] = v end
    f[RALLY_ID[kind]] = "<id>"
    rallyLines[#rallyLines + 1] = ("%07.1f %s|%s"):format(e.t - r0, e.sender, table.concat(f, ";"))
  end
end
check(#rallyLines == 4, ("rally scenario: call, answer, re-send for the late login, cancel (%d messages)"):format(#rallyLines))
gold:compare("map.rally.scenario", rallyLines, check)

gold:finish()
Kit.finish()
