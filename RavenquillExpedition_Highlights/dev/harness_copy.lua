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
  text, token = text:lower(), token:lower()
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
        for _, long in ipairs({ false, true }) do
          local hit = Repeated(News.Story(g, L, Ctx(), nil, long), News.Vars(g, Ctx(), L))
          n = n + 1
          if hit then repeats[#repeats + 1] = L.LOCALE .. " " .. name .. ": " .. hit end
        end
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
  for _, s in ipairs({ issue.lead, issue.second, issue.extra[1] }) do
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
  night = function(i)
    local out = Kills("Tamo Eichengrund", "Dalaran", { { "Atrexis der Grabritter", 0 }, { "Mortis", 17 }, { "Schemen des Erzmagiers", 53 } },
      20, 0)
    for _, e in ipairs(out) do e.t = e.t - 20 * 3600 + 23 * 60 + i end
    out[#out + 1] = E("gear", "Faro Wegemann", At(19, 2, 49) + i, { item = 5004, q = 3, il = 55, oil = 44, slot = 17 })
    out[#out + 1] = E("skill", "Hanne Moosgrund", At(19, 3, 11) + i, { skill = "Alchemy", rank = 150 })
    out[#out + 1] = E("level", "Ole Fichtental", At(19, 1, 5) + i, { lvl = 30 })
    out[#out + 1] = E("mount", "Bodo Kesselring", At(19, 4, 10) + i, { lvl = 40 })
    return out
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
  local again
  for name, make in pairs(PAIRS) do
    for _, L in ipairs(LOCALES) do
      for i = 1, 25 do
        local issue = Issue(make(i), L)
        local text = table.concat(StoryParts(issue), "\n"):lower()
        for _, b in ipairs(issue.brief) do text = text .. "\n" .. b.text:lower() end
        for _, motif in ipairs(L.ONCE) do
          local _, hits = text:gsub(motif:lower():gsub("%p", "%%%0"), "")
          if hits > 1 and not again then again = L.LOCALE .. " " .. name .. ": " .. motif .. " " .. hits .. "x" end
        end
      end
    end
  end
  check(again == nil, ("every joke motif (night, glow, envy, old piece at the vendor ...) at most once per issue, briefs included (%s)")
    :format(tostring(again)))
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

local function Told(s) return table.concat({ s.kicker or "", s.head, s.dek or "", table.concat(s.body, " ") }, " ") end

Kit.section("Length: the lead tells 3 to 5 sentences, the other stories 2 to 3, and names who it is about")
do
  local off, nameless, n = nil, nil, 0
  for name, make in pairs(CASES) do
    for _, L in ipairs(LOCALES) do
      for i = 1, 16 do
        local g = News.Groups(make(i), Ctx())[1]
        local lead, column, v = News.Story(g, L, Ctx(), nil, true), News.Story(g, L, Ctx()), News.Vars(g, Ctx(), L)
        local a, b = #News.Sentences(table.concat(lead.body, " ")), #News.Sentences(table.concat(column.body, " "))
        n = n + 1
        if (a < 3 or a > 5 or b < 2 or b > 3) and not off then off = ("%s %s: lead %d, column %d"):format(L.LOCALE, name, a, b) end
        local who = v.name or v.names
        for _, s in ipairs({ lead, column }) do
          if g.kind ~= "raid" and not (s.head .. " " .. (s.dek or "")):find(who, 1, true) and not nameless then
            nameless = L.LOCALE .. " " .. name .. ": " .. s.head .. " / " .. tostring(s.dek)
          end
        end
      end
    end
  end
  check(off == nil, ("%d leads have 3 to 5 sentences, the same news as second or third story 2 to 3 (%s)"):format(n, tostring(off)))
  check(nameless == nil, "head or dek names the guildmate the story is about (" .. tostring(nameless) .. ")")
end

local NIGHT_WORDS = { deDE = { "nacht", "schlaf", "uhrzeit", "sperrstunde", "ffnungszeiten" },
  enUS = { "morning", "midnight", "sleep", "slept", "night shift", "this hour", "closing time", "opening hours", "rested" } }
local MIDNIGHT = { deDE = "mitternacht in", enUS = "midnight in" }

local function AtHour(h, i)
  local t = At(19, h, 30) + i
  local out = Kills("Tamo Eichengrund", "Dalaran", { { "Atrexis der Grabritter", 0 }, { "Mortis", 9 }, { "Schemen des Erzmagiers", 20 } },
    h, 0)
  for _, e in ipairs(out) do e.t = e.t + i end
  return { out, { E("gear", "Faro Wegemann", t, { item = 5004, q = 3, il = 55, oil = 44, slot = 17, lvl = 48 }) },
    { E("skill", "Hanne Moosgrund", t, { skill = "Alchemy", rank = 150, lvl = 10 }) }, { E("level", "Ole Fichtental", t, { lvl = 30 }) },
    { E("mount", "Bodo Kesselring", t, { lvl = 40 }) }, { E("loot", "Lyra Distelbach", t, { item = 5001, q = 4 }) },
    { E("quest", "Mira Sturmfeder", t, { qid = 9, title = "Auftrag 9", tag = "special", lvl = 37 }) },
    { E("duel", "Mira Sturmfeder", t, { foe = "Bodo Kesselring", lvl = 34 }) } }
end

Kit.section("Night: remarks about the hour only between midnight and five in the morning")
do
  local early, late, midnight, seen = nil, nil, nil, {}
  for h = 0, 23 do
    for _, L in ipairs(LOCALES) do
      for i = 1, 6 do
        for _, entries in ipairs(AtHour(h, i)) do
          local g = News.Groups(entries, Ctx())[1]
          local text = (Told(News.Story(g, L, Ctx(), nil, true)) .. " " .. News.Brief(g, L, Ctx(), News.Desk(L)).text):lower()
          for _, word in ipairs(NIGHT_WORDS[L.LOCALE]) do
            if text:find(word, 1, true) then
              if h >= 5 and not late then late = ("%s %02d:30 %s: %s"):format(L.LOCALE, h, word, text) end
              seen[L.LOCALE .. h] = true
            end
          end
          if h >= 2 and text:find(MIDNIGHT[L.LOCALE], 1, true) and not midnight then midnight = ("%02d: %s"):format(h, text) end
        end
      end
      if h < 5 and not seen[L.LOCALE .. h] and not early then early = L.LOCALE .. " " .. h end
    end
  end
  check(late == nil, "from five in the morning on no text talks about the night or sleep (" .. tostring(late) .. ")")
  check(early == nil, "every night hour gets its remark somewhere (" .. tostring(early) .. " has none)")
  check(midnight == nil, "'Mitternacht in ...' only for a run that ends before two (" .. tostring(midnight) .. ")")
  local desk, lines = News.Desk(DE), {}
  for i, h in ipairs({ 2, 3 }) do
    local g = News.Groups({ E("skill", "Hanne Moosgrund", At(19, h, 11), { skill = ({ "Alchemy", "Mining" })[i], rank = 150 }) }, Ctx())[1]
    lines[i] = News.Brief(g, DE, Ctx(), desk).text
  end
  check(lines[1] == "Hanne Moosgrund: 150 Punkte in Alchemie. Um zwei Uhr nachts." and not lines[2]:find("nachts", 1, true),
    "a brief line at night gets 'Um zwei Uhr nachts.', the next one in the same issue not again (" .. lines[1] .. " / " .. lines[2] .. ")")
end

local FILLER = function()
  return { E("loot", "Lyra Distelbach", At(19, 20, 0), { item = 5001, q = 4 }),
    E("run", "Tamo Eichengrund", At(19, 22, 16), { inst = "Gnomeregan", boss = "Mekgineer Thermaplugg", n = 5, nf = 2 }),
    E("mount", "Bodo Kesselring", At(19, 13, 24), { lvl = 40 }) }
end

local function BriefLines(extra, L)
  local entries = FILLER()
  for _, e in ipairs(extra) do entries[#entries + 1] = e end
  local out = {}
  for _, b in ipairs(Issue(entries, L).brief) do out[b.time .. (out[b.time] and "b" or "")] = b.text end
  return out
end

local function Skill(who, h, m, skill, sec) return E("skill", who, At(19, h, m) + (sec or 0), { skill = skill, rank = 150 }) end

Kit.section("In Kürze: a line leaves out the name only right after the same guildmate's line")
do
  local gear = E("gear", "Faro Wegemann", At(19, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 })
  local de = BriefLines({ gear, Skill("Faro Wegemann", 2, 50, "Fishing"), Skill("Hanne Moosgrund", 3, 11, "Alchemy"),
    Skill("Hanne Moosgrund", 3, 13, "Leatherworking") }, DE)
  check(de["03:13"] == "Zwei Minuten später gleich noch 150 in Lederverarbeitung." and de["03:11"]:find("^Hanne Moosgrund: 150 Punkte"),
    "the same guildmate two minutes later: 'Zwei Minuten später gleich noch 150 in Lederverarbeitung.' (" .. tostring(de["03:13"]) .. ")")
  check(de["02:50"]:find("Faro Wegemann", 1, true) ~= nil,
    "a line after a report that the paper shows as a story keeps its name (" .. tostring(de["02:50"]) .. ")")
  local en = BriefLines({ gear, Skill("Hanne Moosgrund", 3, 11, "Alchemy"), Skill("Hanne Moosgrund", 3, 13, "Leatherworking") }, EN)
  check(en["03:13"] == "Two minutes later, also 150 in Leatherworking.", "English: 'Two minutes later, also ...' (" .. tostring(en["03:13"]) .. ")")
  local between = BriefLines({ gear, Skill("Hanne Moosgrund", 3, 11, "Alchemy"), Skill("Ole Fichtental", 3, 12, "Mining"),
    Skill("Hanne Moosgrund", 3, 13, "Leatherworking") }, DE)
  check(between["03:13"]:find("Hanne Moosgrund", 1, true) and between["03:12"]:find("Ole Fichtental", 1, true),
    "someone else in between: every line names its guildmate (" .. tostring(between["03:13"]) .. ")")
  local gaps = BriefLines({ gear, Skill("Hanne Moosgrund", 3, 11, "Alchemy", 5), Skill("Hanne Moosgrund", 3, 11, "Mining", 40),
    Skill("Hanne Moosgrund", 3, 12, "Cooking"), Skill("Hanne Moosgrund", 4, 42, "Fishing") }, DE)
  check(gaps["03:11b"] == "In derselben Minute gleich noch 150 in Bergbau." and gaps["03:12"] == "Eine Minute später gleich noch 150 in Kochkunst."
    and gaps["04:42"] == "Später am Tag dann noch 150 in Angeln.",
    "same minute, one minute, an hour and more: the right words (" .. tostring(gaps["03:11b"]) .. " / " .. tostring(gaps["04:42"]) .. ")")
end

Kit.section("Upgrades: the slot decides where the piece is worn")
do
  local SLOTS = { offhand = { 5004, 17, 55, 44 }, ring = { 5002, 11, 41, 30 }, weapon = { 5001, 16, 50, 45 } }
  local wrong, missing = nil, nil
  for _, L in ipairs(LOCALES) do
    for slot, s in pairs(SLOTS) do
      local found
      for i = 1, 40 do
        local g = News.Groups({ E("gear", "Faro Wegemann", At(19, 9, 13) + i, { item = s[1], q = 3, il = s[3], oil = s[4], slot = s[2] }) }, Ctx())[1]
        local text = Told(News.Story(g, L, Ctx(), nil, true)) .. " " .. Told(News.Story(g, L, Ctx()))
        found = found or text:find(L.WHERE[slot], 1, true)
        for other, where in pairs(L.WHERE) do
          if other ~= slot and text:find(where, 1, true) and not wrong then wrong = L.LOCALE .. " " .. slot .. ": " .. text end
        end
      end
      if not found and not missing then missing = L.LOCALE .. " " .. slot end
    end
    for i = 1, 40 do
      local text = Told(News.Story(News.Groups({ E("loot", "Lyra Distelbach", At(19, 20) + i, { item = 5001, q = 4 }) }, Ctx())[1], L, Ctx(), nil, true))
      for _, where in pairs(L.WHERE) do if text:find(where, 1, true) and not wrong then wrong = L.LOCALE .. " loot: " .. text end end
    end
  end
  check(missing == nil, "an off-hand upgrade reads 'in der linken Hand', a ring 'am Finger', a weapon 'in der Waffenhand' (" .. tostring(missing) .. ")")
  check(wrong == nil, "never another slot's place, and nothing about where an item that was only looted is worn (" .. tostring(wrong) .. ")")
end

Kit.section("Numbers: what the paper computes is a word up to twelve")
do
  local function Gear(il, oil) return News.Vars(News.Groups({ E("gear", "Faro Wegemann", At(19, 2, 49), { item = 5004, q = 3, il = il, oil = oil, slot = 17 }) }, Ctx())[1], Ctx(), DE) end
  local function Run(minutes) return News.Vars(News.Groups(Kills("Bodo Kesselring", "Maraudon", { { "Noxxion", 0 }, { "Erdrutsch", minutes } }, 18, 0), Ctx())[1], Ctx(), DE) end
  local level = News.Vars(News.Groups({ E("level", "Mira Sturmfeder", At(19, 13, 29), { lvl = 50 }) }, Ctx())[1], Ctx(), DE)
  check(Gear(55, 44).gain == "elf" and Gear(58, 44).gain == "14" and Gear(45, 44).gain == nil,
    "eleven levels more is 'elf', fourteen stays '14', one level more is no jump worth a number")
  check(level.left == "zehn" and Run(7).min == "sieben" and Run(27).min == "27" and Run(1).min == nil,
    "ten levels to go is 'zehn', seven minutes 'sieben', 27 minutes '27', one minute no duration")
  local head
  for i = 1, 40 do
    local g = News.Groups({ E("gear", "Faro Wegemann", At(19, 2, 49) + i, { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }) }, Ctx())[1]
    local s = News.Story(g, DE, Ctx())
    if s.head:find("^Elf Stufen mehr") then head = s.head end
  end
  check(head == "Elf Stufen mehr in der linken Hand", "a headline can open with the jump: 'Elf Stufen mehr in der linken Hand' (" .. tostring(head) .. ")")
end

local HEDGES = { deDE = { "dürfte", "dürften", "vermutlich", "soll", "sollen" }, enUS = { "probably", "presumably", "likely", "supposedly" } }

local function Unmarked(L)
  local bad = {}
  local function Scan(v)
    if type(v) == "table" then for _, x in pairs(v) do Scan(x) end return end
    if type(v) ~= "string" then return end
    local hedged = false
    for w in v:gsub("{[^}]*}", " "):gmatch("[%a\128-\255]+") do
      for _, h in ipairs(HEDGES[L.LOCALE]) do hedged = hedged or w:lower() == h end
    end
    if hedged ~= (v:find("{!sure}", 1, true) ~= nil) then bad[#bad + 1] = v end
  end
  Scan(L.KINDS)
  return bad
end

Kit.section("Guesses: every speculative variant is marked {!sure} and says so")
do
  check(#Unmarked({ LOCALE = "deDE", KINDS = { "Das dürfte stimmen.", "{!sure}Das stimmt.", "{!sure}Das stimmt vermutlich." } }) == 2,
    "the check catches an unmarked guess and a marked sentence without dürfte, vermutlich or soll")
  for _, L in ipairs(LOCALES) do
    local bad = Unmarked(L)
    check(#bad == 0, L.LOCALE .. ": a variant says dürfte/vermutlich/soll exactly when it is marked as a guess (" .. (bad[1] or "none") .. ")")
  end
end

Kit.finish()
