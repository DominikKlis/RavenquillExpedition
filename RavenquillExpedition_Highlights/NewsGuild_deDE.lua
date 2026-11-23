local ADDON, ns = ...
local K = ns.NewsLocales.deDE.KINDS
ns.NewsLocales.deDE.RAIDS = { mc = "Geschmolzener Kern", ony = "Onyxias Hort", bwl = "Pechschwingenhort" }

K.group = {
  kicker = { "Gildengruppe", "Gemeinsam unterwegs", "{?night}Nachtschicht" },
  head = { "{inst}: {names} gemeinsam unterwegs", "{names} schaffen {inst}", "Gildengruppe in {inst}",
    "{?midnight}Mitternacht in {inst}", "{!inst}{names} ziehen gemeinsam los" },
  dek = { "{people} aus der Gilde zogen gemeinsam los.", "Um {time} Uhr war die Gruppe wieder draußen.",
    "Schauplatz war {inst}." },
  body = { "Um {time} Uhr meldete die Gruppe den Abschluss. Wer gemeinsam loszieht, kommt gemeinsam zurück.",
    "{people} aus der Gilde teilten sich die Arbeit. Über die Verteilung der Beute schweigt das Gildenbuch.",
    "{?night}{!sure}Zurück waren alle {night}. Geschlafen wird vermutlich später." },
  detail = { "Um {time} Uhr war die Gruppe wieder draußen.", "Schauplatz war {inst}.", "Mit dabei: {names}." },
  more = { "Die Redaktion gratuliert.", "Die Reparaturkosten bleiben, wie immer, Privatsache.",
    "{!sure}Die nächste Gildengruppe dürfte nicht lange auf sich warten lassen." },
  caption = { "{inst}", "Gildengruppe" },
  brief = { "{inst}: {names} gemeinsam unterwegs.", "{names} schaffen {inst}.", "Gildengruppe: {names}." },
  again = { "{gap} eine Gildengruppe in {inst}.", "{gap} eine Gildengruppe." },
}

K.clear = {
  kicker = { "Schlachtzug", "Gecleart", "{?night}Nachtschicht" },
  head = { "{inst}: Die Gilde räumt auf", "Die Gilde cleart {inst}", "{inst} gecleart",
    "{?midnight}Mitternacht in {inst}: alles erledigt", "{!inst}Die Gilde meldet einen kompletten Clear" },
  dek = { "Kein Boss blieb stehen.", "{grp} aus der Gilde waren dabei.", "Um {time} Uhr fiel der letzte Gegner.",
    "Schauplatz war {inst}." },
  body = { "Um {time} Uhr fiel der Endboss. Danach gab es dort nichts mehr zu tun.",
    "{grp} aus der Gilde standen im Aufgebot. Gemeldet hat es {name}.",
    "{?night}{!sure}Der letzte Gegner fiel {night}. Der Schlaf dürfte heute kürzer ausfallen." },
  detail = { "Um {time} Uhr fiel der letzte Gegner.", "{grp} aus der Gilde standen im Aufgebot.", "Schauplatz war {inst}." },
  more = { "Die Beute wird, wie üblich, nach eingehender Beratung verteilt.",
    "Die Reparaturkosten bleiben, wie immer, Privatsache.", "{!sure}Nächste Woche dürfte es wieder losgehen." },
  caption = { "{inst}", "Schlachtzug" },
  brief = { "{inst}: Die Gilde cleart den Schlachtzug.", "{inst} gecleart.", "Ein Schlachtzug gecleart." },
  again = { "{gap} ein Clear in {inst}.", "{gap} ein kompletter Clear." },
}

K.ready = {
  kicker = { "Raidbereit", "Einstimmung geschafft", "{?names}Verstärkung für den Schlachtzug" },
  head = { "{name} ist raidbereit für {raid}", "{names} sind raidbereit für {raid}", "{raid}: {name} hat die Einstimmung",
    "{raid}: {names} haben die Einstimmung", "{!raid}{name} ist raidbereit", "{!raid}{names} sind raidbereit" },
  dek = { "Der letzte Schritt der Einstimmung ist geschafft.", "Um {time} Uhr war es so weit.", "{name} war dabei Stufe {clvl}." },
  body = { "Um {time} Uhr meldete das Gildenbuch den letzten Schritt. Der Weg in den Schlachtzug ist frei.",
    "Die Einstimmung ist geschafft. Ab sofort zählt beim Gildenraid ein Platz mehr.",
    "{?night}Der letzte Schritt fiel {night}. Für Einstimmungen gibt es offenbar keine Sperrstunde." },
  detail = { "Um {time} Uhr war es so weit.", "{name} war dabei Stufe {clvl}." },
  more = { "Die Redaktion gratuliert.", "{!sure}Die Raidleitung dürfte sich freuen.",
    "Wer noch einen Schritt braucht, sieht es unter Raidbereitschaft." },
  caption = { "{raid}", "Raidbereit" },
  brief = { "{name} ist raidbereit für {raid}.", "{names} sind raidbereit für {raid}.", "{name} ist raidbereit.",
    "{names} sind raidbereit." },
  again = { "{gap} raidbereit für {raid}.", "{gap} raidbereit." },
}

K.first = {
  kicker = { "Gildenpremiere", "Zum ersten Mal", "{?lvl}Vor allen anderen" },
  head = { "{?lvl}Gildenpremiere: {name} erreicht Stufe {lvl}", "{?lvl}Vor allen anderen: {name} auf Stufe {lvl}",
    "{?boss}Gildenpremiere: {boss} besiegt", "{?boss}{boss} fällt zum ersten Mal", "{?boss}{inst}: {boss} fällt zum ersten Mal",
    "{!lvl}{!boss}Eine Premiere für die Gilde" },
  dek = { "{?lvl}Niemand in der Gilde war bisher so weit.", "{?boss}Diesen Gegner hatte die Gilde noch nie besiegt.",
    "Um {time} Uhr war es so weit.", "{grp} aus der Gilde waren dabei." },
  body = { "{?lvl}Um {time} Uhr meldete das Gildenbuch Stufe {lvl}. Noch nie war jemand aus der Gilde so weit gekommen.",
    "{?boss}Um {time} Uhr fiel {boss}. Ein Sieg, den es in der Gilde vorher nicht gab.",
    "Um {time} Uhr war es so weit. Ein Tag, den sich die Gilde merken wird.",
    "{?night}Die Premiere kam {night}. Für Geschichte gibt es offenbar keine Sperrstunde." },
  detail = { "Um {time} Uhr war es so weit.", "{grp} aus der Gilde standen im Aufgebot.", "Schauplatz war {inst}." },
  more = { "Die Redaktion gratuliert und verneigt sich.", "{!sure}Die anderen dürften bald folgen.",
    "Das Gildenbuch hat eine neue erste Seite." },
  caption = { "Gildenpremiere", "{?lvl}Stufe {lvl}", "{boss}" },
  brief = { "{?lvl}Gildenpremiere: {name} erreicht Stufe {lvl}.", "{?boss}Gildenpremiere: {boss} besiegt.",
    "Eine Premiere für die Gilde." },
  again = { "{?lvl}{gap} als Premiere Stufe {lvl}.", "{gap} eine Premiere für die Gilde." },
}
