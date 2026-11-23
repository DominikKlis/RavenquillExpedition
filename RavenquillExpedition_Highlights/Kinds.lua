local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L = ns.H, ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.QUEST_TAGS = { elite = "TAG_ELITE", group = "TAG_GROUP", dungeon = "TAG_DUNGEON", raid = "TAG_RAID", red = "TAG_RED",
  hard = "TAG_HARD", special = "TAG_SPECIAL", legend = "TAG_LEGEND" }

local function Gold(text) return "|cffffd100" .. text .. "|r" end
local function NonEmpty(s, fallback) return (s and s ~= "") and s or fallback end

H.KINDS = {
  gear = {
    code = "g", legacy = true, chat = true, chatMinQuality = 4, icon = "INV_Chest_Chain_05",
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
      local text = (e.src == "bag" and L.LOOT_GOT) or (e.src == "craft" and L.LOOT_CRAFTED) or L.LOOT
      return text:format(self:ItemText(e) .. count)
    end,
  },
  boss = {
    code = "b", chat = true, icon = "INV_Misc_Bone_HumanSkull_01", hidden = function(e) return e.raid end,
    format = function(_, e)
      local boss, inst = Gold(NonEmpty(e.boss, L.A_BOSS)), NonEmpty(e.inst, L.AN_INSTANCE)
      if e.grp and (e.n or 1) > 1 then return L.BOSS_GROUP:format(boss, inst, e.n - 1) end
      return (e.first and L.BOSS_FIRST or L.BOSS):format(boss, inst)
    end,
  },
  run = {
    code = "d", chat = true, icon = "INV_Misc_Key_03",
    format = function(_, e)
      local inst, bosses = Gold(NonEmpty(e.inst, L.AN_INSTANCE)), (e.n or 1) == 1 and L.ONE_BOSS or L.N_BOSSES:format(e.n)
      if e.first then return L.RUN_FIRST:format(inst, bosses) .. (NonEmpty(e.boss) and L.RUN_LAST:format(e.boss) or "") end
      return L.RUN_NEW:format(inst, bosses, e.nf or 1)
    end,
  },
  quest = {
    code = "q", legacy = true, chat = false, icon = "INV_Misc_Note_01",
    hidden = function(e) return H.ATTUNEMENT_QUESTS[e.qid] ~= nil end,
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
  mount = {
    code = "m", chat = true, icon = "Ability_Mount_RidingHorse",
    format = function(_, e) return e.epic and L.MOUNT_EPIC or L.MOUNT end,
  },
  rep = {
    code = "f", chat = true, icon = "INV_Scroll_03",
    format = function(_, e)
      local standing = Plain(_G["FACTION_STANDING_LABEL" .. tostring(e.st)], "string") or tostring(e.st)
      return L.REP:format(standing, Gold(NonEmpty(e.fac, "?")))
    end,
  },
  skill = {
    code = "s", chat = false, icon = "Trade_BlackSmithing",
    format = function(_, e) return L.SKILL:format(Gold(NonEmpty(ns.News.LocalName(e.skill, L.LOCALE), "?")), e.rank or 0) end,
  },
  pvp = {
    code = "p", chat = true, icon = "INV_BannerPVP_02",
    format = function(_, e)
      if e.pk == "rank" then return L.PVP_RANK:format(e.pr or 0, NonEmpty(e.name, "?")) end
      return L.PVP_WIN:format(Gold(NonEmpty(ns.News.LocalName(e.name, L.LOCALE), "?")))
    end,
  },
  duel = {
    code = "u", chat = true, icon = "Ability_Dualwield",
    format = function(_, e) return L.DUEL:format(NonEmpty(e.foe, "?")) end,
  },
  attune = {
    code = "a", chat = false, paper = false, icon = "INV_Misc_Key_14",
    format = function(_, e) return L.ATTUNE:format(Gold(L["RAID_" .. tostring(e.raid)])) end,
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
    E("gear", { item = 6084, il = 30, oil = 18, q = 3, slot = 15 }),
    E("loot", { item = 869, q = 4 }),
    E("run", { inst = L.TEST_DEADMINES, boss = "Edwin VanCleef", n = 6, nf = 6, first = true }),
    E("boss", { enc = 663, boss = "Lucifron", inst = L.TEST_MOLTEN_CORE, grp = true, n = 12, raid = true }),
    E("quest", { qid = 7848, title = L.TEST_QUEST, tag = "special", ql = 60 }),
    E("mount", { epic = true }),
    E("rep", { st = 8, fac = L.TEST_FACTION }),
    E("skill", { skill = L.TEST_SKILL, rank = 300 }),
    E("pvp", { pk = "win", name = L.TEST_BATTLEGROUND }),
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
  { k = "boss", title = "RULE_WORLD_BOSS", text = "HOW_WORLD_BOSS" },
  { k = "run", title = "RULE_RUN", text = "HOW_RUN" },
  { k = "level", title = "RULE_LEVEL", text = "HOW_LEVEL", args = { H.LEVEL_STEP } },
  { k = "mount", title = "RULE_MOUNT", text = "HOW_MOUNT" },
  { k = "rep", title = "RULE_REP", text = "HOW_REP" },
  { k = "skill", title = "RULE_SKILL", text = "HOW_SKILL" },
  { k = "pvp", title = "RULE_PVP", text = "HOW_PVP" },
  { k = "duel", title = "RULE_DUEL", text = "HOW_DUEL" },
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
