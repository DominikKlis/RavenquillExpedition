-- Ravenquill Expedition: Map – settings (shown in the /rq overview), member store, own position, test pins.
-- Pins.lua draws ns.Map.members on the world map and minimap (HereBeDragons).
-- Sync.lua (step 2) sends our position and fills members from guildmates' messages.
--
-- Runs standalone; when the Ravenquill Expedition core is loaded (## OptionalDeps) its helpers are used instead of
-- the local shims below (the shims keep the offline harness running without the core; in game the core is
-- required, ## Dependencies).
local ADDON, ns = ...
local L = ns.L
-- The suite core (AddOns\RavenquillExpedition); nil when it isn't installed.
local GS = _G.RavenquillExpedition

local M = {}
ns.Map = M
_G.RavenquillExpeditionMap = M -- for /dump only

M.core = GS
M.version = "0.2.0"

M.C = {
  TICK = 2,             -- s between refreshes (own position, fades, minimap rule)
  INTERVAL_MIN = 30,    -- step 2 computes the adaptive interval; step 1 uses the floor
  HEARTBEAT = 300,      -- standing still: one message per max(HEARTBEAT, interval)
  FADE_MIN = 180,       -- moving pins fade at max(FADE_MIN, 2 × interval)
  STATIONARY_FADE = 1.5,-- stationary pins fade at 1.5 × heartbeat
  REMOVE_FACTOR = 2,    -- removed at 2 × the fade time
  MINIMAP_FRESH = 45,   -- minimap shows a pin only when younger than this, or stationary
  FAKE_MOVE = 10,       -- test pins move every 10 s
  NOTICE_DELAY = 8,     -- s after login before the privacy notice (chat frames ready)
}

M.DEFAULTS = {
  share = true,     -- user decision 2026-11-14: on by default, with a one-time notice
  worldmap = true,
  minimap = true,
  names = false,
  size = 1.0,
  selfPin = false,  -- test aid: a pin at your own position
}

---------------------------------------------------------------------------
-- Helpers: the core when present, else local shims with the same names and calling conventions
-- (SafeCall / IsSecret / Print are plain functions; the rest are methods). Plan section M.
---------------------------------------------------------------------------
-- Same as core Core.lua:16-20 (v0.2.0).
local function IsSecretShim(v)
  if issecretvalue and issecretvalue(v) then return true end
  if canaccessvalue and v ~= nil and not canaccessvalue(v) then return true end
  return false
end
local function pack(...) return { n = select("#", ...), ... } end
local function SafeCallShim(fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end
local function PrintShim(tag, ...)
  local head = "|cff33ff99Ravenquill Expedition|r"
  if tag then head = head .. " |cffbbbbbb" .. tag .. "|r" end
  print(head .. ":", ...)
end

local IsSecret = (GS and GS.IsSecret) or IsSecretShim
local SafeCall = (GS and GS.SafeCall) or SafeCallShim
local PrintRaw = (GS and GS.Print) or PrintShim
M.IsSecret, M.SafeCall = IsSecret, SafeCall
function M.Print(...) PrintRaw(L.TITLE, ...) end

-- A plain boolean from an API result: secret or non-boolean values count as false (a secret can't be tested).
local function Bool(v) if IsSecret(v) then return false end return v and true or false end
M.Bool = Bool

-- Our own realm in every spelling a "-Realm" suffix might use (as core Core.lua:81-93). Stripping only these
-- keeps hyphenated surnames ("Anna Müller-Lee") intact (code review #6).
local realmSuffixes
local function RealmSuffixes()
  if realmSuffixes then return realmSuffixes end
  local out = {}
  for _, fn in ipairs({ GetNormalizedRealmName or false, GetRealmName or false }) do
    local r = fn and SafeCall(fn)
    if type(r) == "string" and not IsSecret(r) and r ~= "" then
      out[#out + 1] = "-" .. r
      out[#out + 1] = "-" .. r:gsub("[%s%-]", "")
    end
  end
  if out[1] then realmSuffixes = out end
  return out
end
-- key without our own "-Realm" suffix, or nil when it has none
function M.StripRealm(key)
  if type(key) ~= "string" then return end
  for _, suffix in ipairs(RealmSuffixes()) do
    if #key > #suffix and key:sub(-#suffix) == suffix then return key:sub(1, -#suffix - 1) end
  end
end

local Shim = {}
local build = select(4, GetBuildInfo()) or 0
Shim.IS_FOREVER = build >= 16000 and build < 20000
function Shim:Now() return (GetServerTime and SafeCall(GetServerTime)) or time() end
function Shim:NormName(n)
  if type(n) ~= "string" or IsSecret(n) or n == "" then return end
  if Ambiguate then
    local a = SafeCall(Ambiguate, n, "none")
    if type(a) == "string" and not IsSecret(a) then n = a end
  end
  return M.StripRealm(n) or n
end
local function SurnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and sep ~= "" and not IsSecret(sep) then return sep end
  return " "
end
-- Same logic as core Core.lua:69-78 (Forever: 2nd value of UnitName is a surname).
function Shim:UnitKey(unit)
  local read = UnitNameUnmodified or UnitName
  local name, second = SafeCall(read, unit)
  if type(name) ~= "string" or IsSecret(name) or name == "" or name == UNKNOWNOBJECT then return end
  if type(second) == "string" and not IsSecret(second) and second ~= "" then
    local sep = self.IS_FOREVER and SurnameSeparator() or "-"
    if name:sub(-(#sep + #second)) ~= sep .. second then name = name .. sep .. second end
  end
  return self:NormName(name)
end
function Shim:PlayerKey()
  if not self.playerKey then self.playerKey = self:UnitKey("player") end
  return self.playerKey
end
function Shim:InInstance() return Bool(SafeCall(IsInInstance)) end

-- Guild roster, same shape and logic as core Core.lua:138-171: roster[key] = { class, level, online }
Shim.roster = {}
function Shim:RequestRoster()
  local now = GetTime()
  if self.rosterAsked and now - self.rosterAsked < 15 then return end
  self.rosterAsked = now
  if C_GuildInfo and C_GuildInfo.GuildRoster then SafeCall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then SafeCall(GuildRoster) end
end
function Shim:ReadRoster()
  local n = SafeCall(GetNumGuildMembers) or 0
  if type(n) ~= "number" or IsSecret(n) then return end
  local roster = {}
  for i = 1, n do
    local name, _, _, level, _, _, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      roster[key] = { level = (not IsSecret(level)) and level or nil, class = (not IsSecret(classFile)) and classFile or nil,
        online = (not IsSecret(online)) and online and true or false }
    end
  end
  if n > 0 then self.roster = roster end
  self.rosterRead = GetTime()
end
-- true / false, or nil while the roster is still unknown
function Shim:IsGuildMember(key)
  if not key then return false end
  if key == self:PlayerKey() then return Bool(SafeCall(IsInGuild)) end
  if not next(self.roster) then self:RequestRoster(); return nil end
  if self.roster[key] then return true end
  local first = M.StripRealm(key)
  return first and self.roster[first] and true or false
end

for _, name in ipairs({ "Now", "NormName", "UnitKey", "PlayerKey", "InInstance", "IsGuildMember", "RequestRoster" }) do
  M[name] = function(_, ...)
    if GS and type(GS[name]) == "function" then return GS[name](GS, ...) end
    return Shim[name](Shim, ...)
  end
end

function M:Roster() return (GS and type(GS.roster) == "table" and GS.roster) or Shim.roster end
-- GetTime() of the last roster read, or nil (core Core.lua:200 keeps the same field).
function M:RosterReadAt()
  if GS then return type(GS.rosterRead) == "number" and GS.rosterRead or nil end
  return Shim.rosterRead
end

-- Online members in the roster (0 while unknown); cached 30 s because it's read often (code review #7).
function M:OnlineCount()
  local now = GetTime()
  if self.onlineAt and now - self.onlineAt < 30 then return self.online end
  local n = 0
  for _, e in pairs(self:Roster()) do if e.online then n = n + 1 end end
  self.online, self.onlineAt = n, now
  return n
end

-- Roster entry for a key (also "Name-<our realm>" style senders), or nil.
function M:RosterEntry(key)
  if not key then return end
  local roster = self:Roster()
  local first = M.StripRealm(key)
  return roster[key] or (first and roster[first])
end

-- Loud call: our own bugs reach BugSack and db.lastError.
function M.Call(fn, ...)
  local args = pack(...)
  local r = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, function(err)
    local msg = tostring(err)
    if M.db then M.db.lastError = { t = time(), msg = msg, trace = debugstack and debugstack(2, 8, 4) } end
    local h = geterrorhandler and geterrorhandler()
    if h then pcall(h, msg) end
    return msg
  end))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end

---------------------------------------------------------------------------
-- SavedVariables (settings only – other players' positions are never saved, plan section 1)
---------------------------------------------------------------------------
function M:InitDB()
  local db = type(RavenquillExpeditionMapDB) == "table" and RavenquillExpeditionMapDB or {}
  RavenquillExpeditionMapDB = db
  db.v = 1
  db.settings = type(db.settings) == "table" and db.settings or {}
  for k, v in pairs(self.DEFAULTS) do
    if type(db.settings[k]) ~= type(v) then db.settings[k] = v end
  end
  local s = db.settings.size
  if s < 0.5 or s > 2 then db.settings.size = 1.0 end
  self.db, self.settings = db, db.settings
end

---------------------------------------------------------------------------
-- Member store: members[key] = { key, name, mapID, x, y, level, class, heard (GetTime),
--   flags = { s = stationary, t = taxi, g = ghost }, fake = bool, isSelf = bool }
-- Step 2 fills it from received messages; step 1 only from the own and test pins.
---------------------------------------------------------------------------
M.members = {}

function M:Interval() return self.C.INTERVAL_MIN end -- step 2: adaptive

-- Seconds after the last news at which a pin fades (dimmed) – plan section 1, "Staleness".
function M:FadeAfter(m)
  local C = self.C
  if m.flags and m.flags.s then return C.STATIONARY_FADE * math.max(C.HEARTBEAT, self:Interval()) end
  return math.max(C.FADE_MIN, 2 * self:Interval())
end

function M:Age(m) return GetTime() - (m.heard or 0) end

-- "fresh" | "stale" | "gone"
function M:State(m)
  if m.isSelf then return "fresh" end
  local age, fade = self:Age(m), self:FadeAfter(m)
  if age >= fade * self.C.REMOVE_FACTOR then return "gone" end
  if age >= fade then return "stale" end
  return "fresh"
end

---------------------------------------------------------------------------
-- Own position. nil (or 0,0) means "no position" (instances, some loading states) – WarEffortScout Geo.lua:73.
---------------------------------------------------------------------------
local function ReadNumber(v) if type(v) == "number" and not IsSecret(v) then return v end end

function M:ReadOwnPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
  local mapID = ReadNumber(SafeCall(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return end
  local pos = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" or IsSecret(pos) then return end
  local x, y
  if pos.GetXY then x, y = SafeCall(pos.GetXY, pos) else x, y = pos.x, pos.y end
  x, y = ReadNumber(x), ReadNumber(y)
  if not x or not y or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return end
  return mapID, x, y
end

local function PlayerFlags()
  return {
    g = Bool(SafeCall(UnitIsDeadOrGhost, "player")) or nil,
    t = Bool(SafeCall(UnitOnTaxi, "player")) or nil,
  }
end

function M:UpdateSelfPin()
  local key = "@self"
  if not self.settings.selfPin then self.members[key] = nil; return end
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then self.members[key] = nil; return end
  local _, class = SafeCall(UnitClass, "player")
  self.members[key] = {
    key = key, name = self:PlayerKey() or UNKNOWNOBJECT, mapID = mapID, x = x, y = y,
    level = ReadNumber(SafeCall(UnitLevel, "player")) or 0, class = (not IsSecret(class)) and class or nil,
    heard = GetTime(), flags = PlayerFlags(), isSelf = true,
  }
end

---------------------------------------------------------------------------
-- Test pins (/rq map fake): local only, nothing is sent. They show every look and lifecycle:
-- moving (updated every 10 s), stationary, ghost, taxi, stale (faded, removed later), and one that
-- stops updating (drops off the minimap after 45 s, fades at 3 min, disappears at 6 min).
---------------------------------------------------------------------------
local FAKES = {
  { name = "Test Eins",   class = "WARRIOR", level = 60, dx =  0.010, dy =  0.006, move = true },
  { name = "Test Zwei",   class = "MAGE",    level = 42, dx = -0.012, dy =  0.004, flags = { s = true } },
  { name = "Test Drei",   class = "PRIEST",  level = 35, dx =  0.004, dy = -0.012, flags = { g = true }, move = true },
  { name = "Test Vier",   class = "HUNTER",  level = 51, dx = -0.030, dy = -0.020, flags = { t = true }, move = true },
  { name = "Test Fünf",   class = "ROGUE",   level = 27, dx =  0.025, dy = -0.025, age = 200 },
  { name = "Test Sechs",  class = "DRUID",   level = 60, dx = -0.006, dy =  0.020, age = 0 },
  { name = "Test Sieben", class = "PALADIN", level = 19, dx =  0.045, dy =  0.030, move = true },
}

local function Clamp(v) return math.max(0.01, math.min(0.99, v)) end

function M:Fake(on)
  for key, m in pairs(self.members) do if m.fake then self.members[key] = nil end end
  self.fakeOn = false
  if not on then self:Refresh(); return end
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then self.Print(L.FAKE_NOPOS); return end
  local now = GetTime()
  for i, f in ipairs(FAKES) do
    local key = "~fake" .. i
    self.members[key] = {
      key = key, name = f.name, mapID = mapID, x = Clamp(x + f.dx), y = Clamp(y + f.dy),
      level = f.level, class = f.class, heard = now - (f.age or 0), flags = f.flags or {}, fake = true, move = f.move,
    }
  end
  self.fakeOn, self.fakeMovedAt = true, now
  self:Refresh()
end

function M:MoveFakes()
  if not self.fakeOn or GetTime() - (self.fakeMovedAt or 0) < self.C.FAKE_MOVE then return end
  self.fakeMovedAt = GetTime()
  for _, m in pairs(self.members) do
    if m.fake and m.move then
      m.x = Clamp(m.x + (math.random() - 0.5) * 0.006)
      m.y = Clamp(m.y + (math.random() - 0.5) * 0.006)
      m.heard = GetTime()
    end
  end
end

---------------------------------------------------------------------------
-- Refresh loop
---------------------------------------------------------------------------
function M:Refresh()
  if self.UpdateSelfPin then self:UpdateSelfPin() end
  if self.DropOffline then self:DropOffline() end
  for key, m in pairs(self.members) do
    if self:State(m) == "gone" then self.members[key] = nil end
  end
  if self.RefreshPins then self:RefreshPins() end
end

function M:Tick()
  self:MoveFakes()
  if self.SyncTick then self:SyncTick() end
  self:Refresh()
end

---------------------------------------------------------------------------
-- Privacy notice (plan section 5): once, before the first send. Step 1 sends nothing yet.
---------------------------------------------------------------------------
function M:MaybeNotice()
  if self.db.noticeShown or not self.settings.share then return end
  self.db.noticeShown = true
  self.Print(L.NOTICE)
end

---------------------------------------------------------------------------
-- Settings: shown in the /rq overview (user 2026-11-14: options belong in the UI, no chat commands).
-- mod.options follows the core's options contract: header / toggle / range / button / text entries with get/set.
-- `id` is ours (tests and SetOption); the core ignores it.
---------------------------------------------------------------------------
function M:SetOption(key, v)
  local s = self.settings
  if not s then return end
  if key == "size" then
    v = tonumber(v) or 1
    v = math.floor(math.max(0.5, math.min(2, v)) * 10 + 0.5) / 10
  else
    v = v and true or false
  end
  if s[key] == v then return end
  s[key] = v
  if key == "share" and self.OnShareChanged then self:OnShareChanged(v) end
  if key == "size" and self.ApplySize then self:ApplySize() end
  self:Refresh()
end

local function Toggle(id, label, tooltip, disabled)
  return { id = id, type = "toggle", label = L[label], tooltip = tooltip and L[tooltip] or nil, disabled = disabled,
    get = function() return M.settings and M.settings[id] or false end,
    set = function(v) M:SetOption(id, v) end }
end

M.options = {
  { type = "header", label = L.SEC_SHARING },
  Toggle("share", "SETTING_SHARE", "TT_SHARE"),
  { type = "header", label = L.SEC_DISPLAY },
  Toggle("worldmap", "SETTING_WORLDMAP"),
  Toggle("minimap", "SETTING_MINIMAP", "TT_MINIMAP"),
  Toggle("names", "SETTING_NAMES", nil, function() return not (M.settings and M.settings.worldmap) end),
  { id = "size", type = "range", label = L.SETTING_SIZE, min = 0.5, max = 2, step = 0.1, format = "%.1f",
    get = function() return M.settings and M.settings.size or 1 end,
    set = function(v) M:SetOption("size", v) end },
  { type = "header", label = L.SEC_TESTING },
  Toggle("selfPin", "SETTING_SELF", "TT_SELF"),
  { id = "fake", type = "toggle", label = L.SETTING_FAKE, tooltip = L.TT_FAKE,
    get = function() return M.fakeOn and true or false end,
    set = function(v) M:Fake(v) end },
  { id = "diag", type = "text", label = L.SETTING_DIAG, tooltip = L.TT_DIAG,
    lines = function() return M:DebugLines() end },
}

function M:Option(id)
  for _, o in ipairs(self.options) do if o.id == id then return o end end
end

-- Part of the suite: the core owns /rq, the overview window and its settings view (## Dependencies).
if GS and GS.NewModule then
  -- addon = ADDON is required, or the core never fires OnLoad (core Core.lua:235). We init from our own
  -- ADDON_LOADED below either way.
  local mod = GS:NewModule("Map", { addon = ADDON, slash = "map", title = L.TITLE,
    icon = "Interface\\Icons\\INV_Misc_Map_01", options = M.options })
  -- Overview window hooks (core Overview.lua): the button opens the world map; one status line.
  function mod:Open() M:OpenMap() end
  function mod:OverviewStatus() return M:StatusLine() end
  M.module = mod
end

---------------------------------------------------------------------------
-- Overview helpers (also usable without the core)
---------------------------------------------------------------------------
function M:OpenMap()
  if ToggleWorldMap then
    if not pcall(ToggleWorldMap) and WorldMapFrame then pcall(WorldMapFrame.Show, WorldMapFrame) end
  elseif WorldMapFrame then
    pcall(WorldMapFrame.Show, WorldMapFrame)
  end
end

-- "On the map: 3 · sharing on" (+ a warning while our messages don't get through)
function M:StatusLine()
  local n = 0
  for _, m in pairs(self.members) do
    if not m.fake and not m.isSelf and self:State(m) ~= "gone" then n = n + 1 end
  end
  local share = self.settings and self.settings.share
  local line = L.OV_STATUS:format(n, share and L.ON or L.OFF)
  if self.sync and self.sync.slow then line = line .. L.OV_SLOW end
  return line
end

---------------------------------------------------------------------------
-- Debug (Step 1 in-game checks: plan section 2 "Risk to check first")
---------------------------------------------------------------------------
local function F(v)
  if v == nil then return "nil" end
  if IsSecret(v) then return "<secret>" end
  if type(v) == "number" and v % 1 ~= 0 then return ("%.4f"):format(v) end
  return tostring(v)
end

function M:DebugLines()
  local lines = {}
  local function P(s) lines[#lines + 1] = (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local _, buildNum, _, iface = GetBuildInfo()
  P(("v%s, client %s, interface %s, core: %s"):format(self.version, F(buildNum), F(iface),
    GS and F(GS.version) or "not loaded"))
  P(("WOW_PROJECT_ID=%s  CAMELOT=%s  MAINLINE=%s  CLASSIC=%s"):format(F(WOW_PROJECT_ID), F(WOW_PROJECT_CAMELOT),
    F(WOW_PROJECT_MAINLINE), F(WOW_PROJECT_CLASSIC)))
  local hbdForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
  P("HereBeDragons takes its Forever branch: " .. (hbdForever and "|cff00ff00yes|r" or "|cffff4040NO (retail/other branch)|r"))
  local minors = LibStub and LibStub.minors or {}
  P(("LibStub: HereBeDragons-2.0 minor %s, Pins minor %s"):format(F(minors["HereBeDragons-2.0"]), F(minors["HereBeDragons-Pins-2.0"])))

  local mapID, x, y = self:ReadOwnPosition()
  local info = mapID and SafeCall(C_Map.GetMapInfo, mapID)
  P(("Client: map %s (%s) x=%s y=%s"):format(F(mapID), info and F(info.name) or "?", F(x), F(y)))
  local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
  if HBD then
    local hz, htype = SafeCall(HBD.GetPlayerZone, HBD)
    local hx, hy, hmap = SafeCall(HBD.GetPlayerZonePosition, HBD)
    P(("HBD:    map %s (type %s) x=%s y=%s"):format(F(hmap or hz), F(htype), F(hx), F(hy)))
    -- HBD computes the zone position from UnitPosition + its own map data/transforms; the client from C_Map.
    -- Agreement means HBD's data places pins correctly in this zone.
    if mapID and hx and hmap == mapID then
      local d = math.max(math.abs(hx - x), math.abs(hy - y))
      P(d < 0.005 and ("|cff00ff00HBD matches the client|r (diff %.4f)"):format(d)
        or ("|cffff4040HBD differs from the client by %.4f – pins would be misplaced here|r"):format(d))
    elseif mapID then
      P("|cffffff00HBD and client disagree on the map (or HBD has no position) – check the pin by eye|r")
    end
  else
    P("|cffff4040HereBeDragons not loaded|r")
  end

  local n, fresh, stale = 0, 0, 0
  for _, m in pairs(self.members) do
    n = n + 1
    if self:State(m) == "stale" then stale = stale + 1 else fresh = fresh + 1 end
  end
  local w, mm
  if self.CountPins then w, mm = self:CountPins() end
  P(("Members %d (fresh %d, stale %d); pins: world %s, minimap %s; minimap zoom %s, indoors %s, rotate %s"):format(
    n, fresh, stale, F(w), F(mm), F(Minimap and SafeCall(Minimap.GetZoom, Minimap)), F(SafeCall(IsIndoors)),
    F(C_CVar and SafeCall(C_CVar.GetCVar, "rotateMinimap"))))
  if self.SyncDebug then self:SyncDebug(P) end
  if self.db and self.db.lastError then P("Last error: " .. F(self.db.lastError.msg)) end
  return lines
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
M.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "GUILD_ROSTER_UPDATE" then
    if not GS then M.Call(Shim.ReadRoster, Shim) end -- the core reads its own roster
  elseif event == "ADDON_LOADED" then
    if arg1 == ADDON then M.Call(M.InitDB, M) end
  elseif event == "PLAYER_LOGIN" then
    if not M.db then M.Call(M.InitDB, M) end
    C_Timer.NewTicker(M.C.TICK, function() M.Call(M.Tick, M) end)
    C_Timer.After(M.C.NOTICE_DELAY, function() M.Call(M.MaybeNotice, M) end)
    M.Call(M.Refresh, M)
  elseif M.db then
    M.Call(M.Refresh, M)
  end
end)
