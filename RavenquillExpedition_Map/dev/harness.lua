local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end

local MapKit = dofile(DIR .. "/dev/mapkit.lua")
local Kit = MapKit.Kit
local check = Kit.check

local function AddWorldMap(c)
  local canvas = c.newFrame()
  canvas.w, canvas.h = 1000, 700
  local calls = {}
  local allowed = {
    GetCanvas = function() return canvas end,
    GetMapID = function(s) return s.mapID end,
    GetCanvasScale = function(s) return s.scale end,
    IsShown = function(s) return s.shown end,
  }
  local map = { canvas = canvas, mapID = 1429, scale = 1, shown = false, calls = calls, providers = {} }
  map.pinPools = setmetatable({}, { __newindex = function(t, k, v) calls[#calls + 1] = "pinPools." .. tostring(k); rawset(t, k, v) end })
  function map.blizzardShow()
    map.shown, canvas.shown = true, true
    local ran = 0
    for provider in pairs(map.providers) do provider:RefreshAllData(true); ran = ran + 1 end
    for _, f in ipairs(c.frames) do
      local p = f.parent
      while p and p ~= canvas do p = p.parent end
      if p == canvas and f._scripts.OnShow then f._scripts.OnShow(f); ran = ran + 1 end
    end
    return ran
  end
  function map.renderFrame()
    if not map.shown then return end
    for _, f in ipairs(c.frames) do
      if f.parent == canvas and f.shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 0.016) end
    end
  end
  setmetatable(map, {
    __index = function(_, k)
      if allowed[k] then return allowed[k] end
      if type(k) == "string" and k:match("^%u") then
        return function(_, a) calls[#calls + 1] = k; if k == "AddDataProvider" then map.providers[a] = true end end
      end
    end,
    __newindex = function(t, k, v) calls[#calls + 1] = "write " .. tostring(k); rawset(t, k, v) end,
  })
  c.env.WorldMapFrame = map
  return map
end

local function NewWorld(opts)
  opts = opts or {}
  local sched = Kit.Scheduler()
  local map
  local w = MapKit.Client(sched, nil, "Ängis Waldbach", { guild = false, locale = opts.locale, setup = function(_, c)
    if opts.worldMap then map = AddWorldMap(c) end
  end })
  w.fire("ADDON_LOADED", "RavenquillExpedition")
  w.map = map
  function w.advance(sec) sched:advance(sec) end
  return w
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function anyPrinted(w, needle) return w.printedMatch(needle) ~= nil end

local function pinFor(w, store, key)
  for icon in pairs(store) do if icon.key == key then return icon end end
end

local w = NewWorld()
local M = w.M
w.fire("ADDON_LOADED", "RavenquillExpedition_Map")
check(M.db and M.settings.share == true and M.settings.worldmap and M.settings.minimap, "defaults: share/worldmap/minimap on")
check(M.settings.names == false and M.settings.size == 1 and M.settings.selfPin == false, "defaults: names off, size 1, selfPin off")
w.fire("PLAYER_LOGIN")
w.advance(5)
check(not anyPrinted(w, "shares your position"), "notice not before NOTICE_DELAY")
w.advance(5)
check(anyPrinted(w, "shares your position"), "privacy notice shown after login")
check(M.db.noticeShown == true, "noticeShown saved")
check(w.RQ:PlayerKey() == "Ängis Waldbach", "core PlayerKey = First Surname")

local saved = M.db
local w1 = NewWorld()
w1.env.RavenquillExpeditionMapDB = saved
w1.fire("ADDON_LOADED", "RavenquillExpedition_Map"); w1.fire("PLAYER_LOGIN"); w1.advance(20)
check(not anyPrinted(w1, "shares your position"), "notice only once across logins")

local w2 = NewWorld()
w2.env.RavenquillExpeditionMapDB = { settings = { share = "yes", size = 9 } }
w2.fire("ADDON_LOADED", "RavenquillExpedition_Map")
check(w2.M.settings.share == true and w2.M.settings.size == 1, "bad saved values repaired")

w.set("fake", true)
check(count(M.members) == 7, "7 test pins")
check(count(w.hbdWorld) == 7, "world: all 7 placed (stale one too)")
check(count(w.hbdMini) == 6, "minimap: 6 (stale Fünf hidden), got " .. count(w.hbdMini))
local fuenf = pinFor(w, w.hbdWorld, "~fake5")
check(fuenf and fuenf.alpha == 0.45, "stale pin is dimmed")
local vier = pinFor(w, w.hbdWorld, "~fake4")
check(vier and vier.bg.color[1] == 1 and vier.bg.color[2] == 0.82, "taxi pin has a gold ring")
local drei = pinFor(w, w.hbdWorld, "~fake3")
check(drei and drei.fg.color[1] == 0.55, "ghost pin is grey")
local _, placed = next(w.hbdWorld)
check(placed and placed.mapID == 1429 and placed.x >= 0.01 and placed.x <= 0.99, "test pins placed by map ID within bounds")
local x0 = M.members["~fake1"].x
w.advance(50)
check(M.members["~fake1"].x ~= x0, "moving test pin moved")
check(w.maxCanvas() == 1, "moved world pins leave no orphan canvas pins (code review #1)")
check(not pinFor(w, w.hbdMini, "~fake6"), "non-updating pin leaves the minimap after 45 s")
check(pinFor(w, w.hbdMini, "~fake2"), "stationary pin stays on the minimap")
check(pinFor(w, w.hbdMini, "~fake1"), "updating pin stays on the minimap")
w.advance(120)
check(M.members["~fake5"] == nil and not pinFor(w, w.hbdWorld, "~fake5"), "stale pin removed at 2x fade")
w.advance(20)
check(M:State(M.members["~fake6"]) == "stale", "pin fades at 180 s")
w.advance(180)
check(M.members["~fake6"] == nil, "pin removed at 360 s")
check(M.members["~fake2"] and M:State(M.members["~fake2"]) == "fresh", "stationary still fresh at 370 s (fades at 450)")
w.advance(100)
check(M:State(M.members["~fake2"]) == "stale", "stationary fades at 1.5 x heartbeat")

w.set("minimap", false)
check(count(w.hbdMini) == 0, "minimap off removes minimap pins")
w.set("minimap", true)
check(count(w.hbdMini) > 0, "minimap on restores")
w.set("worldmap", false)
check(count(w.hbdWorld) == 0, "worldmap off removes world pins")
w.set("worldmap", true)
w.set("names", true)
local any = next(w.hbdWorld)
check(any and any.label.shown and any.label.text ~= nil, "names on shows labels")
w.set("size", 7)
check(M.settings.size == 2, "size is clamped to 0.5-2")
w.set("size", 1.5)
check(M.settings.size == 1.5 and any.w == 21, "size applied to existing pins")
w.set("fake", false)
check(count(M.members) == 0 and count(w.hbdWorld) == 0 and count(w.hbdMini) == 0, "fake off clears everything")

w.set("selfPin", true)
local me = M.members["@self"]
check(me and me.mapID == 1429 and me.x == 0.5 and me.class == "SHAMAN" and me.level == 33, "self pin from C_Map")
check(pinFor(w, w.hbdWorld, "@self") and pinFor(w, w.hbdMini, "@self"), "self pin on both maps")
check(pinFor(w, w.hbdWorld, "@self").bg.color[1] == 1, "self pin has a white ring")
w.dead = true; w.advance(2)
check(M.members["@self"].flags.g, "ghost flag read")
w.dead = false
w.pos = nil; w.advance(2)
check(M.members["@self"] == nil and count(w.hbdWorld) == 0, "no position -> self pin removed")
w.set("fake", true)
check(anyPrinted(w, "isn't available here"), "fake without position explains")
w.pos = { 1429, 0, 0 }; w.advance(2)
check(M.members["@self"] == nil, "(0,0) counts as no position")
w.pos = { 1429, 0.4, 0.6 }; w.advance(2)
check(M.members["@self"] ~= nil, "position back -> self pin back")
w.set("selfPin", false)

w.set("fake", true)
local f1 = pinFor(w, w.hbdWorld, "~fake1")
f1._scripts.OnEnter(f1)
local tipText = table.concat(w.tip.lines, "|")
check(tipText:find("Test Eins", 1, true) and tipText:find("Test pin", 1, true) and tipText:find("Level 60", 1, true),
  "tooltip: name, level, test marker")
f1._scripts.OnClick(f1)
check(#w.tells == 0, "clicking a test pin doesn't whisper")
M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
  class = "MAGE", heard = w.env.GetTime(), flags = {} }
M:Refresh()
local hp = pinFor(w, w.hbdWorld, "Hans Wurst")
hp._scripts.OnEnter(hp)
local realTip = table.concat(w.tip.lines, "|")
check(not realTip:find("Click", 1, true) and realTip:find("Right-click: invite, inspect", 1, true),
  "a real dot's tooltip names only the right-click menu: " .. realTip)
do
  local page = w.env.CreateFrame("Frame")
  M:BuildPage(page)
  page:Show()
  M:RenderPage()
  local function ListRows()
    local out = {}
    for _, f in ipairs(w.frames) do
      local p = f.parent
      while p and p ~= page do p = p.parent end
      if p == page and f.cells and f.shown then out[#out + 1] = f end
    end
    return out
  end
  local function RowsByName()
    local byName, rowOf = {}, {}
    for _, r in ipairs(ListRows()) do
      local name = r.cells[1]:GetText()
      byName[name], rowOf[name] = (byName[name] or 0) + 1, r
    end
    return byName, rowOf
  end
  local shown, hansRow, fakeRow = 0, nil, nil
  for _, r in ipairs(ListRows()) do
    shown = shown + 1
    if r.key == "Hans Wurst" then hansRow = r elseif r.key == "~fake1" then fakeRow = r end
  end
  check(shown >= 7 and hansRow and hansRow.cells[1]:GetText() == "Hans Wurst" and hansRow.cells[2]:GetText() == "20",
    "the map tab lists the guildmates on the map with name and level (" .. shown .. " rows)")
  check(fakeRow and fakeRow.cells[1]:GetText() == "Test Eins (test)", "test dots are marked as tests in the list")
  local invites = {}
  w.env.C_PartyInfo = { InviteUnit = function(n) invites[#invites + 1] = n end }
  rawget(hansRow, "_scripts").OnClick(hansRow, "RightButton")
  w.env.C_PartyInfo = nil
  check(hansRow.clicks == "RightButtonUp" and invites[1] == "Hans Wurst", "only right-clicking a guildmate in the list reaches the same actions")
  local core = w.env.RavenquillExpedition
  local realRoster = core.roster
  core.roster = {
    ["Hans Wurst"] = { level = 20, class = "MAGE", online = true },
    ["Greta Stumm"] = { level = 33, class = "DRUID", online = true },
    ["Otto Weg"] = { level = 50, class = "ROGUE", online = false },
  }
  M:RenderPage()
  local byName, rowOf = RowsByName()
  hansRow = rowOf["Greta Stumm"]
  check(byName["Greta Stumm"] == 1 and hansRow.cells[2]:GetText() == "33" and hansRow.cells[3]:GetText() == "Unknown"
    and hansRow.cells[4]:GetText() == "", "an online guildmate who doesn't share is listed with an unknown zone")
  check(byName["Hans Wurst"] == 1, "a sharing guildmate on the roster is listed once")
  check(byName["Otto Weg"] == nil, "offline guildmates are not listed")
  invites = {}
  w.env.C_PartyInfo = { InviteUnit = function(n) invites[#invites + 1] = n end }
  rawget(hansRow, "_scripts").OnClick(hansRow, "RightButton")
  w.env.C_PartyInfo = nil
  check(invites[1] == "Greta Stumm", "right-clicking a guildmate who doesn't share still invites")
  hansRow._scripts.OnEnter(hansRow)
  check(table.concat(w.tip.lines, "|"):find("Not sharing a position", 1, true), "the tooltip says the guildmate isn't sharing")
  local env, guild = w.env, {}
  local realCount, realInfo = env.GetNumGuildMembers, env.GetGuildRosterInfo
  for i = 1, 25 do guild[i] = { name = ("Gast%02d Weit"):format(i), level = 30, class = "MAGE", online = true } end
  env.GetNumGuildMembers = function() return #guild end
  env.GetGuildRosterInfo = function(i)
    local r = guild[i]
    if r then return r.name .. "-Realm", "Member", 1, r.level, r.class, r.zone, "", "", r.online, 0, r.class end
  end
  w.fire("GUILD_ROSTER_UPDATE")
  byName = RowsByName()
  local listed = 0
  for i = 1, 25 do if byName[guild[i].name] == 1 then listed = listed + 1 end end
  check(listed == 25 and page.note:GetText() == "",
    "25 more online guildmates than fit: every one gets a row, no \"+N more\" (" .. listed .. " listed)")
  local list = page.list
  local last = list and list:FindY(function(m) return m.name == "Gast25 Weit" end)
  check(list and list:VisibleRows() == 18 and last and last >= 18 * 22,
    "the list shows 18 rows at a time and the last guildmate starts below them (" .. tostring(last) .. ")")
  local bottom = list and list:ScrollTo(math.huge)
  check(bottom and bottom > 0 and list:Offset() == bottom and last + 22 <= bottom + 18 * 22 and list:VisibleRows() == 18,
    "scrolled to the end, the last guildmate is in view (offset " .. tostring(bottom) .. ")")
  env.GetNumGuildMembers, env.GetGuildRosterInfo = realCount, realInfo
  core.roster = realRoster
  page:Hide()
end
local function FakeMenus(env)
  local menus = {}
  env.MenuUtil = { CreateContextMenu = function(owner, build)
    local menu = { owner = owner, titles = {}, entries = {} }
    local root = {
      CreateTitle = function(_, text) menu.titles[#menu.titles + 1] = text end,
      CreateButton = function(_, text, fn)
        local e = { text = text, fn = fn, enabled = true }
        e.SetEnabled = function(_, on) e.enabled = on end
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
local function Shape(menu)
  if not menu then return "no menu" end
  local out = { table.concat(menu.titles, "/") }
  for _, e in ipairs(menu.entries) do out[#out + 1] = e.text .. (e.enabled and "" or " (grey)") end
  return table.concat(out, "|")
end
local function GameCalls(env)
  local calls = {}
  local function record(api) return function(...) calls[#calls + 1] = api .. "(" .. table.concat({ ... }, ",") .. ")" end end
  env.C_PartyInfo = { InviteUnit = record("InviteUnit") }
  env.InspectUnit = record("InspectUnit")
  return calls
end
local function SeenAs(env, unit, canInspect)
  env.UnitNameUnmodified = function(u) if u == unit then return "Hans", "Wurst" end end
  env.CanInspect = function() return canInspect end
end
local ALL_GREY = "Hans Wurst|Invite|Whisper|Inspect (grey)|View Talents (grey)"
do
  local env = w.env
  local menus, calls, tells, ownName = FakeMenus(env), GameCalls(env), #w.tells, env.UnitNameUnmodified
  hp._scripts.OnClick(hp, "RightButton")
  f1._scripts.OnClick(f1, "RightButton")
  local far = menus[1]
  check(#menus == 1 and far.owner == hp and #w.tells == tells, "right-clicking a dot opens a menu for that guildmate; a test dot gets none")
  check(Shape(far) == ALL_GREY, "far away: invite, whisper, inspect, talents under just the name; without stored data or a nearby unit inspect and talents are greyed: " .. Shape(far))
  for _, e in ipairs(far.entries) do e.fn() end
  check(w.tells[#w.tells] == "Hans Wurst" and table.concat(calls, " ") == "InviteUnit(Hans Wurst)",
    "invite and whisper reach the guildmate; the greyed-out entries do nothing: " .. table.concat(calls, " "))
  SeenAs(env, "party2", true)
  hp._scripts.OnClick(hp, "RightButton")
  local near = menus[#menus]
  check(Shape(near) == "Hans Wurst|Invite|Whisper|Inspect|View Talents (grey)",
    "nearby in the group and inspectable: inspect enabled; talents only come from a stored spec, never the game's inspect: " .. Shape(near))
  for i = #calls, 1, -1 do calls[i] = nil end
  Entry(near, "Inspect").fn()
  check(table.concat(calls, " ") == "InspectUnit(party2)", "inspect acts on their unit: " .. table.concat(calls, " "))
  SeenAs(env, "target", false)
  hp._scripts.OnClick(hp, "RightButton")
  check(Shape(menus[#menus]) == ALL_GREY, "targeted but out of inspect range: Inspect greyed out like the game: " .. Shape(menus[#menus]))
  env.UnitNameUnmodified = ownName
  local selfMenus = #menus
  M.members["@probe"] = { key = "@probe", name = "Me", isSelf = true, mapID = 1429, x = 0.5, y = 0.5, flags = {} }
  rawset(hp, "key", "@probe")
  hp._scripts.OnClick(hp, "RightButton")
  rawset(hp, "key", "Hans Wurst")
  M.members["@probe"] = nil
  check(#menus == selfMenus, "your own dot opens no menu")
  env.UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_INTERACT, env.WHISPER, env.INSPECT = "Game Interact", "Game Whisper", "SECRET"
  env.issecretvalue = function(v) return v == "SECRET" end
  hp._scripts.OnClick(hp, "RightButton")
  check(Shape(menus[#menus]) == "Hans Wurst|Invite|Game Whisper|Inspect (grey)|View Talents (grey)",
    "labels are the game's own strings where it has them; a secret one falls back to ours; no Interact title: " .. Shape(menus[#menus]))
  env.UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_INTERACT, env.WHISPER, env.INSPECT, env.issecretvalue = nil, nil, nil, nil
  hp._scripts.OnEnter(hp)
  local tip = table.concat(w.tip.lines, "|")
  check(tip:find("Right-click: invite, inspect", 1, true) and not tip:find("zoom out", 1, true),
    "the dot's tooltip points to the menu and no longer to zooming out")
  f1._scripts.OnEnter(f1)
  check(not table.concat(w.tip.lines, "|"):find("Right-click", 1, true), "a test dot's tooltip offers no menu")
  local mini = pinFor(w, w.hbdMini, "Hans Wurst")
  check(hp.clicks == "RightButtonUp" and mini and mini.clicks == "RightButtonUp",
    "world-map and minimap dots take right-clicks only")
  env.MenuUtil = nil
  hp._scripts.OnClick(hp, "RightButton")
  check(calls[#calls] == "InviteUnit(Hans Wurst)", "without the game's menu, right-click still invites")
  env.C_PartyInfo, env.CanInspect, env.InspectUnit = nil, nil, nil
  check(#w.errors == 0, "menu: no Lua errors (" .. tostring(w.errors[1]) .. ")")
  FakeMenus(env)
  local modules = env.RavenquillExpedition.modules
  local realCraft = modules.Craft
  modules.Craft = { HasStoredGear = function() error("stored gear read broke") end }
  hp._scripts.OnClick(hp, "RightButton")
  modules.Craft = realCraft
  check(tostring(w.errors[1]):find("stored gear read broke", 1, true),
    "an error while building the menu reaches the error handler instead of vanishing: " .. tostring(w.errors[1]))
  for i = #w.errors, 1, -1 do w.errors[i] = nil end
  local db = env.RavenquillExpeditionDB
  if db then db.lastError = nil end
  env.MenuUtil = nil
end
do
  local wd = NewWorld({ locale = "deDE" })
  wd.fire("ADDON_LOADED", "RavenquillExpedition_Map")
  wd.fire("PLAYER_LOGIN")
  local menus, calls, shown = FakeMenus(wd.env), GameCalls(wd.env), {}
  wd.M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
    class = "MAGE", heard = wd.env.GetTime(), flags = {} }
  wd.M:Refresh()
  local pin = pinFor(wd, wd.hbdWorld, "Hans Wurst")
  pin._scripts.OnEnter(pin)
  local deTip = table.concat(wd.tip.lines, "|")
  check(deTip:find("Rechtsklick: einladen, betrachten", 1, true) and not deTip:find("Klicken", 1, true),
    "German tooltip names only the right-click menu: " .. deTip)
  check(not deTip:find("Interagieren", 1, true), "German tooltip says nothing about Interagieren")
  pin._scripts.OnClick(pin, "RightButton")
  local HEAD = "Hans Wurst|Gruppeneinladung anfragen|Flüstern|"
  check(Shape(menus[1]) == HEAD .. "Betrachten (grey)|Talente anzeigen (grey)",
    "German client without the game's strings: exactly these entries, read like the game's German menu, no Craft Advisor needed: " .. Shape(menus[1]))
  local craft = wd.RQ:NewModule("Craft", {})
  pin._scripts.OnClick(pin, "RightButton")
  check(Shape(menus[#menus]) == HEAD .. "Betrachten (grey)|Talente anzeigen (grey)",
    "a Craft Advisor without the inspect window: Betrachten and Talente anzeigen stay greyed: " .. Shape(menus[#menus]))
  local gear, spec = {}, {}
  function craft:HasStoredGear(key) return gear[key] == true end
  function craft:HasStoredSpec(key) return spec[key] == true end
  function craft:ShowInspect(key, view) shown[#shown + 1] = key .. ":" .. tostring(view) end
  local function MenuWith(hasGear, hasSpec)
    gear["Hans Wurst"], spec["Hans Wurst"] = hasGear, hasSpec
    pin._scripts.OnClick(pin, "RightButton")
    return menus[#menus]
  end
  local menu = MenuWith(true, false)
  check(Shape(menu) == HEAD .. "Betrachten|Talente anzeigen (grey)", "far away with stored gear only: Betrachten enabled, Talente anzeigen greyed: " .. Shape(menu))
  Entry(menu, "Betrachten").fn()
  Entry(menu, "Talente anzeigen").fn()
  check(table.concat(shown, " ") == "Hans Wurst:gear" and #calls == 0,
    "Betrachten opens Craft Advisor's window on the stored gear, not the game's inspect; the greyed talents do nothing: " .. table.concat(shown, " "))
  menu = MenuWith(false, true)
  check(Shape(menu) == HEAD .. "Betrachten (grey)|Talente anzeigen", "far away with a stored spec only: Talente anzeigen enabled, Betrachten greyed: " .. Shape(menu))
  Entry(menu, "Talente anzeigen").fn()
  check(shown[2] == "Hans Wurst:talents" and #shown == 2 and #calls == 0,
    "Talente anzeigen opens Craft Advisor's window on the talents page from anywhere, never the game's inspect: " .. tostring(shown[2]))
  check(Shape(MenuWith(true, true)) == HEAD .. "Betrachten|Talente anzeigen", "gear and spec stored: both enabled")
  check(Shape(MenuWith(false, false)) == HEAD .. "Betrachten (grey)|Talente anzeigen (grey)", "nothing stored and nobody nearby: both greyed")
  SeenAs(wd.env, "party2", true)
  menu = MenuWith(false, true)
  Entry(menu, "Betrachten").fn()
  check(Shape(menu) == HEAD .. "Betrachten|Talente anzeigen" and calls[#calls] == "InspectUnit(party2)" and #shown == 2,
    "nearby without stored gear: Betrachten falls back to the game's inspect on their unit: " .. Shape(menu) .. " " .. tostring(calls[#calls]))
  check(#wd.errors == 0, "German menu with and without Craft Advisor: no Lua errors (" .. tostring(wd.errors[1]) .. ")")
end
M.members["Weird Map"] = { key = "Weird Map", name = "Weird Map", mapID = 999999, x = 0.3, y = 0.3, heard = w.env.GetTime(), flags = {} }
M.members["Bad Data"] = { key = "Bad Data", name = "Bad Data", mapID = "x", x = 2, y = 0.3, heard = w.env.GetTime(), flags = {} }
M:Refresh()
check(not pinFor(w, w.hbdWorld, "Weird Map") and not pinFor(w, w.hbdWorld, "Bad Data"), "unknown map / bad data: no pin, no error")

local d = w.diag()
check(d:find("WOW_PROJECT_ID=15", 1, true) and d:find("Forever branch", 1, true), "diagnostics: project IDs")
check(d:find("HBD matches the client", 1, true) or d:find("differs", 1, true), "diagnostics: HBD vs client")
check(not d:find("|c", 1, true) and not d:find("|r", 1, true), "diagnostics are plain text (copyable)")
local mod1 = w.M
local okShape = #mod1.options >= 10
for _, o in ipairs(mod1.options) do
  if type(o.label) ~= "string" or o.label == "" then okShape = false end
  if o.type == "toggle" and not (o.get and o.set) then okShape = false end
  if o.type == "range" and not (o.get and o.set and o.min and o.max and o.step) then okShape = false end
  if o.type == "text" and not o.lines then okShape = false end
end
check(okShape, "options: every entry has a label and its functions")
local untipped = {}
for _, o in ipairs(mod1.options) do
  if o.type ~= "header" and not o.tooltip then untipped[#untipped + 1] = o.key or o.id or o.label end
end
check(#untipped == 0, "every map option explains itself on hover (" .. table.concat(untipped, ", ") .. ")")
w.set("worldmap", false)
check(mod1:Option("names").disabled() == true, "names option greyed out while the world map is off")
w.set("worldmap", true)
check(mod1:Option("names").disabled() == false and mod1:Option("names").get() == true, "names option back")
check(w.env.SLASH_RAVENQUILLMAP1 == nil and w.env.SlashCmdList.RAVENQUILLMAP == nil, "the map registers no chat command")
check(#w.errors == 0 and not (w.env.RavenquillExpeditionDB or {}).lastError, "no Lua errors (" .. tostring(w.errors[1]) .. ")")

local wc = NewWorld()
local mod = wc.RQ:GetModule("Map")
check(wc.env.SLASH_RAVENQUILLMAP1 == nil and wc.env.SlashCmdList.RAVENQUILLMAP == nil, "with the core: the map leaves /rq to it")
check(mod.icon == "Interface\\Icons\\INV_Misc_Map_01", "overview: module icon")
local toggled = 0
wc.env.ToggleWorldMap = function() toggled = toggled + 1 end
mod:Open()
check(toggled == 1, "overview: Open toggles the world map")
wc.env.ToggleWorldMap = function() error("blocked") end
local shown = 0
wc.env.WorldMapFrame = { Show = function() shown = shown + 1 end }
mod:Open()
check(shown == 1, "overview: Open falls back to WorldMapFrame:Show() if ToggleWorldMap fails")
check(mod and mod.addon == "RavenquillExpedition_Map" and mod.slash == "map", "registered as core module (addon = ADDON, slash map)")
wc.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wc.fire("PLAYER_LOGIN")
check(mod == wc.M and wc.env.RavenquillExpeditionMap == mod and mod.api == 2 and mod.db == wc.env.RavenquillExpeditionMapDB,
  "API 2 module: the core set up RavenquillExpeditionMapDB")
wc.set("selfPin", true)
check(wc.M.members["@self"] and wc.M.members["@self"].name == wc.RQ:PlayerKey(), "core helpers used (PlayerKey)")
wc.set("selfPin", false)
check(#mod.options >= 10 and mod.OnSlash == nil, "options handed to the core, no subcommands")
wc.set("fake", true)
check(count(wc.M.members) == 7, "test dots via the option")
check(mod:OverviewStatus() == "On the map: 0 · sharing on", "overview: test pins don't count as guildmates ("
  .. tostring(mod:OverviewStatus()) .. ")")
wc.M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
  class = "MAGE", heard = wc.env.GetTime(), flags = {} }
local commState = wc.RQ.CommState
wc.RQ.CommState = function(self) local st = commState(self); st.slow = true; return st end
local st = mod:OverviewStatus()
check(st:find("^On the map: 1 ") and st:find("getting through"), "overview: status counts guildmates, warns when slow")
wc.RQ.CommState = commState
wc.advance(10)
check(anyPrinted(wc, "Ravenquill Expedition|r |cffbbbbbbGuild Map"), "printing goes through the core (module title)")
check(#wc.errors == 0, "core run: no Lua errors")

local wt = NewWorld()
wt.env.RavenquillExpeditionMapDB = { v = 1, settings = { share = false } }
wt.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wt.fire("PLAYER_LOGIN"); wt.advance(10)
check(wt.M.ticker == nil, "ticker: not running with sharing off and nothing to show")
wt.set("fake", true)
check(wt.M.ticker ~= nil, "ticker: runs while test pins are shown")
wt.set("fake", false); wt.advance(4)
check(wt.M.ticker == nil, "ticker: stops when nothing is left to update")
wt.set("share", true)
check(wt.M.ticker ~= nil, "ticker: runs while sharing")
check(#wt.errors == 0, "ticker: no Lua errors (" .. tostring(wt.errors[1]) .. ")")

local wd = NewWorld({ locale = "deDE" })
wd.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wd.fire("PLAYER_LOGIN"); wd.advance(10)
check(wd.L.TITLE == "Gildenkarte" and anyPrinted(wd, "teilt deine Position"), "German strings")
check(wd.M:Option("share").label == "Meine Position mit der Gilde teilen" and wd.M.openLabel == "Weltkarte"
  and wd.M:Option("diag") == nil and wd.M:OverviewDiagnostics()[1] ~= nil,
  "German option labels; the card opens the 'Weltkarte'; diagnostics live in the overview, not in the options")
check(anyPrinted(wd, "unter /rq", true) or anyPrinted(wd, "/rq|r", true), "German notice points to /rq")
check(#wd.errors == 0, "German client: no Lua errors")

local wm = NewWorld({ worldMap = true })
local map = wm.map
wm.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wm.fire("PLAYER_LOGIN")
wm.set("fake", true)
check(count(wm.hbdWorld) == 7, "world map: 7 test pins placed")
check(wm.hbdWorldCalls == 0, "world map: HBD's world map API (a WorldMapFrame data provider) is never called")
check(#map.calls == 0, "world map: only read methods on WorldMapFrame, nothing written (" .. tostring(map.calls[1]) .. ")")
check(next(map.providers) == nil, "world map: no data provider registered")
local lay = wm.M.worldLayer
check(lay and lay.parent == map.canvas and lay.allPoints == map.canvas, "world map: our layer is a child of the canvas")
check(lay and lay._scripts.OnShow == nil and lay._scripts.OnUpdate ~= nil, "world map: layer draws on OnUpdate, has no OnShow")
local onShow = 0
for f in pairs(wm.hbdWorld) do
  if f.parent ~= lay then onShow = onShow + 100 end
  if f._scripts.OnShow then onShow = onShow + 1 end
end
check(onShow == 0, "world map: every pin sits on the layer, none has an OnShow script")
local p1 = pinFor(wm, wm.hbdWorld, "~fake1")
local points0 = p1.points or 0
check(map.blizzardShow() == 0, "world map: none of our code runs in Blizzard's show path")
check((p1.points or 0) == points0, "world map: nothing is drawn during the show")
map.renderFrame()
local d1 = wm.hbdWorld[p1]
check(p1.shown and p1.point and p1.point[2] == lay and p1.point[3] == "TOPLEFT", "world map: pin drawn on the next frame")
check(p1.point and math.abs(p1.point[4] - d1.x * 1000) < 1e-6 and math.abs(p1.point[5] + d1.y * 700) < 1e-6,
  "world map: zone map position = x * width, -y * height")
local points1 = p1.points
map.renderFrame()
check(p1.points == points1, "world map: no redraw while nothing changed")
map.mapID = 1415; map.renderFrame()
check(p1.shown and math.abs(p1.point[4] - (0.4 + d1.x * 0.2) * 1000) < 1e-6, "world map: shown on the continent above it")
map.mapID = 947; map.renderFrame()
check(p1.shown and math.abs(p1.point[4] - (0.5 + d1.x * 0.1) * 1000) < 1e-6, "world map: shown on the Azeroth map")
map.mapID = 1411; map.renderFrame()
check(not p1.shown, "world map: hidden on a neighbouring zone")
map.mapID = 5555; map.renderFrame()
check(not p1.shown, "world map: hidden on a map HBD doesn't know")
map.mapID, map.scale = 1429, 2; map.renderFrame()
check(p1.shown and p1.scale == 0.5 and math.abs(p1.point[4] - d1.x * 1000 * 2) < 1e-6,
  "world map: zoomed in, the pin keeps its size and its place")
map.scale = 1
local x0w = d1.x
wm.advance(20)
local d2 = wm.hbdWorld[p1]
map.renderFrame()
check(d2 and d2.x ~= x0w and math.abs(p1.point[4] - d2.x * 1000) < 1e-6, "world map: a moved pin is redrawn")
check(wm.maxCanvas() == 1, "world map: still one pin per member after moves")
wm.set("worldmap", false)
check(count(wm.hbdWorld) == 0 and not p1.shown, "world map: option off hides our pins")
check(#map.calls == 0 and wm.hbdWorldCalls == 0, "world map: still nothing written to WorldMapFrame")
check(#wm.errors == 0, "world map: no Lua errors (" .. tostring(wm.errors[1]) .. ")")

local toggles = 0
wm.env.ToggleWorldMap = function() toggles = toggles + 1 end
wm.env.InCombatLockdown = function() return true end
wm.M:Open()
check(toggles == 0 and anyPrinted(wm, "after combat"), "overview: no map opening from addon code in combat")
wm.env.InCombatLockdown = function() return false end
wm.M:Open()
check(toggles == 1, "overview: opens the map out of combat")

do
  local env = setmetatable({}, { __index = _G })
  env._G = env
  local calls = {}
  local function Frame()
    return setmetatable({}, { __index = function(_, k)
      if k == "GetZoom" then return function() return 0 end end
      if k == "IsVisible" then return function() return false end end
      if type(k) == "string" and k:match("^%u") then return function() end end
    end })
  end
  env.CreateFrame = function() return Frame() end
  env.Minimap = Frame()
  env.GetCVar = function() return "0" end
  env.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end; return o end
  env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
  env.MapCanvasDataProviderMixin = {
    OnAdded = function(self, m) self.owningMap = m end,
    GetMap = function(self) return self.owningMap end,
  }
  env.MapCanvasPinMixin = {}
  env.CreateUnsecuredRegionPoolInstance = function() return {} end
  local canvas = Frame()
  local wmf = { calls = calls }
  wmf.pinPools = setmetatable({}, { __newindex = function(t, k, v) calls[#calls + 1] = "pinPools." .. k; rawset(t, k, v) end })
  setmetatable(wmf, { __index = function(_, k)
    if k == "GetCanvas" then return function() return canvas end end
    if k == "IsShown" then return function() return true end end
    if k == "GetMapID" then return function() return nil end end
    if k == "AddDataProvider" then return function(self, p) calls[#calls + 1] = k; p:OnAdded(self) end end
    if type(k) == "string" and k:match("^%u") then return function() calls[#calls + 1] = k end end
  end })
  env.WorldMapFrame = wmf
  assert(loadfile(DIR .. "/libs/LibStub/LibStub.lua", "t", env))()
  local hbd = env.LibStub:NewLibrary("HereBeDragons-2.0-RQE", 999)
  hbd.mapData = {}
  hbd.RegisterCallback = function() end
  hbd.GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end
  local okLoad, err = pcall(assert(loadfile(DIR .. "/libs/HereBeDragons/HereBeDragons-Pins-2.0.lua", "t", env)))
  check(okLoad, "HBD-Pins loads in the stub (" .. tostring(err) .. ")")
  local lib = env.LibStub("HereBeDragons-Pins-2.0-RQE", true)
  check(lib and #calls == 0, "HBD-Pins: nothing registered on WorldMapFrame at load (" .. tostring(calls[1]) .. ")")
  if lib then
    local icon = Frame()
    check(pcall(lib.RemoveWorldMapIcon, lib, "x", icon) and pcall(lib.RemoveAllWorldMapIcons, lib, "x"),
      "HBD-Pins: world map removals work while not attached")
    lib.worldmapProvider:RefreshAllData()
    check(#calls == 0, "HBD-Pins: still nothing on WorldMapFrame")
    check(lib:AddWorldMapIconMap("x", icon, 1429, 0.5, 0.5) == true, "HBD-Pins: another addon's world icon still works")
    local providers = 0
    for _, c in ipairs(calls) do if c == "AddDataProvider" then providers = providers + 1 end end
    lib:AddWorldMapIconMap("x", Frame(), 1429, 0.4, 0.4)
    local providers2 = 0
    for _, c in ipairs(calls) do if c == "AddDataProvider" then providers2 = providers2 + 1 end end
    check(providers == 1 and providers2 == 1 and wmf.pinPools.HereBeDragonsPinsTemplate,
      "HBD-Pins: attaches to the world map once, on the first world icon")
  end
end

do
  local function src(f) local h = assert(io.open(DIR .. "/" .. f, "rb")); local s = h:read("*a"); h:close(); return s end
  local shared = 0
  for _, f in ipairs({ "Map.lua", "Pins.lua", "Sync.lua", "Locale.lua" }) do
    for _ in src(f):gmatch('LibStub%(%s*"HereBeDragons%-[%w%-%.]-2%.0"') do shared = shared + 1 end
  end
  check(shared == 0, "Map never asks LibStub for the shared HereBeDragons copies")
  check(src("libs/HereBeDragons/HereBeDragons-2.0.lua"):find('MAJOR, MINOR = "HereBeDragons-2.0-RQE"', 1, true)
    and src("libs/HereBeDragons/HereBeDragons-Pins-2.0.lua"):find('MAJOR, MINOR = "HereBeDragons-Pins-2.0-RQE"', 1, true)
    and src("libs/HereBeDragons/HereBeDragons-Pins-2.0.lua"):find('LibStub("HereBeDragons-2.0-RQE")', 1, true),
    "our embedded copies register under private names and use each other")
end

do
  local wo = NewWorld({ worldMap = true })
  wo.fire("ADDON_LOADED", "RavenquillExpedition_Map")
  wo.fire("PLAYER_LOGIN")
  local art = wo.env.CreateFrame("Frame", nil, wo.map.canvas)
  art.level = 800
  wo.M:Fake(true)
  wo.advance(3)
  wo.map.blizzardShow()
  wo.map.renderFrame()
  local layer = wo.M.worldLayer
  local pinsAbove = true
  for f in pairs(wo.M.worldPlaced) do if (f.level or 0) <= 800 then pinsAbove = false end end
  check(layer and layer.level and layer.level > 800 and pinsAbove, "our layer and pins sit above the map's highest frame (level 800)")
  local later = wo.env.CreateFrame("Frame", nil, wo.map.canvas)
  later.level = 2000
  for _ = 1, 40 do wo.map.renderFrame() end
  check(layer.level > 2000, "a higher frame added while the map is open: the layer moves above it (" .. tostring(layer.level) .. ")")
end

do
  local wg = NewWorld({ worldMap = true })
  wg.fire("ADDON_LOADED", "RavenquillExpedition_Map")
  wg.fire("PLAYER_LOGIN")
  local M2 = wg.M
  check(M2.settings.hideGroup == true and M2:Option("hideGroup") ~= nil, "option exists, on by default")
  local now = wg.env.GetTime()
  M2.members["Bert Beta"] = { key = "Bert Beta", name = "Bert Beta", mapID = 1429, x = 0.5, y = 0.5, level = 30,
    class = "DRUID", heard = now, flags = {} }
  local core = wg.env.RavenquillExpedition
  core.GroupGuildies = function() return { "Bert Beta" } end
  local function pinsFor(key)
    local world, mini = false, false
    for f in pairs(M2.worldPlaced) do if f.key == key then world = true end end
    for icon in pairs(wg.hbdMini) do if icon.key == key then mini = true end end
    return world, mini
  end
  M2:RefreshPins()
  local world1, mini1 = pinsFor("Bert Beta")
  check(not world1 and not mini1, "a guildmate in my group: no world or minimap dot")
  wg.set("hideGroup", false)
  M2:RefreshPins()
  local world2, mini2 = pinsFor("Bert Beta")
  check(world2 and mini2, "option off: the dots are back")
  wg.set("hideGroup", true)
  core.GroupGuildies = function() return {} end
  M2:RefreshPins()
  local w3 = pinsFor("Bert Beta")
  check(w3, "left the group: the dot is shown again")
  core.GroupGuildies = function() error("group read broke") end
  local db = wg.env.RavenquillExpeditionDB
  if db then db.lastError = nil end
  M2:RefreshPins()
  local w4 = pinsFor("Bert Beta")
  local recorded = db and db.lastError and tostring(db.lastError.msg) or "nothing"
  check(w4 and recorded:find("group read broke", 1, true), "a failing group read still shows the dot and is recorded as an error: " .. recorded)
end

Kit.finish()
