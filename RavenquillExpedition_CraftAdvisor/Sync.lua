-- Guild sync: GUILD channel only, no whispers.
--   Q;<version>                                         "I'm here" (once per login)
--   S;<specIndex>;<ts>                                  the sender's own spec: index into
--      GCA.SPEC_LIST (Spec.lua, append-only), both base36. A separate type, because 0.2.0 drops any
--      G message without exactly 8 fields and ignores unknown types.
--   G;<subject>;<class>;<level>;<ts>;<src>;<i>/<n>;<entries>  one gear record in n chunks
--      subject "" = the sender's own gear (src "s"); otherwise gear the sender inspected (src "i")
--      entries = <slot>=<item string> joined by ","; numbers in base36, viewer fields blank,
--      a non-numeric field (crafter GUID) is sent as "~<text>".
-- Sent through the core's scheduler on its record lane (a raw channel keeps these exact bytes): the core paces every
-- module of the suite together, holds in instances and combat, checks the echo and limits what it reads per sender
-- (docs/sync.md). This file only decides WHAT to send and WHEN it is owed.
local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = GCA.RQ
local W = RQ.Wire

local PREFIX = "GCAdv1"
local VERSION = "2"
-- classes by the core's wire index; only 1-9 (the classes of this game) are part of this format
local CLASSES, CLASS_IDX, MAX_CLASS = W.CLASSES, W.CLASS_IDX, 9
local RANK = { self = 2, inspect = 1 }

local C = {                 -- tunables; pacing, holds and intake limits are the core's
  MAX_MSG = W.MAX_MSG,      -- bytes per message (limit 255)
  MAX_CHUNKS = 6,
  BUFFER_EXPIRE = 180,      -- incomplete received record, after its last chunk
  Q_MIN_DELAY = 20, Q_JITTER = 20, Q_RELOAD_GAP = 900,
  ANSWER_MIN = 5, ANSWER_JITTER = 25,
  OWN_DEBOUNCE = 20, OWN_SPACING = 120,
  PEER_VALID = 86400,       -- a peer heard within this counts as "someone listens" (persisted)
  RELAY_SPACING = 60, RELAY_MIN = 3, RELAY_JITTER = 7, RELAY_MAX = 10,
  ADDON_USER_FRESH = 3600,  -- skip relaying someone heard running the addon this recently
  FUTURE_SLACK = 120,
  SELF_PROTECT = 30 * 86400, -- a member's own record younger than this is never replaced by a relayed one
}
GCA.SyncConst = C

local S = {
  pending = {},      -- [record key] = chunks of our record waiting in the core's record lane
  peers = {},        -- [key] = GetTime() heard this session
  addonUsers = {},   -- [key] = GetTime() heard sending their OWN gear or Q
  buffers = {},      -- reassembly
  relayPending = {}, -- [key] = queued-at GetTime()
  relayHeard = {},   -- [key] = highest ts someone else relayed for this subject
  relayHeardSig = {},-- [key] = gear signature of the last complete relay heard for this subject
  received = 0, sent = 0,
}
GCA.Sync = S

-- our prefix and bytes on the core's record lane: a record goes out whole or not at all; a newer unstarted record
-- with the same key ("self", "Q", "spec", "r:<member>") replaces the older one
local raw = GCA:NewRawChannel({ prefix = PREFIX, lane = "record" })
GCA.syncChannel = raw

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- base 36 from the core: b36s writes negatives as "-<digits>", n36(s, true) also reads upper case
local b36, n36 = W.b36s, W.n36
GCA.b36 = b36

local function Settings() return GCA.db and GCA.db.settings end
local function Enabled()
  local s = Settings()
  return s and s.sync and RQ.Plain(RQ.SafeCall(IsInGuild)) and true or false
end
local function InInstance() return RQ:InInstance() end

-- persisted per character
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
      local n = n36(v:sub(2), true); if not n then return end
      f[i] = tostring(-n)
    else
      local n = n36(v, true); if not n then return end
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
  local r = subject ~= "" and RQ:RosterEntry(subject)
  local class = m.class or (r and r.class)
  local level = m.level or (r and r.level)
  -- receivers reject class 0 / level 0, so don't send a record we can't describe
  if not CLASS_IDX[class or ""] or CLASS_IDX[class] > MAX_CLASS or type(level) ~= "number" or level < 1 then return end
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
-- Sending: whole records on the core's record lane
---------------------------------------------------------------------------
-- onDone runs when the last chunk went out. A record the core drops (not started within 5 min, unfinished after
-- 10 min, a send error, entering an instance) is still owed when it is our own: CheckOwn looks again later.
local function Enqueue(tag, chunks, onDone)
  if not (chunks and chunks[1]) then return end
  S.pending[tag] = #chunks
  raw:SendRecord(tag, chunks, {
    onDone = function()
      S.pending[tag] = nil
      S.sent = S.sent + #chunks
      if onDone then onDone() end
    end,
    onDrop = function(why)
      S.pending[tag] = nil
      if tag == "self" and why ~= "instance" then
        C_Timer.After(C.OWN_SPACING, function() RQ:Call(GCA.CheckOwn, GCA, false) end)
      end
    end,
  })
end

---------------------------------------------------------------------------
-- Own gear: "send until sent"
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
  self:CheckOwnSpec()
  if not OwnDue() then return end
  if S.ownTimer then return end -- one pending broadcast absorbs further triggers
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
    -- skipped if a broadcast went out meanwhile (that cleared `owed`) and gear didn't change
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
  if self.StoreOwnSpec then self:StoreOwnSpec(ownSpec, cs.specTs) end -- for this account's alts
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
-- Inspect relay
---------------------------------------------------------------------------
local function DrainRelays() end -- forward

function GCA:RelayInspect(key)
  if not Enabled() or key == self.playerKey or not RQ:RosterEntry(key) then return end
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
-- Login request
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
  if Enabled() and RQ:RosterComplete() and not InInstance() then
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
  local subject, class, level, ts, src = f[2], n36(f[3], true), n36(f[4], true), n36(f[5], true), f[6]
  local i, n = (f[7] or ""):match("^(%d)/(%d)$")
  i, n = tonumber(i), tonumber(n)
  if not (class and class >= 1 and class <= MAX_CLASS) then return end
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
    local slot = n36(sc, true)
    if not (slot and GCA.IS_SYNC_SLOT[slot]) then return end
    local link = GCA:DecodeItem(body)
    if not link then return end
    items[slot] = link
  end
  return { subject = subject, class = CLASSES[class], level = level, ts = ts, src = src, i = i, n = n, items = items }
end

function GCA:ApplyRecord(senderKey, r)
  local direct = r.subject == ""
  local key = direct and senderKey or RQ:NormName(r.subject)
  if not key or key == self.playerKey then return end
  if not direct and not RQ:RosterEntry(key) then return end
  local source = direct and "self" or "inspect"
  local m = self.db.members[key]
  if m then
    local old = Stamp(m)
    if source == "self" and m.source == "inspect" then
      -- the member's own record always replaces gear someone else relayed or we inspected
    elseif source == "inspect" and m.source == "self" and time() - (m.time or 0) < C.SELF_PROTECT then
      return -- a relay never overwrites the member's own record while it is fresh
    else
      if r.ts < old then return end
      if r.ts == old and RANK[source] <= (RANK[m.source] or 0) then return end
    end
  end
  m = m or {}
  -- m.time = when WE got the data (UI "… ago", pruning); m.ts keeps the gear's own stamp (merge/relay)
  -- a stamp from the future (clock skew, inside FUTURE_SLACK) is stored as now, so it can't block later records
  m.items, m.ts, m.time, m.source = r.items, math.min(r.ts, self:Now()), time(), source
  m.from = (not direct) and senderKey or nil
  m.class, m.level = r.class, r.level
  self.db.members[key] = m
  self:ClearWornCrafted(key, m.items) -- a synced record showing the crafted item worn ends the mark
  S.received = S.received + 1
  self:Invalidate()
  return true
end

local function OnGear(senderKey, f)
  local r = ValidChunk(f)
  if not r then return end
  if r.subject ~= "" then
    local subj = RQ:NormName(r.subject)
    if not subj or not RQ:RosterEntry(subj) then return end
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
    local subj = RQ:NormName(r.subject)
    if subj then S.relayHeardSig[subj] = GCA:GearSignature(items) end
  end
  GCA:ApplyRecord(senderKey, { subject = r.subject, class = r.class, level = r.level, ts = r.ts, items = items })
end

-- S;<index>;<ts>: the sender's own spec. Ignored when the spec's class contradicts what we know.
function GCA:OnSpecMessage(senderKey, f)
  local idx, ts = n36(f[2], true), n36(f[3], true)
  local entry = idx and self.SPEC_LIST and self.SPEC_LIST[idx]
  if not entry or not ts or ts > self:Now() + C.FUTURE_SLACK then return end
  local class, spec = entry[1], entry[2]
  local m, r = self.db.members[senderKey], RQ:RosterEntry(senderKey)
  local known = (r and r.class) or (m and m.class)
  if known and known ~= class then return end
  if self:StoreSpec(senderKey, class, { spec = spec, src = "sync", ts = ts }) then S.specsReceived = (S.specsReceived or 0) + 1 end
  return true
end

-- A message on our prefix from a guildmate. The core has already checked the channel (GUILD), secret values, the
-- sender's name (key = RQ:NormName), our own echo (OnEcho below) and its per-sender intake limit.
function GCA:OnAddonMessage(key, text, sender)
  if type(text) ~= "string" or type(key) ~= "string" or not self.db then return end
  S.lastRaw = sender
  -- nothing is read inside an instance or with sync off
  if InInstance() or not self.db.settings.sync then return end
  local now = GetTime()
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
raw:OnMessage(function(key, text, sender) GCA:OnAddonMessage(key, text, sender) end)
raw:OnEcho(function() S.echoSeen = GetTime() end)

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function GCA:SyncPeerCount(window)
  local n, now = 0, GetTime()
  for _, t in pairs(S.peers) do if now - t < (window or 3600) then n = n + 1 end end
  return n
end

-- "paused" = the core's slow mode: our messages don't come back, the suite sends 1 per 5 min until one does
local function Slow() return RQ:CommState().slow end

function GCA:SyncStatusLine()
  local s = Settings()
  if not (s and s.sync) then return "|cff888888" .. L.SYNC_OFF .. "|r" end
  if not IsInGuild() then return "|cff888888" .. L.SYNC_NOGUILD .. "|r" end
  if Slow() then return "|cffff5555" .. L.SYNC_PAUSED .. "|r" end
  local n = self:SyncPeerCount(3600)
  return string.format(L.SYNC_PEERS, n)
end

-- K1: the same states for the status dot in the window header: "off", "noguild", "paused", "ok" (a guildie with the
-- addon heard in the last hour) or "idle" (on, nobody heard yet).
function GCA:SyncState()
  local s = Settings()
  if not (s and s.sync) then return "off" end
  if not IsInGuild() then return "noguild" end
  if Slow() then return "paused" end
  return self:SyncPeerCount(3600) > 0 and "ok" or "idle"
end

-- Diagnostics (English); P(line) receives each line (the options' copy box), default: chat.
function GCA:SyncStatus(P)
  P = P or function(line) self:Print(line) end
  local s = Settings()
  if s and s.sync and Slow() then P(L.SYNC_STOPPED_MSG) end
  local chunks, relayN = 0, 0
  for _, n in pairs(S.pending) do chunks = chunks + n end
  for _ in pairs(S.relayPending) do relayN = relayN + 1 end
  P(string.format("%s. Received %d record(s) and %d spec(s) this session, sent %d message(s), queued %d message(s), %d relay(s) pending. Own echo: %s.",
    self:SyncStatusLine(), S.received, S.specsReceived or 0, S.sent, chunks, relayN,
    S.echoSeen and (math.floor(GetTime() - S.echoSeen) .. " s ago") or "none yet"))
  if s and s.sync and S.qSkipped then P("(Login request skipped: sent less than 15 min ago on this character.)") end
  P("Suite sync: " .. RQ:CommStatus())
  -- for checking the sender name format in game
  P(string.format("Names: you are '%s'; last guildie message from '%s'.", tostring(self.playerKey), tostring(S.lastRaw or "-")))
end

-- "Retry sync": leave the core's slow mode; our own record goes out again if it is owed
function GCA:SyncRetry()
  local wasPaused = Slow()
  RQ:CommResume()
  self:CheckOwn(false)
  if wasPaused then self:Print(L.SYNC_RESUMED) end -- only when it actually was paused
  self:Invalidate()
end

---------------------------------------------------------------------------
-- Events (registered by Core.lua: OnLogin, PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED call these)
---------------------------------------------------------------------------
function GCA:OnSyncLogin()
  C_Timer.After(C.Q_MIN_DELAY + math.random() * C.Q_JITTER, function() TryQ(0) end)
end

function GCA:OnSyncEnteringWorld()
  if InInstance() then
    raw:Cancel() -- our records wait for nothing in there (own gear stays owed: CheckOwn after leaving)
  else
    C_Timer.After(5, function() RQ:Call(GCA.CheckOwn, GCA, false); RQ:Call(GCA.CheckOwnSpec, GCA); DrainRelays() end)
  end
end

function GCA:OnSyncRegen() self:CheckOwn(false) end
