local ADDON, ns = ...
local GS = ns.GS
local L = GS.OverviewL

GS.modules, GS.moduleOrder = {}, {}

local Proto = {}
local ProtoMeta = { __index = Proto }
ns.ModuleProto = Proto

function Proto:Print(...) GS.Print(self.title or self.name, ...) end

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

function Proto:After(seconds, fn)
  C_Timer.After(seconds, function() GS:Call(fn, self) end)
end

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
ns.SetupModuleDB = SetupDB

function GS:NewModule(name, spec)
  local mod = spec or {}
  if type(mod.api) == "number" and mod.api > self.API then
    self.Print(nil, L.API_TOO_OLD:format(name, mod.api, self.API))
    return setmetatable(mod, ProtoMeta)
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

local function ModuleOptions(m)
  if type(m.options) == "table" and m.options[1] then return m.options end
end
ns.ModuleOptions = ModuleOptions

local function SlashWord(m) return m.slash or m.name:lower() end
ns.SlashWord = SlashWord

SLASH_RAVENQUILL1 = "/rq"
SLASH_RAVENQUILL2 = "/ravenquill"
local function SlashMatches(m, key)
  return SlashWord(m) == key or m.name:lower() == key
end

local function OpenFromSlash(m, name, rest)
  if rest ~= "" and m.OnSlash then return GS:Call(m.OnSlash, m, rest) end
  if m.openFirst and m.Open then return GS:Call(m.Open, m) end
  if ModuleOptions(m) then return GS:Call(GS.OpenModule, GS, name) end
  if m.Open then return GS:Call(m.Open, m) end
  if m.OnSlash then return GS:Call(m.OnSlash, m, "") end
  GS:Call(GS.ToggleOverview, GS)
end

local function SlashModule(key)
  for _, name in ipairs(GS.moduleOrder) do
    local m = GS.modules[name]
    if SlashMatches(m, key) then return m, name end
  end
end

SlashCmdList.RAVENQUILL = function(msg)
  msg = type(msg) == "string" and msg or ""
  local key, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
  local m, name
  if key then m, name = SlashModule(key:lower()) end
  if m then OpenFromSlash(m, name, rest) return end
  GS:Call(GS.ToggleOverview, GS)
end

local function EachModule(fn)
  for _, name in ipairs(GS.moduleOrder) do fn(GS.modules[name]) end
end

local frame = CreateFrame("Frame")
GS.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")

local function OnAddonLoaded(addon)
  if addon == ADDON then
    RavenquillExpeditionDB = type(RavenquillExpeditionDB) == "table" and RavenquillExpeditionDB or {}
    GS.db = RavenquillExpeditionDB
  end
  EachModule(function(m)
    if m.addon == addon and not m.loaded then
      m.loaded = true
      GS:Call(SetupDB, m)
      if m.OnLoad then GS:Call(m.OnLoad, m) end
    end
  end)
end

local function WarnUnloadedModule(m)
  if m.loaded or not (m.sv or m.svChar or m.defaults or m.OnLoad) then return end
  GS.Print(nil, ("module %s never loaded: its spec needs addon = <its folder name> (now %s)."):format(
    tostring(m.name), tostring(m.addon)))
end

local function OnPlayerLogin()
  GS.loggedIn = true
  ns.ResetNameCache()
  GS.guildKey = GS:GuildKey()
  GS:RequestRoster()
  GS:Call(GS.PrunePeers, GS)
  GS:Call(GS.OnLoginComm, GS)
  GS:Call(GS.OnLoginPresence, GS)
  GS:Call(GS.OnLoginGoal, GS)
  EachModule(function(m)
    if m.db and m.loginMigrations then GS:Call(Migrate, m, m.db, m.cdb, m.loginMigrations, "vLogin") end
  end)
  EachModule(function(m) if m.OnLogin then GS:Call(m.OnLogin, m) end end)
  EachModule(WarnUnloadedModule)
end

local function TellGuildChanged(new, old)
  EachModule(function(m) if m.OnGuildChanged then GS:Call(m.OnGuildChanged, m, new, old) end end)
end

local function OnGuildUpdate()
  local new, old = GS:GuildKey(), GS.guildKey
  local inGuild = GS.Plain(GS.SafeCall(IsInGuild))
  if new and new ~= old then
    GS.guildKey = new
    if old then
      ns.ForgetRoster()
      TellGuildChanged(new, old)
    end
  elseif not new and old and not inGuild then
    GS.guildKey = nil
    ns.ForgetRoster()
    TellGuildChanged(nil, old)
  end
end

local CoreEvents = {
  GUILD_ROSTER_UPDATE = function() GS:Call(GS.ReadRoster, GS) end,
  ADDON_LOADED = OnAddonLoaded,
  PLAYER_LOGIN = OnPlayerLogin,
  PLAYER_GUILD_UPDATE = OnGuildUpdate,
}

frame:SetScript("OnEvent", function(_, event, arg1)
  local handle = CoreEvents[event]
  if handle then handle(arg1) end
end)

local function PlainText(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function PeerList(peers, versions)
  local out = {}
  for k, t in pairs(peers or {}) do out[#out + 1] = k .. " " .. (versions[k] or "?") .. " (" .. date("%d.%m. %H:%M", t) .. ")" end
  table.sort(out)
  return out[1] and table.concat(out, ", ") or "-"
end

local function AppendLastError(out, e)
  if not e then return end
  out[#out + 1] = "last error: " .. date("%d.%m. %H:%M", e.t or 0) .. " " .. tostring(e.msg)
  if e.trace then out[#out + 1] = tostring(e.trace) end
end

function GS:DiagLines()
  local out = {
    "Ravenquill Expedition v" .. self.version .. "  build " .. tostring((select(4, GetBuildInfo()))),
    "player: " .. tostring(self:PlayerKey()) .. "  guild: " .. tostring(self:GuildKey()),
    "sync: " .. PlainText(self:CommStatus()),
    "roster members: " .. (function() local n = 0; for _ in pairs(self.roster) do n = n + 1 end; return n end)(),
  }
  out[#out + 1] = "peers: " .. PeerList(self:Peers(), self:PeerVersions() or {})
  local names = {}
  for _, name in ipairs(self.moduleOrder) do names[#names + 1] = name .. "=" .. tostring(self.modules[name].addon) end
  out[#out + 1] = "modules: " .. table.concat(names, ", ")
  AppendLastError(out, (self.db or {}).lastError)
  out[#out + 1] = ""
  out[#out + 1] = "== minimap button"
  self:Call(self.LauncherDebug, self, function(line) out[#out + 1] = PlainText(line) end)
  for _, name in ipairs(self.moduleOrder) do self:AppendModuleDiagnostics(out, self.modules[name]) end
  return out
end

function GS:AppendModuleDiagnostics(out, mod)
  if not mod.OverviewDiagnostics then return end
  local lines = self:Call(mod.OverviewDiagnostics, mod)
  if type(lines) ~= "table" then return end
  out[#out + 1] = ""
  out[#out + 1] = "== " .. tostring(mod.title or mod.name)
  for _, line in ipairs(lines) do out[#out + 1] = tostring(line) end
end
