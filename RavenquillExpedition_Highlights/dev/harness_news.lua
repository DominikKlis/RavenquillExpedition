local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, At, E, Ctx, Client, sched = NK.Kit, NK.At, NK.E, NK.Ctx, NK.Client, NK.sched
local check = Kit.check
local HL = NK.HL

local reader = Client("Lyra Distelbach")
local ns = reader.ns[HL]
local News, DE, EN = ns.News, ns.NewsLocales.deDE, ns.NewsLocales.enUS

local function DayOf(t) return os.date("%Y-%m-%d", t) end

local function Kinds(groups)
  local out = {}
  for i, g in ipairs(groups) do out[i] = g.kind end
  return table.concat(out, ",")
end

Kit.section("Issues: one per day with entries, numbered in order")
do
  local days = News.Days({
    E("level", "Bodo Kesselring", At(16, 10), { lvl = 20 }),
    E("mount", "Mira Sturmfeder", At(18, 13, 24)),
    E("quest", "Mira Sturmfeder", At(18, 17, 5), { qid = 1, title = "Die Köpfe der Bande", tag = "special" }),
    E("level", "Bodo Kesselring", At(18, 23, 59), { lvl = 30 }),
    E("level", "Tamo Eichengrund", At(19, 0, 1), { lvl = 30 }),
  }, DayOf)
  check(#days == 3 and days[1].day == "2026-11-16" and days[2].day == "2026-11-18" and days[3].day == "2026-11-19",
    "three issues for three days with entries, the empty 17th has none")
  check(days[1].no == 1 and days[2].no == 2 and days[3].no == 3, "issue numbers count the days that have entries")
  check(#days[2].entries == 3 and #days[3].entries == 1, "23:59 belongs to its day, 00:01 opens the next issue")
end

local BIG_DAY = {
  E("quest", "Mira Sturmfeder", At(18, 9), { qid = 11, title = "Die Köpfe der Bande", tag = "special" }),
  E("quest", "Mira Sturmfeder", At(18, 9, 30), { qid = 12, title = "Ein Brief für Sturmwind", tag = "special" }),
  E("gear", "Bodo Kesselring", At(18, 10), { item = 5002, q = 3, il = 41, oil = 30, slot = 11 }),
  E("mount", "Tamo Eichengrund", At(18, 11), { lvl = 40 }),
  E("level", "Lyra Distelbach", At(18, 12), { lvl = 40 }),
  E("level", "Tamo Eichengrund", At(18, 12, 30), { lvl = 40 }),
  E("level", "Mira Sturmfeder", At(18, 13), { lvl = 50 }),
  E("run", "Bodo Kesselring", At(18, 14), { inst = "Zul'Farrak", boss = "Häuptling Ukorz Sandskalp", n = 7, nf = 7, first = true }),
  E("loot", "Lyra Distelbach", At(18, 20), { item = 5001, q = 4 }),
  E("gear", "Lyra Distelbach", At(18, 20, 1), { item = 5001, q = 4, il = 50, oil = 45, slot = 16 }),
  E("boss", "Tamo Eichengrund", At(18, 21, 20), { inst = "Geschmolzener Kern", boss = "Lucifron", raid = true, grp = true, n = 12 }),
  E("boss", "Bodo Kesselring", At(18, 21, 40), { inst = "Geschmolzener Kern", boss = "Magmadar", raid = true, grp = true, n = 14 }),
  E("boss", "Tamo Eichengrund", At(18, 22, 5), { inst = "Geschmolzener Kern", boss = "Gehennas", raid = true, grp = true, n = 13 }),
}

Kit.section("Stories: one per run, raid night, item, quest list and level")
do
  local groups = News.Groups(BIG_DAY, Ctx())
  check(Kinds(groups) == "raid,epic,run,level,level,mount,gear,quest",
    "ranked raid > epic > run > level 50 > level 40 > mount > gear > quest (" .. Kinds(groups) .. ")")
  check(#groups[1].entries == 3, "three raid kills of one instance on one day are one raid story")
  check(#groups[2].entries == 2, "loot and gear of the same item are one story")
  check(groups[4].first.lvl == 50 and #groups[5].entries == 2, "two guildies reaching level 40 share a story")
  check(#groups[8].entries == 2, "two notable quests of one person on one day are one story")
  local raid = News.Vars(groups[1], Ctx(), DE)
  check(raid.n == "drei" and raid.min == 45 and raid.start == "21:20" and raid.time == "22:05" and raid.lastboss == "Gehennas"
    and raid.grp == "14", "raid night: three bosses, 45 minutes from 21:20 to 22:05, last Gehennas, 14 guildies")
  local item = News.Vars(groups[2], Ctx(), DE)
  check(item.thing == "eine epische Waffe" and item.gain == 5 and item.item == "|cff7b2cbf[Klinge der Morgenröte]|r",
    "epic item: a weapon phrase, five levels gained, name in the paper's epic colour")
  local levels = News.Vars(groups[5], Ctx(), DE)
  check(levels.names == "Lyra Distelbach und Tamo Eichengrund" and levels.name == nil and levels.lasttime == "12:30",
    "shared level story names both, in order")
  local quests = News.Vars(groups[8], Ctx(), DE)
  check(quests.n == "zwei" and quests.quests == "„Die Köpfe der Bande“ und „Ein Brief für Sturmwind“", "quest story lists both titles")
  local issue = News.Issue({ day = "2026-11-18", no = 7, entries = BIG_DAY }, DE, Ctx())
  local briefs = math.min(News.BRIEF_MAX, 6)
  check(issue.no == 7 and issue.lead.kind == "raid" and issue.second.kind == "epic" and #issue.brief == briefs
    and issue.more == 6 - briefs, "lead raid, second epic, the other six in the brief box or counted for the chronicle")
  local run
  for _, b in ipairs(issue.brief) do if b.text:find("Zul'Farrak", 1, true) then run = b end end
  check(run and run.time == "14:00" and run.text:find("sieben Bosse", 1, true) ~= nil,
    "briefs carry the time and the facts (" .. tostring(run and run.text) .. ")")
end

local function Flatten(issue)
  local parts = {}
  local function Story(s)
    if not s then return end
    for _, slot in ipairs({ "kicker", "head", "dek", "caption" }) do parts[#parts + 1] = tostring(s[slot]) end
    for _, p in ipairs(s.body) do parts[#parts + 1] = p end
  end
  Story(issue.lead)
  Story(issue.second)
  for _, b in ipairs(issue.brief) do parts[#parts + 1] = b.time .. " " .. b.text end
  return table.concat(parts, "\n")
end

Kit.section("Variants: chosen by entry id, the same for every guildmate")
do
  local mine = Flatten(News.Issue({ day = "2026-11-18", no = 1, entries = BIG_DAY }, DE, Ctx()))
  local other = Client("Bodo Kesselring")
  local theirs = Flatten(other.ns[HL].News.Issue({ day = "2026-11-18", no = 1, entries = BIG_DAY }, other.ns[HL].NewsLocales.deDE, Ctx()))
  check(mine == theirs and #mine > 400, "a second client builds the identical paper from the same entries")
  local heads, n = {}, 0
  for i = 1, 40 do
    local g = News.Groups({ E("level", "Mira Sturmfeder", At(18, 12) + i, { lvl = 30 }) }, Ctx())[1]
    local head = News.Story(g, DE, Ctx()).head
    if not heads[head] then heads[head] = true; n = n + 1 end
  end
  check(n >= 3, "different entries get different headlines (" .. n .. " of 40)")
  local g = News.Groups({ E("level", "Mira Sturmfeder", At(18, 12), { lvl = 30 }) }, Ctx())[1]
  check(News.Story(g, DE, Ctx()).head == News.Story(g, DE, Ctx()).head, "the same entry always gets the same headline")
end

local OUTING = "inst boss lastboss n min start grp first before middle lo hi"
local ITEM = "item thing thingnom il oldil gain crafted received looted worn soon weartime"
local KNOWN = {
  raid = OUTING, boss = OUTING, run = "inst lastboss n nf first lo hi", epic = ITEM, gear = ITEM,
  levelmax = "lvl left lead leadtime lastname lasttime", level = "lvl left lead leadtime lastname lasttime",
  mount = "mount epic", quest = "quest quests rest n lastquest legend", rep = "fac standing exalted", skill = "skill rank top",
  pvp = "bg prank", duel = "foe",
}
local REQUIRED_SLOTS = { "kicker", "head", "dek", "body", "caption", "brief" }

local function KnownSet(kind)
  local set = { name = true, names = true, people = true, time = true, clvl = true }
  for key in KNOWN[kind]:gmatch("%S+") do set[key] = true end
  return set
end

local function RenderAlone(text)
  local vars, unknown = {}, {}
  for mode, key in text:gmatch("{([?!]?)([%w_]+)}") do
    if mode ~= "!" then vars[key] = mode == "?" and "" or "Wert" end
    unknown[#unknown + 1] = key
  end
  return News.Fill(text, vars), unknown
end

local function TemplateProblems(L, label)
  local problems = {}
  for kind in pairs(News.RANK) do
    local texts, known = L.KINDS[kind], KnownSet(kind)
    for _, slot in ipairs(REQUIRED_SLOTS) do
      if not (texts and texts[slot] and texts[slot][1]) then problems[#problems + 1] = label .. " " .. kind .. "." .. slot .. " missing" end
    end
    for slot, list in pairs(texts or {}) do
      for _, text in ipairs(list) do
        local out, keys = RenderAlone(text)
        for _, key in ipairs(keys) do if not known[key] then problems[#problems + 1] = label .. " " .. kind .. "." .. slot .. " {" .. key .. "}" end end
        if not out or out:find("[{}]") then problems[#problems + 1] = label .. " " .. kind .. "." .. slot .. ": " .. text end
      end
    end
  end
  return problems
end

local function SameKeys(a, b)
  for k, v in pairs(a) do
    if b[k] == nil or type(b[k]) ~= type(v) then return k end
    if type(v) == "table" and k ~= "KINDS" and k ~= "ARTICLE" then
      local inner = SameKeys(v, b[k])
      if inner then return k .. "." .. inner end
    end
  end
end

Kit.section("Templates: every variant in both languages renders, no placeholder left")
do
  local problems = TemplateProblems(DE, "deDE")
  for _, p in ipairs(TemplateProblems(EN, "enUS")) do problems[#problems + 1] = p end
  check(#problems == 0, "every kind has every slot, every variant uses known data and fills completely ("
    .. (problems[1] or "none") .. ", " .. #problems .. " problems)")
  local missing = SameKeys(EN, DE) or SameKeys(DE, EN)
  check(missing == nil, "German and English have the same texts and tables (" .. tostring(missing) .. ")")
  local genders = true
  for _, L in ipairs({ DE, EN }) do
    for _, noun in pairs(L.NOUNS) do if not L.ARTICLE[noun.g] then genders = false end end
  end
  check(genders, "every item noun has an article pattern for its gender")
end

local PREPOSITION = { deDE = " für ", enUS = " for " }

local function Renderings(L, text)
  local out, base = {}, {}
  for mode, key in text:gmatch("{([?!]?)([%w_]+)}") do if mode ~= "!" then base[key] = mode == "?" and "" or "Wert" end end
  local nouns = text:find("{thing", 1, true) and L.NOUNS or { item = L.NOUNS.item }
  for _, noun in pairs(nouns) do
    for q = 2, 5 do
      local vars = setmetatable({}, { __index = base })
      vars.thing = News.Fill(L.ARTICLE[noun.g].acc, { adj = L.QUALITY[q], noun = noun.n })
      vars.thingnom = News.Fill(L.ARTICLE[noun.g].nom, { adj = L.QUALITY[q], noun = noun.n })
      out[#out + 1] = News.Fill(text, vars)
    end
  end
  return out
end

local function Doubled(L, word)
  local hits = {}
  for kind, texts in pairs(L.KINDS) do
    for slot, list in pairs(texts) do
      for _, text in ipairs(list) do
        for _, s in ipairs(Renderings(L, text)) do
          for clause in (s .. " "):gmatch("[^%.!?,;:]+") do
            local _, n = (" " .. clause .. " "):gsub(word, "")
            if n > 1 then hits[#hits + 1] = kind .. "." .. slot .. ": " .. s end
          end
        end
      end
    end
  end
  return hits
end

Kit.section("Texts never say 'für ... für' or 'for ... for' in one clause")
do
  check(#Doubled({ KINDS = { x = { head = { "{thingnom} für {name}" } } }, NOUNS = { item = { g = "m", n = "Hut für Regen" } },
    ARTICLE = DE.ARTICLE, QUALITY = DE.QUALITY }, PREPOSITION.deDE) > 0, "the check catches a doubled 'für'")
  local de, en = Doubled(DE, PREPOSITION.deDE), Doubled(EN, PREPOSITION.enUS)
  check(#de == 0, "no German variant, with any item noun, has 'für' twice in a clause (" .. (de[1] or "none") .. ")")
  check(#en == 0, "no English variant, with any item noun, has 'for' twice in a clause (" .. (en[1] or "none") .. ")")
  local g = News.Groups({ E("gear", "Faro Berangias", At(20, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }) }, Ctx())[1]
  check(News.Vars(g, Ctx(), DE).thingnom == "ein seltener Nebenhandgegenstand",
    "an off-hand item is 'ein seltener Nebenhandgegenstand' (" .. tostring(News.Vars(g, Ctx(), DE).thingnom) .. ")")
end

Kit.section("Counts: one more is singular, more than one is plural")
do
  local function More(L, n) return News.Counted and News.Counted(L.MORE_BRIEF, n, L) end
  check(More(DE, 1) == "eine weitere Meldung steht in der Chronik." and More(DE, 2) == "zwei weitere Meldungen stehen in der Chronik."
    and More(EN, 1) == "one more report is in the chronicle." and More(EN, 13) == "13 more reports are in the chronicle.",
    "the line about the chronicle counts in words with the right number (" .. tostring(More(DE, 1)) .. ")")
  local entries = {}
  for i = 1, 4 do entries[i] = E("quest", "Mira Sturmfeder", At(18, 9, i), { qid = i, title = "Auftrag " .. i, tag = "special" }) end
  local quests = News.Vars(News.Groups(entries, Ctx())[1], Ctx(), DE).quests
  check(quests == "„Auftrag 1“, „Auftrag 2“, „Auftrag 3“ und ein weiterer", "one quest past the list is 'ein weiterer' ("
    .. tostring(quests) .. ")")
end

local MINIMAL = {
  raid = { "boss", { raid = true } }, boss = { "boss", {} }, run = { "run", { n = 1, nf = 1 } },
  epic = { "loot", { item = 9999, q = 4 } }, gear = { "gear", { item = 9998, q = 3 } }, levelmax = { "level", { lvl = 60 } },
  level = { "level", { lvl = 59 } }, mount = { "mount", {} }, quest = { "quest", { qid = 7, tag = "special" } },
  rep = { "rep", { st = 6 } }, skill = { "skill", { rank = 150 } }, pvp = { "pvp", { pk = "win" } },
  duel = { "duel", { foe = "Bodo Kesselring" } },
}

Kit.section("Degraded data: every kind still prints a full story")
do
  local bad = {}
  for _, L in ipairs({ DE, EN }) do
    for kind, spec in pairs(MINIMAL) do
      for i = 1, 12 do
        local g = News.Groups({ E(spec[1], "Mira Sturmfeder", At(18, 9) + i, spec[2]) }, Ctx())[1]
        local story, brief = News.Story(g, L, Ctx()), News.Brief(g, L, Ctx())
        local text = table.concat({ story.kicker or "", story.head, story.dek or "", story.caption or "", story.body[1] or "", brief.text }, "|")
        if g.kind ~= kind or not (story.kicker and story.dek and story.caption and story.body[1]) or story.head == ""
          or brief.text == "" or text:find("[{}]") then
          bad[#bad + 1] = kind .. ": " .. text
        end
      end
    end
  end
  check(#bad == 0, "missing instance, boss, title, item and level data fall back to fitting variants (" .. (bad[1] or "none") .. ")")
end

local function Many(make, n)
  local texts = {}
  for i = 1, n or 20 do
    local g = News.Groups(make(i), Ctx())[1]
    local s = News.Story(g, DE, Ctx())
    texts[#texts + 1] = table.concat({ s.head, s.dek or "", s.body[1] or "", s.body[2] or "", News.Brief(g, DE, Ctx()).text }, " | ")
  end
  return table.concat(texts, "\n")
end

Kit.section("Degraded data: an item whose name is not cached, a single kill, a run without a duration")
do
  local uncached = Many(function(i) return { E("loot", "Lyra Distelbach", At(18, 20) + i, { item = 5003, q = 4 }) } end)
  check(not uncached:find("[", 1, true) and uncached:find("ine epische Waffe", 1, true),
    "an item without cached data is written as 'eine epische Waffe', never as an empty name")
  local cached = Many(function(i) return { E("loot", "Lyra Distelbach", At(18, 20) + i, { item = 5001, q = 4 }) } end)
  local _, named = cached:gsub("|cff7b2cbf%[Klinge der Morgenröte%]|r", "")
  local _, any = cached:gsub("Klinge der Morgenröte", "")
  check(named > 0 and named == any, "a cached item appears by name, always in the paper's epic colour")
  local g = News.Groups({ E("loot", "Lyra Distelbach", At(18, 20), { item = 9999, q = 4 }) }, Ctx())[1]
  local v = News.Vars(g, Ctx(), DE)
  check(v.thing == "einen epischen Gegenstand" and v.thingnom == "ein epischer Gegenstand"
    and News.Vars(g, Ctx(), EN).thing == "an epic item", "no item data at all: 'einen epischen Gegenstand' / 'an epic item'")
  local single = Many(function(i)
    return { E("boss", "Tamo Eichengrund", At(18, 21) + i, { inst = "Onyxias Hort", boss = "Onyxia", raid = true, grp = true, n = 9 }) }
  end)
  check(not single:find("Minuten", 1, true) and not single:find("Bosse", 1, true) and single:find("Onyxia", 1, true),
    "a single raid kill never claims a duration or a boss count")
  local run = Many(function(i)
    return { E("run", "Bodo Kesselring", At(18, 14) + i, { inst = "Maraudon", boss = "Prinzessin Theradras", n = 6, nf = 2 }) }
  end)
  check(not run:find("Minuten", 1, true) and run:find("Prinzessin Theradras", 1, true),
    "a dungeon run carries no start time, so no variant claims minutes")
end

local GENDERED_STEMS = { "Schurk", "Jäger", "Priester", "Held", "Abenteurer", "Spieler", "Krieger", "Magier", "Hexenmeister",
  "Druid", "Schaman", "Paladin", "Sieger", "Gewinner", "Verlierer", "Kämpfer", "Streiter", "Gefährt", "Kamerad", "Recke",
  "Reckin", "Besitzer", "Anführer", "Kollege", "Kollegin" }
local PRONOUNS = { er = true, sie = true, ihn = true, ihm = true, ihr = true, ihre = true, ihren = true, ihrem = true, ihrer = true,
  ihres = true, sein = true, seine = true, seinen = true, seinem = true, seiner = true, seines = true }

local function GenderedWords(texts)
  local hits = {}
  local function Scan(v)
    if type(v) == "table" then for _, x in pairs(v) do Scan(x) end return end
    if type(v) ~= "string" then return end
    for word in (v:gsub("{[?!]?[%w_]+}", "Xx")):gmatch("[%a\128-\255]+") do
      if PRONOUNS[word:lower()] then hits[#hits + 1] = word .. " in: " .. v end
      for _, stem in ipairs(GENDERED_STEMS) do
        if word:sub(1, #stem) == stem then hits[#hits + 1] = word .. " in: " .. v end
      end
    end
  end
  Scan(texts)
  return hits
end

Kit.section("German texts never guess a character's gender")
do
  check(#GenderedWords({ "Die Schurkin {name} siegt", "{name} und ihre Gruppe" }) == 2 and #GenderedWords({ "{name} erbeutet {thing}" }) == 0,
    "the check catches a gendered class noun and a pronoun, and passes a neutral line")
  local hits = GenderedWords(DE)
  check(#hits == 0, "no deDE newspaper text uses a gendered person noun or pronoun (" .. (hits[1] or "none") .. ")")
end

Kit.section("Names from the sender's client: professions and battlegrounds in the reader's language")
do
  local names = News.NAMES or {}
  local complete, seen, clash, n = true, {}, nil, 0
  for key, pair in pairs(names) do
    n = n + 1
    if not (pair.enUS and pair.deDE) then complete = false end
    for _, name in pairs(pair) do
      if seen[name] and seen[name] ~= key then clash = name end
      seen[name] = key
    end
  end
  check(n >= 15 and complete and clash == nil, "every profession, secondary skill and battleground has an English and a "
    .. "German name, no name belongs to two keys (" .. tostring(clash) .. ")")
  local function SkillVars(name, L)
    local g = News.Groups({ E("skill", "Daesha Tandaryel", At(20, 3, 11), { skill = name, rank = 150 }) }, Ctx())[1]
    return News.Vars(g, Ctx(), L).skill
  end
  check(SkillVars("Alchemy", DE) == "Alchemie" and SkillVars("Lederverarbeitung", EN) == "Leatherworking"
    and SkillVars("Erste Hilfe", DE) == "Erste Hilfe" and SkillVars("First Aid", DE) == "Erste Hilfe"
    and SkillVars("Juwelenschleifen", DE) == "Juwelenschleifen",
    "a skill name from either language is printed in the reader's, an unknown one as it came")
  local issue = News.Issue({ day = "2026-11-20", no = 7, entries = {
    E("level", "Daesha Tandaryel", At(20, 1, 5), { lvl = 10 }),
    E("mount", "Tamo Eichengrund", At(20, 2), { lvl = 40 }),
    E("skill", "Daesha Tandaryel", At(20, 3, 11), { skill = "Alchemy", rank = 150 }),
    E("skill", "Daesha Tandaryel", At(20, 3, 13), { skill = "Leatherworking", rank = 150 }),
    E("pvp", "Bodo Kesselring", At(20, 4), { pk = "win", name = "Warsong Gulch" }),
  } }, DE, Ctx())
  local text = Flatten(issue)
  check(text:find("Alchemie", 1, true) and text:find("Lederverarbeitung", 1, true) and text:find("Kriegshymnenschlucht", 1, true)
    and not text:find("Alchemy", 1, true) and not text:find("Leatherworking", 1, true) and not text:find("Warsong", 1, true),
    "a German paper prints German profession and battleground names, whatever client sent them")
  local log = reader.H:Format(E("skill", "Daesha Tandaryel", At(20, 3, 11), { skill = "Leatherworking", rank = 150 }))
  check(log:find("Lederverarbeitung", 1, true) and not log:find("Leatherworking", 1, true),
    "the chronicle prints the reader's profession name too (" .. log .. ")")
end

local function Click(button) button:GetScript("OnClick")(button) end
local function Frame(c) return c.env.RavenquillExpeditionHighlightsFrame end
local function Heard(c, e) return c.H:Add(e, "wire") end

Kit.section("Window: the Rabenblatt opens on the latest issue, with previous and next issues")
do
  local c = Client("Lyra Distelbach")
  Heard(c, E("level", "Bodo Kesselring", At(16, 10), { lvl = 20, cls = "WARRIOR" }))
  Heard(c, E("mount", "Mira Sturmfeder", At(18, 13, 24), { lvl = 40 }))
  Heard(c, E("loot", "Tamo Eichengrund", At(20, 20), { item = 5001, q = 4 }))
  Heard(c, E("run", "Bodo Kesselring", At(20, 11, 38), { inst = "Zul'Farrak", boss = "Wasserbeschwörerin Velratha", n = 7, nf = 7 }))
  check(c.H:OverviewStatus():find("^4 neu"), "four new entries before the paper is opened (" .. c.H:OverviewStatus() .. ")")
  c.H:ShowWindow()
  local f = Frame(c)
  local paper = f.paper
  check(f.mode == "paper" and paper:IsShown() and not f.msg:IsShown() and f.modeButton:GetText() == "Chronik",
    "the window opens as the newspaper with a Chronik button")
  check(paper.metaLeft:GetText() == "Gildenblatt der Ravenquill Expedition" and paper.metaDate:GetText() == "Freitag, 20. November"
    and paper.metaRight:GetText() == "Nr. 3 · Preis: 1 Kupfer", "meta line: paper, weekday and date, issue number and price")
  check(paper.issue.lead.kind == "epic" and paper.lead.head:GetText() == paper.issue.lead.head and paper.second.head:GetText() == paper.issue.second.head,
    "the latest issue leads with the epic, the run is the second story")
  check(f.issueLabel:GetText() == "Ausgabe vom 20. November" and f.prev:IsEnabled() and not f.next:IsEnabled(),
    "footer: issue date, previous enabled, next disabled on the latest issue")
  check(not c.H:OverviewStatus():find("neu", 1, true), "opening the newspaper counts as looking: nothing new left")
  Click(f.prev)
  check(paper.metaRight:GetText() == "Nr. 2 · Preis: 1 Kupfer" and f.issueLabel:GetText() == "Ausgabe vom 18. November"
    and paper.issue.lead.kind == "mount" and f.next:IsEnabled(), "previous issue: the 18th with the mount")
  check(paper.second.head:GetText() == DE.NO_SECOND_HEAD and paper.brief.more:GetText() == DE.NO_BRIEF,
    "a one-story day says so in the second column and the brief box")
  Click(f.prev)
  check(paper.metaRight:GetText() == "Nr. 1 · Preis: 1 Kupfer" and not f.prev:IsEnabled(), "first issue: previous disabled")
  Click(f.next)
  Click(f.next)
  check(paper.metaRight:GetText() == "Nr. 3 · Preis: 1 Kupfer" and not f.next:IsEnabled(), "next twice: back on the latest issue")
  Click(f.prev)
  Click(f.modeButton)
  local lines = table.concat(f.msg._lines or {}, "\n")
  check(f.mode == "log" and f.msg:IsShown() and not paper:IsShown() and f.modeButton:GetText() == "Zeitung"
    and lines:find("Zul'Farrak", 1, true) and lines:find("neu seit deinem letzten Blick", 1, true),
    "Chronik shows the plain log with the new-entries line, and the button turns into Zeitung")
  Click(f.modeButton)
  check(f.mode == "paper" and paper:IsShown() and not f.msg:IsShown(), "Zeitung switches back to the newspaper")
  f:Hide()
  Click(f.modeButton)
  c.H:ShowWindow()
  check(f.mode == "paper" and paper.metaRight:GetText() == "Nr. 3 · Preis: 1 Kupfer", "reopening starts on the latest issue again")
  Heard(c, E("level", "Mira Sturmfeder", At(20, 21, 15), { lvl = 60 }))
  sched:advance(1)
  local told = paper.brief.lines[1]:GetText() .. " " .. (paper.extras[1].head:GetText() or "")
  check(told:find("Mira Sturmfeder", 1, true), "an entry arriving while the paper is open goes into today's issue")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Window: empty log, masthead and parchment fallbacks")
do
  local c = Client("Tamo Eichengrund", "deDE", function(env, cl)
    env.GetFileIDFromPath = function() return nil end
    cl.frameMethods.SetTexture = function(s, path) s._texture = path; if tostring(path):find("masthead", 1, true) then return false end end
  end)
  c.H:ShowWindow()
  local f = Frame(c)
  local paper = f.paper
  check(not paper.masthead.loaded and paper.masthead.text:IsShown() and not paper.masthead.texture:IsShown()
    and paper.masthead.text:GetText() == "Rabenblatt", "a masthead texture that fails to load falls back to the Morpheus title")
  check(paper.parchment.source == "color", "a missing parchment texture falls back to a paper colour")
  check(paper.lead.head:GetText() == DE.EMPTY_HEAD and f.issueLabel:GetText() == DE.NO_ISSUE and not f.prev:IsEnabled()
    and not f.next:IsEnabled(), "an empty log prints the editors' note and disables both buttons")
  local plain = Client("Mira Sturmfeder", "enUS")
  plain.H:ShowWindow()
  local pf = Frame(plain)
  check(pf.paper.masthead.loaded and pf.paper.masthead.texture:IsShown() and not pf.paper.masthead.text:IsShown(),
    "with the texture available the masthead is the texture")
  check(pf.modeButton:GetText() == "Chronicle" and pf.prev:GetText() == "« Previous issue" and pf.paper.lead.head:GetText() == EN.EMPTY_HEAD,
    "English clients get the English paper")
  check(#c.errors == 0 and #plain.errors == 0, "no Lua errors")
end

Kit.section("Sample issues (German)")
do
  local samples = {
    { day = "2026-11-18", no = 4, entries = {
      E("loot", "Lyra Distelbach", At(18, 20), { item = 5001, q = 4 }),
      E("level", "Tamo Eichengrund", At(18, 17, 44), { lvl = 40 }),
      E("level", "Bodo Kesselring", At(18, 18, 52), { lvl = 40 }),
      E("quest", "Mira Sturmfeder", At(18, 15, 10), { qid = 176, title = "GESUCHT: Hogger", tag = "special" }),
    } },
    { day = "2026-11-19", no = 5, entries = {
      E("run", "Lyra Distelbach", At(19, 19, 8), { inst = "Maraudon", boss = "Prinzessin Theradras", n = 6, nf = 4 }),
      E("quest", "Mira Sturmfeder", At(19, 18, 20), { qid = 7044, title = "Legenden von Maraudon", tag = "special" }),
      E("quest", "Mira Sturmfeder", At(19, 18, 40), { qid = 7046, title = "Das Szepter von Celebras", tag = "special" }),
    } },
    { day = "2026-11-20", no = 6, entries = {
      E("level", "Tamo Eichengrund", At(20, 13, 29), { lvl = 50 }),
      E("gear", "Tamo Eichengrund", At(20, 13, 28), { item = 5002, q = 3, il = 47, oil = 33, slot = 13 }),
      E("mount", "Bodo Kesselring", At(20, 13, 24), { lvl = 40 }),
      E("boss", "Lyra Distelbach", At(20, 21, 0), { inst = "Onyxias Hort", boss = "Onyxia", raid = true, grp = true, n = 11 }),
    } },
  }
  local out = {}
  for _, day in ipairs(samples) do
    local issue = News.Issue(day, DE, Ctx())
    out[#out + 1] = ("== Nr. %d, %s ==\n%s"):format(issue.no, issue.day, Flatten(issue))
  end
  local text = table.concat(out, "\n")
  if os.getenv("RQ_NEWS_SAMPLES") then print(text) end
  check(not text:find("[{}]") and #GenderedWords({ text }) == 0, "three sample days print without placeholders or gendered words")
end

Kit.finish()
