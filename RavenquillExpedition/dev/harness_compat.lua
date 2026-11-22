local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check = Kit.check
local Golden = dofile(DEV .. "golden.lua")
local RECORD = arg[1] == "--record"
local gold = Golden.open(DEV .. "fixtures/compat_golden.lua", RECORD)

local function Released(version)
  return function(env)
    env.C_AddOns.GetAddOnMetadata = function(_, field) if field == "Version" then return version end end
  end
end

local sched, bus = Kit.Setup()
local random = Kit.Random(4242)

Kit.section("Encoder layer: the core's V channel (announcement and answer)")
local bert = Kit.Client(sched, bus, "Bert Hill", { random = random, setup = Released("0.10.0-beta") })
local V = bert.RQ.Comm.tags.V
local VERSIONS = { "0.10.0-beta", "1.0.0", "0.9.2-alpha", "dev", string.rep("9", 30) }
local encoded = {}
for _, ver in ipairs(VERSIONS) do encoded[#encoded + 1] = V:Encode("v", { ver = ver }) or "<nil>" end
encoded[#encoded + 1] = V:Encode("p", {}) or "<nil>"
gold:compare("core.v.encode", encoded, check)

Kit.section("Decoder layer")
local goldEnc = RECORD and encoded or (gold.data["core.v.encode"] or {})
local okDec = 0
for i, ver in ipairs(VERSIONS) do
  local typ, msg = V:Decode("Anna Stone", (goldEnc[i] or ""):match("^V;(.*)$"))
  if typ == "v" and msg.ver == ver:sub(1, 24) then okDec = okDec + 1 end
end
local typ = V:Decode("Anna Stone", (goldEnc[#VERSIONS + 1] or ""):match("^V;(.*)$"))
if typ == "p" then okDec = okDec + 1 end
check(okDec == #VERSIONS + 1, ("%d/%d golden V messages decode to what was sent"):format(okDec, #VERSIONS + 1))

Kit.section("Scenario layer: a login after two silent guildmates")
local cora = Kit.Client(sched, bus, "Cora Vale", { random = random })
bert.login(); cora.login()
sched:advance(1800)
local t0 = sched.t
local anna = Kit.Client(sched, bus, "Anna Stone", { random = random, setup = Released("0.10.0-beta") })
anna.login()
sched:advance(400)
local lines = {}
for _, e in ipairs(bus.log) do
  if e.prefix == "RQE1" and e.t >= t0 then lines[#lines + 1] = ("%07.1f %s|%s"):format(e.t - t0, e.sender, e.msg) end
end
check(#lines == 3, ("scenario: %d core messages in 400 s after the login"):format(#lines))
gold:compare("core.presence.scenario", lines, check)

gold:finish()

Kit.section("Goal channel G: the weekly goal's wire bytes")
local goalGold = Golden.open(DEV .. "fixtures/compat_goal.lua", arg[1] == "--record-goal")
local WEDNESDAY_NOON_UTC = 1795003200
local gsched, gbus = Kit.Setup()
local function GoalClient(name, seed)
  return Kit.Client(gsched, gbus, name, { random = Kit.Random(seed), epoch = WEDNESDAY_NOON_UTC, setup = Released("0.10.0-beta") })
end
local ole = GoalClient("Ole Fichtental", 11)
gbus:setRank("Ole Fichtental", 1)
local G = ole.RQ.Comm.tags.G
local GOALS = {
  { kind = "raid", raid = "mc", by = "Ole Fichtental", week = 20408, ver = 1795003200 },
  { kind = "runs", target = 15, by = "Bodo Kesselring", week = 20408, ver = 1795003140 },
  { kind = "levels", target = 200, by = "Ole Fichtental", week = 20408, ver = 1795002000 },
  { kind = "raid", raid = "naxx", by = "Mira Sturmfeder", week = 20415, ver = 1794990000 },
}
local goalLines = {}
for i, m in ipairs(GOALS) do goalLines[i] = G:Encode("g", m) or "<nil>" end
goalGold:compare("goal.encode", goalLines, check)
local goldGoals = goalGold.data["goal.encode"] or goalLines
local decoded = 0
for i, m in ipairs(GOALS) do
  local kind, got = G:Decode("Anna Stone", (goldGoals[i] or ""):match("^G;(.*)$"))
  local same = kind == "g"
  for k, v in pairs(m) do if got and got[k] ~= v then same = false end end
  if same then decoded = decoded + 1 end
end
check(decoded == #GOALS, ("%d/%d golden G messages decode to what was sent"):format(decoded, #GOALS))

local rika = GoalClient("Rika Steinbeck", 12)
ole.login(); rika.login()
gsched:advance(120)
local g0 = gsched.t
ole.RQ:SetGoal({ kind = "raid", raid = "mc" })
gsched:advance(60)
local mira = GoalClient("Mira Sturmfeder", 13)
ole.fire("GUILD_ROSTER_UPDATE"); rika.fire("GUILD_ROSTER_UPDATE")
mira.login()
gsched:advance(240)
local goalScenario = {}
for _, e in ipairs(gbus.log) do
  if e.prefix == "RQE1" and e.t >= g0 then goalScenario[#goalScenario + 1] = ("%07.1f %s|%s"):format(e.t - g0, e.sender, e.msg) end
end
goalGold:compare("goal.scenario", goalScenario, check)
check(mira.RQ:Goal() ~= nil and mira.RQ:Goal().raid == "mc", "scenario: the late login learns the goal")
goalGold:finish()
Kit.finish()
