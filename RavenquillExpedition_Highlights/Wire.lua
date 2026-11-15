-- Ravenquill Expedition: Highlights – sharing over a core schema channel (tag "H", version 1, prefix RQE1).
-- One highlight = one message (≤ 250 bytes incl. "H;"). Fields are ";"-separated:
--   1;<kind>;<t>;<seq>;<who>;<lvl>;<class#>;<a>;<b>;<c>;<d>;<e>;<f>
--   gear : a=itemID b=ilvl c=quality d=old ilvl e=slot
--   loot : a=itemID b=quality c=src ("bag" when seen in the bags, else empty)
--   boss : a=encounterID b=first(0/1) c=raid(0/1) d=boss name e=instance name f=guildies present (group report)
--   quest: a=questID b=quest level c=tag d=title
--   level: (none)
-- <who> is the subject. It must be the sender, except for "loot", where a guildie in your group may
-- report what another guildie (who doesn't run the suite) looted (seq = "w").
--
-- The outbox (per character, saved) holds own entries until the guild's echo proves delivery. It is worked
-- off every 15 s outside instances. Group events (raid kills, witnessed loot) wait 10 s + rank × 45 s after
-- leaving the instance; the first-ranked suite user in the group reports, the others drop theirs once a
-- report is heard (StillWanted).
local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local Plain = GS.Plain

local KIND_CODE = { gear = "g", loot = "l", boss = "b", quest = "q", level = "v" }
local CODE_KIND = {}
for k, c in pairs(KIND_CODE) do CODE_KIND[c] = k end
local CLASSES, CLASS_IDX = GS.Wire.CLASSES, GS.Wire.CLASS_IDX
local QUEST_TAGS = { elite = true, group = true, dungeon = true, raid = true, red = true, hard = true }

H.PUMP_EVERY = 15
H.RETRY_AFTER = 600
H.MAX_TRIES = 3

-- Texts from the game or from the wire: no colour codes, separators, escapes or control characters.
local function Clean(s, n) return GS.Wire.Clean(Plain(s, "string"), n) end
H.Clean = Clean

-- The wire format, declared once; the core checks every field of every message before a handler sees it.
-- (from = "guild": the "who must be the sender, except witnessed loot" rule is checked in the handler below.)
local ch = H:NewChannel({ tag = "H", version = 1 })
H.channel = ch
local HEAD = { { "t", "int", 1, 4102444800 }, { "seq", "word", 5 }, { "who", "key" }, { "lvl", "int", 1, 200, opt = true },
  { "cls", "int", 0, 99 } }
local function Fields(extra)
  local out = {}
  for _, x in ipairs(HEAD) do out[#out + 1] = x end
  for _, x in ipairs(extra) do out[#out + 1] = x end
  return out
end
ch:Define("g", { from = "guild", fields = Fields({ { "item", "int", 1, 9999999 }, { "il", "int", 0, 2000, opt = true },
  { "q", "int", 0, 8, opt = true }, { "oil", "int", 0, 2000, opt = true }, { "slot", "int", 0, 19, opt = true } }) })
ch:Define("l", { from = "guild", fields = Fields({ { "item", "int", 1, 9999999 }, { "q", "int", 0, 8, opt = true },
  { "src", "word", 3 } }) })
ch:Define("b", { from = "guild", fields = Fields({ { "enc", "int", 0, 9999999, opt = true }, { "first", "flag" }, { "raid", "flag" },
  { "boss", "text", 48 }, { "inst", "text", 48 }, { "n", "int", 1, 80, opt = true } }) })
ch:Define("q", { from = "guild", fields = Fields({ { "qid", "int", 1, 9999999 }, { "ql", "int", 0, 200, opt = true },
  { "tag", "word", 8 }, { "title", "text", 64 } }) })
ch:Define("v", { from = "guild", fields = Fields({}) })

local function Num(v) return (type(v) == "number" and v == v) and math.floor(v) or nil end

-- entry -> type code, message table (nil when it can't go on the wire)
local function ToMessage(e)
  local code = KIND_CODE[e.k]
  if not code or type(e.who) ~= "string" or e.who:find("[;|%c]") then return end
  local seq = e.id and e.id:match("#(%d+)$")
  if e.k == "loot" and e.by and e.by ~= e.who then seq = "w" end
  local m = { t = Num(e.t), seq = seq or "0", who = e.who, lvl = Num(e.lvl), cls = CLASS_IDX[e.cls or ""] or 0 }
  if e.k == "gear" then
    m.item, m.il, m.q, m.oil, m.slot = Num(e.item), Num(e.il), Num(e.q), Num(e.oil), Num(e.slot)
  elseif e.k == "loot" then
    m.item, m.q, m.src = Num(e.item), Num(e.q), e.src == "bag" and "bag" or ""
  elseif e.k == "boss" then
    m.enc, m.first, m.raid, m.boss, m.inst = Num(e.enc), e.first and true or false, e.raid and true or false, e.boss or "", e.inst or ""
    m.n = e.grp and Num(e.n or 1) or nil
  elseif e.k == "quest" then
    m.qid, m.ql, m.tag, m.title = Num(e.qid), Num(e.ql), QUEST_TAGS[e.tag or ""] and e.tag or "hard", e.title or ""
  end
  return code, m
end

H.ToMessage = ToMessage -- (tests)

-- entry -> wire body without "H;" (the golden wire test reads this), or nil
function H.Encode(e)
  local code, m = ToMessage(e)
  if not code then return end
  local text = ch:Encode(code, m)
  return text and text:sub(3)
end

local function Str(v) return (v ~= nil and v ~= "") and v or nil end

-- decoded message -> entry, or nil when not allowed from this sender
local function ToEntry(sender, code, m)
  local k = CODE_KIND[code]
  local witnessed = m.seq == "w"
  if m.who ~= sender and not (witnessed and k == "loot") then return end
  local e = { k = k, t = m.t, who = m.who, lvl = m.lvl, cls = CLASSES[m.cls] }
  if witnessed then
    e.by = sender
  else
    local seq = tonumber(m.seq)
    if not seq or not m.seq:match("^%d+$") or seq > 99999 then return end
    e.id = ("%s#%d#%d"):format(m.who, m.t, seq)
  end
  if k == "gear" then
    e.item, e.il, e.q, e.oil, e.slot = m.item, m.il, m.q, m.oil, m.slot
  elseif k == "loot" then
    e.item, e.q, e.src = m.item, m.q, m.src == "bag" and "bag" or nil
  elseif k == "boss" then
    e.enc, e.first, e.raid, e.boss, e.inst = m.enc, m.first or nil, m.raid or nil, Str(m.boss), Str(m.inst)
    if m.n then e.grp, e.n = true, m.n end
  elseif k == "quest" then
    e.qid, e.ql, e.tag, e.title = m.qid, m.ql, QUEST_TAGS[m.tag] and m.tag or "hard", Str(m.title)
  end
  if witnessed then e.id = H.WitnessID(m.who, e.item, m.t) end
  return e
end

-- body (after "H;") -> entry, or nil when malformed or not allowed from this sender
function H.Decode(sender, body)
  local code, m = ch:Decode(sender, body)
  if not code then return end
  return ToEntry(sender, code, m)
end

---------------------------------------------------------------------------
-- Outbox
---------------------------------------------------------------------------
H.inflight = {} -- [id] = true while queued in the lane or waiting for the echo (session only)

local function Delay(rank) return 10 + (rank or 0) * 45 + math.random() * 20 end

-- Hourly cap: past it, an entry stays local (no guild spam from a busy session).
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

-- Still worth a message? (re-checked right before sending)
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

function H:Send(e, o)
  local code, m = ToMessage(e)
  if not code or not H.Encode(e) then self.cdb.outbox[e.id] = nil return end
  local id = e.id
  self.inflight[id] = true
  ch:Send(code, m, { onResult = function(status)
    self.inflight[id] = nil
    local box = self.cdb.outbox[id]
    if not box then return end
    if status == "delivered" then
      self.cdb.outbox[id] = nil
    elseif status == "lost" then
      box.tries = (box.tries or 0) + 1
      box.nb = GS:Now() + self.RETRY_AFTER
      if box.tries >= self.MAX_TRIES then box.hold = true end -- rest until the next login
    else -- "dropped": never sent (instance, combat, queue full …) – not a try
      box.nb = GS:Now() + 60
    end
    self:SchedulePump(5)
  end })
end

function H:OutboxPump()
  if not (self.db and self:Settings().share) then return end
  local any = false
  if GS:CanSend() then
    local now, gkey = GS:Now(), self:GuildKey()
    local _, idx = self:Log(gkey)
    local due = {}
    for id, o in pairs(self.cdb.outbox) do
      if type(o) ~= "table" or now - (o.t or 0) > self.OUTBOX_MAX_AGE then
        self.cdb.outbox[id] = nil
      elseif o.g == gkey and not o.hold and not self.inflight[id] then
        if now >= (o.nb or 0) then due[#due + 1] = id else any = true end
      elseif o.g == gkey and self.inflight[id] then
        any = true
      end
    end
    table.sort(due, function(a, b) return (self.cdb.outbox[a].t or 0) < (self.cdb.outbox[b].t or 0) end)
    for _, id in ipairs(due) do
      local e = idx[id]
      if not e then
        self.cdb.outbox[id] = nil
      elseif not self:StillWanted(e) then
        self.cdb.outbox[id] = nil
      else
        self:Send(e, self.cdb.outbox[id])
        any = true
      end
    end
  else
    for _, o in pairs(self.cdb.outbox) do if type(o) == "table" and not o.hold then any = true break end end
  end
  if any then self:SchedulePump(self.PUMP_EVERY) end
end

-- One pending pump; an earlier request replaces a later one (stale timers see a different pumpAt and skip).
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

-- Left an instance: group events wait their election delay from now; the rest go out after a short pause.
function H:OnLeftInstance()
  local now = GS:Now()
  for _, o in pairs(self.cdb.outbox) do
    if type(o) == "table" then
      o.nb = math.max(o.nb or 0, now + (o.grp and Delay(o.rank) or (5 + math.random() * 15)))
    end
  end
  self:SchedulePump(5)
end

-- A new session: every waiting entry gets fresh tries.
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
    if e.by and GS:IsGuildMember(e.who) ~= true then return end -- witnessed loot only about known guildies
    if not H:Admit(sender, GetTime()) then return end
    H:Add(e, "wire")
  end)
end
