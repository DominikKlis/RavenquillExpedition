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
    TITLE = "Ravenquill Expedition",
    RECENT = "Latest highlights", NO_RECENT = "Nothing yet.",
    OPEN = "Open", OPEN_WINDOW = "Open %s", BACK = "« Back", OVERVIEW = "Overview", SETTINGS = "Settings", COMMAND = "Chat command: %s",
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
  },
  deDE = {
    RECENT = "Neueste Highlights", NO_RECENT = "Noch nichts.",
    OPEN = "Öffnen", OPEN_WINDOW = "%s öffnen", BACK = "« Zurück", OVERVIEW = "Übersicht", SETTINGS = "Einstellungen", COMMAND = "Chatbefehl: %s",
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
  },
})
