-- Strings: English defaults, German overrides. Same pattern as the Highlights module's Locale.lua.
-- Never pass a client global (e.g. ERR_*) to string.format: deDE uses positional "%1$s".
local ADDON, ns = ...

local L = {
  TITLE = "Guild Map",
  NOTICE = "Guild Map shares your position with your guild (only guildmates who run it see it). You can turn this off in |cffffff00/rq|r → Map.",

  -- tooltip
  TT_LEVEL_CLASS = "Level %d %s",
  TT_AGE_S = "Updated %d s ago",
  TT_AGE_M = "Updated %d min ago",
  TT_STATIONARY = "Standing still",
  TT_TAXI = "On a flight path",
  TT_GHOST = "Dead",
  TT_STALE = "Position is old",
  TT_TEST = "Test pin (not a real player)",
  TT_YOU = "You (test pin)",
  TT_CLICK = "Click to whisper",

  ON = "on", OFF = "off",
  FAKE_NOPOS = "Your position isn't available here (instance?), so no test pins.",
  OV_STATUS = "On the map: %d · sharing %s",
  OV_SLOW = " · your messages aren't getting through",
  SLOW_MODE = "Your position messages aren't coming back from the server – sending only every 5 min until they do.",

  SEC_SHARING = "Sharing",
  SEC_DISPLAY = "Display",
  SEC_TESTING = "Testing",
  SETTING_SHARE = "Share my position with the guild",
  TT_SHARE = "Guildmates who run this addon see where you are. Nothing is sent in instances or in combat.",
  SETTING_WORLDMAP = "Show guildmates on the world map",
  SETTING_MINIMAP = "Show guildmates on the minimap",
  TT_MINIMAP = "Only positions under 45 seconds old, or of guildmates standing still – older ones would be in the wrong place.",
  SETTING_NAMES = "Names under the dots",
  SETTING_SIZE = "Dot size",
  SETTING_SELF = "Test dot at my own position",
  TT_SELF = "A white-ringed dot where you are, to check that dots land in the right place.",
  SETTING_FAKE = "Test dots around me",
  TT_FAKE = "Seven pretend guildmates around you, only on your screen – nothing is sent.",
  SETTING_DIAG = "Diagnostics",
  TT_DIAG = "Technical details to copy and send to whoever helps you with the addon.",
}

local deDE = {
  TITLE = "Gildenkarte",
  NOTICE = "Die Gildenkarte teilt deine Position mit deiner Gilde (nur Gildenmitglieder, die sie nutzen, sehen sie). Abschalten kannst du das unter |cffffff00/rq|r → Karte.",

  TT_LEVEL_CLASS = "Stufe %d %s",
  TT_AGE_S = "Vor %d s aktualisiert",
  TT_AGE_M = "Vor %d Min. aktualisiert",
  TT_STATIONARY = "Steht still",
  TT_TAXI = "Auf einer Flugroute",
  TT_GHOST = "Tot",
  TT_STALE = "Position ist veraltet",
  TT_TEST = "Testpunkt (kein echter Spieler)",
  TT_YOU = "Du (Testpunkt)",
  TT_CLICK = "Klicken zum Anflüstern",

  ON = "an", OFF = "aus",
  FAKE_NOPOS = "Deine Position ist hier nicht verfügbar (Instanz?), daher keine Testpunkte.",
  OV_STATUS = "Auf der Karte: %d · Teilen %s",
  OV_SLOW = " · deine Nachrichten kommen nicht an",
  SLOW_MODE = "Deine Positionsnachrichten kommen nicht vom Server zurück – es wird nur noch alle 5 Min. gesendet, bis sie wieder ankommen.",

  SEC_SHARING = "Teilen",
  SEC_DISPLAY = "Anzeige",
  SEC_TESTING = "Testen",
  SETTING_SHARE = "Meine Position mit der Gilde teilen",
  TT_SHARE = "Gildenmitglieder, die dieses Addon nutzen, sehen, wo du bist. In Instanzen und im Kampf wird nichts gesendet.",
  SETTING_WORLDMAP = "Gildenmitglieder auf der Weltkarte zeigen",
  SETTING_MINIMAP = "Gildenmitglieder auf der Minikarte zeigen",
  TT_MINIMAP = "Nur Positionen, die jünger als 45 Sekunden sind, oder von Gildenmitgliedern, die stillstehen – ältere wären an der falschen Stelle.",
  SETTING_NAMES = "Namen unter den Punkten",
  SETTING_SIZE = "Punktgröße",
  SETTING_SELF = "Testpunkt an meiner Position",
  TT_SELF = "Ein weiß umrandeter Punkt, wo du stehst – um zu prüfen, ob die Punkte an der richtigen Stelle landen.",
  SETTING_FAKE = "Testpunkte um mich herum",
  TT_FAKE = "Sieben gespielte Gildenmitglieder um dich herum, nur auf deinem Bildschirm – nichts wird gesendet.",
  SETTING_DIAG = "Diagnose",
  TT_DIAG = "Technische Angaben zum Kopieren für alle, die dir beim Addon helfen.",
}

if GetLocale() == "deDE" then
  for k, v in pairs(deDE) do L[k] = v end
end

-- Missing keys fall back to the key itself, so a typo shows up instead of erroring.
ns.L = setmetatable(L, { __index = function(_, k) return k end })
