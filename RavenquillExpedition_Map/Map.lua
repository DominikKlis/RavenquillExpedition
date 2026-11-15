-- Ravenquill Expedition: Map – settings (shown in the /rq overview), member store, own position, test pins.
-- Pins.lua draws ns.Map.members on the world map and minimap (HereBeDragons).
-- Sync.lua sends our position and fills members from guildmates' messages (through the core's state lane).
-- A module on the core API 2 (docs/module-api.md): SavedVariables, locale, events, options and sync are the core's.
local ADDON, ns = ...
local L = ns.L
local GS = RavenquillExpedition
local IsSecret, SafeCall, Bool = GS.IsSecret, GS.SafeCall, GS.Bool

local M = {}
ns.Map = M
_G.RavenquillExpeditionMap = M -- for /dump and the Dev addon's tests

M.version = GS:AddOnVersion(ADDON)

M.C = {
  TICK = 2,             -- s between refreshes (own position, fades, minimap rule)
  INTERVAL_MIN = 5,     -- floor of the adaptive send interval (Sync.lua); user choice 2026-11-15: 5 s while moving
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
-- The module (core Module.lua). SavedVariables hold settings only – other players' positions are never saved.
---------------------------------------------------------------------------
local mod = GS:NewModule("Map", {
  addon = ADDON, api = 2, slash = "map", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Map_01",
  sv = "RavenquillExpeditionMapDB", dbVersion = 1, defaults = M.DEFAULTS, locale = ns.Locales,
})
M.mod = mod

function mod:OnLoad()
  local s = self.settings
  if s.size < 0.5 or s.size > 2 then s.size = 1.0 end
  M.db, M.settings = self.db, s
end

---------------------------------------------------------------------------
-- Member store: members[key] = { key, name, mapID, x, y, level, class, heard (GetTime),
--   flags = { s = stationary, t = taxi, g = ghost }, fake = bool, isSelf = bool }
-- Sync.lua fills it from received messages; Map.lua adds the own and test pins.
---------------------------------------------------------------------------
M.members = {}

-- Seconds after the last news at which a pin fades (dimmed). M:Interval is Sync.lua's.
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
-- Own position. nil (or 0,0) means "no position" (instances, some loading states).
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
    key = key, name = GS:PlayerKey() or UNKNOWNOBJECT, mapID = mapID, x = x, y = y,
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
  if not mapID then mod:Print(L.FAKE_NOPOS); return end
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
  self:Wake()
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
-- Refresh loop: a 2 s ticker that runs only while there is something to do (sharing on, pins shown or held).
-- C_Timer.NewTicker rather than mod:Every: a ticker keeps its place among timers that fire at the same moment,
-- so a tick sees the same position as before (the send times in harness_compat.lua depend on it).
---------------------------------------------------------------------------
function M:Refresh()
  if not self.settings then return end
  self:UpdateSelfPin()
  if self.DropOffline then self:DropOffline() end
  for key, m in pairs(self.members) do
    if self:State(m) == "gone" then self.members[key] = nil end
  end
  if self.RefreshPins then self:RefreshPins() end
end

function M:NeedsTick()
  local s = self.settings
  if not s then return false end
  return s.share or s.selfPin or self.fakeOn or next(self.members) ~= nil
    or (self.sync ~= nil and next(self.sync.pending) ~= nil)
end

function M:Tick()
  self:MoveFakes()
  if self.SyncTick then self:SyncTick() end
  self:Refresh()
  if not self:NeedsTick() and self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

-- start the ticker when it's needed and not running (after login only)
function M:Wake()
  if self.ticker or not self.loggedIn or not self:NeedsTick() then return end
  self.ticker = C_Timer.NewTicker(self.C.TICK, function() GS:Call(M.Tick, M) end)
end

---------------------------------------------------------------------------
-- Privacy notice: once, before the first send.
---------------------------------------------------------------------------
function M:MaybeNotice()
  if self.db.noticeShown or not self.settings.share then return end
  self.db.noticeShown = true
  mod:Print(L.NOTICE)
end

---------------------------------------------------------------------------
-- Settings: shown in the /rq overview (user 2026-11-14: options belong in the UI, no chat commands).
-- Entries follow the core's options contract (header / toggle / range / button / text); `id` names them for
-- mod:Option(id).
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
  self:Wake()
end

local function Toggle(id, label, tooltip, disabled)
  return { id = id, type = "toggle", label = L[label], tooltip = tooltip and L[tooltip] or nil, disabled = disabled,
    get = function() return M.settings and M.settings[id] or false end,
    set = function(v) M:SetOption(id, v) end }
end

mod:SetOptions({
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
})

-- Overview window hooks (core Overview.lua): the button opens the world map; one status line.
function mod:Open() M:OpenMap() end
function mod:OverviewStatus() return M:StatusLine() end

---------------------------------------------------------------------------
-- Overview helpers
---------------------------------------------------------------------------
-- Opening the map from addon code runs Blizzard's whole show path tainted; in combat its protected calls (quest pins:
-- SetPassThroughButtons) are then blocked (ADDON_ACTION_BLOCKED). So in combat we only point to the key.
function M:OpenMap()
  if InCombatLockdown and InCombatLockdown() then mod:Print(L.MAP_COMBAT); return end
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
  if GS:CommState().slow then line = line .. L.OV_SLOW end
  return line
end

---------------------------------------------------------------------------
-- Diagnostics (the copy box in /rq map)
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
  P(("v%s, client %s, interface %s, core: %s"):format(self.version, F(buildNum), F(iface), F(GS.version)))
  P(("WOW_PROJECT_ID=%s  CAMELOT=%s  MAINLINE=%s  CLASSIC=%s"):format(F(WOW_PROJECT_ID), F(WOW_PROJECT_CAMELOT),
    F(WOW_PROJECT_MAINLINE), F(WOW_PROJECT_CLASSIC)))
  local hbdForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
  P("HereBeDragons takes its Forever branch: " .. (hbdForever and "|cff00ff00yes|r" or "|cffff4040NO (retail/other branch)|r"))
  local minors = LibStub and LibStub.minors or {}
  P(("LibStub: our HereBeDragons-2.0 minor %s, Pins minor %s (private names); shared Pins minor %s"):format(F(minors["HereBeDragons-2.0-RQE"]), F(minors["HereBeDragons-Pins-2.0-RQE"]), F(minors["HereBeDragons-Pins-2.0"])))

  local mapID, x, y = self:ReadOwnPosition()
  local info = mapID and SafeCall(C_Map.GetMapInfo, mapID)
  P(("Client: map %s (%s) x=%s y=%s"):format(F(mapID), info and F(info.name) or "?", F(x), F(y)))
  local HBD = LibStub and LibStub("HereBeDragons-2.0-RQE", true)
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
  local err = RavenquillExpeditionDB and RavenquillExpeditionDB.lastError
  if err then P("Last error (suite): " .. F(err.msg)) end
  return lines
end

---------------------------------------------------------------------------
-- Lifecycle (the core calls these; events through mod:RegisterEvent run under RQ:Call)
---------------------------------------------------------------------------
function mod:OnLogin()
  M.loggedIn = true
  M:Wake()
  self:After(M.C.NOTICE_DELAY, function() M:MaybeNotice() end)
  M:Refresh()
  if M.SyncLogin then M:SyncLogin() end
end

local function Refresh() M:Refresh() end
mod:RegisterEvent("PLAYER_ENTERING_WORLD", Refresh)
mod:RegisterEvent("ZONE_CHANGED_NEW_AREA", Refresh)
