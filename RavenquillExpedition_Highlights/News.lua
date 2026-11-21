local ADDON, ns = ...

local News = {}
ns.News = News

News.RANK = { raid = 100, epic = 90, run = 80, boss = 75, levelmax = 70, mount = 56, gear = 52, level = 46, quest = 40,
  rep = 38, skill = 34, pvp = 32, duel = 24 }
News.LEVEL_RANK = { [50] = 66, [40] = 64 }
News.BRIEF_MAX = 5
News.QUEST_LIST_MAX = 3
News.PAPER_HEX = { [2] = "1f6b12", [3] = "0b5cad", [4] = "7b2cbf", [5] = "b35900" }

local SLOT_NOUN = { [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
  [9] = "wrist", [10] = "hands", [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket", [15] = "back",
  [16] = "weapon", [17] = "offhand", [18] = "ranged" }
local EQUIP_NOUN = { INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
  INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands", INVTYPE_WAIST = "waist",
  INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "ring", INVTYPE_TRINKET = "trinket",
  INVTYPE_WEAPON = "weapon", INVTYPE_2HWEAPON = "weapon", INVTYPE_WEAPONMAINHAND = "weapon",
  INVTYPE_WEAPONOFFHAND = "weapon", INVTYPE_SHIELD = "shield", INVTYPE_HOLDABLE = "offhand", INVTYPE_RANGED = "ranged",
  INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "relic", INVTYPE_BAG = "bag" }

News.NAMES = {
  alchemy = { enUS = "Alchemy", deDE = "Alchemie" },
  blacksmithing = { enUS = "Blacksmithing", deDE = "Schmiedekunst" },
  enchanting = { enUS = "Enchanting", deDE = "Verzauberkunst" },
  engineering = { enUS = "Engineering", deDE = "Ingenieurskunst" },
  herbalism = { enUS = "Herbalism", deDE = "Kräuterkunde" },
  leatherworking = { enUS = "Leatherworking", deDE = "Lederverarbeitung" },
  mining = { enUS = "Mining", deDE = "Bergbau" },
  skinning = { enUS = "Skinning", deDE = "Kürschnerei" },
  tailoring = { enUS = "Tailoring", deDE = "Schneiderei" },
  cooking = { enUS = "Cooking", deDE = "Kochkunst" },
  firstaid = { enUS = "First Aid", deDE = "Erste Hilfe" },
  fishing = { enUS = "Fishing", deDE = "Angeln" },
  warsong = { enUS = "Warsong Gulch", deDE = "Kriegshymnenschlucht" },
  arathi = { enUS = "Arathi Basin", deDE = "Arathibecken" },
  alterac = { enUS = "Alterac Valley", deDE = "Alteractal" },
}

local nameKey
function News.LocalName(name, locale)
  if not nameKey then
    nameKey = {}
    for key, names in pairs(News.NAMES) do
      for _, n in pairs(names) do nameKey[n] = key end
    end
  end
  local key = name and nameKey[name]
  return key and News.NAMES[key][locale] or name
end

function News.Fill(text, vars)
  local missing = false
  local out = text:gsub("{([?!]?)([%w_]+)}", function(mode, key)
    local v = vars[key]
    if mode == "?" then missing = missing or v == nil return "" end
    if mode == "!" then missing = missing or v ~= nil return "" end
    if v == nil then missing = true return "" end
    return tostring(v)
  end)
  if missing then return nil end
  return out
end

function News.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

function News.Pick(list, seed, vars)
  local fits = {}
  for _, text in ipairs(list or {}) do
    local out = News.Fill(text, vars)
    if out then fits[#fits + 1] = out end
  end
  if not fits[1] then return nil end
  return (fits[News.Hash(seed) % #fits + 1]:gsub("^%l", string.upper))
end

function News.Count(n, T) return T.NUMBERS[n] or tostring(n) end
local Count = News.Count

local function Join(list, T)
  if #list < 2 then return list[1] end
  return table.concat(list, T.COMMA, 1, #list - 1) .. T.AND .. list[#list]
end

local function Own(e) return e.k .. "|" .. tostring(e.id) end
local function ItemKey(e) return "item|" .. e.who .. "|" .. tostring(e.item) end

local GROUP_KEY = {
  boss = function(e)
    if e.raid then return "raid|" .. tostring(e.inst) end
    return "boss|" .. e.who .. "|" .. tostring(e.inst)
  end,
  loot = ItemKey,
  gear = ItemKey,
  quest = function(e) return "quest|" .. e.who end,
  level = function(e) return "level|" .. tostring(e.lvl) end,
}

local function IsEpic(e) return e.k == "loot" or (e.q or 0) >= 4 end
local function ItemKind(g)
  for _, e in ipairs(g.entries) do if IsEpic(e) then return "epic" end end
  return "gear"
end

local GROUP_KIND = {
  boss = function(g) return g.first.raid and "raid" or "boss" end,
  loot = ItemKind,
  gear = ItemKind,
  level = function(g, ctx) return g.first.lvl == ctx.maxLevel and "levelmax" or "level" end,
}

local function Earlier(a, b)
  if a.t ~= b.t then return a.t < b.t end
  return tostring(a.id) < tostring(b.id)
end

local function Finish(g, ctx)
  table.sort(g.entries, Earlier)
  g.first, g.last = g.entries[1], g.entries[#g.entries]
  g.id, g.t = tostring(g.first.id), g.first.t
  local kindOf = GROUP_KIND[g.first.k]
  g.kind = kindOf and kindOf(g, ctx) or g.first.k
  g.rank = (g.kind == "level" and News.LEVEL_RANK[g.first.lvl]) or News.RANK[g.kind] or 0
end

local function Ahead(a, b)
  if a.rank ~= b.rank then return a.rank > b.rank end
  if #a.entries ~= #b.entries then return #a.entries > #b.entries end
  return Earlier(a.first, b.first)
end

function News.Groups(entries, ctx)
  local byKey, groups = {}, {}
  for _, e in ipairs(entries) do
    local keyOf = GROUP_KEY[e.k]
    local key = keyOf and keyOf(e) or Own(e)
    local g = byKey[key]
    if not g then
      g = { key = key, entries = {} }
      byKey[key], groups[#groups + 1] = g, g
    end
    g.entries[#g.entries + 1] = e
  end
  for _, g in ipairs(groups) do Finish(g, ctx) end
  table.sort(groups, Ahead)
  return groups
end

function News.Days(entries, dayOf)
  local byDay, days = {}, {}
  for _, e in ipairs(entries) do
    local day = dayOf(e.t)
    local rec = byDay[day]
    if not rec then
      rec = { day = day, entries = {} }
      byDay[day], days[#days + 1] = rec, rec
    end
    rec.entries[#rec.entries + 1] = e
  end
  table.sort(days, function(a, b) return a.day < b.day end)
  for i, rec in ipairs(days) do rec.no = i end
  return days
end

local function Kills(v, g, ctx, T)
  local first, last, n = g.first, g.last, #g.entries
  v.inst, v.boss, v.time = first.inst, first.boss, ctx.time(last.t)
  if first.first then v.first = "" end
  local guildies = 0
  for _, e in ipairs(g.entries) do guildies = math.max(guildies, e.grp and e.n or 0) end
  if guildies >= 2 then v.grp = Count(guildies, T) end
  if n < 2 then return end
  v.n, v.lastboss, v.start = Count(n, T), last.boss, ctx.time(first.t)
  local min = math.floor((last.t - first.t) / 60 + 0.5)
  if min >= 1 then v.min = min end
end

local function Run(v, g, _, T)
  local e = g.first
  v.inst, v.lastboss = e.inst, e.boss
  if e.first then v.first = "" end
  if (e.n or 1) >= 2 then v.n = Count(e.n, T) end
  if e.n and e.nf and e.nf >= 2 and e.nf < e.n then v.nf = Count(e.nf, T) end
end

local function OfKind(g, k)
  for _, e in ipairs(g.entries) do if e.k == k then return e end end
end

local function TopQuality(g)
  local q = 0
  for _, e in ipairs(g.entries) do q = math.max(q, e.q or (e.k == "loot" and 4 or 0)) end
  return q
end

local function Phrase(T, q, nounKey, case)
  local noun = T.NOUNS[nounKey] or T.NOUNS.item
  local adj = T.QUALITY[q] or T.QUALITY[4]
  return News.Fill(T.ARTICLE[noun.g][case], { adj = adj, noun = noun.n })
end

local function ItemName(name, q)
  return ("|cff%s[%s]|r"):format(News.PAPER_HEX[q] or "2b2118", name)
end

local function ItemNoun(gear, facts)
  return SLOT_NOUN[gear and gear.slot or 0] or EQUIP_NOUN[facts.equipLoc or ""] or "item"
end

local function ItemLevels(v, gear, facts)
  v.il = gear and gear.il or facts.il
  v.oldil = gear and gear.oil
  if v.il and v.oldil and v.il > v.oldil then v.gain = v.il - v.oldil end
end

local LOOT_FLAG = { craft = "crafted", bag = "received" }

local function Item(v, g, ctx, T)
  local gear, loot = OfKind(g, "gear"), OfKind(g, "loot")
  local facts = ctx.item(g.first.item) or {}
  local q, noun = TopQuality(g), ItemNoun(gear, facts)
  v.thing, v.thingnom = Phrase(T, q, noun, "acc"), Phrase(T, q, noun, "nom")
  v.item, v.icon = facts.name and ItemName(facts.name, q), facts.icon
  ItemLevels(v, gear, facts)
  local flag = loot and LOOT_FLAG[loot.src or ""]
  if flag then v[flag] = "" end
  if gear then v.worn = "" end
end

local function People(v, g, ctx, T)
  local names, seen = {}, {}
  for _, e in ipairs(g.entries) do
    if not seen[e.who] then seen[e.who] = true; names[#names + 1] = e.who end
  end
  if #names < 2 then return end
  v.name, v.names, v.n = nil, Join(names, T), Count(#names, T)
  v.lead, v.leadtime = g.first.who, ctx.time(g.first.t)
  v.lastname, v.lasttime = g.last.who, ctx.time(g.last.t)
end

local function Level(v, g, ctx, T)
  v.lvl = g.first.lvl
  local left = ctx.maxLevel and v.lvl and ctx.maxLevel - v.lvl
  if left and left >= 2 then v.left = left end
  People(v, g, ctx, T)
end

local function Quoted(e, T) return News.Fill(T.QUOTE, { title = e.title or ("#" .. tostring(e.qid)) }) end

local function Quest(v, g, _, T)
  local titles = {}
  for _, e in ipairs(g.entries) do
    titles[#titles + 1] = Quoted(e, T)
    if e.tag == "legend" then v.legend = "" end
  end
  v.quest = titles[1]
  if #titles < 2 then return end
  v.n, v.lastquest = Count(#titles, T), titles[#titles]
  local shown = {}
  for i = 1, math.min(#titles, News.QUEST_LIST_MAX) do shown[i] = titles[i] end
  if #titles > #shown then shown[#shown + 1] = News.Fill(T.MORE_QUESTS, { n = Count(#titles - #shown, T) }) end
  v.quests = Join(shown, T)
end

local function Mount(v, g, _, T)
  v.mount = g.first.epic and T.MOUNT_EPIC or T.MOUNT
  if g.first.epic then v.epic = "" end
end

local function Rep(v, g, ctx)
  local e = g.first
  v.fac, v.standing = e.fac, ctx.standing(e.st)
  if e.st == 8 then v.exalted = "" end
end

local function Skill(v, g, _, T)
  local e = g.first
  v.skill, v.rank = News.LocalName(e.skill, T.LOCALE), e.rank
  if (e.rank or 0) >= 300 then v.top = "" end
end

local function Pvp(v, g, _, T)
  local e = g.first
  if e.pk == "rank" then v.prank = e.pr else v.bg = News.LocalName(e.name, T.LOCALE) end
end

local VARS = {
  raid = Kills, boss = Kills, run = Run, epic = Item, gear = Item, levelmax = Level, level = Level, quest = Quest,
  mount = Mount, rep = Rep, skill = Skill, pvp = Pvp,
  duel = function(v, g) v.foe = g.first.foe end,
}

function News.Vars(g, ctx, T)
  local v = { name = g.first.who, time = ctx.time(g.first.t), clvl = g.first.lvl }
  local fill = VARS[g.kind]
  if fill then fill(v, g, ctx, T) end
  return v
end

local function Slot(texts, g, slot, v) return News.Pick(texts[slot], g.id .. "|" .. slot, v) end

function News.Story(g, T, ctx)
  local v = News.Vars(g, ctx, T)
  local texts = T.KINDS[g.kind] or {}
  local story = { kind = g.kind, k = g.first.k, id = g.id, time = v.time, icon = v.icon,
    kicker = g.first.test and T.TEST_KICKER or Slot(texts, g, "kicker", v),
    head = Slot(texts, g, "head", v) or "", dek = Slot(texts, g, "dek", v), caption = Slot(texts, g, "caption", v),
    body = {} }
  story.body[#story.body + 1] = Slot(texts, g, "body", v)
  story.body[#story.body + 1] = Slot(texts, g, "more", v)
  return story
end

function News.Brief(g, T, ctx)
  local v = News.Vars(g, ctx, T)
  return { time = ctx.time(g.first.t), text = Slot(T.KINDS[g.kind] or {}, g, "brief", v) or "" }
end

function News.Issue(day, T, ctx)
  local groups = News.Groups(day.entries, ctx)
  local issue = { day = day.day, no = day.no, t = day.entries[1] and day.entries[1].t, brief = {}, more = 0 }
  issue.lead = groups[1] and News.Story(groups[1], T, ctx)
  issue.second = groups[2] and News.Story(groups[2], T, ctx)
  for i = 3, #groups do
    if #issue.brief < News.BRIEF_MAX then issue.brief[#issue.brief + 1] = News.Brief(groups[i], T, ctx)
    else issue.more = issue.more + 1 end
  end
  return issue
end
