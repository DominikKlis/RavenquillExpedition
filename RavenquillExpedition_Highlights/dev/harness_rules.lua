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
