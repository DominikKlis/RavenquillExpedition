-- Guild sync (plan rev 4, section D): GUILD channel only, no whispers.
--   Q;<version>                                         "I'm here" (once per login)
--   S;<specIndex>;<ts>                                  the sender's own spec (plan F8.4): index into
--      GCA.SPEC_LIST (Spec.lua, append-only), both base36. A separate type, because 0.2.0 drops any
--      G message without exactly 8 fields and ignores unknown types.
--   G;<subject>;<class>;<level>;<ts>;<src>;<i>/<n>;<entries>  one gear record in n chunks
--      subject "" = the sender's own gear (src "s"); otherwise gear the sender inspected (src "i")
--      entries = <slot>=<item string> joined by ","; numbers in base36, viewer fields blank,
--      a non-numeric field (crafter GUID) is sent as "~<text>".
-- Paced far below what Forever is known to drop (Overlord SyncGuild.lua:17-46).
local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local SafeCall, IsSecret = GCA.SafeCall, GCA.IsSecret

local PREFIX = "GCAdv1"
local VERSION = "2"
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_IDX = {}
for i, c in ipairs(CLASSES) do CLASS_IDX[c] = i end
local RANK = { self = 2, inspect = 1 }
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local C = {                 -- tunables (plan D3/D5)
  MAX_MSG = 250,            -- bytes per message (limit 255)
  MAX_CHUNKS = 6,
  BURST = 2, RATE = 1 / 30, -- GUILD bucket
  BUSY_HEARD = 8,           -- hold while this many GUILD addon messages were heard in 60 s
  HEARD_PER_SENDER = 4,     -- at most this many per sender per minute count towards BUSY_HEARD (BURST + 60 s * RATE)
  HOLD_THROTTLED = 10,
  QUEUE_MAX_WAIT = 300,     -- a record not started within this is dropped (whole)
  QUEUE_MAX_AGE = 600,      -- a started record still unfinished after this is dropped
  BUFFER_EXPIRE = 180,      -- incomplete received record, after its last chunk
  ECHO_TIMEOUT = 300,
  INTAKE_PER_MIN = 12,
  Q_MIN_DELAY = 20, Q_JITTER = 20, Q_RELOAD_GAP = 900,
  ANSWER_MIN = 5, ANSWER_JITTER = 25,
  OWN_DEBOUNCE = 20, OWN_SPACING = 120,
  PEER_VALID = 86400,       -- a peer heard within this counts as "someone listens" (persisted)
  RELAY_SPACING = 60, RELAY_MIN = 3, RELAY_JITTER = 7, RELAY_MAX = 10,
  ADDON_USER_FRESH = 3600,  -- skip relaying someone heard running the addon this recently
  FUTURE_SLACK = 120,
}
GCA.SyncConst = C

local S = {
  q = {},            -- send queue: { tag, chunks, i, t, started, onDone }
  tokens = C.BURST, tokenAt = nil,
  hold = 0,
  heard = {},        -- times of GUILD addon messages heard from others
  intake = {},       -- [key] = { t, n }
  peers = {},        -- [key] = GetTime() heard this session
  addonUsers = {},   -- [key] = GetTime() heard sending their OWN gear or Q
  buffers = {},      -- reassembly
  relayPending = {}, -- [key] = queued-at GetTime()
  relayHeard = {},   -- [key] = highest ts someone else relayed for this subject
  relayHeardSig = {},-- [key] = gear signature of the last complete relay heard for this subject
  received = 0, sent = 0,
}
GCA.Sync = S

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function b36(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return "-" .. b36(-n) end
  local s = ""
  repeat
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  until n == 0
  return s
end
local function n36(s)
  if type(s) ~= "string" or s == "" or #s > 8 or not s:match("^%w+$") then return nil end
  return tonumber(s, 36)
end
GCA.b36, GCA.n36 = b36, n36

local function Settings() return GCA.db and GCA.db.settings end
local function Enabled()
  local s = Settings()
  return s and s.sync and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage and true or false
end
local function InInstance() return (SafeCall(IsInInstance)) and true or false end

-- persisted per character (plan F#11)
local function CharState()
  local db = GCA.db
  db.sync = db.sync or {}
  local key = GCA.charKey or "?"
  db.sync[key] = db.sync[key] or {}
  return db.sync[key]
end

local function Stamp(m) return m and (m.ts or m.time) or 0 end

local function PeerKnown()
  if next(S.peers) then return true end
  local at = CharState().peerAt
  return at and GCA:Now() - at < C.PEER_VALID or false
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
-- One item string -> wire form. Returns nil if a field can't be carried losslessly.
function GCA:EncodeItem(link)
  local norm = self:NormItem(link)
  if not norm then return end
  local f = self.SplitColon(norm)
  for i, v in ipairs(f) do
    if v == "" then
      -- keep
    elseif v:match("^%d+$") then f[i] = b36(v)
    elseif v:match("^%-%d+$") then f[i] = "-" .. b36(v:sub(2))
    elseif v:match("^[%w%-]+$") then f[i] = "~" .. v
    else return end
  end
  return table.concat(f, ":")
end

function GCA:DecodeItem(s)
  local f = self.SplitColon(s)
  for i, v in ipairs(f) do
    if v == "" then
      -- keep
    elseif v:sub(1, 1) == "~" then
      v = v:sub(2)
      if not v:match("^[%w%-]+$") then return end
      f[i] = v
    elseif v:sub(1, 1) == "-" then
      local n = n36(v:sub(2)); if not n then return end
      f[i] = tostring(-n)
    else
      local n = n36(v); if not n then return end
      f[i] = tostring(n)
    end
  end
  local id = tonumber(f[1])
  if not id or id < 1 or id >= 1e7 then return end
  return "item:" .. table.concat(f, ":")
end

-- A record -> list of chunk messages (nil if it would need too many).
function GCA:EncodeRecord(m, subject)
  local src = subject == "" and "s" or "i"
  local r = subject ~= "" and self.roster[subject]
  local class = m.class or (r and r.class)
  local level = m.level or (r and r.level)
  -- receivers reject class 0 / level 0, so don't send a record we can't describe
  if not CLASS_IDX[class or ""] or type(level) ~= "number" or level < 1 then return end
  local head = table.concat({ "G", subject, b36(CLASS_IDX[class]), b36(level), b36(Stamp(m)), src }, ";")
  local entries = {}
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local e = m.items and self:EncodeItem(m.items[slot])
    if e then
      e = b36(slot) .. "=" .. e
      if #e <= 80 then entries[#entries + 1] = e end
    end
  end
  local budget = C.MAX_MSG - #head - #";9/9;"
  local chunks, cur, len = {}, {}, 0
  for _, e in ipairs(entries) do
    if len > 0 and len + 1 + #e > budget then chunks[#chunks + 1] = cur; cur, len = {}, 0 end
    cur[#cur + 1] = e
    len = len + (len > 0 and 1 or 0) + #e
  end
  chunks[#chunks + 1] = cur
  if #chunks > C.MAX_CHUNKS then return end
  local out = {}
  for i, list in ipairs(chunks) do
    out[i] = head .. ";" .. i .. "/" .. #chunks .. ";" .. table.concat(list, ",")
  end
  return out
end

---------------------------------------------------------------------------
-- Sending: one queue of whole records, GUILD token bucket, echo watchdog
---------------------------------------------------------------------------
local function Pump() end -- forward

local function Enqueue(tag, chunks, onDone)
  if not (chunks and chunks[1]) then return end
  for i = #S.q, 1, -1 do
    if S.q[i].tag == tag and not S.q[i].started then table.remove(S.q, i) end -- newest replaces
  end
  S.q[#S.q + 1] = { tag = tag, chunks = chunks, i = 1, t = GetTime(), onDone = onDone }
  Pump()
end

local function SendRaw(msg)
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return "error" end
  if res == nil or res == true or res == 0 then return "ok" end
  if res == 3 or res == 8 then return "throttled" end
  return "error"
end

local function PumpOnce()
  local now = GetTime()
  for i = #S.heard, 1, -1 do if now - S.heard[i] > 60 then table.remove(S.heard, i) end end
  -- drop records that waited too long (never half: a started one is only dropped when stuck)
  local ownDropped = false
  for i = #S.q, 1, -1 do
    local it = S.q[i]
    if (not it.started and now - it.t > C.QUEUE_MAX_WAIT) or (it.started and now - it.t > C.QUEUE_MAX_AGE) then
      table.remove(S.q, i)
      if it.tag == "self" then ownDropped = true end
    end
  end
  -- our own record is still owed: try again later instead of waiting for the next event
  if ownDropped then C_Timer.After(C.OWN_SPACING, function() SafeCall(GCA.CheckOwn, GCA, false) end) end
  -- echo watchdog (plan D5, F#10): stop sending if our messages never come back
  if S.echoWait and now - S.echoWait > C.ECHO_TIMEOUT and not S.stopped then
    S.stopped = true
    GCA.Print(L.SYNC_STOPPED_MSG)
    if GCA.Invalidate then GCA:Invalidate() end
  end
  S.tokens = math.min(C.BURST, S.tokens + (now - (S.tokenAt or now)) * C.RATE)
  S.tokenAt = now
  local item = S.q[1]
  -- keep ticking while we wait for our echo, so the watchdog can fire after the last send
  if not item then return S.echoWait ~= nil and not S.stopped end
  if not Enabled() or InInstance() or InCombatLockdown() or S.stopped then return true end
  if now < S.hold or #S.heard >= C.BUSY_HEARD or S.tokens < 1 then return true end
  local r = SendRaw(item.chunks[item.i])
  if r == "throttled" then
    S.tokens, S.hold = 0, now + C.HOLD_THROTTLED
    return true
  end
  S.tokens = S.tokens - 1
  if r == "error" then
    table.remove(S.q, 1)
    if item.tag == "self" then C_Timer.After(C.OWN_SPACING, function() SafeCall(GCA.CheckOwn, GCA, false) end) end
    return #S.q > 0
  end
  S.sent = S.sent + 1
  S.echoWait = S.echoWait or now
  item.started = true
  item.i = item.i + 1
  if item.i > #item.chunks then
    table.remove(S.q, 1)
    if item.onDone then SafeCall(item.onDone) end
  end
  -- keep ticking while the echo is outstanding so the watchdog can fire
  return #S.q > 0 or (S.echoWait ~= nil and not S.stopped)
end

Pump = function()
  if S.armed then return end
  S.armed = true
  C_Timer.After(1, function()
    S.armed = false
    local ok, more = pcall(PumpOnce)
    if ok and more then Pump() end
  end)
end
GCA.SyncPump = Pump

---------------------------------------------------------------------------
-- Own gear: "send until sent" (plan D3.3, F#3)
---------------------------------------------------------------------------
local function OwnRecord() return GCA.playerKey and GCA.db.members[GCA.playerKey] end

local function OwnDue()
  local m = OwnRecord()
  if not (m and m.items) then return false end
  return S.owed or Stamp(m) ~= CharState().sentTs
end

local function QueueOwn()
  local m = OwnRecord()
  if not m then return end
  local ts, queuedAt = Stamp(m), GetTime()
  Enqueue("self", GCA:EncodeRecord(m, ""), function()
    CharState().sentTs = ts
    -- a Q that arrived after we started may have missed the first chunks: still owed then
    if (S.lastQAt or -1e9) <= queuedAt then S.owed = false end
    S.ownSentAt = GetTime()
  end)
end

-- Schedules our own broadcast if it is due. `answer` = reply to a Q (no 120 s spacing).
function GCA:CheckOwn(answer)
  if not Enabled() or not PeerKnown() or InInstance() then return end
  local now = GetTime()
  -- a Q means we owe one broadcast, unless one already went out after it (cleared on send)
  if answer then S.owed = true; S.lastQAt = now; S.specOwed = true end
  SafeCall(self.CheckOwnSpec, self)
  if not OwnDue() then return end
  if S.ownTimer then return end -- one pending broadcast absorbs further triggers (F#2)
  local delay
  if answer then
    delay = C.ANSWER_MIN + math.random() * C.ANSWER_JITTER
  else
    delay = math.max(C.OWN_DEBOUNCE, (S.ownSentAt or -1e9) + C.OWN_SPACING - now)
  end
  S.ownTimer = true
  C_Timer.After(delay, function()
    S.ownTimer = nil
    if not Enabled() or InInstance() then return end
    -- skipped if a broadcast went out meanwhile (that cleared `owed`) and gear didn't change (F#2)
    if not OwnDue() then return end
    if InCombatLockdown() then return end -- still owed; PLAYER_REGEN_ENABLED re-checks
    QueueOwn()
  end)
end

function GCA:OnOwnGearChanged() self:CheckOwn(false) end

---------------------------------------------------------------------------
-- Own spec: "S;<index>;<ts>" whenever it changes, once per session, and in answer to a Q
---------------------------------------------------------------------------
function GCA:CheckOwnSpec()
  if not self.OwnAnnouncedSpec then return end
  local idx, ownSpec = self:OwnAnnouncedSpec()
  if not idx then return end
  local cs = CharState()
  if cs.specIdx ~= idx then cs.specIdx, cs.specTs = idx, self:Now() end
  if self.StoreOwnSpec then SafeCall(self.StoreOwnSpec, self, ownSpec, cs.specTs) end -- K0/L5
  if not Enabled() or not PeerKnown() or InInstance() then return end
  if cs.sentSpec == idx and cs.sentSpecTs == cs.specTs and not S.specOwed then return end
  if S.specTimer then return end
  S.specTimer = true
  C_Timer.After(C.OWN_DEBOUNCE + math.random() * 10, function()
    S.specTimer = nil
    if not Enabled() or InInstance() then return end
    local i, ts = cs.specIdx, cs.specTs
    if not i then return end
    if cs.sentSpec == i and cs.sentSpecTs == ts and not S.specOwed then return end
    Enqueue("spec", { "S;" .. b36(i) .. ";" .. b36(ts) }, function()
      cs.sentSpec, cs.sentSpecTs = i, ts
      S.specOwed = false
    end)
  end)
end

---------------------------------------------------------------------------
-- Inspect relay (plan D3.4, F#5)
---------------------------------------------------------------------------
local function DrainRelays() end -- forward

function GCA:RelayInspect(key)
  if not Enabled() or key == self.playerKey or not self.roster[key] then return end
  S.relayPending[key] = GetTime()
  -- keep at most RELAY_MAX, dropping the oldest
  local n, oldestK, oldestT = 0, nil, math.huge
  for k, t in pairs(S.relayPending) do
    n = n + 1
    if t < oldestT then oldestK, oldestT = k, t end
  end
  if n > C.RELAY_MAX then S.relayPending[oldestK] = nil end
  DrainRelays()
end

DrainRelays = function()
  if S.relayTimer or not next(S.relayPending) then return end
  local now = GetTime()
  local wait = math.max(0, (S.lastRelay or -1e9) + C.RELAY_SPACING - now) + C.RELAY_MIN + math.random() * C.RELAY_JITTER
  S.relayTimer = true
  C_Timer.After(wait, function()
    S.relayTimer = nil
    if not Enabled() or InInstance() or not PeerKnown() then
      -- nobody to tell or not allowed now; try again later
      C_Timer.After(C.RELAY_SPACING, DrainRelays)
      return
    end
    -- oldest pending subject
    local key, t = nil, math.huge
    for k, at in pairs(S.relayPending) do if at < t then key, t = k, at end end
    if not key then return end
    S.relayPending[key] = nil
    local m = GCA.db.members[key]
    local fresh = S.addonUsers[key] and GetTime() - S.addonUsers[key] < C.ADDON_USER_FRESH
    -- someone else already relayed it: as new as ours, or the very same gear (seen a bit earlier)
    local already = m and ((S.relayHeard[key] or -1) >= Stamp(m) or S.relayHeardSig[key] == GCA:GearSignature(m.items))
    if m and m.source == "inspect" and not m.from and not fresh and not already then
      S.lastRelay = GetTime()
      Enqueue("r:" .. key, GCA:EncodeRecord(m, key))
    end
    DrainRelays()
  end)
end

---------------------------------------------------------------------------
-- Login request (plan D3.1)
---------------------------------------------------------------------------
function GCA:SendQ()
  if not Enabled() then return end
  local cs = CharState()
  if cs.lastQ and self:Now() - cs.lastQ < C.Q_RELOAD_GAP then
    S.qSkipped = true
  else
    cs.lastQ = self:Now()
    Enqueue("Q", { "Q;" .. VERSION })
  end
  S.owed = true -- once per session our own gear goes out (also makes the Q sender broadcast it)
  S.specOwed = true
  self:CheckOwn(false)
end

local function TryQ(tries)
  if S.qDone then return end
  if Enabled() and GCA.rosterLoaded and not InInstance() then
    S.qDone = true
    GCA:SendQ()
  elseif (tries or 0) < 60 then
    C_Timer.After(10, function() TryQ((tries or 0) + 1) end)
  end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function ValidChunk(f)
  -- f = { "G", subject, class, level, ts, src, "i/n", entries }
  local subject, class, level, ts, src = f[2], n36(f[3]), n36(f[4]), n36(f[5]), f[6]
  local i, n = (f[7] or ""):match("^(%d)/(%d)$")
  i, n = tonumber(i), tonumber(n)
  if not (class and class >= 1 and class <= #CLASSES) then return end
  if not (level and level >= 1 and level <= 60) then return end
  if not ts or ts > GCA:Now() + C.FUTURE_SLACK then return end
  if not (i and n and i >= 1 and i <= n and n <= C.MAX_CHUNKS) then return end
  if subject == "" then
    if src ~= "s" then return end
  else
    if src ~= "i" then return end
  end
  local items = {}
  for e in (f[8] or ""):gmatch("[^,]+") do
    if #e > 80 then return end
    local sc, body = e:match("^(%w+)=([%w:%-~]*)$")
    local slot = n36(sc)
    if not (slot and GCA.IS_SYNC_SLOT[slot]) then return end
    local link = GCA:DecodeItem(body)
    if not link then return end
    items[slot] = link
  end
  return { subject = subject, class = CLASSES[class], level = level, ts = ts, src = src, i = i, n = n, items = items }
end

function GCA:ApplyRecord(senderKey, r)
  local direct = r.subject == ""
  local key = direct and senderKey or self:NormName(r.subject)
  if not key or key == self.playerKey then return end
  if not direct and not self.roster[key] then return end
  local source = direct and "self" or "inspect"
  local m = self.db.members[key]
  if m then
    local old = Stamp(m)
    if r.ts < old then return end
    if r.ts == old and RANK[source] <= (RANK[m.source] or 0) then return end
  end
  m = m or {}
  -- K0/L6: m.time = when WE got the data (UI "… ago", pruning); m.ts keeps the gear's own stamp (merge/relay)
  m.items, m.ts, m.time, m.source = r.items, r.ts, time(), source
  m.from = (not direct) and senderKey or nil
  m.class, m.level = r.class, r.level
  self.db.members[key] = m
  self:ClearWornCrafted(key, m.items) -- H5.1: a synced record showing the crafted item worn ends the mark
  S.received = S.received + 1
  self:Invalidate()
  return true
end

local function OnGear(senderKey, f)
  local r = ValidChunk(f)
  if not r then return end
  if r.subject ~= "" then
    local subj = GCA:NormName(r.subject)
    if not subj or not GCA.roster[subj] then return end
    -- someone else relays this subject: cancel ours if theirs is as new
    if r.i == r.n then S.relayHeard[subj] = math.max(S.relayHeard[subj] or -1, r.ts) end
  else
    S.addonUsers[senderKey] = GetTime()
  end
  local id = senderKey .. "\0" .. r.subject .. "\0" .. r.ts
  local now = GetTime()
  for k, b in pairs(S.buffers) do if now - b.last > C.BUFFER_EXPIRE then S.buffers[k] = nil end end
  local b = S.buffers[id]
  if not b or b.n ~= r.n then
    b = { n = r.n, parts = {}, got = 0 }
    S.buffers[id] = b
  end
  b.last = now
  if not b.parts[r.i] then b.parts[r.i] = r; b.got = b.got + 1 end
  if b.got < b.n then return end
  S.buffers[id] = nil
  local items = {}
  for _, part in ipairs(b.parts) do for slot, link in pairs(part.items) do items[slot] = link end end
  if r.subject ~= "" then
    local subj = GCA:NormName(r.subject)
    if subj then S.relayHeardSig[subj] = GCA:GearSignature(items) end
  end
  GCA:ApplyRecord(senderKey, { subject = r.subject, class = r.class, level = r.level, ts = r.ts, items = items })
end

-- S;<index>;<ts>: the sender's own spec. Ignored when the spec's class contradicts what we know.
function GCA:OnSpecMessage(senderKey, f)
  local idx, ts = n36(f[2]), n36(f[3])
  local entry = idx and self.SPEC_LIST and self.SPEC_LIST[idx]
  if not entry or not ts or ts > self:Now() + C.FUTURE_SLACK then return end
  local class, spec = entry[1], entry[2]
  local m, r = self.db.members[senderKey], self.roster[senderKey]
  local known = (r and r.class) or (m and m.class)
  if known and known ~= class then return end
  if self:StoreSpec(senderKey, class, { spec = spec, src = "sync", ts = ts }) then S.specsReceived = (S.specsReceived or 0) + 1 end
  return true
end

function GCA:OnAddonMessage(text, chan, sender)
  if IsSecret(text) or IsSecret(chan) or IsSecret(sender) then return end
  if type(text) ~= "string" or type(sender) ~= "string" or chan ~= "GUILD" then return end
  local key = self:NormName(sender)
  if not key then return end
  -- our own echo first, before the instance guard (F#10). Also accept "<us>-<realm>" in case the
  -- sender format differs from our key (B6 is only verified in other addons' code).
  if key == self.playerKey or (self.playerKey and key:match("^(.+)%-[^%-]+$") == self.playerKey) then
    S.echoWait = nil
    S.echoSeen = GetTime()
    S.echoRaw = sender
    return
  end
  S.lastRaw = sender
  if InInstance() or not (self.db and self.db.settings.sync) then return end
  local now = GetTime()
  local it = S.intake[key]
  if not it or now - it.t > 60 then it = { t = now, n = 0, h = 0 }; S.intake[key] = it end
  it.n = it.n + 1
  if it.n > C.INTAKE_PER_MIN then return end
  -- K0/M1: only messages that pass the intake cap count towards the "guild is busy" hold, and each
  -- sender at most HEARD_PER_SENDER per minute (what a well-behaved client can send), so one chatty
  -- or broken client can't stall everyone's sending
  it.h = (it.h or 0) + 1
  if it.h <= C.HEARD_PER_SENDER then S.heard[#S.heard + 1] = now end
  local first = not next(S.peers)
  S.peers[key] = now
  CharState().peerAt = self:Now()
  local f = { strsplit(";", text) }
  if f[1] == "G" and #f == 8 then
    OnGear(key, f)
  elseif f[1] == "S" and #f == 3 then
    self:OnSpecMessage(key, f)
  elseif f[1] == "Q" then
    S.addonUsers[key] = now
    self:CheckOwn(true)
  end
  if first then self:CheckOwn(false); DrainRelays() end
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function GCA:SyncPeerCount(window)
  local n, now = 0, GetTime()
  for _, t in pairs(S.peers) do if now - t < (window or 3600) then n = n + 1 end end
  return n
end

function GCA:SyncStatusLine()
  local s = Settings()
  if not (s and s.sync) then return "|cff888888" .. L.SYNC_OFF .. "|r" end
  if not IsInGuild() then return "|cff888888" .. L.SYNC_NOGUILD .. "|r" end
  if S.stopped then return "|cffff5555" .. L.SYNC_PAUSED .. "|r" end
  local n = self:SyncPeerCount(3600)
  return string.format(L.SYNC_PEERS, n)
end

-- K1: the same states for the status dot in the window header: "off", "noguild", "paused", "ok" (a guildie with the
-- addon heard in the last hour) or "idle" (on, nobody heard yet).
function GCA:SyncState()
  local s = Settings()
  if not (s and s.sync) then return "off" end
  if not IsInGuild() then return "noguild" end
  if S.stopped then return "paused" end
  return self:SyncPeerCount(3600) > 0 and "ok" or "idle"
end

function GCA:SyncStatus()
  local s = Settings()
  local chunks = 0
  for _, it in ipairs(S.q) do chunks = chunks + (#it.chunks - it.i + 1) end
  local relayN = 0
  for _ in pairs(S.relayPending) do relayN = relayN + 1 end
  self.Print(string.format("%s. Received %d record(s) and %d spec(s) this session, sent %d message(s), queued %d message(s), %d relay(s) pending. Own echo: %s.",
    self:SyncStatusLine(), S.received, S.specsReceived or 0, S.sent, chunks, relayN,
    S.echoSeen and (math.floor(GetTime() - S.echoSeen) .. " s ago") or (S.echoWait and "waiting" or "nothing sent yet")))
  if s and s.sync and S.qSkipped then self.Print("(Login request skipped: sent less than 15 min ago on this character.)") end
  -- for checking the sender name format in game (plan B6)
  self.Print(string.format("Names: you are '%s'; last own echo came as '%s'; last guildie message from '%s'.",
    tostring(self.playerKey), tostring(S.echoRaw or "-"), tostring(S.lastRaw or "-")))
end

function GCA:SyncRetry()
  local wasPaused = S.stopped
  S.stopped, S.echoWait = nil, nil
  self:CheckOwn(false)
  Pump()
  if wasPaused then self.Print(L.SYNC_RESUMED) end -- K0/L7: only when it actually was paused
  self:Invalidate()
end

---------------------------------------------------------------------------
-- Hide nothing: we never whisper, so no "No player named" filter is needed.
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event, prefix, ...)
  if event == "CHAT_MSG_ADDON" then
    if IsSecret(prefix) or prefix ~= PREFIX or not GCA.db then return end
    local text, chan, sender = ...
    SafeCall(GCA.OnAddonMessage, GCA, text, chan, sender)
  elseif event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    C_Timer.After(C.Q_MIN_DELAY + math.random() * C.Q_JITTER, function() TryQ(0) end)
  elseif event == "PLAYER_ENTERING_WORLD" then
    if InInstance() then
      wipe(S.q)
      S.echoWait = nil -- don't blame the server for messages we stopped receiving (F#10)
    else
      C_Timer.After(5, function() SafeCall(GCA.CheckOwn, GCA, false); SafeCall(GCA.CheckOwnSpec, GCA); DrainRelays() end)
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    SafeCall(GCA.CheckOwn, GCA, false)
    if S.q[1] then Pump() end
  end
end)
