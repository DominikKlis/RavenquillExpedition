local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local files = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Sync.lua", "RecipeSources.lua" } }))
local units = {
  player = { name="Me", class="ROGUE", level=30, guid="G-me", items={ [8]="item:2302::::" } },
  target = { name="Buddy", class="DRUID", level=28, guid="G-buddy", items={ [5]="item:2300::::", [8]="item:2302::::" } },
  party1 = { name="Mage", class="MAGE", level=30, guid="G-mage", items={} },
}
local itemMeta = {}
local sched = Kit.Scheduler()
local me = Kit.Client(sched, nil, "Me", { locale = "deDE", files = files, setup = function(env)
  env.C_ChatInfo = nil
  function env.UnitNameUnmodified(u) if u=="target" then return "Buddy","Stone" end return env.UnitName(u) end
  env.RavenquillExpeditionCraftDB = { members = { ["Old-Timer"] = { time = 5, items = {} } } }
  env.GameTooltip_Hide = function() end
  env.C_SpellBook = { IsSpellKnown = function(id) return id == 2149 or id == 2160 or id == 3762 end }
  env.RAID_CLASS_COLORS = { DRUID = {r=1,g=.49,b=.04}, ROGUE={r=1,g=.96,b=.41}, MAGE={r=.41,g=.8,b=.94} }
  env.ITEM_QUALITY_COLORS = { [1]={r=1,g=1,b=1}, [2]={r=.1,g=1,b=.1}, [3]={r=0,g=.4,b=1} }
  env.LOCALIZED_CLASS_NAMES_MALE = { DRUID="Druide", ROGUE="Schurke", MAGE="Magier" }
  function env.InCombatLockdown() return false end
  function env.IsInGuild() return true end
  function env.IsInRaid() return false end
  function env.GetNumSubgroupMembers() return 1 end
  function env.GetNumGroupMembers() return 2 end
  function env.GetRealmName() return "Realm" end
  function env.Ambiguate(n) return (n:gsub("%-Realm$","")) end
  function env.UnitName(u) local x=units[u]; return x and x.name end
  function env.UnitClass(u) local x=units[u]; return x and x.class, x and x.class end
  function env.UnitLevel(u) local x=units[u]; return x and x.level end
  function env.UnitGUID(u) local x=units[u]; return x and x.guid end
  function env.UnitIsPlayer(u) return units[u] ~= nil end
  function env.UnitIsUnit(a,b) return units[a] and units[a]==units[b] end
  function env.UnitIsInMyGuild(u) return units[u] ~= nil end
  function env.UnitExists(u) return units[u] ~= nil end
  function env.CanInspect() return true end
  function env.NotifyInspect() end
  function env.GetInventoryItemLink(u, slot) local x=units[u]; return x and x.items[slot] end
  function env.GetInventorySlotInfo(t) return 1, "tex" end
  function env.GetNumGuildMembers() return 2 end
  function env.GetGuildRosterInfo(i) if i==1 then return "Buddy Stone",nil,nil,28,nil,nil,nil,nil,true,nil,"DRUID" else return "Offy-Realm",nil,nil,50,nil,nil,nil,nil,false,nil,"ROGUE" end end
  function env.GetProfessions() return 1, nil end
  function env.GetProfessionInfo(i) return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
  env.C_Item = {
    GetItemInfoInstant = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id]; if not m then return id, "Misc","Misc","",1,15,0 end return id,"Armor","x",m.loc,1,4,m.sub end,
    GetItemInfo = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id] or {loc="",sub=0,lvl=1}; return "Item"..id, "|Hitem:"..id.."|h[Item"..id.."]|h", 2, 20, m.lvl, nil,nil,nil, m.loc, 1, nil, 4, m.sub, m.bind or 2 end,
    GetItemStats = function(link) local id = tonumber(link:match("item:(%d+)")); local m = itemMeta[id]; return m and m.stats or {} end,
    RequestLoadItemDataByID = function() end,
    GetItemNameByID = function(id) return "Reagent"..id end,
    GetItemCount = function() return 3 end,
  }
end })
local env = me.env
local RQ, ns, fire = me.RQ, me.ns[CA], me.fire
local okSy, errSy = pcall(function() Kit.loadchunk(ROOT .. "Sync.lua", env)(CA, ns) end)
io.write("Sync.lua loaded: ", tostring(okSy), " ", okSy and "" or tostring(errSy), "\n")
local GCA = ns.GCA
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", CA)
fire("PLAYER_LOGIN"); sched:flush(200)

io.write("== module registration\n")
local mod = RQ:GetModule("Craft")
check(mod and mod == GCA and mod.addon == "RavenquillExpedition_CraftAdvisor" and mod.slash == "craft" and mod.api == 2
  and mod.loaded and GCA.db == env.RavenquillExpeditionCraftDB, "GCA is the core's module \"Craft\" (api 2, addon, slash, SavedVariables loaded)")
check(env.SLASH_GUILDCRAFTADVISOR1 == nil and env.SLASH_GUILDCRAFTADVISOR2 == nil, "/gca and /guildcraft not registered on the core")
check(env.SlashCmdList.GUILDCRAFTADVISOR == nil and env.GuildCraftAdvisor == nil and env.GuildCraftAdvisor_OnCompartmentClick == nil,
  "no standalone path left: no GUILDCRAFTADVISOR slash handler, no GuildCraftAdvisor globals")
check(type(mod.Open) == "function" and type(mod.OnSlash) == "function" and type(mod.OverviewStatus) == "function", "Open, OnSlash, OverviewStatus present")

io.write("== Migrations: numbered, each once (core API 2)\n")
local db = GCA.db
check(db.v == 3 and db.keysV2 and db.inspectTalentsOffV1 and db.members["Old Timer"] and not db.members["Old-Timer"],
  "db.v = 3; [2] moved the v0.1 key \"Old-Timer\" to \"Old Timer\"; the old flags are kept")
check(db.vLogin == 2, "login migrations ran (db.vLogin = 2)")
local rdb = { keysV2 = true, members = { ["Kim Lee-Realm"] = { time = 9, items = {} }, ["Kim Lee"] = { time = 3, items = {} },
  ["Ann Bo"] = { time = 8, items = {} }, ["Ann Bo-Realm"] = { time = 2, items = {} }, ["Zed Far-OtherRealm"] = { time = 1, items = {} } },
  specs = { ["Kim Lee-Realm"] = { class = "MAGE", spec = "FIRE", ts = 4 } }, specManual = { ["Kim Lee-Realm"] = { class = "MAGE", spec = "FROST" } },
  crafted = { ["Me-Realm"] = { ["Kim Lee-Realm"] = { Leatherworking = { [1] = { item = 1, t = 1 } } } } } }
GCA.loginMigrations[2](rdb)
local ddb = { knownDiag = { login = {} }, lastError = { where = "x" }, diagSender = "S", probe = { frames = {} }, diag = { diagSender = "kept" } }
GCA.migrations[3](ddb)
local fresh = {}
GCA.migrations[3](fresh)
check(ddb.diag.knownDiag and ddb.diag.lastError.where == "x" and ddb.diag.diagSender == "kept" and ddb.knownDiag == nil and ddb.lastError == nil
  and ddb.diagSender == nil and ddb.probe == nil and fresh.diag == nil, "migration [3]: diagnostics under db.diag (none made for a clean database), probe dumps removed")
check(rdb.members["Kim Lee"].time == 9 and rdb.members["Ann Bo"].time == 8 and not rdb.members["Kim Lee-Realm"] and not rdb.members["Ann Bo-Realm"]
  and rdb.members["Zed Far-OtherRealm"] and rdb.specs["Kim Lee"] and rdb.specs["Kim Lee"].spec == "FIRE" and rdb.specManual["Kim Lee"].spec == "FROST"
  and rdb.crafted["Me-Realm"]["Kim Lee"] and not rdb.crafted["Me-Realm"]["Kim Lee-Realm"],
  "login migration [2]: keys with our own realm move to the plain key (newer wins), other realms and the character keys stay")

io.write("== options well-formed\n")
local opts = mod.options
check(type(opts) == "table" and #opts > 0, "mod.options is a non-empty list (" .. tostring(opts and #opts) .. " entries)")
local need = { header = {}, toggle = { "get", "set" }, range = { "get", "set" }, button = { "func" }, text = { "lines" } }
local bad, counts, byLabel = {}, {}, {}
for i, o in ipairs(opts or {}) do
  local req = type(o) == "table" and need[o.type]
  if not req then bad[#bad + 1] = i .. ": type " .. tostring(o and o.type)
  else
    counts[o.type] = (counts[o.type] or 0) + 1
    if type(o.label) ~= "string" or o.label == "" or o.label:match("^OPT_") then bad[#bad + 1] = i .. ": label " .. tostring(o.label) end
    for _, f in ipairs(req) do if type(o[f]) ~= "function" then bad[#bad + 1] = i .. ": " .. f end end
    if o.tooltip ~= nil and type(o.tooltip) ~= "string" then bad[#bad + 1] = i .. ": tooltip" end
    if o.disabled ~= nil and type(o.disabled) ~= "function" then bad[#bad + 1] = i .. ": disabled" end
    if o.type == "range" and not (type(o.min) == "number" and type(o.max) == "number" and type(o.step) == "number") then bad[#bad + 1] = i .. ": range bounds" end
    byLabel[o.label] = o
  end
end
check(#bad == 0, "every entry has a known type and its fields (" .. table.concat(bad, "; ") .. ")")
check(counts.header == 5 and counts.toggle == 7 and counts.range == 1 and counts.button == 7 and counts.text == 5,
  string.format("5 headers, 7 toggles, 1 range, 7 buttons, 5 text boxes (%s/%s/%s/%s/%s)", tostring(counts.header), tostring(counts.toggle),
  tostring(counts.range), tostring(counts.button), tostring(counts.text)))
local missingOpt = {}
for k in pairs(ns.missingL) do if k:match("^OPT_") then missingOpt[#missingOpt + 1] = k end end
check(#missingOpt == 0, "no missing OPT_ locale key (" .. table.concat(missingOpt, ", ") .. ")")
check(opts[1].label == "Vorschläge" and byLabel["Ziel jetzt betrachten"] and byLabel["Gruppe jetzt einlesen"]
  and byLabel["Sync erneut versuchen"] and byLabel["Ravenquill-Minimap-Knopf neu platzieren"] and byLabel["Gespeicherte Ausrüstung vergessen"],
  "German labels (deDE client)")
for _, o in ipairs(opts) do if o.disabled then local ok = pcall(o.disabled); check(ok, "disabled() runs: " .. o.label) end end

io.write("== toggles round-trip on db.settings\n")
local s = GCA.db.settings
for _, o in ipairs(opts) do
  if o.type == "toggle" then
    local v0 = o.get()
    o.set(not v0)
    local v1 = o.get()
    o.set(v0)
    check(type(v0) == "boolean" and v1 == not v0 and o.get() == v0, "toggle round-trip: " .. o.label)
  end
end
local function toggleFor(key, label)
  local o = byLabel[label]
  local before = s[key] and true or false
  o.set(not before)
  local ok = (s[key] and true or false) == not before
  o.set(before)
  return ok and (s[key] and true or false) == before
end
check(toggleFor("showUnlearned", ns.L.FILTER_UNLEARNED) and toggleFor("lookahead", ns.L.FILTER_LOOKAHEAD)
  and toggleFor("autoInspect", ns.L.FILTER_AUTOINSPECT) and toggleFor("sync", ns.L.FILTER_SYNC)
  and toggleFor("inspectTalents", ns.L.OPT_INSPECT_TALENTS), "toggles write the right db.settings keys")
local mm = byLabel[ns.L.OPT_MINIMAP]
mm.set(false)
local hid = env.RavenquillExpeditionDB.launcher.hide == true and mm.get() == false and not RQ:LauncherShown()
mm.set(true)
check(hid and not env.RavenquillExpeditionDB.launcher.hide and mm.get() == true, "minimap toggle = the suite launcher (RavenquillExpeditionDB.launcher.hide)")

io.write("== range = leveling bonus\n")
local range
for _, o in ipairs(opts) do if o.type == "range" then range = o end end
local inval, realInval = 0, GCA.InvalidateScores
GCA.InvalidateScores = function(self, ...) inval = inval + 1; return realInval(self, ...) end
range.set(25)
check(math.abs(s.survival - 0.25) < 1e-9 and range.get() == 25 and inval >= 1, "set(25) -> survival 0.25, get 25, scores invalidated")
range.set(150)
check(math.abs(s.survival - 1) < 1e-9 and range.get() == 100, "set clamps to 100")
range.set(50)
GCA.InvalidateScores = realInval
check(range.min == 0 and range.max == 100 and range.step == 5 and string.format(range.format, range.get()) == "50 %", "0-100 step 5, shows \"50 %\"")

io.write("== text boxes\n")
local wrapper = print
for _, o in ipairs(opts) do
  if o.type == "text" then
    local ok, lines = pcall(o.lines)
    local allStr = ok and type(lines) == "table" and #lines > 0
    for _, l in ipairs(ok and type(lines) == "table" and lines or {}) do
      if type(l) ~= "string" or l:find("|c%x%x%x%x%x%x%x%x") or l:find("|r", 1, true) then allStr = false end
    end
    check(allStr and print == wrapper, "lines() -> plain strings, print restored: " .. o.label .. " (" .. tostring(ok and lines[1]) .. ")")
  end
end
local cap = GCA.DiagLines(function(P) P("|cffff0000red|r line\nsecond"); error("boom") end)
check(print == wrapper and GCA.Capture == nil and cap[1] == "red line" and cap[2] == "second" and cap[3] and cap[3]:find("boom", 1, true) ~= nil,
  "diagnostic lines through a sink (no print swap): colours stripped, lines split, an error kept as the last line")
GCA:Diag().lastError = { where = "UI:Refresh", msg = "x.lua:1: oops\nstack", at = "2026-11-14 12:00:00" }
local le = byLabel[ns.L.OPT_DIAG_ERROR].lines()
check(le[1] == "2026-11-14 12:00:00  UI:Refresh" and le[2] == "x.lua:1: oops", "last error box shows db.lastError")

io.write("== OnSlash routing\n")
local calls = {}
local realOpen, realStats, realEnch = GCA.OpenWindow, GCA.StatsDebug, GCA.EnchantDebug
GCA.OpenWindow = function() calls[#calls + 1] = "open" end
GCA.StatsDebug = function(_, l) calls[#calls + 1] = "stats " .. tostring(l) end
GCA.EnchantDebug = function(_, l) calls[#calls + 1] = "enchant " .. tostring(l) end
local link = "|cnIQ3:|Hitem:9449::::::::36:1488::1::1:28:5242:::::|h[Blade]|h|r"
for _, a in ipairs({ "stats " .. link, "Enchant Debug " .. link, "enchant debug", "", "inspect", "help", "sync retry", "minimap" }) do mod:OnSlash(a) end
check(calls[1] == "stats " .. link and calls[2] == "enchant " .. link and calls[3] == "enchant nil", "stats <link> / enchant debug [link] reach the debug commands (link case kept)")
check(#calls == 8 and calls[4] == "open" and calls[5] == "open" and calls[6] == "open" and calls[7] == "open" and calls[8] == "open", "anything else (incl. empty) opens the window")
GCA.OpenWindow, GCA.StatsDebug, GCA.EnchantDebug = realOpen, realStats, realEnch

io.write("== Open shows (never closes) the window\n")
mod.Open(mod)
local shown1 = GCA.UI.frame and GCA.UI.frame:IsShown()
mod.Open(mod)
check(shown1 and GCA.UI.frame:IsShown(), "mod.Open opens the window and a second Open keeps it open")

io.write("== command texts on the core\n")
local de = ns.Locales.deDE
local leftovers = {}
for _, t in pairs(ns.Locales) do for k, v in pairs(t) do if type(v) == "string" and v:find("/gca", 1, true) then leftovers[#leftovers + 1] = k end end end
check(#leftovers == 0, "no locale text names /gca (" .. table.concat(leftovers, ", ") .. ")")
local rqKeys = {}
for _, t in pairs(ns.Locales) do for k in pairs(t) do if k:match("_RQ$") then rqKeys[#rqKeys + 1] = k end end end
check(#rqKeys == 0 and ns.L.MSG_RECORDED == de.MSG_RECORDED, "no _RQ variants of the command texts left: " .. table.concat(rqKeys, ", "))
do
  local Files = dofile(ROOT .. "dev/files.lua")
  local list = {}
  for _, f in ipairs(Files.all()) do if not f:find("^Locales/") and not f:find("^Data/") then list[#list + 1] = f end end
  local src = Files.source(list)
  local dead = {}
  for k in pairs(ns.Locales.enUS) do
    local prefix = k:match("^(STAT_)") or k:match("^(PROF_)") or k:match("^(CRAFTER_)")
    if not (src:find("%f[%w_]" .. k .. "%f[^%w_]") or (prefix and src:find('"' .. prefix .. '"', 1, true))) then dead[#dead + 1] = k end
  end
  table.sort(dead)
  check(#dead == 0, "every locale text is used by the addon (unused: " .. table.concat(dead, ", ") .. ")")
end
check(GCA.priv == nil and type(GCA.IsSecret) == "function" and type(GCA.BetterSuggestion) == "function"
  and type(GCA.SuggestionOrder) == "function" and type(GCA.PlayerFaction) == "function",
  "no private helper bag: shared helpers are named GCA fields")
local removed = { "inspect", "scan", "whisper", "minimap", "reset", "verbose", "spec", "known", "sync" }
local named = {}
for _, k in ipairs({ "SYNC_STOPPED_MSG", "MSG_RECORDED", "EMPTY_NOGEAR", "WHISPER_DRAFT_KEPT" }) do
  for _, loc in ipairs({ "enUS", "deDE" }) do
    local v = ns.Locales[loc][k]
    for _, c in ipairs(removed) do if v:find("/rq craft " .. c, 1, true) then named[#named + 1] = loc .. "." .. k .. ":" .. c end end
  end
end
check(#named == 0, "core texts name no removed command (" .. table.concat(named, ", ") .. ")")

Kit.finish()
