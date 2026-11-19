local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H

local KIND_CODE, CODE_KIND = {}, {}
for k, kind in pairs(H.KINDS) do KIND_CODE[k], CODE_KIND[kind.code] = kind.code, k end
local CLASSES, CLASS_IDX = GS.Wire.CLASSES, GS.Wire.CLASS_IDX
local QUEST_TAGS = H.QUEST_TAGS

H.PUMP_EVERY = 15
H.RETRY_AFTER = 600
H.MAX_TRIES = 3

local ch = H:NewChannel({ tag = "H", version = 1 })
H.channel = ch
local RELAY = "R"
local HEAD = { { "t", "int", 1, 4102444800 }, { "seq", "word", 5 }, { "who", "key" }, { "lvl", "int", 1, 200, opt = true },
  { "cls", "int", 0, 99 } }
local function Fields(extra)
  local out = {}
  for _, x in ipairs(HEAD) do out[#out + 1] = x end
  for _, x in ipairs(extra) do out[#out + 1] = x end
  return out
end
local KIND_FIELDS = {
  g = Fields({ { "item", "int", 1, 9999999 }, { "il", "int", 0, 2000, opt = true }, { "q", "int", 0, 8, opt = true },
    { "oil", "int", 0, 2000, opt = true }, { "slot", "int", 0, 19, opt = true } }),
  l = Fields({ { "item", "int", 1, 9999999 }, { "q", "int", 0, 8, opt = true }, { "src", "word", 3 } }),
  b = Fields({ { "enc", "int", 0, 9999999, opt = true }, { "first", "flag" }, { "raid", "flag" }, { "boss", "text", 48 },
    { "inst", "text", 48 }, { "n", "int", 1, 80, opt = true } }),
  d = Fields({ { "first", "flag" }, { "n", "int", 1, 99 }, { "nf", "int", 1, 99 }, { "boss", "text", 48 }, { "inst", "text", 48 } }),
  q = Fields({ { "qid", "int", 1, 9999999 }, { "ql", "int", 0, 200, opt = true }, { "tag", "word", 8 }, { "title", "text", 64 } }),
  v = Fields({}),
  m = Fields({ { "epic", "flag" } }),
  f = Fields({ { "st", "int", 1, 8 }, { "fac", "text", 48 } }),
  s = Fields({ { "rank", "int", 1, 999 }, { "skill", "text", 48 } }),
  p = Fields({ { "pk", "enum", { "rank", "win" } }, { "pr", "int", 0, 30, opt = true }, { "name", "text", 48 } }),
  u = Fields({ { "foe", "key" } }),
}
for code, fields in pairs(KIND_FIELDS) do
  ch:Define(code, { from = "guild", fields = fields })
  ch:Define(RELAY .. code, { from = "guild", fields = fields })
end
ch:Define("r", { from = "guild", fields = { { "since", "int", 0, 4102444800 } } })

local function Num(v) return (type(v) == "number" and v == v) and math.floor(v) or nil end

local function Flag(v) return v and true or false end
local function WireQuestTag(tag) return QUEST_TAGS[tag or ""] and tag or "hard" end
local LOOT_SRC_CODE, LOOT_SRC = { bag = "bag", craft = "cr" }, { bag = "bag", cr = "craft" }

local MessageFields = {
  gear = function(m, e) m.item, m.il, m.q, m.oil, m.slot = Num(e.item), Num(e.il), Num(e.q), Num(e.oil), Num(e.slot) end,
  loot = function(m, e) m.item, m.q, m.src = Num(e.item), Num(e.q), LOOT_SRC_CODE[e.src or ""] or "" end,
  boss = function(m, e)
    m.enc, m.first, m.raid, m.boss, m.inst = Num(e.enc), Flag(e.first), Flag(e.raid), e.boss or "", e.inst or ""
    m.n = e.grp and Num(e.n or 1) or nil
  end,
  run = function(m, e) m.first, m.n, m.nf, m.boss, m.inst = Flag(e.first), Num(e.n), Num(e.nf), e.boss or "", e.inst or "" end,
  quest = function(m, e) m.qid, m.ql, m.tag, m.title = Num(e.qid), Num(e.ql), WireQuestTag(e.tag), e.title or "" end,
  mount = function(m, e) m.epic = Flag(e.epic) end,
  rep = function(m, e) m.st, m.fac = Num(e.st), e.fac or "" end,
  skill = function(m, e) m.rank, m.skill = Num(e.rank), e.skill or "" end,
  pvp = function(m, e) m.pk, m.pr, m.name = e.pk, Num(e.pr), e.name or "" end,
  duel = function(m, e) m.foe = e.foe end,
}

local function WireSeq(e)
  local id = e.id or ""
  if e.k == "loot" and ((e.by and e.by ~= e.who) or id:sub(1, 2) == "W#") then return "w" end
  return id:match("#(%d+)$") or "0"
end

local function ToMessage(e)
  local code = KIND_CODE[e.k]
  if not code or type(e.who) ~= "string" or e.who:find("[;|%c]") then return end
  local m = { t = Num(e.t), seq = WireSeq(e), who = e.who, lvl = Num(e.lvl), cls = CLASS_IDX[e.cls or ""] or 0 }
  local fill = MessageFields[e.k]
  if fill then fill(m, e) end
  return code, m
end

H.ToMessage = ToMessage

function H.Encode(e)
  local code, m = ToMessage(e)
  if not code then return end
  local text = ch:Encode(code, m)
  return text and text:sub(3)
end

function H.RelayMessage(e)
  local code, m = ToMessage(e)
  local typ = code and RELAY .. code
  if typ and ch:Encode(typ, m) then return typ, m end
end

local function Str(v) return (v ~= nil and v ~= "") and v or nil end

local EntryFields = {
  gear = function(e, m) e.item, e.il, e.q, e.oil, e.slot = m.item, m.il, m.q, m.oil, m.slot end,
  loot = function(e, m) e.item, e.q, e.src = m.item, m.q, LOOT_SRC[m.src] end,
  boss = function(e, m)
    e.enc, e.first, e.raid, e.boss, e.inst = m.enc, m.first or nil, m.raid or nil, Str(m.boss), Str(m.inst)
    if m.n then e.grp, e.n = true, m.n end
  end,
  run = function(e, m) e.first, e.n, e.nf, e.boss, e.inst = m.first or nil, m.n, m.nf, Str(m.boss), Str(m.inst) end,
  quest = function(e, m) e.qid, e.ql, e.tag, e.title = m.qid, m.ql, WireQuestTag(m.tag), Str(m.title) end,
  mount = function(e, m) e.epic = m.epic or nil end,
  rep = function(e, m) e.st, e.fac = m.st, Str(m.fac) end,
  skill = function(e, m) e.rank, e.skill = m.rank, Str(m.skill) end,
  pvp = function(e, m) e.pk, e.pr, e.name = m.pk, m.pr, Str(m.name) end,
  duel = function(e, m) e.foe = m.foe end,
}

local function OwnEntryId(m)
  local seq = tonumber(m.seq)
  if not seq or not m.seq:match("^%d+$") or seq > 99999 then return nil end
  return ("%s#%d#%d"):format(m.who, m.t, seq)
end

local function Vouched(sender, k, m, relayed)
  if relayed then return m.seq ~= "w" or k == "loot" end
  return m.who == sender or (m.seq == "w" and k == "loot")
end

local function ToEntry(sender, code, m, relayed)
  local k = CODE_KIND[code]
  if not Vouched(sender, k, m, relayed) then return end
  local witnessed = m.seq == "w"
  local e = { k = k, t = m.t, who = m.who, lvl = m.lvl, cls = CLASSES[m.cls] }
  if witnessed then
    e.by = not relayed and sender or nil
  else
    e.id = OwnEntryId(m)
    if not e.id then return end
  end
  local fill = EntryFields[k]
  if fill then fill(e, m) end
  if witnessed then e.id = H.WitnessID(m.who, e.item, m.t) end
  return e
end

function H.Decode(sender, body)
  local code, m = ch:Decode(sender, body)
  if not code then return end
  return ToEntry(sender, code, m)
end

local inflight = {}

local function Delay(rank) return 10 + (rank or 0) * 45 + math.random() * 20 end

function H:CapOk()
  local now, log = GS:Now(), self.cdb.shareLog
  for i = #log, 1, -1 do if now - log[i] > 3600 then table.remove(log, i) end end
  return #log < (self:Settings().shareCap or 8)
end

function H:Share(e, opts)
  opts = opts or {}
  if not self:Settings().share then return end
  local gkey = self:GuildKey()
  if gkey == "-" or not self:CapOk() then return end
  table.insert(self.cdb.shareLog, GS:Now())
  local o = { g = gkey, t = e.t, nb = GS:Now() + (opts.group and Delay(opts.rank) or 0) }
  if opts.group then o.grp, o.rank = true, opts.rank or 0 end
  self.cdb.outbox[e.id] = o
  self:SchedulePump(1)
end

function H:StillWanted(e)
  if e.k == "loot" and e.by then
    return not (self:LootReportedByOthers(e) or GS:IsPeer(e.who))
  end
  if e.k == "boss" and e.grp then
    local events = self:Log()
    for i = #events, 1, -1 do
      local o = events[i]
      if o.k == "boss" and o.who ~= e.who and o.enc == e.enc and math.abs(o.t - e.t) <= self.BOSS_SAME then return false end
    end
  end
  return true
end

function H:Supersede(r)
  local me = GS:PlayerKey()
  local events = self:Log()
  for i = #events, 1, -1 do
    local o = events[i]
    if o.k == "boss" and o.grp and o.who == me and o.enc == r.enc and math.abs(o.t - r.t) <= self.BOSS_SAME
      and self.cdb.outbox[o.id] and not inflight[o.id] then
      self:Remove(o.id)
    end
  end
end

function H:Send(e)
  local code, m = ToMessage(e)
  if not code or not ch:Encode(code, m) then self.cdb.outbox[e.id] = nil return end
  local id = e.id
  inflight[id] = true
  ch:Send(code, m, { onResult = function(status)
    inflight[id] = nil
    local box = self.cdb.outbox[id]
    if not box then return end
    if status == "delivered" then
      self.cdb.outbox[id] = nil
    elseif status == "lost" then
      box.tries = (box.tries or 0) + 1
      box.nb = GS:Now() + self.RETRY_AFTER
      if box.tries >= self.MAX_TRIES then box.hold = true end
    else
      box.nb = GS:Now() + 60
    end
    self:SchedulePump(5)
  end })
end

local function CollectDue(self, now, gkey)
  local due, pending = {}, false
  for id, o in pairs(self.cdb.outbox) do
    if type(o) ~= "table" or now - (o.t or 0) > self.OUTBOX_MAX_AGE then
      self.cdb.outbox[id] = nil
    elseif o.g == gkey and inflight[id] then
      pending = true
    elseif o.g == gkey and not o.hold then
      if now >= (o.nb or 0) then due[#due + 1] = id else pending = true end
    end
  end
  return due, pending
end

local function SendDue(self, due, idx)
  local outbox = self.cdb.outbox
  table.sort(due, function(a, b) return (outbox[a].t or 0) < (outbox[b].t or 0) end)
  local sent = false
  for _, id in ipairs(due) do
    local e = idx[id]
    if e and self:StillWanted(e) then
      self:Send(e)
      sent = true
    else
      outbox[id] = nil
    end
  end
  return sent
end

local function PumpDue(self)
  local now, gkey = GS:Now(), self:GuildKey()
  local _, idx = self:Log(gkey)
  local due, pending = CollectDue(self, now, gkey)
  local sent = SendDue(self, due, idx)
  return pending or sent
end

local function HasUnheldOutbox(self)
  for _, o in pairs(self.cdb.outbox) do if type(o) == "table" and not o.hold then return true end end
  return false
end

function H:OutboxPump()
  if not (self.db and self:Settings().share) then return end
  local any
  if GS:CanSend() then any = PumpDue(self) else any = HasUnheldOutbox(self) end
  if any then self:SchedulePump(self.PUMP_EVERY) end
end

function H:SchedulePump(delay)
  delay = delay or self.PUMP_EVERY
  local at = GetTime() + delay
  if self.pumpAt and self.pumpAt <= at then return end
  self.pumpAt = at
  C_Timer.After(delay, function()
    if self.pumpAt ~= at then return end
    self.pumpAt = nil
    GS:Call(H.OutboxPump, H)
  end)
end

function H:OnLeftInstance()
  local now = GS:Now()
  for _, o in pairs(self.cdb.outbox) do
    if type(o) == "table" then
      o.nb = math.max(o.nb or 0, now + (o.grp and Delay(o.rank) or (5 + math.random() * 15)))
    end
  end
  self:SchedulePump(5)
end

function H:OnLoginOutbox()
  for _, o in pairs(self.cdb.outbox) do
    if type(o) == "table" then o.tries, o.hold = nil, nil end
  end
  self.pumpAt = nil
  self:SchedulePump(30 + math.random() * 30)
end

for code in pairs(CODE_KIND) do
  ch:On(code, function(sender, m)
    if not H.db then return end
    local e = ToEntry(sender, code, m)
    if not e then
      H.db.diag.badMsg = (H.db.diag.badMsg or 0) + 1
      return
    end
    if e.by and GS:IsGuildMember(e.who) ~= true then return end
    if not H:Admit(sender, GetTime()) then return end
    H:Add(e, "wire")
  end)
  ch:On(RELAY .. code, function(sender, m)
    if H.db then H:OnRelay(sender, ToEntry(sender, code, m, true)) end
  end)
end
