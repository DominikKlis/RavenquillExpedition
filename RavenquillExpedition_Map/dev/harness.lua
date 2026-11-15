-- Offline Step 1 harness for RavenquillExpedition_Map: mocks the WoW API and HereBeDragons, loads Locale/Map/Pins,
-- and asserts settings, notice, test-pin lifecycle, minimap rule, self pin, tooltips, clicks, core routing, deDE.
-- Run from anywhere:  lua "<addon>/dev/harness.lua"      (exit code 1 on failure)
-- HereBeDragons itself is NOT exercised here (it's mocked); real placement can only be checked in game.
local DIR = (arg and arg[0] or ""):gsub("[/\\]dev[/\\]harness%.lua$", "")
if DIR == "" or DIR == arg[0] then DIR = "." end

local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. what) end
end

local function NewWorld(opts)
  opts = opts or {}
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.unpack = table.unpack or unpack
  local clock, timers = 0, {}
  env.GetTime = function() return clock end
  env.time = function() return 1763100000 + math.floor(clock) end
  env.GetServerTime = env.time
  env.C_Timer = {
    After = function(t, fn) timers[#timers + 1] = { at = clock + t, fn = fn } end,
    NewTicker = function(t, fn) timers[#timers + 1] = { at = clock + t, fn = fn, every = t } end,
  }
  local function advance(sec)
    local target = clock + sec
    while true do
      local nextT, idx = nil, nil
      for i, tm in ipairs(timers) do if tm.at <= target and (not nextT or tm.at < nextT) then nextT, idx = tm.at, i end end
      if not idx then break end
      local tm = timers[idx]
      clock = tm.at
      if tm.every then tm.at = tm.at + tm.every else table.remove(timers, idx) end
      tm.fn()
    end
    clock = target
  end

  local printed, errors = {}, {}
  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(t, " ")
  end
  env.geterrorhandler = function() return function(msg) errors[#errors + 1] = msg end end
  env.debugstack = function() return "" end
  env.GetBuildInfo = function() return "1.60.1", "99999", "Nov 2026", 16001 end
  env.GetLocale = function() return opts.locale or "enUS" end
  env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CLASSIC = 15, 15, 1, 2
  env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
  env.UNKNOWNOBJECT = "Unknown"
  env.Ambiguate = function(n) return n end
  env.UnitName = function() return "Ängis", "Waldbach" end
  env.UnitNameUnmodified = env.UnitName
  env.UnitClass = function() return "Shaman", "SHAMAN" end
  env.UnitLevel = function() return 33 end
  local dead, taxi, inInstance = false, false, false
  env.UnitIsDeadOrGhost = function() return dead end
  env.UnitOnTaxi = function() return taxi end
  env.IsInInstance = function() return inInstance end
  env.IsIndoors = function() return false end
  env.C_CVar = { GetCVar = function() return "0" end }
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0 } end })
  env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k:lower() end })
  local ownPos = { 1429, 0.5, 0.5 }
  env.C_Map = {
    GetBestMapForUnit = function() if ownPos then return ownPos[1] end end,
    GetPlayerMapPosition = function()
      if not ownPos then return nil end
      return { GetXY = function() return ownPos[2], ownPos[3] end }
    end,
    GetMapInfo = function(id) return { name = "Map" .. id } end,
  }

  -- frames
  local frames = {}
  local function NewFrame(kind)
    local f = { shown = true, alpha = 1, scripts = {}, events = {} }
    local methods = {
      Hide = function(s) s.shown = false end, Show = function(s) s.shown = true end,
      SetAlpha = function(s, a) s.alpha = a end, SetScript = function(s, k, fn) s.scripts[k] = fn end,
      RegisterEvent = function(s, e) s.events[e] = true end,
      SetSize = function(s, w, h) s.w, s.h = w, h end,
      SetText = function(s, t) s.text = t end,
      SetVertexColor = function(s, r, g, b, a) s.color = { r, g, b, a } end,
      CreateTexture = function() return NewFrame("tex") end,
      CreateFontString = function() return NewFrame("fs") end,
      GetZoom = function() return 2 end,
    }
    -- unknown Methods are no-ops; unknown lowercase fields are nil, as on real frames
    return setmetatable(f, { __index = function(_, k) return methods[k] or (k:match("^%u") and function() end or nil) end })
  end
  env.CreateFrame = function(kind) local f = NewFrame(kind); frames[#frames + 1] = f; return f end
  env.UIParent, env.Minimap = NewFrame(), NewFrame()
  local tip = { lines = {} }
  env.GameTooltip = setmetatable(tip, { __index = function(_, k)
    if k == "AddLine" then return function(_, t) tip.lines[#tip.lines + 1] = t end end
    if k == "SetOwner" then return function() tip.lines = {} end end
    return function() end
  end })
  local tells = {}
  env.ChatFrameUtil = { SendTell = function(n) tells[#tells + 1] = n end }
  env.SlashCmdList = {}

  -- HereBeDragons mock
  local hbdWorld, hbdMini, hbdAdds, canvas = {}, {}, 0, {}
  local HBD = {
    GetPlayerZone = function() return ownPos and ownPos[1], 3 end,
    GetPlayerZonePosition = function() if ownPos then return ownPos[2] + 0.001, ownPos[3], ownPos[1], 3 end end,
  }
  local function add(store)
    return function(_, ref, icon, mapID, x, y)
      assert(ref and type(icon) == "table" and type(mapID) == "number" and type(x) == "number" and type(y) == "number",
        "HBD would raise: bad args")
      if mapID == 999999 then return false end
      hbdAdds = hbdAdds + 1
      store[icon] = { mapID = mapID, x = x, y = y }
      if store == hbdWorld then canvas[icon] = (canvas[icon] or 0) + 1 end -- HBD acquires a new canvas pin per add
      icon.shown = true
      return true
    end
  end
  local Pins = {
    AddWorldMapIconMap = add(hbdWorld), AddMinimapIconMap = add(hbdMini),
    RemoveWorldMapIcon = function(_, _, icon) hbdWorld[icon] = nil; canvas[icon] = nil end,
    RemoveMinimapIcon = function(_, _, icon) hbdMini[icon] = nil; icon.shown = false end,
  }
  env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
  env.LibStub = setmetatable({ minors = { ["HereBeDragons-2.0"] = 35, ["HereBeDragons-Pins-2.0"] = 17 } }, {
    __call = function(_, name) return name == "HereBeDragons-2.0" and HBD or Pins end })

  if opts.core then
    local core = { version = "0.1.0", modules = {} }
    core.SafeCall = function(fn, ...) if type(fn) ~= "function" then return end
      local r = table.pack(pcall(fn, ...)); if r[1] then return table.unpack(r, 2, r.n) end end
    core.IsSecret = function() return false end
    core.Print = function(tag, ...) env.print("[core]", tag, ...) end
    function core:Now() return 42 end
    function core:PlayerKey() return "Core Key" end
    function core:NewModule(name, mod) mod.name = name; self.modules[name] = mod; return mod end
    env.RavenquillExpedition = core
  end

  local ns = {}
  for _, file in ipairs({ "Locale.lua", "Map.lua", "Pins.lua", "Sync.lua" }) do
    local chunk = assert(loadfile(DIR .. "/" .. file, "t", env))
    chunk("RavenquillExpedition_Map", ns)
  end
  local M = ns.Map
  local function fire(event, arg1)
    for _, f in ipairs(frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, arg1) end
    end
  end
  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

  return {
    env = env, ns = ns, M = M, L = ns.L, fire = fire, advance = advance, printed = printed, errors = errors,
    tip = tip, tells = tells, hbdWorld = hbdWorld, hbdMini = hbdMini, count = count,
    setPos = function(p) ownPos = p end, setDead = function(v) dead = v end, setTaxi = function(v) taxi = v end,
    -- the settings view in the /rq overview: set an option, read the diagnostics box
    set = function(id, v) local o = ns.Map:Option(id); assert(o and o.set, "no option " .. id); o.set(v) end,
    diag = function() return table.concat(ns.Map:Option("diag").lines(), "\n") end,
    adds = function() return hbdAdds end,
    maxCanvas = function() local m = 0; for _, n in pairs(canvas) do m = math.max(m, n) end; return m end,
  }
end

local function anyPrinted(w, needle)
  for _, line in ipairs(w.printed) do if line:find(needle, 1, true) then return true end end
  return false
end

local function pinFor(w, store, key)
  for icon in pairs(store) do if icon.key == key then return icon end end
end

---------------------------------------------------------------------------
-- 1. Load, defaults, notice once
---------------------------------------------------------------------------
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
check(M:PlayerKey() == "Ängis Waldbach", "shim PlayerKey = First Surname")

-- relog with the saved table: no second notice
local saved = M.db
local w1 = NewWorld()
w1.env.RavenquillExpeditionMapDB = saved
w1.fire("ADDON_LOADED", "RavenquillExpedition_Map"); w1.fire("PLAYER_LOGIN"); w1.advance(20)
check(not anyPrinted(w1, "shares your position"), "notice only once across logins")

-- corrupt settings are repaired
local w2 = NewWorld()
w2.env.RavenquillExpeditionMapDB = { settings = { share = "yes", size = 9 } }
w2.fire("ADDON_LOADED", "RavenquillExpedition_Map")
check(w2.M.settings.share == true and w2.M.settings.size == 1, "bad saved values repaired")

---------------------------------------------------------------------------
-- 2. Test pins: lifecycle and minimap rule
---------------------------------------------------------------------------
w.set("fake", true)
check(w.count(M.members) == 7, "7 test pins")
check(w.count(w.hbdWorld) == 7, "world: all 7 placed (stale one too)")
-- minimap: Fünf (age 200) excluded; Sechs (age 0) and stationary Zwei included
check(w.count(w.hbdMini) == 6, "minimap: 6 (stale Fünf hidden), got " .. w.count(w.hbdMini))
local fuenf = pinFor(w, w.hbdWorld, "~fake5")
check(fuenf and fuenf.alpha == 0.45, "stale pin is dimmed")
local vier = pinFor(w, w.hbdWorld, "~fake4")
check(vier and vier.bg.color[1] == 1 and vier.bg.color[2] == 0.82, "taxi pin has a gold ring")
local drei = pinFor(w, w.hbdWorld, "~fake3")
check(drei and drei.fg.color[1] == 0.55, "ghost pin is grey")
for _, p in pairs(w.hbdWorld) do
  check(p.mapID == 1429 and p.x >= 0.01 and p.x <= 0.99, "test pins placed by map ID within bounds"); break
end
local x0 = M.members["~fake1"].x
w.advance(50)
check(M.members["~fake1"].x ~= x0, "moving test pin moved")
check(w.maxCanvas() == 1, "moved world pins leave no orphan canvas pins (code review #1)")
check(not pinFor(w, w.hbdMini, "~fake6"), "non-updating pin leaves the minimap after 45 s")
check(pinFor(w, w.hbdMini, "~fake2"), "stationary pin stays on the minimap")
check(pinFor(w, w.hbdMini, "~fake1"), "updating pin stays on the minimap")
w.advance(120) -- t = 170 after fake: Fünf age 370 >= 360 -> gone
check(M.members["~fake5"] == nil and not pinFor(w, w.hbdWorld, "~fake5"), "stale pin removed at 2x fade")
w.advance(20)  -- 190: Sechs (age 190) stale
check(M:State(M.members["~fake6"]) == "stale", "pin fades at 180 s")
w.advance(180) -- 370: Sechs gone
check(M.members["~fake6"] == nil, "pin removed at 360 s")
check(M.members["~fake2"] and M:State(M.members["~fake2"]) == "fresh", "stationary still fresh at 370 s (fades at 450)")
w.advance(100) -- 470
check(M:State(M.members["~fake2"]) == "stale", "stationary fades at 1.5 x heartbeat")

-- toggles
w.set("minimap", false)
check(w.count(w.hbdMini) == 0, "minimap off removes minimap pins")
w.set("minimap", true)
check(w.count(w.hbdMini) > 0, "minimap on restores")
w.set("worldmap", false)
check(w.count(w.hbdWorld) == 0, "worldmap off removes world pins")
w.set("worldmap", true)
w.set("names", true)
local any = next(w.hbdWorld)
check(any and any.label.shown and any.label.text ~= nil, "names on shows labels")
w.set("size", 7)
check(M.settings.size == 2, "size is clamped to 0.5-2")
w.set("size", 1.5)
check(M.settings.size == 1.5 and any.w == 21, "size applied to existing pins")
w.set("fake", false)
check(w.count(M.members) == 0 and w.count(w.hbdWorld) == 0 and w.count(w.hbdMini) == 0, "fake off clears everything")

---------------------------------------------------------------------------
-- 3. Self pin, no position, tooltips, click, unknown map
---------------------------------------------------------------------------
w.set("selfPin", true)
local me = M.members["@self"]
check(me and me.mapID == 1429 and me.x == 0.5 and me.class == "SHAMAN" and me.level == 33, "self pin from C_Map")
check(pinFor(w, w.hbdWorld, "@self") and pinFor(w, w.hbdMini, "@self"), "self pin on both maps")
check(pinFor(w, w.hbdWorld, "@self").bg.color[1] == 1, "self pin has a white ring")
w.setDead(true); w.advance(2)
check(M.members["@self"].flags.g, "ghost flag read")
w.setDead(false)
w.setPos(nil); w.advance(2)
check(M.members["@self"] == nil and w.count(w.hbdWorld) == 0, "no position -> self pin removed")
w.set("fake", true)
check(anyPrinted(w, "isn't available here"), "fake without position explains")
w.setPos({ 1429, 0, 0 }); w.advance(2)
check(M.members["@self"] == nil, "(0,0) counts as no position")
w.setPos({ 1429, 0.4, 0.6 }); w.advance(2)
check(M.members["@self"] ~= nil, "position back -> self pin back")
w.set("selfPin", false)

w.set("fake", true)
local f1 = pinFor(w, w.hbdWorld, "~fake1")
f1.scripts.OnEnter(f1)
local tipText = table.concat(w.tip.lines, "|")
check(tipText:find("Test Eins", 1, true) and tipText:find("Test pin", 1, true) and tipText:find("Level 60", 1, true),
  "tooltip: name, level, test marker")
f1.scripts.OnClick(f1)
check(#w.tells == 0, "clicking a test pin doesn't whisper")
-- a "real" member (as step 2 will add)
M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
  class = "MAGE", heard = w.env.GetTime(), flags = {} }
M:Refresh()
local hp = pinFor(w, w.hbdWorld, "Hans Wurst")
hp.scripts.OnEnter(hp)
check(table.concat(w.tip.lines, "|"):find("Click to whisper", 1, true), "real pin tooltip offers whisper")
hp.scripts.OnClick(hp)
check(w.tells[1] == "Hans Wurst", "click whispers the real player")
M.members["Weird Map"] = { key = "Weird Map", name = "Weird Map", mapID = 999999, x = 0.3, y = 0.3, heard = w.env.GetTime(), flags = {} }
M.members["Bad Data"] = { key = "Bad Data", name = "Bad Data", mapID = "x", x = 2, y = 0.3, heard = w.env.GetTime(), flags = {} }
M:Refresh()
check(not pinFor(w, w.hbdWorld, "Weird Map") and not pinFor(w, w.hbdWorld, "Bad Data"), "unknown map / bad data: no pin, no error")

local d = w.diag()
check(d:find("WOW_PROJECT_ID=15", 1, true) and d:find("Forever branch", 1, true), "diagnostics: project IDs")
check(d:find("HBD matches the client", 1, true) or d:find("differs", 1, true), "diagnostics: HBD vs client")
check(not d:find("|c", 1, true) and not d:find("|r", 1, true), "diagnostics are plain text (copyable)")
-- options for the /rq overview (no chat commands any more)
local okShape = #M.options >= 10
for _, o in ipairs(M.options) do
  if type(o.label) ~= "string" or o.label == "" then okShape = false end
  if o.type == "toggle" and not (o.get and o.set) then okShape = false end
  if o.type == "range" and not (o.get and o.set and o.min and o.max and o.step) then okShape = false end
  if o.type == "text" and not o.lines then okShape = false end
end
check(okShape, "options: every entry has a label and its functions")
w.set("worldmap", false)
check(M:Option("names").disabled() == true, "names option greyed out while the world map is off")
w.set("worldmap", true)
check(M:Option("names").disabled() == false and M:Option("names").get() == true, "names option back")
check(w.env.SLASH_RAVENQUILLMAP1 == nil and w.env.SlashCmdList.RAVENQUILLMAP == nil, "the map registers no chat command")
check(#w.errors == 0 and not M.db.lastError, "no Lua errors (" .. tostring(w.errors[1]) .. ")")

---------------------------------------------------------------------------
-- 4. With the core; German client
---------------------------------------------------------------------------
local wc = NewWorld({ core = true })
local mod = wc.env.RavenquillExpedition.modules.Map
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
check(wc.M:PlayerKey() == "Core Key" and wc.M:Now() == 42, "core helpers used when present")
check(mod.options == wc.M.options and #mod.options > 0 and mod.OnSlash == nil, "options handed to the core, no subcommands")
wc.set("fake", true)
check(wc.count(wc.M.members) == 7, "test dots via the option")
check(mod:OverviewStatus() == "On the map: 0 · sharing on", "overview: test pins don't count as guildmates ("
  .. tostring(mod:OverviewStatus()) .. ")")
wc.M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
  class = "MAGE", heard = wc.env.GetTime(), flags = {} }
wc.M.sync.slow = true
local st = mod:OverviewStatus()
check(st:find("^On the map: 1 ") and st:find("getting through"), "overview: status counts guildmates, warns when slow")
wc.M.sync.slow = false
wc.advance(10)
check(anyPrinted(wc, "[core]"), "printing goes through the core")
check(#wc.errors == 0, "core run: no Lua errors")

local wd = NewWorld({ locale = "deDE" })
wd.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wd.fire("PLAYER_LOGIN"); wd.advance(10)
check(wd.L.TITLE == "Gildenkarte" and anyPrinted(wd, "teilt deine Position"), "German strings")
check(wd.M:Option("share").label == "Meine Position mit der Gilde teilen" and wd.M:Option("diag").label == "Diagnose",
  "German option labels")
check(anyPrinted(wd, "unter /rq", true) or anyPrinted(wd, "/rq|r", true), "German notice points to /rq")
check(#wd.errors == 0, "German client: no Lua errors")

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
