-- Two simulated clients run the Example module on the shared test kit: a level-up on one arrives at the other.
-- Run: lua templates/Module/dev/harness.lua   (copy this with the module; adjust the paths if you move it)
local HERE = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(HERE .. "../../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check

local function Client(sched, bus, name)
  return Kit.Client(sched, bus, name, { files = { { HERE .. "../Example.lua", "RavenquillExpedition_Example" } } })
end
local sched, bus = Kit.Setup()
local a = Client(sched, bus, "Anna Stone")
local b = Client(sched, bus, "Bert Hill")
a.login(); b.login(); sched:advance(10)

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
