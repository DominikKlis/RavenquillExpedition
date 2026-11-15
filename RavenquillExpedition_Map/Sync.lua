-- Ravenquill Expedition: Map – position sync. Own prefix, GUILD only, lowest priority on the client.
--   P;<mapID>;<x>;<y>;<level>;<class>;<ts>;<flags>;<n>   numbers base36; x/y 0..46655 (3 digits, sub-yard)
--                                                          flags: s stationary, t taxi, g dead/ghost; n = sender's
--                                                          estimate of active senders (receivers adopt the max)
--   L;<ts>                                                 "leaving" – best effort (share off, logout)
-- These bytes predate the core's schema channels, so Map uses a raw channel on the core's STATE lane: the core sends
-- a position now or not at all, and only while nothing else of the suite waits, no GUILD addon message of this
-- client went out within 4 s, fewer than 10 within 60 s, and a send token is free (core Comm.lua). Map decides
-- WHEN it wants to send (movement, heartbeat, the guild-wide interval); the core decides whether it MAY.
local ADDON, ns = ...
local M = ns.Map
local GS = RavenquillExpedition
local SafeCall, Plain, Bool = GS.SafeCall, GS.Plain, GS.Bool
local W = GS.Wire
local b36, n36, Split, CLASSES = W.b36, W.n36, W.Split, W.CLASSES

local PREFIX = "RQEMap1"
M.PREFIX = PREFIX
local CLASS_MAX = 9    -- Map's wire knows the classes 1-9 (W.CLASSES 1-9 are the shared contract)
local XY_MAX = 46655   -- 36^3 - 1

local C = M.C
C.GUILD_TARGET = 60     -- map messages per minute for the whole guild: one position per 5 s while up to 5 people move,
                        -- slower with more (40 active: every 40 s). Per client the core allows 12 per minute.
C.BUSY_FACTOR = 1.5     -- heard more than 1.5 × target in 60 s -> double our interval
C.ACTIVE_WINDOW = 600   -- senders heard within 10 min count as active
C.MOVE_MIN = 0.003      -- map units moved since the last send that count as "moved"
C.STILL_EPS = 0.001     -- staying within this of an anchor point counts as standing still (any walking speed
C.STILL_AFTER = 20      -- drifts out of it); 20 s like that -> stationary
C.JITTER_MIN = 30      -- first send after login: 30 s + a random share of a window sized to the guild's
C.JITTER_WINDOW_MIN, C.JITTER_WINDOW_MAX = 60, 300 -- online members × 6 s, so a mass login is spread out too
C.SLOW_INTERVAL = 300   -- the core's slow mode (no echo): one probe per 5 min until one comes back
C.STARVE = 30           -- refused this long (or 2 × interval) -> the core waives its 4 s / 10-per-60 s rules once
C.FUTURE_SLACK = 120
C.HOLD_UNKNOWN = 60     -- sender not (yet) in the roster: hold the pin this long
C.ROSTER_EVERY = 120    -- refresh the roster this often while remote pins exist (offline detection)

local raw = M.mod:NewRawChannel({ prefix = PREFIX, lane = "state" })
M.raw = raw

local S = {
  heard = {},          -- GetTime() of map messages from others (busy rule)
  senders = {},        -- [key] = GetTime() last heard (active count)
  nHeard = {},         -- [key] = { n = their estimate, t = GetTime() }
  pending = {},        -- [key] = { m = member, since = GetTime() } – sender not in the roster yet
  rejected = {},       -- [reason] = count
  sent = 0, echoed = 0, received = 0,
}
M.sync = S

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Prune(list, window, now)
  local i = 1
  while list[i] and now - list[i] > window do i = i + 1 end
  if i > 1 then for _ = 1, i - 1 do table.remove(list, 1) end end
end

local function Reject(reason) S.rejected[reason] = (S.rejected[reason] or 0) + 1 end

-- When the first message after login may go out. Each client keeps one random fraction; the window grows with the
-- number of guildmates online (an upper bound on senders), so 40 people logging in together spread over ~4 min
-- instead of all sending within the same minute (harness_sync.lua section 6).
local function FirstSendAt()
  if S.firstAt then return S.firstAt end -- set by "share on"
  if not S.loginAt then return math.huge end
  local online = GS:OnlineCount()
  local window = math.max(C.JITTER_WINDOW_MIN, math.min(C.JITTER_WINDOW_MAX, online * 60 / C.GUILD_TARGET))
  return S.loginAt + C.JITTER_MIN + S.firstRand * window
end

function M:SyncLogin()
  S.loginAt, S.firstRand = GetTime(), math.random()
end

---------------------------------------------------------------------------
-- Pacing
---------------------------------------------------------------------------
-- Senders we heard ourselves (plus us). This, not the adopted maximum, is what we send as n - otherwise
-- clients echo each other's peak forever after people leave.
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
  local online = GS:OnlineCount()
  if online > 0 then maxN = math.min(maxN, online) end
  return math.max(self:DirectSenders(), maxN)
end

-- The guild's update interval (also used by receivers for fading). forSend adds the core's slow mode (our messages
-- don't echo back).
function M:Interval(forSend)
  local base = math.max(C.INTERVAL_MIN, self:ActiveSenders() * 60 / C.GUILD_TARGET)
  Prune(S.heard, 60, GetTime())
  if #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET then base = base * 2 end
  if forSend and GS:CommState().slow then base = math.max(base, C.SLOW_INTERVAL) end
  return base
end

---------------------------------------------------------------------------
-- Sending (called every tick; never queues – it sends the current position or nothing)
---------------------------------------------------------------------------
local function FlagString(stationary, taxi, ghost)
  return (stationary and "s" or "") .. (taxi and "t" or "") .. (ghost and "g" or "")
end

function M:EncodePosition(mapID, x, y, level, class, ts, flags, n)
  return table.concat({ "P", b36(mapID), b36(x * XY_MAX + 0.5), b36(y * XY_MAX + 0.5), b36(level),
    b36(W.CLASS_IDX[class] or 0), b36(ts), flags or "", b36(n) }, ";")
end

function M:SyncTick()
  local now = GetTime()
  self:CheckPending(now)
  if next(self.members) and now - (S.rosterAt or 0) > C.ROSTER_EVERY then
    S.rosterAt = now
    GS:RequestRoster()
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

  -- may we? Map's own rules first, then the core's (guild, instance, combat, hold, the suite's queue, pacing).
  if not self.settings.share then S.skip = "sharing off"; return end
  if last and now - last.t < interval then S.skip = "interval"; return end
  local level = Plain(SafeCall(UnitLevel, "player"), "number") or 0
  local _, class = SafeCall(UnitClass, "player")
  class = Plain(class, "string")
  local ci = W.CLASS_IDX[class or ""]
  if level < 1 or not ci or ci > CLASS_MAX then S.skip = "level/class unknown"; return end
  -- lowest priority: the core yields to everything else this client sends. After being refused for
  -- max(C.STARVE, 2 x interval) one message goes through anyway, or a chatty neighbour (GuildMap sends every ~5 s)
  -- would silence us for good.
  local starving = S.blockedSince and now - S.blockedSince >= math.max(C.STARVE, 2 * interval) or false
  local msg = self:EncodePosition(mapID, x, y, level, class, GS:Now(), flags, self:DirectSenders())
  local ok, why = raw:TrySend(msg, { starving = starving })
  if not ok then S.skip = why; S.blockedSince = S.blockedSince or now; return end
  S.last = { mapID = mapID, x = x, y = y, flags = flags, t = now, why = want }
  S.sent = S.sent + 1
  S.skip, S.blockedSince = nil, nil
end

-- Best effort only: may not get out at logout [U]; the core never sends it inside an instance.
function M:SendLeave()
  if not S.last or not Bool(SafeCall(IsInGuild)) then return end
  raw:SendNow("L;" .. b36(GS:Now()))
  S.last = nil
end

function M:OnShareChanged(on)
  if on then
    S.firstAt = GetTime() -- send soon (still paced); the notice was already shown
  else
    self:SendLeave()
  end
end

---------------------------------------------------------------------------
-- Receiving (the core has checked prefix, GUILD, secrets, the sender's name and the per-sender intake limit;
-- our own messages come back through OnEcho, never here)
---------------------------------------------------------------------------
-- Field checks before anything reaches HereBeDragons (it raises errors on bad input, Pins-2.0.lua:608, :741).
function M:DecodePosition(f)
  if #f ~= 9 then return nil, "field count" end
  local mapID, xi, yi = n36(f[2]), n36(f[3]), n36(f[4])
  local level, cls, ts, flags, n = n36(f[5]), n36(f[6]), n36(f[7]), f[8], n36(f[9])
  if not (mapID and xi and yi and level and cls and ts and n) then return nil, "not a number" end
  if mapID < 1 or mapID > 1e6 or not SafeCall(C_Map.GetMapInfo, mapID) then return nil, "unknown map" end
  if xi > XY_MAX or yi > XY_MAX or (xi == 0 and yi == 0) then return nil, "position range" end
  if level < 1 or level > GS:MaxLevel() then return nil, "level" end
  if cls < 1 or cls > CLASS_MAX then return nil, "class" end
  if ts > GS:Now() + C.FUTURE_SLACK then return nil, "future timestamp" end
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
  M:Wake()
end

function M:CheckPending(now)
  for key, p in pairs(S.pending) do
    local gm = GS:IsGuildMember(key)
    if gm ~= false then
      S.pending[key] = nil
      Store(key, p.m) -- keeps heard = when it arrived, so its age stays real
    elseif now - p.since > C.HOLD_UNKNOWN then
      S.pending[key] = nil
      Reject("not in guild roster")
    end
  end
end

function M:OnMessage(key, text, sender)
  S.lastRaw, S.lastRawKey = sender, key
  if GS:InInstance() then return end -- nothing read in instances
  local now = GetTime()
  S.heard[#S.heard + 1] = now
  S.received = S.received + 1

  local f = Split(text)
  if f[1] == "P" then
    local m, why = self:DecodePosition(f)
    if not m then Reject(why); return end
    S.senders[key] = now
    S.nHeard[key] = { n = m.n, t = now }
    m.key, m.name, m.whisper, m.heard = key, GS:StripRealm(key) or key, sender, now
    if GS:IsGuildMember(key) == false then
      GS:RequestRoster()
      S.pending[key] = { m = m, since = now }
      self:Wake()
      return
    end
    S.pending[key] = nil
    Store(key, m)
    -- they're talking, so a cached "offline" is out of date: refresh (DropOffline waits for a newer read)
    local e = GS:RosterEntry(key)
    if e and e.online == false then GS:RequestRoster() end
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

raw:OnMessage(function(key, text, sender) M:OnMessage(key, text, sender) end)
-- our own position came back from the server (the core tracks delivery and slow mode; this is for diagnostics)
raw:OnEcho(function(text) if text:sub(1, 2) == "P;" then S.echoed = S.echoed + 1 end end)

-- Offline guildmates lose their pin - but only on a roster read NEWER than their last message, or a guildmate
-- who just logged in would vanish again on the old cache. Called from M:Refresh.
function M:DropOffline()
  local readAt = GS:RosterReadAt()
  if not readAt then return end
  for key, m in pairs(self.members) do
    if not m.fake and not m.isSelf and readAt > (m.heard or 0) then
      local e = GS:RosterEntry(key)
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

function M.mod:OnGuildChanged() M:WipeRemote() end

M.mod:RegisterEvent("PLAYER_LOGOUT", function()
  if M.settings and M.settings.share then M:SendLeave() end
end)

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
function M:SyncDebug(P)
  local now = GetTime()
  local cs = GS:CommState()
  P(("Sync: prefix %s %s, active senders %d, interval %.0f s%s%s"):format(PREFIX,
    raw.prefixOk and "registered" or "|cffff4040NOT registered|r",
    self:ActiveSenders(), self:Interval(true), cs.slow and " |cffff8800(slow: no echo)|r" or "",
    #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET and " |cffff8800(busy)|r" or ""))
  P(("Map: sent %d, echoed %d, received %d; last sent %s; skip: %s%s"):format(
    S.sent, S.echoed, S.received,
    S.last and ("%.0f s ago (%s)"):format(now - S.last.t, S.last.why) or "never",
    S.skip or "-", S.blockedSince and (" (refused for %.0f s)"):format(now - S.blockedSince) or ""))
  P(("Core: tokens %.1f, hold %.0f s, queued %d, records %d, waiting for echo %d, delivered %d, lost %d, foreign %s%s"):format(
    cs.tokens, cs.hold, cs.queued, cs.records, cs.inflight, cs.delivered, cs.lost,
    cs.hooked and tostring(cs.foreign) or "(no hook)", GS:InInstance() and ", paused (instance)" or ""))
  local rej = {}
  for k, v in pairs(S.rejected) do rej[#rej + 1] = k .. "=" .. v end
  for k, v in pairs(raw:Status().rejected) do rej[#rej + 1] = "core " .. k .. "=" .. v end
  table.sort(rej)
  P("Rejected: " .. (rej[1] and table.concat(rej, ", ") or "none"))
  local key = S.lastRawKey
  local e = key and GS:RosterEntry(key)
  P(("Last sender raw '%s' -> key '%s', roster: %s; own key '%s'"):format(tostring(S.lastRaw),
    tostring(key), key and (e and ("found, online=" .. tostring(e.online)) or "NOT found") or "-",
    tostring(GS:PlayerKey())))
end
