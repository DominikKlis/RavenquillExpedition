local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L = ns.H, ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.QUEST_TAGS = { elite = "TAG_ELITE", group = "TAG_GROUP", dungeon = "TAG_DUNGEON", raid = "TAG_RAID", red = "TAG_RED",
  hard = "TAG_HARD", special = "TAG_SPECIAL", legend = "TAG_LEGEND" }

local function Gold(text) return "|cffffd100" .. text .. "|r" end
local function Always() return true end
local function NonEmpty(s, fallback) return (s and s ~= "") and s or fallback end

local function SameKill(self, a, b) return a.enc == b.enc and math.abs(a.t - b.t) <= self.BOSS_SAME end
local function KillFact(e) return e.enc and ("e" .. e.enc) or nil end
local function FirstFact(e) if e.what == "level" then return "v" .. tostring(e.lvl) end return KillFact(e) end

local function WithGuild(self, e)
  local who = self.ClassColorName(e.who, e.cls)
  if (e.n or 1) > 1 then return L.WITH_GUILD:format(who, e.n - 1) end
  return who
end

local function SharePeople(a, b)
  local seen = {}
  for _, key in ipairs(H.People(a)) do seen[key] = true end
  for _, key in ipairs(H.People(b)) do if seen[key] then return true end end
  return false
end

H.KINDS = {
  gear = {
    code = "g", legacy = true, chat = true, chatMinQuality = 4, icon = "INV_Chest_Chain_05", hidden = Always,
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
    code = "l", chat = true, icon = "INV_Misc_Bag_08", hidden = function(e) return e.src == "bag" end,
    format = function(self, e)
      local count = (e.n or 1) > 1 and ("x" .. e.n) or ""
      local text = (e.src == "bag" and L.LOOT_GOT) or (e.src == "craft" and L.LOOT_CRAFTED) or (e.src == "quest" and L.LOOT_QUEST)
        or L.LOOT
      return text:format(self:ItemText(e) .. count)
    end,
  },
  boss = {
    code = "b", chat = true, icon = "INV_Misc_Bone_HumanSkull_01", hidden = function(e) return e.raid end,
    same = SameKill, fact = KillFact,
    format = function(_, e)
      local boss, inst = Gold(NonEmpty(e.boss, L.A_BOSS)), NonEmpty(e.inst, L.AN_INSTANCE)
      if e.grp and (e.n or 1) > 1 then return L.BOSS_GROUP:format(boss, inst, e.n - 1) end
      return (e.first and L.BOSS_FIRST or L.BOSS):format(boss, inst)
    end,
  },
  run = {
    code = "d", legacy = true, chat = true, icon = "INV_Misc_Key_03",
    fold = { into = "group", keep = { "inst" },
      same = function(self, a, b) return a.inst == b.inst and math.abs(a.t - b.t) <= self.RUN_FOLD end },
    format = function(_, e)
      local inst, bosses = Gold(NonEmpty(e.inst, L.AN_INSTANCE)), (e.n or 1) == 1 and L.ONE_BOSS or L.N_BOSSES:format(e.n)
      if e.first then return L.RUN_FIRST:format(inst, bosses) .. (NonEmpty(e.boss) and L.RUN_LAST:format(e.boss) or "") end
      return L.RUN_NEW:format(inst, bosses, e.nf or 1)
    end,
  },
  quest = {
    code = "q", legacy = true, chat = false, icon = "INV_Misc_Note_01", hidden = Always,
    format = function(_, e)
      local title = Gold(e.title or ("#" .. tostring(e.qid)))
      if e.act and not e.tag then return L.QUEST_PLAIN:format(title) end
      return L.QUEST:format(title, L[H.QUEST_TAGS[e.tag] or H.QUEST_TAGS.hard])
    end,
  },
  level = {
    code = "v", chat = true, icon = "Spell_Holy_InnerFire", sound = "level",
    fact = function(e) return e.lvl and e.lvl == H.MaxLevel() and ("v" .. e.lvl) or nil end,
    format = function(_, e)
      local max = Plain(SafeCall(GetMaxPlayerLevel), "number")
      return ((max and e.lvl == max) and L.LEVEL_MAX or L.LEVEL):format(e.lvl or 0)
    end,
  },
  mount = {
    code = "m", chat = true, icon = "Ability_Mount_RidingHorse",
    format = function(_, e) return e.epic and L.MOUNT_EPIC or L.MOUNT end,
  },
  rep = {
    code = "f", chat = true, icon = "INV_Scroll_03", hidden = function(e) return (e.st or 0) < H.REP_MILESTONE end,
    format = function(_, e)
      local standing = Plain(_G["FACTION_STANDING_LABEL" .. tostring(e.st)], "string") or tostring(e.st)
      return L.REP:format(standing, Gold(NonEmpty(e.fac, "?")))
    end,
  },
  skill = {
    code = "s", chat = false, icon = "Trade_BlackSmithing", hidden = function(e) return (e.rank or 0) < H.SKILL_TOP end,
    format = function(_, e) return L.SKILL:format(Gold(NonEmpty(ns.News.LocalName(e.skill, L.LOCALE), "?")), e.rank or 0) end,
  },
  pvp = {
    code = "p", chat = true, icon = "INV_BannerPVP_02", hidden = function(e) return e.pk ~= "rank" end,
    format = function(_, e)
      if e.pk == "rank" then return L.PVP_RANK:format(e.pr or 0, NonEmpty(e.name, "?")) end
      return L.PVP_WIN:format(Gold(NonEmpty(ns.News.LocalName(e.name, L.LOCALE), "?")))
    end,
  },
  duel = {
    code = "u", chat = true, icon = "Ability_Dualwield", sound = "duel",
    format = function(_, e) return L.DUEL:format(NonEmpty(e.foe, "?")) end,
  },
  attune = {
    code = "a", chat = false, icon = "INV_Misc_Key_14", hidden = Always,
    format = function(_, e) return L.ATTUNE:format(Gold(L["RAID_" .. tostring(e.raid)])) end,
  },
  group = {
    code = "o", chat = true, icon = "INV_Misc_Key_03",
    same = function(self, a, b) return a.inst == b.inst and math.abs(a.t - b.t) <= self.RUN_SAME and SharePeople(a, b) end,
    subject = function(self, e) return self:PeopleText(e) end,
    format = function(_, e) return L.GROUP:format(Gold(NonEmpty(e.inst, L.AN_INSTANCE))) end,
  },
  clear = {
    code = "c", chat = true, icon = "INV_Misc_Bone_Skull_02", same = SameKill, subject = WithGuild, fact = KillFact,
    format = function(_, e) return L.CLEAR:format(Gold(NonEmpty(e.inst, L.AN_INSTANCE))) end,
  },
  ready = {
    code = "y", chat = true, icon = "INV_Misc_Key_14",
    format = function(_, e) return L.READY:format(Gold(L["RAID_" .. tostring(e.raid)])) end,
  },
  first = {
    code = "t", chat = true, gold = true, sound = "first", icon = "INV_Crown_01", subject = WithGuild, fact = FirstFact,
    same = function(self, a, b) return a.what == b.what and SameKill(self, a, b) end,
    stale = function(self, e)
      local t = self:FirstKnown(FirstFact(e))
      return t ~= nil and t < e.t - self.BOSS_SAME
    end,
    format = function(_, e)
      if e.what == "level" then return L.FIRST_LEVEL:format(Gold(L.FIRST), e.lvl or 0) end
      return L.FIRST_BOSS:format(Gold(L.FIRST_KILL), Gold(NonEmpty(e.boss, L.A_BOSS)), NonEmpty(e.inst, L.AN_INSTANCE))
    end,
  },
}

H.SOUND_GAP = 10
H.SOUNDS = {
  level = { kit = 888, setting = "soundLevel", when = function(e) return e.lvl ~= nil and e.lvl == H.MaxLevel() end },
  first = { kit = 8959, setting = "soundLevel" },
  duel = { kit = 3175, setting = "soundDuel" },
}

local lastChime = -math.huge
local function Muted(self, sound, e)
  if not sound or (sound.when and not sound.when(e)) or self:Settings()[sound.setting] == false then return true end
  return GS:InInstance() or Plain(SafeCall(InCombatLockdown)) and true or false
end

function H:Chime(e)
  local kind = self.KINDS[e.k]
  local sound = kind and kind.sound and self.SOUNDS[kind.sound]
  if Muted(self, sound, e) then return end
  local now, previous = GetTime(), lastChime
  lastChime = now
  if now - previous >= self.SOUND_GAP then SafeCall(PlaySound, sound.kit) end
end

local function Icon(name) return name and ("|TInterface\\Icons\\%s:14:14|t "):format(name) or "" end

local function MemberName(self, key, cls)
  local member = GS:RosterEntry(key)
  return self.ClassColorName(key, cls or (member and member.class))
end

function H:PeopleText(e)
  local names = { MemberName(self, e.who, e.cls) }
  for _, key in ipairs(e.with or {}) do names[#names + 1] = MemberName(self, key) end
  if #names < 2 then return names[1] end
  return table.concat(names, L.COMMA, 1, #names - 1) .. L.AND .. names[#names]
end

function H:Format(e)
  local kind = self.KINDS[e.k]
  local text = kind and kind.format(self, e) or tostring(e.k)
  local subject = kind and kind.subject and kind.subject(self, e) or self.ClassColorName(e.who, e.cls)
  text = Icon(kind and kind.icon) .. subject .. "  ·  " .. text
  if e.by and e.by ~= e.who then text = text .. " |cff888888(" .. L.WITNESSED:format(e.by) .. ")|r" end
  if e.test then text = "|cff888888[" .. L.TEST .. "]|r " .. text end
  return text
end

function H:ShouldPrint(e)
  local s = self:Settings()
  if not (s.chat and self:Shown(e)) then return false end
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
    E("loot", { item = 869, q = 4 }),
    E("group", { inst = L.TEST_DEADMINES, with = { "Bud Stone" }, grp = true }),
    E("clear", { enc = 672, inst = L.TEST_MOLTEN_CORE, n = 12, grp = true }),
    E("boss", { enc = 1100, boss = "Azuregos", inst = L.TEST_AZSHARA, first = true }),
    E("first", { what = "level", lvl = 60 }),
    E("ready", { raid = "mc" }),
    E("mount", { epic = true }),
    E("rep", { st = 8, fac = L.TEST_FACTION }),
    E("skill", { skill = L.TEST_SKILL, rank = 300 }),
    E("pvp", { pk = "rank", pr = 3, name = L.TEST_PVP_RANK }),
    E("duel", { foe = "Bud Stone" }),
    E("level", { lvl = 60 }),
  }
  local n = 0
  for _, e in ipairs(list) do if self:Add(e, "test") then n = n + 1 end end
  return n
end

function H:AddTestEntries()
  self:Print(L.TEST_ADDED:format(self:AddTests()))
  self:Refresh()
end

function H:OnOptionChanged(key, v)
  if key == "share" and v then self:OutboxPump() end
  self:Refresh()
end

local Q = H.QualityName
H.RULES = {
  { k = "loot", title = "RULE_LOOT", text = "HOW_LOOT", args = { Q(H.LOOT_QUALITY) } },
  { k = "clear", title = "RULE_CLEAR", text = "HOW_CLEAR" },
  { k = "boss", title = "RULE_WORLD_BOSS", text = "HOW_WORLD_BOSS" },
  { k = "group", title = "RULE_GROUP", text = "HOW_GROUP" },
  { k = "level", title = "RULE_LEVEL", text = "HOW_LEVEL", args = { H.LEVEL_STEP } },
  { k = "mount", title = "RULE_MOUNT", text = "HOW_MOUNT" },
  { k = "rep", title = "RULE_REP", text = "HOW_REP" },
  { k = "skill", title = "RULE_SKILL", text = "HOW_SKILL" },
  { k = "pvp", title = "RULE_PVP", text = "HOW_PVP" },
  { k = "duel", title = "RULE_DUEL", text = "HOW_DUEL" },
  { k = "first", title = "RULE_FIRST", text = "HOW_FIRST" },
  { k = "ready", title = "RULE_READY", text = "HOW_READY" },
  { k = "attune", title = "RULE_ATTUNE", text = "HOW_ATTUNE" },
}

local function RuleLine(rule)
  local text = L[rule.text]:format(unpack(rule.args or {}))
  return Icon(H.KINDS[rule.k].icon) .. Gold(L[rule.title] .. ":") .. " " .. text
end

local function ShareOff() return not H:Settings().share end
local function ChatOff() return not H:Settings().chat end

local options = {
  { type = "header", label = L.OPT_SHARE_H },
  { type = "toggle", key = "share", label = L.OPT_SHARE, tooltip = L.OPT_SHARE_TIP },
  { type = "note", label = L.OPT_SHARE_CAP:format(H.SHARE_CAP), disabled = ShareOff },
  { type = "header", label = L.OPT_CHAT_H },
  { type = "toggle", key = "chat", label = L.OPT_CHAT, tooltip = L.OPT_CHAT_TIP },
  { type = "toggle", key = "chatAll", label = L.OPT_CHAT_ALL, disabled = ChatOff },
  { type = "toggle", key = "echoOwn", label = L.OPT_ECHO, disabled = ChatOff },
  { type = "header", label = L.OPT_SOUND_H },
  { type = "toggle", key = "soundLevel", label = L.OPT_SOUND_LEVEL:format(GS:MaxLevel()), tooltip = L.OPT_SOUND_TIP,
    get = function() return H:Settings().soundLevel ~= false end },
  { type = "toggle", key = "soundDuel", label = L.OPT_SOUND_DUEL, tooltip = L.OPT_SOUND_TIP,
    get = function() return H:Settings().soundDuel ~= false end },
  { type = "header", label = L.OPT_RULES_H },
}
for _, rule in ipairs(H.RULES) do options[#options + 1] = { type = "note", label = RuleLine(rule) } end
for _, o in ipairs({
  { type = "note", label = L.HOW_ACTIVITY:format(L.LOG_ONLY_HL) },
  { type = "header", label = L.OPT_TEST_H },
  { type = "button", label = L.OPT_TEST, tooltip = L.OPT_TEST_TIP, func = function() H:AddTestEntries() end },
  { type = "button", label = L.OPT_CLEARTEST, func = function() H:Print(L.TEST_CLEARED:format(H:ClearTests())) end },
}) do options[#options + 1] = o end
H:SetOptions(options)
