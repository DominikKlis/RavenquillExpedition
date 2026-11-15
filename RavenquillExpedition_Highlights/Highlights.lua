-- Ravenquill Expedition: Highlights – the log store, formatting, settings and /rq hl.
-- Detectors.lua finds YOUR cool moments (and epic loot of guildies in your group),
-- Wire.lua shares them over the core's GUILD lane, LogWindow.lua shows the log.
local ADDON, ns = ...
local GS = RavenquillExpedition
local L = ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

local H = GS:NewModule("Highlights", { addon = ADDON, slash = "hl", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Note_01" })
ns.H = H

H.MAX_EVENTS = 1500           -- per guild
H.MAX_AGE = 90 * 86400        -- older entries are pruned
H.FUTURE_SLACK = 300          -- reject entries stamped further in the future (clock skew)
H.LOOT_DEDUPE = 300           -- the same loot of the same person within 5 min is one entry
H.BOSS_SAME = 1200            -- reports of the same encounter within 20 min are the same kill
H.OUTBOX_MAX_AGE = 2 * 86400  -- own entries not delivered within 2 days are no longer sent

H.DEFAULTS = {
  share = true,         -- send own highlights to the guild
  shareCap = 8,         -- at most this many shared per hour; more stay local
  chat = true,          -- print highlights in the chat frame (only the big ones unless chatAll)
  chatAll = false,      -- also gear upgrades and quests in chat (the window always has everything)
  echoOwn = true,       -- print own highlights too (shows that detection works)
  minGain = 8,          -- item levels for a "big upgrade" ...
  minGearQuality = 3,   -- ... of a rare or better item (or any first epic in a slot)
  minLootQuality = 4,   -- epic
  levelStep = 10,       -- log level 10, 20, ... (and the max level)
  questRedLevels = 0,   -- > 0: quests this many levels above you also count as hard (off: catches delivery quests)
  logOnlyHighlights = false, -- the log window shows everything (user 2026-11-14); this hides the plain activity
}
H.KINDS = { gear = true, loot = true, boss = true, quest = true, level = true }

local function Print(...) GS.Print(L.TITLE, ...) end
H.Print = Print

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------
local function Table(t) return type(t) == "table" and t or {} end

function H:OnLoad()
  local db = Table(RavenquillExpeditionHighlightsDB)
  RavenquillExpeditionHighlightsDB = db
  db.v = 2
  db.settings = Table(db.settings)
  for k, v in pairs(self.DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
  if db.settings.questRedLevels == 4 and not db.settings.migratedV2 then db.settings.questRedLevels = 0 end -- review #3
  db.settings.migratedV2 = true
  db.guilds = Table(db.guilds)
  db.diag = Table(db.diag)
  self.db = db

  local cdb = Table(RavenquillExpeditionHighlightsCharDB)
  RavenquillExpeditionHighlightsCharDB = cdb
  for _, k in ipairs({ "everEquipped", "ownedEpics", "kills", "quests", "outbox", "shareLog", "activity" }) do cdb[k] = Table(cdb[k]) end
  cdb.seq = tonumber(cdb.seq) or 0
  cdb.installedAt = cdb.installedAt or time()
  self.cdb = cdb

  self.idIndex = {} -- [guildKey] = { [id] = event } (rebuilt, not saved)
end

function H:Settings() return self.db and self.db.settings or self.DEFAULTS end

-- The current guild's log key. The last known key is kept per character, so entries made while
-- GetGuildInfo is still empty after login don't land in the "-" (no guild) bucket.
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

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------
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

-- Add an entry.
--   source "self": own entry, shared (opts.group + opts.rank: a group event that one elected member reports)
--   source "witness": a guildie's loot seen in my group, shared as a group event
--   source "wire": received; "test": local only. opts.localOnly: never shared.
-- Returns the stored entry, or nil if it was rejected or already known.
function H:Add(e, source, opts)
  if not self.db or not Valid(e) then return end
  opts = opts or {}
  local now = GS:Now()
  if e.t > now + self.FUTURE_SLACK or e.t < now - self.MAX_AGE then return end
  local gkey = self:GuildKey()
  local events, idx = self:Log(gkey)
  if idx[e.id] then return end
  if e.k == "loot" then
    for i = #events, 1, -1 do
      local o = events[i]
      if o.t < e.t - self.LOOT_DEDUPE then break end
      if o.k == "loot" and o.who == e.who and o.item == e.item and math.abs(o.t - e.t) <= self.LOOT_DEDUPE then return end
    end
  end
  if source == "test" then e.test = true end
  local pos = #events + 1 -- sorted by time (almost always at the end)
  while pos > 1 and events[pos - 1].t > e.t do pos = pos - 1 end
  table.insert(events, pos, e)
  idx[e.id] = e
  self:Prune(gkey)

  if source == "wire" then
    if e.k == "loot" then self.lootHeard[e.who .. "#" .. tostring(e.item)] = e.t end
    if e.k == "boss" and e.grp then self:Supersede(e) end
    self:Announce(e)
  elseif source == "self" or source == "witness" then
    if source == "witness" or self:Settings().echoOwn then self:Announce(e) end
    if not opts.localOnly and gkey ~= "-" then self:Share(e, opts) end
  end
  if self.RefreshSoon then self:RefreshSoon() elseif self.Refresh then self:Refresh() end
  return e
end

function H:Prune(gkey)
  local events, idx = self:Log(gkey)
  local cutoff = GS:Now() - self.MAX_AGE
  while events[1] and (#events > self.MAX_EVENTS or events[1].t < cutoff) do
    local e = table.remove(events, 1)
    idx[e.id] = nil
  end
end

-- Someone else reported the raid kill we were holding back: theirs replaces ours (if ours wasn't sent).
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

-- Everything else this character does (user 2026-11-14: "show everything, not just highlights"):
-- all loot, every quest, every kill, every level, every new item worn. Kept per character, never sent
-- (the guild lane can't carry it – Forever drops heavy senders). The log window merges it with the highlights.
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
  if self.RefreshSoon then self:RefreshSoon() end
  return e
end

-- Loot reports heard on the wire (also the ones the loot dedupe dropped): [who#item] = t
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
  if self.Refresh then self:Refresh() end
  return n
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
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

-- A clickable item link: the stored one, the client's own (when cached), or a plain coloured [item:ID].
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

function H:Format(e)
  local who = self.ClassColorName(e.who, e.cls)
  local text
  if e.k == "gear" then
    local item = self:ItemText(e)
    local gain = (e.il and e.oil) and (e.il - e.oil) or nil
    if gain and gain > 0 and (e.q or 0) < 4 then text = L.GEAR:format(who, item, gain)
    elseif (e.q or 0) >= 4 then text = L.GEAR_EPIC:format(who, item)
    else text = L.GEAR_FILL:format(who, item) end
  elseif e.k == "loot" then
    text = (e.src == "bag" and L.LOOT_GOT or L.LOOT):format(who, self:ItemText(e) .. ((e.n or 1) > 1 and ("x" .. e.n) or ""))
  elseif e.k == "boss" then
    local boss = "|cffffd100" .. ((e.boss and e.boss ~= "") and e.boss or L.A_BOSS) .. "|r"
    local inst = (e.inst and e.inst ~= "") and e.inst or L.AN_INSTANCE
    if e.grp and (e.n or 1) > 1 then text = L.BOSS_GROUP:format(who, e.n - 1, boss, inst)
    else text = (e.first and L.BOSS_FIRST or L.BOSS):format(who, boss, inst) end
  elseif e.k == "quest" then
    local title = "|cffffd100" .. (e.title or ("#" .. tostring(e.qid))) .. "|r"
    if e.act and not e.tag then text = L.QUEST_PLAIN:format(who, title)
    else text = L.QUEST:format(who, L[QUEST_TAGS[e.tag] or "TAG_HARD"], title) end
  elseif e.k == "level" then
    local max = Plain(SafeCall(GetMaxPlayerLevel), "number")
    text = ((max and e.lvl == max) and L.LEVEL_MAX or L.LEVEL):format(who, e.lvl or 0)
  else
    text = tostring(e.k)
  end
  if e.by and e.by ~= e.who then text = text .. " |cff888888(" .. L.WITNESSED:format(e.by) .. ")|r" end
  if e.test then text = "|cff888888[" .. L.TEST .. "]|r " .. text end
  return text
end

-- Chat shows the big moments; gear and quests only with chatAll (the window always shows everything).
function H:ShouldPrint(e)
  local s = self:Settings()
  if not s.chat then return false end
  if s.chatAll or e.test then return true end
  if e.k == "gear" then return (e.q or 0) >= 4 end
  return e.k == "boss" or e.k == "loot" or e.k == "level"
end

-- Print to chat; a received item line waits up to 2 s for the item's name (a chat line can't be updated later).
function H:Announce(e)
  if not self:ShouldPrint(e) then return end
  if e.item and not Plain(e.link, "string") and not self:ItemCached(e.item) then
    if C_Item and C_Item.RequestLoadItemDataByID then SafeCall(C_Item.RequestLoadItemDataByID, e.item) end
    C_Timer.After(2, function() GS:Call(function() Print(self:Format(e)) end) end)
    return
  end
  Print(self:Format(e))
end

function H.TimeText(t)
  if GetLocale() == "deDE" then return date("%d.%m. %H:%M", t) end
  return date("%m/%d %H:%M", t)
end

---------------------------------------------------------------------------
-- Test entries (/rq hl test): one of each kind, local only
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Options (drawn by the core's overview window; user decision 2026-11-14: options live in the UI)
---------------------------------------------------------------------------
local function S() return H:Settings() end
local function Setter(key, after)
  return function(v)
    S()[key] = v
    if after then after(v) end
    if H.Refresh then H:Refresh() end
  end
end
local function Getter(key) return function() return S()[key] end end
local function ShareOff() return not S().share end
local function ChatOff() return not S().chat end

H.options = {
  { type = "header", label = L.OPT_SHARE_H },
  { type = "toggle", label = L.OPT_SHARE, tooltip = L.OPT_SHARE_TIP, get = Getter("share"),
    set = Setter("share", function(v) if v and H.OutboxPump then H:OutboxPump() end end) },
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
  { type = "button", label = L.OPT_TEST, tooltip = L.OPT_TEST_TIP, func = function() Print(L.TEST_ADDED:format(H:AddTests())) end },
  { type = "button", label = L.OPT_CLEARTEST, func = function() Print(L.TEST_CLEARED:format(H:ClearTests())) end },
  { type = "text", label = L.OPT_DIAG, tooltip = L.OPT_DIAG_TIP, lines = function() return H:DiagLines() end },
}

-- Everything needed to debug detection and sharing, for the copy box.
function H:DiagLines()
  local out = { "Highlights  guild: " .. tostring(self:GuildKey()) }
  for gkey, g in pairs(self.db.guilds) do out[#out + 1] = ("  log %s: %d entries"):format(gkey, #g.events) end
  local waiting = {}
  for id, o in pairs(self.cdb.outbox) do
    waiting[#waiting + 1] = ("%s (tries %s%s)"):format(id, tostring(o.tries or 0), o.hold and ", resting" or "")
  end
  out[#out + 1] = "outbox: " .. (waiting[1] and table.concat(waiting, "; ") or "-")
  out[#out + 1] = "shared this hour: " .. #self.cdb.shareLog .. "  ·  activity entries (this character): " .. #self.cdb.activity
  local keys = {}
  for k, v in pairs(self:Settings()) do keys[#keys + 1] = k .. "=" .. tostring(v) end
  table.sort(keys)
  out[#out + 1] = "settings: " .. table.concat(keys, ", ")
  local d = self.db.diag
  out[#out + 1] = ("secret loot lines: %d, bad messages: %d"):format(d.secretLoot or 0, d.badMsg or 0)
  local seen = {}
  for ev, n in pairs(d.seen or {}) do seen[#seen + 1] = ev .. "=" .. n end
  table.sort(seen)
  out[#out + 1] = "events seen: " .. (seen[1] and table.concat(seen, ", ") or "-")
  local evs = {}
  for ev in pairs(d.last or {}) do evs[#evs + 1] = ev end
  table.sort(evs)
  for _, ev in ipairs(evs) do out[#out + 1] = ("last %s: %s"):format(ev, (d.last[ev]:gsub("|", "||"))) end
  return out
end

---------------------------------------------------------------------------
-- Overview window hooks (core Overview.lua)
---------------------------------------------------------------------------
function H:Open()
  if self.ShowWindow then self:ShowWindow() elseif self.ToggleWindow then self:ToggleWindow() end
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
