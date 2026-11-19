local ADDON, ns = ...
local GS = RavenquillExpedition
local L = ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

local H = GS:NewModule("Highlights", {
  addon = ADDON, api = 2, slash = "hl", title = L.TITLE, icon = "Interface\\Icons\\INV_Misc_Note_01",
  sv = "RavenquillExpeditionHighlightsDB", svChar = "RavenquillExpeditionHighlightsCharDB", dbVersion = 3,
  locale = ns.Locales,
  defaults = {
    share = true,
    shareCap = 8,
    chat = false,
    chatAll = false,
    echoOwn = true,
    minGain = 8,
    minGearQuality = 3,
    minLootQuality = 4,
    levelStep = 10,
    questRedLevels = 0,
    logOnlyHighlights = false,
  },
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

local lootHeard = {}

local function OnHeard(self, e)
  if e.k == "loot" then lootHeard[e.who .. "#" .. tostring(e.item)] = e.t end
  if e.k == "boss" and e.grp then self:Supersede(e) end
end

local function OnSeenHere(self, e, source, opts, gkey)
  if source == "witness" or self:Settings().echoOwn then self:Announce(e) end
  if not opts.localOnly and gkey ~= "-" then self:Share(e, opts) end
end

local SOURCES = {
  wire = { heard = true, after = function(self, e) OnHeard(self, e); self:Announce(e) end },
  relay = { heard = true, after = OnHeard },
  self = { after = OnSeenHere },
  witness = { after = OnSeenHere },
  test = { test = true },
}

local function OutsideKeptWindow(self, t)
  local now = GS:Now()
  return t > now + self.FUTURE_SLACK or t < now - self.MAX_AGE
end

function H:Add(e, source, opts)
  if not self.db or not Valid(e) then return end
  if OutsideKeptWindow(self, e.t) then return end
  local gkey = self:GuildKey()
  local events, idx = self:Log(gkey)
  if idx[e.id] or IsRecentLootRepeat(self, events, e) then return end
  local s = SOURCES[source]
  if s.test then e.test = true end
  InsertByTime(events, e)
  idx[e.id] = e
  if s.heard then self:CapWho(events, idx, e.who) end
  self:Prune(gkey)
  if s.after then s.after(self, e, source, opts or {}, gkey) end
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

function H:EmptyText()
  local s = self:Settings()
  return L.EMPTY:format(self.QualityName(s.minLootQuality), self.QualityName(s.minGearQuality), s.minGain)
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

H:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(self)
  if not (self.db and waitingItems) or itemRefreshArmed then return end
  itemRefreshArmed = true
  C_Timer.After(0.5, function()
    itemRefreshArmed = false
    GS:Call(function() waitingItems = false; self:Refresh() end)
  end)
end)

H.QUEST_TAGS = { elite = "TAG_ELITE", group = "TAG_GROUP", dungeon = "TAG_DUNGEON", raid = "TAG_RAID", red = "TAG_RED",
  hard = "TAG_HARD" }

local function Gold(text) return "|cffffd100" .. text .. "|r" end
local function NonEmpty(s, fallback) return (s and s ~= "") and s or fallback end

H.KINDS = {
  gear = {
    code = "g", chat = true, chatMinQuality = 4, icon = "INV_Chest_Chain_05",
    format = function(self, e)
      local item = self:ItemText(e)
      local quality = e.q or 0
      local gain = (e.il and e.oil) and (e.il - e.oil) or nil
      if gain and gain > 0 and quality < 4 then return L.GEAR:format(item, gain) end
      if quality >= 4 then return L.GEAR_EPIC:format(item) end
      return L.GEAR_FILL:format(item)
    end,
  },
  loot = {
    code = "l", chat = true, icon = "INV_Misc_Bag_08",
    format = function(self, e)
      local count = (e.n or 1) > 1 and ("x" .. e.n) or ""
      return (e.src == "bag" and L.LOOT_GOT or L.LOOT):format(self:ItemText(e) .. count)
    end,
  },
  boss = {
    code = "b", chat = true, icon = "INV_Misc_Bone_HumanSkull_01",
    format = function(_, e)
      local boss, inst = Gold(NonEmpty(e.boss, L.A_BOSS)), NonEmpty(e.inst, L.AN_INSTANCE)
      if e.grp and (e.n or 1) > 1 then return L.BOSS_GROUP:format(boss, inst, e.n - 1) end
      return (e.first and L.BOSS_FIRST or L.BOSS):format(boss, inst)
    end,
  },
  run = {
    code = "d", chat = true, icon = "INV_Misc_Key_03",
    format = function(_, e)
      local inst = Gold(NonEmpty(e.inst, L.AN_INSTANCE))
      if e.first then return L.RUN_FIRST:format(inst, e.n or 1) end
      return L.RUN_NEW:format(inst, e.nf or 1, e.n or 1)
    end,
  },
  quest = {
    code = "q", chat = false, icon = "INV_Misc_Note_01",
    format = function(_, e)
      local title = Gold(e.title or ("#" .. tostring(e.qid)))
      if e.act and not e.tag then return L.QUEST_PLAIN:format(title) end
      return L.QUEST:format(title, L[H.QUEST_TAGS[e.tag] or H.QUEST_TAGS.hard])
    end,
  },
  level = {
    code = "v", chat = true, icon = "Spell_Holy_InnerFire",
    format = function(_, e)
      local max = Plain(SafeCall(GetMaxPlayerLevel), "number")
      return ((max and e.lvl == max) and L.LEVEL_MAX or L.LEVEL):format(e.lvl or 0)
    end,
  },
}

local function Icon(name) return name and ("|TInterface\\Icons\\%s:14:14|t "):format(name) or "" end

function H:Format(e)
  local kind = self.KINDS[e.k]
  local text = kind and kind.format(self, e) or tostring(e.k)
  text = Icon(kind and kind.icon) .. self.ClassColorName(e.who, e.cls) .. "  ·  " .. text
  if e.by and e.by ~= e.who then text = text .. " |cff888888(" .. L.WITNESSED:format(e.by) .. ")|r" end
  if e.test then text = "|cff888888[" .. L.TEST .. "]|r " .. text end
  return text
end

function H:ShouldPrint(e)
  local s = self:Settings()
  if not s.chat then return false end
  if s.chatAll or e.test then return true end
  local kind = self.KINDS[e.k]
  if not (kind and kind.chat) then return false end
  return not kind.chatMinQuality or (e.q or 0) >= kind.chatMinQuality
end

function H:Announce(e)
  if not self:ShouldPrint(e) then return end
  if e.item and not Plain(e.link, "string") and not self:ItemCached(e.item) then
    self.RequestItemData(e.item)
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
    E("run", { inst = L.TEST_DEADMINES, boss = "Edwin VanCleef", n = 6, nf = 6, first = true }),
    E("boss", { enc = 663, boss = "Lucifron", inst = L.TEST_MOLTEN_CORE, grp = true, n = 12, raid = true }),
    E("quest", { qid = 166, title = L.TEST_DEFIAS_QUEST, tag = "dungeon", ql = 22 }),
    E("level", { lvl = 60 }),
  }
  local n = 0
  for _, e in ipairs(list) do if self:Add(e, "test") then n = n + 1 end end
  return n
end

function H:OnOptionChanged(key, v)
  if key == "share" and v then self:OutboxPump() end
  self:Refresh()
end

local QUALITY_VALUE_WIDTH = 96

local function ShareOff() return not H:Settings().share end
local function ChatOff() return not H:Settings().chat end

H:SetOptions({
  { type = "header", label = L.OPT_SHARE_H },
  { type = "toggle", key = "share", label = L.OPT_SHARE, tooltip = L.OPT_SHARE_TIP },
  { type = "range", key = "shareCap", label = L.OPT_CAP, tooltip = L.OPT_CAP_TIP, min = 1, max = 20, step = 1, disabled = ShareOff },
  { type = "header", label = L.OPT_CHAT_H },
  { type = "toggle", key = "chat", label = L.OPT_CHAT, tooltip = L.OPT_CHAT_TIP },
  { type = "toggle", key = "chatAll", label = L.OPT_CHAT_ALL, disabled = ChatOff },
  { type = "toggle", key = "echoOwn", label = L.OPT_ECHO, disabled = ChatOff },
  { type = "header", label = L.OPT_RULES_H },
  { type = "range", key = "minGain", label = L.OPT_GAIN, tooltip = L.OPT_GAIN_TIP, min = 1, max = 40, step = 1 },
  { type = "range", key = "minGearQuality", label = L.OPT_GEARQ, tooltip = L.OPT_QUALITY_TIP, min = 2, max = 4, step = 1,
    display = H.QualityName, valueWidth = QUALITY_VALUE_WIDTH },
  { type = "range", key = "minLootQuality", label = L.OPT_LOOTQ, tooltip = L.OPT_QUALITY_TIP, min = 3, max = 5, step = 1,
    display = H.QualityName, valueWidth = QUALITY_VALUE_WIDTH },
  { type = "range", key = "levelStep", label = L.OPT_LEVEL, tooltip = L.OPT_LEVEL_TIP, min = 0, max = 20, step = 1,
    display = function(v) return v == 0 and L.MAX_ONLY or tostring(v) end, valueWidth = QUALITY_VALUE_WIDTH },
  { type = "range", key = "questRedLevels", label = L.OPT_RED, tooltip = L.OPT_RED_TIP, min = 0, max = 10, step = 1,
    display = function(v) return v == 0 and L.OFF or tostring(v) end, valueWidth = QUALITY_VALUE_WIDTH },
  { type = "header", label = L.OPT_TEST_H },
  { type = "button", label = L.OPT_TEST, tooltip = L.OPT_TEST_TIP, func = function() H:Print(L.TEST_ADDED:format(H:AddTests())) end },
  { type = "button", label = L.OPT_CLEARTEST, func = function() H:Print(L.TEST_CLEARED:format(H:ClearTests())) end },
})

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

H.openLabel = L.OPEN_LABEL
function H:OverviewDiagnostics() return self:DiagLines() end

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
