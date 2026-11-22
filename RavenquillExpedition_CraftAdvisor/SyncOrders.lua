local ADDON, ns = ...
local GCA = ns.GCA
local RQ = GCA.RQ

local C = { RETRY = 60, TICK = 15, MAX_TRIES = 3, LOGIN_DELAY = 20, ACK_GAP = 30 }
GCA.OrderSyncConst = C

local S = { pending = {}, tries = {}, online = {}, ackedAt = {}, sent = 0, acked = 0 }
GCA.OrderSync = S

local ch = GCA:NewChannel({ tag = "CO", version = 1 })
GCA.orderChannel = ch
ch:Define("o", { fields = { { "requester", "key" }, { "id", "b36", 1 }, { "crafter", "key" }, { "line", "b36", 1, 9999 },
  { "spell", "b36", 1, GCA.MAX_SPELL_ID }, { "state", "enum", GCA.ORDER_STATE_LIST },
  { "gain", "int", 1, GCA.ORDER_GAIN_MAX, opt = true } } })
ch:Define("k", { fields = { { "requester", "key" }, { "id", "b36", 1 }, { "state", "enum", GCA.ORDER_STATE_LIST } } })

local function PeerOnline(peer)
  local r = RQ:RosterEntry(peer)
  return r ~= nil and r.online == true
end

local function Unsynced(o, role)
  return role ~= nil and GCA.ORDER_STATES[o.state].by == role and GCA.OrderRank(o.state) > GCA.OrderRank(o.peerState)
end

local function TriesLeft(key, o)
  local t = S.tries[key]
  if not t or t.state ~= o.state then return true, true end
  return t.n < C.MAX_TRIES, GetTime() - t.at >= C.RETRY
end

local function Waiting(key, o)
  local role = GCA:OrderRole(o)
  if not (Unsynced(o, role) and PeerOnline(GCA.OrderPeer(o, role))) then return false, false end
  local left, rested = TriesLeft(key, o)
  return left, left and rested and not S.pending[key]
end

local ArmRetry

local function SendOrder(key, o)
  local t = S.tries[key]
  if not t or t.state ~= o.state then t = { state = o.state, n = 0, at = GetTime() }; S.tries[key] = t end
  S.pending[key] = true
  ch:Send("o", { requester = o.requester, id = o.id, crafter = o.crafter, line = GCA.PROF_BY_KEY[o.prof].skillLine,
    spell = o.spell, state = o.state, gain = o.gain }, { onResult = function(status)
      S.pending[key] = nil
      if status ~= "dropped" then t.n, t.at, S.sent = t.n + 1, GetTime(), S.sent + 1 end
      ArmRetry()
    end })
end

function GCA:PumpOrders()
  for key, o in pairs(self:Orders()) do
    local _, due = Waiting(key, o)
    if due then SendOrder(key, o) end
  end
  ArmRetry()
end

ArmRetry = function()
  if S.retryArmed then return end
  for key, o in pairs(GCA:Orders()) do
    if Waiting(key, o) then
      S.retryArmed = true
      C_Timer.After(C.TICK, function() S.retryArmed = false; RQ:Call(GCA.PumpOrders, GCA) end)
      return
    end
  end
end

local function SendAck(o)
  local key, now = GCA.OrderKey(o.requester, o.id) .. "|" .. o.state, GetTime()
  if now - (S.ackedAt[key] or -C.ACK_GAP) < C.ACK_GAP then return end
  S.ackedAt[key], S.acked = now, S.acked + 1
  ch:Send("k", { requester = o.requester, id = o.id, state = o.state })
end

ch:On("o", function(sender, m)
  local p = GCA.PROF_BY_LINE[m.line]
  if not p then return end
  local o = GCA:MergeOrder(sender, { requester = m.requester, id = m.id, crafter = m.crafter, prof = p.key, spell = m.spell,
    state = m.state, gain = m.gain })
  if not o then return end
  if o.state == m.state then SendAck(o) end
  GCA:PumpOrders()
end)

ch:On("k", function(sender, m)
  if GCA:AckOrder(sender, m.requester, m.id, m.state) then GCA:PumpOrders() end
end)

function GCA:OnOrdersRoster()
  local cameOnline = {}
  for key, o in pairs(self:Orders()) do
    local role = self:OrderRole(o)
    local peer = role and GCA.OrderPeer(o, role)
    if peer and cameOnline[peer] == nil then
      local on = PeerOnline(peer)
      cameOnline[peer] = on and S.online[peer] == false
      S.online[peer] = on
    end
    if peer and cameOnline[peer] then S.tries[key] = nil end
  end
  self:PumpOrders()
end

function GCA:OnOrdersLogin()
  self:PruneOrders()
  C_Timer.After(C.LOGIN_DELAY, function() RQ:Call(GCA.OnOrdersRoster, GCA) end)
end
