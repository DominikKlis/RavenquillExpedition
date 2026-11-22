local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local GM, OFFICER = 0, 1
local SUNDAY_9PM = os.time({ year = 2026, month = 11, day = 22, hour = 21, min = 0, sec = 0 })

local function Released(env)
  env.C_AddOns.GetAddOnMetadata = function(_, field) if field == "Version" then return "0.10.0-beta" end end
end

local function Join(sched, bus, name, rank, opts)
  opts = opts or {}
  local c = Kit.Client(sched, bus, name, { locale = opts.locale or "deDE", random = Kit.Random(#bus.clients + 3),
    setup = opts.setup, epoch = opts.epoch })
  if rank then bus:setRank(name, rank) end
  return c
end

local function Guild(names, opts)
  local sched, bus = Kit.Setup()
  local by = {}
  for _, n in ipairs(names) do by[n[1]] = Join(sched, bus, n[1], n.rank, opts) end
  return sched, bus, by
end

local function GoalMessages(bus, since, pred)
  return bus:count(function(e) return e.t >= since and e.msg:sub(1, 2) == "G;" and (not pred or pred(e)) end)
end

local function Shows(c, kind, extra, setBy)
  local g = c.RQ:Goal()
  if not (g and g.kind == kind and g.setBy == setBy) then return false end
  for k, v in pairs(extra) do if g[k] ~= v then return false end end
  return true
end

local function All(clients, pred)
  for _, c in ipairs(clients) do if not pred(c) then return false, c.name end end
  return true
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

section("Weekly goal: officers set it, the core carries it to every client")
do
  local world = { epoch = SUNDAY_9PM, setup = Released }
  local sched, bus, by = Guild({ { "Ole Fichtental", rank = OFFICER }, { "Rika Steinbeck" }, { "Hanne Moosgrund" },
    { "Bodo Kesselring", rank = OFFICER } }, world)
  local ole, rika, hanne, bodo = by["Ole Fichtental"], by["Rika Steinbeck"], by["Hanne Moosgrund"], by["Bodo Kesselring"]
  local online = { ole, rika, hanne, bodo }
  for _, c in ipairs(online) do c.login() end
  sched:advance(180)
  check(GoalMessages(bus, 0) == 0 and All(online, function(c) return c.RQ:Goal() == nil end),
    "without a goal, logins cost no goal message and nobody shows one")

  check(rika.RQ:SetGoal({ kind = "raid", raid = "mc" }) == false, "a member who is not an officer cannot set a goal")
  check(ole.RQ:SetGoal({ kind = "runs", target = 0 }) == false and ole.RQ:SetGoal({ kind = "raid", raid = "karazhan" }) == false
    and ole.RQ:SetGoal({ kind = "duels", target = 5 }) == false, "a goal outside the kinds and their ranges is refused")
  sched:advance(10)
  check(GoalMessages(bus, 0) == 0 and All(online, function(c) return c.RQ:Goal() == nil end), "and none of that is sent")

  local mark = sched.t
  check(ole.RQ:SetGoal({ kind = "raid", raid = "mc" }) == true, "an officer sets 'Molten Core: all bosses'")
  sched:advance(5)
  local ok, who = All(online, function(c) return Shows(c, "raid", { raid = "mc" }, "Ole Fichtental") end)
  check(ok, "every client shows the officer's goal (" .. (who or "all") .. ")")
  check(GoalMessages(bus, mark) == 1, "setting it costs exactly one guild message: " .. GoalMessages(bus, mark))

  local week = ole.RQ:Goal().week
  rika.RQ.Comm.tags.G:Send("g", { kind = "levels", target = 20, by = "Rika Steinbeck", week = week, ver = rika.RQ:Now() })
  sched:advance(30)
  ok, who = All({ ole, hanne, bodo }, function(c) return Shows(c, "raid", { raid = "mc" }, "Ole Fichtental") end)
  check(ok and GoalMessages(bus, mark, function(e) return e.sender == "Rika Steinbeck" end) == 1,
    "a goal message a member sends past the UI is ignored by every receiver, who checks the setter's rank (" .. (who or "all") .. ")")

  mark = sched.t
  sched:advance(1800)
  check(GoalMessages(bus, mark) <= 1, "half an hour without logins: at most the one correction to Rika's message, nothing else: "
    .. GoalMessages(bus, mark))

  mark = sched.t
  local mira = Join(sched, bus, "Mira Sturmfeder", nil, world)
  for _, c in ipairs(online) do c.fire("GUILD_ROSTER_UPDATE") end
  mira.login()
  sched:advance(150)
  check(Shows(mira, "raid", { raid = "mc" }, "Ole Fichtental"), "a guildmate who logs in later learns the goal")
  check(GoalMessages(bus, mark) == 1, "from one answer, not one per guildmate who has it: " .. GoalMessages(bus, mark))
  online[#online + 1] = mira

  ole.online = false
  bus:setOnline("Ole Fichtental", false)
  online = { rika, hanne, bodo, mira }
  mark = sched.t
  local tamo = Join(sched, bus, "Tamo Eichengrund", nil, world)
  for _, c in ipairs(online) do c.fire("GUILD_ROSTER_UPDATE") end
  tamo.login()
  sched:advance(150)
  check(Shows(tamo, "raid", { raid = "mc" }, "Ole Fichtental")
    and GoalMessages(bus, mark) == 1 and GoalMessages(bus, mark, function(e) return e.sender == "Ole Fichtental" end) == 0,
    "with the officer offline a guildmate passes the goal on, still as Ole's")
  online[#online + 1] = tamo

  mark = sched.t
  check(bodo.RQ:SetGoal({ kind = "runs", target = 15 }) == true, "a second officer sets a newer goal")
  sched:advance(5)
  ok, who = All(online, function(c) return Shows(c, "runs", { target = 15 }, "Bodo Kesselring") end)
  check(ok and GoalMessages(bus, mark) == 1, "the newer goal replaces the old one everywhere, again for one message ("
    .. (who or "all") .. ", " .. GoalMessages(bus, mark) .. ")")
  local olesMessage
  for _, e in ipairs(bus.log) do if e.sender == "Ole Fichtental" and e.msg:sub(1, 2) == "G;" then olesMessage = e.msg end end
  hanne.fire("CHAT_MSG_ADDON", "RQE1", olesMessage, "GUILD", "Ole Fichtental-Realm")
  sched:advance(30)
  check(Shows(hanne, "runs", { target = 15 }, "Bodo Kesselring"), "the older goal heard again does not come back")
  check(bodo.RQ:SetGoal({ kind = "levels", target = 30 }) == true, "the same officer changes the goal again")
  sched:advance(5)
  ok, who = All(online, function(c) return Shows(c, "levels", { target = 30 }, "Bodo Kesselring") end)
  check(ok, "and that replaces their earlier one (" .. (who or "all") .. ")")

  local toMidnight = SUNDAY_9PM + 3 * 3600 - bodo.RQ:Now()
  sched:advance(toMidnight - 30)
  check(Shows(hanne, "levels", { target = 30 }, "Bodo Kesselring"), "on Sunday at 23:59 the goal still stands")
  sched:advance(60)
  ok, who = All(online, function(c) return c.RQ:Goal() == nil end)
  check(ok, "at the start of Monday it has ended on every client (" .. (who or "all") .. ")")
  hanne.fire("PLAYER_LOGIN")
  check(hanne.RQ:Goal() == nil and next(hanne.env.RavenquillExpeditionDB.goals[hanne.RQ:GuildKey()]) == nil,
    "and the next login drops last week's goal from the saved variables")
  check(bodo.RQ:SetGoal({ kind = "raid", raid = "bwl" }) == true, "an officer can set the new week's goal")
  sched:advance(5)
  ok, who = All(online, function(c) return Shows(c, "raid", { raid = "bwl" }, "Bodo Kesselring") end)
  check(ok, "and every client takes it (" .. (who or "all") .. ")")
  local errors = 0
  for _, c in pairs(by) do errors = errors + #c.errors end
  check(errors + #mira.errors + #tamo.errors == 0, "no Lua errors")
end

Kit.finish()
