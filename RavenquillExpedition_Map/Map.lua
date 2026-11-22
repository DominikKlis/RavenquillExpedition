local ADDON, ns = ...
local L = ns.L
local GS = RavenquillExpedition
local IsSecret, SafeCall, Bool, Plain = GS.IsSecret, GS.SafeCall, GS.Bool, GS.Plain

local M = GS:NewModule("Map", {
  addon = ADDON, api = 2, slash = "map", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Map_01",
  sv = "RavenquillExpeditionMapDB", dbVersion = 1, locale = ns.Locales,
  defaults = {
    share = true,
    worldmap = true,
    minimap = true,
    names = false,
    hideGroup = true,
    size = 1.0,
    selfPin = false,
  },
})
ns.Map = M
_G.RavenquillExpeditionMap = M

M.version = GS:AddOnVersion(ADDON)

M.C = {
  TICK = 2,
  INTERVAL_MIN = 5,
  HEARTBEAT = 300,
  FADE_MIN = 180,
  BEAT_OF_FADE = 0.75,
  STATIONARY_FADE = 1.5,
  REMOVE_FACTOR = 2,
  MINIMAP_FRESH = 45,
  FAKE_MOVE = 10,
  NOTICE_DELAY = 8,
  GUILD_TARGET = 60,
  BUSY_FACTOR = 1.5,
  ACTIVE_WINDOW = 600,
  MOVE_MIN = 0.003,
  STILL_EPS = 0.001,
  STILL_AFTER = 20,
  JITTER_MIN = 30,
  JITTER_WINDOW_MIN = 60,
  JITTER_WINDOW_MAX = 300,
  SLOW_INTERVAL = 300,
  STARVE = 10,
  FUTURE_SLACK = 120,
  HOLD_UNKNOWN = 60,
  ROSTER_EVERY = 120,
}

function M:OnLoad()
  local s = self.settings
  if s.size < 0.5 or s.size > 2 then s.size = 1.0 end
end

M.members = {}
M.lastHeard = {}

function M:FadeAfter(m)
  local C = self.C
  if m.flags and m.flags.s then return C.STATIONARY_FADE * math.max(C.HEARTBEAT, self:Interval()) end
  return math.max(C.FADE_MIN, 2 * self:Interval())
end

function M:Age(m) return GetTime() - (m.heard or 0) end

function M:State(m)
  if m.isSelf then return "fresh" end
  local age, fade = self:Age(m), self:FadeAfter(m)
  if age >= fade * self.C.REMOVE_FACTOR then return "gone" end
  if age >= fade then return "stale" end
  return "fresh"
end

local function PositionXY(pos)
  local x, y
  if pos.GetXY then x, y = SafeCall(pos.GetXY, pos) else x, y = pos.x, pos.y end
  return Plain(x, "number"), Plain(y, "number")
end

local function OffMap(x, y)
  return not x or not y or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1
end

function M:ReadOwnPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
  local mapID = Plain(SafeCall(C_Map.GetBestMapForUnit, "player"), "number")
  if not mapID then return end
  local pos = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" or IsSecret(pos) then return end
  local x, y = PositionXY(pos)
  if OffMap(x, y) then return end
  return mapID, x, y
end

function M:ReadPlayer()
  local _, class = SafeCall(UnitClass, "player")
  return {
    level = Plain(SafeCall(UnitLevel, "player"), "number") or 0,
    class = Plain(class, "string"),
    ghost = Bool(SafeCall(UnitIsDeadOrGhost, "player")),
    taxi = Bool(SafeCall(UnitOnTaxi, "player")),
  }
end

function M:UpdateSelfPin()
  local key = "@self"
  if not self.settings.selfPin then self.members[key] = nil; return end
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then self.members[key] = nil; return end
  local me = self:ReadPlayer()
  self.members[key] = {
    key = key, name = GS:PlayerKey() or UNKNOWNOBJECT, mapID = mapID, x = x, y = y, level = me.level, class = me.class,
    heard = GetTime(), flags = { g = me.ghost or nil, t = me.taxi or nil }, isSelf = true,
  }
end

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
  if not mapID then self:Print(L.FAKE_NOPOS); return end
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

function M:Refresh()
  if not self.settings then return end
  self:UpdateSelfPin()
  self:DropOffline()
  for key, m in pairs(self.members) do
    if self:State(m) == "gone" then self.members[key], self.lastHeard[key] = nil, m.heard end
  end
  self:RefreshPins()
  if self.RenderPage then self:RenderPage() end
end

function M:NeedsTick()
  local s = self.settings
  if not s then return false end
  return s.share or s.selfPin or self.fakeOn or next(self.members) ~= nil
    or (self.sync ~= nil and next(self.sync.pending) ~= nil)
end

function M:Tick()
  self:MoveFakes()
  self:SyncTick()
  self:Refresh()
  if not self:NeedsTick() and self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

function M:Wake()
  if self.ticker or not GS.loggedIn or not self:NeedsTick() then return end
  self.ticker = C_Timer.NewTicker(self.C.TICK, function() GS:Call(M.Tick, M) end)
end

function M:MaybeNotice()
  if self.db.noticeShown or not self.settings.share then return end
  self.db.noticeShown = true
  self:Print(L.NOTICE)
end

function M:OnOptionChanged(key, v)
  if key == "share" then self:OnShareChanged(v) end
  if key == "size" then
    self.settings.size = math.floor(math.max(0.5, math.min(2, tonumber(v) or 1)) * 10 + 0.5) / 10
    self:ApplySize()
  end
  self:Refresh()
  self:Wake()
end

M:SetOptions({
  { type = "header", label = L.SEC_SHARING },
  { type = "toggle", key = "share", label = L.SETTING_SHARE, tooltip = L.TT_SHARE },
  { type = "header", label = L.SEC_DISPLAY },
  { type = "toggle", key = "worldmap", label = L.SETTING_WORLDMAP, tooltip = L.TT_WORLDMAP },
  { type = "toggle", key = "minimap", label = L.SETTING_MINIMAP, tooltip = L.TT_MINIMAP },
  { type = "toggle", key = "names", label = L.SETTING_NAMES, tooltip = L.TT_NAMES,
    disabled = function() return not (M.settings and M.settings.worldmap) end },
  { type = "toggle", key = "hideGroup", label = L.SETTING_HIDE_GROUP, tooltip = L.TT_HIDE_GROUP },
  { type = "range", key = "size", label = L.SETTING_SIZE, tooltip = L.TT_SIZE, min = 0.5, max = 2, step = 0.1, format = "%.1f" },
  { type = "header", label = L.SEC_TESTING },
  { type = "toggle", key = "selfPin", label = L.SETTING_SELF, tooltip = L.TT_SELF },
  { id = "fake", type = "toggle", label = L.SETTING_FAKE, tooltip = L.TT_FAKE,
    get = function() return M.fakeOn and true or false end,
    set = function(v) M:Fake(v) end },
})

M.openLabel = L.OPEN_LABEL
function M:OverviewDiagnostics() return self:DebugLines() end

function M:Open()
  if InCombatLockdown and InCombatLockdown() then self:Print(L.MAP_COMBAT); return end
  if ToggleWorldMap then
    if not pcall(ToggleWorldMap) and WorldMapFrame then pcall(WorldMapFrame.Show, WorldMapFrame) end
  elseif WorldMapFrame then
    pcall(WorldMapFrame.Show, WorldMapFrame)
  end
end

function M:GuildmatesOnMap()
  local out = {}
  for _, m in pairs(self.members) do
    if not m.fake and not m.isSelf and self:PositionState(m) == "onMap" then out[#out + 1] = m end
  end
  table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return out
end

function M:OverviewStatus()
  local share = self.settings and self.settings.share
  local line = L.OV_STATUS:format(#self:GuildmatesOnMap(), share and L.ON or L.OFF)
  if GS:CommState().slow then line = line .. L.OV_SLOW end
  return line
end

function M:OverviewHeadline()
  local onMap = self:GuildmatesOnMap()
  local first = onMap[1]
  if not first then return { line = L.OV_HEAD_NONE } end
  local zone = M.ZoneText(first)
  return { line = L.OV_HEAD:format(#onMap, zone and L.OV_HEAD_WHERE:format(first.name, zone) or first.name) }
end

local function F(v)
  if v == nil then return "nil" end
  if IsSecret(v) then return "<secret>" end
  if type(v) == "number" and v % 1 ~= 0 then return ("%.4f"):format(v) end
  return tostring(v)
end

local function VersionLines(self, P)
  local _, buildNum, _, iface = GetBuildInfo()
  P(("v%s, client %s, interface %s, core: %s"):format(self.version, F(buildNum), F(iface), F(GS.version)))
  P(("WOW_PROJECT_ID=%s  CAMELOT=%s  MAINLINE=%s  CLASSIC=%s"):format(F(WOW_PROJECT_ID), F(WOW_PROJECT_CAMELOT),
    F(WOW_PROJECT_MAINLINE), F(WOW_PROJECT_CLASSIC)))
  local hbdForever = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
  P("HereBeDragons takes its Forever branch: " .. (hbdForever and "|cff00ff00yes|r" or "|cffff4040NO (retail/other branch)|r"))
  local minors = LibStub and LibStub.minors or {}
  P(("LibStub: our HereBeDragons-2.0 minor %s, Pins minor %s (private names); shared Pins minor %s"):format(F(minors["HereBeDragons-2.0-RQE"]), F(minors["HereBeDragons-Pins-2.0-RQE"]), F(minors["HereBeDragons-Pins-2.0"])))
end

local function CompareWithHBD(P, HBD, mapID, x, y)
  local hz, htype = SafeCall(HBD.GetPlayerZone, HBD)
  local hx, hy, hmap = SafeCall(HBD.GetPlayerZonePosition, HBD)
  P(("HBD:    map %s (type %s) x=%s y=%s"):format(F(hmap or hz), F(htype), F(hx), F(hy)))
  if not mapID then return end
  if not (hx and hmap == mapID) then
    return P("|cffffff00HBD and client disagree on the map (or HBD has no position) – check the pin by eye|r")
  end
  local d = math.max(math.abs(hx - x), math.abs(hy - y))
  P(d < 0.005 and ("|cff00ff00HBD matches the client|r (diff %.4f)"):format(d)
    or ("|cffff4040HBD differs from the client by %.4f – pins would be misplaced here|r"):format(d))
end

local function PositionLines(self, P)
  local mapID, x, y = self:ReadOwnPosition()
  local info = mapID and SafeCall(C_Map.GetMapInfo, mapID)
  P(("Client: map %s (%s) x=%s y=%s"):format(F(mapID), info and F(info.name) or "?", F(x), F(y)))
  local HBD = LibStub and LibStub("HereBeDragons-2.0-RQE", true)
  if not HBD then return P("|cffff4040HereBeDragons not loaded|r") end
  CompareWithHBD(P, HBD, mapID, x, y)
end

local function MembersLine(self)
  local n, fresh, stale = 0, 0, 0
  for _, m in pairs(self.members) do
    n = n + 1
    if self:State(m) == "stale" then stale = stale + 1 else fresh = fresh + 1 end
  end
  local w, mm = self:CountPins()
  return ("Members %d (fresh %d, stale %d); pins: world %s, minimap %s; minimap zoom %s, indoors %s, rotate %s"):format(
    n, fresh, stale, F(w), F(mm), F(Minimap and SafeCall(Minimap.GetZoom, Minimap)), F(SafeCall(IsIndoors)),
    F(C_CVar and SafeCall(C_CVar.GetCVar, "rotateMinimap")))
end

function M:DebugLines()
  local lines = {}
  local function P(s) lines[#lines + 1] = (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  VersionLines(self, P)
  PositionLines(self, P)
  P(MembersLine(self))
  self:SyncDebug(P)
  local err = RavenquillExpeditionDB and RavenquillExpeditionDB.lastError
  if err then P("Last error (suite): " .. F(err.msg)) end
  return lines
end

function M:OnLogin()
  self:Wake()
  self:After(self.C.NOTICE_DELAY, function() self:MaybeNotice() end)
  self:Refresh()
  self:SyncLogin()
end

local function Refresh() M:Refresh() end
M:RegisterEvent("PLAYER_ENTERING_WORLD", function(self, _, isReloadingUi)
  if Bool(isReloadingUi) then self:SyncReloaded() end
  self:Refresh()
end)
M:RegisterEvent("ZONE_CHANGED_NEW_AREA", Refresh)
