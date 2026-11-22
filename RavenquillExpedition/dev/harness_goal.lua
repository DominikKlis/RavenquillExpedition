local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local GM, OFFICER = 0, 1

local function Guild(names)
  local sched, bus = Kit.Setup()
  local by = {}
  for _, n in ipairs(names) do
    local c = Kit.Client(sched, bus, n[1], { locale = n.locale or "deDE", random = Kit.Random(#bus.clients + 3),
      setup = n.setup })
    by[n[1]] = c
    if n.rank then bus:setRank(n[1], n.rank) end
  end
  return sched, bus, by
end

section("Officers: guild ranks whose permissions include reading officer chat")
do
  local sched, bus, by = Guild({ { "Rika Steinbeck", rank = GM }, { "Ole Fichtental", rank = OFFICER }, { "Hanne Moosgrund" } })
  bus:member("Bodo Kesselring", "PALADIN", 52, false)
  bus:setRank("Bodo Kesselring", 5)
  local hanne = by["Hanne Moosgrund"]
  local RQ = hanne.RQ
  check(RQ:IsOfficer("Rika Steinbeck") == nil, "before the guild roster is read, nobody is known to be an officer")
  for _, c in pairs(by) do c.login() end
  sched:advance(5)
  check(RQ:IsOfficer("Rika Steinbeck") == true, "the guild master (rank 0) is an officer")
  check(RQ:IsOfficer("Ole Fichtental") == true, "a rank whose permissions include officer chat is an officer")
  check(RQ:IsOfficer("Hanne Moosgrund") == false and RQ:IsOfficer("Bodo Kesselring") == false,
    "a member rank, and a rank the game reports no permissions for, are not")
  check(RQ:IsOfficer("Niemand Hier") == false, "someone outside the guild is not an officer")
  check(by["Ole Fichtental"].RQ:IsOfficer(by["Ole Fichtental"].RQ:PlayerKey()) == true, "an officer's client knows its own rights")
  bus:setRank("Hanne Moosgrund", OFFICER)
  hanne.fire("GUILD_ROSTER_UPDATE")
  check(RQ:IsOfficer("Hanne Moosgrund") == true, "a promotion counts from the next roster read")
  hanne.env.C_GuildInfo.GuildControlGetRankFlags = nil
  check(RQ:IsOfficer("Rika Steinbeck") == true and RQ:IsOfficer("Ole Fichtental") == false,
    "without the rank permissions API only the guild master counts")
end

Kit.finish()
