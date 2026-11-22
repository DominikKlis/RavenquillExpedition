local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness_rally%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end
local MapKit = dofile(DIR .. "/dev/mapkit.lua")
local Kit = MapKit.Kit
local check = Kit.check
math.randomseed(7)

local function Waypoints(env, c)
  c.waypoints = {}
  env.UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }
  env.C_Map.SetUserWaypoint = function(p) c.waypoints[#c.waypoints + 1] = p end
  env.C_Map.CanSetUserWaypointOnMap = function(mapID) return mapID ~= 1411 end
  env.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) c.supertracked = on end }
end

local function Client(sched, bus, name, opts)
  opts = opts or {}
  return MapKit.Client(sched, bus, name, { pos = opts.pos, locale = opts.locale, class = opts.class, level = opts.level,
    setup = function(env, c)
      env.GetSubZoneText = function() return opts.subzone or "" end
      if opts.waypoints then Waypoints(env, c) end
      if opts.saved then env.RavenquillExpeditionMapDB = opts.saved end
    end })
end

local function Menus(env)
  local menus = {}
  env.MenuUtil = { CreateContextMenu = function(owner, build)
    local menu = { owner = owner, titles = {}, entries = {} }
    local root = {
      CreateTitle = function(_, t) menu.titles[#menu.titles + 1] = t end,
      CreateDivider = function() menu.entries[#menu.entries + 1] = { text = "---" } end,
      CreateButton = function(_, t, fn)
        local e = { text = t, fn = fn }
        e.SetEnabled = function(_, on) e.grey = not on end
        menu.entries[#menu.entries + 1] = e
        return e
      end,
    }
    build(owner, root)
    menus[#menus + 1] = menu
  end }
  return menus
end

local function Entry(menu, text)
  for _, e in ipairs(menu and menu.entries or {}) do if e.text == text then return e end end
end

local function Flag(c, key) return c.M:RallyFlags()[key] end

local function Dot(c, key)
  local flag = Flag(c, key)
  for f in pairs(c.hbdWorld) do
    if f.key == key and not (flag and flag.world == f) then return f end
  end
end

local function Notice(c)
  local f = c.M.rallyNotice
  if not (f and f:IsShown()) then return "none" end
  local action = f.action:GetText() .. (f.action:IsEnabled() and "" or " (grey)")
  return table.concat({ f.title:GetText(), f.who:GetText(), f.details:GetText(), action,
    f.waypoint:IsShown() and f.waypoint:GetText() or "-" }, " | ")
end

local function Click(c, button) local b = c.M.rallyNotice[button]; b._scripts.OnClick(b) end

local function RallySends(bus, kind, sender)
  return bus:count(function(e)
    return e.prefix == "RQEMap1" and e.msg:sub(1, 2) == kind .. ";" and (not sender or e.sender == sender)
  end)
end

local function Near(a, b) return math.abs(a - b) <= 2 / 46655 end

local function FlagAt(c, key, mapID, x, y)
  local fl = Flag(c, key)
  local world, mini = fl and c.hbdWorld[fl.world], fl and c.hbdMini[fl.mini]
  return world ~= nil and mini ~= nil and world.mapID == mapID and Near(world.x, x) and Near(world.y, y)
    and mini.mapID == mapID and Near(mini.x, x) and Near(mini.y, y) and mini.edge == true
end

local function NoErrors(clients, what)
  local all = {}
  for _, c in ipairs(clients) do
    for _, e in ipairs(c.errors) do all[#all + 1] = c.name .. ": " .. tostring(e) end
  end
  check(#all == 0, what .. ": no Lua errors (" .. tostring(all[1]) .. ")")
end

local function Guild(opts)
  local sched, bus = Kit.Setup()
  local A = Client(sched, bus, "Anna Alpha", { pos = { 1429, 0.40, 0.40 }, subzone = "Schwarzfelsspitze", class = "MAGE",
    waypoints = opts and opts.waypoints })
  local B = Client(sched, bus, "Bert Beta", { pos = { 1429, 0.60, 0.60 }, locale = "deDE", waypoints = opts and opts.waypoints })
  local Cc = Client(sched, bus, "Cora Vale", { pos = { 1429, 0.70, 0.30 } })
  A.login(); B.login(); Cc.login()
  sched:advance(120)
  return sched, bus, A, B, Cc
end

Kit.section("A rally reaches every client: notice and flag")
do
  local sched, bus, A, B, Cc = Guild()
  local menus = Menus(A.env)
  local bertDot = Dot(A, "Bert Beta")
  bertDot._scripts.OnClick(bertDot, "RightButton")
  local set = Entry(menus[1], "Set rally point here")
  check(set ~= nil and menus[1].entries[#menus[1].entries - 1].text == "---",
    "A's menu on Bert's dot ends with a divider and 'Set rally point here'")
  set.fn()
  sched:advance(10)
  check(RallySends(bus, "R", "Anna Alpha") == 1, "one rally call on the wire: " .. RallySends(bus, "R"))
  check(Notice(B) == "Sammelruf | Anna Alpha: Schwarzfelsspitze | Map1429 · 0 unterwegs · noch 15 min | Ich komme | -",
    "Bert (German) gets the notice: " .. Notice(B))
  check(Notice(Cc) == "Rally call | Anna Alpha: Schwarzfelsspitze | Map1429 · 0 on the way · 15 min left | I'm coming | -",
    "Cora (English) gets the notice: " .. Notice(Cc))
  check(Notice(A) == "Rally call | Anna Alpha: Schwarzfelsspitze | Map1429 · 0 on the way · 15 min left | Cancel | -",
    "Anna sees her own call with Cancel instead of I'm coming: " .. Notice(A))
  check(FlagAt(B, "Anna Alpha", 1429, 0.40, 0.40) and FlagAt(Cc, "Anna Alpha", 1429, 0.40, 0.40)
    and FlagAt(A, "Anna Alpha", 1429, 0.40, 0.40),
    "a flag at Anna's spot on everyone's world map and minimap; on the minimap it stays on the edge when out of range")
  local tipFlag = Flag(Cc, "Anna Alpha").world
  tipFlag._scripts.OnEnter(tipFlag)
  check(table.concat(Cc.tip.lines, "|") == "Rally point|Anna Alpha: Schwarzfelsspitze|Map1429 · 0 on the way · 15 min left|Click: show the call",
    "the flag's tooltip names the call: " .. table.concat(Cc.tip.lines, "|"))

  Kit.section("I'm coming counts everywhere")
  Click(B, "action")
  sched:advance(10)
  check(Notice(B) == "Sammelruf | Anna Alpha: Schwarzfelsspitze | Map1429 · 1 unterwegs · noch 15 min | Unterwegs (grey) | -",
    "Bert answered: his button turns into 'Unterwegs' and his count is 1: " .. Notice(B))
  check(Notice(A):find("· 1 on the way ·", 1, true) and Notice(Cc):find("· 1 on the way ·", 1, true),
    "Anna and Cora count Bert too: " .. Notice(A) .. " / " .. Notice(Cc))
  Click(Cc, "action")
  for _ = 1, 4 do Click(B, "action"); Click(Cc, "action") end
  sched:advance(10)
  local counts = {}
  for _, c in ipairs({ A, B, Cc }) do counts[#counts + 1] = c.M.RallyCount(c.M.rallies["Anna Alpha"]) end
  check(table.concat(counts, ",") == "2,2,2", "Cora answered too: 2 on the way for all three (" .. table.concat(counts, ",") .. ")")
  check(RallySends(bus, "J") == 2, "answering again sends nothing: one message per guildmate who comes (" .. RallySends(bus, "J") .. ")")

  Kit.section("A guildmate who logs in later learns the active rally")
  sched:advance(180)
  Click(B, "close")
  local D = Client(sched, bus, "Dora Late", { pos = { 1429, 0.20, 0.80 } })
  D.login()
  check(Notice(D) == "none", "right after login Dora knows nothing yet")
  sched:advance(120)
  check(Notice(D) == "Rally call | Anna Alpha: Schwarzfelsspitze | Map1429 · 2 on the way · 10 min left | I'm coming | -",
    "Anna re-sent her call after Dora's first position: Dora sees it with the current count and time: " .. Notice(D))
  check(FlagAt(D, "Anna Alpha", 1429, 0.40, 0.40), "Dora has the flag")
  check(RallySends(bus, "R", "Anna Alpha") == 2, "the late login cost one more call message (" .. RallySends(bus, "R") .. ")")
  counts = {}
  for _, c in ipairs({ A, B, Cc, D }) do counts[#counts + 1] = c.M.RallyCount(c.M.rallies["Anna Alpha"]) end
  check(table.concat(counts, ",") == "2,2,2,2", "the re-send keeps everyone at 2, nobody counts twice (" .. table.concat(counts, ",") .. ")")
  sched:advance(300)
  check(RallySends(bus, "R", "Anna Alpha") == 2, "no further re-sends while nobody new appears")
  check(Notice(B) == "none", "Bert had closed the notice: Anna's re-send doesn't open it again")
  local flagBert = Flag(B, "Anna Alpha").world
  flagBert._scripts.OnClick(flagBert, "LeftButton")
  check(Notice(B) == "Sammelruf | Anna Alpha: Schwarzfelsspitze | Map1429 · 2 unterwegs · noch 5 min | Unterwegs (grey) | -",
    "reopened from the flag, Bert's answer survived the re-send: " .. Notice(B))

  Kit.section("Cancel reaches everyone; a lost cancel ends by time")
  bus.drop = function(_, prefix, msg, c) return c == Cc and prefix == "RQEMap1" and msg:sub(1, 2) == "X;" end
  local menusA = #menus
  bertDot._scripts.OnClick(bertDot, "RightButton")
  local cancel = Entry(menus[menusA + 1], "Cancel rally point")
  check(cancel ~= nil, "while her call is active, Anna's menu offers 'Cancel rally point'")
  cancel.fn()
  sched:advance(10)
  check(Notice(A) == "none" and Notice(B) == "none" and Notice(D) == "none" and not Flag(A, "Anna Alpha")
    and not Flag(B, "Anna Alpha") and not Flag(D, "Anna Alpha"), "cancelled: notice and flag gone for Anna, Bert and Dora")
  check(Notice(Cc) ~= "none" and Flag(Cc, "Anna Alpha") ~= nil, "Cora lost the cancel message and still shows the call")
  local expires = Cc.M.rallies["Anna Alpha"].expires
  sched:advance(expires - Cc.RQ:Now() - 4)
  check(Notice(Cc):find("· 1 min left", 1, true), "Cora's call counts down to its last minute: " .. Notice(Cc))
  sched:advance(8)
  check(Notice(Cc) == "none" and not Flag(Cc, "Anna Alpha") and Cc.M.rallies["Anna Alpha"] == nil,
    "15 minutes after the call it ends for Cora too, without any message")
  check(RallySends(bus, "X") == 1 and RallySends(bus, "R") == 2 and RallySends(bus, "J") == 2,
    ("the whole rally cost 5 messages: 2 calls (one for the late login), 2 answers, 1 cancel (R %d, J %d, X %d)"):format(
      RallySends(bus, "R"), RallySends(bus, "J"), RallySends(bus, "X")))
  NoErrors({ A, B, Cc, D }, "rally lifecycle")
end

Kit.section("Expiry without cancel; spamming the button")
do
  local sched, bus, A, B, Cc = Guild()
  bus.drop = function() return false end
  local t0 = A.RQ:Now()
  for _ = 1, 10 do A.M:CallRally(); sched:advance(2) end
  sched:advance(5)
  check(RallySends(bus, "R") == 1 and A.printedMatch("You can set a new rally point in"),
    "ten clicks in 20 s send one call and tell Anna when she can call again (" .. RallySends(bus, "R") .. ")")
  local first = B.M.rallies["Anna Alpha"]
  Click(B, "close")
  check(Notice(B) == "none" and Flag(B, "Anna Alpha") ~= nil, "Bert closes the notice; the flag stays")
  local flagB = Flag(B, "Anna Alpha").world
  flagB._scripts.OnClick(flagB, "LeftButton")
  check(Notice(B):find("Anna Alpha", 1, true), "clicking the flag shows the call again: " .. Notice(B))
  Click(B, "close")
  sched:advance(t0 + 31 - A.RQ:Now())
  A.pos = { 1429, 0.45, 0.42 }
  A.M:CallRally()
  sched:advance(10)
  local second = B.M.rallies["Anna Alpha"]
  check(RallySends(bus, "R") == 2 and second and second ~= first and second.id > first.id and Near(second.x, 0.45),
    "after 30 s Anna may call again: the new call replaces the old one (one per caller)")
  check(Notice(B):find("0 unterwegs", 1, true) and FlagAt(B, "Anna Alpha", 1429, 0.45, 0.42),
    "Bert closed the old notice, but the new call shows again, with its flag at the new spot: " .. Notice(B))
  local untilEnd = second.expires - B.RQ:Now()
  sched:advance(untilEnd - 3)
  check(Notice(B) ~= "none" and Flag(Cc, "Anna Alpha") ~= nil, "shortly before 15 minutes the call is still there")
  sched:advance(6)
  check(Notice(A) == "none" and Notice(B) == "none" and Notice(Cc) == "none" and not Flag(A, "Anna Alpha")
    and not Flag(B, "Anna Alpha") and not Flag(Cc, "Anna Alpha"), "after 15 minutes the call ends everywhere")
  check(A.M:Interval(true) >= A.M.C.INTERVAL_MIN and RallySends(bus, "X") == 0, "expiry needs no message")
  NoErrors({ A, B, Cc }, "expiry and spam")

end

Kit.section("Waypoint, one notice at a time")
do
  local sched, _, A, B, Cc = Guild({ waypoints = true })
  A.M:CallRally()
  sched:advance(10)
  check(Notice(B) == "Sammelruf | Anna Alpha: Schwarzfelsspitze | Map1429 · 0 unterwegs · noch 15 min | Ich komme | Wegpunkt",
    "with the game's waypoint API the notice offers 'Wegpunkt': " .. Notice(B))
  Click(B, "waypoint")
  local wp = B.waypoints[1]
  check(wp and wp.mapID == 1429 and Near(wp.x, 0.40) and Near(wp.y, 0.40) and B.supertracked == true,
    "Wegpunkt sets the game's own waypoint at the rally point and tracks it")
  Cc.M:CallRally()
  sched:advance(10)
  check(Notice(B):find("Cora Vale: Map1429", 1, true), "a second call: Bert's notice shows the newer one: " .. Notice(B))
  check(Flag(B, "Anna Alpha") ~= nil and Flag(B, "Cora Vale") ~= nil, "both flags are on Bert's map")
  Click(B, "close")
  check(Notice(B):find("Anna Alpha: Schwarzfelsspitze", 1, true), "closing it shows the older call next: " .. Notice(B))
  Click(B, "close")
  check(Notice(B) == "none", "closing that leaves no notice")
  B.pos = { 1411, 0.5, 0.5 }
  B.M:CallRally()
  sched:advance(10)
  check(Notice(A) == "Rally call | Bert Beta: Map1411 | 0 on the way · 15 min left | I'm coming | -",
    "no waypoint button where the game can't hold one (map 1411): " .. Notice(A))
  NoErrors({ A, B, Cc }, "waypoint")

end

Kit.section("Ignoring rally calls")
do
  local sched, _, A, B, Cc = Guild()
  local option = B.M:Option("ignoreRally")
  check(option and option.label == "Sammelrufe ignorieren" and option.tooltip and option.tooltip ~= "",
    "/rq map has the option 'Sammelrufe ignorieren' with a tooltip")
  B.set("ignoreRally", true)
  A.M:CallRally()
  sched:advance(10)
  check(Notice(B) == "none" and Flag(B, "Anna Alpha") == nil, "Bert ignores calls: no notice, no flag")
  check(Notice(Cc) ~= "none", "Cora still gets it")
  sched:advance(30)
  B.M:CallRally()
  sched:advance(10)
  check(Notice(B):find("Bert Beta:", 1, true) and Flag(B, "Bert Beta") ~= nil, "Bert's own call still shows while he ignores others")
  B.M:CancelRally()
  B.set("ignoreRally", false)
  check(Notice(B):find("Anna Alpha", 1, true) and Flag(B, "Anna Alpha") ~= nil,
    "turning the option off shows Anna's call that is still running: " .. Notice(B))
  NoErrors({ A, B, Cc }, "ignore option")

end

Kit.section("Bad rally messages")
do
  local _, _, A, B, Cc = Guild()
  local function Hear(c, sender, msg) c.fire("CHAT_MSG_ADDON", "RQEMap1", msg, "GUILD", sender .. "-Realm") end
  local now = B.RQ:Now()
  local b36 = B.RQ.Wire.b36
  local good = table.concat({ "R", b36(now), b36(1429), b36(18662), b36(18662), "0", "Hier" }, ";")
  Hear(B, "Eve Fake", (good:gsub("^R;[^;]+", "R;" .. b36(now - 900))))
  Hear(B, "Eve Fake", (good:gsub("^R;[^;]+", "R;" .. b36(now + 600))))
  Hear(B, "Eve Fake", (good:gsub("^(R;[^;]+;)[^;]+", "%1" .. b36(999999))))
  Hear(B, "Eve Fake", good .. ";extra")
  Hear(B, "Eve Fake", "J;Anna Alpha")
  Hear(B, "Eve Fake", "X")
  check(next(B.M.rallies) == nil and Notice(B) == "none", "expired, future, unknown-map and malformed messages are dropped")
  Hear(B, "Eve Fake", good)
  check(Notice(B) == "Sammelruf | Eve Fake: Hier | Map1429 · 0 unterwegs · noch 15 min | Ich komme | -", "a valid one shows: " .. Notice(B))
  Hear(B, "Mallory Spoof", "X;" .. b36(now))
  check(Notice(B) ~= "none", "only the caller can cancel a call")
  Hear(B, "Eve Fake", "J;Eve Fake;" .. b36(now - 1))
  check(B.M.RallyCount(B.M.rallies["Eve Fake"]) == 0, "an answer to an older call doesn't count")
  Hear(B, "Eve Fake", good)
  Hear(B, "Mallory Spoof", "J;Eve Fake;" .. b36(now))
  Hear(B, "Mallory Spoof", "J;Eve Fake;" .. b36(now))
  check(B.M.RallyCount(B.M.rallies["Eve Fake"]) == 1, "the same guildmate answering twice counts once")
  Hear(B, "Eve Fake", (good:gsub("^R;[^;]+", "R;" .. b36(now - 60))))
  check(B.M.rallies["Eve Fake"].id == now and B.M.RallyCount(B.M.rallies["Eve Fake"]) == 1,
    "a late older call doesn't replace the newer one")
  Hear(B, "Eve Fake", "X;" .. b36(now))
  Hear(B, "Eve Fake", good)
  check(Notice(B) == "none" and Flag(B, "Eve Fake") == nil, "a cancelled call stays cancelled when its call message comes again")
  NoErrors({ A, B, Cc }, "bad messages")

end

Kit.finish()
