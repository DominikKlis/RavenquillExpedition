local ADDON, ns = ...

local News = {}
ns.News = News

News.RANK = { raid = 100, epic = 90, run = 80, boss = 75, levelmax = 70, mount = 56, gear = 52, level = 46, quest = 40,
  rep = 38, skill = 34, pvp = 32, duel = 24 }
News.LEVEL_RANK = { [50] = 66, [40] = 64 }
News.BRIEF_MAX, News.QUEST_LIST_MAX, News.SAME_OUTING = 8, 3, 300
News.PAPER_HEX = { [2] = "1f6b12", [3] = "0b5cad", [4] = "7b2cbf", [5] = "b35900" }
News.SUBJECT, News.PERSONAL = { name = true, names = true }, { clvl = true, lo = true, hi = true }
News.KEY = { raid = "n boss", boss = "n boss", run = "n nf first lastboss", epic = "il item", gear = "il item",
  quest = "n rest", rep = "standing", skill = "rank", level = "left", levelmax = "people" }
News.FACT_OF = { thingnom = "thing", gain = "oldil", quests = "quest rest", lastquest = "quest", before = "boss middle",
  lead = "order time", leadtime = "order time", lastname = "order time", lasttime = "order time", soon = "worn",
  weartime = "worn", clvl = "levels", lo = "levels", hi = "levels" }

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
  leatherworking = { enUS = "Leatherworking", deDE = "Lederverarbeitung" }, fishing = { enUS = "Fishing", deDE = "Angeln" },
  warsong = { enUS = "Warsong Gulch", deDE = "Kriegshymnenschlucht" }, cooking = { enUS = "Cooking", deDE = "Kochkunst" },
  blacksmithing = { enUS = "Blacksmithing", deDE = "Schmiedekunst" }, alchemy = { enUS = "Alchemy", deDE = "Alchemie" },
  engineering = { enUS = "Engineering", deDE = "Ingenieurskunst" }, firstaid = { enUS = "First Aid", deDE = "Erste Hilfe" },
  enchanting = { enUS = "Enchanting", deDE = "Verzauberkunst" }, alterac = { enUS = "Alterac Valley", deDE = "Alteractal" },
  herbalism = { enUS = "Herbalism", deDE = "Kräuterkunde" }, arathi = { enUS = "Arathi Basin", deDE = "Arathibecken" },
  tailoring = { enUS = "Tailoring", deDE = "Schneiderei" }, skinning = { enUS = "Skinning", deDE = "Kürschnerei" },
  mining = { enUS = "Mining", deDE = "Bergbau" },
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

do
  local parsed = {}
  local function Parse(text)
    local p = parsed[text]
    if p then return p end
    p = { printed = {}, required = {} }
    for mode, key in text:gmatch("{([?!]?)([%w_]+)}") do
      if mode == "" then p.printed[#p.printed + 1] = key elseif mode == "?" then p.required[#p.required + 1] = key end
    end
    parsed[text] = p
    return p
  end

  local function AddFacts(out, key)
    if News.SUBJECT[key] then return end
    for fact in (News.FACT_OF[key] or key):gmatch("%S+") do out[#out + 1] = fact end
  end

  function News.Facts(text, vars)
    local p, out = Parse(text), {}
    for _, key in ipairs(p.printed) do AddFacts(out, key) end
    for _, key in ipairs(p.required) do if vars[key] == "" then AddFacts(out, key) end end
    return out
  end

  function News.Sentences(text)
    local out = {}
    for s in text:gmatch("[^%.!?]+[%.!?]*") do
      s = s:match("^%s*(.-)%s*$")
      if s ~= "" then out[#out + 1] = s end
    end
    return out
  end

  function News.Desk(T) return { T = T, said = {} } end

  local function Marks(text, out, vars, desk, st)
    local marks, who = News.Sentences(out), vars.name or vars.names or ""
    marks[#marks + 1] = text
    for _, motif in ipairs(desk.T.ONCE or {}) do if out:find(motif, 1, true) then marks[#marks + 1] = motif end end
    for _, key in ipairs(st and Parse(text).printed or {}) do
      if News.PERSONAL[key] then marks[#marks + 1] = who .. "|" .. key .. "|" .. tostring(vars[key]) end
    end
    return marks
  end

  local function Seen(said, marks)
    for _, m in ipairs(marks) do if said[m] then return true end end
    return false
  end

  local function Covers(facts, set)
    for _, f in ipairs(facts) do if set[f] then return true end end
    return false
  end

  local function Fresh(facts, marks, st, desk)
    if st and Covers(facts, st.used) then return false end
    return not (desk and Seen(desk.said, marks))
  end

  local function Candidates(list, vars, st, desk)
    local fits = {}
    for _, text in ipairs(list or {}) do
      local out = News.Fill(text, vars)
      if out then
        local facts, marks = News.Facts(text, vars), desk and Marks(text, out, vars, desk, st) or {}
        if Fresh(facts, marks, st, desk) then fits[#fits + 1] = { out = out, facts = facts, marks = marks } end
      end
    end
    return fits
  end

  local function Filter(list, keep)
    local out = {}
    for _, c in ipairs(list) do if keep(c) then out[#out + 1] = c end end
    return out[1] and out or list
  end

  local function Choose(fits, seed, st)
    local pool = fits
    if st then
      pool = Filter(pool, function(c) return c.facts[1] ~= nil end)
      pool = Filter(pool, function(c) return Covers(c.facts, st.key) end)
    end
    return pool[News.Hash(seed) % #pool + 1]
  end

  function News.Pick(list, seed, vars, st, desk)
    local fits = Candidates(list, vars, st, desk)
    if not fits[1] then return nil end
    local c = Choose(fits, seed, st)
    if st and not c.facts[1] then
      if st.flavour then return nil end
      st.flavour = true
    end
    if st then for _, f in ipairs(c.facts) do st.used[f] = true end end
    for _, m in ipairs(c.marks) do desk.said[m] = true end
    return (c.out:gsub("^%l", string.upper))
  end
end

local function Fit(list, vars)
  for _, text in ipairs(list or {}) do
    local out = News.Fill(text, vars)
    if out then return out end
  end
end

function News.First(list, vars)
  local out = Fit(list, vars)
  return out and (out:gsub("^%l", string.upper))
end

function News.Count(n, T) return T.NUMBERS[n] or tostring(n) end
local Count = News.Count

function News.Counted(list, n, T) return Fit(list, { n = Count(n, T), one = n == 1 and "" or nil }) end

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

local function AddPeople(people, g)
  for _, e in ipairs(g.entries) do
    if not people[e.who] then people[e.who] = true; people[#people + 1] = e.who end
  end
  return people
end

local function Finish(g, ctx)
  table.sort(g.entries, Earlier)
  g.first, g.last = g.entries[1], g.entries[#g.entries]
  g.id, g.t = tostring(g.first.id), g.first.t
  local kindOf = GROUP_KIND[g.first.k]
  g.kind = kindOf and kindOf(g, ctx) or g.first.k
  g.rank = (g.kind == "level" and News.LEVEL_RANK[g.first.lvl]) or News.RANK[g.kind] or 0
  g.people = g.kind == "raid" and {} or AddPeople({}, g)
end

local function Ahead(a, b)
  if a.rank ~= b.rank then return a.rank > b.rank end
  if #a.people ~= #b.people then return #a.people > #b.people end
  if #a.entries ~= #b.entries then return #a.entries > #b.entries end
  return Earlier(a.first, b.first)
end

local MergeOutings
do
  local function Outing(g) return g.first.k == "run" or (g.first.k == "boss" and not g.first.raid) end
  local function KillCount(g) return g.first.k == "run" and (g.first.n or 1) or #g.entries end

  local function ShareWord(a, b)
    local seen = {}
    for w in (a or ""):gmatch("[%w\128-\255']+") do if #w >= 4 then seen[w:lower()] = true end end
    for w in (b or ""):gmatch("[%w\128-\255']+") do if seen[w:lower()] then return true end end
    return false
  end

  local function SamePlace(a, b)
    local ea, eb = a.last.enc, b.last.enc
    if ea and eb then return ea == eb end
    return (a.first.inst ~= nil and a.first.inst == b.first.inst) or ShareWord(a.last.boss, b.last.boss)
  end

  local function Apart(cluster, g)
    for _, member in ipairs(cluster) do
      for _, who in ipairs(member.people) do if g.people[who] then return false end end
    end
    return true
  end

  local function SameOuting(cluster, g)
    local h = cluster[1]
    return h.first.k == g.first.k and KillCount(h) == KillCount(g) and math.abs(h.last.t - g.last.t) <= News.SAME_OUTING
      and SamePlace(h, g) and Apart(cluster, g)
  end

  local function ClusterFor(clusters, g)
    for _, c in ipairs(clusters) do if SameOuting(c, g) then return c end end
  end

  local function Settle(reports)
    local votes, people = {}, {}
    for _, r in ipairs(reports) do votes[r.first.inst or ""] = (votes[r.first.inst or ""] or 0) + 1 end
    table.sort(reports, function(a, b)
      local va, vb = votes[a.first.inst or ""], votes[b.first.inst or ""]
      if va ~= vb then return va > vb end
      return Earlier(a.first, b.first)
    end)
    for _, r in ipairs(reports) do AddPeople(people, r) end
    reports[1].reports, reports[1].people = reports, people
    return reports[1]
  end

  MergeOutings = function(groups)
    local out, clusters = {}, {}
    for _, g in ipairs(groups) do
      local c = Outing(g) and ClusterFor(clusters, g)
      if c then
        c[#c + 1] = g
      else
        out[#out + 1] = g
        if Outing(g) then clusters[#clusters + 1] = { g, slot = #out } end
      end
    end
    for _, c in ipairs(clusters) do if c[2] then out[c.slot] = Settle(c) end end
    return out
  end
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
  groups = MergeOutings(groups)
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

local function AllFirst(g)
  for _, r in ipairs(g.reports or { g }) do
    for _, e in ipairs(r.entries) do if not e.first then return false end end
  end
  return true
end

local function Levels(v, g)
  if not g.reports then return end
  local lo, hi
  for _, r in ipairs(g.reports) do
    local l = r.first.lvl
    if l then lo, hi = math.min(lo or l, l), math.max(hi or l, l) end
  end
  v.clvl = lo == hi and lo or nil
  if lo ~= hi then v.lo, v.hi = lo, hi end
end

local function BossList(g, from, to, T)
  local names = {}
  for i = from, to do
    local boss = g.entries[i].boss
    if not boss then return nil end
    names[#names + 1] = boss
  end
  return Join(names, T)
end

local function Guildies(g, T)
  local n = 0
  for _, e in ipairs(g.entries) do n = math.max(n, e.grp and e.n or 0) end
  if n >= 2 then return Count(n, T) end
end

local function Kills(v, g, ctx, T)
  local first, last, n = g.first, g.last, #g.entries
  v.inst, v.boss, v.time, v.grp = first.inst, first.boss, ctx.time(last.t), Guildies(g, T)
  if AllFirst(g) then v.first = "" end
  Levels(v, g)
  if n < 2 then return end
  v.n, v.lastboss, v.start = Count(n, T), last.boss, ctx.time(first.t)
  v.before = BossList(g, 1, n - 1, T)
  if n >= 3 then v.middle = BossList(g, 2, n - 1, T) end
  local min = math.floor((last.t - first.t) / 60 + 0.5)
  if min >= 1 then v.min = min end
end

local function SameNf(g)
  local nf = g.first.nf
  for _, r in ipairs(g.reports or {}) do if r.first.nf ~= nf then return nil end end
  return nf
end

local function Run(v, g, _, T)
  local e, nf = g.first, SameNf(g)
  v.inst, v.lastboss = e.inst, e.boss
  if AllFirst(g) then v.first = "" end
  if (e.n or 1) >= 2 then v.n = Count(e.n, T) end
  if e.n and nf and nf >= 2 and nf < e.n then v.nf = Count(nf, T) end
  Levels(v, g)
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

local function Worn(v, loot, gear, ctx)
  local after = gear.t - loot.t
  if after >= 0 and after < 60 then v.soon = "" elseif after >= 60 then v.weartime = ctx.time(gear.t) end
end

local function Item(v, g, ctx, T)
  local gear, loot = OfKind(g, "gear"), OfKind(g, "loot")
  local facts = ctx.item(g.first.item) or {}
  local q, noun = TopQuality(g), ItemNoun(gear, facts)
  v.thing, v.thingnom = Phrase(T, q, noun, "acc"), Phrase(T, q, noun, "nom")
  v.item, v.icon = facts.name and ItemName(facts.name, q), facts.icon
  ItemLevels(v, gear, facts)
  if loot then v[LOOT_FLAG[loot.src or ""] or "looted"] = "" end
  if gear then v.worn = "" end
  if loot and gear then Worn(v, loot, gear, ctx) end
end

local function Level(v, g, ctx)
  v.lvl = g.first.lvl
  local left = ctx.maxLevel and v.lvl and ctx.maxLevel - v.lvl
  if left and left >= 2 then v.left = left end
  if #g.people < 2 then return end
  v.lead, v.leadtime = g.first.who, ctx.time(g.first.t)
  v.lastname, v.lasttime = g.last.who, ctx.time(g.last.t)
end

local function Quoted(e, T) return News.Fill(T.QUOTE, { title = e.title or ("#" .. tostring(e.qid)) }) end

local function Listed(titles, from, T)
  local shown, last = {}, math.min(#titles, from + News.QUEST_LIST_MAX - 1)
  for i = from, last do shown[#shown + 1] = titles[i] end
  if #titles > last then shown[#shown + 1] = News.Counted(T.MORE_QUESTS, #titles - last, T) end
  return Join(shown, T)
end

local function Quest(v, g, _, T)
  local titles = {}
  for _, e in ipairs(g.entries) do
    titles[#titles + 1] = Quoted(e, T)
    if e.tag == "legend" then v.legend = "" end
  end
  v.quest = titles[1]
  if #titles < 2 then return end
  v.n, v.lastquest = Count(#titles, T), titles[#titles]
  v.quests, v.rest = Listed(titles, 1, T), Listed(titles, 2, T)
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
  local people = g.people or {}
  if #people >= 2 then v.name, v.names, v.people = nil, Join(people, T), Count(#people, T) end
  local fill = VARS[g.kind]
  if fill then fill(v, g, ctx, T) end
  return v
end

local function KeySet(kind)
  local set = {}
  for f in (News.KEY[kind] or ""):gmatch("%S+") do set[f] = true end
  return set
end

local function Paragraph(Slot, st)
  local plain = st.flavour
  local body, detail = Slot("body", st), Slot("detail", st)
  if st.flavour and not plain then body, detail = detail, body end
  if body and detail then return body .. " " .. detail end
  return body or detail
end

function News.Story(g, T, ctx, desk)
  local v, st = News.Vars(g, ctx, T), { used = {}, key = {} }
  local texts = T.KINDS[g.kind] or {}
  local function Slot(slot, state) return News.Pick(texts[slot], g.id .. "|" .. slot, v, state, desk) end
  local story = { kind = g.kind, k = g.first.k, id = g.id, time = v.time, icon = v.icon, body = {} }
  story.kicker = g.first.test and T.TEST_KICKER or Slot("kicker")
  story.head = Slot("head", { used = st.used, key = {} }) or ""
  st.key = KeySet(g.kind)
  story.dek = Slot("dek", st)
  story.body[#story.body + 1] = Paragraph(Slot, st)
  story.body[#story.body + 1] = Slot("more", st)
  story.caption = Slot("caption")
  return story
end

function News.Brief(g, T, ctx)
  local v = News.Vars(g, ctx, T)
  return { time = ctx.time(g.first.t), text = News.First((T.KINDS[g.kind] or {}).brief, v) or "" }
end

local function ByTime(a, b) return Earlier(a.first, b.first) end

function News.Issue(day, T, ctx)
  local groups, desk = News.Groups(day.entries, ctx), News.Desk(T)
  local issue = { day = day.day, no = day.no, t = day.entries[1] and day.entries[1].t, brief = {}, more = 0 }
  issue.lead = groups[1] and News.Story(groups[1], T, ctx, desk)
  issue.second = groups[2] and News.Story(groups[2], T, ctx, desk)
  local shown = {}
  for i = 3, #groups do
    if #shown < News.BRIEF_MAX then shown[#shown + 1] = groups[i] else issue.more = issue.more + 1 end
  end
  table.sort(shown, ByTime)
  for i, g in ipairs(shown) do issue.brief[i] = News.Brief(g, T, ctx) end
  return issue
end
