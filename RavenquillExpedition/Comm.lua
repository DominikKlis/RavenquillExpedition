local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local W = GS.Wire

local PREFIX = "RQE1"
GS.COMM_PREFIX = PREFIX

local C = {
  MAX_MSG = W.MAX_MSG,
  BURST = 3, RATE = 1 / 5,
  SLOW_RATE = 1 / 300,
  BUSY_HEARD = 20,
  HEARD_PER_SENDER = 4,
  INTAKE_PER_MIN = 15,
  INTAKE_STATE_PER_MIN = 15,
  ECHO_TIMEOUT = 120,
  SLOW_AFTER_LOSSES = 2,
  QUEUE_MAX = 40,
  QUEUE_MAX_WAIT = 1800,
  RECORD_MAX_WAIT = 300,
  RECORD_MAX_AGE = 600,
  HOLD_THROTTLED = 30,
  STATE_QUIET = 4,
  STATE_MAX_60 = 10,
  STARVE = 30,
}
GS.CommConst = C

local S = {
  q = {},
  records = {},
  tokens = C.BURST, tokenAt = nil,
  hold = 0,
  heard = {},
  intake = {},
  inflight = {},
  sends = {},
  prefixes = {},
  tags = {},
  sent = 0, received = 0, echoed = 0, lost = 0, foreign = 0, dropped = 0,
}
GS.Comm = S

local function Result(cb, status) if cb then GS:Call(cb, status) end end

local function Rate() return S.slow and C.SLOW_RATE or C.RATE end
local function Refill(now)
  S.tokens = math.min(C.BURST, S.tokens + (now - (S.tokenAt or now)) * Rate())
  S.tokenAt = now
end

local function CanSend()
  if not GS.loggedIn then return false, "not logged in" end
  if GS:InInstance() then return false, "instance" end
  if InCombatLockdown and Plain(SafeCall(InCombatLockdown)) then return false, "combat" end
  if not Plain(SafeCall(IsInGuild)) then return false, "not in a guild" end
  return true
end
function GS:CanSend() return CanSend() end

local Note
local sending = false
local function SendRaw(prefix, msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "error" end
  sending = true
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "GUILD")
  sending = false
  Note(S.sends, GetTime())
  if not ok then return "error" end
  if res == nil or res == true or res == 0 then return "ok" end
  if res == 3 or res == 8 then return "throttled" end
  return "error"
end

local function Prune(list, window, now)
  local i = 1
  while list[i] and now - list[i] > window do i = i + 1 end
  if i == 1 then return end
  local n = #list
  for j = i, n do list[j - i + 1] = list[j] end
  for j = n - i + 2, n do list[j] = nil end
end
GS.PruneTimes = Prune

Note = function(list, now)
  Prune(list, 60, now)
  list[#list + 1] = now
end

local function Inflight(prefix, msg, onResult, now)
  local k = prefix .. "\0" .. msg
  local list = S.inflight[k]
  if not list then list = {}; S.inflight[k] = list end
  list[#list + 1] = { t = now, onResult = onResult }
  S.sent = S.sent + 1
  S.firstSent = S.firstSent or now
  S.lastSent = now
end

local Pump

local function Unsendable(msg) return #msg > C.MAX_MSG or msg:find("\0", 1, true) ~= nil end

local function QueueEvent(prefix, msg, onResult, channel)
  if Unsendable(msg) then return false, "too long" end
  local ok, why = CanSend()
  if not ok then return false, why end
  if #S.q >= C.QUEUE_MAX then return false, "queue full" end
  S.q[#S.q + 1] = { prefix = prefix, msg = msg, t = GetTime(), onResult = onResult, channel = channel }
  Pump()
  return true
end

local function QueueRecord(prefix, key, chunks, opts, channel)
  if type(chunks) ~= "table" or not chunks[1] then return false, "empty" end
  for _, c in ipairs(chunks) do
    if type(c) ~= "string" or Unsendable(c) then return false, "too long" end
  end
  for i = #S.records, 1, -1 do
    local r = S.records[i]
    if r.prefix == prefix and r.key == key and not r.started then table.remove(S.records, i) end
  end
  S.records[#S.records + 1] = { prefix = prefix, key = key, chunks = chunks, i = 1, t = GetTime(),
    onDone = opts and opts.onDone, onDrop = opts and opts.onDrop, channel = channel }
  Pump()
  return true
end

local function CancelRecords(prefix, key)
  for i = #S.records, 1, -1 do
    local r = S.records[i]
    if r.prefix == prefix and (key == nil or r.key == key) then table.remove(S.records, i) end
  end
end

local function SpendToken() S.tokens = math.max(-1, S.tokens - 1) end
local function HoldAfterThrottle(now) S.tokens, S.hold = 0, now + C.HOLD_THROTTLED end
local function CountSent(channel) if channel then channel.stats.sent = channel.stats.sent + 1 end end
local function WireLabel(prefix, text) return prefix == PREFIX and text or (prefix .. " " .. text) end

local function StateLaneRefusal(now)
  local last = S.sends[#S.sends]
  if last and now - last < C.STATE_QUIET then return ("another addon sent < %d s ago"):format(C.STATE_QUIET) end
  if #S.sends >= C.STATE_MAX_60 then return ("%d+ guild addon messages in 60 s"):format(C.STATE_MAX_60) end
  if S.tokens < 1 then return "no send token" end
end

local function TrySend(prefix, msg, opts, channel)
  local now = GetTime()
  if Unsendable(msg) then return false, "too long" end
  local ok, why = CanSend()
  if not ok then return false, why end
  if now < S.hold then return false, "throttled (hold)" end
  if S.q[1] or S.records[1] then return false, "Ravenquill Expedition modules are waiting to send" end
  Prune(S.sends, 60, now)
  Refill(now)
  local refusal = not (opts and opts.starving) and StateLaneRefusal(now)
  if refusal then return false, refusal end
  local r = SendRaw(prefix, msg)
  GS:Trace("comm.tx", r, prefix .. " " .. msg)
  if r == "throttled" then HoldAfterThrottle(now); return false, "throttled" end
  if r ~= "ok" then S.hold = now + C.HOLD_THROTTLED; return false, "send error" end
  SpendToken()
  Inflight(prefix, msg, nil, now)
  CountSent(channel)
  Pump()
  return true
end

local function SendNow(prefix, msg, channel)
  if GS:InInstance() or Unsendable(msg) then return false end
  local r = SendRaw(prefix, msg)
  GS:Trace("comm.tx", r, prefix .. " " .. msg)
  Refill(GetTime())
  SpendToken()
  if r == "ok" then CountSent(channel) end
  return r == "ok"
end

local function DropAll()
  local q, recs = {}, {}
  for i, it in ipairs(S.q) do q[i] = it end
  for i, r in ipairs(S.records) do recs[i] = r end
  for i = #S.q, 1, -1 do S.q[i] = nil end
  for i = #S.records, 1, -1 do S.records[i] = nil end
  for _, it in ipairs(q) do Result(it.onResult, "deferred") end
  for _, r in ipairs(recs) do if r.onDrop then GS:Call(r.onDrop, "instance") end end
end

local PumpOnce
do
  local function ExpireInflight(now)
    for k, list in pairs(S.inflight) do
      while list[1] and now - list[1].t > C.ECHO_TIMEOUT do
        local e = table.remove(list, 1)
        S.lost = S.lost + 1
        S.lostSinceEcho = (S.lostSinceEcho or 0) + 1
        GS:Trace("comm.lost", (k:gsub("%z", " ")))
        Result(e.onResult, "lost")
      end
      if not list[1] then S.inflight[k] = nil end
    end
  end

  local function SlowDownWithoutEcho(now)
    if S.slow or (S.lostSinceEcho or 0) < C.SLOW_AFTER_LOSSES then return end
    local since = S.lastEcho or S.firstSent
    if not since or now - since <= C.ECHO_TIMEOUT then return end
    S.slow = true
    Refill(now)
    S.tokens = math.min(S.tokens, 0)
    GS:Trace("comm.slow", "no echo for " .. C.ECHO_TIMEOUT .. " s")
    if S.slowSaid then return end
    S.slowSaid = true
    GS.Print(nil, GS.OverviewL.SLOW_WARNING)
  end

  local function ExpireQueue(now)
    for i = #S.q, 1, -1 do
      local it = S.q[i]
      if now - it.t > C.QUEUE_MAX_WAIT then table.remove(S.q, i); S.dropped = S.dropped + 1; Result(it.onResult, "deferred") end
    end
  end

  local function RecordExpired(r, now)
    return now - r.t > (r.started and C.RECORD_MAX_AGE or C.RECORD_MAX_WAIT)
  end

  local function ExpireRecords(now)
    for i = #S.records, 1, -1 do
      local r = S.records[i]
      if RecordExpired(r, now) then
        table.remove(S.records, i)
        S.dropped = S.dropped + 1
        if r.onDrop then GS:Call(r.onDrop, "timeout") end
      end
    end
  end

  local function RemoveRecord(rec)
    for i, x in ipairs(S.records) do if x == rec then table.remove(S.records, i) break end end
  end

  local function NextRecord()
    for _, r in ipairs(S.records) do if r.started then return r end end
    return S.records[1]
  end

  local function MustWait(now, queuedAt)
    if not CanSend() or now < S.hold or #S.heard >= C.BUSY_HEARD then return true end
    if S.tokens >= 1 then return false end
    local waited = now - queuedAt
    if S.slow or waited < C.STARVE or (S.lastSent and now - S.lastSent < 1 / C.RATE) then return true end
    GS:Trace("comm.starve", ("sending after %d s without a token"):format(waited))
    return false
  end

  local function SettleQueuedEvent(item, r, now)
    table.remove(S.q, 1)
    if r == "error" then return Result(item.onResult, "deferred") end
    Inflight(item.prefix, item.msg, item.onResult, now)
    CountSent(item.channel)
  end

  local function SettleRecordChunk(rec, msg, r, now)
    if r == "error" then
      RemoveRecord(rec)
      if rec.onDrop then GS:Call(rec.onDrop, "error") end
      return
    end
    Inflight(rec.prefix, msg, nil, now)
    CountSent(rec.channel)
    rec.started = true
    rec.i = rec.i + 1
    if rec.i <= #rec.chunks then return end
    RemoveRecord(rec)
    if rec.onDone then GS:Call(rec.onDone) end
  end

  local function SendNext(now, item, rec)
    local prefix, msg
    if item then prefix, msg = item.prefix, item.msg else prefix, msg = rec.prefix, rec.chunks[rec.i] end
    local r = SendRaw(prefix, msg)
    GS:Trace("comm.tx", r, WireLabel(prefix, msg))
    if r == "throttled" then return HoldAfterThrottle(now) end
    SpendToken()
    if item then return SettleQueuedEvent(item, r, now) end
    SettleRecordChunk(rec, msg, r, now)
  end

  PumpOnce = function()
    local now = GetTime()
    Prune(S.heard, 60, now)
    Prune(S.sends, 60, now)
    ExpireInflight(now)
    SlowDownWithoutEcho(now)
    if (S.q[1] or S.records[1]) and GS:InInstance() then DropAll() end
    ExpireQueue(now)
    ExpireRecords(now)
    Refill(now)
    local item = S.q[1]
    local rec = not item and NextRecord() or nil
    if not item and not rec then return next(S.inflight) ~= nil end
    if MustWait(now, (item or rec).t) then return true end
    SendNext(now, item, rec)
    return true
  end
end

Pump = function()
  if S.armed then return end
  S.armed = true
  C_Timer.After(1, function()
    S.armed = false
    local done, more = GS:Call(function() return true, PumpOnce() end)
    if not done then more = true end
    if more then C_Timer.After(4, Pump) end
  end)
end

local STATUS = { echo = "delivered", lost = "lost", deferred = "dropped" }
local Channel = ns.Channel

local function Reject(ch, why, detail)
  ch.stats.rejected[why] = (ch.stats.rejected[why] or 0) + 1
  GS:Trace("comm.reject", ch.name .. ": " .. why .. (detail and (" " .. tostring(detail)) or ""))
end

function Channel:On(typ, fn) self.handlers[typ] = fn end

function Channel:Send(typ, msg, opts)
  local text, why = self:Encode(typ, msg)
  local cb = opts and opts.onResult
  if not text then Reject(self, "encode: " .. tostring(why)); Result(cb, "dropped") return end
  local ok = QueueEvent(PREFIX, text, cb and function(status) cb(STATUS[status] or status) end, self)
  if not ok then Result(cb, "dropped") end
end

function Channel:TrySend(typ, msg, opts)
  local text, why = self:Encode(typ, msg)
  if not text then Reject(self, "encode: " .. tostring(why)); return false, why end
  return TrySend(PREFIX, text, opts, self)
end

function Channel:Receive(sender, body)
  local typ, msg, detail = self:Decode(sender, body)
  if not typ then return Reject(self, msg, detail) end
  self.stats.received = self.stats.received + 1
  local h = self.handlers[typ]
  if h then GS:Call(h, sender, msg) end
end

function Channel:Status() return self.stats end

function ns.ModuleProto:NewChannel(spec)
  local tag, version = spec and spec.tag, spec and spec.version or 1
  if type(tag) ~= "string" or tag == "" or tag:find("[;|]") then error("NewChannel: bad tag " .. tostring(tag), 2) end
  if S.tags[tag] then error("NewChannel: tag '" .. tag .. "' is already taken", 2) end
  local ch = setmetatable({ name = (self.name or "?") .. "/" .. tag, tag = tag, version = version, types = {}, handlers = {},
    stats = { sent = 0, received = 0, rejected = {} } }, Channel)
  S.tags[tag] = ch
  return ch
end

local Raw = {}
Raw.__index = Raw

local function RegisterPrefix(prefix)
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
  GS:Trace("comm.prefix", prefix .. " " .. tostring(ok) .. " " .. tostring(res))
  return ok and (res == nil or res == true or res == 0 or res == 1) or false
end

function Raw:OnMessage(fn) self.onMessage = fn end
function Raw:OnEcho(fn) self.onEcho = fn end
function Raw:Send(text, opts)
  local cb = opts and opts.onResult
  local ok = QueueEvent(self.prefix, text, cb and function(status) cb(STATUS[status] or status) end, self)
  if not ok then Result(cb, "dropped") end
  return ok
end
function Raw:TrySend(text, opts) return TrySend(self.prefix, text, opts, self) end
function Raw:SendNow(text) return SendNow(self.prefix, text, self) end
function Raw:SendRecord(key, chunks, opts) return QueueRecord(self.prefix, key, chunks, opts, self) end
function Raw:Cancel(key) CancelRecords(self.prefix, key) end
function Raw:Status() return self.stats end

function ns.ModuleProto:NewRawChannel(spec)
  local prefix, lane = spec and spec.prefix, spec and spec.lane or "event"
  if type(prefix) ~= "string" or prefix == "" or #prefix > 16 or prefix == PREFIX then error("NewRawChannel: bad prefix " .. tostring(prefix), 2) end
  if S.prefixes[prefix] then error("NewRawChannel: prefix '" .. prefix .. "' is already taken", 2) end
  assert(lane == "event" or lane == "state" or lane == "record", "NewRawChannel: lane must be event, state or record")
  local raw = setmetatable({ name = (self.name or "?") .. "/" .. prefix, prefix = prefix, lane = lane,
    stats = { sent = 0, received = 0, rejected = {} } }, Raw)
  S.prefixes[prefix] = raw
  if GS.loggedIn then raw.prefixOk = RegisterPrefix(prefix) end
  return raw
end

local OnAddonMessage
do
  local function SettleEcho(prefix, text)
    local k = prefix .. "\0" .. text
    local list = S.inflight[k]
    if not (list and list[1]) then return end
    local e = table.remove(list, 1)
    if not list[1] then S.inflight[k] = nil end
    S.echoed, S.lastEcho, S.lostSinceEcho = S.echoed + 1, GetTime(), 0
    if S.slow then S.slow = false end
    GS:Trace("comm.echo", WireLabel(prefix, text))
    Result(e.onResult, "echo")
  end

  local function IntakeOf(key, now)
    local it = S.intake[key]
    if not it or now - it.t > 60 then it = { t = now, n = 0, ns = 0, h = 0 }; S.intake[key] = it end
    return it
  end

  local function AdmitState(it, raw)
    it.ns = it.ns + 1
    if it.ns <= C.INTAKE_STATE_PER_MIN then return true end
    raw.stats.rejected.intake = (raw.stats.rejected.intake or 0) + 1
    return false
  end

  local function AdmitEvent(it, key, now)
    it.n = it.n + 1
    if it.n > C.INTAKE_PER_MIN then GS:Trace("comm.drop", "intake limit " .. key) return false end
    it.h = it.h + 1
    if it.h <= C.HEARD_PER_SENDER then Note(S.heard, now) end
    return true
  end

  local function Admit(key, raw)
    local now = GetTime()
    local it = IntakeOf(key, now)
    if raw and raw.lane == "state" then return AdmitState(it, raw) end
    return AdmitEvent(it, key, now)
  end

  local function Deliver(key, prefix, text, sender, raw)
    S.received = S.received + 1
    GS:NotePeer(key)
    GS:Trace("comm.rx", key, WireLabel(prefix, text))
    if raw then
      raw.stats.received = raw.stats.received + 1
      if raw.onMessage then GS:Call(raw.onMessage, key, text, sender) end
      return
    end
    local tag, body = text:match("^([^;]+);(.*)$")
    local ch = tag and S.tags[tag]
    if ch then return ch:Receive(key, body) end
  end

  OnAddonMessage = function(prefix, text, chan, sender)
    local raw = S.prefixes[prefix]
    if prefix ~= PREFIX and not raw then return end
    text, chan, sender = Plain(text, "string"), Plain(chan, "string"), Plain(sender, "string")
    if not (text and sender) or chan ~= "GUILD" then return end
    local key = GS:NormName(sender)
    if not key then return end
    if GS:IsMe(key) then
      SettleEcho(prefix, text)
      if raw and raw.onEcho then GS:Call(raw.onEcho, text) end
      return
    end
    if not Admit(key, raw) then return end
    return Deliver(key, prefix, text, sender, raw)
  end
end

function GS:CommState()
  local inflight = 0
  for _, list in pairs(S.inflight) do inflight = inflight + #list end
  local chunks = 0
  for _, r in ipairs(S.records) do chunks = chunks + #r.chunks - r.i + 1 end
  return { tokens = S.tokens, slow = S.slow and true or false, hold = math.max(0, S.hold - GetTime()), queued = #S.q,
    records = #S.records, chunks = chunks, inflight = inflight, sent = S.sent, delivered = S.echoed, lost = S.lost,
    received = S.received, foreign = S.foreign, hooked = S.hooked and true or false, lastSent = S.lastSent }
end

function GS:CommResume()
  S.slow, S.firstSent, S.lastEcho, S.lostSinceEcho = false, nil, nil, 0
  Pump()
end

function GS:CommStatus()
  local st = self:CommState()
  return ("queue %d, records %d, sent %d, delivered %d, lost %d, waiting for echo %d, received %d, tokens %.1f, foreign %s%s%s"):format(
    st.queued, st.records, st.sent, st.delivered, st.lost, st.inflight, st.received, st.tokens,
    S.hooked and tostring(S.foreign) or "(no hook)",
    self:InInstance() and ", |cffff8800paused (instance)|r" or "", S.slow and ", |cffff8800slow (no echo)|r" or "")
end

function GS:OnLoginComm()
  RegisterPrefix(PREFIX)
  for _, raw in pairs(S.prefixes) do raw.prefixOk = RegisterPrefix(raw.prefix) end
end

if hooksecurefunc and C_ChatInfo and C_ChatInfo.SendAddonMessage then
  pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", function(prefix, _, chan)
    if sending or Plain(chan, "string") ~= "GUILD" then return end
    local now = GetTime()
    Note(S.sends, now)
    Refill(now)
    S.tokens = math.min(S.tokens, math.max(0, S.tokens - 1))
    S.foreign = S.foreign + 1
    GS:Trace("comm.foreign", Plain(prefix, "string") or "?")
  end)
  S.hooked = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, prefix, ...)
  if event == "CHAT_MSG_ADDON" then
    prefix = Plain(prefix, "string")
    if prefix and (prefix == PREFIX or S.prefixes[prefix]) then GS:Call(OnAddonMessage, prefix, ...) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if GS:InInstance() then GS:Call(DropAll) elseif S.q[1] or S.records[1] then Pump() end
  elseif S.q[1] or S.records[1] then
    Pump()
  end
end)
