local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local HL = "RavenquillExpedition_Highlights"

local function At(day, hour, min) return os.time({ year = 2026, month = 11, day = day, hour = hour, min = min or 0, sec = 0 }) end
local NOW = At(20, 20, 0)
local OFFICER = 1
local TOWN = { name = "Burgschmied", itype = "none" }

local function Split(key) return key:match("^(%S+) (.+)$") end

local function Stubs(c, env)
  env.RAID_CLASS_COLORS = {}
  env.Enum = { QuestTag = {} }
  env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  function env.GetInventoryItemLink() end
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
  env.UnitFactionGroup = function() return "Alliance" end
  env.PlaySound = function(kit) c.sounds[#c.sounds + 1] = kit end
  env.IsInInstance = function() return c.place.itype ~= "none", c.place.itype end
  env.GetInstanceInfo = function() return c.place.name, c.place.itype, nil, nil, nil, nil, nil, c.place.id end
  env.GetRealZoneText = function() return c.place.name end
  env.GetNumGroupMembers = function() return #c.party end
  env.IsInRaid = function() return c.raid end
  local first, surname = Split(c.name)
  local function Name(unit)
    if unit == "player" then return first, surname end
    local i = tonumber(tostring(unit):match("^%a+(%d+)$"))
    local key = i and c.party[i]
    if key then return Split(key) end
  end
  env.UnitName, env.UnitNameUnmodified = Name, Name
end

local function World()
  local sched, bus = Kit.Setup()
  local w = { sched = sched, bus = bus, by = {}, list = {} }
  function w.join(name, opts)
    opts = opts or {}
    local c = Kit.Client(sched, bus, name, { guild = "Die Gilde", realm = "Forever", locale = opts.locale or "deDE",
      class = opts.class or "PALADIN", level = opts.level or 60, epoch = NOW, random = Kit.Random(#bus.clients + 31),
      addons = { HL }, setup = function(env, cl)
        cl.place, cl.party, cl.raid, cl.sounds = TOWN, {}, false, {}
        Stubs(cl, env)
      end })
    c.H = c.ns[HL].H
    if opts.rank then bus:setRank(name, opts.rank) end
    w.by[name] = c
    w.list[#w.list + 1] = c
    return c
  end
  function w.start()
    for _, c in ipairs(w.list) do c.login() end
    for _, c in ipairs(w.list) do
      for _, o in ipairs(w.list) do if o ~= c then c.RQ:NotePeer(o.name) end end
    end
    sched:advance(5)
  end
  function w.group(members, raid)
    for _, c in ipairs(members) do
      if type(c) == "table" then
        c.party, c.raid = {}, raid or false
        for _, o in ipairs(members) do c.party[#c.party + 1] = type(o) == "table" and o.name or o end
      end
    end
  end
  function w.go(members, place)
    for _, c in ipairs(members) do
      if type(c) == "table" then
        c.place = place
        c.fire("PLAYER_ENTERING_WORLD", false, false)
      end
    end
  end
  function w.kill(members, enc, boss)
    for _, c in ipairs(members) do
      if type(c) == "table" then c.fire("ENCOUNTER_END", enc, boss, 9, 40, 1) end
    end
  end
  function w.settle(seconds) sched:advance(seconds or 300) end
  return w
end

local function Count(list, pred)
  local n = 0
  for _, e in ipairs(list) do if pred(e) then n = n + 1 end end
  return n
end
local function OfKind(k) return function(e) return e.k == k end end
local function Sent(w, code) return w.bus:count(function(m) return m.msg:find("^H;1;" .. code .. ";") ~= nil end) end
local function Lines(c) return (c.H:LogLines()) end
local function PaperEntries(c)
  local out = {}
  for _, day in ipairs(c.H:Issues()) do for _, e in ipairs(day.entries) do out[#out + 1] = e end end
  return out
end
local function Errors(w)
  local n, first = 0, nil
  for _, c in ipairs(w.list) do
    n = n + #c.errors
    first = first or c.errors[1]
  end
  return n, first
end

local MC = { name = "Geschmolzener Kern", itype = "raid", id = 409 }

section("Raid boss kills: kept for the weekly raid goal, but no line in the chronicle, the paper or chat")
do
  local w = World()
  local ole = w.join("Ole Fichtental", { rank = OFFICER })
  local rika, lyra = w.join("Rika Steinbeck"), w.join("Lyra Distelbach")
  w.bus:member("Bodo Kesselring", "PALADIN", 60)
  w.start()
  ole.RQ:SetGoal({ kind = "raid", raid = "mc" })
  lyra.H:Settings().chat = true
  w.settle(10)
  local printedBefore = #lyra.printed
  local raid = { rika, "Bodo Kesselring" }
  w.group(raid, true)
  w.go(raid, MC)
  w.kill(raid, 663, "Lucifron")
  w.settle(600)
  w.kill(raid, 664, "Magmadar")
  w.go(raid, TOWN)
  w.settle(300)
  check(Sent(w, "b") == 2, "the raid's two kills each went to the guild once (" .. Sent(w, "b") .. ")")
  check(Count(lyra.H:Log(), OfKind("boss")) == 2, "Lyra keeps both kills")
  check(Count(Lines(lyra), OfKind("boss")) == 0 and Count(PaperEntries(lyra), OfKind("boss")) == 0,
    "neither kill is a line in her chronicle or her paper")
  check(#lyra.printed == printedBefore and lyra.H:NewSinceLastLook() == 0,
    "no chat line and nothing new to read, although chat is on")
  local done, total = lyra.H:GoalProgress(lyra.RQ:Goal())
  check(done == 2 and total == 10, "the weekly raid goal counts both: " .. tostring(done) .. " of " .. tostring(total))
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Group reports: one report per group moment, also when two guildmates report it at the same time")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  w.bus:member("Cara Moss", "MAGE", 60)
  w.bus:member("Bud Stone", "DRUID", 60)
  w.start()
  local function Report(who, seq, t)
    return { k = "boss", t = t, who = who, id = ("%s#%d#%d"):format(who, t, seq), enc = 672, boss = "Ragnaros",
      inst = MC.name, raid = true, grp = true, n = 12, lvl = 60 }
  end
  lyra.H:Add(Report("Cara Moss", 1, NOW - 3000), "wire")
  lyra.H:Add(Report("Bud Stone", 2, NOW - 2960), "wire")
  lyra.H:Add(Report("Bud Stone", 3, NOW - 3000 + lyra.H.BOSS_SAME + 60), "wire")
  check(Count(lyra.H:Log(), OfKind("boss")) == 2,
    "Bud's report of the same Ragnaros kill is not stored again; a kill after the same-kill window is ("
    .. Count(lyra.H:Log(), OfKind("boss")) .. ")")
end

local DEADMINES = { name = "Die Todesminen", itype = "party", id = 36 }

local function Story(c)
  local days = c.H:Issues()
  local News = c.ns[HL].News
  local issue = days[#days] and News.Issue(days[#days], c.RQ.NewLocale(c.ns[HL].NewsLocales), c.H:NewsContext())
  return issue and issue.lead or {}
end

section("Guild group: one line for a dungeon run with guildmates, every name, sent once by one of them")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach", { rank = OFFICER })
  local ole, hanne, tamo = w.join("Ole Fichtental"), w.join("Hanne Moosgrund"), w.join("Tamo Eichengrund")
  w.start()
  lyra.RQ:SetGoal({ kind = "runs", target = 5 })
  hanne.H:Settings().chat = true
  local party = { ole, hanne, tamo }
  w.group(party)
  w.go(party, DEADMINES)
  w.kill(party, 1144, "Edwin VanCleef")
  w.go({ ole }, TOWN)
  w.settle(ole.H.RUN_GRACE + 200)
  check(Sent(w, "o") == 1 and Count(hanne.H:Log(), OfKind("group")) == 1,
    "Ole leaves first: his line for the group reaches Hanne while she is still inside")
  w.go({ hanne, tamo }, TOWN)
  w.settle(ole.H.RUN_GRACE + 600)
  check(Sent(w, "o") == 1, "Hanne and Tamo leave later and send nothing: one message for the run (" .. Sent(w, "o") .. ")")
  local lines = {}
  for _, c in ipairs({ lyra, ole, hanne, tamo }) do lines[#lines + 1] = Count(Lines(c), OfKind("group")) end
  check(table.concat(lines, ",") == "1,1,1,1", "every chronicle has exactly one line for it (" .. table.concat(lines, ",") .. ")")
  local e = lyra.H:Log()[#lyra.H:Log()]
  local text = lyra.H:Format(e)
  check(text:find("Ole Fichtental", 1, true) and text:find("Hanne Moosgrund", 1, true) and text:find("Tamo Eichengrund", 1, true)
    and text:find("Die Todesminen|r geschafft", 1, true) and not text:find("Boss", 1, true),
    "the line names all three and the dungeon, without a boss count: " .. text)
  check(lyra.H:NewSinceLastLook() == 1 and hanne.H:NewSinceLastLook() == 0 and tamo.H:NewSinceLastLook() == 0,
    "it is new to Lyra, who was not there, and not to the ones who were")
  check(select(1, lyra.H:GoalProgress(lyra.RQ:Goal())) == 1, "the weekly runs goal counts the run once")
  local lead = Story(lyra)
  check(lead.k == "group" and ((lead.head or ""):find("Die Todesminen", 1, true) or (lead.head or ""):find("Ole Fichtental", 1, true)),
    "the paper tells it as a guild group story: " .. tostring(lead.head))
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Guild group: a run without guildmates is no line, and an old guildmate's run entry still reads")
do
  local w = World()
  local ole, lyra = w.join("Ole Fichtental"), w.join("Lyra Distelbach")
  w.start()
  w.go({ ole }, DEADMINES)
  w.kill({ ole }, 1144, "Edwin VanCleef")
  w.go({ ole }, TOWN)
  w.settle(ole.H.RUN_GRACE + 300)
  check(Sent(w, "o") == 0 and Count(ole.H:Log(), OfKind("group")) == 0, "a solo run is no line and no message")
  local old = { k = "run", t = NOW - 60, who = "Ole Fichtental", id = "Ole Fichtental#" .. (NOW - 60) .. "#9", inst = "Uldaman",
    boss = "Archaedas", n = 7, nf = 7, first = true, lvl = 44 }
  lyra.H:Add(old, "wire")
  check(Count(Lines(lyra), OfKind("run")) == 1 and lyra.H:Format(old):find("Uldaman", 1, true),
    "an old peer's dungeon run still has its line")
end

section("Raid clear: when the last boss falls, one line for the raid, without a boss count, sent once")
do
  local w = World()
  local rika, lyra, ole = w.join("Rika Steinbeck"), w.join("Lyra Distelbach"), w.join("Ole Fichtental")
  local raid = { rika, lyra }
  for i = 1, 8 do
    local name = "Gast Nummer" .. string.char(64 + i)
    w.bus:member(name, "WARRIOR", 60)
    raid[#raid + 1] = name
  end
  w.start()
  w.group(raid, true)
  w.go(raid, MC)
  w.kill(raid, 671, "Majordomo Executus")
  w.settle(900)
  w.kill(raid, 672, "Ragnaros")
  w.go(raid, TOWN)
  w.settle(600)
  check(Sent(w, "c") == 1 and Sent(w, "b") == 2, "one clear message for the raid, next to the two kill records")
  local lines = {}
  for _, c in ipairs({ rika, lyra, ole }) do lines[#lines + 1] = Count(Lines(c), OfKind("clear")) end
  check(table.concat(lines, ",") == "1,1,1", "each chronicle has one clear line (" .. table.concat(lines, ",") .. ")")
  local e
  for _, x in ipairs(ole.H:Log()) do if x.k == "clear" then e = x end end
  local text = e and ole.H:Format(e) or ""
  check(text:find("Lyra Distelbach und 9 aus der Gilde  ·  |cffffd100Geschmolzener Kern|r gecleart", 1, true)
    and not text:find("Boss", 1, true), "the line: the reporter and nine from the guild, Molten Core cleared: " .. text)
  check(ole.H:NewSinceLastLook() == 1 and rika.H:NewSinceLastLook() == 0, "new to Ole, who was not there; not to Rika")
  check(Story(ole).k == "clear", "the paper leads with the clear (" .. tostring(Story(ole).head) .. ")")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Quests: an attunement step still reaches raid readiness without a line; an old guildmate's quest still reads")
do
  local w = World()
  local mira, lyra = w.join("Mira Sturmfeder"), w.join("Lyra Distelbach")
  w.start()
  mira.fire("QUEST_TURNED_IN", 7848, 1000, 500)
  mira.fire("QUEST_TURNED_IN", 7622, 100, 10)
  w.settle(300)
  local facts = lyra.H:AttunementFacts()["Mira Sturmfeder"] or {}
  check(Sent(w, "q") == 1 and facts[7848] ~= nil, "Mira's Core Fragment step reaches Lyra's raid readiness, one message")
  check(Count(Lines(lyra), OfKind("quest")) == 0 and Count(PaperEntries(lyra), OfKind("quest")) == 0
    and Count(Lines(mira), OfKind("quest")) == 0, "the step is no line in either chronicle or paper")
  local old = { k = "quest", t = NOW - 60, who = "Bodo Kesselring", id = "Bodo Kesselring#" .. (NOW - 60) .. "#4", qid = 90,
    title = "Der Segen des Windsuchers", tag = "legend", lvl = 60 }
  w.bus:member("Bodo Kesselring", "PALADIN", 60)
  lyra.H:Add(old, "wire")
  check(Count(Lines(lyra), OfKind("quest")) == 1 and lyra.H:Format(old):find("Der Segen des Windsuchers", 1, true),
    "a legendary quest from a guildmate on an older version still has its line")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

Kit.finish()
