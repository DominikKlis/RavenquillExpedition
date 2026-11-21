local ADDON, ns = ...
local RQ = RavenquillExpedition
local Dev = ns.Dev

local ping = Dev.pingChannel or Dev.mod:NewChannel({ tag = "~T", version = 1 })
Dev.pingChannel = ping
ping:Define("ping", { fields = { { "n", "int", 0, 4102444800 } } })
Dev:Register("comm.echo", function(t)
  local can, why = RQ:CanSend()
  t:note("state: " .. RQ:CommStatus())
  if not can then t:ok(false, "can send: " .. tostring(why)) t:done() return end
  ping:Send("ping", { n = time() }, { onResult = function(status)
    t:ok(status == "delivered", "own message came back: " .. tostring(status))
    t:done()
  end })
end, 150)

Dev:Register("ui.overview", function(t)
  if RQ:OverviewShown() then RQ:ToggleOverview() end
  RQ:ToggleOverview()
  local shown, opt = RQ:OverviewShown()
  t:ok(shown and opt == nil, "/rq opens the home view")
  local rows = RQ:OverviewRows()
  t:ok(type(rows) == "table" and #rows >= #RQ.moduleOrder - 1, ("overview rows: %d for %d modules"):format(#rows, #RQ.moduleOrder))
  RQ:ToggleOverview()
  t:ok(not RQ:OverviewShown(), "/rq again closes it")
  t:done()
end)

Dev:Register("ui.options", function(t)
  for _, name in ipairs(RQ.moduleOrder) do
    local m = RQ.modules[name]
    if type(m.options) == "table" and m.options[1] then
      local ok, err = pcall(RQ.ShowModuleOptions, RQ, name)
      local shown, opt = RQ:OverviewShown()
      t:ok(ok and shown and opt == name, ("options of %s open (%d entries)%s"):format(name, #m.options, ok and "" or (": " .. tostring(err))))
    end
  end
  if RQ:OverviewShown() then RQ:ToggleOverview() end
  if RQ:OverviewShown() then RQ:ToggleOverview() end
  t:done()
end)

Dev:Register("map.pins", function(t)
  local M = rawget(_G, "RavenquillExpeditionMap")
  if not M then t:note("Map not loaded") t:done() return end
  local was = M.fakeOn
  M:Fake(true)
  local n = 0
  for _, m in pairs(M.members or {}) do if m.fake then n = n + 1 end end
  t:ok(n > 0, "test pins created: " .. n)
  if not was then M:Fake(false) end
  t:done()
end)

Dev:Register("craft.window", function(t)
  local mod = RQ:GetModule("Craft")
  if not mod then t:note("CraftAdvisor not loaded") t:done() return end
  local function state()
    local f = rawget(_G, "RavenquillExpeditionCraftFrame")
    return f and (f:IsShown() and "shown" or "hidden") or "no frame"
  end
  local db = rawget(_G, "RavenquillExpeditionCraftDB")
  local errBefore = db and db.diag and db.diag.lastError and db.diag.lastError.at
  t:note("before Open: " .. state() .. ", combat " .. tostring(InCombatLockdown and InCombatLockdown()))
  local ok, err = pcall(mod.Open, mod)
  t:ok(ok, "Open() runs" .. (ok and "" or (": " .. tostring(err))))
  t:note("right after Open: " .. state())
  local le = db and db.diag and db.diag.lastError
  if le and le.at ~= errBefore then t:note("CraftAdvisor recorded an error: " .. tostring(le.msg)) end
  t:after(1, function()
    t:note("1 s later: " .. state())
    local f = rawget(_G, "RavenquillExpeditionCraftFrame")
    t:ok(f and f:IsShown(), "the Craft Advisor window is shown")
    if f and f:IsShown() then f:Hide() end
    t:done()
  end)
end)

Dev:Register("sv.shapes", function(t)
  local function Version(name)
    local mod = RQ:GetModule(name)
    return mod and mod.dbVersion
  end
  local checks = {
    { "RavenquillExpeditionDB", nil },
    { "RavenquillExpeditionHighlightsDB", Version("Highlights") },
    { "RavenquillExpeditionMapDB", Version("Map") },
    { "RavenquillExpeditionCraftDB", nil },
  }
  for _, c in ipairs(checks) do
    local db = rawget(_G, c[1])
    if db ~= nil then
      t:ok(type(db) == "table" and (c[2] == nil or db.v == c[2]),
        ("%s is a table%s"):format(c[1], c[2] and (" with v = " .. c[2]) or ""))
    else
      t:note(c[1] .. " not loaded")
    end
  end
  t:done()
end)

Dev:Register("env.info", function(t)
  local _, build, _, iface = GetBuildInfo()
  t:note(("client %s, interface %s, core %s"):format(tostring(build), tostring(iface), tostring(RQ.version)))
  t:note("player " .. tostring((RQ:PlayerKey())) .. ", guild " .. tostring((RQ:GuildKey())))
  t:note("hooks: core comm " .. tostring(RQ.Comm and RQ.Comm.hooked))
  t:note("ReloadUI is " .. type(ReloadUI))
  t:done()
end)

Dev.GAME_GLOBALS = {
  "Ambiguate", "BACKSLOT", "BANK_CONTAINER", "ButtonFrameTemplate_HideButtonBar",
  "ButtonFrameTemplate_HidePortrait", "CHESTSLOT", "CLASS_ICON_TCOORDS", "CUSTOM_CLASS_COLORS", "C_AddOns",
  "C_CVar", "C_ChatInfo", "C_ClassTalents", "C_Container", "C_GuildInfo", "C_Item", "C_Map", "C_PartyInfo", "C_QuestLog",
  "C_Reputation", "C_Spell", "C_SpellBook", "C_SuperTrack", "C_Texture", "C_Timer", "C_TooltipInfo",
  "C_TradeSkillUI", "C_Traits", "C_XMLUtil", "CanInspect", "ChatEdit_GetActiveWindow", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_OpenChat", "ChatFrame_SendTell", "CheckInteractDistance", "Constants", "CreateFrame",
  "DEFAULT_CHAT_FRAME", "Enum", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "GameFontHighlightSmall", "GameTooltip",
  "GameTooltip_Hide", "GameTooltip_ShowCompareItem", "GetAddOnInfo", "GetAddOnMetadata", "GetBuildInfo",
  "GetCoinTextureString", "GetContainerItemLink", "GetContainerNumSlots", "GetCursorPosition",
  "GetDetailedItemLevelInfo", "GetFileIDFromPath", "GetGuildInfo", "GetGuildRosterInfo", "GetInstanceInfo",
  "GetInventoryItemLink", "GetInventorySlotInfo", "GetItemCount", "GetItemInfo", "GetItemInfoInstant",
  "GetItemStats", "GetLocale", "GetMaxPlayerLevel", "GetMoneyString", "GetNormalizedRealmName",
  "GetNumGroupMembers", "GetNumGuildMembers", "GetNumQuestLogEntries", "GetNumSubgroupMembers",
  "GetNumTradeSkills", "GetProfessionInfo", "GetProfessions", "GetQuestLogTitle", "GetQuestTagInfo",
  "GetRealZoneText", "GetRealmName", "GetServerTime", "GetSpellInfo", "GetTime", "debugprofilestop", "GetTradeSkillItemLink",
  "GetTradeSkillLine", "GetTradeSkillRecipeLink", "GuildRoster", "HANDSSLOT", "HBD_PINS_WORLDMAP_SHOW_WORLD",
  "HEADSLOT", "HandleModifiedItemClick", "ITEM_CLASSES_ALLOWED", "ITEM_QUALITY_COLORS", "ITEM_REQ_SKILL",
  "InCombatLockdown", "InspectFrame", "InspectUnit", "InviteUnit", "IsAddOnLoaded", "IsControlKeyDown", "IsInGuild", "IsInInstance", "IsInRaid",
  "IsIndoors", "IsModifiedClick", "IsPlayerSpell", "IsShiftKeyDown", "LEGSSLOT", "LOCALIZED_CLASS_NAMES_FEMALE",
  "LOCALIZED_CLASS_NAMES_MALE", "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE", "IsMounted", "GetUnitSpeed",
  "GetBattlefieldWinner",
  "LibStub", "LoadAddOn", "MAINHANDSLOT", "MenuUtil", "MinimalSliderWithSteppersMixin", "Minimap", "NECKSLOT",
  "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil", "NotifyInspect",
  "OpenWorldMap", "PanelTemplates_DeselectTab", "PanelTemplates_SelectTab", "PanelTemplates_TabResize", "ReloadUI", "CreateVector2D", "UnitPosition", "GetFactionInfoByID",
  "ProfessionsFrame", "RAID_CLASS_COLORS", "RANGEDSLOT", "SECONDARYHANDSLOT", "SHOULDERSLOT", "SPEED",
  "ScrollUtil", "SendChatMessage", "SetItemRef", "ShoppingTooltip1", "ShoppingTooltip2", "ShowUIPanel",
  "SHIRTSLOT", "TABARDSLOT",
  "TRINKET0SLOT", "TRINKET1SLOT", "ToggleWorldMap", "UIParent", "UISpecialFrames", "UNKNOWNOBJECT", "UiMapPoint",
  "UnitClass", "UnitFactionGroup", "UnitGUID", "UnitIsDeadOrGhost", "UnitIsInMyGuild", "UnitIsPlayer",
  "UnitIsUnit", "UnitLevel", "UnitName", "UnitNameUnmodified", "UnitOnTaxi", "UnitTokenFromGUID", "WAISTSLOT",
  "WOW_PROJECT_CAMELOT", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WRISTSLOT",
  "WorldMapFrame", "canaccessvalue", "date", "debugstack", "geterrorhandler", "hooksecurefunc", "issecretvalue",
  "strsplit", "time", "tinsert", "wipe",
}

Dev:Register("env.globals", function(t)
  local missing = {}
  for _, name in ipairs(Dev.GAME_GLOBALS) do
    if _G[name] == nil then missing[#missing + 1] = name end
  end
  table.sort(missing)
  t:note(("%d of %d game globals the suite reads exist"):format(#Dev.GAME_GLOBALS - #missing, #Dev.GAME_GLOBALS))
  t:note("missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
  t:done()
end)

local PROBE_PATTERNS = { "DUEL", "PVPRANK", "PVP_RANK", "PVPRank", "PvpRank", "HONOR", "SkillLine", "SKILL_RANK", "Profession" }

local function Matches(name)
  for _, p in ipairs(PROBE_PATTERNS) do if name:find(p, 1, true) then return true end end
end

local function NoteTable(t, label, tbl)
  if type(tbl) ~= "table" then t:note(label .. " is " .. type(tbl)) return end
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  t:note(label .. ": " .. table.concat(keys, ", "))
end

Dev:Register("probe.milestones", function(t)
  local found = {}
  for name, value in pairs(_G) do
    if type(name) == "string" and Matches(name) and (type(value) == "function" or type(value) == "string") then
      found[#found + 1] = name
    end
  end
  table.sort(found)
  for _, name in ipairs(found) do
    local v = _G[name]
    t:note(type(v) == "string" and (name .. " = " .. v) or (name .. "()"))
  end
  NoteTable(t, "C_PvP", rawget(_G, "C_PvP"))
  NoteTable(t, "C_Spell", rawget(_G, "C_Spell"))
  NoteTable(t, "C_TradeSkillUI", rawget(_G, "C_TradeSkillUI"))
  if type(GetProfessions) == "function" then
    for i, index in pairs({ GetProfessions() }) do
      local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
      t:note(("profession %s: %s %s/%s line %s"):format(tostring(i), tostring(name), tostring(rank), tostring(maxRank), tostring(skillLine)))
    end
  end
  t:done()
end)

Dev:Register("map.worldmap", function(t)
  local M = rawget(_G, "RavenquillExpeditionMap")
  if not M then t:note("Map not loaded") t:done() return end
  if not (WorldMapFrame and ToggleWorldMap) then t:note("no WorldMapFrame / ToggleWorldMap") t:done() return end
  if InCombatLockdown() then t:note("in combat: not opening the map from addon code") t:done() return end
  local blocked = {}
  local watch = CreateFrame("Frame")
  watch:RegisterEvent("ADDON_ACTION_BLOCKED")
  watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  watch:SetScript("OnEvent", function(_, event, addon, fn)
    blocked[#blocked + 1] = { event = event, addon = tostring(addon), fn = tostring(fn) }
  end)
  local ourLib = LibStub and LibStub("HereBeDragons-Pins-2.0-RQE", true)
  t:ok(ourLib and not ourLib.worldmapAttached, "our private HBD-Pins copy never registers with the world map")
  t:note("shared HereBeDragons-Pins-2.0 (other addons): minor " .. tostring(LibStub and LibStub.minors and LibStub.minors["HereBeDragons-Pins-2.0"]))
  local fakeWas = M.fakeOn
  if not fakeWas then M:Fake(true) end
  local wasShown = WorldMapFrame:IsShown()
  if wasShown then pcall(ToggleWorldMap) end
  local ok, err = pcall(ToggleWorldMap)
  t:ok(ok, "ToggleWorldMap() runs" .. (ok and "" or (": " .. tostring(err))))
  t:after(1, function()
    t:ok(WorldMapFrame:IsShown(), "the world map is shown")
    local shown, total = 0, 0
    for f in pairs(M.worldPlaced or {}) do
      total = total + 1
      if f:IsVisible() then shown = shown + 1 end
    end
    t:note(("world pins: %d placed, %d visible on map %s"):format(total, shown, tostring(WorldMapFrame:GetMapID())))
    local layer = M.worldLayer
    t:ok(total == 0 or (layer and layer:GetParent() == WorldMapFrame:GetCanvas()),
      "Map's world pins sit on its own layer on the map canvas")
    local ours = 0
    for _, b in ipairs(blocked) do
      t:note(("%s: %s tried %s"):format(b.event, b.addon, b.fn))
      if b.addon == "RavenquillExpedition_Map" then ours = ours + 1 end
    end
    t:ok(ours == 0, "no ADDON_ACTION_BLOCKED/FORBIDDEN for RavenquillExpedition_Map (" .. #blocked .. " events in all)")
    watch:UnregisterAllEvents()
    if WorldMapFrame:IsShown() and not wasShown then pcall(ToggleWorldMap) end
    if not fakeWas then M:Fake(false) end
    t:done()
  end)
end)

Dev:Register("launcher", function(t)
  local b = rawget(_G, "RavenquillExpeditionLauncher")
  t:ok(b ~= nil, "the suite's minimap button exists")
  if b then t:note("shown " .. tostring(b:IsShown())) end
  local db = rawget(_G, "RavenquillExpeditionDB")
  t:note("launcher settings: " .. (db and type(db.launcher) == "table" and
    ("hide=" .. tostring(db.launcher.hide) .. " angle=" .. tostring(db.launcher.angle)) or "none"))
  t:done()
end)

Dev:Register("sync.state", function(t)
  local st = RQ:CommState()
  t:note(("tokens %.1f, slow %s, queued %d, records %d, sent %d, delivered %d, lost %d, received %d, foreign %d, hooked %s"):format(
    st.tokens, tostring(st.slow), st.queued, st.records, st.sent, st.delivered, st.lost, st.received, st.foreign, tostring(st.hooked)))
  for prefix, raw in pairs(RQ.Comm.prefixes) do
    local s = raw:Status()
    local rej = {}
    for k, v in pairs(s.rejected) do rej[#rej + 1] = k .. "=" .. v end
    t:note(("%s (%s): prefix %s, sent %d, received %d%s"):format(prefix, raw.lane, raw.prefixOk and "registered" or "NOT registered",
      s.sent, s.received, rej[1] and (", rejected " .. table.concat(rej, " ")) or ""))
    t:ok(raw.prefixOk, prefix .. " prefix registered")
  end
  t:ok(st.hooked, "the core sees other addons' guild sends (hook)")
  t:done()
end)

local RATE_PREFIX = "RQTst"
local PHASES = { { every = 10, n = 6 }, { every = 5, n = 12 }, { every = 2, n = 30 } }
Dev:Register("comm.rate", function(t)
  local can, why = RQ:CanSend()
  if not can then t:ok(false, "can send: " .. tostring(why)) t:done() return end
  local okReg = pcall(C_ChatInfo.RegisterAddonMessagePrefix, RATE_PREFIX)
  t:ok(okReg, "test prefix registered")
  local sentAt, echoAt, results = {}, {}, {}
  local watch = CreateFrame("Frame")
  watch:RegisterEvent("CHAT_MSG_ADDON")
  watch:SetScript("OnEvent", function(_, _, prefix, text, chan, sender)
    if prefix ~= RATE_PREFIX or chan ~= "GUILD" or RQ.IsSecret(text) or RQ.IsSecret(sender) then return end
    if RQ:IsMe(RQ:NormName(sender)) and sentAt[text] and not echoAt[text] then echoAt[text] = GetTime() end
  end)
  local function Send(phase, i)
    local text = ("p%d;%d"):format(phase, i)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, RATE_PREFIX, text, "GUILD")
    sentAt[text] = GetTime()
    if not ok or not (res == nil or res == true or res == 0) then results[#results + 1] = text .. " send result " .. tostring(res) end
  end
  local start = 1
  for p, ph in ipairs(PHASES) do
    for i = 1, ph.n do
      local at = start + (i - 1) * ph.every
      t:after(at, function() Send(p, i) end)
    end
    start = start + ph.n * ph.every + 15
  end
  t:after(start + 10, function()
    watch:UnregisterAllEvents()
    for p, ph in ipairs(PHASES) do
      local echoed, lat = 0, 0
      for i = 1, ph.n do
        local text = ("p%d;%d"):format(p, i)
        if echoAt[text] then echoed = echoed + 1; lat = lat + (echoAt[text] - sentAt[text]) end
      end
      t:note(("every %d s (%d/min): %d of %d echoed%s"):format(ph.every, 60 / ph.every, echoed, ph.n,
        echoed > 0 and (", avg %.1f s"):format(lat / echoed) or ""))
    end
    for _, r in ipairs(results) do t:note(r) end
    t:ok(true, "measured (read the notes)")
    t:done()
  end)
end, 260, { manual = true })

Dev:Register("map.state", function(t)
  local M = rawget(_G, "RavenquillExpeditionMap")
  if not M then t:note("Map not loaded") t:done() return end
  local s = M.settings or {}
  t:note(("settings: share %s, worldmap %s, minimap %s, names %s, size %s, selfPin %s"):format(tostring(s.share),
    tostring(s.worldmap), tostring(s.minimap), tostring(s.names), tostring(s.size), tostring(s.selfPin)))
  local n = 0
  for key, m in pairs(M.members or {}) do
    n = n + 1
    local ok, state = pcall(M.State, M, m)
    local okAge, age = pcall(M.Age, M, m)
    t:note(("member %s: map %s x %.3f y %.3f, %s, age %s s%s%s"):format(tostring(key), tostring(m.mapID), m.x or -1, m.y or -1,
      ok and tostring(state) or "?", okAge and tostring(math.floor(age or -1)) or "?", m.fake and ", test pin" or "", m.isSelf and ", self" or ""))
  end
  t:note(n .. " members in Map's store")
  local okPos, mapID, x, y = pcall(M.ReadOwnPosition, M)
  t:note(("own position: %s %s %s %s"):format(tostring(okPos), tostring(mapID), tostring(x), tostring(y)))
  if M.SyncDebug then
    pcall(M.SyncDebug, M, function(line) t:note("sync: " .. tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end)
  end
  local opened = false
  if WorldMapFrame and not WorldMapFrame:IsShown() and not InCombatLockdown() then opened = pcall(ToggleWorldMap) end
  t:after(2, function()
    local placed, visible = 0, 0
    for f, d in pairs(M.worldPlaced or {}) do
      placed = placed + 1
      if f:IsVisible() then visible = visible + 1 end
      local left, top = f:GetLeft(), f:GetTop()
      t:note(("world pin %s: placed on map %s (%.3f, %.3f), shown %s, visible %s, alpha %.2f, parent is layer %s, at %s,%s"):format(
        tostring(f.key), tostring(d.mapID), d.x or -1, d.y or -1, tostring(f:IsShown()), tostring(f:IsVisible()),
        f:GetAlpha() or -1, tostring(f:GetParent() == M.worldLayer), tostring(left and math.floor(left)),
        tostring(top and math.floor(top))))
    end
    for key in pairs(M.members or {}) do
      local has = false
      for f in pairs(M.worldPlaced or {}) do if f.key == key then has = true end end
      if not has then t:note("NO world pin for member " .. tostring(key)) end
    end
    local layer = M.worldLayer
    local okTop, top = pcall(M.TopCanvasLevel)
    t:note(("world pins: %d placed, %d visible; layer %s (visible %s, %dx%d, level %s, highest other canvas level %s, strata %s); map open %s, map ID %s"):format(placed,
      visible, layer and "exists" or "MISSING", layer and tostring(layer:IsVisible()) or "-", layer and layer:GetWidth() or 0,
      layer and layer:GetHeight() or 0, layer and tostring(layer:GetFrameLevel()) or "-", okTop and tostring(top) or "?",
      layer and tostring(layer:GetFrameStrata()) or "-",
      tostring(WorldMapFrame and WorldMapFrame:IsShown()), tostring(WorldMapFrame and WorldMapFrame:GetMapID())))
    if opened and WorldMapFrame:IsShown() then pcall(ToggleWorldMap) end
    t:done()
  end)
end, 20, { manual = true })

local function CraftErrorSince(gca, before)
  local le = gca.db and gca.db.diag and gca.db.diag.lastError
  if le and le.at ~= before then return tostring(le.where) .. ": " .. tostring(le.msg):match("^[^\n]*") end
end

local function CraftStep(t, gca, label, fn, ...)
  local before = gca.db.diag and gca.db.diag.lastError and gca.db.diag.lastError.at
  local started = debugprofilestop()
  local ok, err = pcall(fn, ...)
  local ms = debugprofilestop() - started
  local guarded = CraftErrorSince(gca, before)
  t:ok(ok and not guarded, ("%s (%.0f ms)%s"):format(label, ms, (not ok and (": " .. tostring(err))) or (guarded and (": " .. guarded)) or ""))
end

local function CraftSyncRoundTrip(t, gca)
  local own = gca.playerKey and gca.db.members[gca.playerKey]
  if not (own and own.items) then t:note("no own gear record yet") return end
  local okEnc, chunks = pcall(gca.EncodeRecord, gca, own, "")
  t:ok(okEnc and type(chunks) == "table" and chunks[1], "own gear record encodes: " .. (okEnc and tostring(chunks and #chunks) .. " message(s)" or tostring(chunks)))
  local longest = 0
  for _, c in ipairs(okEnc and chunks or {}) do longest = math.max(longest, #c) end
  t:ok(longest <= gca.SyncConst.MAX_MSG, ("longest message %d <= %d bytes"):format(longest, gca.SyncConst.MAX_MSG))
  local same, total = 0, 0
  for _, slot in ipairs(gca.SYNC_SLOTS) do
    local link = own.items[slot]
    if link then
      total = total + 1
      local enc = gca:EncodeItem(link)
      local dec = enc and gca:DecodeItem(enc)
      if dec and tonumber(dec:match("item:(%d+)")) == tonumber(tostring(link):match("item:(%d+)")) then same = same + 1 end
    end
  end
  t:ok(same == total, ("own items survive encode/decode: %d of %d"):format(same, total))
end

Dev:Register("craft.smoke", function(t)
  local gca = RQ:GetModule("Craft")
  if not (gca and gca.db and gca.UI) then t:note("CraftAdvisor not loaded") t:done() return end
  if InCombatLockdown() then t:note("in combat: skipped") t:done() return end
  local UI = gca.UI
  local settings = gca.db.settings
  local profBefore = gca.db.profSel and gca.charKey and gca.db.profSel[gca.charKey]
  local modeBefore, offlineBefore = settings.memberView, settings.needsOffline
  local f = rawget(_G, "RavenquillExpeditionCraftFrame")
  local wasShown = f and f:IsShown()
  CraftStep(t, gca, "open the window", function() if not (f and f:IsShown()) then gca:Open() end end)
  f = rawget(_G, "RavenquillExpeditionCraftFrame")
  t:ok(f and f:IsShown(), "window shown")
  local own = gca:OwnProfessions() or {}
  local profs = {}
  for _, p in ipairs(gca.PROFESSIONS) do if own[p.key] then profs[#profs + 1] = p.key end end
  for _, p in ipairs(gca.PROFESSIONS) do if not own[p.key] then profs[#profs + 1] = p.key break end end
  for _, prof in ipairs(profs) do
    CraftStep(t, gca, "profession " .. prof .. (own[prof] and "" or " (browse)"), function()
      gca:SelectProfession(prof)
      UI:Refresh()
    end)
    for _, mode in ipairs({ "sheet", "list" }) do
      CraftStep(t, gca, "  " .. mode .. " view, own character", function()
        UI:SetMemberMode(mode)
        UI:OpenMember(gca.playerKey)
      end)
    end
    local members = UI.lastMembers or {}
    local opened = 0
    for _, m in ipairs(members) do
      if opened >= 3 then break end
      if m.key and m.key ~= gca.playerKey then
        opened = opened + 1
        CraftStep(t, gca, "  member " .. tostring(m.key), UI.OpenMember, UI, m.key)
      end
    end
    CraftStep(t, gca, "  sheet slot 1", function() UI:SetMemberMode("sheet"); UI:SelectSheetSlot(gca.SYNC_SLOTS[1]) end)
    CraftStep(t, gca, "  guild needs view", function()
      UI:SetView("needs")
      UI:SetNeedsOffline(true)
      UI:SetNeedsOffline(false)
      UI:SetView("member")
    end)
  end
  CraftStep(t, gca, "guild needs for all members", gca.GuildNeeds, gca)
  CraftSyncRoundTrip(t, gca)
  if profBefore then gca:SelectProfession(profBefore) end
  settings.memberView, settings.needsOffline = modeBefore, offlineBefore
  CraftStep(t, gca, "restore and refresh", function() UI:ApplyMemberMode(); UI:Refresh() end)
  if not wasShown and f and f:IsShown() then f:Hide() end
  t:done()
end, 60)

local function TextureFacts(tex)
  local out = {}
  for _, method in ipairs({ "GetTexture", "GetTextureFileID", "GetTextureFilePath" }) do
    local ok, v = pcall(function() return tex[method](tex) end)
    out[#out + 1] = method .. "=" .. tostring(ok and v)
  end
  return table.concat(out, " ")
end

local function CheckNewspaper(t, H)
  local frame = _G.RavenquillExpeditionHighlightsFrame
  local paper = frame and frame.paper
  t:ok(paper ~= nil and paper:IsVisible(), "the window opens on the newspaper")
  if not paper then return end
  local m, p = paper.masthead, paper.parchment
  t:ok(m.loaded, ("masthead texture loaded (SetTexture returned %s; %s)"):format(tostring(m.result), TextureFacts(m.texture)))
  t:ok(p.source == "texture", ("parchment texture loaded: %s (%s; %s)"):format(p.source, H.PARCHMENT, TextureFacts(p.texture)))
  t:ok(p.vignette:IsShown(), ("vignette loaded (%s)"):format(TextureFacts(p.vignette)))
  local font = paper.lead.head:GetFont()
  t:ok(type(font) == "string" and font:upper():find("MORPHEUS", 1, true) ~= nil, "headline font: " .. tostring(font))
  local off = Dev.TextOutside(paper)
  t:ok(off == nil, ("window paper %dx%d: every text on the paper, none cut%s"):format(math.floor(paper:GetWidth() + 0.5),
    math.floor(paper:GetHeight() + 0.5), off and (": " .. off:sub(1, 60)) or ""))
  local issue = paper.issue
  t:note(("issue %s of %s, lead: %s"):format(tostring(issue and issue.no), tostring(issue and issue.day),
    tostring(issue and issue.lead and issue.lead.head)))
end

local function CheckTab(t)
  local ov = _G.RavenquillExpeditionOverview
  local page = ov and ov.optView.pages.Highlights
  t:ok(page and page:IsVisible() and page.msg and not page.paper, "CHRONIK opened the /rq Highlights tab on the log, no paper there")
  if not (page and page.msg) then t:done() return end
  t:after(1, function()
    local okVisible, visible = pcall(function() return page.msg:GetNumVisibleLines() end)
    t:note("log lines on screen (scrolls to the new-entries line on open): " .. tostring(okVisible and visible or "no GetNumVisibleLines"))
    if RQ:OverviewShown() then RQ:ToggleOverview() end
    if RQ:OverviewShown() then RQ:ToggleOverview() end
    t:done()
  end)
end

Dev:Register("highlights.smoke", function(t)
  local H = RQ:GetModule("Highlights")
  if not (H and H.db) then t:note("Highlights not loaded") t:done() return end
  local okLines, list, nHL, nAct = pcall(H.LogLines, H)
  t:ok(okLines, "log lines: " .. (okLines and (tostring(nHL) .. " highlights, " .. tostring(nAct) .. " activity") or tostring(list)))
  local formatted, failed, firstErr = 0, 0, nil
  for _, e in ipairs(okLines and list or {}) do
    local ok, text = pcall(H.Format, H, e)
    if ok and type(text) == "string" then formatted = formatted + 1 else failed = failed + 1; firstErr = firstErr or tostring(text) end
  end
  t:ok(failed == 0, ("every log line formats: %d ok, %d failed%s"):format(formatted, failed, firstErr and (": " .. firstErr) or ""))
  local sent, back, differ = 0, 0, nil
  for _, e in ipairs(okLines and list or {}) do
    if not e.act and e.id and not e.by and sent < 25 then
      local okEnc, body = pcall(H.Encode, e)
      if okEnc and body then
        sent = sent + 1
        local okDec, r = pcall(H.Decode, e.who, body)
        if okDec and r and r.k == e.k and r.t == e.t and r.who == e.who and r.item == e.item then back = back + 1
        else differ = differ or (tostring(e.k) .. " " .. tostring(e.id)) end
      end
    end
  end
  t:ok(back == sent, ("own entries survive encode/decode: %d of %d%s"):format(back, sent, differ and (", first difference " .. differ) or ""))
  local okWin, err = pcall(function() H:ShowWindow(); H:Refresh() end)
  t:ok(okWin, "newspaper window opens and fills" .. (okWin and "" or (": " .. tostring(err))))
  CheckNewspaper(t, H)
  local frame = _G.RavenquillExpeditionHighlightsFrame
  local okLog, logErr = pcall(function() frame.chronicle:Click() end)
  t:ok(okLog and not frame:IsShown(), "CHRONIK closes the sheet" .. (okLog and "" or (": " .. tostring(logErr))))
  t:after(1, function() CheckTab(t) end)
end, 30)

local MILESTONE_APIS = { "IsMounted", "GetUnitSpeed", "UnitOnTaxi", "GetBattlefieldWinner", "UnitFactionGroup",
  "GetProfessions", "GetProfessionInfo" }
local MILESTONE_STRINGS = { "LOOT_ITEM_CREATED_SELF", "FACTION_STANDING_CHANGED", "FACTION_STANDING_LABEL7",
  "FACTION_STANDING_LABEL8", "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT", "SKILL_RANK_UP" }

local function CheckReputation(t)
  local R = rawget(_G, "C_Reputation")
  local ok = type(R) == "table" and type(R.GetNumFactions) == "function" and type(R.GetFactionDataByIndex) == "function"
  t:ok(ok, "C_Reputation.GetNumFactions and GetFactionDataByIndex exist")
  if not ok then return end
  local f = R.GetFactionDataByIndex(1)
  t:note(("factions %s, first: %s reaction %s header %s"):format(tostring(R.GetNumFactions()), tostring(f and f.name),
    tostring(f and f.reaction), tostring(f and f.isHeader)))
end

Dev:Register("highlights.milestones", function(t)
  local H = RQ:GetModule("Highlights")
  if not (H and H.db) then t:note("Highlights not loaded") t:done() return end
  for _, name in ipairs(MILESTONE_APIS) do t:ok(type(_G[name]) == "function", name .. " is " .. type(_G[name])) end
  for _, name in ipairs(MILESTONE_STRINGS) do t:ok(type(_G[name]) == "string", name .. " = " .. tostring(_G[name])) end
  if type(GetUnitSpeed) == "function" then
    local _, run = GetUnitSpeed("player")
    t:note(("mounted %s, run speed %s"):format(tostring(IsMounted and IsMounted()), tostring(run)))
  end
  CheckReputation(t)
  local rec = H.cdb.mount
  t:ok(type(rec) == "table", ("mount record: tier %s, base level %s"):format(tostring(rec and rec.tier), tostring(rec and rec.base)))
  t:done()
end, 10)

local INSPECT_FRAMES ={ "ProfessionsFrame", "TradeSkillFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame",
  "FriendsFrame", "CollectionsJournal", "EncounterJournal", "PVEFrame", "MerchantFrame", "QuestLogFrame", "WorldMapFrame" }
local INSPECT_MAX_LINES = 3000

local function Pack(...) return { n = select("#", ...), ... } end

local function Call(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return nil end
  local r = Pack(pcall(fn, obj, ...))
  if not r[1] then return nil end
  return unpack(r, 2, math.max(r.n, 2))
end

local function RegionName(r)
  return tostring(Call(r, "GetDebugName") or Call(r, "GetName") or "?")
end

local function Points(r)
  local out = {}
  for i = 1, Call(r, "GetNumPoints") or 0 do
    local p, rel, rp, x, y = Call(r, "GetPoint", i)
    out[#out + 1] = ("%s>%s:%s(%.0f,%.0f)"):format(tostring(p), rel and RegionName(rel) or "parent", tostring(rp), x or 0, y or 0)
  end
  return table.concat(out, " ")
end

local function Color(r, method)
  local cr, cg, cb, ca = Call(r, method)
  if not cr then return "-" end
  return ("%.2f,%.2f,%.2f,%.2f"):format(cr, cg or 0, cb or 0, ca or 1)
end

local function TextureLine(r, atlases)
  local atlas = Call(r, "GetAtlas")
  if atlas then atlases[atlas] = true end
  local layer, sub = Call(r, "GetDrawLayer")
  return (" layer=%s/%s atlas=%s file=%s tc=%s vc=%s blend=%s"):format(tostring(layer), tostring(sub), tostring(atlas),
    tostring(Call(r, "GetTexture")), table.concat({ Call(r, "GetTexCoord") }, ","), Color(r, "GetVertexColor"),
    tostring(Call(r, "GetBlendMode")))
end

local function FontLine(r)
  local font = Call(r, "GetFontObject")
  local text = tostring(Call(r, "GetText") or ""):sub(1, 40)
  return (" font=%s color=%s justify=%s text=%q"):format(tostring(font and Call(font, "GetName")), Color(r, "GetTextColor"),
    tostring(Call(r, "GetJustifyH")), text)
end

local function Describe(r, depth, atlases)
  local kind = tostring(Call(r, "GetObjectType"))
  local w, h = Call(r, "GetSize")
  local line = ("%s%s %s %.0fx%.0f shown=%s"):format(("  "):rep(depth), kind, RegionName(r), w or 0, h or 0,
    tostring(Call(r, "IsShown")))
  if kind == "Texture" or kind == "MaskTexture" then line = line .. TextureLine(r, atlases)
  elseif kind == "FontString" then line = line .. FontLine(r)
  else line = line .. (" level=%s strata=%s"):format(tostring(Call(r, "GetFrameLevel")), tostring(Call(r, "GetFrameStrata"))) end
  return line .. " @ " .. Points(r)
end

local function Walk(f, depth, out, atlases)
  if #out >= INSPECT_MAX_LINES or Call(f, "IsForbidden") then return end
  out[#out + 1] = Describe(f, depth, atlases)
  for _, r in ipairs({ Call(f, "GetRegions") }) do out[#out + 1] = Describe(r, depth + 1, atlases) end
  for _, c in ipairs({ Call(f, "GetChildren") }) do Walk(c, depth + 1, out, atlases) end
end

local function AtlasLines(atlases)
  local out = {}
  for atlas in pairs(atlases) do
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    out[#out + 1] = info and ("%s file=%s %dx%d l=%.4f r=%.4f t=%.4f b=%.4f tilesH=%s tilesV=%s"):format(atlas,
      tostring(info.file or info.filename), info.width or 0, info.height or 0, info.leftTexCoord or 0, info.rightTexCoord or 0,
      info.topTexCoord or 0, info.bottomTexCoord or 0, tostring(info.tilesHorizontally), tostring(info.tilesVertically))
      or (atlas .. " (no info)")
  end
  table.sort(out)
  return out
end

function Dev:InspectFrame(name)
  local f = rawget(_G, name)
  if type(f) ~= "table" then return nil end
  local out, atlases = {}, {}
  Walk(f, 0, out, atlases)
  self.db.inspect = type(self.db.inspect) == "table" and self.db.inspect or {}
  self.db.inspect[name] = { t = time(), lines = out, atlases = AtlasLines(atlases) }
  local shot = rawget(_G, "Screenshot")
  if type(shot) == "function" then pcall(shot) end
  return #out
end

Dev:Register("ui.inspect", function(t)
  RQ.Print("Dev", "|cffffff00Open the Blizzard windows to copy (profession, character, spellbook ...). Each one is recorded and screenshotted. 2 minutes.|r")
  local done, ticks = {}, 0
  local function Poll()
    ticks = ticks + 1
    for _, name in ipairs(INSPECT_FRAMES) do
      local f = rawget(_G, name)
      if not done[name] and type(f) == "table" and Call(f, "IsShown") then
        done[name] = true
        t:after(0.6, function()
          local n = Dev:InspectFrame(name)
          t:ok(n and n > 0, ("%s recorded: %s regions"):format(name, tostring(n)))
          RQ.Print("Dev", name .. " recorded.")
        end)
      end
    end
    if ticks < 115 then t:after(1, Poll) else t:done() end
  end
  t:after(1, Poll)
end, 130, { manual = true })

local function TakeScreenshot()
  local shot = rawget(_G, "Screenshot")
  if type(shot) == "function" then pcall(shot) end
end

Dev:Register("ui.capture", function(t)
  if RQ:OverviewShown() then RQ:ToggleOverview() end
  if RQ:OverviewShown() then RQ:ToggleOverview() end
  RQ:ToggleOverview()
  t:after(1.5, function()
    TakeScreenshot()
    local n = Dev:InspectFrame("RavenquillExpeditionOverview")
    t:ok(n and n > 0, ("overview recorded: %s regions"):format(tostring(n)))
    local tabs, i = { "Highlights", "Map", "Craft" }, 0
    local function NextTab()
      i = i + 1
      local name = tabs[i]
      if not name then
        RQ:ToggleOverview()
        RQ:ToggleOverview()
        return t:done()
      end
      RQ:ShowModulePage(name)
      t:after(1.5, function()
        TakeScreenshot()
        t:ok(select(2, RQ:OverviewShown()) == name, name .. " tab shown and screenshotted")
        t:after(1.5, NextTab)
      end)
    end
    t:after(2, NextTab)
  end)
end, 30, { manual = true })

local Probe = {}
local SPEC_IDS = { 71, 72, 73, 65, 66, 70, 253, 254, 255, 259, 260, 261, 256, 257, 258, 262, 263, 264, 62, 63, 64, 265, 266, 267,
  102, 103, 104, 105 }

function Probe.Api(path)
  local v = _G
  for part in path:gmatch("[^.]+") do
    if type(v) ~= "table" then return nil end
    v = rawget(v, part)
  end
  return v
end

function Probe.Call(path, ...)
  local fn = Probe.Api(path)
  if type(fn) ~= "function" then return false, "missing" end
  local res = { pcall(fn, ...) }
  if not res[1] then return false, tostring(res[2]) end
  return true, unpack(res, 2)
end

function Probe.Describe(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k, x in pairs(v) do
    if #keys < 14 then keys[#keys + 1] = tostring(k) .. "=" .. (type(x) == "table" and "{" .. #x .. "}" or tostring(x)) end
  end
  table.sort(keys)
  return "{" .. table.concat(keys, " ") .. "}"
end

function Probe.Classic(t)
  local ok, tabs = Probe.Call("GetNumTalentTabs")
  t:note("classic GetNumTalentTabs: " .. tostring(ok) .. " " .. tostring(tabs))
  if not ok or type(tabs) ~= "number" or tabs < 1 then return end
  local okTab, tabName, _, points = Probe.Call("GetTalentTabInfo", 1)
  local okNum, n = Probe.Call("GetNumTalents", 1)
  t:note(("classic tab 1: %s %s points %s, talents %s"):format(tostring(okTab), tostring(tabName), tostring(points), tostring(okNum and n)))
  local okInfo, name, icon, tier, column, rank, maxRank = Probe.Call("GetTalentInfo", 1, 1)
  t:note(("classic talent 1/1: %s name %s icon %s tier %s col %s rank %s/%s"):format(tostring(okInfo), tostring(name),
    tostring(icon), tostring(tier), tostring(column), tostring(rank), tostring(maxRank)))
  local okOther = Probe.Call("GetTalentInfo", 1, 1, false, false, 2)
  t:note("classic GetTalentInfo with a class index argument: " .. tostring(okOther))
end

function Probe.Node(t, configID, nodeID, label)
  local ok, info = Probe.Call("C_Traits.GetNodeInfo", configID, nodeID)
  t:note(label .. " node " .. tostring(nodeID) .. ": " .. tostring(ok) .. " " .. Probe.Describe(info))
  local entryID = ok and type(info) == "table" and type(info.entryIDs) == "table" and info.entryIDs[1]
  if not entryID then return end
  local okE, entry = Probe.Call("C_Traits.GetEntryInfo", configID, entryID)
  t:note(label .. " entry " .. tostring(entryID) .. ": " .. tostring(okE) .. " " .. Probe.Describe(entry))
  local defID = okE and type(entry) == "table" and entry.definitionID
  if not defID then return end
  local okD, def = Probe.Call("C_Traits.GetDefinitionInfo", defID)
  t:note(label .. " definition " .. tostring(defID) .. ": " .. tostring(okD) .. " " .. Probe.Describe(def))
end

function Probe.Own(t)
  local ok, configID = Probe.Call("C_ClassTalents.GetActiveConfigID")
  t:note("own active config: " .. tostring(ok) .. " " .. tostring(configID))
  if not ok or not configID then return end
  local okC, config = Probe.Call("C_Traits.GetConfigInfo", configID)
  t:note("own config info: " .. tostring(okC) .. " " .. Probe.Describe(config))
  local treeID = okC and type(config) == "table" and type(config.treeIDs) == "table" and config.treeIDs[1]
  local okN, nodes = Probe.Call("C_Traits.GetTreeNodes", treeID)
  t:note("own tree " .. tostring(treeID) .. " nodes: " .. tostring(okN) .. " " .. tostring(type(nodes) == "table" and #nodes))
  if okN and type(nodes) == "table" and nodes[1] then Probe.Node(t, configID, nodes[1], "own") end
  return configID, treeID
end

function Probe.OtherTrees(t, configID, ownTree)
  local seen, found = {}, {}
  for _, specID in ipairs(SPEC_IDS) do
    local ok, treeID = Probe.Call("C_ClassTalents.GetTraitTreeForSpec", specID)
    if ok and treeID and not seen[treeID] then seen[treeID] = true; found[#found + 1] = specID .. "->" .. tostring(treeID) end
  end
  t:note("GetTraitTreeForSpec: " .. (found[1] and table.concat(found, " ") or "nothing"))
  for treeID in pairs(seen) do
    if treeID ~= ownTree then
      local okN, nodes = Probe.Call("C_Traits.GetTreeNodes", treeID)
      t:note("other tree " .. tostring(treeID) .. " nodes: " .. tostring(okN) .. " " .. tostring(type(nodes) == "table" and #nodes))
      if okN and type(nodes) == "table" and nodes[1] then Probe.Node(t, configID, nodes[1], "other") end
      return
    end
  end
end

Dev:Register("talents.probe", function(t)
  local _, class = UnitClass("player")
  t:note("class " .. tostring(class) .. ", level " .. tostring(UnitLevel("player")))
  Probe.Classic(t)
  local configID, ownTree = Probe.Own(t)
  Probe.OtherTrees(t, configID, ownTree)
  t:ok(true, "talent API probe ran (read the notes)")
  t:done()
end, 10, { manual = true })
