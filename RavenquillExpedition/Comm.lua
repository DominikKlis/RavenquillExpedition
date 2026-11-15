-- Ravenquill Expedition core: ONE scheduler for every GUILD addon message the suite sends (docs/sync.md).
-- Forever rules this follows: only GUILD works; 255 bytes per message; heavy senders are dropped SILENTLY (per player,
-- all prefixes); our own GUILD messages echo back in about a second - the only proof of delivery.
-- One token bucket per client (burst 2, then 1 per 30 s; 1 per 5 min while nothing echoes), three lanes:
--   event   queued, sent in order, confirmed by the echo: onResult "delivered" | "lost" | "dropped"
--   record  a list of chunks sent whole (one per token); an unstarted record with the same key is replaced
--   state   "now or not at all" (a position): TrySend sends right away or says why not; never queued, lowest priority
-- When a token is free: event first, then record chunks (a started record finishes first), state only via TrySend
-- when nothing else waits. Nothing is sent inside an instance or in combat.
-- Channels (what modules use):
--   mod:NewChannel{ tag, version }        schema messages under the core prefix RQE1: "<tag>;<version>;<type>;..."
--   mod:NewRawChannel{ prefix, lane }     a module's own prefix and its own bytes (Map's RQEMap1, CraftAdvisor's GCAdv1)
local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local W = GS.Wire

local PREFIX = "RQE1"
GS.COMM_PREFIX = PREFIX

local C = {
  MAX_MSG = W.MAX_MSG,
  -- Measured in game (Dev test comm.rate, 2026-11-15): 30 messages per minute from one client for a full minute all
  -- echoed. We use 40% of that: 3 at once, then 1 per 5 s (12 per minute) for every module together.
  BURST = 3, RATE = 1 / 5,
  SLOW_RATE = 1 / 300,    -- while our messages don't echo back: 1 per 5 min until one does
  BUSY_HEARD = 20,        -- hold events/records while this many event/record messages were heard in 60 s ...
  HEARD_PER_SENDER = 4,   -- ... counting at most this many per sender (one chatty client can't stall everyone)
  INTAKE_PER_MIN = 15,    -- per sender on event/record prefixes; more is not read (a client sends at most 12 + burst)
  INTAKE_STATE_PER_MIN = 15, -- per sender on state prefixes
  ECHO_TIMEOUT = 120,     -- a sent message that never echoes counts as lost
  QUEUE_MAX = 40,
  QUEUE_MAX_WAIT = 1800,  -- an event not sent within 30 min -> "dropped" (the module keeps its copy)
  RECORD_MAX_WAIT = 300,  -- a record not started within 5 min is dropped whole
  RECORD_MAX_AGE = 600,   -- a started record still unfinished after 10 min is dropped
  HOLD_THROTTLED = 30,
  STATE_QUIET = 4,        -- state lane: skip if this client sent any GUILD addon message within 4 s ...
  STATE_MAX_60 = 10,      -- ... or 10 or more within 60 s (waived once when the caller is starving)
  STARVE = 30,            -- an event / record waiting this long goes out without a token (other addons' sends drain
                          -- the bucket; a chatty one would otherwise silence the suite). Still at most 1 own send per 5 s.
}
GS.CommConst = C -- internal numbers (read by tests); modules use GS.Wire.MAX_MSG

-- Internal state. GS.Comm.q (the event queue, q[1] = next) and GS.Comm.lastSent stay readable until Map moves onto
-- the scheduler (Stage 2c); nothing else outside this file may read them.
local S = {
  q = {},            -- event lane: { prefix, msg, t, onResult, channel }
  records = {},      -- record lane: { prefix, key, chunks, i, t, started, onDone, onDrop, channel }
  tokens = C.BURST, tokenAt = nil,
  hold = 0,
  heard = {},        -- GetTime() of counted event/record messages from others
  intake = {},       -- [senderKey] = { t, n, ns, h }
  inflight = {},     -- [prefix .. "\0" .. text] = { { t, onResult }, ... } oldest first
  sends = {},        -- GetTime() of every GUILD addon message this client sent (any addon, via the hook)
  prefixes = {},     -- prefix -> raw channel (own prefixes)
  tags = {},         -- RQE1 tag -> schema channel
  sent = 0, received = 0, echoed = 0, lost = 0, foreign = 0, dropped = 0,
}
GS.Comm = S

local function Result(cb, status) if cb then GS:Call(cb, status) end end

local function Rate() return S.slow and C.SLOW_RATE or C.RATE end
local function Refill(now)
  S.tokens = math.min(C.BURST, S.tokens + (now - (S.tokenAt or now)) * Rate())
  S.tokenAt = now
end

-- ok, reason
local function CanSend()
  if not GS.loggedIn then return false, "not logged in" end
  if GS:InInstance() then return false, "instance" end
  if InCombatLockdown and Plain(SafeCall(InCombatLockdown)) then return false, "combat" end
  if not Plain(SafeCall(IsInGuild)) then return false, "not in a guild" end
  return true
end
function GS:CanSend() return CanSend() end

local sending = false -- true while the scheduler itself calls SendAddonMessage (the hook ignores those)
local function SendRaw(prefix, msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "error" end
  sending = true
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "GUILD")
  sending = false
  S.sends[#S.sends + 1] = GetTime()
  if not ok then return "error" end
  if res == nil or res == true or res == 0 then return "ok" end
  if res == 3 or res == 8 then return "throttled" end -- [U] live values (ChatThrottleLib's fallback enum)
  return "error"
end

local function Prune(list, window, now)
  local i = 1
  while list[i] and now - list[i] > window do i = i + 1 end
  for _ = 2, i do table.remove(list, 1) end
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

local Pump -- forward

---------------------------------------------------------------------------
-- Lanes
---------------------------------------------------------------------------
-- Event lane. false, reason when it can't be queued (too long, can't send now, queue full).
local function QueueEvent(prefix, msg, onResult, channel)
  if #msg > C.MAX_MSG or msg:find("\0", 1, true) then return false, "too long" end
  local ok, why = CanSend()
  if not ok then return false, why end
  if #S.q >= C.QUEUE_MAX then return false, "queue full" end
  S.q[#S.q + 1] = { prefix = prefix, msg = msg, t = GetTime(), onResult = onResult, channel = channel }
  Pump()
  return true
end

-- Record lane: chunks go out one per token, whole or not at all.
local function QueueRecord(prefix, key, chunks, opts, channel)
  if type(chunks) ~= "table" or not chunks[1] then return false, "empty" end
  for _, c in ipairs(chunks) do
    if type(c) ~= "string" or #c > C.MAX_MSG or c:find("\0", 1, true) then return false, "too long" end
  end
  for i = #S.records, 1, -1 do
    local r = S.records[i]
    if r.prefix == prefix and r.key == key and not r.started then table.remove(S.records, i) end -- newest replaces
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

-- State lane: send now or say why not. opts.starving waives the STATE_QUIET / STATE_MAX_60 rules once (bucket may go to -1).
local function TrySend(prefix, msg, opts, channel)
  local now = GetTime()
  if #msg > C.MAX_MSG then return false, "too long" end
  local ok, why = CanSend()
  if not ok then return false, why end
  if now < S.hold then return false, "throttled (hold)" end
  if S.q[1] or S.records[1] then return false, "Ravenquill Expedition modules are waiting to send" end
  Prune(S.sends, 60, now)
  Refill(now)
  local starving = opts and opts.starving
  if not starving then
    local last = S.sends[#S.sends]
    if last and now - last < C.STATE_QUIET then return false, ("another addon sent < %d s ago"):format(C.STATE_QUIET) end
    if #S.sends >= C.STATE_MAX_60 then return false, ("%d+ guild addon messages in 60 s"):format(C.STATE_MAX_60) end
    if S.tokens < 1 then return false, "no send token" end
  end
  local r = SendRaw(prefix, msg)
  GS:Trace("comm.tx", r, prefix .. " " .. msg)
  if r == "throttled" then S.tokens, S.hold = 0, now + C.HOLD_THROTTLED; return false, "throttled" end
  if r ~= "ok" then S.hold = now + C.HOLD_THROTTLED; return false, "send error" end
  S.tokens = math.max(-1, S.tokens - 1)
  Inflight(prefix, msg, nil, now)
  if channel then channel.stats.sent = channel.stats.sent + 1 end
  Pump() -- keeps the echo watchdog ticking
  return true
end

-- Best effort, now (a "leaving" message at logout): charges the bucket, no checks but the instance rule.
local function SendNow(prefix, msg)
  if GS:InInstance() or #msg > C.MAX_MSG then return false end
  local r = SendRaw(prefix, msg)
  GS:Trace("comm.tx", r, prefix .. " " .. msg)
  Refill(GetTime())
  S.tokens = math.max(-1, S.tokens - 1)
  return r == "ok"
end

---------------------------------------------------------------------------
-- The pump
---------------------------------------------------------------------------
-- Everything waiting goes back to its module (entering an instance).
local function DropAll()
  local q, recs = {}, {}
  for i, it in ipairs(S.q) do q[i] = it end
  for i, r in ipairs(S.records) do recs[i] = r end
  for i = #S.q, 1, -1 do S.q[i] = nil end -- emptied in place: S.q may still be read by Map until Stage 2c
  for i = #S.records, 1, -1 do S.records[i] = nil end
  for _, it in ipairs(q) do Result(it.onResult, "deferred") end
  for _, r in ipairs(recs) do if r.onDrop then GS:Call(r.onDrop, "instance") end end
end

local function PumpOnce()
  local now = GetTime()
  Prune(S.heard, 60, now)
  Prune(S.sends, 60, now)
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
  -- echo watchdog: something was lost and nothing has come back for ECHO_TIMEOUT (since login or since the last
  -- echo) -> slow down until an echo returns. Said once per session.
  local since = S.lastEcho or S.firstSent
  if not S.slow and (S.lostSinceEcho or 0) > 0 and since and now - since > C.ECHO_TIMEOUT then
    S.slow = true
    GS:Trace("comm.slow", "no echo for " .. C.ECHO_TIMEOUT .. " s")
    if not S.slowSaid then
      S.slowSaid = true
      GS.Print(nil, "guild sync: our messages don't come back – sending slowly now (1 per 5 min).")
    end
  end
  if (S.q[1] or S.records[1]) and GS:InInstance() then DropAll() end
  for i = #S.q, 1, -1 do
    local it = S.q[i]
    if now - it.t > C.QUEUE_MAX_WAIT then table.remove(S.q, i); S.dropped = S.dropped + 1; Result(it.onResult, "deferred") end
  end
  for i = #S.records, 1, -1 do
    local r = S.records[i]
    if (not r.started and now - r.t > C.RECORD_MAX_WAIT) or (r.started and now - r.t > C.RECORD_MAX_AGE) then
      table.remove(S.records, i)
      S.dropped = S.dropped + 1
      if r.onDrop then GS:Call(r.onDrop, "timeout") end
    end
  end
  Refill(now)
  local item = S.q[1]
  local rec
  if not item then
    for _, r in ipairs(S.records) do if r.started then rec = r break end end
    rec = rec or S.records[1]
  end
  if not item and not rec then return next(S.inflight) ~= nil end
  if not CanSend() or now < S.hold or #S.heard >= C.BUSY_HEARD then return true end
  if S.tokens < 1 then
    -- starving: waited STARVE and our own last send is at least one refill period ago -> one goes out anyway
    local waited = now - (item and item.t or rec.t)
    if waited < C.STARVE or (S.lastSent and now - S.lastSent < 1 / C.RATE) then return true end
    GS:Trace("comm.starve", ("sending after %d s without a token"):format(waited))
  end
  local prefix, msg = item and item.prefix or rec.prefix, item and item.msg or rec.chunks[rec.i]
  local r = SendRaw(prefix, msg)
  GS:Trace("comm.tx", r, prefix == PREFIX and msg or (prefix .. " " .. msg))
  if r == "throttled" then
    S.tokens, S.hold = 0, now + C.HOLD_THROTTLED
    return true
  end
  S.tokens = math.max(-1, S.tokens - 1)
  if item then
    table.remove(S.q, 1)
    if r == "error" then Result(item.onResult, "deferred"); return true end
    Inflight(prefix, msg, item.onResult, now)
    if item.channel then item.channel.stats.sent = item.channel.stats.sent + 1 end
    return true
  end
  if r == "error" then
    for i, x in ipairs(S.records) do if x == rec then table.remove(S.records, i) break end end
    if rec.onDrop then GS:Call(rec.onDrop, "error") end
    return true
  end
  Inflight(prefix, msg, nil, now)
  if rec.channel then rec.channel.stats.sent = rec.channel.stats.sent + 1 end
  rec.started = true
  rec.i = rec.i + 1
  if rec.i > #rec.chunks then
    for i, x in ipairs(S.records) do if x == rec then table.remove(S.records, i) break end end
    if rec.onDone then GS:Call(rec.onDone) end
  end
  return true
end

Pump = function()
  if S.armed then return end
  S.armed = true
  C_Timer.After(1, function()
    S.armed = false
    -- RQ:Call: an error reaches BugSack, lastError and the Dev log; the pump keeps ticking after one
    local done, more = GS:Call(function() return true, PumpOnce() end)
    if not done then more = true end
    if more then C_Timer.After(4, Pump) end -- keep ticking while anything waits; refill is time based
  end)
end
GS.CommPump = Pump

---------------------------------------------------------------------------
-- Schema channels: mod:NewChannel{ tag, version } (wire "<tag>;<version>;<type>;<field>;...", prefix RQE1)
-- ch:Define(type, { lane = "event" | "state", from = "self" | "guild", fields = { { name, kind, ... }, ... } })
--   kinds: { name, "int", lo, hi }  { name, "b36", lo, hi }  { name, "text", maxBytes }  { name, "class" }
--          { name, "time" }  { name, "flag" }  { name, "enum", { "a", "b" } }  { name, "key" }
--          { name, "word", maxLen }  (letters and digits only, never shortened)
--   a field with opt = true may be empty (nil in the message table). from = "self": every "key" field must be the
--   sender (or there is none). A message that fails any check never reaches a handler (counted in ch:Status()).
-- ch:On(type, function(senderKey, msg) end)
-- ch:Send(type, msg, { onResult = fn(status) })   event lane: "delivered" | "lost" | "dropped"
-- ch:TrySend(type, msg, { starving })             state lane: ok, reason
---------------------------------------------------------------------------
local STATUS = { echo = "delivered", lost = "lost", deferred = "dropped" }
local Channel = {}
Channel.__index = Channel

local function Reject(ch, why)
  ch.stats.rejected[why] = (ch.stats.rejected[why] or 0) + 1
  GS:Trace("comm.reject", ch.name .. ": " .. why)
end

local function EncodeField(f, v)
  local kind = f[2]
  if v == nil then return f.opt and "" or nil end
  if kind == "int" or kind == "time" then
    if type(v) ~= "number" or v ~= v then return nil end
    return tostring(math.floor(v))
  elseif kind == "b36" then
    if type(v) ~= "number" then return nil end
    return W.b36(v)
  elseif kind == "text" then
    return W.Clean(v, f[3] or C.MAX_MSG)
  elseif kind == "class" then
    return tostring(W.CLASS_IDX[v] or 0)
  elseif kind == "flag" then
    return v and "1" or "0"
  elseif kind == "enum" then
    for _, e in ipairs(f[3] or {}) do if e == v then return v end end
    return nil
  elseif kind == "key" then
    v = Plain(v, "string")
    if not v or v == "" or v:find("[;|%c]") then return nil end
    return v
  elseif kind == "word" then
    v = tostring(v)
    if not v:match("^%w*$") or #v > (f[3] or 16) then return nil end
    return v
  end
end

local function DecodeField(f, s, now)
  local kind = f[2]
  if s == "" then
    if f.opt then return true, nil end
    if kind ~= "text" and kind ~= "word" then return false end
  end
  if kind == "int" then
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < (f[3] or -math.huge) or n > (f[4] or math.huge) or not s:match("^%-?%d+$") then return false end
    return true, n
  elseif kind == "time" then
    local n = tonumber(s)
    if not n or not s:match("^%d+$") or n < 1 or n > now + 300 then return false end
    return true, n
  elseif kind == "b36" then
    local n = W.n36(s)
    if not n or n < (f[3] or 0) or n > (f[4] or math.huge) then return false end
    return true, n
  elseif kind == "text" then
    return true, W.Clean(s, f[3] or C.MAX_MSG)
  elseif kind == "class" then
    local n = tonumber(s)
    local c = n and W.CLASSES[n]
    if not c then return false end
    return true, c
  elseif kind == "flag" then
    if s ~= "0" and s ~= "1" then return false end
    return true, s == "1"
  elseif kind == "enum" then
    for _, e in ipairs(f[3] or {}) do if e == s then return true, s end end
    return false
  elseif kind == "key" then
    if s:find("[|%c]") or #s > 64 then return false end
    return true, s
  elseif kind == "word" then
    if not s:match("^%w*$") or #s > (f[3] or 16) then return false end
    return true, s
  end
  return false
end

function Channel:Define(typ, def)
  assert(type(typ) == "string" and typ ~= "" and not typ:find("[;|]"), "Define: bad type")
  assert(type(def) == "table" and type(def.fields) == "table", "Define: fields missing")
  def.lane = def.lane or "event"
  assert(def.lane == "event" or def.lane == "state", "Define: lane must be event or state")
  self.types[typ] = def
end

function Channel:On(typ, fn) self.handlers[typ] = fn end

-- the wire text for a message, or nil, why
function Channel:Encode(typ, msg)
  local def = self.types[typ]
  if not def then return nil, "unknown type" end
  local function build(half)
    local out = { self.tag, tostring(self.version), typ }
    for _, f in ipairs(def.fields) do
      local v = msg[f[1]]
      if half and f[2] == "text" and type(v) == "string" then v = GS.Cut(v, math.floor((f[3] or C.MAX_MSG) / 2)) end
      local s = EncodeField(f, v)
      if s == nil then return nil, "field " .. f[1] end
      out[#out + 1] = s
    end
    return table.concat(out, ";")
  end
  local text, why = build(false)
  if text and #text > C.MAX_MSG then text, why = build(true) end
  if not text then return nil, why end
  if #text > C.MAX_MSG then return nil, "too long" end
  return text
end

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

-- body = everything after "<tag>;" -> type, msg; or nil, why (not counted; Receive counts)
function Channel:Decode(sender, body)
  if type(body) ~= "string" then return nil, "no body" end
  local f = W.Split(body)
  if f[1] ~= tostring(self.version) then return nil, "version " .. tostring(f[1]) end
  local def = self.types[f[2] or ""]
  if not def then return nil, "unknown type " .. tostring(f[2]) end
  -- missing trailing fields count as empty (rejected unless empty is allowed); extra trailing fields are ignored
  -- (a later version may append fields without breaking this one)
  local msg, now = {}, GS:Now()
  for i, fd in ipairs(def.fields) do
    local ok, v = DecodeField(fd, f[i + 2] or "", now)
    if not ok then return nil, "field " .. fd[1] end
    msg[fd[1]] = v
    if def.from == "self" and fd[2] == "key" and v ~= nil and GS:NormName(v) ~= sender then return nil, "not the sender" end
  end
  return f[2], msg
end

function Channel:Receive(sender, body)
  local typ, msg = self:Decode(sender, body)
  if not typ then return Reject(self, msg) end
  self.stats.received = self.stats.received + 1
  local h = self.handlers[typ]
  if h then GS:Call(h, sender, msg) end
end

function Channel:Status() return self.stats end

function GS.ModuleProto:NewChannel(spec)
  local tag, version = spec and spec.tag, spec and spec.version or 1
  if type(tag) ~= "string" or tag == "" or tag:find("[;|]") then error("NewChannel: bad tag " .. tostring(tag), 2) end
  if S.tags[tag] then error("NewChannel: tag '" .. tag .. "' is already taken", 2) end
  local ch = setmetatable({ name = (self.name or "?") .. "/" .. tag, tag = tag, version = version, types = {}, handlers = {},
    stats = { sent = 0, received = 0, rejected = {} } }, Channel)
  S.tags[tag] = ch
  return ch
end

---------------------------------------------------------------------------
-- Raw channels: mod:NewRawChannel{ prefix, lane } - the module's own prefix and bytes, the core's scheduler.
-- raw:OnMessage(function(senderKey, text, rawSender) end)   raw:OnEcho(function(text) end)
-- raw:Send(text, { onResult })            event lane ("delivered" | "lost" | "dropped")
-- raw:TrySend(text, { starving }) -> ok, reason              state lane
-- raw:SendNow(text) -> ok                  best effort now (a "leaving" message)
-- raw:SendRecord(key, chunks, { onDone, onDrop }) -> ok      record lane
-- raw:Cancel(key)   raw:Status()
---------------------------------------------------------------------------
local Raw = {}
Raw.__index = Raw

local function RegisterPrefix(prefix)
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  -- old API: true/false; modern: Enum.RegisterAddonMessagePrefixResult (0 success, 1 duplicate) [U on Forever]
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
function Raw:SendNow(text) return SendNow(self.prefix, text) end
function Raw:SendRecord(key, chunks, opts) return QueueRecord(self.prefix, key, chunks, opts, self) end
function Raw:Cancel(key) CancelRecords(self.prefix, key) end
function Raw:Status() return self.stats end

function GS.ModuleProto:NewRawChannel(spec)
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

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function OnAddonMessage(prefix, text, chan, sender)
  local raw = S.prefixes[prefix]
  if prefix ~= PREFIX and not raw then return end
  text, chan, sender = Plain(text, "string"), Plain(chan, "string"), Plain(sender, "string")
  if not (text and sender) or chan ~= "GUILD" then return end
  local key = GS:NormName(sender)
  if not key then return end
  if RavenquillExpeditionDB and not RavenquillExpeditionDB.diagSender then RavenquillExpeditionDB.diagSender = sender end
  if GS:IsMe(key) then
    local k = prefix .. "\0" .. text
    local list = S.inflight[k]
    if list and list[1] then
      local e = table.remove(list, 1)
      if not list[1] then S.inflight[k] = nil end
      S.echoed, S.lastEcho, S.lostSinceEcho = S.echoed + 1, GetTime(), 0
      if S.slow then S.slow = false end
      GS:Trace("comm.echo", prefix == PREFIX and text or (prefix .. " " .. text))
      Result(e.onResult, "echo")
    end
    if raw and raw.onEcho then GS:Call(raw.onEcho, text) end
    return
  end
  local state = raw and raw.lane == "state"
  local now = GetTime()
  local it = S.intake[key]
  if not it or now - it.t > 60 then it = { t = now, n = 0, ns = 0, h = 0 }; S.intake[key] = it end
  if state then
    it.ns = it.ns + 1
    if it.ns > C.INTAKE_STATE_PER_MIN then raw.stats.rejected.intake = (raw.stats.rejected.intake or 0) + 1 return end
  else
    it.n = it.n + 1
    if it.n > C.INTAKE_PER_MIN then GS:Trace("comm.drop", "intake limit " .. key) return end
    it.h = it.h + 1
    if it.h <= C.HEARD_PER_SENDER then S.heard[#S.heard + 1] = now end
  end
  S.received = S.received + 1
  GS:NotePeer(key)
  GS:Trace("comm.rx", key, prefix == PREFIX and text or (prefix .. " " .. text))
  if raw then
    raw.stats.received = raw.stats.received + 1
    if raw.onMessage then GS:Call(raw.onMessage, key, text, sender) end
    return
  end
  local tag, body = text:match("^([^;]+);(.*)$")
  local ch = tag and S.tags[tag]
  if ch then return ch:Receive(key, body) end
end

---------------------------------------------------------------------------
-- State for diagnostics and modules
---------------------------------------------------------------------------
function GS:CommState()
  local inflight = 0
  for _, list in pairs(S.inflight) do inflight = inflight + #list end
  local chunks = 0
  for _, r in ipairs(S.records) do chunks = chunks + #r.chunks - r.i + 1 end
  return { tokens = S.tokens, slow = S.slow and true or false, hold = math.max(0, S.hold - GetTime()), queued = #S.q,
    records = #S.records, chunks = chunks, inflight = inflight, sent = S.sent, delivered = S.echoed, lost = S.lost,
    received = S.received, foreign = S.foreign, hooked = S.hooked and true or false, lastSent = S.lastSent }
end

-- leave slow mode (a "retry" button): the next messages go out at the normal pace
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

-- One budget per client: GUILD addon messages this client sends without the scheduler (other addons, and suite
-- modules not yet on it) use up our tokens too, so the suite as a whole stays within one client's pace.
-- [U] hooksecurefunc on a C_ChatInfo function on Forever; CommStatus shows "foreign n" when it works.
if hooksecurefunc and C_ChatInfo and C_ChatInfo.SendAddonMessage then
  pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", function(prefix, _, chan)
    if sending or Plain(chan, "string") ~= "GUILD" then return end
    local now = GetTime()
    S.sends[#S.sends + 1] = now
    Refill(now)
    S.tokens = math.max(0, S.tokens - 1) -- other addons' sends empty the bucket but never put us in debt
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
