local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, At, E, Ctx = NK.Kit, NK.At, NK.E, NK.Ctx
local check = Kit.check

local reader = NK.Client("Lyra Distelbach")
local News = reader.ns[NK.HL].News
local DE, EN = reader.ns[NK.HL].NewsLocales.deDE, reader.ns[NK.HL].NewsLocales.enUS

local function Counts(week)
  local out = {}
  for _, c in ipairs(week and week.counts or {}) do out[#out + 1] = c.n .. " " .. c.label end
  return table.concat(out, " | ")
end

local function Honors(week)
  local out = {}
  for _, h in ipairs(week and week.honors or {}) do out[#out + 1] = h.title .. " · " .. h.who .. " · " .. h.why end
  return table.concat(out, " | ")
end

local function Reversed(list)
  local out = {}
  for i = #list, 1, -1 do out[#out + 1] = list[i] end
  return out
end

local function Run(who, t, inst, n, nf, lvl)
  return E("run", who, t, { inst = inst, boss = "Endboss von " .. inst, n = n, nf = nf, lvl = lvl })
end

local function Raid(who, t, boss, enc)
  return E("boss", who, t, { inst = "Geschmolzener Kern", boss = boss, enc = enc, raid = true, grp = true, n = 12, lvl = 60 })
end

local function Quest(who, t, lvl) return E("quest", who, t, { qid = t, title = "Auftrag " .. t, tag = "special", lvl = lvl }) end

local WEEK = {
  Quest("Ole Fichtental", At(16, 10), 40),
  Run("Ole Fichtental", At(17, 19), "Uldaman", 7, 7, 42),
  Run("Rika Steinbeck", At(17, 19, 2), "Uldaman", 7, 3, 44),
  E("skill", "Ilsa Brunnhold", At(18, 11), { skill = "Leatherworking", rank = 225, lvl = 36 }),
  Quest("Ole Fichtental", At(19, 22), 44),
  Raid("Tamo Eichengrund", At(20, 21, 20), "Lucifron", 663),
  Raid("Bodo Kesselring", At(20, 21, 21), "Lucifron", 663),
  Raid("Tamo Eichengrund", At(20, 21, 50), "Magmadar", 664),
  E("loot", "Rika Steinbeck", At(21, 20), { item = 5001, q = 4, lvl = 45 }),
  E("gear", "Rika Steinbeck", At(21, 20, 1), { item = 5001, q = 4, il = 50, oil = 45, slot = 16, lvl = 45 }),
  E("mount", "Hanne Moosgrund", At(22, 12), { lvl = 40 }),
  Run("Rika Steinbeck", At(22, 15), "Zul'Farrak", 6, 6, 45),
  Run("Hanne Moosgrund", At(22, 15, 1), "Zul'Farrak", 6, 2, 40),
}

Kit.section("Week in numbers: levels gained, bosses defeated and epic finds of a fixed week")
do
  local week = News.Week(WEEK, DE, Ctx())
  check(Counts(week) == "5 Stufen gewonnen | 15 Bosse besiegt | 1 epischer Fund",
    "Ole 40 to 44 and Rika 44 to 45 are five levels; 7 + 1 + 1 + 6 bosses; one epic (" .. Counts(week) .. ")")
  check(week and week.counts[1].key == "levels" and week.counts[2].key == "bosses" and week.counts[3].key == "epics",
    "the numbers come in a fixed order, each with its key")
  local twice = News.Week({ Raid("Tamo Eichengrund", At(20, 21, 20), "Lucifron", 663),
    Raid("Bodo Kesselring", At(20, 21, 21), "Lucifron", 663), Run("Rika Steinbeck", At(17, 19), "Uldaman", 7, 7, 44),
    Run("Ole Fichtental", At(17, 19, 2), "Uldaman", 7, 2, 42) }, DE, Ctx())
  check(Counts(twice) == "8 Bosse besiegt",
    "a raid kill two guildmates report counts once, a run two guildmates both report counts once (" .. Counts(twice) .. ")")
  local one = News.Week({ Quest("Mira Sturmfeder", At(16, 9), 20), Quest("Mira Sturmfeder", At(18, 9), 21),
    Raid("Tamo Eichengrund", At(20, 21), "Onyxia", 1084), E("loot", "Rika Steinbeck", At(18, 20), { item = 5001, q = 4 }) }, DE, Ctx())
  check(Counts(one) == "1 Stufe gewonnen | 1 Boss besiegt | 1 epischer Fund", "one of each reads in the singular (" .. Counts(one) .. ")")
  local en = News.Week(WEEK, EN, Ctx())
  check(Counts(en) == "5 levels gained | 15 bosses defeated | 1 epic find", "English: " .. Counts(en))
end

Kit.section("Honors: a crafter, a climber and a companion, each with the reason")
do
  local week = News.Week(WEEK, DE, Ctx())
  check(Honors(week) == "Meisterhand der Woche · Ilsa Brunnhold · Lederverarbeitung auf 225"
    .. " | Aufstieg der Woche · Ole Fichtental · von Stufe 40 auf 44"
    .. " | Treue Seele der Woche · Rika Steinbeck · zwei Dungeonläufe mit Gildenmitgliedern",
    "three honors in the paper's order, with name and reason (" .. Honors(week) .. ")")
  check(week and week.honors[1].key == "crafter" and week.honors[2].key == "climber" and week.honors[3].key == "companion",
    "each honor carries its rule's key")
  check(Honors(News.Week(Reversed(WEEK), DE, Ctx())) == Honors(week) and Counts(News.Week(Reversed(WEEK), DE, Ctx())) == Counts(week),
    "the same entries in another order give the same review")
  local en = News.Week(WEEK, EN, Ctx())
  check(Honors(en) == "Crafter of the week · Ilsa Brunnhold · Leatherworking up to 225"
    .. " | Climber of the week · Ole Fichtental · from level 40 to 44"
    .. " | Companion of the week · Rika Steinbeck · two dungeon runs with guildmates", "English: " .. Honors(en))
end

Kit.section("Honors: a tie goes to the name first in the alphabet, whatever order the entries came in")
do
  local tie = { Quest("Mira Sturmfeder", At(16, 9), 20), Quest("Bodo Kesselring", At(16, 9, 5), 30),
    Quest("Mira Sturmfeder", At(22, 9), 23), Quest("Bodo Kesselring", At(22, 9, 5), 33) }
  local week = News.Week(tie, DE, Ctx())
  check(Honors(week) == "Aufstieg der Woche · Bodo Kesselring · von Stufe 30 auf 33",
    "Bodo and Mira both climb three levels: Bodo is honored (" .. Honors(week) .. ")")
  check(Honors(News.Week(Reversed(tie), DE, Ctx())) == Honors(week), "and still Bodo when Mira's entries come first")
end

Kit.section("Honors: nobody is honored twice, a rule nobody qualifies for is left out")
do
  local week = News.Week({ Quest("Ole Fichtental", At(16, 10), 40),
    E("skill", "Ole Fichtental", At(18, 11), { skill = "Alchemy", rank = 150, lvl = 42 }), Quest("Ole Fichtental", At(21, 10), 44),
    Quest("Rika Steinbeck", At(17, 10), 44), Quest("Rika Steinbeck", At(21, 12), 45) }, DE, Ctx())
  check(Honors(week) == "Meisterhand der Woche · Ole Fichtental · Alchemie auf 150 | Aufstieg der Woche · Rika Steinbeck · von Stufe 44 auf 45",
    "Ole tops crafting and climbing: the climb goes to Rika, no companion honor without a shared run (" .. Honors(week) .. ")")
  local luck = News.Week({ E("loot", "Rika Steinbeck", At(18, 20), { item = 5001, q = 4, lvl = 58 }),
    E("loot", "Hanne Moosgrund", At(19, 20), { item = 5003, q = 4, lvl = 39 }),
    E("loot", "Hanne Moosgrund", At(20, 20), { item = 9999, q = 4, lvl = 39 }) }, DE, Ctx())
  check(Counts(luck) == "3 epische Funde" and Honors(luck) == "Glückspilz der Woche · Hanne Moosgrund · zwei epische Funde",
    "a week of loot only: no levels row, the luck honor goes to the most finds (" .. Counts(luck) .. "; " .. Honors(luck) .. ")")
  local single = News.Week({ E("loot", "Rika Steinbeck", At(18, 20), { item = 5001, q = 4, lvl = 58 }) }, DE, Ctx())
  check(Honors(single) == "Glückspilz der Woche · Rika Steinbeck · |cff7b2cbf[Klinge der Morgenröte]|r",
    "a single find is named, in the paper's epic colour (" .. Honors(single) .. ")")
end

Kit.section("Empty weeks: nothing to count, no review")
do
  check(News.Week({}, DE, Ctx()) == nil, "a week without entries has no review")
  local quiet = { E("mount", "Hanne Moosgrund", At(18, 12), { lvl = 40 }),
    E("rep", "Mira Sturmfeder", At(19, 19), { st = 8, fac = "Argentumdämmerung", lvl = 60 }), Quest("Mira Sturmfeder", At(20, 13), 60) }
  check(News.Week(quiet, DE, Ctx()) == nil, "a mount, a reputation and a quest without a level gained: no numbers, no review")
end

Kit.finish()
