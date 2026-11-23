local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, Layout, At, E, Ctx = NK.Kit, NK.Layout, NK.At, NK.E, NK.Ctx
local check = Kit.check

NK.sched:advance(At(22, 21, 30) - NK.NOW)
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

Kit.section("Sunday: the paper's calendar finds the Sunday, its week number and its Monday")
do
  local function Sunday(t)
    local s = News.Sunday(t)
    return s and (s.from .. " KW " .. s.no) or "-"
  end
  check(Sunday(At(22, 0, 1)) == "2026-11-16 KW 47" and Sunday(At(22, 23, 59)) == "2026-11-16 KW 47",
    "Sunday 22 November, from 00:01 to 23:59: week 47, which began on Monday the 16th (" .. Sunday(At(22, 0, 1)) .. ")")
  check(Sunday(At(21, 23, 59)) == "-" and Sunday(At(23, 0, 1)) == "-", "Saturday and Monday are no Sundays")
  check(Sunday(os.time({ year = 2027, month = 1, day = 3, hour = 12 })) == "2026-12-28 KW 53"
    and Sunday(os.time({ year = 2026, month = 1, day = 4, hour = 12 })) == "2025-12-29 KW 1",
    "around New Year the week numbers follow ISO 8601: week 53 of 2026, week 1 of 2026")
  check(Sunday(os.time({ year = 2026, month = 10, day = 25, hour = 0, min = 30 })) == "2026-10-19 KW 43",
    "the Sunday the clocks go back is still week 43 from Monday the 19th")
end

local function Joined(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e end
  return out
end

Kit.section("Sunday edition: the Sunday issue reviews its Monday to Sunday, other issues review nothing")
do
  local entries = Joined(WEEK)
  entries[#entries + 1] = Quest("Mira Sturmfeder", At(15, 10), 50)
  entries[#entries + 1] = Raid("Tamo Eichengrund", At(15, 21), "Onyxia", 1084)
  local days = News.Days(entries, News.DayOf)
  local function Edition(day)
    for i, d in ipairs(days) do if d.day == day then return News.SundayEdition(days, i, DE, Ctx()) end end
    return "no issue"
  end
  local this, last = Edition("2026-11-22"), Edition("2026-11-15")
  check(this and this.no == 47 and Counts(this) == Counts(News.Week(WEEK, DE, Ctx())) and Honors(this) == Honors(News.Week(WEEK, DE, Ctx())),
    "the issue of Sunday the 22nd reviews week 47, without the 15th (" .. Counts(this) .. ")")
  check(last and last.no == 46 and Counts(last) == "1 Boss besiegt", "the issue of Sunday the 15th reviews week 46 (" .. Counts(last) .. ")")
  check(Edition("2026-11-21") == nil and Edition("2026-11-16") == nil, "the Saturday and Monday issues have no review")
end

local SPEC = { side = 34, sidePad = 18 }

local function LayoutClient(locale, extra)
  return NK.Client("Lyra Distelbach", locale, function(env, c)
    Layout.Install(c)
    Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
    c.frameMethods.SetDesaturated = function(s, on) s._desaturated = on end
    c.frameMethods.SetVertexColor = function(s, r, g, b) s._tint = { r, g, b } end
    c.frameMethods.SetTextColor = function(s, r, g, b) s._ink = { r, g, b } end
    c.frameMethods.SetJustifyH = function(s, j) s._justify = j end
    if extra then extra(env, c) end
  end)
end

local function Paper(entries, locale, extra)
  local c = LayoutClient(locale, extra)
  for _, e in ipairs(entries) do c.H:Add(e, "wire") end
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  return c, f, f.paper
end

local function R(region) return Layout.Rect(region) end

local function SideTexts(c, paper)
  local rule, out = R(paper.sideRule), {}
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    local r = R(fs)
    if r.left > rule.right and r.top <= rule.top + 0.5 then out[#out + 1] = fs end
  end
  table.sort(out, function(a, b)
    local ra, rb = R(a), R(b)
    if math.abs(ra.top - rb.top) > 0.5 then return ra.top > rb.top end
    return ra.left < rb.left
  end)
  return out
end

local function Read(list)
  local out = {}
  for i, fs in ipairs(list) do out[i] = fs._text end
  return table.concat(out, " / ")
end

local function Group(who, t, inst, with, lvl) return E("group", who, t, { inst = inst, with = { with }, grp = true, lvl = lvl }) end

local function WorldBoss(who, t, inst, boss, enc) return E("boss", who, t, { inst = inst, boss = boss, enc = enc, first = true, lvl = 60 }) end

local SHOWN_WEEK = {
  E("level", "Ole Fichtental", At(16, 10), { lvl = 40 }),
  Group("Rika Steinbeck", At(17, 19), "Uldaman", "Ole Fichtental", 44),
  E("skill", "Ilsa Brunnhold", At(18, 11), { skill = "Leatherworking", rank = 300, lvl = 36 }),
  E("rep", "Ole Fichtental", At(19, 22), { st = 8, fac = "Argentumdämmerung", lvl = 44 }),
  WorldBoss("Tamo Eichengrund", At(20, 21, 20), "Azshara", "Azuregos", 1100),
  WorldBoss("Bodo Kesselring", At(20, 21, 50), "Verwüstete Lande", "Lord Kazzak", 1101),
  E("loot", "Rika Steinbeck", At(21, 20), { item = 5001, q = 4, lvl = 45 }),
  E("mount", "Hanne Moosgrund", At(22, 12), { lvl = 40 }),
  Group("Hanne Moosgrund", At(22, 15), "Zul'Farrak", "Rika Steinbeck", 40),
}

local REVIEW_DE = "Die Woche in Zahlen / 5 / Stufen gewonnen / 2 / Bosse besiegt / 1 / epischer Fund"
  .. " / MEISTERHAND DER WOCHE / Ilsa Brunnhold / Lederverarbeitung auf 300 / AUFSTIEG DER WOCHE / Ole Fichtental"
  .. " / von Stufe 40 auf 44 / TREUE SEELE DER WOCHE / Rika Steinbeck / zwei Dungeonläufe mit Gildenmitgliedern"

Kit.section("Window: the Sunday paper prints the week in numbers and the honors instead of In Kürze")
do
  local c, f, paper = Paper(SHOWN_WEEK)
  check(paper.meta.mid:GetText() == "Sonntag, 22. November", "the latest issue is Sunday's (" .. paper.meta.mid:GetText() .. ")")
  local side = Read(SideTexts(c, paper))
  check(side == REVIEW_DE, "the side column reads the review top to bottom (" .. side .. ")")
  check(f.issueLabel:GetText() == "Sonntagsausgabe · KW 47", "the footer calls it the Sunday edition of week 47 (" .. f.issueLabel:GetText() .. ")")
  f.prev:GetScript("OnClick")(f.prev)
  local saturday = Read(SideTexts(c, paper))
  check(saturday:find("^In Kürze / ") and not saturday:find("Woche", 1, true) and f.issueLabel:GetText() == "Ausgabe vom 21. November",
    "Saturday's issue has the normal In Kürze column and footer (" .. saturday .. ")")
  f.next:GetScript("OnClick")(f.next)
  check(Read(SideTexts(c, paper)) == REVIEW_DE and f.issueLabel:GetText() == "Sonntagsausgabe · KW 47", "and back on Sunday the review")
  local en, ef, ep = Paper(SHOWN_WEEK, "enUS")
  local english = Read(SideTexts(en, ep))
  check(english:find("^The week in numbers / 5 / levels gained / 2 / bosses defeated / 1 / epic find / CRAFTER OF THE WEEK / ")
    and ef.issueLabel:GetText() == "Sunday edition · week 47", "English: " .. english .. " · " .. ef.issueLabel:GetText())
  check(#c.errors == 0 and #en.errors == 0, "no Lua errors (" .. tostring(c.errors[1] or en.errors[1]) .. ")")
end

Kit.section("Window: a Sunday after a week with nothing to count keeps the normal paper")
do
  local c, f, paper = Paper({ E("mount", "Hanne Moosgrund", At(18, 12), { lvl = 40 }),
    E("rep", "Mira Sturmfeder", At(22, 11), { st = 8, fac = "Argentumdämmerung", lvl = 60 }) })
  local side = Read(SideTexts(c, paper))
  check(paper.meta.mid:GetText() == "Sonntag, 22. November" and side:find("^In Kürze / ") and not side:find("Woche", 1, true),
    "Sunday's side column is In Kürze (" .. side .. ")")
  check(f.issueLabel:GetText() == "Ausgabe vom 22. November", "and the footer names the date (" .. f.issueLabel:GetText() .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Window: the Sunday edition reviews only what the Chronik shows, not the entries the rules hide")
do
  local c, _, paper = Paper({
    E("level", "Ole Fichtental", At(16, 10), { lvl = 40 }),
    E("skill", "Ilsa Brunnhold", At(18, 11), { skill = "Leatherworking", rank = 225, lvl = 36 }),
    Quest("Ole Fichtental", At(19, 22), 44),
    Raid("Tamo Eichengrund", At(20, 21, 20), "Lucifron", 663),
    Raid("Tamo Eichengrund", At(20, 21, 50), "Magmadar", 664),
    E("loot", "Rika Steinbeck", At(21, 20), { item = 5001, q = 4, lvl = 45 }),
    E("mount", "Ole Fichtental", At(22, 12), { lvl = 42 }),
  })
  check(#c.H:Log() == 7 and #c.H:ShownLog() == 3, "all seven entries are kept, the Chronik shows three of them ("
    .. #c.H:Log() .. ", " .. #c.H:ShownLog() .. ")")
  local side = Read(SideTexts(c, paper))
  check(side == "Die Woche in Zahlen / 2 / Stufen gewonnen / 1 / epischer Fund / AUFSTIEG DER WOCHE / Ole Fichtental"
    .. " / von Stufe 40 auf 42 / GLÜCKSPILZ DER WOCHE / Rika Steinbeck / |cff7b2cbf[Klinge der Morgenröte]|r",
    "the hidden quest, raid kill records and leatherworking step count for nothing (" .. side .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local function Offenders(c, paper, texts)
  local pr, out = R(paper), {}
  for _, fs in ipairs(texts or Layout.Texts(c, paper)) do
    local r = R(fs)
    if not (r and Layout.Inside(pr, r)) or Layout.Truncated(fs) then out[#out + 1] = fs._text:sub(1, 50) end
  end
  return out
end

local function Overlapping(list)
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = R(list[i]), R(list[j])
      if a.left < b.right - 0.5 and b.left < a.right - 0.5 and a.bottom < b.top - 0.5 and b.bottom < a.top - 0.5 then
        return list[i]._text .. " / " .. list[j]._text
      end
    end
  end
end

local function InColumn(paper, list)
  local left, right = R(paper.sideRule).right + SPEC.sidePad * paper.scale - 0.5, R(paper).right - SPEC.side + 0.5
  for _, fs in ipairs(list) do
    local r = R(fs)
    if r.left < left or r.right > right then return fs._text end
  end
end

local function RowsBesideFigures(paper)
  local n = 0
  for _, row in ipairs(paper.week.rows) do
    if row.label:IsShown() then
      local fig, label = R(row.figure), R(row.label)
      if not (label.left > fig.right and label.top <= fig.top + 0.5 and label.bottom >= fig.bottom - 0.5) then return false end
      n = n + 1
    end
  end
  return n > 0
end

local function RuleBetween(paper, side)
  local rule, kicker = R(paper.week.rule), nil
  for _, fs in ipairs(side) do if fs == paper.week.honors[1].title then kicker = R(fs) end end
  local lastRow
  for _, row in ipairs(paper.week.rows) do if row.label:IsShown() then lastRow = R(row.figure) end end
  return kicker and lastRow and paper.week.rule:IsShown() and rule.top <= lastRow.bottom and rule.bottom >= kicker.top
end

local function Fits(c, paper, tag)
  local off, side = Offenders(c, paper), SideTexts(c, paper)
  check(#off == 0, "every text is on the page and shown in full" .. tag .. " (" .. (off[1] or "none") .. ")")
  local overlap, outside = Overlapping(side), InColumn(paper, side)
  check(overlap == nil and outside == nil, "the review's texts do not overlap and stay inside the column" .. tag .. " ("
    .. tostring(overlap or outside) .. ")")
  check(RowsBesideFigures(paper) and RuleBetween(paper, side),
    "each label sits beside its figure, a rule runs between the numbers and the honors" .. tag)
end

Kit.section("Layout: the review fits its column at full size, on a small screen and in English")
do
  local c, f, paper = Paper(SHOWN_WEEK)
  Fits(c, paper, " at 900 px")
  local low = math.huge
  for _, fs in ipairs(Layout.Texts(c, paper)) do low = math.min(low, R(fs).bottom) end
  local fr, spare = R(f), low - R(f.footerRule).top
  check(fr.height <= 780 and fr.height >= c.H.WINDOW_MIN_H and spare >= 0 and spare < 60,
    ("the sheet grows to hold the review and ends just under its last text (%.0f px high, %.0f px spare)"):format(fr.height, spare))
  local small, _, sp = Paper(SHOWN_WEEK, "deDE", function(env) Layout.Pin(env.UIParent, 0, 0, 1024, 600) end)
  Fits(small, sp, " on a 1024x600 screen")
  check(Read(SideTexts(small, sp)) == REVIEW_DE, "with all three honors")
  local en, _, ep = Paper(SHOWN_WEEK, "enUS")
  Fits(en, ep, " in English")
  check(#c.errors + #small.errors + #en.errors == 0, "no Lua errors")
end

Kit.section("Layout: on a very short sheet the honors that do not fit are left out whole")
do
  local c = LayoutClient()
  for _, e in ipairs(SHOWN_WEEK) do c.H:Add(e, "wire") end
  c.H.WINDOW_W, c.H.WINDOW_H = 640, 395
  c.H:ShowWindow()
  local paper = c.env.RavenquillExpeditionHighlightsFrame.paper
  local off, side = Offenders(c, paper, SideTexts(c, paper)), Read(SideTexts(c, paper))
  check(#off == 0, "every text of the review stays on the page (" .. (off[1] or "none") .. ")")
  check(side:find("^Die Woche in Zahlen / 5 / Stufen gewonnen / 2 / Bosse besiegt / 1 / epischer Fund / MEISTERHAND DER WOCHE / ")
    and not side:find("TREUE SEELE", 1, true), "the numbers stay, the last honors are dropped (" .. side .. ")")
  local whole = true
  for _, h in ipairs(c.env.RavenquillExpeditionHighlightsFrame.paper.week.honors) do
    if h.title:IsShown() ~= h.who:IsShown() or h.who:IsShown() ~= h.why:IsShown() then whole = false end
  end
  check(whole, "an honor is shown with its title, name and reason, or not at all")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.finish()
