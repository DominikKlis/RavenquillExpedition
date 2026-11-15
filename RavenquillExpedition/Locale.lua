-- Ravenquill Expedition core: locale tables. GS.NewLocale({ enUS = {...}, deDE = {...} }) gives a table that answers
-- in the client's language, falls back to English, then to the key itself (a missing text shows its key, never nil).
-- Modules get theirs through NewModule(name, { locale = ... }) as mod.L.
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

-- The core's own texts (the /rq window).
GS.OverviewL = GS.NewLocale({
  enUS = {
    TITLE = "Ravenquill Expedition",
    MODULES = "Modules", RECENT = "Latest highlights", NO_RECENT = "Nothing yet.",
    OPEN = "Open", OPTIONS = "Options", BACK = "< Back",
    ENABLE_HINT = "Disabled – enable it in the AddOns list at character select.",
    MISSING = "Not installed.", DISABLED = "Disabled", NOT_INSTALLED = "Not installed",
    SYNC = "Guild sync: %s", SYNC_OK = "|cff33ff33ok|r", SYNC_PAUSED = "|cffff8800paused (instance)|r",
    SYNC_SLOW = "|cffff8800slow – our messages don't come back|r", SYNC_IDLE = "|cffaaaaaanothing sent yet|r",
    SYNC_DETAIL = "%d delivered, %d waiting", PEERS = "%d guildies with Ravenquill (%d online)",
    NO_GUILD = "no guild", LEGACY = "older version – update it to get its options here", LOADED = "loaded",
    NO_OPTIONS = "This module has no options.", DIAG = "Diagnostics",
    COPY_HINT = "Ctrl+A, then Ctrl+C to copy. Esc closes.",
    API_TOO_OLD = "%s needs a newer Ravenquill Expedition core (API %d, this one has %d). Update the core addon.",
  },
  deDE = {
    MODULES = "Module", RECENT = "Neueste Highlights", NO_RECENT = "Noch nichts.",
    OPEN = "Öffnen", OPTIONS = "Optionen", BACK = "< Zurück",
    ENABLE_HINT = "Deaktiviert – in der AddOn-Liste bei der Charakterauswahl einschalten.",
    MISSING = "Nicht installiert.", DISABLED = "Deaktiviert", NOT_INSTALLED = "Nicht installiert",
    SYNC = "Gilden-Sync: %s", SYNC_OK = "|cff33ff33ok|r", SYNC_PAUSED = "|cffff8800pausiert (Instanz)|r",
    SYNC_SLOW = "|cffff8800langsam – unsere Nachrichten kommen nicht zurück|r", SYNC_IDLE = "|cffaaaaaanoch nichts gesendet|r",
    SYNC_DETAIL = "%d zugestellt, %d wartend", PEERS = "%d Gildenmitglieder mit Ravenquill (%d online)",
    NO_GUILD = "keine Gilde", LEGACY = "ältere Version – aktualisieren, dann erscheinen ihre Optionen hier", LOADED = "geladen",
    NO_OPTIONS = "Dieses Modul hat keine Optionen.", DIAG = "Diagnose",
    COPY_HINT = "Strg+A, dann Strg+C zum Kopieren. Esc schließt.",
    API_TOO_OLD = "%s braucht einen neueren Ravenquill-Expedition-Kern (API %d, dieser hat %d). Bitte den Kern aktualisieren.",
  },
})
