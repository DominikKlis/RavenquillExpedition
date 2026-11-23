local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local Layout = dofile(DEV .. "../../RavenquillExpedition_Highlights/dev/layout.lua")
local check, section = Kit.check, Kit.section

local WEDNESDAY_NOON = os.time({ year = 2026, month = 11, day = 18, hour = 12, min = 0, sec = 0 })
local OFFICER = 1
local COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }

local sched, bus = Kit.Setup()
local function Join(name, rank, class)
  local c = Kit.Client(sched, bus, name, { locale = "deDE", epoch = WEDNESDAY_NOON, random = Kit.Random(#bus.clients + 5),
    class = class, setup = function(env, cl)
      Layout.Install(cl)
      Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
      env.RAID_CLASS_COLORS = COLORS
      cl.frameMethods.SetTextColor = function(s, r, g, b) s._ink = { r, g, b } end
    end })
  if rank then bus:setRank(name, rank) end
  return c
end
local ole, hanne = Join("Ole Fichtental", OFFICER, "DRUID"), Join("Hanne Moosgrund", nil, "ROGUE")
bus:member("Rika Steinbeck", "WARRIOR", 58, true, "Brennende Steppe")
bus:member("Bodo Kesselring", "PALADIN", 52, false, "Winterquell")
bus:member("Ilsa Brunnhold", "MAGE", 36, true, "Rotkammgebirge")
for _, r in ipairs(bus.roster) do if r.name == "Ole Fichtental" then r.zone = "Tanaris" end end
ole.login(); hanne.login()
sched:advance(5)

local function Shown(f) return f ~= nil and rawget(f, "_shown") == true end
local function Click(b) rawget(b, "_scripts").OnClick(b) end
local function Plain(s)
  return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
local function Home(c)
  if c.RQ:OverviewShown() then c.RQ:ShowHome() else c.RQ:ToggleOverview() end
  return c.env.RavenquillExpeditionOverview.home
end
local function Lists(home)
  local out = { home.now, home.list, home.online }
  for _, list in pairs(home.feeds) do out[#out + 1] = list end
  return out
end
local function Headings(home)
  local shown = {}
  for _, list in ipairs(Lists(home)) do if Shown(list) and Shown(list.heading) then shown[#shown + 1] = list.heading end end
  table.sort(shown, function(a, b) return Layout.Rect(a).top > Layout.Rect(b).top end)
  local out = {}
  for i, h in ipairs(shown) do out[i] = h:GetText() end
  return table.concat(out, " | "), shown[1]
end
local function Items(list, text)
  local out = {}
  for _, item in ipairs(list.items) do if Shown(item) then out[#out + 1] = text(item) end end
  return table.concat(out, " | ")
end
local function Cards(home)
  return Items(home.now, function(card) return card.title:GetText() .. ": " .. card.line:GetText() .. " [" .. card.open:GetText() .. "]" end)
end
local function Rows(home) return Items(home.list, function(row) return row.title:GetText() .. ": " .. row.line:GetText() end) end
local function Online(home)
  return Items(home.online, function(row) return Plain(row.name:GetText()) .. " " .. row.level:GetText() .. " " .. row.zone:GetText() end)
end
local function Feed(list) return Items(list, function(row) return Plain(row.text:GetText()) end) end

local function Modules(c)
  local m = {}
  m.board = c.RQ:NewModule("Board", { addon = "BoardAddon", title = "Anschlagbrett" })
  function m.board:BuildPage() end
  function m.board:OverviewHeadline() return { line = "Nichts Neues am Brett" } end
  m.coach = c.RQ:NewModule("Coach", { addon = "CoachAddon", title = "Postkutsche" })
  function m.coach:OverviewStatus() return "2 Linien" end
  return m
end
Modules(ole)
local hanneMods = Modules(hanne)

section("Home: a member with no goal and no officer rank sees the guild now, the newest notices and who is online")
do
  local asked
  function hanneMods.board:OverviewFeed(max)
    asked = max
    local rows = {}
    for i = 1, 7 do rows[i] = { t = WEDNESDAY_NOON - i * 600, text = "|cffff7d0aOle|r · Aushang " .. i, highlight = i == 2 } end
    rows[5].t = WEDNESDAY_NOON - 2 * 86400
    rows[6] = { text = "ohne Zeit" }
    return { title = "Neu am Brett", rows = rows }
  end
  local home = Home(hanne)
  local feed = home.feeds.Board
  check(not Shown(home.goal) and Headings(home) == "Jetzt in der Gilde | Neu am Brett | Gerade online",
    "no goal box; the sections read 'Jetzt in der Gilde', the module's feed, then 'Gerade online': " .. Headings(home))
  check(Rows(home):find("Anschlagbrett: Nichts Neues am Brett | Postkutsche: 2 Linien$") and not Shown(home.now),
    "with no module offering something to do, 'Jetzt in der Gilde' lists the modules: " .. Rows(home))
  check(asked == 5 and Feed(feed) == "11:50 » Ole · Aushang 1 | 11:40 » Ole · Aushang 2 | 11:30 » Ole · Aushang 3 | "
    .. "11:20 » Ole · Aushang 4 | 16.11. » Ole · Aushang 5",
    "the feed asks for five lines and shows them as time » text, today's by the clock, older ones by the date; a line without a time is left out: "
    .. Feed(feed))
  local glowing = {}
  for i, row in ipairs(feed.items) do if Shown(row) and Shown(row.glow[1]) then glowing[#glowing + 1] = i end end
  check(table.concat(glowing, ",") == "2", "only the line marked as a highlight glows gold (" .. table.concat(glowing, ",") .. ")")
  check(Online(home) == "Ilsa Brunnhold 36 Rotkammgebirge | Ole Fichtental 33 Tanaris | Rika Steinbeck 58 Brennende Steppe",
    "'Gerade online' lists the guildmates online by name with level and zone, not Hanne herself and not Bodo, who is offline: "
    .. Online(home))
  local oleRow = home.online.items[2]
  check(oleRow and oleRow.name._ink and oleRow.name._ink[1] == 1 and oleRow.name._ink[2] == 0.49,
    "each name in its class colour (Ole the druid in orange)")
  local sync = {}
  for _, fs in ipairs(Layout.Texts(hanne, home)) do if Plain(fs._text):find("Gilden-Sync", 1, true) then sync[#sync + 1] = fs._text end end
  check(#sync == 0 and table.concat(hanne.RQ:DiagLines(), "\n"):find("\nGilden-Sync: noch nichts gesendet\n", 1, true),
    "the sync line is not on the home, the diagnostics carry it (" .. table.concat(sync, " / ") .. ")")
  Click(feed.items[3])
  check(select(2, hanne.RQ:OverviewShown()) == "Board", "a click on a feed line opens the module's page")
end

section("Home: without a goal, officers are offered one above the same sections")
do
  local home = Home(ole)
  local headings, first = Headings(home)
  check(Shown(home.goal) and home.goal.title:GetText() == "Expeditionsziel der Woche" and Shown(home.goal.none)
    and home.goal.none:GetText() == "Für diese Woche gibt es noch kein Ziel." and Shown(home.goal.set)
    and home.goal.set:GetText() == "Ziel festlegen" and not Shown(home.goal.change) and not Shown(home.goal.bar),
    "an officer sees the goal box with 'Ziel festlegen'")
  check(headings == "Jetzt in der Gilde | Gerade online" and Layout.Rect(home.goal.title).top - Layout.Rect(first).top >= 56,
    "the sections follow below the goal box: " .. headings)
end

section("Home: the officer's goal picker")
do
  local home = Home(ole)
  Click(home.goal.set)
  local picker = home.picker
  local controls = picker.panel.controls
  local raid, setRaid, runs, setRuns = controls[2], controls[3], controls[5], controls[6]
  check(Shown(picker) and not Shown(home.book) and picker.title:GetText() == "Expeditionsziel der Woche festlegen"
    and raid.value:GetText() == "Geschmolzener Kern" and runs.value:GetText() == "10" and controls[8].value:GetText() == "25",
    "'Ziel festlegen' opens the picker: a raid (Molten Core first), 10 runs, 25 levels")
  Click(picker.back)
  check(not Shown(picker) and Shown(home.book) and ole.RQ:Goal() == nil, "'« Zurück' leaves without setting anything")
  Click(home.goal.set)
  Click(raid.plus)
  check(raid.value:GetText() == "Onyxias Hort", "'+' steps to the next raid: " .. tostring(raid.value:GetText()))
  Click(setRaid)
  local goal = ole.RQ:Goal()
  check(goal and goal.kind == "raid" and goal.raid == "ony" and goal.setBy == "Ole Fichtental" and not Shown(picker)
    and Shown(home.book), "'Dieses Ziel festlegen' sets 'Onyxia: all bosses' and goes back to the home")
  check(home.goal.label:GetText() == "Onyxias Hort: alle Bosse" and home.goal.left:GetText() == "noch 5 Tage"
    and Shown(home.goal.bar) and Shown(home.goal.change) and not Shown(home.goal.set),
    "the home shows the goal, the days left of the week (Wednesday: 5) and 'Ändern' for the officer")
  Click(home.goal.change)
  check(Shown(picker) and raid.value:GetText() == "Onyxias Hort", "'Ändern' reopens the picker on the current goal")
  Click(runs.plus); Click(runs.plus)
  Click(setRuns)
  goal = ole.RQ:Goal()
  check(goal and goal.kind == "runs" and goal.target == 12 and home.goal.label:GetText() == "12 Dungeonläufe mit Gildenmitgliedern",
    "a number of runs, raised twice from 10, replaces the raid: " .. tostring(home.goal.label:GetText()))
  sched:advance(15)
  local other = Home(hanne)
  check(Shown(other.goal) and other.goal.label:GetText() == "12 Dungeonläufe mit Gildenmitgliedern"
    and not Shown(other.goal.change) and not Shown(other.goal.set),
    "a member's home shows the officer's goal read-only, without 'Ändern' or 'Ziel festlegen'")
end

section("Home: the progress bar reads the modules' GoalProgress")
do
  local home = Home(hanne)
  local bar = home.goal.bar
  check(bar.text:GetText() == "Den Fortschritt zählen die Gilden-Highlights" and not Shown(bar.fill),
    "with no module counting, the bar says who would count it: " .. tostring(bar.text:GetText()))
  local done = 3
  function hanneMods.board:GoalProgress(goal) if goal.kind == "runs" then return done, goal.target end end
  Home(hanne)
  check(bar.text:GetText() == "3 von 12 Läufen" and Shown(bar.fill) and math.abs(bar.fill._w - 410 * 3 / 12) < 0.01,
    "a module's count fills the bar: " .. tostring(bar.text:GetText()) .. ", " .. tostring(bar.fill._w))
  done = 7
  Home(hanne)
  check(bar.text:GetText() == "7 von 12 Läufen" and math.abs(bar.fill._w - 410 * 7 / 12) < 0.01, "more runs move the bar on")
  done = 15
  Home(hanne)
  check(bar.text:GetText() == "Geschafft! 12 von 12 Läufen" and math.abs(bar.fill._w - 410) < 0.01,
    "reaching the target says so and the bar stays full: " .. tostring(bar.text:GetText()))
  hanneMods.board.GoalProgress = nil
end

section("Home: 'Jetzt in der Gilde' lists what modules offer to do now, one action each")
do
  local now, opened, line = hanne.RQ:Now(), {}, "2 Aushänge für dich"
  function hanneMods.board:OverviewNow()
    return { { title = "Anschlagbrett", line = line, action = "Lesen", open = function(b) opened[#opened + 1] = { "Brett", b } end },
      { title = "Ohne Knopf", line = "nichts zu tun" } }
  end
  function hanneMods.coach:OverviewNow()
    return { { title = "Postkutsche", line = "fährt in 5 min", action = "Einsteigen", ends = now + 300,
      open = function() opened[#opened + 1] = { "Kutsche" } end } }
  end
  local home = Home(hanne)
  check(Cards(home) == "Postkutsche: fährt in 5 min [Einsteigen] | Anschlagbrett: 2 Aushänge für dich [Lesen]"
    and Shown(home.now) and not Shown(home.list),
    "each module's rows are cards with their one action; what ends soonest comes first; rows without an action are left out: "
    .. Cards(home))
  local card = home.now.items[2]
  Click(card.open)
  check(#opened == 1 and opened[1][1] == "Brett" and opened[1][2] == card.open,
    "the card's button runs the row's open, handing it the button (to anchor a menu)")
  line = "3 Aushänge für dich"
  home = Home(hanne)
  check(Cards(home):find("Anschlagbrett: 3 Aushänge für dich [Lesen]", 1, true), "the rows are read anew on each refresh")
  function hanneMods.coach:OverviewNow()
    local out = {}
    for i = 1, 7 do out[i] = { title = "Kutsche " .. i, line = "Halt " .. i, action = "Einsteigen", ends = now + i, open = function() end } end
    return out
  end
  home = Home(hanne)
  local shown = select(2, Cards(home):gsub("%[", ""))
  check(shown == 2 and Headings(home) == "Jetzt in der Gilde | Neu am Brett | Gerade online",
    "at most two cards, so the feed and the online list keep their room: " .. shown .. " cards; " .. Headings(home))
  check(select(2, Feed(home.feeds.Board):gsub("»", "")) == 3 and select(2, Online(home):gsub(" | ", "")) == 2,
    "under the goal and two cards, the feed and the online list each keep three lines: " .. Online(home))
  function hanneMods.coach:OverviewNow() error("Kutsche kaputt") end
  local errorsBefore = #hanne.errors
  home = Home(hanne)
  check(Cards(home) == "Anschlagbrett: 3 Aushänge für dich [Lesen]" and #hanne.errors == errorsBefore + 1,
    "a failing hook reaches BugSack and the other modules' rows stay: " .. Cards(home))
  hanne.errors[#hanne.errors] = nil
  function hanneMods.board:OverviewNow() return {} end
  hanneMods.coach.OverviewNow = nil
  home = Home(hanne)
  check(not Shown(home.now) and Shown(home.list) and Rows(home):find("Anschlagbrett: Nichts Neues am Brett | Postkutsche: 2 Linien$"),
    "when no module has anything to do, the module rows come back as the list: " .. Rows(home))
end

section("Home: a crowded guild still gets its online list, ending in how many more there are")
do
  for i = 1, 20 do bus:member(("Gast %02d"):format(i), "MAGE", 20 + i, true, "Dämmerwald") end
  hanne.fire("GUILD_ROSTER_UPDATE")
  local home = Home(hanne)
  local names = {}
  for _, row in ipairs(home.online.items) do if Shown(row) then names[#names + 1] = row.name:GetText() end end
  local more = names[#names]
  check(Shown(home.goal) and #names >= 2 and more == ("… und %d weitere"):format(23 - #names + 1) and names[1] == "Gast 01",
    "with a goal, five module rows and the feed above, the online list still shows the first names and then '… und N weitere': "
    .. table.concat(names, ", "))
  check(Headings(home) == "Jetzt in der Gilde | Neu am Brett | Gerade online", "all three sections stay: " .. Headings(home))
end

section("Home: a feed with no lines is left out")
do
  function hanneMods.board:OverviewFeed() return { title = "Neu am Brett", rows = {} } end
  local home = Home(hanne)
  check(Headings(home) == "Jetzt in der Gilde | Gerade online", "a feed with no lines has no heading: " .. Headings(home))
end

check(#ole.errors + #hanne.errors == 0, "no Lua errors (" .. tostring(ole.errors[1] or hanne.errors[1]) .. ")")
Kit.finish()
