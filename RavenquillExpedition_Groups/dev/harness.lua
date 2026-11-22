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

Kit.finish()
