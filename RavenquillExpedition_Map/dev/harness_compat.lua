local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness_compat%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end
package.path = DIR .. "/dev/?.lua;" .. package.path
local Mock = require("mock")
local Golden = dofile(DIR .. "/../RavenquillExpedition/dev/golden.lua")
local RECORD = arg[1] == "--record"
local gold = Golden.open(DIR .. "/dev/fixtures/compat_golden.lua", RECORD)
math.random = Golden.Random(4242)

local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end

local sched = Mock.Scheduler()
local bus = Mock.Bus(sched)
local function Client(name, class, level, pos)
  bus:member(name, class, level)
  return Mock.NewWorld({ sched = sched, bus = bus, name = name, class = class, level = level, pos = pos,
    dir = DIR })
end

print("== Encoder layer")
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

print("== Decoder layer")
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

print("== Scenario layer")
local B = Client("Bert Hill", "DRUID", 35, { 1429, 0.6, 0.6 })
B.login()
local t0 = sched.t
W.moving = true
sched:at(sched.t + 2, function()
  if W.moving and W.pos then
    local p = W.pos
    W.pos = { p[1], math.min(0.9, math.max(0.1, p[2] + (math.random() - 0.5) * 0.004)),
      math.min(0.9, math.max(0.1, p[3] + (math.random() - 0.5) * 0.004)) }
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

print("== SavedVariables layer: old shapes load into the same tables as before")
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

gold:finish()
print(("%d passed, %d failed, 0 skipped"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
