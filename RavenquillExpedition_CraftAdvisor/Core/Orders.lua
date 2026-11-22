local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = GCA.RQ
local EMPTY = {}

local BOTH, NOBODY = { crafter = true, requester = true }, {}
local STATES = {
  requested = { rank = 1, by = "requester", activeFor = BOTH },
  accepted = { rank = 2, by = "crafter", activeFor = BOTH },
  declined = { rank = 3, by = "crafter", activeFor = NOBODY },
  withdrawn = { rank = 4, by = "requester", activeFor = NOBODY },
  done = { rank = 5, by = "crafter", activeFor = { requester = true } },
  received = { rank = 6, by = "requester", activeFor = NOBODY },
}
GCA.ORDER_STATES = STATES
GCA.ORDER_STATE_LIST = { "requested", "accepted", "declined", "withdrawn", "done", "received" }

local ACTIONS = {
  accept = { by = "crafter", from = { requested = true }, to = "accepted" },
  done = { by = "crafter", from = { accepted = true }, to = "done" },
  decline = { by = "crafter", from = { requested = true, accepted = true }, to = "declined" },
  withdraw = { by = "requester", from = { requested = true, accepted = true }, to = "withdrawn" },
  receive = { by = "requester", from = { done = true }, to = "received" },
}
GCA.ORDER_ACTIONS = ACTIONS
local ACTION_ORDER = { "accept", "done", "receive", "decline", "withdraw" }

GCA.ORDER_LISTS = { "tome", "mine", "guild", "finished" }
local LIST_OF_ROLE = { crafter = "tome", requester = "mine" }

GCA.ORDER_FINISHED_TTL = 14 * 86400
GCA.ORDER_OPEN_TTL = 30 * 86400
GCA.ORDER_MAX = 100
GCA.ORDER_GAIN_MAX = 9999
GCA.heardOrders = {}

local function Rank(state) return STATES[state] and STATES[state].rank or 0 end
GCA.OrderRank = Rank

local function Final(state) return next(STATES[state].activeFor) == nil end

function GCA.OrderKey(requester, id) return requester .. "#" .. id end
local function KeyOf(o) return GCA.OrderKey(o.requester, o.id) end

function GCA.OrderPeer(o, role) return role == "requester" and o.crafter or o.requester end

function GCA:Orders()
  local guilds = self.db and self.db.guilds
  local g = type(guilds) == "table" and guilds[RQ:GuildKey() or "-"]
  local store = type(g) == "table" and g.orders
  return type(store) == "table" and store or EMPTY
end

function GCA:OrderRole(o)
  local me = self.playerKey
  if not me then return nil end
  if o.requester == me then return "requester" end
  if o.crafter == me then return "crafter" end
end

local function Changed(self)
  self.ordersGen = (self.ordersGen or 0) + 1
  self:Invalidate()
  if self.PumpOrders then self:PumpOrders() end
end

local function ValidOrder(o)
  return type(o) == "table" and STATES[o.state] ~= nil and type(o.requester) == "string" and type(o.crafter) == "string"
    and type(o.id) == "number" and type(o.spell) == "number" and GCA.PROF_BY_KEY[o.prof] ~= nil
end

local function Expired(o, now)
  local age = now - (tonumber(o.t) or 0)
  return age > (Final(o.state) and GCA.ORDER_FINISHED_TTL or GCA.ORDER_OPEN_TTL)
end

function GCA:PruneOrders()
  local store, now = self:Orders(), time()
  for key, o in pairs(store) do
    if not ValidOrder(o) or key ~= KeyOf(o) or Expired(o, now) then store[key] = nil end
  end
end

local function OldestFinished(store)
  local oldest, oldestT
  for key, o in pairs(store) do
    local t = tonumber(o.t) or 0
    if Final(o.state) and (not oldestT or t < oldestT) then oldest, oldestT = key, t end
  end
  return oldest
end

local function MakeRoom(self)
  local store, n = self:Orders(), 0
  for _ in pairs(store) do n = n + 1 end
  if n < self.ORDER_MAX then return true end
  local oldest = OldestFinished(store)
  if not oldest then return false end
  store[oldest] = nil
  return true
end

local function Gain(v)
  v = tonumber(v)
  if not v or v < 0.5 then return nil end
  return math.min(GCA.ORDER_GAIN_MAX, math.floor(v + 0.5))
end

local function OpenOrderFor(self, crafter, spell)
  for _, o in pairs(self:Orders()) do
    if o.requester == self.playerKey and o.crafter == crafter and o.spell == spell and STATES[o.state].activeFor.crafter then
      return o
    end
  end
end

local function NextId(self)
  local last = 0
  for _, o in pairs(self:Orders()) do
    if o.requester == self.playerKey and o.id > last then last = o.id end
  end
  return math.max(self:Now(), last + 1)
end

function GCA:PlaceOrder(crafter, prof, spell, gain)
  local me = self.playerKey
  if not (me and type(crafter) == "string" and crafter ~= me and self:RecipeRow(prof, spell)) then return nil end
  local open = OpenOrderFor(self, crafter, spell)
  if open then return open end
  if not MakeRoom(self) then return nil end
  local o = { id = NextId(self), requester = me, crafter = crafter, prof = prof, spell = spell, gain = Gain(gain),
    state = "requested", t = time() }
  self:GuildStore("orders")[KeyOf(o)] = o
  Changed(self)
  return o
end

function GCA:OrderActions(o)
  local role, out = self:OrderRole(o), {}
  for _, name in ipairs(ACTION_ORDER) do
    local a = ACTIONS[name]
    if a.by == role and a.from[o.state] then out[#out + 1] = name end
  end
  return out
end

function GCA:OrderAction(o, action)
  local a = ACTIONS[action]
  if not (a and o and self:Orders()[KeyOf(o)] == o) then return false end
  if self:OrderRole(o) ~= a.by or not a.from[o.state] then return false end
  o.state, o.t = a.to, time()
  Changed(self)
  return true
end

local function Authored(sender, m)
  local st = STATES[m.state]
  return st ~= nil and m.requester ~= m.crafter and sender == m[st.by]
end

local function HearOrder(self, key, m)
  local heard = self.heardOrders
  local old = heard[key]
  if old and Rank(m.state) <= Rank(old.state) then return nil end
  m.t = time()
  heard[key] = m
  self:Invalidate()
  return nil
end

local NOTICES = {
  requested = function(who, item) return string.format(L.ORDER_NOTICE_REQUESTED, who, item) end,
  accepted = function(who, item) return string.format(L.ORDER_NOTICE_ACCEPTED, who, item) end,
  declined = function(who, item) return string.format(L.ORDER_NOTICE_DECLINED, who, item) end,
  withdrawn = function(who, item) return string.format(L.ORDER_NOTICE_WITHDRAWN, who, item) end,
  done = function(who, item) return string.format(L.ORDER_NOTICE_DONE, who, item) end,
  received = function(who, item) return string.format(L.ORDER_NOTICE_RECEIVED, who, item) end,
}

local function Notice(self, o)
  local peer = GCA.OrderPeer(o, self:OrderRole(o))
  self:Print(NOTICES[o.state](peer, self:OrderItemText(o)))
end

local function NewFromMessage(self, key, m)
  if not MakeRoom(self) then return nil end
  local o = { id = m.id, requester = m.requester, crafter = m.crafter, prof = m.prof, spell = m.spell, gain = Gain(m.gain),
    state = m.state, t = time() }
  self:GuildStore("orders")[key] = o
  return o
end

local function Adopt(self, key, m)
  local o = self:Orders()[key]
  if not o then return NewFromMessage(self, key, m), true end
  if o.crafter ~= m.crafter or o.spell ~= m.spell or o.prof ~= m.prof then return nil, false end
  if Rank(m.state) <= Rank(o.state) then return o, false end
  o.state, o.t = m.state, time()
  return o, true
end

function GCA:MergeOrder(sender, m)
  if not (Authored(sender, m) and self.PROF_BY_KEY[m.prof] and self:RecipeRow(m.prof, m.spell)) then return nil end
  local key = GCA.OrderKey(m.requester, m.id)
  if not self:OrderRole(m) then return HearOrder(self, key, m) end
  local o, adopted = Adopt(self, key, m)
  if not o then return nil end
  if Rank(m.state) > Rank(o.peerState) then o.peerState = m.state end
  if adopted then
    self.heardOrders[key] = nil
    Notice(self, o)
    Changed(self)
  end
  return o
end

function GCA:AckOrder(sender, requester, id, state)
  local o = self:Orders()[GCA.OrderKey(requester, id)]
  local role = o and self:OrderRole(o)
  if not (role and GCA.OrderPeer(o, role) == sender and STATES[state]) then return nil end
  if Rank(state) > Rank(o.peerState) then o.peerState = state end
  return o
end

function GCA:OrderList(o)
  local role = self:OrderRole(o)
  if not role then return STATES[o.state].activeFor.crafter and "guild" or nil end
  return STATES[o.state].activeFor[role] and LIST_OF_ROLE[role] or "finished"
end

local function Newest(a, b)
  if a.t ~= b.t then return (a.t or 0) > (b.t or 0) end
  return KeyOf(a) < KeyOf(b)
end

function GCA:OrderLists()
  local lists, store = { tome = {}, mine = {}, guild = {}, finished = {} }, self:Orders()
  for _, o in pairs(store) do
    local list = lists[self:OrderList(o) or ""]
    if list then list[#list + 1] = o end
  end
  for key, o in pairs(self.heardOrders) do
    if not store[key] and self:OrderList(o) == "guild" then lists.guild[#lists.guild + 1] = o end
  end
  for _, list in pairs(lists) do table.sort(list, Newest) end
  return lists
end

function GCA:OrderItemText(o)
  local r = self:RecipeRow(o.prof, o.spell)
  if not r then return "?" end
  if r.kind == "enchant" then
    local row = self:EnchantData().bySpell[o.spell]
    return row and self:EnchantInfo(row).name or r.name
  end
  local info = self:GetInfo(r.itemID)
  return info and (info.link or info.name) or r.name
end
