-- Ravenquill Expedition core: ONE shared GUILD addon-message lane for all modules.
-- Forever rules this follows (researched for GuildCraftAdvisor, see its HANDOFF.md "Guild sync on Forever"):
--   only GUILD works; 255 bytes per message; heavy senders are dropped SILENTLY (per player, all prefixes:
--   Overlord\SyncGuild.lua:17-20); our own GUILD messages echo back in about a second (SyncGuild.lua:35-37),
--   the only proof of delivery.
-- Pacing = GuildCraftAdvisor Sync.lua:24-44 (burst 2, then 1 per 30 s, busy hold, per-sender caps, echo watchdog).
-- Nothing is queued or sent inside an instance or in combat. Reading inside instances is allowed here
-- (every value is checked for secrets first) [U: whether GUILD addon messages arrive there on Forever].
--
-- Other suite addons with their own prefix (GuildCraftAdvisor, RavenquillExpedition_Map) can share this budget:
--   if RavenquillExpedition and RavenquillExpedition.TakeSendToken then ok = RavenquillExpedition:TakeSendToken() end
local GS = RavenquillExpedition
local SafeCall, IsSecret, Plain = GS.SafeCall, GS.IsSecret, GS.Plain

local PREFIX = "RQE1"
GS.COMM_PREFIX = PREFIX

local C = {
  MAX_MSG = 250,
  BURST = 2, RATE = 1 / 30,
  SLOW_RATE = 1 / 300,    -- while our messages never echo back (Overlord: 1 per 5 min)
  BUSY_HEARD = 8,         -- hold while this many messages from others were heard in the last 60 s ...
  HEARD_PER_SENDER = 4,   -- ... counting at most this many per sender (one chatty client can't stall everyone)
  INTAKE_PER_MIN = 12,    -- per sender; more is not read
  ECHO_TIMEOUT = 120,     -- a sent message that never echoes counts as lost
  QUEUE_MAX = 40,
  QUEUE_MAX_WAIT = 1800,  -- not sent within 30 min outside instances -> "deferred" (the module keeps its copy)
  HOLD_THROTTLED = 30,
}
GS.CommConst = C

-- PUBLIC CONTRACT (RavenquillExpedition_Map reads these to yield to the core): RavenquillExpedition.Comm.q stays the same array
-- (q[1] = next message waiting), RavenquillExpedition.Comm.lastSent = GetTime() of our last send. Don't rename.
local S = {
  q = {},            -- { tag, msg, t, onResult }
  tokens = C.BURST, tokenAt = nil,
  hold = 0,
  heard = {},        -- GetTime() of counted messages from others
  intake = {},       -- [senderKey] = { t, n, h }
  echo = {},         -- [msg] = { t, onResult }
  handlers = {},
  sent = 0, received = 0, echoed = 0, lost = 0,
}
GS.Comm = S

-- handler(senderKey, body) – body is everything after "<tag>;"
function GS:RegisterComm(tag, handler) S.handlers[tag] = handler end

local function Result(cb, status) if cb then GS:Call(cb, status) end end

local function Rate() return S.slow and C.SLOW_RATE or C.RATE end
local function Refill(now)
  S.tokens = math.min(C.BURST, S.tokens + (now - (S.tokenAt or now)) * Rate())
  S.tokenAt = now
end

-- One shared budget per client for every suite prefix.
function GS:TakeSendToken()
  local now = GetTime()
  Refill(now)
  if S.tokens < 1 or now < S.hold then return false end
  S.tokens = S.tokens - 1
  return true
end

local function CanSend()
  if not GS.loggedIn or GS:InInstance() then return false end
  if InCombatLockdown and Plain(SafeCall(InCombatLockdown)) then return false end
  if not Plain(SafeCall(IsInGuild)) then return false end
  return true
end
GS.CanSendGuild = CanSend

local Pump -- forward

-- Queue one message. onResult(status): "echo" (delivered), "lost" (sent, no echo), "deferred" (not sent:
-- instance, queue full, waited too long, send error – try again later). Returns false when not queued.
function GS:SendGuild(tag, body, onResult)
  local msg = tag .. ";" .. (body or "")
  if #msg > C.MAX_MSG or msg:find("\0", 1, true) then return false end
  if not CanSend() or #S.q >= C.QUEUE_MAX then return false end
  S.q[#S.q + 1] = { tag = tag, msg = msg, t = GetTime(), onResult = onResult }
  Pump()
  return true
end

local function SendRaw(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "error" end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return "error" end
  if res == nil or res == true or res == 0 then return "ok" end
  if res == 3 or res == 8 then return "throttled" end -- [U] live values (ChatThrottleLib's fallback enum)
  return "error"
end

-- Everything waiting goes back to its module (entering an instance, leaving the guild).
local function DeferAll()
  local q = {}
  for i, it in ipairs(S.q) do q[i] = it end
  for i = #S.q, 1, -1 do S.q[i] = nil end -- emptied in place: S.q is read by other addons (see S below)
  for _, it in ipairs(q) do Result(it.onResult, "deferred") end
end

local function PumpOnce()
  local now = GetTime()
  for i = #S.heard, 1, -1 do if now - S.heard[i] > 60 then table.remove(S.heard, i) end end
  for msg, e in pairs(S.echo) do
    if now - e.t > C.ECHO_TIMEOUT then
      S.echo[msg] = nil
      S.lost = S.lost + 1
      Result(e.onResult, "lost")
    end
  end
  -- echo watchdog: sent for a while and nothing ever came back -> slow down (and say so once)
  if not S.slow and S.sent > 0 and S.echoed == 0 and S.firstSent and now - S.firstSent > C.ECHO_TIMEOUT and S.lost > 0 then
    S.slow = true
    GS.Print(nil, "guild sync: our messages don't come back – sending slowly now (1 per 5 min).")
  end
  if S.q[1] and not CanSend() and GS:InInstance() then DeferAll() end
  for i = #S.q, 1, -1 do
    local it = S.q[i]
    if now - it.t > C.QUEUE_MAX_WAIT then table.remove(S.q, i); Result(it.onResult, "deferred") end
  end
  Refill(now)
  local item = S.q[1]
  if not item then return next(S.echo) ~= nil end
  if not CanSend() or now < S.hold or #S.heard >= C.BUSY_HEARD or S.tokens < 1 then return true end
  local r = SendRaw(item.msg)
  if r == "throttled" then
    S.tokens, S.hold = 0, now + C.HOLD_THROTTLED
    return true
  end
  S.tokens = S.tokens - 1
  table.remove(S.q, 1)
  if r == "error" then Result(item.onResult, "deferred"); return true end
  S.sent = S.sent + 1
  S.firstSent = S.firstSent or now
  S.lastSent = now
  S.echo[item.msg] = { t = now, onResult = item.onResult }
  return true
end

Pump = function()
  if S.armed then return end
  S.armed = true
  C_Timer.After(1, function()
    S.armed = false
    local ok, more = pcall(PumpOnce)
    if not ok then
      if RavenquillExpeditionDB then RavenquillExpeditionDB.lastError = { t = time(), msg = "Comm: " .. tostring(more) } end
      more = true
    end
    if more then C_Timer.After(4, Pump) end -- keep ticking while anything waits; refill is time based
  end)
end
GS.CommPump = Pump

local function OnAddonMessage(text, chan, sender)
  text, chan, sender = Plain(text, "string"), Plain(chan, "string"), Plain(sender, "string")
  if not (text and sender) or chan ~= "GUILD" then return end
  local key = GS:NormName(sender)
  if not key then return end
  if RavenquillExpeditionDB and not RavenquillExpeditionDB.diagSender then RavenquillExpeditionDB.diagSender = sender end
  local tag, body = text:match("^([^;]+);(.*)$")
  if key == GS:PlayerKey() then
    local e = S.echo[text]
    if e then
      S.echo[text] = nil
      S.echoed, S.lastEcho = S.echoed + 1, GetTime()
      if S.slow then S.slow = false end
      Result(e.onResult, "echo")
    end
    return
  end
  local now = GetTime()
  local it = S.intake[key]
  if not it or now - it.t > 60 then it = { t = now, n = 0, h = 0 }; S.intake[key] = it end
  it.n = it.n + 1
  if it.n > C.INTAKE_PER_MIN then return end
  it.h = it.h + 1
  if it.h <= C.HEARD_PER_SENDER then S.heard[#S.heard + 1] = now end
  S.received = S.received + 1
  GS:NotePeer(key)
  local h = tag and S.handlers[tag]
  if h then GS:Call(h, key, body) end
end

function GS:CommStatus()
  local echoWait = 0
  for _ in pairs(S.echo) do echoWait = echoWait + 1 end
  return ("queue %d, sent %d, delivered %d, lost %d, waiting for echo %d, received %d, tokens %.1f, foreign %s%s%s"):format(
    #S.q, S.sent, S.echoed, S.lost, echoWait, S.received, S.tokens, S.hooked and tostring(S.foreign) or "(no hook)",
    self:InInstance() and ", |cffff8800paused (instance)|r" or "", S.slow and ", |cffff8800slow (no echo)|r" or "")
end

function GS:OnLoginComm()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end

-- One budget per client (user decision 2026-11-14): GUILD addon messages this client sends under OTHER prefixes
-- (GuildCraftAdvisor, RavenquillExpedition_Map, ...) use up our tokens too, so the suite as a whole stays within one
-- client's pace. (The map in turn skips its sends while we just sent: it hooks the same function.)
-- [U] hooksecurefunc on a C_ChatInfo function on Forever; /rq comm shows "foreign n" when it works.
S.foreign = 0
if hooksecurefunc and C_ChatInfo and C_ChatInfo.SendAddonMessage then
  pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", function(prefix, _, chan)
    if Plain(prefix, "string") == PREFIX or Plain(chan, "string") ~= "GUILD" then return end
    local now = GetTime()
    Refill(now)
    S.tokens = math.max(-1, S.tokens - 1) -- may go below zero: the next refill pays it back
    S.foreign = S.foreign + 1
  end)
  S.hooked = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, prefix, ...)
  if event == "CHAT_MSG_ADDON" then
    if Plain(prefix, "string") ~= PREFIX then return end
    GS:Call(OnAddonMessage, ...)
  elseif event == "PLAYER_ENTERING_WORLD" then
    if GS:InInstance() then GS:Call(DeferAll) elseif S.q[1] then Pump() end
  elseif S.q[1] then
    Pump()
  end
end)
