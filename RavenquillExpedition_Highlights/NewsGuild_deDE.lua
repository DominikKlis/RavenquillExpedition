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
