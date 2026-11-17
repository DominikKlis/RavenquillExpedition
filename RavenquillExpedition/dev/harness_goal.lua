local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section
local TEMPLATE = Kit.ADDONS .. "templates/Module/"

local f = io.open(TEMPLATE .. "Example.lua", "rb")
if not f then
  Kit.skip("goal not yet reached", "templates/Module/Example.lua does not exist")
  Kit.finish()
end
local src = f:read("*a")
f:close()

section("Size")
local n = 0
for line in (src .. "\n"):gmatch("([^\n]*)\n") do
  if line:gsub("%-%-.*$", ""):match("%S") then n = n + 1 end
end
check(n <= 40, ("the example module has %d code lines (budget 40)"):format(n))
check(not src:find("CreateFrame", 1, true) and not src:find("C_ChatInfo", 1, true) and not src:find("GetLocale", 1, true),
  "no own event frame, no direct addon messages, no own locale pick")

section("Loads, options, locale")
local function Client(sched, bus, name, locale)
  return Kit.Client(sched, bus, name, { locale = locale, files = { { TEMPLATE .. "Example.lua", "RavenquillExpedition_Example" } } })
end
local sched, bus = Kit.Setup()
local a = Client(sched, bus, "Anna Stone", "enUS")
local b = Client(sched, bus, "Bert Hill", "deDE")
a.login(); b.login(); sched:advance(10)
local ma, mb = a.module("Example"), b.module("Example")
check(ma and ma.db and ma.settings.share == true, "registered; SavedVariables with defaults")
check(#ma.options == 2 and ma:Option("share").get() == true, "two options for /rq")
check(ma.L.SHARE == "Share my level-ups" and mb.L.SHARE == "Meine Stufenaufstiege teilen", "English and German texts")

section("Sync between two clients")
a.fire("PLAYER_LEVEL_UP", 31)
sched:advance(10)
local got = mb:GuildStore("levels")
check(got["Anna Stone"] and got["Anna Stone"].level == 31, "the level-up arrived")
check(b.printedMatch("Anna Stone hat Stufe 31 erreicht") ~= nil, "shown in German on the German client")
for lvl = 32, 40 do a.fire("PLAYER_LEVEL_UP", lvl) end
sched:advance(600)
check(got["Anna Stone"].level == 40 and b.printedMatch("Stufe 40 erreicht") ~= nil, "a burst of 9 level-ups: the newest arrives")
local CC = a.RQ.CommConst
local cap60 = CC.BURST + 60 * CC.RATE
local gap = math.huge
local prevT
for _, e in ipairs(bus.log) do
  if e.sender == "Anna Stone" and e.chat == "GUILD" then
    if prevT then gap = math.min(gap, e.t - prevT) end
    prevT = e.t
  end
end
check(bus:maxPer(60, "Anna Stone") <= cap60 and bus:maxPer(60, "Anna Stone") <= 15 and gap >= 1,
  ("paced by the core: %d per 60 s (<= %d and <= 15 measured-safe/2), closest two %s s apart"):format(
  bus:maxPer(60, "Anna Stone"), cap60, tostring(gap)))
b.fire("CHAT_MSG_ADDON", "RQE1", "EX;1;lvl;Cora Vale;60", "GUILD", "Anna Stone-Realm")
check(got["Cora Vale"] == nil, "a message about someone else is rejected before the handler")

section("Combat, and a store that stays small (review 2026-11-15)")
a.combat = true
a.fire("PLAYER_LEVEL_UP", 41)
sched:advance(60)
check(got["Anna Stone"].level == 40, "in combat nothing goes out")
a.combat = false
a.fire("PLAYER_REGEN_ENABLED")
sched:advance(30)
check(got["Anna Stone"].level == 41, "the level-up from combat goes out when combat ends")
for lvl = 42, 60 do a.fire("PLAYER_LEVEL_UP", lvl); sched:advance(30) end
local keys = 0
for _ in pairs(got) do keys = keys + 1 end
check(keys == 1 and got["Anna Stone"].level == 60, "one entry per guildmate, however many level-ups (" .. keys .. ")")
check(#a.errors == 0 and #b.errors == 0, "no Lua errors")
Kit.finish()
