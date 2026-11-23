local ADDON, ns = ...
local GS = RavenquillExpedition
local L = ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

local RETIRED_SETTINGS = { shareCap = 8, minGain = 8, minGearQuality = 3, minLootQuality = 4, levelStep = 10, questRedLevels = 0 }
local defaults = { share = true, chat = false, chatAll = false, echoOwn = true, logOnlyHighlights = false }
for k, v in pairs(RETIRED_SETTINGS) do defaults[k] = v end

local H = GS:NewModule("Highlights", {
  addon = ADDON, api = 2, slash = "hl", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Note_01", openFirst = true,
  sv = "RavenquillExpeditionHighlightsDB", svChar = "RavenquillExpeditionHighlightsCharDB", dbVersion = 3,
  locale = ns.Locales,
  defaults = defaults,
  charDefaults = { everEquipped = {}, ownedEpics = {}, kills = {}, quests = {}, outbox = {}, shareLog = {}, activity = {} },
})
ns.H = H

H.LOOT_QUALITY = 4
H.LEVEL_STEP = 10
H.SHARE_CAP = 8

H.MAX_EVENTS = 1500
H.MAX_AGE = 90 * 86400
H.FUTURE_SLACK = 300
H.LOOT_DEDUPE = 300
H.BOSS_SAME = 1200
H.RUN_SAME = 3600
H.GROUP_NAMES_MAX = 120
H.OUTBOX_MAX_AGE = 2 * 86400
H.RECV_PER_HOUR = 30
H.MAX_PER_WHO = 300

H.migrations = {
  [2] = function(db)
    if type(db.settings) ~= "table" then db.settings = {} end
    if db.settings.questRedLevels == 4 and not db.settings.migratedV2 then db.settings.questRedLevels = 0 end
    db.settings.migratedV2 = true
  end,
  [3] = function(db)
    if type(db.settings) ~= "table" then db.settings = {} end
    db.settings.chat = false
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

function H:Settings() return self.db and self.db.settings or self.defaults end

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

H.NOTABLE_QUEST_TAGS = { special = true, legend = true, raid = true }

local function Valid(e)
  if type(e) ~= "table" or not H.KINDS[e.k] then return false end
  if e.k == "quest" and not H.NOTABLE_QUEST_TAGS[e.tag] then return false end
  if type(e.id) ~= "string" or type(e.who) ~= "string" or e.who == "" then return false end
  if type(e.t) ~= "number" then return false end
  return true
end

function H.MaxLevel() return Plain(SafeCall(GetMaxPlayerLevel), "number") end

local function FirstFact(self, e)
  local kind = self.KINDS[e.k]
  return kind and kind.fact and kind.fact(e) or nil
end

function H:KeepFirst(gkey, e)
  local fact = not e.test and FirstFact(self, e)
  if not fact then return end
  local g = self.db.guilds[gkey]
  if type(g.firsts) ~= "table" then g.firsts = {} end
  if not g.firsts[fact] or e.t < g.firsts[fact] then g.firsts[fact] = e.t end
end

function H:FirstKnown(fact)
  local g = self.db.guilds[self:GuildKey()]
  local t = g and type(g.firsts) == "table" and g.firsts[fact] or nil
  for _, e in ipairs((self:Log())) do
    if not e.test and FirstFact(self, e) == fact and (not t or e.t < t) then t = e.t end
  end
  return t
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

local lootHeard = {}

function H.People(e)
  local out = { e.who }
  for _, key in ipairs(e.with or {}) do out[#out + 1] = key end
  return out
end

local function Listed(list, key)
  for _, x in ipairs(list or {}) do if x == key then return true end end
  return false
end

local function NewToMe(self, e)
  local me = GS:PlayerKey()
  if e.who == me or Listed(e.with, me) then return false end
  return not (e.grp and self:WasThere(e))
end

local function Arriving(self, e)
  if NewToMe(self, e) then e.unseen = true end
  if e.grp then self:Supersede(e) end
end

local function OnHeard(_, e)
  if e.k == "loot" then lootHeard[e.who .. "#" .. tostring(e.item)] = e.t end
end

local function OnSeenHere(self, e, source, opts)
  if source == "witness" or self:Settings().echoOwn then self:Announce(e) end
  if opts.localOnly or not self:Share(e, opts) then e.held = true end
end

local SOURCES = {
  wire = { heard = true, live = true, after = function(self, e) OnHeard(self, e); self:Announce(e) end },
  relay = { heard = true, after = OnHeard },
  self = { live = true, after = OnSeenHere },
  witness = { after = OnSeenHere },
  test = { test = true },
}

local function OutsideKeptWindow(self, t)
  local now = GS:Now()
  return t > now + self.FUTURE_SLACK or t < now - self.MAX_AGE
end

local function Admissible(self, events, idx, e, s)
  local stale = self.KINDS[e.k].stale
  if s.heard and stale and stale(self, e) then return false end
  if s.heard and not idx[e.id] then Arriving(self, e) end
  return not (idx[e.id] or IsRecentLootRepeat(self, events, e) or self:Reported(e))
end

function H:Add(e, source, opts)
  if not self.db or not Valid(e) or OutsideKeptWindow(self, e.t) then return end
  local gkey = self:GuildKey()
  local events, idx = self:Log(gkey)
  local s = SOURCES[source]
  if not Admissible(self, events, idx, e, s) then return end
  if s.test then e.test = true end
  InsertByTime(events, e)
  idx[e.id] = e
  self:KeepAttunement(gkey, e)
  self:KeepFirst(gkey, e)
  if s.heard then self:CapWho(events, idx, e.who) end
  self:Prune(gkey)
  if s.after then s.after(self, e, source, opts or {}) end
  if s.live then self:Chime(e) end
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

local recv = {}
function H:Admit(sender, now)
  local list = recv[sender]
  if not list then list = {}; recv[sender] = list end
  GS.PruneTimes(list, 3600, now)
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

function H:LootReportedByOthers(e)
  local t = lootHeard[e.who .. "#" .. tostring(e.item)]
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

function H.QualityName(q)
  local name = Plain(_G["ITEM_QUALITY" .. tostring(q) .. "_DESC"], "string") or tostring(q)
  local hex = QUALITY_HEX[q]
  return hex and ("|cff" .. hex .. name .. "|r") or name
end

function H.ItemInfo(item) return SafeCall((C_Item and C_Item.GetItemInfo) or GetItemInfo, item) end

function H.RequestItemData(id)
  if C_Item and C_Item.RequestLoadItemDataByID then SafeCall(C_Item.RequestLoadItemDataByID, id) end
end

function H:ItemCached(id)
  local name = id and Plain(self.ItemInfo(id), "string")
  return name ~= nil
end

local waitingItems, itemRefreshArmed = false, false

function H:ItemText(e)
  if Plain(e.link, "string") then return e.link end
  local id = e.item
  if not id then return "?" end
  local name, link = self.ItemInfo(id)
  link = Plain(link, "string")
  if link then return link end
  self.RequestItemData(id)
  waitingItems = true
  local hex = QUALITY_HEX[e.q or 1] or "ffffff"
  return ("|cff%s[%s]|r"):format(hex, Plain(name, "string") or ("item:" .. id))
end

function H:CachedItem(id)
  local name, _, _, il = self.ItemInfo(id)
  name = Plain(name, "string")
  if not name then
    self.RequestItemData(id)
    waitingItems = true
  end
  return name, Plain(il, "number")
end

H:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(self)
  if not (self.db and waitingItems) or itemRefreshArmed then return end
  itemRefreshArmed = true
  C_Timer.After(0.5, function()
    itemRefreshArmed = false
    GS:Call(function() waitingItems = false; self:Refresh() end)
  end)
end)

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
  out[#out + 1] = self:CatchupLine()
  out[#out + 1] = "events seen: " .. JoinedOr(SortedAssignments(d.seen or {}), ", ", "-")
  AddLastEventLines(out, d.last)
  return out
end

H.openLabel, H.openInHeader = L.OPEN_LABEL, true
function H:OverviewDiagnostics() return self:DiagLines() end

function H:Open() self:ShowWindow() end

function H:OverviewStatus()
  if not self.db then return end
  local events, unseen, waiting = self:ShownLog(), self:NewSinceLastLook(), 0
  for _ in pairs(self.cdb.outbox) do waiting = waiting + 1 end
  local s = L.OV_STATUS:format(#events, self:Settings().share and L.ON or L.OFF)
  if unseen > 0 then s = L.OV_NEW:format(unseen) .. " · " .. s end
  if waiting > 0 then s = s .. " · " .. L.OV_WAITING:format(waiting) end
  return s
end

