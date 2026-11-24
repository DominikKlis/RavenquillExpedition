local ADDON, ns = ...
local M = ns.Map
local GS = RavenquillExpedition
local SafeCall, Bool = GS.SafeCall, GS.Bool
local W = GS.Wire
local b36, n36, Split, CLASSES = W.b36, W.n36, W.Split, W.CLASSES

local PREFIX = "RQEMap1"
M.PREFIX = PREFIX
local CLASS_MAX = 9
local XY_MAX = 46655

local C = M.C

local raw = M:NewRawChannel({ prefix = PREFIX, lane = "state" })
M.raw = raw

local S = {
  heard = {},
  senders = {},
  nHeard = {},
  pending = {},
  rejected = {},
  sent = 0, echoed = 0, received = 0,
}
M.sync = S

local Prune = GS.PruneTimes

local function Reject(reason) S.rejected[reason] = (S.rejected[reason] or 0) + 1 end

local function FirstSendAt()
  if S.firstAt then return S.firstAt end
  if not S.loginAt then return math.huge end
  local online = GS:OnlineCount()
  local window = math.max(C.JITTER_WINDOW_MIN, math.min(C.JITTER_WINDOW_MAX, online * 60 / C.GUILD_TARGET))
  return S.loginAt + C.JITTER_MIN + S.firstRand * window
end

function M:SyncLogin()
  S.loginAt, S.firstRand = GetTime(), math.random()
end

function M:SyncReloaded()
  S.firstAt = GetTime()
end

function M:DirectSenders()
  local now, count = GetTime(), 0
  for key, t in pairs(S.senders) do
    if now - t <= C.ACTIVE_WINDOW then count = count + 1 else S.senders[key] = nil end
  end
  if self.settings and self.settings.share then count = count + 1 end
  return math.max(1, count)
end

function M:ActiveSenders()
  local now, maxN = GetTime(), 0
  for key, h in pairs(S.nHeard) do
    if now - h.t <= C.ACTIVE_WINDOW then maxN = math.max(maxN, h.n) else S.nHeard[key] = nil end
  end
  local online = GS:OnlineCount()
  if online > 0 then maxN = math.min(maxN, online) end
  return math.max(self:DirectSenders(), maxN)
end

function M:Interval(forSend)
  local base = math.max(C.INTERVAL_MIN, self:ActiveSenders() * 60 / C.GUILD_TARGET)
  Prune(S.heard, 60, GetTime())
  if #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET then base = base * 2 end
  if forSend and GS:CommState().slow then base = math.max(base, C.SLOW_INTERVAL) end
  return base
end

local function FlagString(stationary, taxi, ghost)
  return (stationary and "s" or "") .. (taxi and "t" or "") .. (ghost and "g" or "")
end

function M:EncodePosition(mapID, x, y, level, class, ts, flags, n)
  return table.concat({ "P", b36(mapID), b36(x * XY_MAX + 0.5), b36(y * XY_MAX + 0.5), b36(level),
    b36(W.CLASS_IDX[class] or 0), b36(ts), flags or "", b36(n) }, ";")
end

local function RefreshRosterWhenDue(self, now)
  if not next(self.members) or now - (S.rosterAt or 0) <= C.ROSTER_EVERY then return end
  S.rosterAt = now
  GS:RequestRoster()
end

local function MovedFromAnchor(a, mapID, x, y)
  return not a or a[1] ~= mapID or math.max(math.abs(a[2] - x), math.abs(a[3] - y)) > C.STILL_EPS
end

local function OwnState(mapID, x, y, now)
  if MovedFromAnchor(S.anchor, mapID, x, y) then S.anchor, S.lastMoveAt = { mapID, x, y }, now end
  local me = M:ReadPlayer()
  local stationary = not me.taxi and now - (S.lastMoveAt or now) >= C.STILL_AFTER
  return { mapID = mapID, x = x, y = y, level = me.level, class = me.class, taxi = me.taxi, stationary = stationary,
    flags = FlagString(stationary, me.taxi, me.ghost) }
end

local function WalkedSince(last, pos)
  if pos.stationary then return false end
  return math.max(math.abs(pos.x - last.x), math.abs(pos.y - last.y)) >= C.MOVE_MIN
end

local function HeartbeatAfter(pos)
  if pos.stationary then return C.HEARTBEAT end
  return C.FADE_MIN * C.BEAT_OF_FADE
end

local function SendReason(pos, now, interval)
  local last = S.last
  if not last then
    if now >= FirstSendAt() then return "first" end
    return nil
  end
  if pos.mapID ~= last.mapID then return "zone" end
  if pos.flags ~= last.flags then return "flags" end
  if WalkedSince(last, pos) then return "moved" end
  if now - last.t >= math.max(HeartbeatAfter(pos), interval) then return "heartbeat" end
end

local function KnownLevelAndClass(pos)
  local ci = W.CLASS_IDX[pos.class or ""]
  return pos.level >= 1 and ci ~= nil and ci <= CLASS_MAX
end

local function SendPosition(self, pos, now, interval)
  local waitingSince = S.blockedSince and math.max(S.last and S.last.t or 0, S.blockedSince - interval)
  local starving = waitingSince and now - waitingSince >= math.max(C.STARVE, 2 * interval) or false
  local msg = self:EncodePosition(pos.mapID, pos.x, pos.y, pos.level, pos.class, GS:Now(), pos.flags, self:DirectSenders())
  local ok, why = raw:TrySend(msg, { starving = starving })
  if not ok then S.skip = why; S.blockedSince = S.blockedSince or now; return end
  S.last = { mapID = pos.mapID, x = pos.x, y = pos.y, flags = pos.flags, t = now, why = pos.why }
  S.sent = S.sent + 1
  S.skip, S.blockedSince = nil, nil
end

function M:SyncTick()
  local now = GetTime()
  self:CheckPending(now)
  RefreshRosterWhenDue(self, now)
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then S.skip = "no position"; return end
  local pos = OwnState(mapID, x, y, now)
  local interval = self:Interval(true)
  pos.why = SendReason(pos, now, interval)
  if not pos.why then S.skip = nil; S.blockedSince = nil; return end
  if not self.settings.share then S.skip = "sharing off"; return end
  if S.last and now - S.last.t < interval then S.skip = "interval"; return end
  if not KnownLevelAndClass(pos) then S.skip = "level/class unknown"; return end
  SendPosition(self, pos, now, interval)
end

function M:SendLeave()
  if not S.last or not Bool(SafeCall(IsInGuild)) then return end
  raw:SendNow("L;" .. b36(GS:Now()))
  S.last = nil
end

function M:OnShareChanged(on)
  if on then
    S.firstAt = GetTime()
  else
    self:SendLeave()
  end
end

local function AllPresent(...)
  for i = 1, select("#", ...) do if not select(i, ...) then return false end end
  return true
end

local function PlaceProblem(mapID, xi, yi)
  if mapID < 1 or mapID > 1e6 or not SafeCall(C_Map.GetMapInfo, mapID) then return "unknown map" end
  if xi > XY_MAX or yi > XY_MAX or (xi == 0 and yi == 0) then return "position range" end
end

local function DetailProblem(level, cls, ts, flags, n)
  if level < 1 or level > GS:MaxLevel() then return "level" end
  if cls < 1 or cls > CLASS_MAX then return "class" end
  if ts > GS:Now() + C.FUTURE_SLACK then return "future timestamp" end
  if not flags:match("^[stg]*$") or #flags > 3 then return "flags" end
  if n < 1 or n > 1000 then return "sender estimate" end
end

function M:DecodePosition(f)
  if #f ~= 9 then return nil, "field count" end
  local mapID, xi, yi = n36(f[2]), n36(f[3]), n36(f[4])
  local level, cls, ts, flags, n = n36(f[5]), n36(f[6]), n36(f[7]), f[8], n36(f[9])
  if not AllPresent(mapID, xi, yi, level, cls, ts, n) then return nil, "not a number" end
  local problem = PlaceProblem(mapID, xi, yi) or DetailProblem(level, cls, ts, flags, n)
  if problem then return nil, problem end
  local fl = {}
  for c in flags:gmatch(".") do fl[c] = true end
  return { mapID = mapID, x = xi / XY_MAX, y = yi / XY_MAX, level = level, class = CLASSES[cls], ts = ts,
    flags = fl, n = n }
end

local function Store(key, m)
  local old = M.members[key]
  if old and old.ts and m.ts < old.ts then Reject("older than shown"); return end
  M.members[key] = m
  M:RefreshPins()
  M:Wake()
end

function M:CheckPending(now)
  for key, p in pairs(S.pending) do
    local gm = GS:IsGuildMember(key)
    if gm ~= false then
      S.pending[key] = nil
      Store(key, p.m)
    elseif now - p.since > C.HOLD_UNKNOWN then
      S.pending[key] = nil
      Reject("not in guild roster")
    end
  end
end

local function OnPosition(self, key, f, sender, now)
  local m, why = self:DecodePosition(f)
  if not m then return Reject(why) end
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
  local e = GS:RosterEntry(key)
  if e and e.online == false then GS:RequestRoster() end
end

local function OnLeave(self, key, f)
  local ts = n36(f[2])
  if #f ~= 2 or not ts then return Reject("bad leave") end
  local old = self.members[key]
  if old and not old.fake and (not old.ts or ts >= old.ts) then
    self.members[key] = nil
    self:RefreshPins()
  end
  S.senders[key], S.nHeard[key], S.pending[key] = nil, nil, nil
  self.lastHeard[key] = nil
end

M.handlers = { P = OnPosition, L = OnLeave }

function M:OnMessage(key, text, sender)
  S.lastRaw, S.lastRawKey = sender, key
  if GS:InInstance() then return end
  local now = GetTime()
  S.heard[#S.heard + 1] = now
  S.received = S.received + 1
  local f = Split(text)
  local handle = self.handlers[f[1]]
  if handle then return handle(self, key, f, sender, now) end
  Reject("unknown type")
end

raw:OnMessage(function(key, text, sender) M:OnMessage(key, text, sender) end)
raw:OnEcho(function(text) if text:sub(1, 2) == "P;" then S.echoed = S.echoed + 1 end end)

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

function M:OnGuildChanged()
  for key, m in pairs(self.members) do
    if not m.fake and not m.isSelf then self.members[key] = nil end
  end
  wipe(S.pending); wipe(S.senders); wipe(S.nHeard); wipe(S.heard)
  self:RefreshPins()
end

M:RegisterEvent("PLAYER_LOGOUT", function()
  if M.settings and M.settings.share then M:SendLeave() end
end)

local function SyncLine(self, cs)
  return ("Sync: prefix %s %s, active senders %d, interval %.0f s%s%s"):format(PREFIX,
    raw.prefixOk and "registered" or "|cffff4040NOT registered|r",
    self:ActiveSenders(), self:Interval(true), cs.slow and " |cffff8800(slow: no echo)|r" or "",
    #S.heard > C.BUSY_FACTOR * C.GUILD_TARGET and " |cffff8800(busy)|r" or "")
end

local function MapLine(now)
  return ("Map: sent %d, echoed %d, received %d; last sent %s; skip: %s%s"):format(
    S.sent, S.echoed, S.received,
    S.last and ("%.0f s ago (%s)"):format(now - S.last.t, S.last.why) or "never",
    S.skip or "-", S.blockedSince and (" (refused for %.0f s)"):format(now - S.blockedSince) or "")
end

local function CoreLine(cs)
  return ("Core: tokens %.1f, hold %.0f s, queued %d, records %d, waiting for echo %d, delivered %d, lost %d, foreign %s%s"):format(
    cs.tokens, cs.hold, cs.queued, cs.records, cs.inflight, cs.delivered, cs.lost,
    cs.hooked and tostring(cs.foreign) or "(no hook)", GS:InInstance() and ", paused (instance)" or "")
end

local function RejectedLine()
  local rej = {}
  for k, v in pairs(S.rejected) do rej[#rej + 1] = k .. "=" .. v end
  for k, v in pairs(raw:Status().rejected) do rej[#rej + 1] = "core " .. k .. "=" .. v end
  table.sort(rej)
  return "Rejected: " .. (rej[1] and table.concat(rej, ", ") or "none")
end

local function LastSenderLine()
  local key = S.lastRawKey
  local e = key and GS:RosterEntry(key)
  local roster = key and (e and ("found, online=" .. tostring(e.online)) or "NOT found") or "-"
  return ("Last sender raw '%s' -> key '%s', roster: %s; own key '%s'"):format(tostring(S.lastRaw),
    tostring(key), roster, tostring(GS:PlayerKey()))
end

function M:SyncDebug(P)
  local now = GetTime()
  local cs = GS:CommState()
  P(SyncLine(self, cs))
  P(MapLine(now))
  P(CoreLine(cs))
  P(RejectedLine())
  P(LastSenderLine())
end
