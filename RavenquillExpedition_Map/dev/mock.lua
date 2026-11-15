-- WoW API mock for the RavenquillExpedition_Map harnesses: one shared clock and GUILD channel ("bus") for many
-- virtual clients ("worlds"), each loading the addon files into its own environment.
-- HereBeDragons is mocked (records placements); real map math is only testable in game.
local Mock = {}

function Mock.Scheduler()
  local s = { t = 0, timers = {} }
  function s:at(t, fn, every) self.timers[#self.timers + 1] = { at = t, fn = fn, every = every } end
  function s:advance(sec)
    local target = self.t + sec
    while true do
      local best, idx
      for i, tm in ipairs(self.timers) do
        if tm.at <= target and (not best or tm.at < best) then best, idx = tm.at, i end
      end
      if not idx then break end
      local tm = self.timers[idx]
      self.t = tm.at
      if tm.every then tm.at = tm.at + tm.every else table.remove(self.timers, idx) end
      tm.fn()
    end
    self.t = target
  end
  return s
end

-- The guild channel: delivers each GUILD addon message to every world (sender included = echo) after latency.
function Mock.Bus(sched)
  local b = { sched = sched, worlds = {}, log = {}, latency = 1, roster = {} }
  function b.drop(sender, prefix, msg) return false end
  function b:send(world, prefix, msg, chat)
    self.log[#self.log + 1] = { t = self.sched.t, sender = world.name, prefix = prefix, msg = msg, chat = chat }
    if chat ~= "GUILD" or not world.guild or self.drop(world.name, prefix, msg) then return end
    self.sched:at(self.sched.t + self.latency, function()
      for _, w in ipairs(self.worlds) do
        if w.guild == world.guild and w.prefixes[prefix] then w.fire("CHAT_MSG_ADDON", prefix, msg, "GUILD", world.name) end
      end
    end)
  end
  function b:member(name, class, level, online)
    self.roster[#self.roster + 1] = { name = name, class = class, level = level, online = online ~= false }
  end
  function b:setOnline(name, online)
    for _, r in ipairs(self.roster) do if r.name == name then r.online = online end end
  end
  -- map messages (P/L) sent, optionally only from one sender, within [t0, t1)
  function b:count(t0, t1, sender, kind)
    local n = 0
    for _, e in ipairs(self.log) do
      if e.prefix == "RQEMap1" and e.t >= t0 and e.t < t1 and (not sender or e.sender == sender)
        and (not kind or e.msg:sub(1, 1) == kind) then n = n + 1 end
    end
    return n
  end
  return b
end

local function NewFrameFactory(world)
  local function NewFrame()
    local f = { shown = true, alpha = 1, scripts = {}, events = {} }
    local methods = {
      Hide = function(s) s.shown = false end, Show = function(s) s.shown = true end,
      SetAlpha = function(s, a) s.alpha = a end, SetScript = function(s, k, fn) s.scripts[k] = fn end,
      RegisterEvent = function(s, e) s.events[e] = true end,
      SetSize = function(s, w, h) s.w, s.h = w, h end,
      SetText = function(s, t) s.text = t end,
      SetVertexColor = function(s, r, g, b, a) s.color = { r, g, b, a } end,
      CreateTexture = function() return NewFrame() end,
      CreateFontString = function() return NewFrame() end,
      GetZoom = function() return 2 end,
    }
    -- real frame methods we call (or HBD calls) are no-ops; any other method name is a bug -> error.
    -- Unknown lowercase fields are nil, as on real frames.
    local noop = { SetPoint = true, ClearAllPoints = true, SetParent = true, EnableMouse = true, RegisterForClicks = true,
      SetTexture = true, SetTextColor = true, SetFrameLevel = true, SetFrameStrata = true, UnregisterEvent = true }
    return setmetatable(f, { __index = function(_, k)
      if methods[k] then return methods[k] end
      if noop[k] then return function() end end
      if type(k) == "string" and k:match("^%u") then error("mock: unknown frame method " .. k, 2) end
      return nil
    end })
  end
  return NewFrame
end

-- opts: sched, bus, name ("First Surname"), class, level, locale, core (bool), pos {mapID, x, y}, guild, dir
function Mock.NewWorld(opts)
  local sched = opts.sched or Mock.Scheduler()
  local bus = opts.bus
  local world = { name = opts.name or "Ängis Waldbach", guild = opts.guild, prefixes = {}, printed = {}, errors = {},
    tells = {}, frames = {}, hbdWorld = {}, hbdMini = {}, pos = opts.pos or { 1429, 0.5, 0.5 },
    dead = false, taxi = false, combat = false, instance = false }
  if bus and world.guild == nil then world.guild = "Testgilde" end
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.unpack = table.unpack or unpack
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
  env.GetTime = function() return sched.t end
  env.time = function() return 1763100000 + math.floor(sched.t) end
  env.GetServerTime = env.time
  env.C_Timer = {
    After = function(t, fn) sched:at(sched.t + t, fn) end,
    NewTicker = function(t, fn) sched:at(sched.t + t, fn, t) end,
  }
  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    world.printed[#world.printed + 1] = { t = sched.t, text = table.concat(t, " ") }
  end
  env.geterrorhandler = function() return function(msg) world.errors[#world.errors + 1] = msg end end
  env.debugstack = function() return "" end
  env.GetBuildInfo = function() return "1.60.1", "99999", "Nov 2026", 16001 end
  env.GetLocale = function() return opts.locale or "enUS" end
  env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CLASSIC = 15, 15, 1, 2
  env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
  env.UNKNOWNOBJECT = "Unknown"
  env.Ambiguate = function(n) return n end
  env.GetNormalizedRealmName = function() return "Realm" end
  env.GetRealmName = function() return "Realm" end
  local first, surname = world.name:match("^(%S+) (.+)$")
  env.UnitName = function() return first or world.name, surname end
  env.UnitNameUnmodified = env.UnitName
  env.UnitClass = function() return "x", opts.class or "SHAMAN" end
  env.UnitLevel = function() return opts.level or 33 end
  env.GetMaxPlayerLevel = function() return 60 end
  env.UnitIsDeadOrGhost = function() return world.dead end
  env.UnitOnTaxi = function() return world.taxi end
  env.InCombatLockdown = function() return world.combat end
  env.IsInInstance = function() return world.instance end
  env.IsIndoors = function() return false end
  env.IsInGuild = function() return world.guild ~= nil end
  env.GetGuildInfo = function() return world.guild end
  env.C_CVar = { GetCVar = function() return "0" end }
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0 } end })
  env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k:lower() end })
  env.C_Map = {
    GetBestMapForUnit = function() if world.pos then return world.pos[1] end end,
    GetPlayerMapPosition = function()
      local p = world.pos
      if not p then return nil end
      return { GetXY = function() return p[2], p[3] end }
    end,
    GetMapInfo = function(id) if id ~= 999999 then return { name = "Map" .. id } end end,
  }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) world.prefixes[p] = true; return 0 end,
    SendAddonMessage = function(prefix, msg, chat)
      assert(type(msg) == "string" and #msg <= 255, "message too long")
      if world.throttle then return 3 end
      if bus then bus:send(world, prefix, msg, chat) end
      return 0
    end,
  }
  env.hooksecurefunc = function(tbl, key, fn)
    local orig = tbl[key]
    tbl[key] = function(...)
      local r = table.pack(orig(...))
      fn(...)
      return table.unpack(r, 1, r.n)
    end
  end
  env.C_GuildInfo = {
    GuildRoster = function()
      world.rosterRequests = (world.rosterRequests or 0) + 1
      sched:at(sched.t + 1, function() world.fire("GUILD_ROSTER_UPDATE") end)
    end,
  }
  env.GetNumGuildMembers = function() return bus and #bus.roster or 0 end
  env.GetGuildRosterInfo = function(i)
    local r = bus and bus.roster[i]
    if not r then return end
    return r.name, "Member", 1, r.level, r.class, "Zone", "", "", r.online, 0, r.class
  end

  local NewFrame = NewFrameFactory(world)
  env.CreateFrame = function() local f = NewFrame(); world.frames[#world.frames + 1] = f; return f end
  env.UIParent, env.Minimap = NewFrame(), NewFrame()
  local tip = { lines = {} }
  world.tip = tip
  env.GameTooltip = setmetatable(tip, { __index = function(_, k)
    if k == "AddLine" then return function(_, t) tip.lines[#tip.lines + 1] = t end end
    if k == "SetOwner" then return function() tip.lines = {} end end
    return function() end
  end })
  env.ChatFrameUtil = { SendTell = function(n) world.tells[#world.tells + 1] = n end }
  env.SlashCmdList = {}

  -- HereBeDragons mock
  local HBD = {
    GetPlayerZone = function() return world.pos and world.pos[1], 3 end,
    GetPlayerZonePosition = function() local p = world.pos; if p then return p[2] + 0.001, p[3], p[1], 3 end end,
  }
  world.canvas = {} -- [icon] = canvas pins acquired for it on the (open) world map
  local function add(store, isWorld)
    return function(_, ref, icon, mapID, x, y)
      assert(ref and type(icon) == "table" and type(mapID) == "number" and type(x) == "number" and type(y) == "number",
        "HBD would raise: bad args")
      if mapID == 999999 then return false end
      store[icon] = { mapID = mapID, x = x, y = y }
      if isWorld then world.canvas[icon] = (world.canvas[icon] or 0) + 1 end
      icon.shown = true
      return true
    end
  end
  function world.maxCanvas()
    local m = 0
    for _, n in pairs(world.canvas) do m = math.max(m, n) end
    return m
  end
  local Pins = {
    AddWorldMapIconMap = add(world.hbdWorld, true), AddMinimapIconMap = add(world.hbdMini),
    RemoveWorldMapIcon = function(_, _, icon) world.hbdWorld[icon] = nil; world.canvas[icon] = nil end,
    RemoveMinimapIcon = function(_, _, icon) world.hbdMini[icon] = nil; icon.shown = false end,
  }
  env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
  env.LibStub = setmetatable({ minors = { ["HereBeDragons-2.0"] = 35, ["HereBeDragons-Pins-2.0"] = 17 } }, {
    __call = function(_, name) return name == "HereBeDragons-2.0" and HBD or Pins end })

  if opts.core then
    local core = { version = "0.2.0", modules = {}, roster = {} }
    core.SafeCall = function(fn, ...) if type(fn) ~= "function" then return end
      local r = table.pack(pcall(fn, ...)); if r[1] then return table.unpack(r, 2, r.n) end end
    core.IsSecret = function() return false end
    core.Print = function(tag, ...) env.print("[core]", tag, ...) end
    function core:Now() return env.time() end
    function core:PlayerKey() return world.name end
    function core:NewModule(name, mod) mod.name = name; self.modules[name] = mod; return mod end
    env.RavenquillExpedition = core
  end

  if opts.realCore then
    env.Enum = env.Enum or {}
    local coreNs = {}
    world.coreName = "RavenquillExpedition"
    for _, file in ipairs({ "Core.lua", "Comm.lua" }) do
      local chunk = assert(loadfile(opts.dir .. "/../" .. world.coreName .. "/" .. file, "t", env))
      chunk(world.coreName, coreNs)
    end
  end

  world.env, world.sched, world.bus = env, sched, bus
  world.ns = {}
  for _, file in ipairs(opts.files or { "Locale.lua", "Map.lua", "Pins.lua", "Sync.lua" }) do
    local chunk = assert(loadfile(opts.dir .. "/" .. file, "t", env))
    chunk("RavenquillExpedition_Map", world.ns)
  end
  world.M, world.L = world.ns.Map, world.ns.L
  function world.fire(event, ...)
    for _, f in ipairs(world.frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
  end
  -- the settings view in the /rq overview: set an option, read the diagnostics box
  function world.set(id, v)
    local o = world.M:Option(id)
    assert(o and o.set, "no option " .. tostring(id))
    o.set(v)
  end
  function world.diag() return table.concat(world.M:Option("diag").lines(), "\n") end
  function world.login()
    if opts.realCore then world.fire("ADDON_LOADED", world.coreName) end
    world.fire("ADDON_LOADED", "RavenquillExpedition_Map")
    world.fire("PLAYER_LOGIN")
    world.fire("PLAYER_ENTERING_WORLD")
  end
  function world.printedMatch(needle)
    for _, line in ipairs(world.printed) do if line.text:find(needle, 1, true) then return line end end
  end
  if bus then bus.worlds[#bus.worlds + 1] = world end
  return world
end

return Mock
