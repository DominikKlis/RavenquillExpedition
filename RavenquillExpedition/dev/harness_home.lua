local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local WEDNESDAY_NOON = os.time({ year = 2026, month = 11, day = 18, hour = 12, min = 0, sec = 0 })
local OFFICER = 1

local sched, bus = Kit.Setup()
local function Join(name, rank)
  local c = Kit.Client(sched, bus, name, { locale = "deDE", epoch = WEDNESDAY_NOON, random = Kit.Random(#bus.clients + 5) })
  if rank then bus:setRank(name, rank) end
  c.frameMethods.SetWidth = function(s, w) s._w = w end
  return c
end
local ole, hanne = Join("Ole Fichtental", OFFICER), Join("Hanne Moosgrund")
ole.login(); hanne.login()
sched:advance(5)

local function Shown(f) return f ~= nil and rawget(f, "_shown") == true end
local function Click(b) rawget(b, "_scripts").OnClick(b) end
local function Home(c)
  if c.RQ:OverviewShown() then c.RQ:ShowHome() else c.RQ:ToggleOverview() end
  return c.env.RavenquillExpeditionOverview.home
end
local function Cards(home)
  local out = {}
  for _, card in ipairs(home.now.items) do
    if Shown(card) then out[#out + 1] = card.title:GetText() .. ": " .. card.line:GetText() .. " [" .. card.open:GetText() .. "]" end
  end
  return table.concat(out, " | ")
end
local function Rows(home)
  local out = {}
  for _, row in ipairs(home.list.items) do
    if Shown(row) then out[#out + 1] = row.title:GetText() .. ": " .. row.line:GetText() end
  end
  return table.concat(out, " | ")
end

local function Modules(c)
  local m = {}
  m.board = c.RQ:NewModule("Board", { addon = "BoardAddon", title = "Anschlagbrett" })
  function m.board:OverviewHeadline() return { line = "Nichts Neues am Brett" } end
  m.coach = c.RQ:NewModule("Coach", { addon = "CoachAddon", title = "Postkutsche" })
  function m.coach:OverviewStatus() return "2 Linien" end
  return m
end
Modules(ole)
local hanneMods = Modules(hanne)

section("Home: without a goal, members see no goal box and officers are offered one")
do
  local home = Home(hanne)
  check(not Shown(home.goal) and home.nowTitle:GetText() == "Jetzt in der Gilde",
    "a member with no goal set sees no empty goal box, the page starts with 'Jetzt in der Gilde'")
  check(Rows(home):find("Anschlagbrett: Nichts Neues am Brett | Postkutsche: 2 Linien$") and not Shown(home.now),
    "with no module offering something to do, the module rows stay as the list: " .. Rows(home))
  home = Home(ole)
  check(Shown(home.goal) and home.goal.title:GetText() == "Expeditionsziel der Woche" and Shown(home.goal.none)
    and home.goal.none:GetText() == "Für diese Woche gibt es noch kein Ziel." and Shown(home.goal.set)
    and home.goal.set:GetText() == "Ziel festlegen" and not Shown(home.goal.change) and not Shown(home.goal.bar),
    "an officer sees the goal box with 'Ziel festlegen'")
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
  check(shown == 4, "with the goal above, at most four cards fit: " .. shown)
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

check(#ole.errors + #hanne.errors == 0, "no Lua errors (" .. tostring(ole.errors[1] or hanne.errors[1]) .. ")")
Kit.finish()
