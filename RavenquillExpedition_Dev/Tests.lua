-- Ravenquill Expedition: Dev - the in-game tests. Only what the offline harnesses can't prove: the real client API,
-- the real guild channel, real frames. Keep each test short; each one that sends costs a sync token.
local ADDON, ns = ...
local RQ = RavenquillExpedition
local Dev = ns.Dev

-- The guild echoes our own message back: proof that the server accepted and delivered it. Tag "~T" has no
-- handler on any client, so guildmates ignore it (it still counts towards their intake cap, once).
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
  local checks = {
    { "RavenquillExpeditionDB", nil },
    { "RavenquillExpeditionHighlightsDB", 2 },
    { "RavenquillExpeditionMapDB", 1 },
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
  t:note("player " .. tostring(RQ:PlayerKey()) .. ", guild " .. tostring(RQ:GuildKey()))
  t:note("hooks: core comm " .. tostring(RQ.Comm and RQ.Comm.hooked))
  t:note("ReloadUI is " .. type(ReloadUI))
  t:done()
end)

-- The world map opens without ADDON_ACTION_BLOCKED for the Map module (BugGrabber 2026-11: SetPassThroughButtons
-- blocked for Blizzard's quest pins, because HereBeDragons' world map data provider ran our code in the map's show
-- path). Map draws its world pins on its own canvas layer now. Opening from here is addon code, so a block in
-- this path would name RavenquillExpedition_Dev; the real proof is the keybind (M), in combat, with BugGrabber.
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
  if not fakeWas then M:Fake(true) end -- world pins to draw
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

-- How fast may one client send on Forever? Sends on its own prefix "RQTst" (other clients don't register it, so they
-- ignore it), bypassing the core's scheduler on purpose, in three phases (every 10 s, 5 s, 2 s; one minute each) and
-- counts how many of our own messages come back. Only run by name: bash scripts/dev-run.sh comm.rate
-- Risk: at the server's limit our addon messages may be dropped for a while (all addons); it recovers by itself.
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
    start = start + ph.n * ph.every + 15 -- a pause between phases
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

-- What Map knows and shows right now (diagnostic: only notes). Run by name: bash scripts/dev-run.sh map.state
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
  local placed, visible = 0, 0
  for f in pairs(M.worldPlaced or {}) do
    placed = placed + 1
    if f:IsVisible() then visible = visible + 1 end
  end
  local layer = M.worldLayer
  t:note(("world pins: %d placed, %d visible; layer %s (shown %s, %dx%d); map open %s, map ID %s"):format(placed, visible,
    layer and "exists" or "MISSING", layer and tostring(layer:IsVisible()) or "-", layer and layer:GetWidth() or 0,
    layer and layer:GetHeight() or 0, tostring(WorldMapFrame and WorldMapFrame:IsShown()),
    tostring(WorldMapFrame and WorldMapFrame:GetMapID())))
  local okPos, mapID, x, y = pcall(M.ReadOwnPosition, M)
  t:note(("own position: %s %s %s %s"):format(tostring(okPos), tostring(mapID), tostring(x), tostring(y)))
  if M.SyncDebug then
    pcall(M.SyncDebug, M, function(line) t:note("sync: " .. tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end)
  end
  t:done()
end, 20, { manual = true })
