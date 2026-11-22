local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local HL = "RavenquillExpedition_Highlights"

local function At(day, hour, min) return os.time({ year = 2026, month = 11, day = day, hour = hour, min = min or 0, sec = 0 }) end
local OFFICER = 1

local function Stubs(env)
  env.RAID_CLASS_COLORS = {}
  env.Enum = { QuestTag = {} }
  env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  function env.GetInventoryItemLink() end
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
  env.UnitFactionGroup = function() return "Alliance" end
end

local function World(now)
  local sched, bus = Kit.Setup()
  local w = { sched = sched, bus = bus, by = {} }
  function w.join(name, rank, level)
    local c = Kit.Client(sched, bus, name, { guild = "Die Gilde", realm = "Forever", locale = "deDE", class = "PALADIN",
      level = level or 60, epoch = now, random = Kit.Random(#bus.clients + 17), addons = { HL }, setup = Stubs })
    c.H = c.ns[HL].H
    if rank then bus:setRank(name, rank) end
    w.by[name] = c
    return c
  end
  function w.start()
    for _, c in pairs(w.by) do c.login() end
    sched:advance(5)
  end
  return w
end

local seq = 0
local function E(k, who, t, fields)
  seq = seq + 1
  local e = { k = k, who = who, t = t, id = ("%s#%d#%d"):format(who, t, seq) }
  for key, v in pairs(fields or {}) do e[key] = v end
  return e
end
local function Heard(c, e) return c.H:Add(e, "wire") end
local function Kill(who, day, enc, boss) return E("boss", who, At(day, 21, enc % 50), { enc = enc, boss = boss, raid = true, grp = true, n = 12 }) end

local function Bar(c)
  if c.RQ:OverviewShown() then c.RQ:ShowHome() else c.RQ:ToggleOverview() end
  return c.env.RavenquillExpeditionOverview.home.goal.bar.text:GetText()
end

local function Row(c, title)
  for _, row in ipairs(c.H:OverviewNow() or {}) do if row.title == title then return row end end
end

section("Goal progress: Molten Core bosses the guild killed this week")
do
  local w = World(At(20, 21, 30))
  local ole, lyra = w.join("Ole Fichtental", OFFICER), w.join("Lyra Distelbach")
  w.start()
  ole.RQ:SetGoal({ kind = "raid", raid = "mc" })
  w.sched:advance(10)
  Heard(lyra, Kill("Rika Steinbeck", 18, 663, "Lucifron"))
  Heard(lyra, Kill("Rika Steinbeck", 18, 664, "Magmadar"))
  Heard(lyra, Kill("Bodo Kesselring", 19, 663, "Lucifron"))
  Heard(lyra, Kill("Rika Steinbeck", 13, 665, "Gehennas"))
  Heard(lyra, Kill("Rika Steinbeck", 19, 1084, "Onyxia"))
  lyra.H:Add(Kill("Lyra Distelbach", 19, 666, "Garr"), "test")
  local goal = lyra.RQ:Goal()
  local done, total = lyra.H:GoalProgress(goal)
  check(done == 2 and total == 10, "two of Molten Core's ten bosses: Lucifron twice counts once; last week's Gehennas, "
    .. "Onyxia and a test entry do not count (" .. tostring(done) .. "/" .. tostring(total) .. ")")
  check(Bar(lyra) == "2 von 10 Bossen", "the /rq home's bar shows it: " .. tostring(Bar(lyra)))
  Heard(lyra, Kill("Mira Sturmfeder", 20, 666, "Garr"))
  check(Bar(lyra) == "3 von 10 Bossen", "a kill heard tonight moves the bar: " .. tostring(Bar(lyra)))
  ole.RQ:SetGoal({ kind = "raid", raid = "ony" })
  w.sched:advance(10)
  check(Bar(lyra) == "Geschafft! 1 von 1 Bossen", "Onyxia, killed this week, is done at once: " .. tostring(Bar(lyra)))
  check(#lyra.errors + #ole.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1] or ole.errors[1]) .. ")")
end

section("Goal progress: dungeon runs with guildmates and levels gained, counted like the Sunday edition")
do
  local w = World(At(20, 21, 30))
  local ole, lyra = w.join("Ole Fichtental", OFFICER), w.join("Lyra Distelbach")
  w.start()
  ole.RQ:SetGoal({ kind = "runs", target = 5 })
  w.sched:advance(10)
  local run = { inst = "Zul'Farrak", boss = "Häuptling Ukorz Sandskalp", n = 7, nf = 7 }
  Heard(lyra, E("run", "Bodo Kesselring", At(18, 14), run))
  Heard(lyra, E("run", "Tamo Eichengrund", At(18, 14, 2), run))
  Heard(lyra, E("run", "Mira Sturmfeder", At(19, 16), { inst = "Maraudon", boss = "Prinzessin Theradras", n = 9, nf = 9 }))
  Heard(lyra, E("run", "Bodo Kesselring", At(13, 14), run))
  Heard(lyra, E("run", "Tamo Eichengrund", At(13, 14, 1), run))
  check(Bar(lyra) == "1 von 5 Läufen",
    "one run this week had two guildmates; a solo run and last week's run do not count: " .. tostring(Bar(lyra)))
  ole.RQ:SetGoal({ kind = "levels", target = 10 })
  w.sched:advance(10)
  Heard(lyra, E("gear", "Tamo Eichengrund", At(16, 9), { item = 1, q = 2, il = 30, oil = 20, slot = 5, lvl = 41 }))
  Heard(lyra, E("level", "Tamo Eichengrund", At(19, 9), { lvl = 44 }))
  Heard(lyra, E("quest", "Mira Sturmfeder", At(17, 9), { qid = 5, title = "Q", tag = "special", lvl = 50 }))
  Heard(lyra, E("level", "Mira Sturmfeder", At(20, 9), { lvl = 52 }))
  Heard(lyra, E("level", "Rika Steinbeck", At(12, 9), { lvl = 30 }))
  check(Bar(lyra) == "5 von 10 Stufen", "Tamo went 41 to 44 and Mira 50 to 52 this week: " .. tostring(Bar(lyra)))
  check(#lyra.errors + #ole.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1] or ole.errors[1]) .. ")")
end

section("Now rows: raid readiness for a raid goal, and the Sunday edition")
do
  local w = World(At(22, 18))
  local ole, lyra = w.join("Ole Fichtental", OFFICER), w.join("Lyra Distelbach")
  w.join("Hanne Moosgrund", nil, 40)
  w.start()
  check(Row(lyra, "Raidbereitschaft") == nil, "without a goal there is no raid readiness row")
  ole.RQ:SetGoal({ kind = "raid", raid = "mc" })
  w.sched:advance(10)
  local row = Row(lyra, "Raidbereitschaft")
  check(row and row.line == "Dir fehlt noch: Kernfragment aus den Schwarzfelstiefen" and row.action == "Ansehen",
    "a Molten Core goal: the row tells Lyra the step she still needs: " .. tostring(row and row.line))
  if row then row.open() end
  local page = lyra.env.RavenquillExpeditionOverview.optView.pages.Highlights
  check(lyra.RQ.optionsModule == "Highlights" and page and page.mode == "raid" and lyra.H:Settings().raidFocus == "mc",
    "'Ansehen' opens the Raidbereitschaft view on Molten Core")
  lyra.H:DeclareAttuned("mc")
  ole.H:DeclareAttuned("mc")
  w.sched:advance(60)
  row = Row(lyra, "Raidbereitschaft")
  check(row and row.line == "2 von 2 bereit für Geschmolzener Kern",
    "once attuned, the row counts who is ready at raid level: " .. tostring(row and row.line))
  ole.RQ:SetGoal({ kind = "raid", raid = "zg" })
  w.sched:advance(10)
  check(Row(lyra, "Raidbereitschaft") == nil, "Zul'Gurub needs no attunement, so no row")
  Heard(lyra, E("loot", "Rika Steinbeck", At(22, 17), { item = 5001, q = 4 }))
  row = Row(lyra, "Rabenblatt")
  check(row and row.line:find("^Sonntagsausgabe: ") and row.action == "Lesen",
    "on Sunday, news makes the Rabenblatt row point at the Sunday edition: " .. tostring(row and row.line))
  check(#lyra.errors + #ole.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1] or ole.errors[1]) .. ")")
end

Kit.finish()
