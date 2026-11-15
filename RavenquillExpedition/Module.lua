-- Ravenquill Expedition core: modules. A module is its own addon folder; it registers with
--   local mod = RavenquillExpedition:NewModule("Name", spec)
-- spec fields (all optional; docs/module-api.md):
--   addon         the module's folder name: its SavedVariables are set up and OnLoad runs at its ADDON_LOADED
--   api           minimum core API (RQ.API); a too-old core prints one line and doesn't load the module
--   title, icon, slash   its row in the /rq overview and "/rq <slash>"
--   sv, svChar    names of its SavedVariables (account / per character); ready as mod.db / mod.cdb in OnLoad
--   defaults      setting defaults, kept in db.settings (mod.settings); a missing or wrong-typed value is replaced
--   charDefaults  defaults for the per-character table (mod.cdb), same rule
--   dbVersion, migrations = { [n] = function(db, cdb, mod) end }   run in order from db.v + 1 up to dbVersion,
--                 each under RQ:Call; one that fails stops the chain (db.v stays at the last good step)
--   loginMigrations = { [n] = function(db, cdb, mod) end }   the same at PLAYER_LOGIN (realm / player known), db.vLogin
--   locale = { enUS = {...}, deDE = {...} }   becomes mod.L (client language, then English, then the key)
-- Callbacks: mod:OnLoad(), mod:OnLogin(), mod:OnGuildChanged(newKey, oldKey), mod:OnSlash(rest), mod:Open(),
--   mod:OverviewStatus(), mod:OverviewRecent(n), mod:OnOptionChanged(key, value). Every call goes through RQ:Call.
-- Methods: see Proto below (Print, RegisterEvent, After, Every, GuildStore, SetOptions, Option, ...).
local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL

GS.modules, GS.moduleOrder = {}, {}

---------------------------------------------------------------------------
-- Module methods
---------------------------------------------------------------------------
local Proto = {}
local ProtoMeta = { __index = Proto }
GS.ModuleProto = Proto

function Proto:Print(...) GS.Print(self.title or self.name, ...) end

-- handler(mod, ...) or, without handler, the method mod[event]; runs under RQ:Call
function Proto:RegisterEvent(event, handler)
  local f = rawget(self, "eventFrame")
  if not f then
    f = CreateFrame("Frame")
    rawset(self, "eventFrame", f)
    rawset(self, "eventHandlers", {})
    f:SetScript("OnEvent", function(_, ev, ...)
      local h = self.eventHandlers[ev]
      if h then GS:Call(h, self, ...) end
    end)
  end
  self.eventHandlers[event] = handler or function(m, ...) if m[event] then return m[event](m, ...) end end
  -- an event this client doesn't know raises in RegisterEvent: report false instead
  local ok = pcall(f.RegisterEvent, f, event)
  if not ok then self.eventHandlers[event] = nil; GS:Trace("event", self.name .. ": unknown event " .. tostring(event)) end
  return ok
end

function Proto:UnregisterEvent(event)
  local f = rawget(self, "eventFrame")
  if not f then return end
  self.eventHandlers[event] = nil
  f:UnregisterEvent(event)
end

-- fn(mod) after `seconds`, under RQ:Call
function Proto:After(seconds, fn)
  C_Timer.After(seconds, function() GS:Call(fn, self) end)
end

-- fn(mod) every `seconds` until handle:Cancel()
function Proto:Every(seconds, fn)
  local handle = { cancelled = false }
  function handle.Cancel(h) h.cancelled = true end
  local function tick()
    if handle.cancelled then return end
    GS:Call(fn, self)
    if not handle.cancelled then C_Timer.After(seconds, tick) end
  end
  C_Timer.After(seconds, tick)
  return handle
end

-- A table in the module's SavedVariables for the current guild: db.guilds[guildKey][name or "data"].
-- Data from one guild never shows in another. "-" while the guild is unknown.
function Proto:GuildStore(name)
  local db = self.db
  if not db then return {} end
  db.guilds = type(db.guilds) == "table" and db.guilds or {}
  local g = GS:GuildKey() or "-"
  db.guilds[g] = type(db.guilds[g]) == "table" and db.guilds[g] or {}
  local k = name or "data"
  db.guilds[g][k] = type(db.guilds[g][k]) == "table" and db.guilds[g][k] or {}
  return db.guilds[g][k]
end

-- The options shown in /rq (entry types: header, toggle, range, button, text; see Options.lua).
-- Shorthand: { type = "toggle", key = "share", label = ... } reads and writes mod.settings.share and then calls
-- mod:OnOptionChanged("share", value).
function Proto:SetOptions(list)
  for _, o in ipairs(list) do
    if o.key then
      o.id = o.id or o.key
      local key = o.key
      if not o.get then o.get = function() return self.settings and self.settings[key] end end
      if not o.set then
        o.set = function(v)
          if not self.settings then return end
          self.settings[key] = v
          if self.OnOptionChanged then GS:Call(self.OnOptionChanged, self, key, v) end
        end
      end
    end
  end
  self.options = list
  return list
end

function Proto:Option(id)
  for _, o in ipairs(self.options or {}) do
    if o.id == id or o.key == id then return o end
  end
end

---------------------------------------------------------------------------
-- SavedVariables: defaults and numbered migrations
---------------------------------------------------------------------------
local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end

local function FillDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if v ~= nil and type(t[k]) ~= type(v) then t[k] = Copy(v) end
  end
end
GS.FillDefaults = FillDefaults

local function Migrate(mod, db, cdb, list, field, upTo)
  if type(list) ~= "table" and not upTo then return end
  local from = tonumber(db[field]) or 0
  local to = upTo or 0
  for n in pairs(list or {}) do if type(n) == "number" and n > to then to = n end end
  for n = from + 1, to do
    local fn = list and list[n]
    if fn then
      local ok = GS:Call(function() fn(db, cdb, mod); return true end)
      if not ok then GS:Trace("err", mod.name .. ": migration " .. field .. " " .. n .. " failed") return end
    end
    db[field] = n
  end
end

local function SetupDB(mod)
  local db, cdb
  if mod.sv then
    db = _G[mod.sv]
    if type(db) ~= "table" then db = {} end
    _G[mod.sv] = db
  end
  if mod.svChar then
    cdb = _G[mod.svChar]
    if type(cdb) ~= "table" then cdb = {} end
    _G[mod.svChar] = cdb
  end
  if db then
    Migrate(mod, db, cdb, mod.migrations, "v", mod.dbVersion)
    if mod.defaults then
      if type(db.settings) ~= "table" then db.settings = {} end
      FillDefaults(db.settings, mod.defaults)
      mod.settings = db.settings
    end
    mod.db = db
  end
  if cdb then
    if mod.charDefaults then FillDefaults(cdb, mod.charDefaults) end
    mod.cdb = cdb
  end
end
-- (for the offline compat harnesses: what the core does at the module's ADDON_LOADED, before OnLoad)
GS.SetupModuleDB = SetupDB

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
function GS:NewModule(name, spec)
  local mod = spec or {}
  if type(mod.api) == "number" and mod.api > self.API then
    self.Print(nil, L.API_TOO_OLD:format(name, mod.api, self.API))
    return setmetatable(mod, ProtoMeta) -- usable table, never loaded
  end
  mod.name, mod.core = name, self
  if getmetatable(mod) == nil then setmetatable(mod, ProtoMeta) end
  if mod.locale then mod.L = GS.NewLocale(mod.locale) end
  if mod.options then mod:SetOptions(mod.options) end
  if not self.modules[name] then self.moduleOrder[#self.moduleOrder + 1] = name end
  self.modules[name] = mod
  return mod
end

function GS:GetModule(name) return self.modules[name] end

---------------------------------------------------------------------------
-- Slash: the only command is /rq (options live in the UI, not in chat commands).
--   /rq            the overview window
--   /rq <key>      that module's options (or its window when it has no options)
--   /rq <key> ...  passed to mod:OnSlash(rest) for modules that still take arguments
---------------------------------------------------------------------------
SLASH_RAVENQUILL1 = "/rq"
SLASH_RAVENQUILL2 = "/ravenquill"
SlashCmdList.RAVENQUILL = function(msg)
  msg = type(msg) == "string" and msg or ""
  local key, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
  if key then
    key = key:lower()
    for _, name in ipairs(GS.moduleOrder) do
      local m = GS.modules[name]
      if (m.slash or name:lower()) == key or name:lower() == key then
        if rest ~= "" and m.OnSlash then GS:Call(m.OnSlash, m, rest)
        elseif type(m.options) == "table" and m.options[1] and GS.OpenModule then GS:Call(GS.OpenModule, GS, name)
        elseif m.Open then GS:Call(m.Open, m)
        elseif m.OnSlash then GS:Call(m.OnSlash, m, "")
        elseif GS.ToggleOverview then GS:Call(GS.ToggleOverview, GS) end
        return
      end
    end
  end
  if GS.ToggleOverview then GS:Call(GS.ToggleOverview, GS) end
end

---------------------------------------------------------------------------
-- Events: the lifecycle of the core and every module
---------------------------------------------------------------------------
local function EachModule(fn)
  for _, name in ipairs(GS.moduleOrder) do fn(GS.modules[name]) end
end

local frame = CreateFrame("Frame")
GS.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "GUILD_ROSTER_UPDATE" then
    GS:Call(GS.ReadRoster, GS)
  elseif event == "ADDON_LOADED" then
    if arg1 == ADDON then
      RavenquillExpeditionDB = type(RavenquillExpeditionDB) == "table" and RavenquillExpeditionDB or {}
      GS.db = RavenquillExpeditionDB
    end
    EachModule(function(m)
      if m.addon == arg1 and not m.loaded then
        m.loaded = true
        GS:Call(SetupDB, m)
        if m.OnLoad then GS:Call(m.OnLoad, m) end
      end
    end)
  elseif event == "PLAYER_LOGIN" then
    GS.loggedIn = true
    GS.playerKey, GS.realmSuffixes = nil, nil
    GS.guildKey = GS:GuildKey()
    GS:RequestRoster()
    GS:Call(GS.PrunePeers, GS)
    if GS.OnLoginComm then GS:Call(GS.OnLoginComm, GS) end
    EachModule(function(m)
      if m.db and m.loginMigrations then GS:Call(Migrate, m, m.db, m.cdb, m.loginMigrations, "vLogin") end
    end)
    EachModule(function(m) if m.OnLogin then GS:Call(m.OnLogin, m) end end)
  elseif event == "PLAYER_GUILD_UPDATE" then
    -- a real change only: unknown -> known right after login is not one
    local new, old = GS:GuildKey(), GS.guildKey
    local inGuild = GS.Plain(GS.SafeCall(IsInGuild))
    if new and new ~= old then
      GS.guildKey = new
      if old then EachModule(function(m) if m.OnGuildChanged then GS:Call(m.OnGuildChanged, m, new, old) end end) end
    elseif not new and old and not inGuild then
      GS.guildKey = nil
      EachModule(function(m) if m.OnGuildChanged then GS:Call(m.OnGuildChanged, m, nil, old) end end)
    end
  end
end)
