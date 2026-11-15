-- Offline harness for RavenquillExpedition_Map: mocks the WoW API and HereBeDragons, loads the real core and then
-- Locale/Map/Pins/Sync, and asserts settings, notice, test-pin lifecycle, minimap rule, self pin, tooltips, clicks,
-- the core module (options, overview), deDE.
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
    NewTicker = function(t, fn)
      local tm = { at = clock + t, fn = fn, every = t }
      timers[#timers + 1] = tm
      return { Cancel = function() for i, x in ipairs(timers) do if x == tm then table.remove(timers, i) return end end end }
    end,
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
      SetParent = function(s, p) s.parent = p end,
      SetPoint = function(s, ...) s.point = { ... }; s.points = (s.points or 0) + 1 end,
      SetScale = function(s, v) s.scale = v end,
      SetAllPoints = function(s, o) s.allPoints = o end,
      GetWidth = function(s) return s.w or (s.allPoints and s.allPoints:GetWidth()) or 0 end,
      GetHeight = function(s) return s.h or (s.allPoints and s.allPoints:GetHeight()) or 0 end,
      GetFrameLevel = function(s) return s.level or 1 end,
      SetFrameLevel = function(s, l) s.level = l end,
      GetParent = function(s) return s.parent end,
      GetChildren = function(s)
        local out = {}
        for _, x in ipairs(frames) do if x.parent == s then out[#out + 1] = x end end
        return table.unpack(out)
      end,
      IsShown = function(s) return s.shown end,
    }
    -- unknown Methods are no-ops; unknown lowercase fields are nil, as on real frames
    return setmetatable(f, { __index = function(_, k) return methods[k] or (k:match("^%u") and function() end or nil) end })
  end
  env.CreateFrame = function(kind, _, parent)
    local f = NewFrame(kind); f.parent = parent; frames[#frames + 1] = f; return f
  end
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
  local hbdMini, hbdAdds, hbdWorldCalls = {}, 0, 0
  -- Maps: zone 1429 and its sibling 1411 on continent 1415, under the Azeroth map 947. World coordinates are the
  -- zone's x/y * 1000; zone 1429 covers x 0.4-0.6 / y 0.2-0.4 of the continent and x 0.5-0.6 / y 0.5-0.6 of Azeroth.
  local HBD = {
    GetPlayerZone = function() return ownPos and ownPos[1], 3 end,
    GetPlayerZonePosition = function() if ownPos then return ownPos[2] + 0.001, ownPos[3], ownPos[1], 3 end end,
    mapData = { [1429] = { parent = 1415, mapType = 3 }, [1411] = { parent = 1415, mapType = 3 },
      [1415] = { parent = 947, mapType = 2 } },
    GetWorldCoordinatesFromZone = function(_, x, y, mapID)
      if mapID ~= 1429 then return nil, nil, nil end
      return x * 1000, y * 1000, 0
    end,
    GetZoneCoordinatesFromWorldInstance = function(_, wx, wy, inst, mapID)
      if inst ~= 0 then return end
      if mapID == 1429 then return wx / 1000, wy / 1000 end
      if mapID == 1415 then return 0.4 + wx / 1000 * 0.2, 0.2 + wy / 1000 * 0.2 end
    end,
    GetAzerothWorldMapCoordinatesFromWorld = function(_, wx, wy, inst)
      if inst == 0 then return 0.5 + wx / 1000 * 0.1, 0.5 + wy / 1000 * 0.1 end
    end,
  }
  env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
  local function add(store)
    return function(_, ref, icon, mapID, x, y)
      assert(ref and type(icon) == "table" and type(mapID) == "number" and type(x) == "number" and type(y) == "number",
        "HBD would raise: bad args")
      if mapID == 999999 then return false end
      hbdAdds = hbdAdds + 1
      store[icon] = { mapID = mapID, x = x, y = y }
      icon.shown = true
      return true
    end
  end
  local Pins = {
    AddMinimapIconMap = add(hbdMini),
    -- HBD's world map API registers a data provider on WorldMapFrame (the taint, Pins.lua header): never used
    AddWorldMapIconMap = function() hbdWorldCalls = hbdWorldCalls + 1 end,
    AddWorldMapIconWorld = function() hbdWorldCalls = hbdWorldCalls + 1 end,
    RemoveWorldMapIcon = function() hbdWorldCalls = hbdWorldCalls + 1 end,
    RemoveAllWorldMapIcons = function() hbdWorldCalls = hbdWorldCalls + 1 end,
    RemoveMinimapIcon = function(_, _, icon) hbdMini[icon] = nil; icon.shown = false end,
  }
  env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
  env.LibStub = setmetatable({ minors = { ["HereBeDragons-2.0-RQE"] = 35, ["HereBeDragons-Pins-2.0-RQE"] = 17 } }, {
    __call = function(_, name) return name == "HereBeDragons-2.0-RQE" and HBD or Pins end })

  local map
  if opts.worldMap then
    local canvas = NewFrame("canvas")
    canvas.w, canvas.h = 1000, 700
    local calls = {}
    local allowed = {
      GetCanvas = function() return canvas end,
      GetMapID = function(s) return s.mapID end,
      GetCanvasScale = function(s) return s.scale end,
      IsShown = function(s) return s.shown end,
    }
    map = { canvas = canvas, mapID = 1429, scale = 1, shown = false, calls = calls, providers = {} }
    map.pinPools = setmetatable({}, { __newindex = function(t, k, v) calls[#calls + 1] = "pinPools." .. tostring(k); rawset(t, k, v) end })
    -- Blizzard's show path (ToggleWorldMap -> ShowUIPanel): every data provider's RefreshAllData, then the canvas
    -- children's OnShow scripts, all in one (secure) execution. Returns how often our code ran in it.
    function map.blizzardShow()
      map.shown, canvas.shown = true, true
      local ran = 0
      for provider in pairs(map.providers) do provider:RefreshAllData(true); ran = ran + 1 end
      for _, f in ipairs(frames) do
        local p = f.parent
        while p and p ~= canvas do p = p.parent end
        if p == canvas and f.scripts.OnShow then f.scripts.OnShow(f); ran = ran + 1 end
      end
      return ran
    end
    -- one rendered frame: OnUpdate of every visible frame on the canvas
    function map.renderFrame()
      if not map.shown then return end
      for _, f in ipairs(frames) do
        if f.parent == canvas and f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end
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
    env.WorldMapFrame = map
  end

  -- the real core first (the .toc requires it), as the game loads it
  local frames0 = #frames
  local coreDir = DIR .. "/../RavenquillExpedition"
  local coreNs = {}
  for _, file in ipairs(dofile(coreDir .. "/dev/toc.lua")(coreDir)) do
    assert(loadfile(coreDir .. "/" .. file, "t", env))("RavenquillExpedition", coreNs)
  end
  local RQ = env.RavenquillExpedition
  for i = frames0 + 1, #frames do
    local f = frames[i]
    if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "RavenquillExpedition") end
  end

  local ns = {}
  for _, file in ipairs({ "Locale.lua", "Map.lua", "Pins.lua", "Sync.lua" }) do
    local chunk = assert(loadfile(DIR .. "/" .. file, "t", env))
    chunk("RavenquillExpedition_Map", ns)
  end
  local M = ns.Map
  -- world pins: our own layer's (Pins.lua M.worldPlaced, [frame] = { mapID, x, y, ... })
  local hbdWorld = M.worldPlaced or {}
  local function fire(event, arg1)
    for _, f in ipairs(frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, arg1) end
    end
  end
  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

  return {
    env = env, ns = ns, M = M, mod = M.mod, RQ = RQ, L = ns.L, fire = fire, advance = advance, printed = printed, errors = errors,
    tip = tip, tells = tells, hbdWorld = hbdWorld, hbdMini = hbdMini, count = count,
    setPos = function(p) ownPos = p end, setDead = function(v) dead = v end, setTaxi = function(v) taxi = v end,
    -- the settings view in the /rq overview: set an option, read the diagnostics box
    set = function(id, v) local o = M.mod:Option(id); assert(o and o.set, "no option " .. id); o.set(v) end,
    diag = function() return table.concat(M.mod:Option("diag").lines(), "\n") end,
    adds = function() return hbdAdds end, hbdWorldCalls = function() return hbdWorldCalls end, map = map,
    frames = frames,
    -- world pin frames per member (one, however often it moved)
    maxCanvas = function()
      local per, m = {}, 0
      for f in pairs(hbdWorld) do per[f.key] = (per[f.key] or 0) + 1; m = math.max(m, per[f.key]) end
      return m
    end,
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
check(w.RQ:PlayerKey() == "Ängis Waldbach", "core PlayerKey = First Surname")

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
local mod1 = w.mod
local okShape = #mod1.options >= 10
for _, o in ipairs(mod1.options) do
  if type(o.label) ~= "string" or o.label == "" then okShape = false end
  if o.type == "toggle" and not (o.get and o.set) then okShape = false end
  if o.type == "range" and not (o.get and o.set and o.min and o.max and o.step) then okShape = false end
  if o.type == "text" and not o.lines then okShape = false end
end
check(okShape, "options: every entry has a label and its functions")
w.set("worldmap", false)
check(mod1:Option("names").disabled() == true, "names option greyed out while the world map is off")
w.set("worldmap", true)
check(mod1:Option("names").disabled() == false and mod1:Option("names").get() == true, "names option back")
check(w.env.SLASH_RAVENQUILLMAP1 == nil and w.env.SlashCmdList.RAVENQUILLMAP == nil, "the map registers no chat command")
check(#w.errors == 0 and not (w.env.RavenquillExpeditionDB or {}).lastError, "no Lua errors (" .. tostring(w.errors[1]) .. ")")

---------------------------------------------------------------------------
-- 4. The core module (overview row, options); German client
---------------------------------------------------------------------------
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
check(mod == wc.M.mod and mod.api == 2 and mod.db == wc.env.RavenquillExpeditionMapDB and mod.settings == wc.M.settings,
  "API 2 module: the core set up RavenquillExpeditionMapDB")
wc.set("selfPin", true)
check(wc.M.members["@self"] and wc.M.members["@self"].name == wc.RQ:PlayerKey(), "core helpers used (PlayerKey)")
wc.set("selfPin", false)
check(#mod.options >= 10 and mod.OnSlash == nil, "options handed to the core, no subcommands")
wc.set("fake", true)
check(wc.count(wc.M.members) == 7, "test dots via the option")
check(mod:OverviewStatus() == "On the map: 0 · sharing on", "overview: test pins don't count as guildmates ("
  .. tostring(mod:OverviewStatus()) .. ")")
wc.M.members["Hans Wurst"] = { key = "Hans Wurst", name = "Hans Wurst", mapID = 1429, x = 0.3, y = 0.3, level = 20,
  class = "MAGE", heard = wc.env.GetTime(), flags = {} }
local commState = wc.RQ.CommState
wc.RQ.CommState = function(self) local st = commState(self); st.slow = true; return st end -- the core's slow mode
local st = mod:OverviewStatus()
check(st:find("^On the map: 1 ") and st:find("getting through"), "overview: status counts guildmates, warns when slow")
wc.RQ.CommState = commState
wc.advance(10)
check(anyPrinted(wc, "Ravenquill Expedition|r |cffbbbbbbGuild Map"), "printing goes through the core (module title)")
check(#wc.errors == 0, "core run: no Lua errors")

-- the 2 s ticker runs only while there is something to do (sharing on, pins shown or held)
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
check(wd.mod:Option("share").label == "Meine Position mit der Gilde teilen" and wd.mod:Option("diag").label == "Diagnose",
  "German option labels")
check(anyPrinted(wd, "unter /rq", true) or anyPrinted(wd, "/rq|r", true), "German notice points to /rq")
check(#wd.errors == 0, "German client: no Lua errors")

---------------------------------------------------------------------------
-- 5. World map without taint (BugGrabber: ADDON_ACTION_BLOCKED 'Button:SetPassThroughButtons()' when the map
--    opens). Our code must not run inside Blizzard's map-show path: no data provider, no pin pool, no AcquirePin,
--    no hooks, no OnShow; the pins are drawn from our layer's own OnUpdate afterwards.
---------------------------------------------------------------------------
local wm = NewWorld({ worldMap = true })
local map = wm.map
wm.fire("ADDON_LOADED", "RavenquillExpedition_Map"); wm.fire("PLAYER_LOGIN")
wm.set("fake", true)
check(wm.count(wm.hbdWorld) == 7, "world map: 7 test pins placed")
check(wm.hbdWorldCalls() == 0, "world map: HBD's world map API (a WorldMapFrame data provider) is never called")
check(#map.calls == 0, "world map: only read methods on WorldMapFrame, nothing written (" .. tostring(map.calls[1]) .. ")")
check(next(map.providers) == nil, "world map: no data provider registered")
local lay = wm.M.worldLayer
check(lay and lay.parent == map.canvas and lay.allPoints == map.canvas, "world map: our layer is a child of the canvas")
check(lay and lay.scripts.OnShow == nil and lay.scripts.OnUpdate ~= nil, "world map: layer draws on OnUpdate, has no OnShow")
local onShow = 0
for f in pairs(wm.hbdWorld) do
  if f.parent ~= lay then onShow = onShow + 100 end
  if f.scripts.OnShow then onShow = onShow + 1 end
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
wm.advance(20) -- test pins move
local d2 = wm.hbdWorld[p1]
map.renderFrame()
check(d2 and d2.x ~= x0w and math.abs(p1.point[4] - d2.x * 1000) < 1e-6, "world map: a moved pin is redrawn")
check(wm.maxCanvas() == 1, "world map: still one pin per member after moves")
wm.set("worldmap", false)
check(wm.count(wm.hbdWorld) == 0 and not p1.shown, "world map: option off hides our pins")
check(#map.calls == 0 and wm.hbdWorldCalls() == 0, "world map: still nothing written to WorldMapFrame")
check(#wm.errors == 0, "world map: no Lua errors (" .. tostring(wm.errors[1]) .. ")")

-- in combat the overview doesn't open the map from addon code: that would run the whole show path tainted
local toggles = 0
wm.env.ToggleWorldMap = function() toggles = toggles + 1 end
wm.env.InCombatLockdown = function() return true end
wm.M:OpenMap()
check(toggles == 0 and anyPrinted(wm, "after combat"), "overview: no map opening from addon code in combat")
wm.env.InCombatLockdown = function() return false end
wm.M:OpenMap()
check(toggles == 1, "overview: opens the map out of combat")

---------------------------------------------------------------------------
-- 6. The embedded HereBeDragons-Pins (libs, modified: NOTICE.txt) registers nothing on WorldMapFrame until an
--    addon adds a world map icon; we only use its minimap part.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Private library names (in-game ADDON_ACTION_BLOCKED, 2026-11-15): RXPGuides and others share the LibStub copy named
-- "HereBeDragons-Pins-2.0"; when our code called into it, its world-map provider read state we had written and
-- Blizzard blamed Map. Our copies must only ever be reached under their private names.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Draw order on the world map (in game 2026-11-15: pins "visible" but drawn under the map art): our layer goes
-- above the highest frame on the canvas, also when Blizzard adds a higher one while the map is open.
---------------------------------------------------------------------------
do
  local wo = NewWorld({ worldMap = true })
  wo.fire("ADDON_LOADED", "RavenquillExpedition_Map")
  wo.fire("PLAYER_LOGIN")
  local art = wo.env.CreateFrame("Frame", nil, wo.map.canvas) -- Blizzard's map art / pins
  art.level = 800
  wo.M:Fake(true)
  wo.advance(3)
  wo.map.blizzardShow()
  wo.map.renderFrame()
  local layer = wo.M.worldLayer
  local pinsAbove = true
  for f in pairs(wo.M.worldPlaced) do if (f.level or 0) <= 800 then pinsAbove = false end end
  check(layer and layer.level and layer.level > 800 and pinsAbove, "our layer and pins sit above the map's highest frame (level 800)")
  local later = wo.env.CreateFrame("Frame", nil, wo.map.canvas) -- a pin Blizzard adds while the map is open
  later.level = 2000
  for _ = 1, 40 do wo.map.renderFrame() end -- 40 frames x 0.016 s > the 0.5 s check
  check(layer.level > 2000, "a higher frame added while the map is open: the layer moves above it (" .. tostring(layer.level) .. ")")
end

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
