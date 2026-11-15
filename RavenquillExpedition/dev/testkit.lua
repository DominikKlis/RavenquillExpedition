-- Shared test kit for multi-client tests: one virtual clock, one GUILD channel ("bus") with echo and latency, and any
-- number of clients, each loading the REAL core plus the addons you name (through their .toc) into its own Lua
-- environment. Generalised from RavenquillExpedition_Map/dev/mock.lua.
--
--   local Kit = dofile(<AddOns>/RavenquillExpedition/dev/testkit.lua)
--   local sched, bus = Kit.Setup()
--   local a = Kit.Client(sched, bus, "Anna Stone", { addons = { "RavenquillExpedition_Highlights" } })
--   a.login(); sched:advance(60)
--   Kit.check(cond, "label"); Kit.section("name"); Kit.skip("name", "reason"); Kit.finish()
--
-- Client options: addons (folder names, loaded after the core), files ({ path, addonName } extra files),
--   class, level, locale, guild ("Testgilde"; false = no guild), realm, setup = fn(env, client) (extra API before
--   loading), noCore = true (old-version clients that bring their own code).
-- Client fields: env, name, fire(event, ...), login(), module(name), RQ, printed, errors, sent (its own sends),
--   instance / combat / dead / throttle flags the API reads.
-- Bus: bus.log = { { t, sender, prefix, msg, chat } }, bus.latency (s), bus.drop(sender, prefix, msg) -> true drops,
--   bus:member(name, class, level, online), bus:count(fn), bus:maxPer(seconds, sender, prefixes).
local Kit = {}
local ADDONS = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "")) .. "../../"
local TocFiles = dofile(ADDONS .. "RavenquillExpedition/dev/toc.lua")
Kit.ADDONS = ADDONS

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local pass, fail, skips = 0, 0, 0
function Kit.check(cond, label)
  if cond then pass = pass + 1; io.write("  ok   ", label, "\n") else fail = fail + 1; io.write("  FAIL ", label, "\n") end
  return cond
end
function Kit.section(name) io.write("== ", name, "\n") end
function Kit.skip(name, reason) skips = skips + 1; io.write("SKIP ", name, ": ", reason, "\n") end
function Kit.finish()
  io.write(("%d passed, %d failed, %d skipped\n"):format(pass, fail, skips))
  os.exit(fail == 0 and 0 or 1)
end

-- loadfile with an environment, on Lua 5.1 (setfenv) and 5.2+
function Kit.loadchunk(path, env)
  if setfenv then
    local f = assert(loadfile(path))
    setfenv(f, env)
    return f
  end
  return assert(loadfile(path, "t", env))
end

---------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------
function Kit.Scheduler()
  local s = { t = 0, timers = {}, seq = 0 }
  function s:at(t, fn, every)
    self.seq = self.seq + 1
    self.timers[#self.timers + 1] = { at = t, fn = fn, every = every, seq = self.seq }
  end
  function s:advance(sec)
    local target = self.t + sec
    while true do
      local best, idx
      for i, tm in ipairs(self.timers) do
        if tm.at <= target and (not best or tm.at < best.at or (tm.at == best.at and tm.seq < best.seq)) then best, idx = tm, i end
      end
      if not idx then break end
      self.t = best.at
      if best.every then best.at = best.at + best.every else table.remove(self.timers, idx) end
      best.fn()
    end
    self.t = target
  end
  return s
end

---------------------------------------------------------------------------
-- Guild channel
---------------------------------------------------------------------------
function Kit.Bus(sched)
  local b = { sched = sched, clients = {}, log = {}, latency = 1, roster = {} }
  function b.drop() return false end
  function b:send(client, prefix, msg, chat)
    self.log[#self.log + 1] = { t = self.sched.t, sender = client.name, prefix = prefix, msg = msg, chat = chat }
    if chat ~= "GUILD" or not client.guild or self.drop(client.name, prefix, msg) then return end
    self.sched:at(self.sched.t + self.latency, function()
      for _, c in ipairs(self.clients) do
        if c.online and c.guild == client.guild and c.prefixes[prefix] then
          c.fire("CHAT_MSG_ADDON", prefix, msg, "GUILD", client.name .. "-" .. (client.realm or "Realm"))
        end
      end
    end)
  end
  function b:member(name, class, level, online)
    for _, r in ipairs(self.roster) do if r.name == name then return end end
    self.roster[#self.roster + 1] = { name = name, class = class, level = level, online = online ~= false }
  end
  function b:count(pred)
    local n = 0
    for _, e in ipairs(self.log) do if pred(e) then n = n + 1 end end
    return n
  end
  -- the most GUILD messages `sender` sent within any window of `seconds` (only `prefixes` when given)
  function b:maxPer(seconds, sender, prefixes)
    local times = {}
    for _, e in ipairs(self.log) do
      if e.chat == "GUILD" and e.sender == sender and (not prefixes or prefixes[e.prefix]) then times[#times + 1] = e.t end
    end
    local best = 0
    for i = 1, #times do
      local n = 0
      for j = i, #times do if times[j] - times[i] < seconds then n = n + 1 end end
      if n > best then best = n end
    end
    return best
  end
  return b
end

function Kit.Setup()
  local sched = Kit.Scheduler()
  return sched, Kit.Bus(sched)
end

---------------------------------------------------------------------------
-- Frames: methods we know are recorded; any other method is a no-op (permissive), like the game for our purposes.
---------------------------------------------------------------------------
local function NewFrameFactory(client)
  local function obj()
    local f = { _shown = false, _scripts = {}, _events = {} }
    return setmetatable(f, { __index = function(_, k)
      if type(k) ~= "string" or not k:match("^%u") then return nil end
      if k == "SetScript" then return function(s, ev, fn) s._scripts[ev] = fn end end
      if k == "GetScript" then return function(s, ev) return s._scripts[ev] end end
      if k == "HookScript" then return function(s, ev, fn)
        local old = s._scripts[ev]
        s._scripts[ev] = function(...) if old then old(...) end fn(...) end
      end end
      if k == "RegisterEvent" then return function(s, ev) s._events[ev] = true end end
      if k == "UnregisterEvent" then return function(s, ev) s._events[ev] = nil end end
      if k == "UnregisterAllEvents" then return function(s) s._events = {} end end
      if k == "IsShown" or k == "IsVisible" then return function(s) return s._shown end end
      if k == "Show" then return function(s) local was = s._shown; s._shown = true; if not was and s._scripts.OnShow then s._scripts.OnShow(s) end end end
      if k == "Hide" then return function(s) local was = s._shown; s._shown = false; if was and s._scripts.OnHide then s._scripts.OnHide(s) end end end
      if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
      if k == "SetText" then return function(s, v) s._text = v end end
      if k == "GetText" then return function(s) return s._text end end
      if k == "SetChecked" then return function(s, v) s._checked = v and true or false end end
      if k == "GetChecked" then return function(s) return s._checked end end
      if k == "CreateFontString" or k == "CreateTexture" then return function() return obj() end end
      if k:match("^Get") or k:match("^Is") then return function() return nil end end
      return function() end
    end })
  end
  return obj
end

---------------------------------------------------------------------------
-- A client
---------------------------------------------------------------------------
function Kit.Client(sched, bus, name, opts)
  opts = opts or {}
  local c = { name = name, online = true, guild = opts.guild == nil and "Testgilde" or opts.guild or nil,
    realm = opts.realm or "Realm", prefixes = {}, printed = {}, errors = {}, sent = {}, frames = {},
    instance = false, combat = false, dead = false, throttle = false, sched = sched, bus = bus }
  if bus then bus:member(name, opts.class or "SHAMAN", opts.level or 33) end
  local env = setmetatable({}, { __index = _G })
  env._G = env
  c.env = env
  env.unpack = table.unpack or unpack
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
  env.tinsert, env.tremove = table.insert, table.remove
  env.strsplit = function(sep, s)
    local out, pos = {}, 1
    while true do
      local i = s:find(sep, pos, true)
      if not i then out[#out + 1] = s:sub(pos) break end
      out[#out + 1] = s:sub(pos, i - 1); pos = i + 1
    end
    return env.unpack(out)
  end
  env.math = setmetatable({ random = opts.random or math.random }, { __index = math })
  env.GetTime = function() return sched.t end
  env.time = function() return 1763100000 + math.floor(sched.t) end
  env.GetServerTime = env.time
  env.date = os.date
  env.C_Timer = {
    After = function(t, fn) sched:at(sched.t + t, function() if c.online then fn() end end) end,
    NewTicker = function(t, fn) sched:at(sched.t + t, function() if c.online then fn() end end, t) end,
  }
  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    c.printed[#c.printed + 1] = { t = sched.t, text = table.concat(t, " ") }
  end
  env.geterrorhandler = function() return function(msg) c.errors[#c.errors + 1] = msg end end
  env.debugstack = function() return "" end
  env.GetBuildInfo = function() return "1.60.1", "70938", "Nov 2026", 16001 end
  env.GetLocale = function() return opts.locale or "enUS" end
  env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
  env.UNKNOWNOBJECT = "Unknown"
  env.Ambiguate = function(n) return n end
  env.GetNormalizedRealmName = function() return c.realm end
  env.GetRealmName = function() return c.realm end
  local first, surname = name:match("^(%S+) (.+)$")
  env.UnitName = function(u) if u == "player" then return first or name, surname end end
  env.UnitNameUnmodified = env.UnitName
  env.UnitClass = function(u) if u == "player" then return "x", opts.class or "SHAMAN" end end
  env.UnitLevel = function(u) if u == "player" then return opts.level or 33 end end
  env.GetMaxPlayerLevel = function() return 60 end
  env.UnitIsDeadOrGhost = function() return c.dead end
  env.InCombatLockdown = function() return c.combat end
  env.IsInInstance = function() return c.instance, c.instance and "party" or "none" end
  env.IsInGuild = function() return c.guild ~= nil end
  env.GetGuildInfo = function() return c.guild end
  env.GetNumGroupMembers = function() return 0 end
  env.IsInRaid = function() return false end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) c.prefixes[p] = true; return 0 end,
    SendAddonMessage = function(prefix, msg, chat)
      assert(type(msg) == "string" and #msg <= 255, "message over 255 bytes")
      if c.throttle then return 3 end
      c.sent[#c.sent + 1] = { t = sched.t, prefix = prefix, msg = msg, chat = chat }
      if bus then bus:send(c, prefix, msg, chat) end
      return 0
    end,
  }
  env.hooksecurefunc = function(tbl, key, fn)
    if type(tbl) == "string" then tbl, key, fn = env, tbl, key end
    local orig = tbl[key]
    tbl[key] = function(...)
      local r = { n = select("#", ...), orig(...) }
      fn(...)
      return env.unpack(r, 1, #r)
    end
  end
  env.C_GuildInfo = { GuildRoster = function() sched:at(sched.t + 1, function() if c.online then c.fire("GUILD_ROSTER_UPDATE") end end) end }
  env.GetNumGuildMembers = function() return bus and #bus.roster or 0 end
  env.GetGuildRosterInfo = function(i)
    local r = bus and bus.roster[i]
    if not r then return end
    return r.name .. "-" .. c.realm, "Member", 1, r.level, r.class, "Zone", "", "", r.online, 0, r.class
  end
  env.C_AddOns = { GetAddOnMetadata = function() return "dev" end, IsAddOnLoaded = function() return true end,
    GetAddOnInfo = function(n) return n, n, "", true, nil end }
  env.SlashCmdList = {}
  env.UISpecialFrames = {}
  local NewFrame = NewFrameFactory(c)
  env.CreateFrame = function() local f = NewFrame(); c.frames[#c.frames + 1] = f; return f end
  env.UIParent, env.GameTooltip, env.Minimap = NewFrame(), NewFrame(), NewFrame()
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) c.printed[#c.printed + 1] = { t = sched.t, text = tostring(text) } end }

  function c.fire(event, ...)
    for _, f in ipairs(c.frames) do
      if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
  end
  if opts.setup then opts.setup(env, c) end

  c.addons = {}
  local function loadAddon(addon)
    local ns = {}
    for _, f in ipairs(TocFiles(ADDONS .. addon)) do Kit.loadchunk(ADDONS .. addon .. "/" .. f, env)(addon, ns) end
    c.addons[#c.addons + 1] = addon
    return ns
  end
  if not opts.noCore then c.coreNs = loadAddon("RavenquillExpedition") end
  c.ns = {}
  for _, addon in ipairs(opts.addons or {}) do c.ns[addon] = loadAddon(addon) end
  for _, f in ipairs(opts.files or {}) do
    local ns = c.ns[f[2]] or {}
    c.ns[f[2]] = ns
    Kit.loadchunk(f[1], env)(f[2], ns)
    local seen = false
    for _, a in ipairs(c.addons) do if a == f[2] then seen = true end end
    if not seen then c.addons[#c.addons + 1] = f[2] end
  end
  c.RQ = env.RavenquillExpedition
  function c.module(n) return c.RQ and c.RQ:GetModule(n) end
  function c.login()
    for _, a in ipairs(c.addons) do c.fire("ADDON_LOADED", a) end
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD", true, false)
    c.fire("GUILD_ROSTER_UPDATE")
  end
  function c.printedMatch(needle)
    for _, line in ipairs(c.printed) do if line.text:find(needle, 1, true) then return line end end
  end
  if bus then bus.clients[#bus.clients + 1] = c end
  return c
end

-- A fixed random generator (same jitter on every run and every Lua version).
function Kit.Random(seed)
  local s = seed or 12345
  return function(a, b)
    s = (s * 1103515245 + 12345) % 2147483648
    local r = s / 2147483648
    if a == nil then return r end
    if b == nil then a, b = 1, a end
    return a + math.floor(r * (b - a + 1))
  end
end

return Kit
