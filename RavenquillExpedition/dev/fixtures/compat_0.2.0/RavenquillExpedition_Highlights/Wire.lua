-- Ravenquill Expedition: Highlights – sharing over the core's GUILD lane (tag "H").
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

local TAG, VERSION = "H", "1"
local KIND_CODE = { gear = "g", loot = "l", boss = "b", quest = "q", level = "v" }
local CODE_KIND = {}
for k, c in pairs(KIND_CODE) do CODE_KIND[c] = k end
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
  "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local CLASS_IDX = {}
for i, c in ipairs(CLASSES) do CLASS_IDX[c] = i end
local QUEST_TAGS = { elite = true, group = true, dungeon = true, raid = true, red = true, hard = true }

H.PUMP_EVERY = 15
H.RETRY_AFTER = 600
H.MAX_TRIES = 3

-- Texts from the game or from the wire: no colour codes, separators, escapes or control characters.
local function Clean(s, n)
  s = Plain(s, "string")
  if not s then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[;|%c]", "")
  return GS.Cut(s, n)
end
H.Clean = Clean
local function Num(v) return (type(v) == "number" and v == v) and tostring(math.floor(v)) or "" end
local function Bit(v) return v and "1" or "0" end

function H.Encode(e)
  local code = KIND_CODE[e.k]
  if not code or type(e.who) ~= "string" or e.who:find("[;|%c]") then return end
  local seq = e.id and e.id:match("#(%d+)$")
  if e.k == "loot" and e.by and e.by ~= e.who then seq = "w" end
  local f = { VERSION, code, Num(e.t), seq or "0", e.who, Num(e.lvl), Num(CLASS_IDX[e.cls or ""] or 0) }
  if e.k == "gear" then
    f[8], f[9], f[10], f[11], f[12] = Num(e.item), Num(e.il), Num(e.q), Num(e.oil), Num(e.slot)
  elseif e.k == "loot" then
    f[8], f[9], f[10] = Num(e.item), Num(e.q), e.src == "bag" and "bag" or ""
  elseif e.k == "boss" then
    f[8], f[9], f[10], f[11], f[12], f[13] = Num(e.enc), Bit(e.first), Bit(e.raid), Clean(e.boss, 48), Clean(e.inst, 48),
      e.grp and Num(e.n or 1) or ""
  elseif e.k == "quest" then
    f[8], f[9], f[10], f[11] = Num(e.qid), Num(e.ql), QUEST_TAGS[e.tag or ""] and e.tag or "hard", Clean(e.title, 64)
  end
  local body = table.concat(f, ";")
  if #body + #TAG + 1 > GS.CommConst.MAX_MSG then -- shorten the free texts and try once more
    if e.k == "boss" then f[11], f[12] = Clean(e.boss, 24), Clean(e.inst, 24) end
    if e.k == "quest" then f[11] = Clean(e.title, 32) end
    body = table.concat(f, ";")
    if #body + #TAG + 1 > GS.CommConst.MAX_MSG then return end
  end
  return body
end

-- Split on ";" keeping empty fields (gmatch differs between Lua 5.1 and 5.4 for empty matches).
local function Split(s)
  local out, pos = {}, 1
  while true do
    local i = s:find(";", pos, true)
    if not i then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, i - 1)
    pos = i + 1
  end
end

local function Int(s, lo, hi)
  local n = tonumber(s)
  if not n or n ~= math.floor(n) or n < lo or n > hi then return nil end
  return n
end
local function Str(s, n) s = Clean(s, n); return s ~= "" and s or nil end

-- body -> entry, or nil when malformed or not allowed from this sender
function H.Decode(sender, body)
  if type(body) ~= "string" then return end
  local f = Split(body)
  if f[1] ~= VERSION then return end -- other versions: ignored, so the format can change later
  local k = CODE_KIND[f[2] or ""]
  local t = Int(f[3], 1, 4102444800)
  local who = f[5]
  if not (k and t and who and who ~= "") or who:find("[|%c]") then return end
  local witnessed = f[4] == "w"
  if who ~= sender and not (witnessed and k == "loot") then return end
  local e = { k = k, t = t, who = who, lvl = Int(f[6], 1, 200), cls = CLASSES[Int(f[7], 0, 99) or 0] }
  if witnessed then
    e.by = sender
  else
    local seq = Int(f[4], 0, 99999)
    if not seq then return end
    e.id = ("%s#%d#%d"):format(who, t, seq)
  end
  if k == "gear" then
    e.item, e.il, e.q, e.oil, e.slot = Int(f[8], 1, 9999999), Int(f[9], 0, 2000), Int(f[10], 0, 8), Int(f[11], 0, 2000), Int(f[12], 0, 19)
    if not e.item then return end
  elseif k == "loot" then
    e.item, e.q, e.src = Int(f[8], 1, 9999999), Int(f[9], 0, 8), f[10] == "bag" and "bag" or nil
    if not e.item then return end
  elseif k == "boss" then
    e.enc, e.first, e.raid, e.boss, e.inst = Int(f[8], 0, 9999999), f[9] == "1" or nil, f[10] == "1" or nil, Str(f[11], 48), Str(f[12], 48)
    local n = Int(f[13], 1, 80)
    if n then e.grp, e.n = true, n end
  elseif k == "quest" then
    e.qid, e.ql, e.tag, e.title = Int(f[8], 1, 9999999), Int(f[9], 0, 200), QUEST_TAGS[f[10] or ""] and f[10] or "hard", Str(f[11], 64)
    if not e.qid then return end
  end
  if witnessed then e.id = H.WitnessID(who, e.item, t) end
  return e
end

---------------------------------------------------------------------------
-- Outbox
---------------------------------------------------------------------------
H.inflight = {} -- [id] = true while queued in the lane or waiting for the echo (session only)

local function Delay(rank) return 10 + (rank or 0) * 45 + math.random() * 20 end

-- Hourly cap: past it, an entry stays local (review #3).
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
  local body = H.Encode(e)
  if not body then self.cdb.outbox[e.id] = nil return end
  local id = e.id
  local queued = GS:SendGuild(TAG, body, function(status)
    self.inflight[id] = nil
    local box = self.cdb.outbox[id]
    if not box then return end
    if status == "echo" then
      self.cdb.outbox[id] = nil
    elseif status == "lost" then
      box.tries = (box.tries or 0) + 1
      box.nb = GS:Now() + self.RETRY_AFTER
      if box.tries >= self.MAX_TRIES then box.hold = true end -- rest until the next login
    else -- "deferred": never sent (instance, combat, queue full …) – not a try
      box.nb = GS:Now() + 60
    end
    self:SchedulePump(5)
  end)
  if queued then self.inflight[id] = true else o.nb = GS:Now() + 60 end
end

function H:OutboxPump()
  if not (self.db and self:Settings().share) then return end
  local any = false
  if GS.CanSendGuild() then
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

GS:RegisterComm(TAG, function(sender, body)
  if not H.db then return end
  local e = H.Decode(sender, body)
  if not e then
    H.db.diag.badMsg = (H.db.diag.badMsg or 0) + 1
    return
  end
  if e.by and GS:IsGuildMember(e.who) ~= true then return end -- witnessed loot only about known guildies
  H:Add(e, "wire")
end)
