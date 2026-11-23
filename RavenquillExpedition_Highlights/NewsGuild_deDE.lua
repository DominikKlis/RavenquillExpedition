local ADDON, ns = ...
local K = ns.NewsLocales.deDE.KINDS

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
