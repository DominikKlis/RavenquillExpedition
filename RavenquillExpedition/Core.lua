-- Ravenquill Expedition core: module registry, shared helpers, roster, peers, the /rq slash command.
-- Modules are separate addons (RavenquillExpedition_<Name>) with "## Dependencies: RavenquillExpedition".
-- Comm.lua adds the shared GUILD addon-message lane.
local ADDON, ns = ...

local GS = {}
_G.RavenquillExpedition = GS
GS.version = "0.2.0"
GS.modules, GS.moduleOrder = {}, {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- A secret / protected value: even comparing it can raise on Forever (Overlord\Sync.lua:719-721,
-- !BugGrabber log), so test before touching.
local function IsSecret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if canaccessvalue and v ~= nil and not canaccessvalue(v) then return true end
  return false
end
GS.IsSecret = IsSecret

-- A plain (non-secret) value of the given Lua type, else nil.
function GS.Plain(v, typ)
  if v == nil or IsSecret(v) then return nil end
  if typ and type(v) ~= typ then return nil end
  return v
end

local function pack(...) return { n = select("#", ...), ... } end

-- Quiet call: returns the results, or nothing when fn is missing or fails (API probing).
local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end
GS.SafeCall = SafeCall

-- Loud call: like SafeCall, but our own bugs reach BugSack and RavenquillExpeditionDB.lastError.
function GS:Call(fn, ...)
  if type(fn) ~= "function" then return end
  local args = pack(...)
  local r = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, function(err)
    local msg = tostring(err)
    if RavenquillExpeditionDB then RavenquillExpeditionDB.lastError = { t = time(), msg = msg, trace = debugstack and debugstack(2, 8, 4) } end
    local h = geterrorhandler and geterrorhandler()
    if h then pcall(h, msg) end
    return msg
  end))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end

function GS.Print(tag, ...)
  local head = "|cff33ff99Ravenquill Expedition|r"
  if tag then head = head .. " |cffbbbbbb" .. tag .. "|r" end
  print(head .. ":", ...)
end

local build = select(4, GetBuildInfo()) or 0
GS.IS_FOREVER = build >= 16000 and build < 20000

function GS:Now()
  local t = GS.Plain(SafeCall(GetServerTime), "number")
  return t or time()
end

-- On Forever the 2nd value of UnitName is a SURNAME, and roster / addon senders read "First Surname"
-- (GuildCraftAdvisor Core.lua:259-278, ForeverLFG QuestFacts.lua:17-31). Copied so both agree on names.
local function SurnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = GS.Plain(c and c.CHARACTERNAME_SURNAME_SEPARATOR, "string")
  if sep and sep ~= "" then return sep end
  return " "
end

-- Our own realm in every spelling a "-Realm" suffix might use. Stripping only these keeps
-- hyphenated surnames ("Anna Muller-Lee") intact.
local function RealmSuffixes()
  if GS.realmSuffixes then return GS.realmSuffixes end
  local out = {}
  for _, r in ipairs({ GS.Plain(SafeCall(GetNormalizedRealmName), "string") or false,
                       GS.Plain(SafeCall(GetRealmName), "string") or false }) do
    if r and r ~= "" then
      out[#out + 1] = "-" .. r
      out[#out + 1] = "-" .. r:gsub("[%s%-]", "")
    end
  end
  if out[1] then GS.realmSuffixes = out end
  return out
end

function GS:NormName(n)
  n = GS.Plain(n, "string")
  if not n or n == "" then return end
  if Ambiguate then n = GS.Plain(SafeCall(Ambiguate, n, "none"), "string") or n end
  for _, suffix in ipairs(RealmSuffixes()) do
    if #n > #suffix and n:sub(-#suffix) == suffix then n = n:sub(1, -#suffix - 1) break end
  end
  return n
end

function GS:UnitKey(unit)
  local read = UnitNameUnmodified or UnitName
  local name, second = SafeCall(read, unit)
  name, second = GS.Plain(name, "string"), GS.Plain(second, "string")
  if not name or name == "" or name == UNKNOWNOBJECT then return end
  if second and second ~= "" then
    local sep = self.IS_FOREVER and SurnameSeparator() or "-"
    if name:sub(-(#sep + #second)) ~= sep .. second then name = name .. sep .. second end
  end
  return self:NormName(name)
end

function GS:PlayerKey()
  if not self.playerKey then self.playerKey = self:UnitKey("player") end
  return self.playerKey
end

-- "<guild>@<normalized realm>", or nil when not in a guild / not known yet after login.
-- Only the normalized realm name is used, so the key can't flip between spellings.
function GS:GuildKey()
  local g = GS.Plain(SafeCall(GetGuildInfo, "player"), "string")
  local realm = GS.Plain(SafeCall(GetNormalizedRealmName), "string")
  if not g or g == "" or not realm or realm == "" then return end
  return g .. "@" .. realm
end

function GS:InInstance()
  local inside = SafeCall(IsInInstance)
  return (GS.Plain(inside) and true) or false
end

-- Client format string -> anchored Lua pattern. Handles deDE positional "%1$s" (copied from GCA Core.lua).
-- Captures come back in the order they appear in the string (fine for the loot strings used here).
function GS.FormatToPattern(fmt)
  fmt = GS.Plain(fmt, "string")
  if not fmt then return end
  local f = fmt:gsub("%%(%d+)%$([sd])", "%%%2")
  local out, i = {}, 1
  while i <= #f do
    local c = f:sub(i, i)
    if c == "%" then
      local n = f:sub(i + 1, i + 1)
      if n == "s" then out[#out + 1] = "(.+)"
      elseif n == "d" then out[#out + 1] = "(%d+)"
      elseif n == "%" then out[#out + 1] = "%%"
      else return end
      i = i + 2
    else
      out[#out + 1] = c:find("[%(%)%.%[%]%*%+%-%?%^%$]") and ("%" .. c) or c
      i = i + 1
    end
  end
  local p = "^" .. table.concat(out) .. "$"
  if not pcall(string.match, "", p) then return end
  return p
end

-- Cut a string to at most n bytes without splitting a UTF-8 character (German umlauts).
function GS.Cut(s, n)
  if type(s) ~= "string" then return "" end
  if #s <= n then return s end
  s = s:sub(1, n)
  local i = #s
  while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
  if i > 0 and s:byte(i) >= 0xC0 then
    local need = s:byte(i) >= 0xF0 and 4 or s:byte(i) >= 0xE0 and 3 or 2
    if #s - i + 1 < need then s = s:sub(1, i - 1) end
  end
  return s
end

---------------------------------------------------------------------------
-- Guild roster cache: GS.roster[key] = { class, level, online }
---------------------------------------------------------------------------
GS.roster = {}
function GS:RequestRoster()
  local now = GetTime()
  if self.rosterAsked and now - self.rosterAsked < 15 then return end
  self.rosterAsked = now
  if C_GuildInfo and C_GuildInfo.GuildRoster then SafeCall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then SafeCall(GuildRoster) end
end

function GS:ReadRoster()
  local n = GS.Plain(SafeCall(GetNumGuildMembers), "number") or 0
  local roster = {}
  for i = 1, n do
    local name, _, _, level, _, _, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      roster[key] = { level = GS.Plain(level, "number"), class = GS.Plain(classFile, "string"), online = GS.Plain(online) and true or false }
      if RavenquillExpeditionDB and not RavenquillExpeditionDB.diagRosterName then RavenquillExpeditionDB.diagRosterName = GS.Plain(name, "string") end
    end
  end
  if n > 0 then self.roster = roster end
  self.rosterRead = GetTime()
end

-- true / false, or nil while the roster is still unknown
function GS:IsGuildMember(key)
  if not key then return false end
  if key == self:PlayerKey() then return (SafeCall(IsInGuild)) and true or false end
  if not next(self.roster) then self:RequestRoster(); return nil end
  return self.roster[key] and true or false
end

-- Keys of the guild members in my party/raid (without me).
function GS:GroupGuildies()
  local out = {}
  local n = GS.Plain(SafeCall(GetNumGroupMembers), "number") or 0
  if n == 0 then return out end
  local raid = GS.Plain(SafeCall(IsInRaid)) and true or false
  local me = self:PlayerKey()
  for i = 1, n do
    local key = self:UnitKey((raid and "raid" or "party") .. i)
    if key and key ~= me and self:IsGuildMember(key) == true then out[#out + 1] = key end
  end
  return out
end

---------------------------------------------------------------------------
-- Peers: guildies heard on the suite's lane (= they run a Ravenquill Expedition module). Saved per account.
---------------------------------------------------------------------------
GS.PEER_MAX_AGE = 14 * 86400
function GS:NotePeer(key)
  if not (RavenquillExpeditionDB and key) then return end
  RavenquillExpeditionDB.peers = RavenquillExpeditionDB.peers or {}
  RavenquillExpeditionDB.peers[key] = self:Now()
end
function GS:IsPeer(key)
  if key and key == self:PlayerKey() then return true end
  local t = RavenquillExpeditionDB and RavenquillExpeditionDB.peers and RavenquillExpeditionDB.peers[key]
  return t and self:Now() - t <= self.PEER_MAX_AGE or false
end

-- My place (0 = first) among the candidates that run the suite, sorted by name. Everyone in the group
-- computes the same order, so the first one reports and the others only step in when it doesn't.
function GS:ElectionRank(candidates)
  local list, me = {}, self:PlayerKey()
  list[1] = me
  for _, k in ipairs(candidates or {}) do if k ~= me and self:IsPeer(k) then list[#list + 1] = k end end
  table.sort(list)
  for i, k in ipairs(list) do if k == me then return i - 1, #list end end
  return 0, #list
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
-- mod.addon = the module's addon folder name (its SavedVariables are ready at that ADDON_LOADED)
-- Callbacks (all optional): mod:OnLoad(), mod:OnLogin(), mod:OnSlash(rest), mod.slash = "hl", mod.title
function GS:NewModule(name, mod)
  mod = mod or {}
  mod.name, mod.core = name, self
  if not self.modules[name] then self.moduleOrder[#self.moduleOrder + 1] = name end
  self.modules[name] = mod
  return mod
end

function GS:GetModule(name) return self.modules[name] end

---------------------------------------------------------------------------
-- Slash: the only command is /rq (user decision 2026-11-14: options live in the UI, not in chat commands).
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
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
GS.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "GUILD_ROSTER_UPDATE" then
    GS:Call(GS.ReadRoster, GS)
  elseif event == "ADDON_LOADED" then
    if arg1 == ADDON then
      RavenquillExpeditionDB = type(RavenquillExpeditionDB) == "table" and RavenquillExpeditionDB or {}
      GS.db = RavenquillExpeditionDB
    end
    for _, name in ipairs(GS.moduleOrder) do
      local m = GS.modules[name]
      if m.addon == arg1 and not m.loaded then
        m.loaded = true
        if m.OnLoad then GS:Call(m.OnLoad, m) end
      end
    end
  elseif event == "PLAYER_LOGIN" then
    GS.loggedIn = true
    GS.playerKey, GS.realmSuffixes = nil, nil
    GS:RequestRoster()
    if GS.OnLoginComm then GS:Call(GS.OnLoginComm, GS) end
    for _, name in ipairs(GS.moduleOrder) do
      local m = GS.modules[name]
      if m.OnLogin then GS:Call(m.OnLogin, m) end
    end
  end
end)
