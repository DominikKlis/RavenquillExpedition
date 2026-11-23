local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local Layout = dofile(DEV .. "layout.lua")
local SMF = dofile(DEV .. "smf.lua")
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
        cl.frameMethods.AddMessage = function(s, m, r, g, b) s._lines = s._lines or {}; s._lines[#s._lines + 1] = { m, r, g, b } end
        cl.frameMethods.Clear = function(s) s._lines = {} end
        Stubs(cl, env)
        if opts.screen then
          Layout.Install(cl)
          Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
          SMF.Install(cl)
        end
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

local function Known(w, encs)
  for _, c in ipairs(w.list) do
    c.H:Log()
    local g = c.H.db.guilds[c.H:GuildKey()]
    g.firsts = g.firsts or {}
    for _, enc in ipairs(encs) do g.firsts["e" .. enc] = NOW - 7 * 86400 end
  end
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
  Known(w, { 663, 664 })
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

section("Guild group: a run without guildmates is no line and no message")
do
  local w = World()
  local ole = w.join("Ole Fichtental")
  w.start()
  w.go({ ole }, DEADMINES)
  w.kill({ ole }, 1144, "Edwin VanCleef")
  w.go({ ole }, TOWN)
  w.settle(ole.H.RUN_GRACE + 300)
  check(Sent(w, "o") == 0 and Count(ole.H:Log(), OfKind("group")) == 0, "a solo run is no line and no message")
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
  Known(w, { 671, 672 })
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

section("Raidbereit: the last attunement step is one line for the guild, with or without a weekly goal; a tick is none")
do
  local w = World()
  local mira, lyra = w.join("Mira Sturmfeder"), w.join("Lyra Distelbach")
  w.start()
  for _, qid in ipairs({ 4322, 6403 }) do mira.fire("QUEST_TURNED_IN", qid, 100, 10) end
  w.settle(300)
  check(Count(lyra.H:Log(), OfKind("ready")) == 0, "two of three Onyxia steps: not ready yet")
  mira.fire("QUEST_TURNED_IN", 6502, 100, 10)
  mira.H:DeclareAttuned("bwl")
  w.settle(300)
  local ready = {}
  for _, e in ipairs(Lines(lyra)) do if e.k == "ready" then ready[#ready + 1] = lyra.H:Format(e) end end
  check(#ready == 1 and ready[1]:find("Mira Sturmfeder  ·  raidbereit für |cffffd100Onyxias Hort|r", 1, true),
    "the third step makes Mira raid ready for Onyxia, one line on Lyra's side: " .. tostring(ready[1]))
  check(Sent(w, "y") == 1 and Count(Lines(lyra), OfKind("attune")) == 0, "one message; the Blackwing tick has no line")
  check(lyra.RQ:Goal() == nil and Count(PaperEntries(lyra), OfKind("ready")) == 1, "no weekly goal is set, the paper still has it")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Quests: an attunement step still reaches raid readiness without a line")
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
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

local GUILD = { ["Hanne Moosgrund"] = "ROGUE", ["Rika Steinbeck"] = "WARRIOR", ["Mira Sturmfeder"] = "PRIEST",
  ["Ilsa Brunnhold"] = "SHAMAN", ["Bodo Kesselring"] = "PALADIN", ["Ole Fichtental"] = "DRUID", ["Tamo Eichengrund"] = "HUNTER",
  ["Kael Wintermoor"] = "WARLOCK" }

local function Members(w)
  local names = {}
  for name in pairs(GUILD) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do if not w.by[name] then w.bus:member(name, GUILD[name], 60) end end
end

local oldSeq = 0
local function Old(k, who, t, fields)
  oldSeq = oldSeq + 1
  local e = { k = k, t = t, who = who, lvl = 40, cls = GUILD[who], id = ("%s#%d#%d"):format(who, t, oldSeq), unseen = true }
  for key, v in pairs(fields) do e[key] = v end
  return e
end

local function Saved(c, events)
  c.env.RavenquillExpeditionHighlightsDB = { v = 3, guilds = { ["Die Gilde@Forever"] = { events = events } } }
end

local function FromOlder(c, e)
  local body = c.H.Encode(e)
  c.fire("CHAT_MSG_ADDON", "RQE1", "H;" .. body, "GUILD", e.who)
end

local function Listed(list, e)
  for _, x in ipairs(list) do if x == e then return true end end
  return false
end

local function FeedTexts(c)
  local out = {}
  for _, row in ipairs((c.H:OverviewFeed(100) or {}).rows or {}) do out[#out + 1] = row.text end
  return out
end

local function ChronicleTexts(c)
  c.RQ:ShowModulePage("Highlights")
  local out = {}
  for _, line in ipairs(c.env.RavenquillExpeditionOverview.optView.pages.Highlights.msg._lines or {}) do out[#out + 1] = line[1] end
  return out
end

local function Holds(texts, needle)
  for _, text in ipairs(texts) do if text:find(needle, 1, true) then return true end end
  return false
end

local OLD_RULES = {
  { "a gear upgrade", "gear", "Hanne Moosgrund", { item = 5004, q = 3, il = 55, oil = 44, slot = 17 } },
  { "an epic put on", "gear", "Rika Steinbeck", { item = 5006, q = 4, il = 50, oil = 45, slot = 16 } },
  { "a quest milestone", "quest", "Mira Sturmfeder", { qid = 90, title = "Der Segen des Windsuchers", tag = "legend" } },
  { "a profession at 150", "skill", "Ilsa Brunnhold", { skill = "Leatherworking", rank = 150 } },
  { "a profession at 225", "skill", "Ilsa Brunnhold", { skill = "Leatherworking", rank = 225 } },
  { "reputation at Revered", "rep", "Mira Sturmfeder", { st = 7, fac = "Argentumdämmerung" } },
  { "a battleground win", "pvp", "Bodo Kesselring", { pk = "win", name = "Warsong Gulch" } },
  { "an epic by mail, trade or auction", "loot", "Rika Steinbeck", { item = 5002, q = 4, src = "bag" } },
  { "a dungeon boss kill", "boss", "Ole Fichtental", { enc = 4, boss = "Hochinquisitor Weißsträhne", inst = "Scharlachrotes Kloster" } },
  { "a dungeon boss's first kill from before 0.10.0", "boss", "Hanne Moosgrund",
    { enc = 596, boss = "Theka der Märtyrer", inst = "Zul'Farrak", first = true } },
  { "a dungeon boss's first kill in English from before 0.10.0", "boss", "Tamo Eichengrund",
    { enc = 427, boss = "Tinkerer Gizlock", inst = "Maraudon", first = true } },
}

local NEW_RULES = {
  { "an epic quest reward", "loot", "Rika Steinbeck", { item = 5003, q = 4, src = "quest" } },
  { "a looted epic", "loot", "Bodo Kesselring", { item = 5001, q = 4 } },
  { "a crafted epic", "loot", "Ilsa Brunnhold", { item = 5005, q = 4, src = "craft" } },
  { "a profession at 300", "skill", "Ilsa Brunnhold", { skill = "Leatherworking", rank = 300 } },
  { "reputation at Exalted", "rep", "Mira Sturmfeder", { st = 8, fac = "Argentumdämmerung" } },
  { "a PvP rank", "pvp", "Bodo Kesselring", { pk = "rank", pr = 3, name = "Unteroffizier" } },
  { "a level step", "level", "Ole Fichtental", { lvl = 40 } },
  { "a world boss's first kill", "boss", "Kael Wintermoor", { enc = 1100, boss = "Azuregos", inst = "Azshara", first = true } },
  { "a world boss's first kill by its encounter", "boss", "Bodo Kesselring",
    { enc = 3026, boss = "Lord Kazzak", inst = "Verwüstete Lande", first = true } },
}

local function Entries(cases, at)
  local out = {}
  for i, case in ipairs(cases) do
    case.entry = Old(case[2], case[3], at + i * 180, case[4])
    out[#out + 1] = case.entry
  end
  return out
end

section("Old entries: a saved entry the new rules no longer log has no line anywhere and is not counted; the log keeps it")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  Members(w)
  local saved = Entries(OLD_RULES, At(20, 8))
  for _, e in ipairs(Entries(NEW_RULES, At(20, 12))) do saved[#saved + 1] = e end
  Saved(lyra, saved)
  w.start()
  local lines, paper, feed = Lines(lyra), PaperEntries(lyra), FeedTexts(lyra)
  for _, case in ipairs(OLD_RULES) do
    local text = lyra.H:Format(case.entry)
    check(not Listed(lines, case.entry) and not Listed(paper, case.entry) and not Holds(feed, text),
      "saved " .. case[1] .. ": no line in the Chronik, no story in the Rabenblatt, no row in the home feed")
  end
  for _, case in ipairs(NEW_RULES) do
    check(Listed(lines, case.entry) and Listed(paper, case.entry) and Holds(feed, lyra.H:Format(case.entry)),
      "saved " .. case[1] .. ": still in the Chronik, the Rabenblatt and the home feed")
  end
  check(lyra.H:NewSinceLastLook() == #NEW_RULES and lyra.H:OverviewStatus():find(("^%d neu · %d Einträge · "):format(#NEW_RULES, #NEW_RULES)),
    "the counts only count the " .. #NEW_RULES .. " lines: " .. lyra.H:OverviewStatus())
  local texts = ChronicleTexts(lyra)
  local marker
  for i, text in ipairs(texts) do if text == "– neu seit deinem letzten Blick –" then marker = i end end
  check(marker and texts[marker + 1]:find(lyra.H:Format(NEW_RULES[1].entry), 1, true),
    "the Chronik's 'new' mark sits above the first line it shows (" .. tostring(marker and texts[marker + 1]) .. ")")
  local _, idx = lyra.H:Log()
  local kept = 0
  for _, e in ipairs(saved) do if idx[e.id] == e then kept = kept + 1 end end
  check(#lyra.H:Log() == #saved and kept == #saved and lyra.H:NewSinceLastLook() == 0,
    "the saved log still holds all " .. #saved .. " entries after the Chronik was read (" .. kept .. ")")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Old entries: a guildmate on 0.10.0 sends what the new rules no longer log: no chat line, nothing new, kept in the log")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  Members(w)
  w.start()
  lyra.H:Settings().chat, lyra.H:Settings().chatAll = true, true
  local at = lyra.env.time() - 7200
  local heard = Entries(OLD_RULES, at)
  for _, case in ipairs(OLD_RULES) do
    local printed, logged = #lyra.printed, #lyra.H:Log()
    FromOlder(lyra, case.entry)
    w.settle(5)
    check(#lyra.H:Log() == logged + 1 and #lyra.printed == printed and lyra.H:NewSinceLastLook() == 0 and #Lines(lyra) == 0,
      case[1] .. " from an older version: logged, but no chat line, no line and nothing new")
  end
  for _, e in ipairs(Entries(NEW_RULES, at + 3600)) do FromOlder(lyra, e); heard[#heard + 1] = e end
  w.settle(5)
  check(#lyra.H:Log() == #heard and lyra.H:NewSinceLastLook() == #NEW_RULES and #Lines(lyra) == #NEW_RULES,
    "what the new rules keep still arrives as a line and counts as new (" .. lyra.H:NewSinceLastLook() .. ")")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

local function GroupLines(c)
  local out = {}
  for _, e in ipairs(Lines(c)) do if e.k == "group" then out[#out + 1] = c.H:Format(e) end end
  return out
end

section("Old dungeon runs: three guildmates' saved run entries from one dungeon are one Gildengruppe line; a lone run is none")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  Members(w)
  local function Run(who, t, inst, n) return Old("run", who, t, { inst = inst, boss = "Edwin VanCleef", n = n, nf = n, first = true }) end
  local saved = {
    Run("Mira Sturmfeder", At(20, 10, 5), "Die Todesminen", 5),
    Run("Bodo Kesselring", At(20, 15, 10), "Uldaman", 7),
    Run("Ole Fichtental", At(20, 18, 40), "Die Todesminen", 5),
    Run("Hanne Moosgrund", At(20, 18, 43), "Die Todesminen", 5),
    Run("Tamo Eichengrund", At(20, 18, 51), "Die Todesminen", 4),
    Run("Kael Wintermoor", At(20, 19, 5), "Die Todesminen", 3),
  }
  Saved(lyra, saved)
  w.start()
  local groups = GroupLines(lyra)
  check(#groups == 1 and Count(Lines(lyra), OfKind("run")) == 0, "one guild group line and no run line in the Chronik ("
    .. #groups .. " group, " .. Count(Lines(lyra), OfKind("run")) .. " run)")
  check(groups[1] and groups[1]:find("Ole Fichtental, Hanne Moosgrund und Tamo Eichengrund  ·  |cffffd100Die Todesminen|r geschafft", 1, true)
    and not groups[1]:find("Boss", 1, true), "the three who finished within twenty minutes, by the new group line, without a boss count: "
    .. tostring(groups[1]))
  check(not Holds(groups, "Uldaman") and not Holds(groups, "Mira Sturmfeder") and not Holds(groups, "Kael Wintermoor"),
    "Bodo's lone Uldaman, Mira's run that morning and Kael's 25 minutes later are no line")
  check(Count(PaperEntries(lyra), OfKind("group")) == 1 and Count(PaperEntries(lyra), OfKind("run")) == 0 and Story(lyra).k == "group",
    "the Rabenblatt tells it as one guild group story (" .. tostring(Story(lyra).head) .. ")")
  local feed = FeedTexts(lyra)
  check(#feed == 1 and feed[1] == lyra.H:Format(Lines(lyra)[1]), "the home feed has the one line")
  check(lyra.H:NewSinceLastLook() == 1 and lyra.H:OverviewStatus():find("^1 neu · 1 Einträge · "),
    "it counts as one new entry: " .. lyra.H:OverviewStatus())
  check(#lyra.H:Log() == #saved, "the saved log still holds the six run entries")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Old dungeon runs: live from 0.10.0 they fold into one line without chat; next to a new member's group line they add nothing")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  Members(w)
  w.start()
  lyra.H:Settings().chat = true
  local at, printed = lyra.env.time() - 3600, #lyra.printed
  local function Run(who, t, inst) return Old("run", who, t, { inst = inst, boss = "Mekgineer Thermaplugg", n = 5, nf = 5 }) end
  for i, who in ipairs({ "Ole Fichtental", "Hanne Moosgrund", "Tamo Eichengrund" }) do
    FromOlder(lyra, Run(who, at + i * 120, "Gnomeregan"))
  end
  w.settle(5)
  local groups = GroupLines(lyra)
  check(#groups == 1 and groups[1]:find("Ole Fichtental, Hanne Moosgrund und Tamo Eichengrund  ·  |cffffd100Gnomeregan|r geschafft", 1, true),
    "three run messages from older versions read as one guild group line: " .. tostring(groups[1]))
  check(#lyra.printed == printed and lyra.H:NewSinceLastLook() == 1, "no per-person chat line, and one new entry")
  local t = lyra.env.time() - 1200
  lyra.H:Add({ k = "group", t = t, who = "Rika Steinbeck", cls = "WARRIOR", lvl = 45, id = ("Rika Steinbeck#%d#7"):format(t),
    inst = "Uldaman", with = { "Bodo Kesselring", "Mira Sturmfeder" }, grp = true }, "wire")
  for i, who in ipairs({ "Bodo Kesselring", "Mira Sturmfeder" }) do
    FromOlder(lyra, Run(who, t + 600 + i * 60, "Uldaman"))
  end
  w.settle(5)
  groups = GroupLines(lyra)
  check(#groups == 2 and Holds(groups, "Rika Steinbeck, Bodo Kesselring und Mira Sturmfeder  ·  |cffffd100Uldaman|r"),
    "Rika's group line already names Bodo and Mira: their old run messages add no second Uldaman line (" .. #groups .. " lines)")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

local function ChronicleRow(c, needle)
  c.RQ:ShowModulePage("Highlights")
  local page = c.env.RavenquillExpeditionOverview.optView.pages.Highlights
  for _, line in ipairs(page.msg._lines or {}) do
    if line[1]:find(needle, 1, true) then return line end
  end
end

local function SetLevel(w, name, level)
  for _, r in ipairs(w.bus.roster) do if r.name == name then r.level = level end end
  for _, c in ipairs(w.list) do c.fire("GUILD_ROSTER_UPDATE") end
end

section("Erster in der Gilde: the first character at max level is a gold line and leads the paper; the next one is a level line")
do
  local w = World()
  local alex, lyra = w.join("Alex Morgenrot", { level = 59 }), w.join("Lyra Distelbach", { level = 40 })
  local tamo = w.join("Tamo Eichengrund", { level = 59 })
  w.start()
  alex.fire("PLAYER_LEVEL_UP", 60)
  w.settle(120)
  local first = lyra.H:Log()[#lyra.H:Log()]
  check(Sent(w, "t") == 1 and Sent(w, "v") == 0 and first and first.k == "first" and first.what == "level" and first.lvl == 60,
    "Alex is the first at 60: one 'first in the guild' message instead of the level line")
  local row = ChronicleRow(lyra, "Erster in der Gilde")
  check(row and row[1]:find("Alex Morgenrot  ·  |cffffd100Erster in der Gilde|r auf Stufe 60!", 1, true)
    and row[1]:find("^|cffffd100%d%d:%d%d|r  |cffffd100»»|r ") and row[2] == 1 and row[3] == 0.9 and row[4] == 0.55,
    "Lyra's chronicle draws it as a gold row: gold time, gold mark, gold line (" .. tostring(row and row[1]) .. ")")
  check(lyra.H.KINDS[first.k].gold and Story(lyra).k == "first", "the kind is gold and the paper leads with it: " .. tostring(Story(lyra).head))
  SetLevel(w, "Alex Morgenrot", 60)
  tamo.fire("PLAYER_LEVEL_UP", 60)
  w.settle(120)
  check(Sent(w, "t") == 1 and Sent(w, "v") == 1 and lyra.H:Log()[#lyra.H:Log()].k == "level",
    "Tamo reaches 60 second: an ordinary level line")
  w.settle(lyra.H.BOSS_SAME)
  local at = lyra.env.time()
  local late = { k = "first", what = "level", t = at, who = "Bodo Kesselring", lvl = 60, id = "Bodo Kesselring#" .. at .. "#3" }
  w.bus:member("Bodo Kesselring", "PALADIN", 60)
  lyra.H:Add(late, "wire")
  check(Count(lyra.H:Log(), OfKind("first")) == 1, "a later claim to be first at 60 is not stored")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

local function Under(root, r)
  while r do
    if r == root then return true end
    r = r._parent
  end
  return false
end

local function GoldBoxes(c, root)
  local out = {}
  for _, r in ipairs(c.regions) do
    local color = r._type == "Texture" and r._shown and Under(root, r) and r._color
    local rect = color and color[1] == 1 and color[2] == 0.82 and color[3] == 0 and Layout.Rect(r)
    if rect and rect.width > 2 and rect.height > 2 then out[#out + 1] = rect end
  end
  return out
end

local function Around(box, line)
  return box.left <= line.left and box.right >= line.right and box.top >= line.top and box.bottom <= line.bottom
    and box.top - line.top <= 2 and line.bottom - box.bottom <= 2
end

local function Boxed(c, page)
  local msg = page.msg
  SMF.Tick(msg)
  local boxes, rows = GoldBoxes(c, page), {}
  for i, line in ipairs(msg.visibleLines) do
    local rect = line._shown and line._text and Layout.Rect(line)
    for _, box in ipairs(rect and boxes or {}) do
      if Around(box, rect) then rows[#rows + 1] = (line._text:find("Erster in der Gilde", 1, true) and "gold" or "plain") .. "@" .. i end
    end
  end
  return table.concat(rows, ","), #boxes
end

local function GoldLineAt(page)
  for i, line in ipairs(page.msg.visibleLines) do
    if line._shown and line._text and line._text:find("Erster in der Gilde", 1, true) then return i end
  end
  return nil
end

section("Erster in der Gilde: the chronicle draws a gold box behind the row, which follows it while scrolling, resizing and filtering")
do
  local w = World()
  local alex, lyra = w.join("Alex Morgenrot", { level = 59 }), w.join("Lyra Distelbach", { level = 40, screen = true })
  w.bus:member("Bodo Kesselring", "PALADIN", 40)
  w.start()
  alex.fire("PLAYER_LEVEL_UP", 60)
  w.settle(120)
  for i = 1, 6 do
    local t = lyra.env.time() - 60 + i
    lyra.H:Add({ k = "level", t = t, who = "Bodo Kesselring", lvl = 40 + i, id = ("Bodo Kesselring#%d#%d"):format(t, i) }, "wire")
  end
  lyra.H:Activity({ k = "duel", foe = "Bodo Kesselring" })
  lyra.H:Activity({ k = "duel", foe = "Bodo Kesselring" })
  lyra.RQ:ShowModulePage("Highlights")
  local page = lyra.env.RavenquillExpeditionOverview.optView.pages.Highlights
  local msg = page.msg
  Layout.Pin(page, 0, 0, 632, 400)
  local rows, n = Boxed(lyra, page)
  check(GoldLineAt(page) == 9 and rows == "gold@9" and n == 1, "the first in the guild has a gold box around its line, the eight newer lines none ("
    .. rows .. ", " .. n .. " boxes, gold line " .. tostring(GoldLineAt(page)) .. ")")
  local wheel = msg:GetScript("OnMouseWheel")
  lyra.env.IsShiftKeyDown = function() return false end
  wheel(msg, 1)
  rows, n = Boxed(lyra, page)
  check(GoldLineAt(page) == 6 and rows == "gold@6" and n == 1, "the wheel scrolls up three lines: the box moves down with its line ("
    .. rows .. ", gold line " .. tostring(GoldLineAt(page)) .. ")")
  wheel(msg, 1); wheel(msg, 1)
  rows, n = Boxed(lyra, page)
  check(GoldLineAt(page) == nil and rows == "" and n == 0, "scrolled past it, the line is off the screen and so is its box (" .. n .. " boxes)")
  lyra.env.IsShiftKeyDown = function() return true end
  wheel(msg, -1)
  lyra.env.IsShiftKeyDown = function() return false end
  rows, n = Boxed(lyra, page)
  check(rows == "gold@9" and n == 1, "shift and the wheel jump back to the bottom: the box is back on its line (" .. rows .. ")")
  local t = lyra.env.time()
  lyra.H:Add({ k = "level", t = t, who = "Bodo Kesselring", lvl = 50, id = ("Bodo Kesselring#%d#9"):format(t) }, "wire")
  w.settle(1)
  rows, n = Boxed(lyra, page)
  check(rows == "gold@10" and n == 1, "a new entry pushes the line up one: the box goes with it (" .. rows .. ")")
  local before = #msg.visibleLines
  Layout.Pin(page, 0, 0, 632, 250)
  rows, n = Boxed(lyra, page)
  check(#msg.visibleLines < before and rows == "gold@10" and n == 1, "a smaller window lays out new lines: the box finds its line again ("
    .. rows .. ", " .. #msg.visibleLines .. " lines)")
  page.onlyHL:SetChecked(true)
  page.onlyHL:GetScript("OnClick")(page.onlyHL)
  rows, n = Boxed(lyra, page)
  check(rows == "gold@8" and n == 1, "'Nur Highlights' drops the two duels below it: the box moves down with its line (" .. rows .. ")")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Erster in der Gilde: a raid's first kill of a boss is one gold line; a late claim for a known boss is refused")
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
  w.kill(raid, 663, "Lucifron")
  w.go(raid, TOWN)
  w.settle(600)
  check(Sent(w, "t") == 1 and Sent(w, "b") == 1, "one first message for the raid next to the kill record")
  local firsts = {}
  for _, c in ipairs({ rika, lyra, ole }) do firsts[#firsts + 1] = Count(Lines(c), OfKind("first")) end
  check(table.concat(firsts, ",") == "1,1,1", "each chronicle has one first line (" .. table.concat(firsts, ",") .. ")")
  local e
  for _, x in ipairs(ole.H:Log()) do if x.k == "first" then e = x end end
  check(e and ole.H:Format(e):find("Lyra Distelbach und 9 aus der Gilde  ·  |cffffd100Erster Kill der Gilde|r: |cffffd100Lucifron|r",
    1, true), "the line: the reporter and nine from the guild, the guild's first Lucifron: " .. tostring(e and ole.H:Format(e)))
  local newcomer = w.join("Neu Ankunft")
  newcomer.login()
  w.settle(5)
  local later = { newcomer, "Gast NummerA" }
  w.group(later, true)
  w.go(later, MC)
  w.sched:advance(8 * 86400)
  newcomer.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
  w.go(later, TOWN)
  w.settle(600)
  check(Count(newcomer.H:Log(), OfKind("first")) == 1 and Count(ole.H:Log(), OfKind("first")) == 1,
    "a newcomer who never heard of the old kill claims it; Ole knows better and keeps one first line")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Home: 'Neu in der Chronik' lists what the chronicle lists, a first in the guild highlighted and leading the paper card")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach")
  w.bus:member("Rika Steinbeck", "WARRIOR", 60)
  w.start()
  local t = lyra.env.time() - 600
  local function Heard(k, seq, fields)
    local e = { k = k, t = t + seq, who = "Rika Steinbeck", lvl = 60, cls = "WARRIOR", id = ("Rika Steinbeck#%d#%d"):format(t + seq, seq) }
    for key, v in pairs(fields) do e[key] = v end
    return lyra.H:Add(e, "wire")
  end
  Heard("level", 1, { lvl = 58 })
  Heard("boss", 2, { enc = 663, boss = "Lucifron", inst = MC.name, raid = true, grp = true, n = 10 })
  Heard("first", 3, { what = "boss", enc = 663, boss = "Lucifron", inst = MC.name, grp = true, n = 10 })
  Heard("quest", 4, { qid = 7848, title = "Einstimmung auf den Kern", tag = "special" })
  local feed = lyra.H:OverviewFeed(5)
  local rows = feed and feed.rows or {}
  check(#rows == 2 and rows[1].highlight and rows[1].text:find("Erster Kill der Gilde", 1, true) and not rows[2].highlight
    and rows[2].text:find("Stufe 58", 1, true), "the feed has the first (highlighted) and the level, not the kill record or the step ("
    .. #rows .. " rows)")
  local lead = lyra.H:PaperLead()
  check(lead and lead.k == "first", "the Rabenblatt card's lead is the first in the guild: " .. tostring(lead and lead.head))
end

local LEVEL_UP, RAID_WARNING, DUEL = 888, 8959, 3175

section("Sounds: a guildmate reaching 60, the first in the guild and a duel win each play once, live over guild sync")
do
  local w = World()
  local alex, lyra = w.join("Alex Morgenrot", { level = 59 }), w.join("Lyra Distelbach", { level = 40 })
  local tamo = w.join("Tamo Eichengrund", { level = 59 })
  w.start()
  alex.fire("PLAYER_LEVEL_UP", 60)
  w.settle(60)
  check(table.concat(lyra.sounds, ",") == tostring(RAID_WARNING), "Alex first at 60: Lyra hears the raid warning ("
    .. table.concat(lyra.sounds, ",") .. ")")
  check(table.concat(alex.sounds, ",") == tostring(RAID_WARNING), "and Alex, for his own live entry, too")
  SetLevel(w, "Alex Morgenrot", 60)
  tamo.fire("PLAYER_LEVEL_UP", 60)
  w.settle(60)
  check(lyra.sounds[2] == LEVEL_UP and #lyra.sounds == 2, "Tamo reaches 60 next: the level-up sound")
  tamo.fire("PLAYER_LEVEL_UP", 70)
  tamo.H:Add(tamo.ns[HL].Own("duel", { foe = "Lyra Distelbach" }), "self")
  w.settle(60)
  check(#lyra.sounds == 3 and lyra.sounds[3] == DUEL, "a level that is not the max is silent; the duel win plays the short sound ("
    .. table.concat(lyra.sounds, ",") .. ")")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

section("Sounds: no sound on catch-up, in combat or in an instance; a burst plays once; the two boxes turn them off")
do
  local w = World()
  local lyra = w.join("Lyra Distelbach", { level = 40 })
  w.bus:member("Bodo Kesselring", "PALADIN", 60)
  w.start()
  local seq = 0
  local function Heard(k, fields, source)
    seq = seq + 1
    local t = lyra.env.time()
    local e = { k = k, t = t, who = "Bodo Kesselring", lvl = 60, id = ("Bodo Kesselring#%d#%d"):format(t, seq) }
    for key, v in pairs(fields or {}) do e[key] = v end
    return lyra.H:Add(e, source or "wire")
  end
  local function Heard60(source) return Heard("level", { lvl = 60 }, source) end
  Heard60("relay")
  check(#lyra.sounds == 0, "a level 60 caught up after login is silent")
  lyra.combat = true
  Heard60()
  lyra.combat = false
  lyra.place = MC
  Heard60()
  lyra.place = TOWN
  check(#lyra.sounds == 0, "in combat and in an instance it is silent")
  w.settle(30)
  Heard60(); w.settle(2); Heard("duel", { foe = "Lyra Distelbach" }); w.settle(2); Heard60()
  check(#lyra.sounds == 1, "three entries within seconds play one sound (" .. #lyra.sounds .. ")")
  w.settle(30)
  local levelBox, duelBox = lyra.H:Option("soundLevel"), lyra.H:Option("soundDuel")
  check(levelBox.get() and duelBox.get() and levelBox.label == "Sound, wenn jemand Stufe 60 erreicht"
    and duelBox.label == "Sound bei einem Duellsieg in der Gilde", "both boxes are ticked by default, labelled as on the settings page")
  levelBox.set(false)
  Heard60()
  check(#lyra.sounds == 1 and not levelBox.get(), "with the level box off, a level 60 is silent")
  w.settle(30)
  Heard("duel", { foe = "Lyra Distelbach" })
  check(#lyra.sounds == 2 and lyra.sounds[2] == DUEL, "the duel box is separate: a duel win still plays")
  duelBox.set(false)
  w.settle(30)
  Heard("duel", { foe = "Lyra Distelbach" })
  check(#lyra.sounds == 2, "with the duel box off, a duel win is silent")
  check(Errors(w) == 0, "no Lua errors (" .. tostring(select(2, Errors(w))) .. ")")
end

Kit.finish()
