local GK = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "groupkit.lua")
local Kit = GK.Kit
local check, section = Kit.check, Kit.section

section("Loads, options, locale")
do
  local sched, bus = Kit.Setup()
  local de = GK.Login(sched, GK.Client(sched, bus, "Hanne Moosgrund", { class = "ROGUE", level = 39 }))
  local en = GK.Login(sched, GK.Client(sched, bus, "Bert Hill", { locale = "enUS" }))
  check(de.G and de.G.db and de.G.settings.announce == true, "registered as a module; SavedVariables with the announce default on")
  check(de.G.title == "Gruppensuche" and en.G.title == "Group Finder", "German and English titles")
  check(#de.G.options == 1 and de.G:Option("announce").get() == true, "one option in /rq: the chat notice")
  de.G:Option("announce").set(false)
  check(de.G.settings.announce == false, "the option writes the setting")
  local row
  for _, r in ipairs(de.RQ:OverviewRows()) do if r.name == "Groups" then row = r end end
  check(row and row.options and row.slash == "/rq groups", "listed in the /rq overview with its options under /rq groups")
  check(#de.errors == 0 and #en.errors == 0, "no Lua errors")
end

Kit.finish()
