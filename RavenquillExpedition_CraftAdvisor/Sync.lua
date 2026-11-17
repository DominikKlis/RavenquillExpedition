local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = GCA.RQ
local W = RQ.Wire

local PREFIX = "GCAdv1"
local VERSION = "2"
local CLASSES, CLASS_IDX, MAX_CLASS = W.CLASSES, W.CLASS_IDX, 9
local RANK = { self = 2, inspect = 1 }

local C = {
  MAX_MSG = W.MAX_MSG,
  MAX_CHUNKS = 6,
  BUFFER_EXPIRE = 180,
  Q_MIN_DELAY = 20, Q_JITTER = 20, Q_RELOAD_GAP = 900,
  ANSWER_MIN = 5, ANSWER_JITTER = 25,
  OWN_DEBOUNCE = 20, OWN_SPACING = 120,
  PEER_VALID = 86400,
  RELAY_SPACING = 60, RELAY_MIN = 3, RELAY_JITTER = 7, RELAY_MAX = 10,
  ADDON_USER_FRESH = 3600,
  FUTURE_SLACK = 120,
  SELF_PROTECT = 30 * 86400,
}
GCA.SyncConst = C

local S = {
  pending = {},
  peers = {},
  addonUsers = {},
  buffers = {},
  relayPending = {},
  relayHeard = {},
  relayHeardSig = {},
  received = 0, sent = 0,
}
GCA.Sync = S

local raw = GCA:NewRawChannel({ prefix = PREFIX, lane = "record" })
GCA.syncChannel = raw

local b36, n36 = W.b36s, W.n36
GCA.b36 = b36

local function SyncOn()
  local s = GCA:Settings()
  return s and s.sync
end
local function Enabled()
  return SyncOn() and RQ.Plain(RQ.SafeCall(IsInGuild)) and true or false
end
local function InInstance() return RQ:InInstance() end

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

function GCA:EncodeItem(link)
  local norm = self:NormItem(link)
  if not norm then return end
  local f = self.SplitColon(norm)
  for i, v in ipairs(f) do
    if v == "" then
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

local MAX_ENTRY = 80
local function SourceCode(subject) return subject == "" and "s" or "i" end

local function RecordHead(m, subject)
  local r = subject ~= "" and RQ:RosterEntry(subject) or {}
  local classIdx, level = CLASS_IDX[m.class or r.class or ""], m.level or r.level
  if not classIdx or classIdx > MAX_CLASS or type(level) ~= "number" or level < 1 then return end
  return table.concat({ "G", subject, b36(classIdx), b36(level), b36(Stamp(m)), SourceCode(subject) }, ";")
end

local function EncodeEntries(gca, items)
  local entries = {}
  for _, slot in ipairs(gca.SYNC_SLOTS) do
    local e = items and gca:EncodeItem(items[slot])
    e = e and b36(slot) .. "=" .. e
    if e and #e <= MAX_ENTRY then entries[#entries + 1] = e end
  end
  return entries
end

local function PackChunks(entries, budget)
  local chunks, cur, len = {}, {}, 0
  for _, e in ipairs(entries) do
    if len > 0 and len + 1 + #e > budget then chunks[#chunks + 1] = cur; cur, len = {}, 0 end
    cur[#cur + 1] = e
    len = len + (len > 0 and 1 or 0) + #e
  end
  chunks[#chunks + 1] = cur
  return chunks
end

function GCA:EncodeRecord(m, subject)
  local head = RecordHead(m, subject)
  if not head then return end
  local chunks = PackChunks(EncodeEntries(self, m.items), C.MAX_MSG - #head - #";9/9;")
  if #chunks > C.MAX_CHUNKS then return end
  local out = {}
  for i, list in ipairs(chunks) do
    out[i] = head .. ";" .. i .. "/" .. #chunks .. ";" .. table.concat(list, ",")
  end
  return out
end

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
    if (S.lastQAt or -1e9) <= queuedAt then S.owed = false end
    S.ownSentAt = GetTime()
  end)
end

function GCA:CheckOwn(answer)
  if not Enabled() or not PeerKnown() or InInstance() then return end
  local now = GetTime()
  if answer then S.owed = true; S.lastQAt = now; S.specOwed = true end
  self:CheckOwnSpec()
  if not OwnDue() then return end
  if S.ownTimer then return end
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
    if not OwnDue() then return end
    if InCombatLockdown() then return end
    QueueOwn()
  end)
end

function GCA:OnOwnGearChanged() self:CheckOwn(false) end

function GCA:CheckOwnSpec()
  if not self.OwnAnnouncedSpec then return end
  local idx, ownSpec = self:OwnAnnouncedSpec()
  if not idx then return end
  local cs = CharState()
  if cs.specIdx ~= idx then cs.specIdx, cs.specTs = idx, self:Now() end
  if self.StoreOwnSpec then self:StoreOwnSpec(ownSpec, cs.specTs) end
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

local DrainRelays

function GCA:RelayInspect(key)
  if not Enabled() or key == self.playerKey or not RQ:RosterEntry(key) then return end
  S.relayPending[key] = GetTime()
  local n, oldestK, oldestT = 0, nil, math.huge
  for k, t in pairs(S.relayPending) do
    n = n + 1
    if t < oldestT then oldestK, oldestT = k, t end
  end
  if n > C.RELAY_MAX then S.relayPending[oldestK] = nil end
  DrainRelays()
end

function DrainRelays()
  if S.relayTimer or not next(S.relayPending) then return end
  local now = GetTime()
  local wait = math.max(0, (S.lastRelay or -1e9) + C.RELAY_SPACING - now) + C.RELAY_MIN + math.random() * C.RELAY_JITTER
  S.relayTimer = true
  C_Timer.After(wait, function()
    S.relayTimer = nil
    if not Enabled() or InInstance() or not PeerKnown() then
      C_Timer.After(C.RELAY_SPACING, DrainRelays)
      return
    end
    local key, t = nil, math.huge
    for k, at in pairs(S.relayPending) do if at < t then key, t = k, at end end
    if not key then return end
    S.relayPending[key] = nil
    local m = GCA.db.members[key]
    local fresh = S.addonUsers[key] and GetTime() - S.addonUsers[key] < C.ADDON_USER_FRESH
    local already = m and ((S.relayHeard[key] or -1) >= Stamp(m) or S.relayHeardSig[key] == GCA:GearSignature(m.items))
    if m and m.source == "inspect" and not m.from and not fresh and not already then
      S.lastRelay = GetTime()
      Enqueue("r:" .. key, GCA:EncodeRecord(m, key))
    end
    DrainRelays()
  end)
end

function GCA:SendQ()
  if not Enabled() then return end
  local cs = CharState()
  if cs.lastQ and self:Now() - cs.lastQ < C.Q_RELOAD_GAP then
    S.qSkipped = true
  else
    cs.lastQ = self:Now()
    Enqueue("Q", { "Q;" .. VERSION })
  end
  S.owed = true
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

local function InRange(v, lo, hi) return v ~= nil and v >= lo and v <= hi end

local function DecodeEntries(list)
  local items = {}
  for e in list:gmatch("[^,]+") do
    if #e > MAX_ENTRY then return end
    local sc, body = e:match("^(%w+)=([%w:%-~]*)$")
    local slot = n36(sc, true)
    local link = slot and GCA.IS_SYNC_SLOT[slot] and GCA:DecodeItem(body)
    if not link then return end
    items[slot] = link
  end
  return items
end

local function ValidChunk(f)
  local subject, class, level, ts, src = f[2], n36(f[3], true), n36(f[4], true), n36(f[5], true), f[6]
  local i, n = (f[7] or ""):match("^(%d)/(%d)$")
  i, n = tonumber(i), tonumber(n)
  if not (InRange(class, 1, MAX_CLASS) and InRange(level, 1, 60) and InRange(ts, 0, GCA:Now() + C.FUTURE_SLACK)) then return end
  if not (InRange(n, 1, C.MAX_CHUNKS) and InRange(i, 1, n) and src == SourceCode(subject)) then return end
  local items = DecodeEntries(f[8] or "")
  if not items then return end
  return { subject = subject, class = CLASSES[class], level = level, ts = ts, src = src, i = i, n = n, items = items }
end

local function RecordTarget(senderKey, subject)
  if subject == "" then return senderKey, "self" end
  local key = RQ:NormName(subject)
  if key and RQ:RosterEntry(key) then return key, "inspect", senderKey end
end

local function Supersedes(r, source, m)
  if source == "self" and m.source == "inspect" then return true end
  if source == "inspect" and m.source == "self" and time() - (m.time or 0) < C.SELF_PROTECT then return false end
  local old = Stamp(m)
  if r.ts ~= old then return r.ts > old end
  return RANK[source] > (RANK[m.source] or 0)
end

function GCA:ApplyRecord(senderKey, r)
  local key, source, from = RecordTarget(senderKey, r.subject)
  if not key or key == self.playerKey then return end
  local m = self.db.members[key]
  if m and not Supersedes(r, source, m) then return end
  m = m or {}
  m.items, m.ts, m.time, m.source = r.items, math.min(r.ts, self:Now()), time(), source
  m.from, m.class, m.level = from, r.class, r.level
  self.db.members[key] = m
  self:ClearWornCrafted(key, m.items)
  S.received = S.received + 1
  self:Invalidate()
  return true
end

local function CompletedItems(senderKey, r)
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
  if b.got < b.n then return nil end
  S.buffers[id] = nil
  local items = {}
  for _, part in ipairs(b.parts) do for slot, link in pairs(part.items) do items[slot] = link end end
  return items
end

local function OnGear(senderKey, f)
  local r = ValidChunk(f)
  if not r then return end
  local relayed = r.subject ~= ""
  local subj = relayed and RQ:NormName(r.subject)
  if relayed and not (subj and RQ:RosterEntry(subj)) then return end
  if not relayed then
    S.addonUsers[senderKey] = GetTime()
  elseif r.i == r.n then
    S.relayHeard[subj] = math.max(S.relayHeard[subj] or -1, r.ts)
  end
  local items = CompletedItems(senderKey, r)
  if not items then return end
  if relayed then S.relayHeardSig[subj] = GCA:GearSignature(items) end
  GCA:ApplyRecord(senderKey, { subject = r.subject, class = r.class, level = r.level, ts = r.ts, items = items })
end

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

function GCA:OnAddonMessage(key, text, sender)
  if type(text) ~= "string" or type(key) ~= "string" or not self.db then return end
  S.lastRaw = sender
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

function GCA:SyncPeerCount(window)
  local n, now = 0, GetTime()
  for _, t in pairs(S.peers) do if now - t < (window or 3600) then n = n + 1 end end
  return n
end

local function Slow() return RQ:CommState().slow end

function GCA:SyncStatusLine()
  if not SyncOn() then return "|cff888888" .. L.SYNC_OFF .. "|r" end
  if not IsInGuild() then return "|cff888888" .. L.SYNC_NOGUILD .. "|r" end
  if Slow() then return "|cffff5555" .. L.SYNC_PAUSED .. "|r" end
  local n = self:SyncPeerCount(3600)
  return string.format(L.SYNC_PEERS, n)
end

function GCA:SyncState()
  if not SyncOn() then return "off" end
  if not IsInGuild() then return "noguild" end
  if Slow() then return "paused" end
  return self:SyncPeerCount(3600) > 0 and "ok" or "idle"
end

function GCA:SyncStatus(P)
  P = P or function(line) self:Print(line) end
  local on = SyncOn()
  if on and Slow() then P(L.SYNC_STOPPED_MSG) end
  local chunks, relayN = 0, 0
  for _, n in pairs(S.pending) do chunks = chunks + n end
  for _ in pairs(S.relayPending) do relayN = relayN + 1 end
  P(string.format("%s. Received %d record(s) and %d spec(s) this session, sent %d message(s), queued %d message(s), %d relay(s) pending. Own echo: %s.",
    self:SyncStatusLine(), S.received, S.specsReceived or 0, S.sent, chunks, relayN,
    S.echoSeen and (math.floor(GetTime() - S.echoSeen) .. " s ago") or "none yet"))
  if on and S.qSkipped then P("(Login request skipped: sent less than 15 min ago on this character.)") end
  P("Suite sync: " .. RQ:CommStatus())
  P(string.format("Names: you are '%s'; last guildie message from '%s'.", tostring(self.playerKey), tostring(S.lastRaw or "-")))
end

function GCA:SyncRetry()
  local wasPaused = Slow()
  RQ:CommResume()
  self:CheckOwn(false)
  if wasPaused then self:Print(L.SYNC_RESUMED) end
  self:Invalidate()
end

function GCA:OnSyncLogin()
  C_Timer.After(C.Q_MIN_DELAY + math.random() * C.Q_JITTER, function() TryQ(0) end)
end

function GCA:OnSyncEnteringWorld()
  if InInstance() then
    raw:Cancel()
  else
    C_Timer.After(5, function() RQ:Call(GCA.CheckOwn, GCA, false); RQ:Call(GCA.CheckOwnSpec, GCA); DrainRelays() end)
  end
end

function GCA:OnSyncRegen() self:CheckOwn(false) end
