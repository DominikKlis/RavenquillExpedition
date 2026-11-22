local ADDON, ns = ...
ns.Locales = ns.Locales or {}

ns.Locales.deDE = {
  TITLE = "Gruppensuche",
  OPT_ANNOUNCE = "Im Chat melden, wenn jemand eine Gruppe in meinem Stufenbereich sucht",
  OPT_ANNOUNCE_TIP = "Eine Zeile pro neuem Gesuch, das zu deiner Stufe passt. Anmeldungen für dein eigenes Gesuch siehst du immer.",

  ROLE_tank = "Tank", ROLE_heal = "Heiler", ROLE_dps = "Schaden",
  RAID_TITLE = "Gildenraid: %s",
  LEVEL_RANGE = "Stufe %d-%d",
  TODAY = "Heute", TOMORROW = "Morgen", WHEN = "%s %s",
  WEEKDAY_1 = "Sonntag", WEEKDAY_2 = "Montag", WEEKDAY_3 = "Dienstag", WEEKDAY_4 = "Mittwoch",
  WEEKDAY_5 = "Donnerstag", WEEKDAY_6 = "Freitag", WEEKDAY_7 = "Samstag",
  AGO_NOW = "gerade eben", AGO_MIN = "vor %d min", AGO_HOURS = "vor %d h",

  ANNOUNCE = "%s sucht für %s: %s. Anmelden unter /rq groups",
  ANNOUNCE_RAID = "%s plant %s, %s. Zusagen unter /rq groups",
  SIGNUP_NOTE = "%s meldet sich als %s an. Einladen unter /rq groups",
  WHISPER = "Hallo! Ich melde mich für %s an, als %s. (Ravenquill)",
  WHISPER_WHEN = "Hallo! Ich sage für %s am %s zu, als %s. (Ravenquill)",

  ZONE_389 = "Der Flammenschlund", ZONE_43 = "Die Höhlen des Wehklagens", ZONE_36 = "Die Todesminen",
  ZONE_33 = "Burg Schattenfang", ZONE_48 = "Tiefschwarze Grotte", ZONE_34 = "Das Verlies", ZONE_90 = "Gnomeregan",
  ZONE_47 = "Kral der Klingenhauer", ZONE_189 = "Scharlachrotes Kloster", ZONE_129 = "Hügel der Klingenhauer",
  ZONE_70 = "Uldaman", ZONE_209 = "Zul'Farrak", ZONE_349 = "Maraudon", ZONE_109 = "Der Tempel von Atal'Hakkar",
  ZONE_230 = "Schwarzfelstiefen", ZONE_429 = "Düsterbruch", ZONE_329 = "Stratholme", ZONE_289 = "Scholomance",
  ZONE_309 = "Zul'Gurub", ZONE_509 = "Ruinen von Ahn'Qiraj", ZONE_409 = "Geschmolzener Kern", ZONE_249 = "Onyxias Hort",
  ZONE_469 = "Pechschwingenhort", ZONE_531 = "Tempel von Ahn'Qiraj", ZONE_533 = "Naxxramas",
  WING_GRAVEYARD = "Friedhof", WING_LIBRARY = "Bibliothek", WING_ARMORY = "Waffenkammer", WING_CATHEDRAL = "Kathedrale",
  WING_EAST = "Ost", WING_WEST = "West", WING_NORTH = "Nord",
  ACT_LBRS = "Untere Schwarzfelsspitze", ACT_UBRS = "Obere Schwarzfelsspitze",
}
