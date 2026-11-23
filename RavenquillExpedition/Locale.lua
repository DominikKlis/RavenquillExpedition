local ADDON, ns = ...
local GS = ns.GS

function GS.NewLocale(tables)
  tables = type(tables) == "table" and tables or {}
  local client = GS.Plain(GS.SafeCall(GetLocale), "string") or "enUS"
  local own, en = tables[client] or {}, tables.enUS or {}
  return setmetatable({}, { __index = function(t, k)
    local v = own[k]
    if v == nil then v = en[k] end
    if v == nil then v = k end
    rawset(t, k, v)
    return v
  end })
end

GS.OverviewL = GS.NewLocale({
  enUS = {
    TITLE = "Ravenquill Expedition", CRAFT_TITLE = "Guild Workshop",
    OPEN = "Open", OPEN_WINDOW = "Open %s", BACK = "« Back", OVERVIEW = "Overview", SETTINGS = "Settings",
    ENABLE_HINT = "Disabled – enable it in the AddOns list at character select.",
    MISSING = "Not installed.", DISABLED = "Disabled", NOT_INSTALLED = "Not installed",
    SYNC = "Guild sync: %s", SYNC_OK = "|cff33ff33ok|r", SYNC_PAUSED = "|cffff8800paused (instance)|r",
    SYNC_SLOW = "|cffff8800slow – our messages don't come back|r", SYNC_IDLE = "|cffaaaaaanothing sent yet|r",
    SLOW_WARNING = "guild sync: our messages don't come back – sending slowly now (1 per 5 min). /rq: \"Try again now\".",
    SYNC_RETRY = "Try again now",
    SYNC_DETAIL = "%d delivered, %d waiting", PEERS = "With Ravenquill: %d in the guild, %d online",
    NO_GUILD = "no guild", LEGACY = "older version – update it to get its options here", LOADED = "loaded",
    NO_OPTIONS = "This module has no options.",
    COPY_HINT = "Ctrl+A, then Ctrl+C to copy. Esc closes.", SHOW_LAUNCHER = "Show the minimap button",
    COPY_DIAG = "Copy diagnostics",
    NEWER_VERSION = "%s runs a newer version (%s, you have %s). Update with CurseForge or WowUp.",
    NEWER_FORMAT = "%s sends guild data in a newer format than this version reads. Update with CurseForge or WowUp.",
    UPDATE_TO = "|cffff8800update to %s|r", UPDATE_ANY = "|cffff8800update available|r",
    PEER_VERSIONS = "Guildmates with Ravenquill Expedition",
    CONFIRM = "Click again to confirm",
    API_TOO_OLD = "%s needs a newer Ravenquill Expedition core (API %d, this one has %d). Update the core addon.",
    NOW_TITLE = "Now in the guild", ONLINE_TITLE = "Online now", ONLINE_MORE = "… and %d more",
    GOAL_TITLE = "Expedition goal of the week", GOAL_CHANGE = "Change", GOAL_SET = "Set a goal",
    GOAL_NONE = "No goal for this week yet.", GOAL_SET_BY = "Set by %s, until Sunday.",
    GOAL_RAID = "%s: all bosses", GOAL_RUNS = "%d dungeon runs with guildmates", GOAL_LEVELS = "%d levels for the guild",
    GOAL_UNIT_RAID = "%d of %d bosses", GOAL_UNIT_RUNS = "%d of %d runs", GOAL_UNIT_LEVELS = "%d of %d levels",
    GOAL_DONE = "Done! %s", GOAL_NO_PROGRESS = "Guild Highlights count the progress",
    GOAL_DAYS_LEFT = "%d days left", GOAL_LAST_DAY = "ends today",
    GOAL_PICK_TITLE = "Set the expedition goal of the week",
    GOAL_PICK_HINT = "Everyone with Ravenquill sees it until Sunday night. A new goal replaces the current one.",
    GOAL_PICK_RAID = "Raid: all bosses", GOAL_PICK_RUNS = "Dungeon runs with guildmates",
    GOAL_PICK_LEVELS = "Levels the whole guild gains", GOAL_RAID_LABEL = "Raid", GOAL_COUNT_LABEL = "How many",
    GOAL_APPLY = "Set this goal",
    RAID_zg = "Zul'Gurub", RAID_mc = "Molten Core", RAID_ony = "Onyxia's Lair", RAID_bwl = "Blackwing Lair",
    RAID_aq20 = "Ruins of Ahn'Qiraj", RAID_aq40 = "Temple of Ahn'Qiraj", RAID_naxx = "Naxxramas",
  },
  deDE = {
    CRAFT_TITLE = "Gildenwerkstatt",
    OPEN = "Öffnen", OPEN_WINDOW = "%s öffnen", BACK = "« Zurück", OVERVIEW = "Übersicht", SETTINGS = "Einstellungen",
    ENABLE_HINT = "Deaktiviert – in der AddOn-Liste bei der Charakterauswahl einschalten.",
    MISSING = "Nicht installiert.", DISABLED = "Deaktiviert", NOT_INSTALLED = "Nicht installiert",
    SYNC = "Gilden-Sync: %s", SYNC_OK = "|cff33ff33ok|r", SYNC_PAUSED = "|cffff8800pausiert (Instanz)|r",
    SYNC_SLOW = "|cffff8800langsam – unsere Nachrichten kommen nicht zurück|r", SYNC_IDLE = "|cffaaaaaanoch nichts gesendet|r",
    SLOW_WARNING = "Gilden-Sync: unsere Nachrichten kommen nicht zurück – sende jetzt langsam (1 alle 5 Min.). /rq: \"Jetzt erneut versuchen\".",
    SYNC_RETRY = "Jetzt erneut versuchen",
    SYNC_DETAIL = "%d zugestellt, %d wartend", PEERS = "Mit Ravenquill: %d in der Gilde, %d online",
    NO_GUILD = "keine Gilde", LEGACY = "ältere Version – aktualisieren, dann erscheinen ihre Optionen hier", LOADED = "geladen",
    NO_OPTIONS = "Dieses Modul hat keine Optionen.",
    COPY_HINT = "Strg+A, dann Strg+C zum Kopieren. Esc schließt.", SHOW_LAUNCHER = "Minimap-Knopf zeigen",
    COPY_DIAG = "Diagnose kopieren",
    NEWER_VERSION = "%s nutzt eine neuere Version (%s, du hast %s). Bitte mit CurseForge oder WowUp aktualisieren.",
    NEWER_FORMAT = "%s sendet Gildendaten in einem neueren Format, als diese Version lesen kann. Bitte mit CurseForge oder WowUp aktualisieren.",
    UPDATE_TO = "|cffff8800Update auf %s|r", UPDATE_ANY = "|cffff8800Update verfügbar|r",
    PEER_VERSIONS = "Gildenmitglieder mit Ravenquill Expedition",
    CONFIRM = "Zum Bestätigen erneut klicken",
    API_TOO_OLD = "%s braucht einen neueren Ravenquill-Expedition-Kern (API %d, dieser hat %d). Bitte den Kern aktualisieren.",
    NOW_TITLE = "Jetzt in der Gilde", ONLINE_TITLE = "Gerade online", ONLINE_MORE = "… und %d weitere",
    GOAL_TITLE = "Expeditionsziel der Woche", GOAL_CHANGE = "Ändern", GOAL_SET = "Ziel festlegen",
    GOAL_NONE = "Für diese Woche gibt es noch kein Ziel.", GOAL_SET_BY = "Festgelegt von %s, gilt bis Sonntag.",
    GOAL_RAID = "%s: alle Bosse", GOAL_RUNS = "%d Dungeonläufe mit Gildenmitgliedern", GOAL_LEVELS = "%d Stufen für die Gilde",
    GOAL_UNIT_RAID = "%d von %d Bossen", GOAL_UNIT_RUNS = "%d von %d Läufen", GOAL_UNIT_LEVELS = "%d von %d Stufen",
    GOAL_DONE = "Geschafft! %s", GOAL_NO_PROGRESS = "Den Fortschritt zählen die Gilden-Highlights",
    GOAL_DAYS_LEFT = "noch %d Tage", GOAL_LAST_DAY = "endet heute",
    GOAL_PICK_TITLE = "Expeditionsziel der Woche festlegen",
    GOAL_PICK_HINT = "Alle mit Ravenquill sehen es bis Sonntagnacht. Ein neues Ziel ersetzt das bisherige.",
    GOAL_PICK_RAID = "Schlachtzug: alle Bosse", GOAL_PICK_RUNS = "Dungeonläufe mit Gildenmitgliedern",
    GOAL_PICK_LEVELS = "Stufen, die die ganze Gilde aufsteigt", GOAL_RAID_LABEL = "Schlachtzug", GOAL_COUNT_LABEL = "Wie viele",
    GOAL_APPLY = "Dieses Ziel festlegen",
    RAID_zg = "Zul'Gurub", RAID_mc = "Geschmolzener Kern", RAID_ony = "Onyxias Hort", RAID_bwl = "Pechschwingenhort",
    RAID_aq20 = "Ruinen von Ahn'Qiraj", RAID_aq40 = "Tempel von Ahn'Qiraj", RAID_naxx = "Naxxramas",
  },
})
