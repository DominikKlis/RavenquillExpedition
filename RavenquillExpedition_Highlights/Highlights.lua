local ADDON, ns = ...
local GS = RavenquillExpedition
local L = ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

local H = GS:NewModule("Highlights", {
  addon = ADDON, api = 2, slash = "hl", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Note_01",
  sv = "RavenquillExpeditionHighlightsDB", svChar = "RavenquillExpeditionHighlightsCharDB", dbVersion = 2,
  locale = ns.Locales,
  charDefaults = { everEquipped = {}, ownedEpics = {}, kills = {}, quests = {}, outbox = {}, shareLog = {}, activity = {} },
})
ns.H = H

H.MAX_EVENTS = 1500
H.MAX_AGE = 90 * 86400
H.FUTURE_SLACK = 300
H.LOOT_DEDUPE = 300
H.BOSS_SAME = 1200
H.OUTBOX_MAX_AGE = 2 * 86400
H.RECV_PER_HOUR = 30
H.MAX_PER_WHO = 300

H.DEFAULTS = {
  share = true,
  shareCap = 8,
  chat = true,
  chatAll = false,
  echoOwn = true,
  minGain = 8,
  minGearQuality = 3,
  minLootQuality = 4,
  levelStep = 10,
  questRedLevels = 0,
  logOnlyHighlights = false,
}
H.KINDS = { gear = true, loot = true, boss = true, quest = true, level = true }
H.defaults = H.DEFAULTS

H.migrations = {
  [2] = function(db)
    if type(db.settings) ~= "table" then db.settings = {} end
    if db.settings.questRedLevels == 4 and not db.settings.migratedV2 then db.settings.questRedLevels = 0 end
    db.settings.migratedV2 = true
  end,
}

local function Table(t) return type(t) == "table" and t or {} end

function H:OnLoad()
  local db, cdb = self.db, self.cdb
  db.guilds = Table(db.guilds)
  db.diag = Table(db.diag)
  cdb.seq = tonumber(cdb.seq) or 0
  cdb.installedAt = cdb.installedAt or time()

  self.idIndex = {}
end

function H:Settings() return self.db and self.db.settings or self.DEFAULTS end

function H:GuildKey()
  local k = GS:GuildKey()
  if k then
    if self.cdb then self.cdb.guildKey = k end
    return k
  end
  if self.cdb and self.cdb.guildKey and Plain(SafeCall(IsInGuild)) then return self.cdb.guildKey end
  return "-"
end

function H:Log(gkey)
  gkey = gkey or self:GuildKey()
  local g = self.db.guilds[gkey]
  if not g then
    g = { events = {} }
    self.db.guilds[gkey] = g
  end
  if not self.idIndex[gkey] then
    local idx = {}
    for _, e in ipairs(g.events) do if e.id then idx[e.id] = e end end
    self.idIndex[gkey] = idx
  end
  return g.events, self.idIndex[gkey]
end

function H:NextID(who, t)
  self.cdb.seq = (self.cdb.seq + 1) % 100000
  return ("%s#%d#%d"):format(who, t, self.cdb.seq)
end

function H.WitnessID(who, item, t) return ("W#%s#%d#%d"):format(who, item or 0, t) end

local function Valid(e)
  if type(e) ~= "table" or not H.KINDS[e.k] then return false end
  if type(e.id) ~= "string" or type(e.who) ~= "string" or e.who == "" then return false end
  if type(e.t) ~= "number" then return false end
  return true
end

function H:Remove(id, gkey)
  local events, idx = self:Log(gkey)
  if not idx[id] then return end
  for i = #events, 1, -1 do
    if events[i].id == id then table.remove(events, i) break end
  end
  idx[id] = nil
  self.cdb.outbox[id] = nil
end

local function IsRecentLootRepeat(self, events, e)
  if e.k ~= "loot" then return false end
  for i = #events, 1, -1 do
    local o = events[i]
    if o.t < e.t - self.LOOT_DEDUPE then return false end
    if o.k == "loot" and o.who == e.who and o.item == e.item and math.abs(o.t - e.t) <= self.LOOT_DEDUPE then return true end
  end
  return false
end

local function InsertByTime(events, e)
  local pos = #events + 1
  while pos > 1 and events[pos - 1].t > e.t do pos = pos - 1 end
  table.insert(events, pos, e)
end

local function OnHeardFromWire(self, e)
  if e.k == "loot" then self.lootHeard[e.who .. "#" .. tostring(e.item)] = e.t end
  if e.k == "boss" and e.grp then self:Supersede(e) end
  self:Announce(e)
end

local function OnSeenHere(self, e, source, opts, gkey)
  if source == "witness" or self:Settings().echoOwn then self:Announce(e) end
  if not opts.localOnly and gkey ~= "-" then self:Share(e, opts) end
end

local function OutsideKeptWindow(self, t)
  local now = GS:Now()
  return t > now + self.FUTURE_SLACK or t < now - self.MAX_AGE
end

function H:Add(e, source, opts)
  if not self.db or not Valid(e) then return end
  opts = opts or {}
  if OutsideKeptWindow(self, e.t) then return end
  local gkey = self:GuildKey()
  local events, idx = self:Log(gkey)
  if idx[e.id] or IsRecentLootRepeat(self, events, e) then return end
  if source == "test" then e.test = true end
  InsertByTime(events, e)
  idx[e.id] = e
  if source == "wire" then self:CapWho(events, idx, e.who) end
  self:Prune(gkey)
  if source == "wire" then
    OnHeardFromWire(self, e)
  elseif source == "self" or source == "witness" then
    OnSeenHere(self, e, source, opts, gkey)
  end
  self:RefreshSoon()
  return e
end

function H:CapWho(events, idx, who)
  local n, first = 0, nil
  for i, o in ipairs(events) do
    if o.who == who then n = n + 1; first = first or i end
  end
  if n > self.MAX_PER_WHO and first then
    local o = table.remove(events, first)
    idx[o.id] = nil
  end
end

H.recv = {}
function H:Admit(sender, now)
  local list = self.recv[sender]
  if not list then list = {}; self.recv[sender] = list end
  while list[1] and now - list[1] > 3600 do table.remove(list, 1) end
  if #list >= self.RECV_PER_HOUR then
    self.db.diag.recvCapped = (self.db.diag.recvCapped or 0) + 1
    return false
  end
  list[#list + 1] = now
  return true
end

function H:Prune(gkey)
  local events, idx = self:Log(gkey)
  local cutoff = GS:Now() - self.MAX_AGE
  while events[1] and (#events > self.MAX_EVENTS or events[1].t < cutoff) do
    local e = table.remove(events, 1)
    idx[e.id] = nil
  end
end

function H:Supersede(r)
  local me = GS:PlayerKey()
  local events = self:Log()
  for i = #events, 1, -1 do
    local o = events[i]
    if o.k == "boss" and o.grp and o.who == me and o.enc == r.enc and math.abs(o.t - r.t) <= self.BOSS_SAME
      and self.cdb.outbox[o.id] and not (self.inflight and self.inflight[o.id]) then
      self:Remove(o.id)
    end
  end
end

H.ACTIVITY_MAX = 3000
H.ACTIVITY_AGE = 30 * 86400
function H:Activity(e)
  if not (self.cdb and type(e) == "table" and self.KINDS[e.k]) then return end
  e.t = e.t or GS:Now()
  e.who = e.who or GS:PlayerKey() or "?"
  e.act = true
  local a = self.cdb.activity
  a[#a + 1] = e
  local cutoff = e.t - self.ACTIVITY_AGE
  while a[1] and (#a > self.ACTIVITY_MAX or a[1].t < cutoff) do table.remove(a, 1) end
  self:RefreshSoon()
  return e
end

H.lootHeard = {}
function H:LootReportedByOthers(e)
  local t = self.lootHeard[e.who .. "#" .. tostring(e.item)]
  return t and math.abs(t - e.t) <= self.LOOT_DEDUPE or false
end

function H:ClearTests()
  local n = 0
  for gkey, g in pairs(self.db.guilds) do
    local _, idx = self:Log(gkey)
    for i = #g.events, 1, -1 do
      if g.events[i].test then idx[g.events[i].id] = nil; table.remove(g.events, i); n = n + 1 end
    end
  end
  self:Refresh()
  return n
end

function H.ClassColorName(name, class)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and colors and colors[class]
  if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
  if c and c.r then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
  return name
end

local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff" }

function H:ItemCached(id)
  local name = id and Plain(SafeCall((C_Item and C_Item.GetItemInfo) or GetItemInfo, id), "string")
  return name ~= nil
end

function H:ItemText(e)
  if Plain(e.link, "string") then return e.link end
  local id = e.item
  if not id then return "?" end
  local name, link = SafeCall((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
  link = Plain(link, "string")
  if link then return link end
  if C_Item and C_Item.RequestLoadItemDataByID then SafeCall(C_Item.RequestLoadItemDataByID, id) end
  self.waitingItems = true
  local hex = QUALITY_HEX[e.q or 1] or "ffffff"
  return ("|cff%s[%s]|r"):format(hex, Plain(name, "string") or ("item:" .. id))
end

local QUEST_TAGS = { elite = "TAG_ELITE", group = "TAG_GROUP", dungeon = "TAG_DUNGEON", raid = "TAG_RAID", red = "TAG_RED" }

local function Gold(text) return "|cffffd100" .. text .. "|r" end
local function NonEmpty(s, fallback) return (s and s ~= "") and s or fallback end

local FormatKind = {
  gear = function(self, e, who)
    local item = self:ItemText(e)
    local quality = e.q or 0
    local gain = (e.il and e.oil) and (e.il - e.oil) or nil
    if gain and gain > 0 and quality < 4 then return L.GEAR:format(who, item, gain) end
    if quality >= 4 then return L.GEAR_EPIC:format(who, item) end
    return L.GEAR_FILL:format(who, item)
  end,
  loot = function(self, e, who)
    local count = (e.n or 1) > 1 and ("x" .. e.n) or ""
    return (e.src == "bag" and L.LOOT_GOT or L.LOOT):format(who, self:ItemText(e) .. count)
  end,
  boss = function(_, e, who)
    local boss, inst = Gold(NonEmpty(e.boss, L.A_BOSS)), NonEmpty(e.inst, L.AN_INSTANCE)
    if e.grp and (e.n or 1) > 1 then return L.BOSS_GROUP:format(who, e.n - 1, boss, inst) end
    return (e.first and L.BOSS_FIRST or L.BOSS):format(who, boss, inst)
  end,
  quest = function(_, e, who)
    local title = Gold(e.title or ("#" .. tostring(e.qid)))
    if e.act and not e.tag then return L.QUEST_PLAIN:format(who, title) end
    return L.QUEST:format(who, L[QUEST_TAGS[e.tag] or "TAG_HARD"], title)
  end,
  level = function(_, e, who)
    local max = Plain(SafeCall(GetMaxPlayerLevel), "number")
    return ((max and e.lvl == max) and L.LEVEL_MAX or L.LEVEL):format(who, e.lvl or 0)
  end,
}

function H:Format(e)
  local who = self.ClassColorName(e.who, e.cls)
  local format = FormatKind[e.k]
  local text = format and format(self, e, who) or tostring(e.k)
  if e.by and e.by ~= e.who then text = text .. " |cff888888(" .. L.WITNESSED:format(e.by) .. ")|r" end
  if e.test then text = "|cff888888[" .. L.TEST .. "]|r " .. text end
  return text
end

function H:ShouldPrint(e)
  local s = self:Settings()
  if not s.chat then return false end
  if s.chatAll or e.test then return true end
  if e.k == "gear" then return (e.q or 0) >= 4 end
  return e.k == "boss" or e.k == "loot" or e.k == "level"
end

function H:Announce(e)
  if not self:ShouldPrint(e) then return end
  if e.item and not Plain(e.link, "string") and not self:ItemCached(e.item) then
    if C_Item and C_Item.RequestLoadItemDataByID then SafeCall(C_Item.RequestLoadItemDataByID, e.item) end
    C_Timer.After(2, function() GS:Call(function() self:Print(self:Format(e)) end) end)
    return
  end
  self:Print(self:Format(e))
end

function H.TimeText(t) return date(L.FMT_TIME, t) end

function H:AddTests()
  local me = GS:PlayerKey() or "Me"
  local _, cls = SafeCall(UnitClass, "player")
  local lvl = Plain(SafeCall(UnitLevel, "player"), "number") or 1
  local t = GS:Now()
  local base = { who = me, cls = Plain(cls, "string"), lvl = lvl }
  local i = 0
  local function E(k, fields)
    i = i + 1
    local e = { k = k, t = t, id = "TEST#" .. i .. "#" .. t }
    for kk, v in pairs(base) do e[kk] = v end
    for kk, v in pairs(fields) do e[kk] = v end
    return e
  end
  local list = {
    E("gear", { item = 6084, il = 30, oil = 18, q = 3, slot = 15 }),
    E("loot", { item = 869, q = 4 }),
    E("boss", { enc = 1144, boss = "Edwin VanCleef", inst = "Die Todesminen", first = true }),
    E("boss", { enc = 663, boss = "Lucifron", inst = "Geschmolzener Kern", grp = true, n = 12, raid = true }),
    E("quest", { qid = 166, title = "The Defias Brotherhood", tag = "dungeon", ql = 22 }),
    E("level", { lvl = 60 }),
  }
  local n = 0
  for _, e in ipairs(list) do if self:Add(e, "test") then n = n + 1 end end
  return n
end

local function S() return H:Settings() end
local function Setter(key, after)
  return function(v)
    S()[key] = v
    if after then after(v) end
    H:Refresh()
  end
end
local function Getter(key) return function() return S()[key] end end
local function ShareOff() return not S().share end
local function ChatOff() return not S().chat end

H.options = {
  { type = "header", label = L.OPT_SHARE_H },
  { type = "toggle", label = L.OPT_SHARE, tooltip = L.OPT_SHARE_TIP, get = Getter("share"),
    set = Setter("share", function(v) if v then H:OutboxPump() end end) },
  { type = "range", label = L.OPT_CAP, tooltip = L.OPT_CAP_TIP, min = 1, max = 20, step = 1,
    get = Getter("shareCap"), set = Setter("shareCap"), disabled = ShareOff },
  { type = "header", label = L.OPT_CHAT_H },
  { type = "toggle", label = L.OPT_CHAT, tooltip = L.OPT_CHAT_TIP, get = Getter("chat"), set = Setter("chat") },
  { type = "toggle", label = L.OPT_CHAT_ALL, get = Getter("chatAll"), set = Setter("chatAll"), disabled = ChatOff },
  { type = "toggle", label = L.OPT_ECHO, get = Getter("echoOwn"), set = Setter("echoOwn"), disabled = ChatOff },
  { type = "header", label = L.OPT_RULES_H },
  { type = "range", label = L.OPT_GAIN, tooltip = L.OPT_GAIN_TIP, min = 1, max = 40, step = 1, get = Getter("minGain"), set = Setter("minGain") },
  { type = "range", label = L.OPT_GEARQ, tooltip = L.OPT_QUALITY_TIP, min = 2, max = 4, step = 1,
    get = Getter("minGearQuality"), set = Setter("minGearQuality") },
  { type = "range", label = L.OPT_LOOTQ, tooltip = L.OPT_QUALITY_TIP, min = 3, max = 5, step = 1,
    get = Getter("minLootQuality"), set = Setter("minLootQuality") },
  { type = "range", label = L.OPT_LEVEL, tooltip = L.OPT_LEVEL_TIP, min = 0, max = 20, step = 1, get = Getter("levelStep"), set = Setter("levelStep") },
  { type = "range", label = L.OPT_RED, tooltip = L.OPT_RED_TIP, min = 0, max = 10, step = 1,
    get = Getter("questRedLevels"), set = Setter("questRedLevels") },
  { type = "header", label = L.OPT_LOG_H },
  { type = "toggle", label = L.OPT_ONLY_HL, tooltip = L.OPT_ONLY_HL_TIP, get = Getter("logOnlyHighlights"), set = Setter("logOnlyHighlights") },
  { type = "button", label = L.OPT_OPEN_LOG, func = function() H:Open() end },
  { type = "button", label = L.OPT_TEST, tooltip = L.OPT_TEST_TIP, func = function() H:Print(L.TEST_ADDED:format(H:AddTests())) end },
  { type = "button", label = L.OPT_CLEARTEST, func = function() H:Print(L.TEST_CLEARED:format(H:ClearTests())) end },
  { type = "text", label = L.OPT_DIAG, tooltip = L.OPT_DIAG_TIP, lines = function() return H:DiagLines() end },
}

local function SortedAssignments(t)
  local list = {}
  for k, v in pairs(t) do list[#list + 1] = k .. "=" .. tostring(v) end
  table.sort(list)
  return list
end

local function JoinedOr(list, sep, empty) return list[1] and table.concat(list, sep) or empty end

local function OutboxLine(outbox)
  local waiting = {}
  for id, o in pairs(outbox) do
    waiting[#waiting + 1] = ("%s (tries %s%s)"):format(id, tostring(o.tries or 0), o.hold and ", resting" or "")
  end
  return "outbox: " .. JoinedOr(waiting, "; ", "-")
end

local function AddLastEventLines(out, last)
  local evs = {}
  for ev in pairs(last or {}) do evs[#evs + 1] = ev end
  table.sort(evs)
  for _, ev in ipairs(evs) do out[#out + 1] = ("last %s: %s"):format(ev, (last[ev]:gsub("|", "||"))) end
end

function H:DiagLines()
  local out = { "Highlights  guild: " .. tostring(self:GuildKey()) }
  for gkey, g in pairs(self.db.guilds) do out[#out + 1] = ("  log %s: %d entries"):format(gkey, #g.events) end
  out[#out + 1] = OutboxLine(self.cdb.outbox)
  out[#out + 1] = "shared this hour: " .. #self.cdb.shareLog .. "  ·  activity entries (this character): " .. #self.cdb.activity
  out[#out + 1] = "settings: " .. table.concat(SortedAssignments(self:Settings()), ", ")
  local d = self.db.diag
  out[#out + 1] = ("secret loot lines: %d, bad messages: %d"):format(d.secretLoot or 0, d.badMsg or 0)
  out[#out + 1] = "events seen: " .. JoinedOr(SortedAssignments(d.seen or {}), ", ", "-")
  AddLastEventLines(out, d.last)
  return out
end

function H:Open()
  self:ShowWindow()
end

function H:OverviewStatus()
  if not self.db then return end
  local events = self:Log()
  local waiting = 0
  for _ in pairs(self.cdb.outbox) do waiting = waiting + 1 end
  local s = L.OV_STATUS:format(#events, self:Settings().share and L.ON or L.OFF)
  if waiting > 0 then s = s .. " · " .. L.OV_WAITING:format(waiting) end
  return s
end

function H:OverviewRecent(n)
  if not self.db then return end
  local events, out = self:Log(), {}
  for i = math.max(1, #events - n + 1), #events do
    local e = events[i]
    out[#out + 1] = "|cff888888" .. self.TimeText(e.t) .. "|r  " .. self:Format(e)
  end
  return out
end
