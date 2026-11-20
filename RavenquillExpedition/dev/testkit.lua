local Kit = {}
local ADDONS = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "")) .. "../../"
local TocFiles = dofile(ADDONS .. "RavenquillExpedition/dev/toc.lua")
Kit.ADDONS = ADDONS

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

function Kit.loadchunk(path, env)
  if setfenv then
    local f = assert(loadfile(path))
    setfenv(f, env)
    return f
  end
  return assert(loadfile(path, "t", env))
end

function Kit.Scheduler(opts)
  opts = opts or {}
  local s = { t = opts.start or 0, timers = {}, seq = 0 }
  local function run(tm)
    if not opts.trap then return tm.fn() end
    local ok, err = pcall(tm.fn)
    if not ok then Kit.check(false, "timer error: " .. tostring(err)) end
  end
  function s:at(t, fn, every)
    self.seq = self.seq + 1
    local tm = { at = t, fn = fn, every = every, seq = self.seq }
    self.timers[#self.timers + 1] = tm
    return { Cancel = function()
      for i, x in ipairs(self.timers) do if x == tm then table.remove(self.timers, i) return end end
    end }
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
      run(best)
    end
    self.t = target
  end
  function s:flush(limit)
    local n = 0
    while self.timers[1] and n < limit do
      run(table.remove(self.timers, 1))
      n = n + 1
    end
  end
  return s
end

function Kit.Bus(sched)
  local b = { sched = sched, clients = {}, log = {}, latency = 1, roster = {} }
  function b.drop() return false end
  function b:send(client, prefix, msg, chat)
    self.log[#self.log + 1] = { t = self.sched.t, sender = client.name, prefix = prefix, msg = msg, chat = chat }
    if chat ~= "GUILD" or not client.guild then return end
    local lost = {}
    for _, c in ipairs(self.clients) do lost[c] = self.drop(client.name, prefix, msg, c) end
    self.sched:at(self.sched.t + self.latency, function()
      for _, c in ipairs(self.clients) do
        if c.online and c.guild == client.guild and c.prefixes[prefix] and not lost[c] then
          c.fire("CHAT_MSG_ADDON", prefix, msg, "GUILD", client.name .. "-" .. (client.realm or "Realm"))
        end
      end
    end)
  end
  function b:member(name, class, level, online)
    for _, r in ipairs(self.roster) do if r.name == name then return end end
    self.roster[#self.roster + 1] = { name = name, class = class, level = level, online = online ~= false }
  end
  function b:setOnline(name, online)
    for _, r in ipairs(self.roster) do if r.name == name then r.online = online end end
  end
  function b:count(pred)
    local n = 0
    for _, e in ipairs(self.log) do if pred(e) then n = n + 1 end end
    return n
  end
  function b:sentBy(who, pred)
    local out = {}
    for _, e in ipairs(self.log) do if e.sender == who and (not pred or pred(e)) then out[#out + 1] = e end end
    return out
  end
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

function Kit.Two(opts)
  local sched, bus = Kit.Setup()
  local a = Kit.Client(sched, bus, "Anna Stone", opts and opts.a)
  local b = Kit.Client(sched, bus, "Bert Hill", opts and opts.b)
  a.login(); b.login()
  sched:advance(5)
  return sched, bus, a, b
end

function Kit.strsplit(sep, s)
  local out, pos = {}, 1
  while true do
    local i = s:find(sep, pos, true)
    if not i then out[#out + 1] = s:sub(pos) break end
    out[#out + 1] = s:sub(pos, i - 1); pos = i + 1
  end
  return (table.unpack or unpack)(out)
end

local FrameMethods = {}
function FrameMethods.SetScript(s, ev, fn) s._scripts[ev] = fn end
function FrameMethods.GetScript(s, ev) return s._scripts[ev] end
function FrameMethods.HookScript(s, ev, fn)
  local old = s._scripts[ev]
  s._scripts[ev] = function(...) if old then old(...) end fn(...) end
end
function FrameMethods.RegisterEvent(s, ev) s._events[ev] = true end
function FrameMethods.UnregisterEvent(s, ev) s._events[ev] = nil end
function FrameMethods.UnregisterAllEvents(s) s._events = {} end
function FrameMethods.IsShown(s) return s._shown end
FrameMethods.IsVisible = FrameMethods.IsShown
function FrameMethods.Show(s) local was = s._shown; s._shown = true; if not was and s._scripts.OnShow then s._scripts.OnShow(s) end end
function FrameMethods.Hide(s) local was = s._shown; s._shown = false; if was and s._scripts.OnHide then s._scripts.OnHide(s) end end
function FrameMethods.SetShown(s, v) if v then s:Show() else s:Hide() end end
function FrameMethods.SetText(s, v) s._text = v end
function FrameMethods.SetAlpha(s, v) s._alpha = v end
function FrameMethods.GetAlpha(s) return s._alpha or 1 end
function FrameMethods.GetText(s) return s._text end
function FrameMethods.SetChecked(s, v) s._checked = v and true or false end
function FrameMethods.GetChecked(s) return s._checked end
function FrameMethods.GetName(s) return s._name end
function FrameMethods.GetObjectType(s) return s._type end
function FrameMethods.GetParent(s) return s._parent end
function FrameMethods.GetChildren(s) return (table.unpack or unpack)(s._children) end
Kit.FrameMethods = FrameMethods

local function NewFrameFactory(c)
  local function obj(otype, name, parent)
    local f = { _type = otype or "Frame", _name = name, _parent = parent, _children = {}, _shown = false, _scripts = {},
      _events = {} }
    if parent then parent._children[#parent._children + 1] = f end
    if name then c.env[name] = f end
    return setmetatable(f, { __index = function(_, k)
      if type(k) ~= "string" or not k:match("^%u") then return nil end
      local m = c.frameMethods[k] or FrameMethods[k]
      if m then return m end
      if k == "CreateFontString" or k == "CreateTexture" then return function() return obj() end end
      if k:match("^Get") or k:match("^Is") then return function() return nil end end
      return function() end
    end })
  end
  return obj
end

local function InstallEngine(env, c, sched, opts)
  local epoch = opts.epoch or 1763100000
  env.unpack = table.unpack or unpack
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
  env.tinsert, env.tremove = table.insert, table.remove
  env.strsplit = Kit.strsplit
  env.math = setmetatable({ random = opts.random or math.random }, { __index = math })
  env.GetTime = function() return sched.t end
  env.time = function() return epoch + math.floor(sched.t) end
  env.GetServerTime = env.time
  env.date = os.date
  env.C_Timer = {
    After = function(t, fn) sched:at(sched.t + t, function() if c.online then fn() end end) end,
    NewTicker = function(t, fn) return sched:at(sched.t + t, function() if c.online then fn() end end, t) end,
  }
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) c.printed[#c.printed + 1] = { t = sched.t, text = tostring(text) } end }
  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    env.DEFAULT_CHAT_FRAME:AddMessage(table.concat(t, " "))
  end
  env.geterrorhandler = function() return function(msg) c.errors[#c.errors + 1] = msg end end
  env.debugstack = function() return "" end
  env.hooksecurefunc = function(tbl, key, fn)
    if type(tbl) == "string" then tbl, key, fn = env, tbl, key end
    local orig = tbl[key]
    tbl[key] = function(...)
      local r = { n = select("#", ...), orig(...) }
      fn(...)
      return env.unpack(r, 1, #r)
    end
  end
  env.SlashCmdList = {}
  env.UISpecialFrames = {}
  local NewFrame = NewFrameFactory(c)
  c.newFrame = NewFrame
  env.CreateFrame = function(...)
    local f = c.newFrame(...)
    c.frames[#c.frames + 1] = f
    return f
  end
  env.UIParent, env.Minimap = NewFrame(), NewFrame()
  local tip = NewFrame("GameTooltip")
  tip.lines = {}
  function tip.SetOwner(s) s.lines = {} end
  function tip.AddLine(s, text) s.lines[#s.lines + 1] = text end
  env.GameTooltip, c.tip = tip, tip
  function c.fire(event, ...)
    for _, f in ipairs(c.frames) do
      if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
  end
end

local function InstallPlayer(env, c, sched, bus, name, opts)
  env.GetBuildInfo = function() return "1.60.1", "70938", "Nov 2026", 16001 end
  env.GetLocale = function() return opts.locale or "enUS" end
  env.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
  env.UNKNOWNOBJECT = "Unknown"
  env.Ambiguate = function(n)
    local own = "-" .. c.realm
    return n:sub(-#own) == own and n:sub(1, -#own - 1) or n
  end
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
  env.C_GuildInfo = { GuildRoster = function() sched:at(sched.t + 1, function() if c.online then c.fire("GUILD_ROSTER_UPDATE") end end) end }
  env.GetNumGuildMembers = function() return bus and #bus.roster or 0 end
  env.GetGuildRosterInfo = function(i)
    local r = bus and bus.roster[i]
    if not r then return end
    return r.name .. "-" .. c.realm, "Member", 1, r.level, r.class, "Zone", "", "", r.online, 0, r.class
  end
  env.C_AddOns = { GetAddOnMetadata = function() return "dev" end, IsAddOnLoaded = function() return true end,
    GetAddOnInfo = function(n) return n, n, "", true, nil end }
end

function Kit.Client(sched, bus, name, opts)
  opts = opts or {}
  local c = { name = name, online = true, guild = opts.guild == nil and "Testgilde" or opts.guild or nil,
    realm = opts.realm or "Realm", prefixes = {}, printed = {}, errors = {}, sent = {}, frames = {}, frameMethods = {},
    instance = false, combat = false, dead = false, throttle = false, sched = sched, bus = bus }
  if bus then bus:member(name, opts.class or "SHAMAN", opts.level or 33) end
  local env = opts.env or setmetatable({}, { __index = _G })
  env._G = env
  c.env = env
  InstallEngine(env, c, sched, opts)
  InstallPlayer(env, c, sched, bus, name, opts)
  if opts.setup then opts.setup(env, c) end

  c.addons, c.ns = {}, {}
  function c.loadAddon(addon)
    local ns = {}
    for _, f in ipairs(TocFiles(ADDONS .. addon)) do Kit.loadchunk(ADDONS .. addon .. "/" .. f, env)(addon, ns) end
    c.addons[#c.addons + 1] = addon
    c.ns[addon] = ns
    return ns
  end
  if not opts.noCore then c.coreNs = c.loadAddon("RavenquillExpedition") end
  for _, addon in ipairs(opts.addons or {}) do c.loadAddon(addon) end
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
  function c.newModule(n) return c.RQ:NewModule(n, { addon = n }) end
  function c.login()
    for _, a in ipairs(c.addons) do c.fire("ADDON_LOADED", a) end
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD", true, false)
    c.fire("GUILD_ROSTER_UPDATE")
  end
  function c.printedMatch(needle)
    for _, line in ipairs(c.printed) do if line.text:find(needle, 1, true) then return line end end
  end
  function c.printedSince(mark)
    local out = {}
    for i = mark + 1, #c.printed do out[#out + 1] = c.printed[i].text end
    return table.concat(out, "\n")
  end
  if bus then bus.clients[#bus.clients + 1] = c end
  return c
end

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
