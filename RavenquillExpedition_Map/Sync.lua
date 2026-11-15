-- Ravenquill Expedition: Map – position sync (dev/PLAN.md section 1). Own prefix, GUILD only, lowest priority on the client.
--   P;<mapID>;<x>;<y>;<level>;<class>;<ts>;<flags>;<n>   numbers base36; x/y 0..46655 (3 digits, sub-yard)
--                                                          flags: s stationary, t taxi, g dead/ghost; n = sender's
--                                                          estimate of active senders (receivers adopt the max)
--   L;<ts>                                                 "leaving" – best effort (share off, logout)
-- Not the core's shared "GSuite1" lane: its 1 msg / 30 s budget is for all core modules, and position traffic
-- would starve them. Instead the map yields to every other GUILD addon message this client sends (hook below).
local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local SafeCall, IsSecret, Bool = M.SafeCall, M.IsSecret, M.Bool

local PREFIX = "RQEMap1"
M.PREFIX = PREFIX
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_IDX = {}
for i, c in ipairs(CLASSES) do CLASS_IDX[c] = i end
local XY_MAX = 46655 -- 36^3 - 1
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local C = M.C
C.GUILD_TARGET = 10     -- map messages per minute for the whole guild (Overlord's hard ceiling, SyncGuild.lua:44)
C.BUSY_FACTOR = 1.5     -- heard more than 1.5 × target in 60 s -> double our interval
C.ACTIVE_WINDOW = 600   -- senders heard within 10 min count as active
C.MOVE_MIN = 0.003      -- map units moved since the last send that count as "moved"
C.STILL_EPS = 0.001     -- staying within this of an anchor point counts as standing still (any walking speed
C.STILL_AFTER = 20      -- drifts out of it); 20 s like that -> stationary
C.JITTER_MIN = 30      -- first send after login: 30 s + a random share of a window sized to the guild's
C.JITTER_WINDOW_MIN, C.JITTER_WINDOW_MAX = 60, 300 -- online members × 6 s, so a mass login is spread out too
C.ECHO_TIMEOUT = 120
C.SLOW_INTERVAL = 300   -- no echo: one probe per 5 min until one comes back (Overlord SyncGuild.lua:35-37)
C.QUIET_ANY = 15        -- skip if this client sent any GUILD addon message within 15 s ...
C.MAX_ANY_60 = 3        -- ... or 3 or more within 60 s
C.STARVE = 120          -- blocked this long (or 2 × interval) -> the 3-per-60-s rule is waived once
C.HOLD_THROTTLED = 30   -- also after a send error
C.INTAKE_PER_MIN = 6    -- per sender; a correct client sends at most 2 a minute
C.FUTURE_SLACK = 120
C.HOLD_UNKNOWN = 60     -- sender not (yet) in the roster: hold the pin this long
C.ROSTER_EVERY = 120    -- refresh the roster this often while remote pins exist (offline detection)

local S = {
  sends = {},          -- GetTime() of every GUILD addon message this client sent (any addon)
  hooked = false,
  heard = {},          -- GetTime() of map messages from others (busy rule)
  senders = {},        -- [key] = GetTime() last heard (active count)
  nHeard = {},         -- [key] = { n = their estimate, t = GetTime() }
  intake = {},         -- [key] = { t, n }
  pending = {},        -- [key] = { m = member, since = GetTime() } – sender not in the roster yet
  rejected = {},       -- [reason] = count
  sent = 0, echoed = 0, lost = 0, received = 0,
}
M.sync = S

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function b36(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  local s = ""
  repeat
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  until n == 0
  return s
end
local function n36(s)
  if type(s) ~= "string" or s == "" or #s > 8 or not s:match("^[0-9a-z]+$") then return nil end
  return tonumber(s, 36)
end
M.b36, M.n36 = b36, n36

local function Split(msg)
  local t = {}
  for f in (msg .. ";"):gmatch("([^;]*);") do t[#t + 1] = f end
  return t
end

local function Plain(v, kind) if type(v) == kind and not IsSecret(v) then return v end end

local function Prune(list, window, now)
  local i = 1
  while list[i] and now - list[i] > window do i = i + 1 end
  if i > 1 then for _ = 1, i - 1 do table.remove(list, 1) end end
end

local function Reject(reason) S.rejected[reason] = (S.rejected[reason] or 0) + 1 end

local function MaxLevel()
  local n = Plain(SafeCall(GetMaxPlayerLevel), "number")
  return math.max(60, n or 60)
end

local StripRealm = M.StripRealm -- only our own realm's suffix (code review #6)

-- When the first message after login may go out. Each client keeps one random fraction; the window grows with the
-- number of guildmates online (an upper bound on senders), so 40 people logging in together spread over ~4 min
-- instead of all sending within the same minute (harness_sync.lua section 6).
local function FirstSendAt()
  if S.firstAt then return S.firstAt end -- set by "share on"
  if not S.loginAt then return math.huge end
  local online = M:OnlineCount()
  local window = math.max(C.JITTER_WINDOW_MIN, math.min(C.JITTER_WINDOW_MAX, online * 60 / C.GUILD_TARGET))
  return S.loginAt + C.JITTER_MIN + S.firstRand * window
end

local function IsMe(key)
  local me = M:PlayerKey()
  return me ~= nil and (key == me or StripRealm(key) == me)
end

---------------------------------------------------------------------------
-- Count every GUILD addon message this client sends, from any addon (plan section 1, "Lowest priority").
-- [U] that hooksecurefunc on C_ChatInfo.SendAddonMessage sees other addons' calls on Forever – `debug` shows it.
---------------------------------------------------------------------------
if hooksecurefunc and C_ChatInfo and C_ChatInfo.SendAddonMessage then
  S.hooked = pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", function(_, _, chatType)
    if type(chatType) == "string" and not IsSecret(chatType) and chatType:upper() == "GUILD" then
      S.sends[#S.sends + 1] = GetTime()
    end
  end) and true or false
end

local function LastAnySend()
  if S.hooked then return S.sends[#S.sends] end
  local core = M.core and M.core.Comm
  local t = S.lastOwn
  if core and type(core.lastSent) == "number" and (not t or core.lastSent > t) then t = core.lastSent end
  return t
end

---------------------------------------------------------------------------
-- Pacing
---------------------------------------------------------------------------
-- Senders we heard ourselves (plus us). This, not the adopted maximum, is what we send as n - otherwise
-- clients echo each other's peak forever after people leave (code review #4).
function M:DirectSenders()
  local now, count = GetTime(), 0
  for key, t in pairs(S.senders) do
    if now - t <= C.ACTIVE_WINDOW then count = count + 1 else S.senders[key] = nil end
  end
  if self.settings and self.settings.share then count = count + 1 end
  return math.max(1, count)
end

-- What we pace by: our own count, or a higher one somebody else heard (a fresh client learns the guild's size
-- from the first message), capped at the online roster count so one bad n can't stall us.
function M:ActiveSenders()
  local now, maxN = GetTime(), 0
  for key, h in pairs(S.nHeard) do
    if now - h.t <= C.ACTIVE_WINDOW then maxN = math.max(maxN, h.n) else S.nHeard[key] = nil end
  end
  local online = self:OnlineCount()
  if online > 0 then maxN = math.min(maxN, online) end
  return math.max(self:DirectSenders(), maxN)
end

-- The guild's update interval (also used by receivers for fading). forSend adds our own slow mode.
function M:Interval(forSend)
  local base = math.max(C.INTERVAL_MIN, self:ActiveSenders() * 60 / C.GUILD_TARGET)
  Prune(S.heard, 60, GetTime())
  if #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET then base = base * 2 end
  if forSend and S.slow then base = math.max(base, C.SLOW_INTERVAL) end
  return base
end

local function SendRaw(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "error" end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return "error" end
  if res == nil or res == true or res == 0 then return "ok" end
  if res == 3 or res == 8 then return "throttled" end -- [U] live values (as GCA / core Comm.lua)
  return "error"
end

local function CanSend()
  if not M.settings.share then return false, "sharing off" end
  if not S.prefixOk then return false, "prefix not registered" end
  if not Bool(SafeCall(IsInGuild)) then return false, "not in a guild" end
  if M:InInstance() then return false, "instance" end
  if Bool(SafeCall(InCombatLockdown)) then return false, "combat" end
  return true
end

---------------------------------------------------------------------------
-- Sending (called every tick; never queues – it sends the current position or nothing)
---------------------------------------------------------------------------
local function FlagString(stationary, taxi, ghost)
  return (stationary and "s" or "") .. (taxi and "t" or "") .. (ghost and "g" or "")
end

function M:EncodePosition(mapID, x, y, level, class, ts, flags, n)
  return table.concat({ "P", b36(mapID), b36(x * XY_MAX + 0.5), b36(y * XY_MAX + 0.5), b36(level),
    b36(CLASS_IDX[class] or 0), b36(ts), flags or "", b36(n) }, ";")
end

function M:SyncTick()
  local now = GetTime()
  Prune(S.sends, 60, now)
  -- delivery check: our own message must come back (plan section 1, "Delivery check")
  if S.echoWait and now - S.echoWait > C.ECHO_TIMEOUT then
    S.echoWait = nil
    S.lost = S.lost + 1
    if not S.slow then
      S.slow = true
      if not S.slowSaid then S.slowSaid = true; self.Print(L.SLOW_MODE) end
    end
  end
  self:CheckPending(now)
  if next(self.members) and now - (S.rosterAt or 0) > C.ROSTER_EVERY then
    S.rosterAt = now
    self:RequestRoster()
  end

  -- own movement state: moving = left a small circle around the anchor (slow walkers drift out of it too)
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then S.skip = "no position"; return end
  local a = S.anchor
  if not a or a[1] ~= mapID or math.max(math.abs(a[2] - x), math.abs(a[3] - y)) > C.STILL_EPS then
    S.anchor, S.lastMoveAt = { mapID, x, y }, now
  end
  local taxi = Bool(SafeCall(UnitOnTaxi, "player"))
  local ghost = Bool(SafeCall(UnitIsDeadOrGhost, "player"))
  local stationary = not taxi and now - (S.lastMoveAt or now) >= C.STILL_AFTER
  local flags = FlagString(stationary, taxi, ghost)

  -- why send?
  local last, want = S.last, nil
  local interval = self:Interval(true)
  if not last then
    if now >= FirstSendAt() then want = "first" end
  elseif mapID ~= last.mapID and not taxi then want = "zone" -- on a taxi: take-off, landing, heartbeat only
  elseif flags ~= last.flags then want = "flags"
  elseif not taxi and not stationary and math.max(math.abs(x - last.x), math.abs(y - last.y)) >= C.MOVE_MIN then
    want = "moved"
  elseif now - last.t >= math.max(C.HEARTBEAT, interval) then want = "heartbeat"
  end
  if not want then S.skip = nil; S.blockedSince = nil; return end

  -- may we?
  local ok, why = CanSend()
  if not ok then S.skip = why; return end
  if now < (S.hold or 0) then S.skip = "throttled (hold)"; return end
  if last and now - last.t < interval then S.skip = "interval"; return end
  -- lowest priority: yield to everything else this client sends. After being blocked for max(2 min, 2 x interval)
  -- one message goes through anyway, or a chatty neighbour (GuildMap sends every ~5 s) would silence us for good
  -- (code review #2).
  local starving = S.blockedSince and now - S.blockedSince >= math.max(C.STARVE, 2 * interval)
  if not starving then
    local lastAny = LastAnySend()
    local why
    local core = M.core and M.core.Comm
    if core and type(core.q) == "table" and core.q[1] then
      why = "Ravenquill Expedition modules are waiting to send" -- they go first (code review #5)
    elseif lastAny and now - lastAny < C.QUIET_ANY then
      why = "another addon sent < 15 s ago"
    elseif S.hooked and #S.sends >= C.MAX_ANY_60 then
      why = "3+ guild addon messages in 60 s"
    end
    if why then S.skip = why; S.blockedSince = S.blockedSince or now; return end
  end

  local level = Plain(SafeCall(UnitLevel, "player"), "number") or 0
  local _, class = SafeCall(UnitClass, "player")
  class = Plain(class, "string")
  if level < 1 or not CLASS_IDX[class or ""] then S.skip = "level/class unknown"; return end
  local msg = self:EncodePosition(mapID, x, y, level, class, self:Now(), flags, self:DirectSenders())
  local r = SendRaw(msg)
  if r == "throttled" then S.hold = now + C.HOLD_THROTTLED; S.skip = "throttled"; return end
  if r ~= "ok" then S.hold = now + C.HOLD_THROTTLED; S.skip = "send error"; return end
  if not S.hooked then S.lastOwn = now end
  S.last = { mapID = mapID, x = x, y = y, flags = flags, t = now, why = want }
  S.sent = S.sent + 1
  S.echoWait = S.echoWait or now
  S.skip, S.blockedSince = nil, nil
end

-- Best effort only: may not get out at logout [U]; never sent inside an instance (house rule).
function M:SendLeave()
  if not S.prefixOk or self:InInstance() or not Bool(SafeCall(IsInGuild)) or not S.last then return end
  SendRaw("L;" .. b36(self:Now()))
  S.last = nil
end

function M:OnShareChanged(on)
  if on then
    S.firstAt = GetTime() -- send soon (still paced); the notice was already shown
  else
    self:SendLeave()
    S.echoWait = nil
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- Field checks before anything reaches HereBeDragons (it raises errors on bad input, Pins-2.0.lua:608, :741).
function M:DecodePosition(f)
  if #f ~= 9 then return nil, "field count" end
  local mapID, xi, yi = n36(f[2]), n36(f[3]), n36(f[4])
  local level, cls, ts, flags, n = n36(f[5]), n36(f[6]), n36(f[7]), f[8], n36(f[9])
  if not (mapID and xi and yi and level and cls and ts and n) then return nil, "not a number" end
  if mapID < 1 or mapID > 1e6 or not SafeCall(C_Map.GetMapInfo, mapID) then return nil, "unknown map" end
  if xi > XY_MAX or yi > XY_MAX or (xi == 0 and yi == 0) then return nil, "position range" end
  if level < 1 or level > MaxLevel() then return nil, "level" end
  if not CLASSES[cls] then return nil, "class" end
  if ts > self:Now() + C.FUTURE_SLACK then return nil, "future timestamp" end
  if not flags:match("^[stg]*$") or #flags > 3 then return nil, "flags" end
  if n < 1 or n > 1000 then return nil, "sender estimate" end
  local fl = {}
  for c in flags:gmatch(".") do fl[c] = true end
  return { mapID = mapID, x = xi / XY_MAX, y = yi / XY_MAX, level = level, class = CLASSES[cls], ts = ts,
    flags = fl, n = n }
end

local function Store(key, m)
  local old = M.members[key]
  if old and old.ts and m.ts < old.ts then Reject("older than shown"); return end
  M.members[key] = m
  if M.RefreshPins then M:RefreshPins() end
end

function M:CheckPending(now)
  for key, p in pairs(S.pending) do
    local gm = self:IsGuildMember(key)
    if gm ~= false then
      S.pending[key] = nil
      Store(key, p.m) -- keeps heard = when it arrived, so its age stays real
    elseif now - p.since > C.HOLD_UNKNOWN then
      S.pending[key] = nil
      Reject("not in guild roster")
    end
  end
end

function M:OnAddonMessage(prefix, text, chan, sender)
  if Plain(prefix, "string") ~= PREFIX then return end
  text, chan, sender = Plain(text, "string"), Plain(chan, "string"), Plain(sender, "string")
  if not (text and sender) or chan ~= "GUILD" then return end
  local key = self:NormName(sender)
  if not key then return end
  if IsMe(key) then
    S.echoRaw = sender
    if S.echoWait or S.slow then
      S.echoWait = nil
      S.echoed = S.echoed + 1
      S.slow = false
    end
    return
  end
  S.lastRaw, S.lastRawKey = sender, key
  if self:InInstance() then return end -- nothing read in instances (plan section 1)
  local now = GetTime()
  local it = S.intake[key]
  if not it or now - it.t > 60 then it = { t = now, n = 0 }; S.intake[key] = it end
  it.n = it.n + 1
  if it.n > C.INTAKE_PER_MIN then Reject("intake limit"); return end
  S.heard[#S.heard + 1] = now
  S.received = S.received + 1

  local f = Split(text)
  if f[1] == "P" then
    local m, why = self:DecodePosition(f)
    if not m then Reject(why); return end
    S.senders[key] = now
    S.nHeard[key] = { n = m.n, t = now }
    m.key, m.name, m.whisper, m.heard = key, StripRealm(key) or key, sender, now
    if self:IsGuildMember(key) == false then
      self:RequestRoster()
      S.pending[key] = { m = m, since = now }
      return
    end
    S.pending[key] = nil
    Store(key, m)
    -- they're talking, so a cached "offline" is out of date: refresh (DropOffline waits for a newer read)
    local e = self:RosterEntry(key)
    if e and e.online == false then self:RequestRoster() end
  elseif f[1] == "L" then
    local ts = n36(f[2])
    if #f ~= 2 or not ts then Reject("bad leave"); return end
    local old = self.members[key]
    if old and not old.fake and (not old.ts or ts >= old.ts) then
      self.members[key] = nil
      if self.RefreshPins then self:RefreshPins() end
    end
    S.senders[key], S.nHeard[key], S.pending[key] = nil, nil, nil
  else
    Reject("unknown type") -- a newer version's message: ignore quietly
  end
end

-- Offline guildmates lose their pin - but only on a roster read NEWER than their last message, or a guildmate
-- who just logged in would vanish again on the old cache (code review #3). Called from M:Refresh.
function M:DropOffline()
  local readAt = self:RosterReadAt()
  if not readAt then return end
  for key, m in pairs(self.members) do
    if not m.fake and not m.isSelf and readAt > (m.heard or 0) then
      local e = self:RosterEntry(key)
      if e and e.online == false then self.members[key] = nil end
    end
  end
end

-- Own guild changed or left: nothing from the old guild stays.
function M:WipeRemote()
  for key, m in pairs(self.members) do
    if not m.fake and not m.isSelf then self.members[key] = nil end
  end
  wipe(S.pending); wipe(S.senders); wipe(S.nHeard); wipe(S.heard)
  if self.RefreshPins then self:RefreshPins() end
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
function M:SyncDebug(P)
  local now = GetTime()
  P(("Sync: prefix %s %s, hook %s, active senders %d, interval %.0f s%s%s"):format(PREFIX,
    S.prefixOk and "registered" or ("|cffff4040NOT registered (" .. tostring(S.prefixRes) .. ")|r"), S.hooked and "ok" or "|cffff8800missing|r",
    self:ActiveSenders(), self:Interval(true), S.slow and " |cffff8800(slow: no echo)|r" or "",
    #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET and " |cffff8800(busy)|r" or ""))
  P(("Sent %d, echoed %d, lost %d, received %d; last sent %s; skip: %s; GUILD sends by this client in 60 s: %d"):format(
    S.sent, S.echoed, S.lost, S.received,
    S.last and ("%.0f s ago (%s)"):format(now - S.last.t, S.last.why) or "never",
    S.skip or "-", #S.sends))
  local rej = {}
  for k, v in pairs(S.rejected) do rej[#rej + 1] = k .. "=" .. v end
  table.sort(rej)
  P("Rejected: " .. (rej[1] and table.concat(rej, ", ") or "none"))
  local key = S.lastRawKey
  local e = key and self:RosterEntry(key)
  P(("Last sender raw '%s' -> key '%s', roster: %s; own echo raw '%s', own key '%s'"):format(tostring(S.lastRaw),
    tostring(key), key and (e and ("found, online=" .. tostring(e.online)) or "NOT found") or "-",
    tostring(S.echoRaw), tostring(self:PlayerKey())))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix = ...
    if prefix == PREFIX then M.Call(M.OnAddonMessage, M, ...) end -- cheap filter first (code review #7)
  elseif event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      -- old API: true/false; modern: Enum.RegisterAddonMessagePrefixResult (0 success, 1 duplicate) [U on Forever]
      local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
      S.prefixRes = res
      S.prefixOk = ok and (res == nil or res == true or res == 0 or res == 1) or false
    end
    S.loginAt, S.firstRand = GetTime(), math.random()
    M:RequestRoster() -- sizes the first-send window (the core asks at login too; requests are throttled)
    S.guild = Plain(SafeCall(GetGuildInfo, "player"), "string")
  elseif event == "PLAYER_ENTERING_WORLD" then
    if M:InInstance() then S.echoWait = nil end
  elseif event == "PLAYER_GUILD_UPDATE" then
    local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
    if not Bool(SafeCall(IsInGuild)) or (g and S.guild and g ~= S.guild) then M.Call(M.WipeRemote, M) end
    if g then S.guild = g end
  elseif event == "PLAYER_LOGOUT" then
    if M.settings and M.settings.share then pcall(M.SendLeave, M) end
  end
end)
