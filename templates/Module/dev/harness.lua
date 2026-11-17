local HERE = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(HERE .. "../../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check

local example = { files = { { HERE .. "../Example.lua", "RavenquillExpedition_Example" } } }
local sched, bus, a, b = Kit.Two({ a = example, b = example })
sched:advance(5)

a.fire("PLAYER_LEVEL_UP", 31)
sched:advance(10)
local levels = b.module("Example"):GuildStore("levels")
check(levels["Anna Stone"] and levels["Anna Stone"].level == 31, "Bert stored Anna's level-up")
check(b.printedMatch("Anna Stone reached level 31") ~= nil, "and showed it in chat")
check(bus:maxPer(60, "Anna Stone") <= 4, "within the suite's send budget")

b.module("Example"):Option("announce").set(false)
a.fire("PLAYER_LEVEL_UP", 32)
sched:advance(40)
check(levels["Anna Stone"].level == 32 and not b.printedMatch("level 32"), "announce off: stored, not printed")
a.combat = true
a.fire("PLAYER_LEVEL_UP", 33)
sched:advance(40)
a.combat = false
a.fire("PLAYER_REGEN_ENABLED")
sched:advance(40)
check(levels["Anna Stone"].level == 33, "a level-up in combat goes out when combat ends")
check(#a.errors == 0 and #b.errors == 0, "no Lua errors")
Kit.finish()
