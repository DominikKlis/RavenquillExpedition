local HERE = (arg[0]:gsub("[^/\\]*$", ""))
local function LoadKit(dir)
  for _ = 1, 4 do
    local path = dir .. "RavenquillExpedition/dev/testkit.lua"
    local f = io.open(path, "rb")
    if f then f:close(); return dofile(path) end
    dir = dir .. "../"
  end
  error("RavenquillExpedition/dev/testkit.lua not found above " .. HERE)
end
local Kit = LoadKit(HERE .. "../")
local check, section = Kit.check, Kit.section
local MODULE = HERE .. "../Example.lua"

section("The core does the plumbing")
local file = assert(io.open(MODULE, "rb"))
local src = file:read("a")
file:close()
check(not src:find("CreateFrame", 1, true) and not src:find("C_ChatInfo", 1, true) and not src:find("GetLocale", 1, true),
  "no own event frame, no direct addon messages, no own locale pick")

section("Loads, options, locale")
local function Opts(locale) return { locale = locale, files = { { MODULE, "RavenquillExpedition_Example" } } } end
local sched, bus, a, b = Kit.Two({ a = Opts("enUS"), b = Opts("deDE") })
sched:advance(5)
local ma, mb = a.module("Example"), b.module("Example")
check(ma and ma.db and ma.settings.share == true, "registered; SavedVariables with defaults")
check(#ma.options == 2 and ma:Option("share").get() == true, "two options for /rq")
check(ma.L.SHARE == "Share my level-ups" and mb.L.SHARE == "Meine Stufenaufstiege teilen", "English and German texts")

section("Sync between two clients")
a.fire("PLAYER_LEVEL_UP", 31)
sched:advance(10)
local levels = mb:GuildStore("levels")
check(levels["Anna Stone"] and levels["Anna Stone"].level == 31, "Bert stored Anna's level-up")
check(b.printedMatch("Anna Stone hat Stufe 31 erreicht") ~= nil, "and showed it in chat, in German on the German client")
check(bus:maxPer(60, "Anna Stone") <= 4, "within the suite's send budget")
for lvl = 32, 40 do a.fire("PLAYER_LEVEL_UP", lvl) end
sched:advance(600)
check(levels["Anna Stone"].level == 40 and b.printedMatch("Stufe 40 erreicht") ~= nil, "a burst of 9 level-ups: the newest arrives")
local sends = bus:sentBy("Anna Stone", function(e) return e.chat == "GUILD" end)
local gap = math.huge
for i = 2, #sends do gap = math.min(gap, sends[i].t - sends[i - 1].t) end
local per60 = bus:maxPer(60, "Anna Stone")
check(per60 <= 15 and gap >= 1, ("paced by the core: %d per 60 s (<= 15 measured-safe/2), closest two %s s apart"):format(per60, tostring(gap)))

section("Messages the module never sees")
b.fire("CHAT_MSG_ADDON", "RQE1", "EX;1;lvl;Cora Vale;60", "GUILD", "Anna Stone-Realm")
check(levels["Cora Vale"] == nil, "a message about someone else is rejected before the handler")
b.fire("CHAT_MSG_ADDON", "RQE1", "EX;1;lvl;Anna Stone;999", "GUILD", "Anna Stone-Realm")
check(levels["Anna Stone"].level == 40, "a level outside 1-200 is rejected")
b.fire("CHAT_MSG_ADDON", "RQE1", "EX;1;nope;Anna Stone", "GUILD", "Anna Stone-Realm")
check(levels["Anna Stone"].level == 40 and #b.errors == 0, "an unknown message type is ignored")

section("Options")
mb:Option("announce").set(false)
a.fire("PLAYER_LEVEL_UP", 41)
sched:advance(40)
check(levels["Anna Stone"].level == 41 and not b.printedMatch("Stufe 41"), "announce off: stored, not printed")
ma:Option("share").set(false)
local sentBefore = #bus:sentBy("Anna Stone")
a.fire("PLAYER_LEVEL_UP", 42)
sched:advance(40)
check(#bus:sentBy("Anna Stone") == sentBefore and levels["Anna Stone"].level == 41, "share off: the level-up is not sent")
ma:Option("share").set(true)
a.fire("PLAYER_LEVEL_UP", 43)
sched:advance(40)
check(levels["Anna Stone"].level == 43, "share on again: the next level-up goes out")

section("Combat, and a store that stays small")
a.combat = true
a.fire("PLAYER_LEVEL_UP", 44)
sched:advance(60)
check(levels["Anna Stone"].level == 43, "in combat nothing goes out")
a.combat = false
a.fire("PLAYER_REGEN_ENABLED")
sched:advance(30)
check(levels["Anna Stone"].level == 44, "a level-up in combat goes out when combat ends")
for lvl = 45, 60 do a.fire("PLAYER_LEVEL_UP", lvl); sched:advance(30) end
local keys = 0
for _ in pairs(levels) do keys = keys + 1 end
check(keys == 1 and levels["Anna Stone"].level == 60, "one entry per guildmate, however many level-ups (" .. keys .. ")")

section("The other way round")
b.fire("PLAYER_LEVEL_UP", 20)
sched:advance(10)
local fromBert = ma:GuildStore("levels")["Bert Hill"]
check(fromBert and fromBert.level == 20 and a.printedMatch("Bert Hill reached level 20") ~= nil,
  "Anna stored Bert's level-up and showed it in English")
check(#a.errors == 0 and #b.errors == 0, "no Lua errors")
Kit.finish()
