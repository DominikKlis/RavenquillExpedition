local GK = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "groupkit.lua")
local Kit = GK.Kit
local check, section = Kit.check, Kit.section

section("Loads, options, locale")
do
  local sched, _, _, by = GK.Guild({ { "Hanne Moosgrund", "ROGUE", 39 }, { "Bert Hill", "WARRIOR", 40, locale = "enUS" } })
  local de, en = by["Hanne Moosgrund"], by["Bert Hill"]
  check(de.G and de.G.db and de.G.settings.announce == true, "registered as a module; SavedVariables with the announce default on")
  check(de.G.title == "Gruppensuche" and en.G.title == "Group Finder", "German and English titles")
  check(#de.G.options == 1 and de.G:Option("announce").get() == true, "one option in /rq: the chat notice")
  de.G:Option("announce").set(false)
  check(de.G.settings.announce == false, "the option writes the setting")
  en.G:Post(GK.Spec(en, "smcath", {}))
  sched:advance(10)
  check(GK.PostOf(de, "Bert Hill") and de.printedMatch("Bert Hill sucht") == nil,
    "chat notice off: Hanne gets Bert's fitting post but no chat line")
  de.G:Option("announce").set(true)
  en.G:Post(GK.Spec(en, "smarm", { tank = 1 }))
  sched:advance(10)
  check(de.printedMatch("Bert Hill sucht für Scharlachrotes Kloster: Waffenkammer: Heiler, Schaden.") ~= nil,
    "chat notice on: one line for his next post")
  de.G:Post(GK.Spec(de, "smcath", { dps = 2 }))
  sched:advance(10)
  check(en.printedMatch("Hanne Moosgrund is looking for Scarlet Monastery: Cathedral: Tank, Healer, DPS. Sign up in /rq groups")
    ~= nil, "the English client says it in English")
  local row
  for _, r in ipairs(de.RQ:OverviewRows()) do if r.name == "Groups" then row = r end end
  check(row and row.options and row.slash == "/rq groups", "listed in the /rq overview with its options under /rq groups")
  check(#de.errors == 0 and #en.errors == 0, "no Lua errors")
end

local LYRA = { "Lyra Distelbach", "MAGE", 40, "Wald von Elwynn" }
local HANNE = { "Hanne Moosgrund", "ROGUE", 39, "Arathihochland" }
local RIKA = { "Rika Steinbeck", "WARRIOR", 58, "Brennende Steppe" }
local MIRA = { "Mira Sturmfeder", "PRIEST", 60, "Östliche Pestländer" }
local WEEKDAYS = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

local function RaidTime(now, days, hour)
  local d = os.date("*t", now)
  return now - (d.hour * 3600 + d.min * 60 + d.sec) + days * 86400 + hour * 3600
end

local function Scene(viewer)
  local sched, bus, cs, by = GK.Guild({ viewer or LYRA, HANNE, RIKA, MIRA })
  local rika, hanne, mira = by["Rika Steinbeck"], by["Hanne Moosgrund"], by["Mira Sturmfeder"]
  local raidAt = RaidTime(mira.RQ:Now(), 2, 20)
  mira.G:Post(GK.Spec(mira, "mc", { tank = 2, heal = 5, dps = 7 }, { when = raidAt, note = "Einstimmung nötig" }))
  rika.G:Post(GK.Spec(rika, "scholo", { tank = 1, dps = 1 }))
  sched:advance(360)
  hanne.G:Post(GK.Spec(hanne, "smcath", { heal = 1, dps = 1 }))
  sched:advance(180)
  return sched, bus, cs, by, raidAt
end

local function Errors(cs)
  for _, c in ipairs(cs) do if #c.errors > 0 then return c.name .. ": " .. tostring(c.errors[1]) end end
  return "none"
end

section("The /rq page: every post as a card with its roles")
do
  local sched, _, cs, by, raidAt = Scene()
  local lyra = by["Lyra Distelbach"]
  local page = GK.OpenPage(lyra)
  local cards = GK.Cards(lyra)
  check(GK.Shown(page) and #cards == 3 and GK.Shown(page.find) and page.find:GetText() == "Gruppe suchen"
    and not GK.Shown(page.empty), "Lyra's Gruppensuche page shows three cards and the 'Gruppe suchen' button")
  local h, r, m = cards[1], cards[2], cards[3]
  check(h.title:GetText() == "Scharlachrotes Kloster: Kathedrale" and h.total:GetText() == "2/5"
    and GK.Plain(h.line:GetText()) == "Hanne Moosgrund  39 · Stufe 35-45 · Arathihochland · vor 3 min",
    "newest dungeon first: title, 2/5 filled, poster with level, level range, zone and age: " .. GK.Plain(h.line:GetText()))
  check(h.line:GetText():find("|cfffff569Hanne Moosgrund|r", 1, true) ~= nil, "the poster's name in her class colour")
  check(GK.PillTexts(h) == "Tank gesucht [wanted], Heiler " .. CHECK .. " [full], Schaden 1/3 [part]",
    "role pills: tank wanted, healer filled, dps 1/3: " .. GK.PillTexts(h))
  check(GK.Shown(h.tag) and h.tag.text:GetText() == "Passt zu deiner Stufe" and h.tag.style == "fit",
    "'Passt zu deiner Stufe' on the Kathedrale (35-45) for Lyra (40)")
  check(GK.Shown(h.action) and h.action:GetText() == "Anmelden" and h.action:IsEnabled() and not GK.Shown(h.close),
    "an enabled 'Anmelden' button, no poster buttons")
  check(r.title:GetText() == "Scholomance" and not GK.Shown(r.tag) and GK.Plain(r.line:GetText()):find("vor 9 min$")
    and GK.PillTexts(r) == "Tank " .. CHECK .. " [full], Heiler gesucht [wanted], Schaden 1/3 [part]",
    "Scholomance (58-60) next, without the level pill: " .. GK.PillTexts(r))
  local d = os.date("*t", raidAt)
  local raidLine = "Mira Sturmfeder  60 · " .. WEEKDAYS[d.wday] .. " 20:00 · Einstimmung nötig"
  check(m.title:GetText() == "Gildenraid: Geschmolzener Kern" and m.total:GetText() == "14/40"
    and GK.Plain(m.line:GetText()) == raidLine and m.action:GetText() == "Zusagen",
    "the raid last: 'Gildenraid: Geschmolzener Kern', 14/40, day and time and note, 'Zusagen': " .. GK.Plain(m.line:GetText()))
  check(GK.PillTexts(m) == "Tank 2/4 [part], Heiler 5/8 [part], Schaden 7/28 [part]", "raid pills count every slot")
  check(lyra.G:OverviewStatus() == "3 Gruppen offen · 3 online",
    "the page's status line: three groups open, three guildmates with Ravenquill online: " .. lyra.G:OverviewStatus())
  sched:advance(3600 - 180 + 31)
  check(#GK.Cards(lyra) == 1 and GK.Cards(lyra)[1].title:GetText() == "Gildenraid: Geschmolzener Kern"
    and lyra.G:OverviewStatus() == "1 Gruppe offen · 3 online", "an hour later only the raid is left on the open page")
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

section("Signing up from the page")
do
  local sched, _, cs, by = Scene()
  local lyra, hanne, rika = by["Lyra Distelbach"], by["Hanne Moosgrund"], by["Rika Steinbeck"]
  GK.OpenPage(lyra)
  local h = GK.Cards(lyra)[1]
  GK.Click(h.action)
  local menu = lyra.menus[1] and GK.Menu(lyra.menus[1].gen, h.action)
  check(menu and menu[1].text == "Anmelden als" and #menu == 3 and menu[2].text == "Tank" and menu[3].text == "Schaden",
    "'Anmelden' with two open roles asks which: Tank or Schaden (the healer slot is full)")
  GK.Pick(menu, "Schaden")
  sched:advance(10)
  local own = GK.PostOf(hanne, "Hanne Moosgrund")
  check(own.signups[1] and own.signups[1].who == "Lyra Distelbach" and own.signups[1].role == "dps"
    and GK.Counts(own) == "0/1 1/1 2/3", "Hanne's post now lists Lyra as dps, 2/3")
  check(lyra.whispers[1] and lyra.whispers[1].target == "Hanne Moosgrund", "and Lyra whispered Hanne")
  h = GK.Cards(lyra)[1]
  check(h.action:GetText() == "Angemeldet" and not h.action:IsEnabled() and GK.PillTexts(h):find("Schaden 2/3", 1, true),
    "Lyra's card turns into a greyed 'Angemeldet', her slot counted: " .. GK.PillTexts(h))
  rika.G:Post(GK.Spec(rika, "scholo", { tank = 1, dps = 3 }))
  sched:advance(10)
  local r = GK.Cards(lyra)[1]
  check(r.title:GetText() == "Scholomance", "Rika's edit is the newest post now and moves to the top")
  local menus = #lyra.menus
  GK.Click(r.action)
  sched:advance(10)
  local rikas = GK.PostOf(rika, "Rika Steinbeck")
  check(#lyra.menus == menus and rikas.signups[1] and rikas.signups[1].role == "heal",
    "with one open role (healer) 'Anmelden' signs up right away, no menu")
  check(GK.Cards(lyra)[1].action:GetText() == "Angemeldet", "and that card reads 'Angemeldet' too")

  local page = GK.OpenPage(hanne)
  local mine = GK.Cards(hanne)[1]
  check(mine.title:GetText() == "Scharlachrotes Kloster: Kathedrale" and mine.tag.text:GetText() == "Dein Gesuch"
    and not GK.Shown(mine.action) and GK.Shown(mine.edit) and GK.Shown(mine.close),
    "Hanne sees her own post first, marked 'Dein Gesuch', with 'Ändern' and 'Schließen' instead of 'Anmelden'")
  check(GK.Shown(mine.rows[1]) and mine.rows[1].text:GetText() == "Lyra Distelbach · Schaden"
    and mine.rows[1].invite:GetText() == "Einladen", "under the pills: Lyra as dps with an 'Einladen' button")
  GK.Click(mine.rows[1].invite)
  check(hanne.invites[1] == "Lyra Distelbach", "one click invites Lyra")
  check(page.find:GetText() == "Gesuch ändern", "the header button offers to edit her post")
  GK.Click(mine.close)
  sched:advance(10)
  check(hanne.G:OwnPost() == nil and GK.PostOf(lyra, "Hanne Moosgrund") == nil and #GK.Cards(lyra) == 2,
    "'Schließen' takes the post down for everyone")
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

section("The post form")
do
  local sched, _, cs, by = Scene()
  local lyra, hanne = by["Lyra Distelbach"], by["Hanne Moosgrund"]
  local page = GK.OpenPage(lyra)
  local form = page.form
  GK.Click(page.find)
  check(GK.Shown(form) and not GK.Shown(page.list) and not GK.Shown(page.find) and form.title:GetText() == "Neues Gesuch",
    "'Gruppe suchen' opens the form in place of the list")
  check(form.draft.activity == "smarm" and form.submit:GetText() == "Posten",
    "it starts on the first dungeon that fits Lyra's level (Waffenkammer, 32-42)")
  local menu = GK.Menu(form.activity._gen, form.activity)
  local titles, radios = {}, 0
  for _, e in ipairs(menu) do if e.kind == "title" then titles[#titles + 1] = e.text else radios = radios + 1 end end
  check(table.concat(titles, ", ") == "Dungeons, Schlachtzüge" and radios == #lyra.A.LIST,
    "the activity menu lists every dungeon, then every raid")
  GK.Pick(menu, "Scharlachrotes Kloster: Kathedrale (35-45)")
  check(form.draft.activity == "smcath" and form.roles.dps.value:GetText() == "0/3", "picking the Kathedrale shows its slots")
  GK.Click(form.roles.dps.plus)
  GK.Click(form.roles.dps.plus)
  GK.Click(form.roles.tank.plus)
  GK.Click(form.roles.tank.plus)
  check(form.roles.dps.value:GetText() == "2/3" and form.roles.tank.value:GetText() == "1/1"
    and not form.roles.tank.plus:IsEnabled() and form.roles.heal.value:GetText() == "0/1" and not form.roles.heal.minus:IsEnabled(),
    "steppers count who is already in, and stop at the role's slots")
  check(not GK.Shown(form.day) and not GK.Shown(form.whenLabel), "a dungeon has no start time")
  form.note:SetText("Bring Tränke; mit | Strich")
  GK.Click(form.submit)
  sched:advance(10)
  local atHanne = GK.PostOf(hanne, "Lyra Distelbach")
  check(atHanne and atHanne.activity == "smcath" and GK.Counts(atHanne) == "1/1 0/1 2/3"
    and atHanne.note == "Bring Tränke mit  Strich" and lyra.G:OwnPost().note == atHanne.note,
    "'Posten' sends it: Hanne gets the roles and the note, cleaned the same at both ends")
  check(not GK.Shown(form) and GK.Shown(page.list) and page.find:GetText() == "Gesuch ändern" and #GK.Cards(lyra) == 4,
    "the form closes, the list shows Lyra's post on top")
  GK.Click(page.find)
  check(form.title:GetText() == "Gesuch ändern" and form.draft.activity == "smcath" and form.roles.dps.value:GetText() == "2/3"
    and form.note:GetText() == "Bring Tränke mit  Strich" and form.submit:GetText() == "Aktualisieren",
    "'Gesuch ändern' opens the form filled with her post")
  GK.Pick(GK.Menu(form.activity._gen, form.activity), "Geschmolzener Kern")
  check(GK.Shown(form.day) and GK.Shown(form.time.value) and form.roles.dps.value:GetText() == "2/28",
    "a raid shows the start row and the raid's slots")
  local now = lyra.RQ:Now()
  local days = GK.Menu(form.day._gen, form.day)
  check(#days == 7 and days[1].text == "Heute" and days[2].text == "Morgen"
    and days[3].text == WEEKDAYS[os.date("*t", now + 2 * 86400).wday], "the start day: today, tomorrow, then weekdays")
  days[3].fn(days[3].data)
  GK.Click(form.time.plus)
  GK.Click(form.time.plus)
  check(form.time.value:GetText() == "21:00", "the time steps by half hours from 20:00")
  GK.Click(form.submit)
  sched:advance(10)
  local raid = GK.PostOf(hanne, "Lyra Distelbach")
  check(raid and raid.activity == "mc" and raid.kind == "raid" and raid.when == RaidTime(now, 2, 21),
    "the raid goes out for the day after tomorrow, 21:00")
  GK.Click(page.find)
  form.draft.day, form.draft.minutes = 0, 0
  GK.Click(form.submit)
  check(GK.Shown(form) and form.error:GetText() == "Der Termin liegt in der Vergangenheit."
    and lyra.G:OwnPost().when == raid.when, "a start in the past is refused with a reason")
  GK.Click(form.cancel)
  check(not GK.Shown(form) and GK.Shown(page.list), "'Abbrechen' goes back to the list")
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

section("/rq home: one headline")
do
  local sched, _, cs, by = Scene()
  local lyra, hanne, rika, mira = by["Lyra Distelbach"], by["Hanne Moosgrund"], by["Rika Steinbeck"], by["Mira Sturmfeder"]
  local function Head(c) return c.G:OverviewHeadline().line end
  check(Head(lyra) == "Hanne Moosgrund sucht für Scharlachrotes Kloster · passt zu dir",
    "a post that fits comes first, the dungeon without its wing so the line fits the row: " .. Head(lyra))
  rika.G:Post(GK.Spec(rika, "scholo", { tank = 1, dps = 2 }))
  sched:advance(10)
  check(Head(lyra) == "Hanne Moosgrund sucht für Scharlachrotes Kloster · passt zu dir",
    "still Hanne's after Rika's newer post, which does not fit Lyra: " .. Head(lyra))
  hanne.G:Close()
  sched:advance(10)
  check(Head(lyra) == "Rika Steinbeck sucht für Scholomance", "otherwise the newest dungeon: " .. Head(lyra))
  lyra.RQ:ToggleOverview()
  local row
  for _, item in ipairs(lyra.env.RavenquillExpeditionOverview.home.list.items) do
    if GK.Shown(item) and item.title:GetText() == "Gruppensuche" then row = item end
  end
  check(row and row.line:GetText() == Head(lyra),
    "with nothing that fits Lyra to sign up for, the /rq home's module row for Gruppensuche shows the headline")
  GK.Click(row)
  check(lyra.RQ.optionsModule == "Groups" and GK.Shown(lyra.G.page), "clicking the row opens the Gruppensuche page")
  rika.G:Close()
  sched:advance(10)
  check(Head(lyra):find("^Mira Sturmfeder plant Geschmolzener Kern · %a+ 20:00$"), "otherwise the next raid: " .. Head(lyra))
  mira.G:Close()
  sched:advance(10)
  check(Head(lyra) == "Gerade sucht niemand eine Gruppe", "nothing open: " .. Head(lyra))
  lyra.G:Post(GK.Spec(lyra, "smarm", {}))
  sched:advance(10)
  check(Head(lyra) == "Dein Gesuch für Scharlachrotes Kloster ist offen", "your own post: " .. Head(lyra))
  hanne.G:SignUp("Lyra Distelbach", "tank")
  sched:advance(10)
  check(Head(lyra) == "Hanne Moosgrund hat sich für dein Gesuch angemeldet (Tank)", "a sign-up for it comes first: " .. Head(lyra))
  rika.G:SignUp("Lyra Distelbach", "dps")
  sched:advance(10)
  check(Head(lyra) == "2 Anmeldungen für dein Gesuch", "two sign-ups: " .. Head(lyra))
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

section("/rq home: a group that fits you, and sign-ups for yours, are rows in 'Jetzt in der Gilde'")
do
  local sched, _, cs, by = Scene()
  local lyra, hanne, rika = by["Lyra Distelbach"], by["Hanne Moosgrund"], by["Rika Steinbeck"]
  local function Rows(c)
    local out = {}
    for i, r in ipairs(c.G:OverviewNow()) do out[i] = r.title .. ": " .. r.line .. " [" .. r.action .. "]" end
    return table.concat(out, " | ")
  end
  check(Rows(lyra) == "Gruppensuche: Hanne Moosgrund sucht für Scharlachrotes Kloster · passt zu dir [Anmelden]"
    and lyra.G:OverviewNow()[1].ends == GK.PostOf(lyra, "Hanne Moosgrund").expires,
    "Lyra gets one row for the post that fits her, with 'Anmelden', ending with the post: " .. Rows(lyra))
  check(Rows(rika) == "", "Rika has an open post without sign-ups and nothing fits her level: no row")
  lyra.RQ:ToggleOverview()
  local home = lyra.env.RavenquillExpeditionOverview.home
  local card = home.now.items[1]
  check(card and GK.Shown(card) and card.title:GetText() == "Gruppensuche" and card.open:GetText() == "Anmelden",
    "the home shows it as a card")
  GK.Click(card.open)
  local menu = lyra.menus[1] and GK.Menu(lyra.menus[1].gen, card.open)
  check(menu and menu[1].text == "Anmelden als" and lyra.menus[1].owner == card.open,
    "'Anmelden' on the home asks for the role in a menu at the card's button")
  GK.Pick(menu, "Tank")
  sched:advance(10)
  local own = GK.PostOf(hanne, "Hanne Moosgrund")
  check(own.signups[#own.signups].who == "Lyra Distelbach" and own.signups[#own.signups].role == "tank",
    "picking Tank signs Lyra up for Hanne's post")
  lyra.RQ:ShowHome()
  check(not GK.Shown(card) or card.title:GetText() ~= "Gruppensuche", "signed up, the row goes from Lyra's home")
  check(Rows(hanne) == "Gruppensuche: Lyra Distelbach hat sich für dein Gesuch angemeldet (Tank) [Ansehen]",
    "Hanne gets a row for the sign-up: " .. Rows(hanne))
  hanne.G:OverviewNow()[1].open()
  check(hanne.RQ.optionsModule == "Groups" and GK.Shown(hanne.G.page), "'Ansehen' opens her Gruppensuche page to invite")
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

section("English")
do
  local _, _, cs, by = Scene({ "Lyra Distelbach", "MAGE", 40, "Elwynn Forest", locale = "enUS" })
  local lyra = by["Lyra Distelbach"]
  GK.OpenPage(lyra)
  local h, m = GK.Cards(lyra)[1], GK.Cards(lyra)[3]
  check(lyra.G:OverviewHeadline().line == "Hanne Moosgrund is looking for Scarlet Monastery · fits you",
    "the headline in English")
  check(h.title:GetText() == "Scarlet Monastery: Cathedral"
    and GK.Plain(h.line:GetText()) == "Hanne Moosgrund  39 · Level 35-45 · Arathihochland · 3 min ago"
    and GK.PillTexts(h):find("^Tank wanted") and h.tag.text:GetText() == "Fits your level" and h.action:GetText() == "Sign up",
    "the card in English: " .. GK.Plain(h.line:GetText()))
  check(m.title:GetText() == "Guild raid: Molten Core" and m.action:GetText() == "I'm in"
    and GK.PillTexts(m):find("DPS 7/28", 1, true), "the raid card in English")
  check(lyra.G:OverviewStatus() == "3 groups open · 3 online" and lyra.G.page.find:GetText() == "Find group",
    "status and button")
  check(Errors(cs) == "none", "no Lua errors (" .. Errors(cs) .. ")")
end

Kit.finish()
