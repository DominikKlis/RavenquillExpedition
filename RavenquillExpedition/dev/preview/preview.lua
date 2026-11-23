local HERE = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):gsub("[^/]*$", ""))
if HERE == "" then HERE = "./" end
local Capture = dofile(HERE .. "capture.lua")
local Scene = dofile(HERE .. "scene.lua")
local Kit, REPO = Capture.Kit, Capture.REPO

local OUT = arg[1] or (REPO .. ".cache/preview")
local WANTED = {}
for i = 2, #arg do WANTED[arg[i]] = true end

local saved = arg[0]
arg[0] = REPO .. "RavenquillExpedition_Highlights/dev/preview.lua"
local NK = dofile(REPO .. "RavenquillExpedition_Highlights/dev/newskit.lua")
arg[0] = saved

local MAP = "RavenquillExpedition_Map"
local CRAFT = "RavenquillExpedition_CraftAdvisor"
local MAP_FILES = {}
for _, f in ipairs({ "Locale.lua", "Map.lua", "Menu.lua", "Pins.lua", "Page.lua", "Sync.lua" }) do
  MAP_FILES[#MAP_FILES + 1] = { REPO .. MAP .. "/" .. f, MAP }
end

local menus = {}

local function MapStubs(env)
  env.WOW_PROJECT_ID, env.WOW_PROJECT_CAMELOT, env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CLASSIC = 15, 15, 1, 2
  env.UnitOnTaxi = function() return false end
  env.IsIndoors = function() return false end
  env.C_CVar = { GetCVar = function() return "0" end }
  env.RAID_CLASS_COLORS = Scene.CLASS_COLORS
  env.LOCALIZED_CLASS_NAMES_MALE = Scene.CLASS_NAMES
  env.LOCALIZED_CLASS_NAMES_FEMALE = Scene.CLASS_NAMES
  env.C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.61 end } end,
    GetMapInfo = function(id) return { name = Scene.ZONES[id] or "Unbekannt" } end,
  }
  env.ChatFrameUtil = { SendTell = function() end }
  env.Enum = env.Enum or {}
  env.Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
  local hbd = {
    GetPlayerZone = function() return 1429, 3 end,
    GetPlayerZonePosition = function() return 0.42, 0.61, 1429, 3 end,
    mapData = setmetatable({}, { __index = function() return { parent = 1415, mapType = 3 } end }),
    GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end,
    GetZoneCoordinatesFromWorldInstance = function(_, wx, wy) return wx / 1000, wy / 1000 end,
    GetAzerothWorldMapCoordinatesFromWorld = function(_, wx, wy) return 0.5 + wx / 10000, 0.5 + wy / 10000 end,
  }
  local pins = setmetatable({}, { __index = function() return function() return true end end })
  env.HBD_PINS_WORLDMAP_SHOW_WORLD = 3
  env.LibStub = setmetatable({ minors = {} }, { __call = function(_, name) return name:find("Pins") and pins or hbd end })
  env.MenuUtil = { CreateContextMenu = function(owner, gen) menus.context = { owner = owner, gen = gen } end }
end

local function CraftStubs(env)
  env.GetInventorySlotInfo = function(t) return 1, [[Interface\PaperDoll\UI-PaperDoll-Slot-]] .. t end
  env.GetProfessions = function() return 1, 2 end
  env.GetProfessionInfo = function(i)
    if i == 1 then return "Lederverarbeitung", 133611, 255, 300, nil, nil, 165 end
    if i == 2 then return "Verzauberkunst", 136244, 180, 225, nil, nil, 333 end
  end
  env.C_SpellBook = { IsSpellKnown = function() return true end }
  env.IsShiftKeyDown = function() return false end
  env.HandleModifiedItemClick = function() end
  env.GetNumSubgroupMembers = function() return 0 end
  env.UnitGUID = function(u) if u == "player" then return "Player-1-LYRA" end end
  env.UnitIsUnit = function(a, b) return a == b end
  env.UnitIsPlayer = function(u) return u == "player" end
  env.CanInspect = function() return false end
  env.CheckInteractDistance = function() return false end
  env.ITEM_QUALITY_COLORS = Scene.QUALITY
  local newsInfo, newsInstant = env.C_Item.GetItemInfo, env.C_Item.GetItemInfoInstant
  env.C_Item.GetItemInfo = function(id)
    local it = Scene.ItemFor(id)
    if it then return it.name, Scene.Link(it), it.q, it.il, it.ml or 1, nil, nil, nil, it.loc, it.icon end
    return newsInfo(tonumber(id) or tonumber(tostring(id):match("item:(%d+)")))
  end
  env.C_Item.GetItemInfoInstant = function(id)
    local it = Scene.ItemFor(id)
    if it then return it.id, "Rüstung", "Leder", it.loc, it.icon, 4, 2 end
    return newsInstant(tonumber(id) or tonumber(tostring(id):match("item:(%d+)")))
  end
  env.C_Item.GetItemStats = function() return {} end
  env.GetItemIcon = function(id) local it = Scene.ItemFor(id); return it and it.icon end
end

local function RosterStubs(env)
  env.GetNumGuildMembers = function() return #Scene.ROSTER, #Scene.ROSTER end
  env.GetGuildRosterInfo = function(i)
    local r = Scene.ROSTER[i]
    if not r then return end
    return r.name .. "-Forever", r.rank or "Mitglied", 1, r.level, Scene.CLASS_NAMES[r.class], r.zone, "", "", r.online, 0, r.class
  end
  for k, v in pairs(Scene.GLOBALS) do env[k] = v end
end

local sched = NK.sched
local c = Kit.Client(sched, nil, "Lyra Distelbach", {
  locale = os.getenv("RQ_LOCALE") or "deDE", guild = "Ravenquill Expedition", realm = "Forever", class = "MAGE", level = 40,
  epoch = NK.NOW - NK.START, random = function() return 0.5 end,
  addons = { NK.HL, CRAFT }, files = MAP_FILES,
  setup = function(env, cl)
    NK.Stubs(env, cl)
    MapStubs(env)
    Capture.Install(cl, env)
    CraftStubs(env)
    RosterStubs(env)
    env.CreateFrame = function(...)
      local f = cl.newFrame(...)
      cl.frames[#cl.frames + 1] = f
      return f
    end
  end,
})
Scene.Icons(NK.ITEMS)
c.login()
sched:advance(5)

local env = c.env
local GS = env.RavenquillExpedition
local H = c.ns[NK.HL].H
local M = c.ns[MAP].Map
local GCA = c.ns[CRAFT].GCA

local function Settle() sched:advance(1) end
local function Hide(f) if f and f.Hide then f:Hide() end end

local function Overview(page, options)
  return function()
    if not GS:OverviewShown() then GS:ToggleOverview() end
    if page == nil then GS:ShowHome()
    elseif options then GS:ShowModuleOptions(page)
    else GS:ShowModulePage(page) end
    Settle()
    return env.RavenquillExpeditionOverview
  end
end

local function Paper()
  Hide(env.RavenquillExpeditionOverview)
  H:ShowWindow()
  Settle()
  return env.RavenquillExpeditionHighlightsFrame
end

local function Advisor(view, scope, mode)
  return function()
    Hide(env.RavenquillExpeditionHighlightsFrame)
    if not (GCA.UI.frame and GCA.UI.frame:IsShown()) then GCA.UI:Toggle() end
    Settle()
    GCA.UI:SetView(view, scope)
    if scope == "member" then
      GCA.UI:OpenMember(Scene.FOCUS)
      GCA.UI:SetMemberMode(mode or "sheet")
    end
    Settle()
    return GCA.UI.frame
  end
end

local function Seed()
  for _, r in ipairs(Scene.ROSTER) do
    if r.peer then GS:NotePeer(r.name) end
  end
  c.fire("GUILD_ROSTER_UPDATE")
  for i, r in ipairs(Scene.ROSTER) do
    if r.pos then
      M:OnMessage(r.name, M:EncodePosition(r.pos[1], r.pos[2], r.pos[3], r.level, r.class, 100 + i, r.pos[4] or "", i), r.name .. "-Forever")
    end
  end
  for _, r in ipairs(Scene.ROSTER) do
    local m = M.members[r.name]
    if m and r.pos and r.pos[5] then m.heard = sched.t - r.pos[5] end
  end
  for _, e in ipairs(Scene.Highlights(NK)) do H:Add(e, "wire") end
  Scene.Craft(GCA, env)
  Settle()
end

local SCREENS = {
  { id = "hl-paper-empty", title = "Rabenblatt, erste Ausgabe", before = true, show = Paper },
  { id = "ov-home", title = "/rq Übersicht", show = Overview(nil) },
  { id = "hl-log", title = "Gilden-Highlights: Chronik", show = Overview("Highlights") },
  { id = "hl-set", title = "Gilden-Highlights: Einstellungen", show = Overview("Highlights", true) },
  { id = "map-list", title = "Gildenkarte", show = Overview("Map") },
  { id = "map-set", title = "Gildenkarte: Einstellungen", show = Overview("Map", true) },
  { id = "craft-page", title = "Gildenwerkstatt in /rq", show = Overview("Craft") },
  { id = "craft-set", title = "Gildenwerkstatt: Einstellungen in /rq", show = Overview("Craft", true) },
  { id = "hl-paper", title = "Rabenblatt", show = Paper },
  { id = "map-menu", title = "Rechtsklick auf ein Gildenmitglied", menu = function()
    M:Contact(env.UIParent, M.members[Scene.ROSTER[2].name])
    return menus.context and menus.context.gen, menus.context and menus.context.owner
  end },
  { id = "ca-member", title = "Werkstatt: Herstellen, Nach Mitglied", show = Advisor("make", "member", "sheet") },
  { id = "ca-member-list", title = "Werkstatt: Herstellen, Nach Mitglied, Liste", show = Advisor("make", "member", "list") },
  { id = "ca-filter", title = "Werkstatt: Filter-Menü", menu = function()
    local fb = GCA.UI.filterButton
    local dd = fb and (fb.dropdown or fb)
    return dd and dd._gen, dd
  end },
  { id = "ca-all", title = "Werkstatt: Herstellen, Für alle", show = Advisor("make", "all") },
  { id = "ca-commission", title = "Werkstatt: Herstellen lassen", show = Advisor("commission") },
  { id = "ca-whisper", title = "Angebots-Flüstertext", show = function()
    GCA.UI:OpenWhisperEditor()
    Settle()
    return env.RavenquillExpeditionCraftWhisperEditor
  end, after = function() Hide(env.RavenquillExpeditionCraftWhisperEditor) end },
  { id = "insp", title = "Betrachten-Fenster", show = function()
    Hide(GCA.UI.frame)
    GCA:ShowInspect(Scene.FOCUS, "gear")
    Settle()
    return GCA.UI.inspect
  end },
  { id = "hl-raid", title = "Raidbereitschaft", show = Overview("Readiness") },
}

local shots = {}

local function Capture1(def)
  if def.menu then
    local gen, owner = def.menu()
    if not gen then error("no menu generator") end
    return Capture.MenuScreen(def.id, def.title, gen, owner)
  end
  local root = def.show()
  if not root then error("no window") end
  return Capture.Snapshot(c, root, def.id, def.title)
end

local function Run(def)
  if next(WANTED) and not WANTED[def.id] then return end
  local ok, shot = pcall(Capture1, def)
  if ok then shots[#shots + 1] = shot else io.write("FAILED ", def.id, ": ", tostring(shot), "\n") end
  if def.after then pcall(def.after) end
end

for _, def in ipairs(SCREENS) do if def.before then Run(def) end end
Seed()
for _, def in ipairs(SCREENS) do if not def.before then Run(def) end end

os.execute((package.config:sub(1, 1) == "\\" and "mkdir \"" .. OUT:gsub("/", "\\") .. "\" 2>nul") or ("mkdir -p '" .. OUT .. "'"))
Capture.Write(OUT .. "/screens.json", shots)
io.write(#shots, " screens -> ", OUT, "/screens.json\n")
for _, e in ipairs(c.errors) do io.write("LUA ERROR ", tostring(e):sub(1, 300), "\n") end
