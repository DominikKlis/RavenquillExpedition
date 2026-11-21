local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, At, E, Ctx = NK.Kit, NK.At, NK.E, NK.Ctx
local check = Kit.check

local reader = NK.Client("Lyra Distelbach")
local News = reader.ns[NK.HL].News
local DE, EN = reader.ns[NK.HL].NewsLocales.deDE, reader.ns[NK.HL].NewsLocales.enUS
local LOCALES = { DE, EN }

local function Issue(entries, L) return News.Issue({ day = "2026-11-19", no = 5, entries = entries }, L, Ctx()) end

local function Kills(who, inst, bosses, h, m, fields)
  local out = {}
  for i, b in ipairs(bosses) do
    local e = { inst = inst, boss = b[1], enc = b[3] }
    for k, v in pairs(fields or {}) do e[k] = v end
    out[i] = E("boss", who, At(19, h, m) + b[2] * 60, e)
  end
  return out
end

local MARAUDON = { { "Schlingwurzler", 0, 423 }, { "Noxxion", 7, 422 }, { "Celebras der Verfluchte", 15, 425 },
  { "Erdrutsch", 38, 426 }, { "Prinzessin Theradras", 47, 429 }, { "Faulschnapper", 48, 428 } }

local CASES = {
  maraudon = function(i) return Kills("Bodo Kesselring", "Maraudon", MARAUDON, 18, 20, { first = true, lvl = 52 }) end,
  raid = function(i)
    return Kills("Tamo Eichengrund", "Geschmolzener Kern", { { "Lucifron", 0 }, { "Magmadar", 20 }, { "Gehennas", 45 } }, 21, 20,
      { raid = true, grp = true, n = 14 })
  end,
  single = function(i)
    return { E("boss", "Mira Sturmfeder", At(19, 15, 10) + i, { inst = "Dämmerwald", boss = "Mor'Ladim", first = true, lvl = 33 }) }
  end,
  run = function(i)
    return { E("run", "Tamo Eichengrund", At(19, 22, 16) + i,
      { inst = "Gefängnis von Alcaz", boss = "Blazeroar", n = 10, nf = 5, lvl = 51 }) }
  end,
  firstrun = function(i)
    return { E("run", "Mira Sturmfeder", At(19, 23, 19) + i,
      { inst = "Ausgrabungsstätte", boss = "Reliktwächter", n = 3, nf = 3, first = true, lvl = 31 }) }
  end,
  epic = function(i)
    return { E("loot", "Lyra Distelbach", At(19, 20, 0) + i, { item = 5001, q = 4 }),
      E("gear", "Lyra Distelbach", At(19, 20, 0) + i + 1, { item = 5001, q = 4, il = 50, oil = 45, slot = 16, lvl = 49 }) }
  end,
  gear = function(i)
    return { E("gear", "Faro Wegemann", At(19, 2, 49) + i, { item = 5004, q = 3, il = 55, oil = 44, slot = 17, lvl = 48 }) }
  end,
  levels = function(i)
    return { E("level", "Mira Sturmfeder", At(19, 17, 44) + i, { lvl = 40 }), E("level", "Bodo Kesselring", At(19, 18, 52), { lvl = 40 }) }
  end,
  quests = function(i)
    local out = {}
    for q = 1, 4 do out[q] = E("quest", "Mira Sturmfeder", At(19, 9, q) + i, { qid = q, title = "Auftrag " .. q, tag = "special", lvl = 37 }) end
    return out
  end,
  mount = function(i) return { E("mount", "Tamo Eichengrund", At(19, 13, 24) + i, { lvl = 40 }) } end,
  rep = function(i) return { E("rep", "Bodo Kesselring", At(19, 12, 7) + i, { st = 7, fac = "Argentumdämmerung", lvl = 55 }) } end,
  skill = function(i) return { E("skill", "Lyra Distelbach", At(19, 3, 11) + i, { skill = "Alchemy", rank = 150, lvl = 10 }) } end,
  pvp = function(i) return { E("pvp", "Bodo Kesselring", At(19, 16, 3) + i, { pk = "win", name = "Warsong Gulch", lvl = 29 }) } end,
  duel = function(i) return { E("duel", "Mira Sturmfeder", At(19, 18, 9) + i, { foe = "Bodo Kesselring", lvl = 34 }) } end,
}

local SUBJECTS = { name = true, names = true, lead = true, lastname = true, icon = true }

local function Tokens(vars)
  local out = {}
  for key, value in pairs(vars) do
    if not SUBJECTS[key] and value ~= "" then out[#out + 1] = tostring(value) end
  end
  return out
end

local function Mentions(text, token)
  local from = 1
  while true do
    local s, e = text:find(token, from, true)
    if not s then return false end
    local before, after = text:sub(s - 1, s - 1), text:sub(e + 1, e + 1)
    if not before:find("[%w\128-\255:]") and not after:find("[%w\128-\255:]") then return true end
    from = s + 1
  end
end

local function Sentences(text)
  local out = {}
  for s in text:gmatch("[^%.!?]+[%.!?]*") do
    s = s:match("^%s*(.-)%s*$")
    if s ~= "" then out[#out + 1] = s end
  end
  return out
end

local function Repeated(story, vars)
  local parts = { story.head, story.dek or "", story.body[1] or "", story.body[2] or "" }
  for _, token in ipairs(Tokens(vars)) do
    local seen
    for p, text in ipairs(parts) do
      if Mentions(text, token) then
        if seen then return token .. " in: " .. parts[seen] .. " / " .. text end
        seen = p
      end
    end
  end
end

Kit.section("Facts: head, dek and body each say something the others did not")
do
  local repeats, n = {}, 0
  for name, make in pairs(CASES) do
    for _, L in ipairs(LOCALES) do
      for i = 1, 16 do
        local g = News.Groups(make(i), Ctx())[1]
        local hit = Repeated(News.Story(g, L, Ctx()), News.Vars(g, Ctx(), L))
        n = n + 1
        if hit then repeats[#repeats + 1] = L.LOCALE .. " " .. name .. ": " .. hit end
      end
    end
  end
  check(#repeats == 0, ("no number, time, boss, place or item appears in two of head, dek and body (%d stories, %d repeats: %s)")
    :format(n, #repeats, repeats[1] or "none"))
  local restated
  for i = 1, 16 do
    local g = News.Groups(CASES.maraudon(i), Ctx())[1]
    local s, tokens = News.Story(g, DE, Ctx()), {}
    for _, token in ipairs(Tokens(News.Vars(g, Ctx(), DE))) do
      if Mentions(s.head, token) then tokens[#tokens + 1] = token end
    end
    for _, sentence in ipairs(Sentences(table.concat(s.body, " "))) do
      local all = tokens[1] ~= nil
      for _, token in ipairs(tokens) do all = all and Mentions(sentence, token) end
      if all and not restated then restated = s.head .. " / " .. sentence end
    end
  end
  check(restated == nil, "no body sentence restates the headline's facts (" .. tostring(restated) .. ")")
end

local function StoryParts(issue)
  local parts = {}
  for _, s in ipairs({ issue.lead, issue.second }) do
    parts[#parts + 1] = s.kicker or ""
    parts[#parts + 1] = s.head
    parts[#parts + 1] = s.dek or ""
    for _, p in ipairs(s.body) do parts[#parts + 1] = p end
  end
  return parts
end

local function Twice(issue)
  local seen = {}
  for _, part in ipairs(StoryParts(issue)) do
    for _, sentence in ipairs(Sentences(part)) do
      if seen[sentence] then return sentence end
      seen[sentence] = true
    end
  end
end

local function Count(issue, word)
  local n = 0
  for _, part in ipairs(StoryParts(issue)) do n = n + select(2, part:gsub(word, "")) end
  return n
end

local PAIRS = {
  run = function(i)
    return { E("run", "Tamo Eichengrund", At(19, 14, 2) + i, { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 5, nf = 2 }),
      E("run", "Mira Sturmfeder", At(19, 20, 40) + i, { inst = "Uldaman", boss = "Archaedas", n = 7, nf = 7, first = true }) }
  end,
  boss = function(i)
    local a = Kills("Bodo Kesselring", "Maraudon", MARAUDON, 10, 5 + i % 9, { first = true })
    local b = Kills("Lyra Distelbach", "Zul'Farrak", { { "Antu'sul", 0 }, { "Theka der Märtyrer", 4 }, { "Gahz'rilla", 9 } }, 16, i % 20)
    for _, e in ipairs(b) do a[#a + 1] = e end
    return a
  end,
  level = function(i)
    return { E("level", "Mira Sturmfeder", At(19, 11, 3) + i, { lvl = 30 }), E("level", "Bodo Kesselring", At(19, 19, 3) + i, { lvl = 20 }) }
  end,
  gear = function(i)
    return { E("gear", "Faro Wegemann", At(19, 9, 13) + i, { item = 5002, q = 3, il = 41, oil = 30, slot = 11 }),
      E("gear", "Tamo Eichengrund", At(19, 21, 7) + i, { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }) }
  end,
  mixed = function(i)
    return { E("run", "Tamo Eichengrund", At(19, 14, 2) + i, { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 5, nf = 2 }),
      E("loot", "Lyra Distelbach", At(19, 20, 0) + i, { item = 5001, q = 4 }),
      E("level", "Mira Sturmfeder", At(19, 11, 3) + i, { lvl = 30 }), E("mount", "Bodo Kesselring", At(19, 8, 0) + i, { lvl = 40 }) }
  end,
}

local VOICE = { deDE = "Redaktion", enUS = "editors" }

Kit.section("Flavour: per issue no sentence twice, the editors speak at most once")
do
  local twice, voices, n = nil, nil, 0
  for name, make in pairs(PAIRS) do
    for _, L in ipairs(LOCALES) do
      for i = 1, 25 do
        local issue = Issue(make(i), L)
        n = n + 1
        local s = Twice(issue)
        if s and not twice then twice = L.LOCALE .. " " .. name .. ": " .. s end
        local v = Count(issue, VOICE[L.LOCALE])
        if v > 1 and not voices then voices = L.LOCALE .. " " .. name .. ": " .. v .. "x" end
      end
    end
  end
  check(twice == nil, ("no sentence or kicker appears twice in one issue (%d issues; %s)"):format(n, tostring(twice)))
  check(voices == nil, ("'Redaktion' / 'editors' at most once per issue (%s)"):format(tostring(voices)))
end

local function Flat(issue)
  local parts = StoryParts(issue)
  for _, b in ipairs(issue.brief) do parts[#parts + 1] = b.text end
  return table.concat(parts, "\n")
end

Kit.section("Outings: one dungeon run reported by several guildmates is one story")
do
  local run = {
    E("run", "Hilde Krugbauer", At(19, 21, 52) + 33, { inst = "Die Versunkene Stadt", boss = "Min'loth die Schlange", n = 3, nf = 3,
      first = true, lvl = 42 }),
    E("run", "Moira Stonebrook", At(19, 21, 52) + 53, { inst = "The Drowned City", boss = "Min'loth the Serpent", n = 3, nf = 3,
      first = true, lvl = 49 }),
  }
  check(#News.Groups(run, Ctx()) == 1, "a German and an English report of one run are one group")
  local issue = Issue(run, DE)
  local text = Flat(issue)
  check(issue.lead.head:find("Hilde Krugbauer und Moira Stonebrook", 1, true) and not issue.second,
    "the story names both, the second column stays free (" .. issue.lead.head .. ")")
  check(not text:find("Drowned", 1, true) and not text:find("Serpent", 1, true),
    "one instance name in one language for the whole story")
  local en = Issue(run, EN)
  check(en.lead.head:find("Hilde Krugbauer and Moira Stonebrook", 1, true) ~= nil, "the English paper joins them with 'and'")
  local bosses = { { "Captain Dreadrise", 0, 3476 }, { "Unsterbliche Wächter", 9, 3478 }, { "Min'loth die Schlange", 10, 3479 } }
  local english = { { "Captain Dreadrise", 0, 3476 }, { "Deathless Guardians", 9, 3478 }, { "Min'loth the Serpent", 10, 3479 } }
  local kills = Kills("Hilde Krugbauer", "Die Versunkene Stadt", bosses, 21, 42, { first = true })
  for _, e in ipairs(Kills("Gerd Rübsam", "Die Versunkene Stadt", bosses, 21, 42, { first = true })) do kills[#kills + 1] = e end
  for _, e in ipairs(Kills("Moira Stonebrook", "The Drowned City", english, 21, 42, { first = true })) do kills[#kills + 1] = e end
  local groups = News.Groups(kills, Ctx())
  local head = groups[1] and News.Story(groups[1], DE, Ctx()).head or ""
  local all = head:find("Hilde Krugbauer", 1, true) and head:find("Gerd Rübsam", 1, true) and head:find("Moira Stonebrook", 1, true)
  check(#groups == 1 and all and head:find(", ", 1, true) and head:find(" und ", 1, true),
    "three boss reports of one run, two languages, are one story naming all three (" .. #groups .. ": " .. head .. ")")
  local apart = {
    E("run", "Tamo Eichengrund", At(19, 20, 10), { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 4, nf = 4 }),
    E("run", "Mira Sturmfeder", At(19, 20, 11), { inst = "Uldaman", boss = "Archaedas", n = 4, nf = 4 }),
    E("run", "Bodo Kesselring", At(19, 22, 30), { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 4, nf = 4 }),
  }
  check(#News.Groups(apart, Ctx()) == 3, "different dungeons in the same minute, or the same dungeon hours apart, stay separate")
end

Kit.section("Kickers and claims fit the facts")
do
  local mixed, wild, claims = nil, nil, nil
  for i = 1, 30 do
    local kills = Kills("Bodo Kesselring", "Maraudon", MARAUDON, 18, 20)
    kills[1].first = true
    for _, L in ipairs(LOCALES) do
      local s = News.Story(News.Groups(kills, Ctx())[1], L, Ctx())
      if s.kicker == "Premiere" then mixed = s.kicker end
      if s.kicker == "Aus der Wildnis" then wild = s.kicker end
    end
    local bag = { E("loot", "Lyra Distelbach", At(19, 20, 0) + i, { item = 5001, q = 4, src = "bag" }) }
    local text = Flat(Issue(bag, DE))
    for _, word in ipairs({ "Post", "Handel", "Auktion", "lange Suche" }) do
      if text:find(word, 1, true) then claims = word .. ": " .. text end
    end
  end
  check(mixed == nil, "no 'Premiere' when only some of the kills were firsts")
  check(wild == nil, "a dungeon with six bosses is never 'Aus der Wildnis'")
  check(claims == nil, "an item that turned up in the bags claims no mail, trade or auction, and no long search (" .. tostring(claims) .. ")")
  local premiere = false
  for i = 1, 30 do
    if News.Story(News.Groups(CASES.maraudon(i), Ctx())[1], DE, Ctx()).kicker == "Premiere" then premiere = true end
  end
  check(premiere, "six first kills can be a 'Premiere'")
end

Kit.section("In Kürze: in time order, one phrasing per kind")
do
  local issue = Issue({
    E("run", "Tamo Eichengrund", At(19, 22, 16), { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 5, nf = 2 }),
    E("loot", "Lyra Distelbach", At(19, 20, 0), { item = 5001, q = 4 }),
    E("skill", "Bodo Kesselring", At(19, 19, 39), { skill = "Fishing", rank = 150 }),
    E("level", "Mira Sturmfeder", At(19, 1, 5), { lvl = 10 }),
    E("skill", "Mira Sturmfeder", At(19, 3, 13), { skill = "Leatherworking", rank = 150 }),
    E("gear", "Faro Wegemann", At(19, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }),
    E("skill", "Mira Sturmfeder", At(19, 3, 11), { skill = "Alchemy", rank = 150 }),
  }, DE)
  local times = {}
  for i, b in ipairs(issue.brief) do times[i] = b.time end
  local sorted = true
  for i = 2, #times do if times[i] < times[i - 1] then sorted = false end end
  check(#times == 5 and sorted, "the brief lines run from morning to evening (" .. table.concat(times, " ") .. ")")
  local odd
  for _, kind in ipairs({ "skill", "levels", "gear", "run", "single", "quests", "rep" }) do
    for _, L in ipairs(LOCALES) do
      local first
      for i = 1, 12 do
        local text = News.Brief(News.Groups(CASES[kind](i), Ctx())[1], L, Ctx()).text
        first = first or text
        if text ~= first and not odd then odd = kind .. ": " .. first .. " / " .. text end
      end
    end
  end
  check(odd == nil, "the same kind of news is always phrased the same way in the brief box (" .. tostring(odd) .. ")")
end

Kit.finish()
