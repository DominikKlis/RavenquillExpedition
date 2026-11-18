local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local section = H.section
local GCA, advance, ns, SOURCES, check, fakeSug = H.GCA, H.advance, H.ns, H.SOURCES, H.check, H.fakeSug
local plain, captureTip, tipText, ROOT, Files, Frame = H.plain, H.captureTip, H.tipText, H.ROOT, H.Files, H.Frame
local fakeSections, plainTip = H.fakeSections, H.plainTip
H.lateGlobals()
H.templateMode = "fail"

do
  section("where to get missing recipes (own Data/Sources.lua, no other addon) + inner border")
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  local Src = UIx.Src
  local RS = ns.RecipeSources
  local REAL = SOURCES
  local cur = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local function show(d, c)
    UIx.current = c or cur
    UIx.sugList:SetData({ d })
    return UIx.sugList.pools.default[1]
  end
  local function reset() Src.Reset(); RS.world = {} end
  check(_G.CraftersJournal == nil and _G.LibQuestieDB == nil and type(REAL) == "table" and type(RS) == "table",
    "sources: CraftersJournal / QuestieDB absent in this run, Data/Sources.lua and RecipeSources.lua loaded")
  ns.Sources = nil
  reset()
  local dT = fakeSug({ known = false })
  local dP = fakeSug({ known = false, cand = { spellID = 999001, itemID = 4244, recipe = { skill = 120, src = "pattern", r = {} } } })
  check(plain(UIx.SourceLine(dT, cur)) == "Trainer (skill 100)" and plain(UIx.SourceLine(dP, cur)) == "Pattern"
    and UIx.SourceLine(fakeSug(), cur) == nil, "no data: 'Trainer (skill 100)' / 'Pattern', known recipe -> no line")
  captureTip()
  Src.AddTooltip(UIx.SourceInfo(dP, cur))
  check(tipText():find("Pattern", 1, true) and not tipText():find("Crafter's Journal", 1, true) and not tipText():find("Right-click", 1, true),
    "no data: tooltip shows the coarse label, no hint at another addon, no waypoint hint")
  local FAKE = {
    factions = { [59] = "Thorium Brotherhood" },
    trainers = { Leatherworking = { { 301, 1 }, { 303, 2 }, { 302, 2 } } },
    npcs = {
      [101] = { "Androd Fadran", "A", 1417, 0.45, 0.6 },
      [102] = { "Far Vendor", "A", 1417, 0.1, 0.1 },
      [103] = { "Horde Vendor", "H", 1417, 0.2, 0.2 },
      [104] = { "Dungeon Vendor", "", 0, 0, 0, 1585 },
      [201] = { "Defias Bandit", "X", 0, 0, 0, 40 },
      [301] = { "Apprentice Trainer", "", 1429, 0.5, 0.5 },
      [302] = { "Journeyman A", "A", 1453, 0.5, 0.5 },
      [303] = { "Journeyman H", "H", 1454, 0.5, 0.5 },
      [401] = { "Quest Giver", "A", 1429, 0.3, 0.4 },
      [666] = { 5 },
    },
    levels = { [201] = { 12, 14 } },
    quests = { [501] = { "Alliance Quest", "A", 30, { 401 } }, [502] = { "Horde Quest", "H", 30, { 401 } } },
    recipes = {
      [999001] = { s = 5000, p = 12500, rep = { 59, 6 }, v = { 103, 101, 102 }, d = { 201 } },
      [999002] = { t = 1, fee = 500 },
      [999003] = { s = 5001, q = { 502, 501 }, w = 120, wl = { 10, 20 } },
      [999004] = { s = 5002, v = { 104 }, o = 3 },
      [999005] = { s = 5003, v = { 666, 103 } },
    },
  }
  local MAPS = { [1417] = "Arathi Highlands", [1429] = "Elwynn Forest", [1453] = "Stormwind City", [1454] = "Orgrimmar" }
  local AREAS = { [40] = "Westfall", [1585] = "Blackrock Depths" }
  local pos
  C_Map = {
    GetMapInfo = function(m) return MAPS[m] and { name = MAPS[m] } or nil end,
    GetAreaInfo = function(a) return AREAS[a] end,
    GetWorldPosFromMapPos = function(m, v) return 0, { GetXY = function() return v.x * 1000 + m, v.y * 1000 end } end,
  }
  CreateVector2D = function(x, y) return { x = x, y = y } end
  UnitPosition = function() if pos then return pos[1], pos[2], 0, 0 end end
  UnitFactionGroup = function() return "Alliance" end
  C_Reputation = { GetFactionDataByID = function(id) return id == 59 and { reaction = 5 } or nil end }
  FACTION_STANDING_LABEL6 = "Honored"
  do
    local db = {
      npcs = {
        [1] = { "Mapped", "A", 1417, 0.45, 0.6, 40 }, [2] = { "Area only", "", 0, 0, 0, 1585 },
        [3] = { "Bad coords", "H", 1417, 1.5, 0.2, 40 }, [4] = { "Unknown map", "", 9999, 0.1, 0.1, 40 },
        [5] = { "Empty area", "", 0, 0, 0, 77 }, [6] = { "No place" }, [7] = { 5 }, [8] = "junk",
      },
      levels = { [1] = { 12, 14 }, [2] = { 50, 50 }, [3] = { "5", "7" }, [4] = { 1 }, [5] = "x" },
    }
    local function describe(n)
      if not n then return "nil" end
      return table.concat({ n.id, n.name, tostring(n.side), tostring(n.map), tostring(n.x), tostring(n.y), tostring(n.zone), tostring(n.level) }, "|")
    end
    local function all()
      local out = {}
      for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, "1", 99 }) do out[#out + 1] = describe(RS.NpcInfo(db, id)) end
      return table.concat(out, ";")
    end
    local savedMap = C_Map
    local MAPS2, AREAS2 = { [1417] = "Arathi Highlands" }, { [40] = "Westfall", [1585] = "Blackrock Depths", [77] = "" }
    C_Map = { GetMapInfo = function(m) return MAPS2[m] and { name = MAPS2[m] } or nil end, GetAreaInfo = function(a) return AREAS2[a] end }
    local withMap = all()
    C_Map = { GetMapInfo = function() error("boom") end, GetAreaInfo = function(a) return AREAS2[a] end }
    local erroring = all()
    C_Map = nil
    local noMap = all()
    C_Map = savedMap
    check(withMap == "1|Mapped|A|1417|0.45|0.6|Arathi Highlands|12-14;2|Area only||nil|nil|nil|Blackrock Depths|50;"
      .. "3|Bad coords|H|nil|nil|nil|Westfall|5-7;4|Unknown map||9999|0.1|0.1|Westfall|nil;5|Empty area||nil|nil|nil|nil|nil;"
      .. "6|No place|nil|nil|nil|nil|nil|nil;nil;nil;nil;nil",
      "NpcInfo: coordinates, zone from the map or else the area, levels (one, range, as strings), bad rows: " .. withMap)
    check(erroring == withMap:gsub("Arathi Highlands", "Westfall") and noMap == withMap:gsub("|Arathi Highlands|", "|nil|")
      :gsub("|Blackrock Depths|", "|nil|"):gsub("|Westfall|", "|nil|"),
      "NpcInfo: an erroring map lookup falls back to the area; no C_Map, no zone: " .. erroring .. " / " .. noMap)
  end
  ns.Sources = FAKE
  reset()
  local info = UIx.SourceInfo(dP, cur)
  local line = plain(UIx.SourceLine(dP, cur))
  check(line == "Vendor: Androd Fadran (Arathi Highlands)  +1 more" and info.list[1].count == 2,
    "sources: no position -> the first vendor your side can use (the Horde one skipped), 2 usable, '+1 more': " .. line)
  check(info.sourced and info.scroll == 5000 and info.canWaypoint and info.list[1].cost == 12500 and info.list[2].kind == "drop"
    and info.list[2].npc.map == nil and info.list[2].npc.zone == "Westfall" and info.list[2].npc.level == "12-14",
    "sources: pattern item, vendor price, vendor with coordinates, drop without (zone from the area ID, level 12-14)")
  check(info.rep and info.rep.standing == "Honored" and info.rep.name == "Thorium Brotherhood" and info.rep.met == false,
    "sources: reputation 'Honored' with the English faction name (the client has none), not met at Friendly")
  pos = { 1417 + 100, 100 }
  reset()
  check(UIx.SourceInfo(dP, cur).list[1].npc.name == "Far Vendor", "sources: with a position the nearest usable vendor wins")
  pos = nil
  reset()
  captureTip()
  Src.AddTooltip(info)
  local t = tipText()
  check(t:find("Vendor: Androd Fadran | Arathi Highlands 45, 60", 1, true) and t:find("Drop: Defias Bandit (12-14) | Westfall", 1, true)
    and t:find("Requires Honored with Thorium Brotherhood", 1, true) and t:find("+1 more vendors", 1, true)
    and t:find("show it on the map", 1, true) and not t:find("Shift-right-click", 1, true) and not t:find("pattern in chat", 1, true),
    "tooltip: vendor + coords, drop + level/zone, reputation, more vendors, click hints")
  local dTr = fakeSug({ known = false, cand = { spellID = 999002, recipe = { skill = 100, src = "trainer", r = {} } } })
  local it = UIx.SourceInfo(dTr, cur)
  check(it.list[1].kind == "trainer" and it.list[1].cost == 500 and it.list[1].npc and it.list[1].npc.name == "Journeyman A"
    and it.list[1].npc.zone == "Stormwind City",
    "sources: trainer fee, skill 100 -> a journeyman trainer of your side (not the Horde one listed first)")
  local dQ = fakeSug({ known = false, cand = { spellID = 999003, recipe = { skill = 150, src = "pattern", r = {} } } })
  local iq = UIx.SourceInfo(dQ, cur)
  check(#iq.list == 2 and iq.list[1].kind == "quest" and iq.list[1].name == "Alliance Quest" and iq.list[1].npc.name == "Quest Giver"
    and iq.list[2].kind == "world" and iq.list[2].levels[2] == 20 and plain(UIx.SourceLine(dQ, cur)) == "Quest: Alliance Quest (level 30)  +1 more",
    "sources: only your side's quest (giver placed), then the world drop with creature levels")
  local dD = fakeSug({ known = false, cand = { spellID = 999004, recipe = { skill = 150, src = "pattern", r = {} } } })
  local idg = UIx.SourceInfo(dD, cur)
  check(idg.list[1].npc.name == "Dungeon Vendor" and idg.list[1].npc.zone == "Blackrock Depths" and not idg.list[1].npc.map
    and not idg.canWaypoint and idg.list[2] and idg.list[2].kind == "objects" and idg.list[2].count == 3,
    "sources: a dungeon vendor (no coordinates: zone only, no waypoint) + 'In chests/objects (3)'")
  local dBad = fakeSug({ known = false, cand = { spellID = 999005, recipe = { skill = 150, src = "pattern", r = {} } } })
  local okBad, ib = pcall(UIx.SourceInfo, dBad, cur)
  check(okBad and ib.list[1].otherSide and plain(UIx.SourceLine(dBad, cur)) == "Vendor (other faction only)",
    "sources: a malformed NPC row and an other-side vendor -> 'Vendor (other faction only)', no error")
  local entries = Src.MenuEntries(info)
  check(#entries == 1 and entries[1].waypoint and entries[1].waypoint.name == "Androd Fadran",
    "menu: one waypoint (vendor with coordinates; not the drop without); no 'Link pattern' (user 2026-11-15)")
  local said, savedPrint = {}, GCA.Print
  GCA.Print = function(_, m) said[#said + 1] = plain(m) end
  local native, tt = {}, {}
  UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) native.st = v end }
  C_Map.SetUserWaypoint = function(p) native.p = p end
  C_Map.CanSetUserWaypointOnMap = function() return true end
  TomTom = { AddWaypoint = function(self, m, x, y, opts) tt[#tt + 1] = { self = self, m = m, x = x, y = y, title = opts and opts.title, from = opts and opts.from } return "uid" end }
  local vn = info.list[1].npc
  check(Src.SetWaypoint(vn) == true and tt[1] and tt[1].self == TomTom and tt[1].from == "Craft Advisor" and tt[1].m == 1417 and tt[1].x == 0.45 and tt[1].y == 0.6
    and tt[1].title == "Androd Fadran" and native.p == nil and said[#said] == "Waypoint set: Androd Fadran, Arathi Highlands 45, 60.",
    "waypoint: TomTom:AddWaypoint(1417, 0.45, 0.6, { title }) when TomTom is installed: " .. tostring(said[#said]))
  TomTom = { AddWaypoint = function() error("TomTom changed") end }
  check(Src.SetWaypoint(vn) == true and native.p and native.p[1] == 1417 and native.p[2] == 0.45 and native.p[3] == 0.6 and native.st == true,
    "waypoint: TomTom erroring -> C_Map.SetUserWaypoint(UiMapPoint 1417 / 0.45 / 0.6) + super-track")
  TomTom = nil
  native = {}
  check(Src.SetWaypoint(vn) == true and native.p and native.p[1] == 1417, "waypoint: no TomTom -> the client's user waypoint")
  C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap, UiMapPoint, C_SuperTrack = nil, nil, nil, nil
  check(Src.SetWaypoint(vn) == false and said[#said] == "Couldn't set a waypoint: Androd Fadran is at Arathi Highlands 45, 60.",
    "waypoint: no TomTom, no waypoint API -> the coordinates in chat: " .. tostring(said[#said]))
  check(Src.SetWaypoint(info.list[2].npc) == false and Src.SetWaypoint(idg.list[1].npc) == false, "no coordinates -> no waypoint, nothing invented")
  GCA.Print = savedPrint
  local made
  MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { items = {} }
    function root:CreateTitle(x) self.title = x end
    function root:CreateButton(x) self.items[#self.items + 1] = x end
    gen(owner, root); made = root
  end }
  check(Src.Menu(UIParent, info, "Vest") and made and made.title == "Vest" and #made.items == 1
    and made.items[1] == "Show on map: Androd Fadran (vendor)", "right-click menu via MenuUtil.CreateContextMenu (show on map)")
  local openedMap
  OpenWorldMap = function(id) openedMap = id end
  GCA.Print = function() end
  Src.ShowOnMap(vn)
  GCA.Print = savedPrint
  check(openedMap == vn.map, "clicking a source opens the world map on its zone (" .. tostring(openedMap) .. ")")
  OpenWorldMap = nil
  check(Src.ShowOnMap({ name = "x" }) == false, "no coordinates -> nothing happens")
  MenuUtil = nil
  check(Src.Menu(UIParent, { list = {} }) == false, "no coordinates and no pattern -> no menu")
  check(UIx.SourceClick(UIParent, "RightButton", fakeSug(), cur) == true and UIx.SourceClick(UIParent, "LeftButton", dP, cur) == false,
    "SourceClick: right-click handled, left click not")
  ns.Sources = { npcs = {}, recipes = setmetatable({}, { __index = function() error("boom") end }) }
  reset()
  check(plain(UIx.SourceLine(dP, cur)) == "Pattern" and plain(UIx.SourceLine(dT, cur)) == "Trainer (skill 100)", "sources: data erroring -> coarse label")
  ns.Sources = { recipes = 5 }
  reset()
  check(plain(UIx.SourceLine(dP, cur)) == "Pattern", "sources: data of the wrong shape -> treated as missing")
  ns.Sources = REAL
  C_Map, CreateVector2D, UnitPosition, C_Reputation, FACTION_STANDING_LABEL6 = nil, nil, nil, nil, nil
  reset()
  do
    local missing, n = {}, 0
    for prof, rows in pairs(ns.Recipes) do
      for id in pairs(rows) do n = n + 1; if not REAL.recipes[id] then missing[#missing + 1] = prof .. ":" .. id end end
    end
    for _, e in ipairs(ns.Enchants.rows) do n = n + 1; if not REAL.recipes[e.spell] then missing[#missing + 1] = "enchant:" .. e.spell end end
    local noNpc = {}
    for id, r in pairs(REAL.recipes) do
      for _, v in ipairs(r.v or {}) do if not REAL.npcs[v] then noNpc[#noNpc + 1] = id .. ">" .. v end end
    end
    check(#missing == 0 and #noNpc == 0, ("Data/Sources.lua covers all %d recipe rows (missing %s), every vendor has an NPC row (%s)")
      :format(n, table.concat(missing, ","), table.concat(noNpc, ",")))
    local lw = fakeSug({ known = false, cand = { spellID = 2158, recipe = { skill = 65, src = "pattern", r = {} } } })
    check(plain(UIx.SourceLine(lw, cur)) == "In chests/objects (12)", "real data: Fine Leather Boots' pattern is in 12 chests/objects: " .. plain(UIx.SourceLine(lw, cur)))
    local tr = fakeSug({ known = false, cand = { spellID = 2153, recipe = { skill = 15, src = "trainer", r = {} } } })
    local itr = UIx.SourceInfo(tr, cur)
    check(itr.sourced and itr.list[1].kind == "trainer" and itr.list[1].cost == 50 and itr.list[1].npc and REAL.npcs[itr.list[1].npc.id],
      "real data: Handstitched Leather Pants -> trainer, fee 50, a named trainer NPC")
    local found
    for id, r in pairs(REAL.recipes) do
      local all = r.v ~= nil and not r.t
      for _, v in ipairs(r.v or {}) do all = all and REAL.npcs[v][2] == "" and REAL.npcs[v][3] ~= 0 end
      if all and (not found or id < found) then found = id end
    end
    local iv = found and UIx.SourceInfo(fakeSug({ known = false, cand = { spellID = found, recipe = { skill = 1, src = "pattern", r = {} } } }), cur)
    local vs = iv and iv.list[1]
    check(vs and vs.kind == "vendor" and vs.npc.map and vs.npc.x and iv.canWaypoint and Src.MenuEntries(iv)[1],
      "real data: a pattern vendor with coordinates offers a waypoint (recipe " .. tostring(found) .. ", " .. tostring(vs and vs.npc and vs.npc.name) .. ")")
    local dh = UIx.SourceInfo(fakeSug({ known = false, cand = { spellID = 23636, recipe = { src = "pattern", skill = 295 } } }), cur)
    check(dh.list[1].kind == "vendor" and not dh.list[1].extra and dh.list[1].npc.name == "Lokhtos Darkbargainer" and dh.list[1].cost == 63529
      and dh.rep and dh.rep.name == "Thorium Brotherhood",
      "real data: Dark Iron Helm's vendor from Data/Sources.lua, its missing price from Data/ExtraSources.lua (same NPC), Thorium Brotherhood")
    local f = assert(io.open(ROOT .. "Data/Sources.lua", "rb"))
    local text = f:read("a")
    f:close()
    check(not text:find("--", 1, true) and #text < 200000,
      ("Data/Sources.lua: no comments, %d bytes"):format(#text))
  end
  do
    local bad = {}
    local files = Files.group("UI")
    files[#files + 1] = "RecipeSources.lua"
    for _, file in ipairs(files) do
      local i = 0
      for l in io.lines(ROOT .. file) do
        i = i + 1
        local code = l:gsub("%-%-.*$", "")
        if code:find("CraftersJournal", 1, true) or code:find("Questie", 1, true) then bad[#bad + 1] = file .. ":" .. i end
      end
    end
    check(#bad == 0, "regression: no CraftersJournal / QuestieDB access in UI.lua or RecipeSources.lua " .. table.concat(bad, ", "))
  end
  do
    local bad = {}
    local NO_FALLBACK = { [2740] = true, [2758] = true, [2787] = true }
    local function npc(id, where) if not REAL.npcs[id] then bad[#bad + 1] = where .. ">npc " .. tostring(id) end end
    for prof, list in pairs(REAL.trainers) do
      for _, t in ipairs(list) do
        npc(t[1], "trainer " .. prof)
        if not (type(t[2]) == "number" and t[2] >= 1 and t[2] <= 15) then bad[#bad + 1] = "trainer " .. prof .. ">ranks " .. tostring(t[2]) end
      end
    end
    for id, r in pairs(REAL.recipes) do
      for _, v in ipairs(r.v or {}) do npc(v, "recipe " .. id .. " vendor") end
      for _, q in ipairs(r.q or {}) do if not REAL.quests[q] then bad[#bad + 1] = "recipe " .. id .. ">quest " .. tostring(q) end end
      if r.rep and not (REAL.factions[r.rep[1]] or NO_FALLBACK[r.rep[1]]) then bad[#bad + 1] = "recipe " .. id .. ">faction " .. tostring(r.rep[1]) end
    end
    for qid, q in pairs(REAL.quests) do
      for _, g in ipairs(type(q[4]) == "table" and q[4] or {}) do npc(g, "quest " .. qid .. " giver") end
    end
    for id, n in pairs(REAL.npcs) do
      if type(n[1]) ~= "string" or n[1] == "" or (n[2] ~= "A" and n[2] ~= "H" and n[2] ~= "" and n[2] ~= "X") then bad[#bad + 1] = "npc " .. id end
    end
    table.sort(bad)
    check(#bad == 0, "Data/Sources.lua: every trainer, vendor and quest giver is an NPC row, every quest and faction exists "
      .. table.concat(bad, ", ", 1, math.min(#bad, 12)))
  end
  UnitFactionGroup = nil
  reset()
  do
    local dN = fakeSug({ known = false, cand = { spellID = 10550, recipe = { src = "pattern", skill = 205 } } })
    local info = UIx.SourceInfo(dN, cur)
    check(info and info.list[1] and info.list[1].kind == "drop" and info.list[1].extra and info.list[1].count == 2
      and plain(UIx.SourceLine(dN, cur)):find("Bristleback Skullcrusher (Shen'dralas)", 1, true) and info.list[1].npc.level == "42-43",
      "extra sources: Nightscape Cloak's pattern drops from Bristleback Skullcrusher in Shen'dralas (+1 more): " .. plain(UIx.SourceLine(dN, cur) or "nil"))
    local dV = fakeSug({ known = false, cand = { spellID = 23636, recipe = { src = "pattern", skill = 295 } } })
    local iv = UIx.SourceInfo(dV, cur)
    check(iv.list[1].kind == "vendor" and iv.list[1].cost == 63529 and plain(UIx.SourceLine(dV, cur)):find("Lokhtos Darkbargainer", 1, true),
      "extra sources: vendor (Dark Iron Helm from Lokhtos, with price): " .. plain(UIx.SourceLine(dV, cur) or "nil"))
    local dC = fakeSug({ known = false, cand = { spellID = 24913, recipe = { src = "pattern", skill = 300 } } })
    local ic = UIx.SourceInfo(dC, cur)
    check(ic.list[1].kind == "drop" and ic.list[2].kind == "container" and UIx.Src.LineOf(ic.list[2], ic) == "Found in: Decoded True Believer Clippings",
      "extra sources: drop + 'Found in: <item>' (Darkrune Helm)")
    captureTip(); GameTooltip:SetOwner(UIParent); UIx.Src.AddTooltip(ic)
    check(tipText():find("Found in: Decoded True Believer Clippings", 1, true) and tipText():find("Cenarion Hold Infantry", 1, true), "extra sources in the source tooltip")
    Src.Reset()
  end
  ns.Sources = nil
  reset()
  local tags = UIx.CraftTags(dT)
  local tag
  for _, x in ipairs(tags) do if x[1] == "Not learned" then tag = x end end
  check(tag == nil and UIx.LearnText(dT, cur):find(UIx.COLORS.notLearnedTag, 1, true) and UIx.LearnText(fakeSug({ known = false, cand = { spellID = 1, recipe = {} } }), cur),
    "no grey 'Not learned' tag any more; one red source text (UI.LearnText) for every view")
  local b = show(dT)
  check(b.source == nil and b.nl._shown and plain(b.nl.text._text) == "Trainer (skill 100)"
    and b.nl.text._text:find("TrainerGossipIcon", 1, true) and b.nl.text._text:find(UIx.COLORS.notLearnedTag, 1, true) and b._SetHeight[1] == 50,
    "unlearned card = the best source with its icon (trainer), red, no third source line, 50 px: " .. plain(b.nl.text._text))
  do
    local S = UIx.Src
    check(S.Icon("quest"):find("AvailableQuestIcon", 1, true) and S.Icon("vendor"):find("VendorGossipIcon", 1, true)
      and S.Icon("drop"):find("Skull", 1, true) and S.Icon("world"):find("INV_Misc_Map_01", 1, true) and S.Icon("nope"):find("INV_Scroll_03", 1, true),
      "source icons: quest !, vendor bag, mob drop skull, world drop map, other = scroll")
    check(S.Money(1250305) == "125g 3s 5c" and S.Money(20000) == "2g" and S.Money(0) == nil,
      "money without GetCoinTextureString: '125g 3s 5c', zero parts left out, nothing for 0")
    check(S.PatternPrice({ scroll = 5000 }) == nil, "no Auctionator: no pattern price")
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id == 5000 and 125000 or nil end } } }
    local savedGet = GCA.GetInfo
    GCA.GetInfo = function(self, id) if id == 5000 then return { bind = 2 } elseif id == 5001 then return { bind = 1 } end return savedGet(self, id) end
    check(S.PatternPrice({ scroll = 5000 }) == 125000 and S.PatternPrice({ scroll = 5001 }) == nil,
      "BoE pattern: Auctionator's price; a BoP pattern: none")
    local vend = { cj = true, scroll = 5000, canWaypoint = true, skill = 100, have = 120,
      list = { { kind = "vendor", cost = 12000, npc = { name = "Androd", zone = "Arathi", map = 1, x = 0.4, y = 0.5 } },
               { kind = "trainer", cost = 500 } } }
    captureTip()
    S.AddTooltip(vend, { click = "CLICK", right = "RIGHT" })
    local t = plain(tipText())
    local iPrice, iVend, iAH = t:find("\nPrice\n", 1, true), t:find("At the vendor | ", 1, true), t:find("In the auction house | ", 1, true)
    check(t:find("Where to get it", 1, true) and t:find("Vendor: Androd | Arathi 40, 50", 1, true) and t:find("Trainer | Skill 100 (reached)", 1, true)
      and iPrice and iVend and iAH and iPrice < iVend and iVend < iAH and t:find("At the trainer | ", 1, true)
      and t:find("Pattern | ", 1, true) and t:find("CLICK\nRIGHT", 1, true),
      "tooltip: sources with icons + where, then 'Price' (vendor / trainer / auction house), pattern, two hint lines: " .. t:gsub("\n", " / "))
    check(not plain(UIx.SourceBadge(fakeSug({ known = false }), cur) or ""):find("|", 1, true), "the source line itself has no prices any more")
    captureTip()
    S.AddTooltip({ cj = true, list = { { kind = "drop", npcs = { { name = "Bandit", level = 12, zone = "Westfall" } } } } })
    check(not tipText():find("Price", 1, true), "a drop without an AH price: no price block")
    GCA.GetInfo = savedGet
    Auctionator = nil
  end
  H.tip, H.hyper = {}, {}
  b.nl._scripts.OnEnter(b.nl)
  check(tipText():find("Not learned", 1, true) and tipText():find("Trainer", 1, true),
    "hovering 'Not learned' shows where to get the recipe: " .. tipText():gsub("\n", " | "))
  local okClick = pcall(b.nl._scripts.OnClick, b.nl, "LeftButton")
  local okRight = pcall(b.nl._scripts.OnClick, b.nl, "RightButton")
  check(okClick and okRight, "clicking 'Not learned' (left: map marker / right: menu) raises no error")
  b = show(fakeSug())
  check(not b.nl._shown and b._SetHeight[1] == 50, "known recipe -> no 'Not learned' button, 50 px")
  local de = ns.Locales.deDE
  check(string.format(de.SRC_LINE_VENDOR, "A", "B") == "Händler: A (B)" and string.format(de.SRC_LINE_TRAINER_HAVE, 170, 150) == "Lehrer (Fertigkeit 170, du hast 150)"
    and de.FILTER_UNLEARNED == "Fehlende Rezepte zeigen" and de.NOT_LEARNED == "Nicht erlernt", "German texts")
  local nsf = UIx.AddInnerBorder(CreateFrame("Frame", nil, UIParent))
  check(nsf and nsf.how == "atlas" and nsf.TopLeftCorner._atlas == "UI-Frame-InnerTopLeft" and nsf.RightEdge._atlas == "!UI-Frame-InnerRightTile"
    and nsf.BottomLeftCorner._points[1][5] == -1 and nsf.TopEdge._h == 3 and nsf.LeftEdge._w == 3,
    "inner border: 6x6 corners (bottom at y -1), 3 px tiles, probe atlases")
  NineSliceUtil = { ApplyLayoutByName = function(f, name) f.TopLeftCorner = { layout = name } end }
  local nsu = UIx.AddInnerBorder(CreateFrame("Frame", nil, UIParent))
  check(nsu.how == "util" and nsu.TopLeftCorner.layout == "InsetFrameTemplate", "inner border: NineSliceUtil 'InsetFrameTemplate' layout when present")
  NineSliceUtil = nil
  local origInfo = C_Texture.GetAtlasInfo
  C_Texture.GetAtlasInfo = function(name)
    local i = origInfo(name)
    if i and name:find("^Skillbar_") then i.leftTexCoord, i.rightTexCoord, i.topTexCoord, i.bottomTexCoord = 0.1, 0.9, 0, 1 end
    if name == "Skillbar_Fill_Flipbook_Tailoring" then return { width = 1, height = 1, file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end
    return i
  end
  local rb = UIx.CreateProfessionPicker and UIx.CreateProfessionPicker(UIx.frame, UIx.frame)
  if rb then
    rb:SetSkill("Lederverarbeitung 150/300", 150, 300, "Leatherworking")
    local tc = rb.fill._SetTexCoord
    check(rb.barKind == "atlas" and rb.fill._atlas == "Skillbar_Fill_Flipbook_Leatherworking" and rb.flare._atlas == "Skillbar_Flare_Leatherworking"
      and rb.clip and rb.fill._w == UIx.PROF_BAR_W - 10 and math.abs(rb.clip._w - (UIx.PROF_BAR_W - 10) * 0.5) < 1e-9
      and tc and math.abs(tc[1] - 0.1) < 1e-9 and math.abs(tc[2] - 0.5) < 1e-9 and math.abs(tc[4] - 1 / 30) < 1e-9
      and rb.flare._shown and rb.flare._points[1][2] == rb.clip,
      "rank bar: LW flipbook fill at full width in a clipping frame cut to 50 %, one frame (row 1 of 30, column 1 of 2), flare at the cut")
    local anim = {}
    local fakeAG = { Play = function() anim.played = (anim.played or 0) + 1 end, Stop = function() end, SetLooping = function(_, v) anim.loop = v end,
      CreateAnimation = function(_, kind)
        anim.kind = kind
        return { SetFlipBookRows = function(_, v) anim.rows = v end, SetFlipBookColumns = function(_, v) anim.cols = v end,
          SetFlipBookFrames = function(_, v) anim.frames = v end, SetDuration = function(_, v) anim.dur = v end }
      end }
    local origCT2 = Frame.CreateTexture
    Frame.CreateTexture = function(self, ...) local t = origCT2(self, ...); t.CreateAnimationGroup = function() return fakeAG end; return t end
    local rb2 = UIx.CreateProfessionPicker(UIx.frame, UIx.frame)
    Frame.CreateTexture = origCT2
    rb2:SetSkill("x", 150, 300, "Leatherworking"); rb2:SetSkill("x", 150, 300, "Leatherworking")
    check(rb2.anim == fakeAG and anim.kind == "FlipBook" and anim.rows == 30 and anim.cols == 2 and anim.frames == 60 and anim.dur == 2
      and anim.loop == "NONE" and anim.played == 1, "rank bar: FlipBook 30x2, 60 frames, 2 s, played once per new rank (not on every refresh)")
    rb2:SetSkill("x", 151, 300, "Leatherworking")
    check(anim.played == 2, "rank bar: a new rank plays it again")
    rb:SetSkill("Schneiderei 300/300", 300, 300, "Tailoring")
    check(rb.fill._atlas == "Skillbar_Fill_Flipbook_Tailoring" and rb.flare._atlas == "Skillbar_Flare_Leatherworking" and not rb.flare._shown,
      "rank bar: the profession's own fill when the client has it, LW flare as fallback, no flare at 100 %")
  else
    check(false, "rank bar: UI.CreateProfessionPicker exported for the test")
  end
  C_Texture.GetAtlasInfo = origInfo
  UIx.frame:Hide()
end

do
  section("W: weapon rows in the list, the sheet and guild needs")
  local errBefore = GCA.UI.errorCount or 0
  local E = { key = "kw", set = { weights = { Strength = 1, MainHandDps = 2, TwoHandDps = 2, OffHandDps = 1 }, source = {} },
    raw = { source = { kind = "sim", minLevel = 30, maxLevel = 40 } }, class = "WARRIOR", spec = "FURY", level = 40, share = 0.5, t = 1 }
  local function eq(name, cstats, speed) return { name = name, quality = 2, icon = 135, link = "|Hitem:77|h[" .. name .. "]|h", cstats = cstats, speed = speed, scores = {} } end
  local eqInfo = { [16] = eq("Old Sword", { Strength = 2, MainHandDps = 15 }, 2.6), [17] = eq("Old Left Sword", { MainHandDps = 10 }, 2.4),
    [18] = eq("Old Gun", { Agility = 1, RangedDps = 8 }, 3.0) }
  local items = { [16] = "item:77", [17] = "item:78", [18] = "item:79" }
  local function rec() return { skill = 100, src = "trainer", r = {} } end
  local twoH = fakeSug({ e = E, slot = 16, points = 9, pct = 0.3, bothHands = true, equipped = { name = "Old Sword + Old Left Sword", quality = 2,
      cstats = { Strength = 2, MainHandDps = 15, OffHandDps = 10 }, speed = 2.6 },
    cand = { spellID = 9101, itemID = 9101, recipe = rec() }, info = { name = "Craft Greatsword", quality = 3, icon = "x", minLevel = 30,
      link = "|Hitem:9101|h[Craft Greatsword]|h", cstats = { Strength = 20, TwoHandDps = 45 }, speed = 3.4 } })
  local offH = fakeSug({ e = E, slot = 17, hand = "off", points = 4, pct = 0.1, equipped = eqInfo[17],
    cand = { spellID = 9102, itemID = 9102, recipe = rec() }, info = { name = "Craft Sword", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9102|h[Craft Sword]|h", cstats = { Strength = 8, MainHandDps = 30 }, speed = 2.6 } })
  local partner = fakeSug({ e = E, slot = 16, status = "needs-partner", tier = 2, pct = nil, points = 3, equipped = eqInfo[16],
    cand = { spellID = 9103, itemID = 9103, recipe = rec() }, info = { name = "Lonely Sword", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9103|h[Lonely Sword]|h", cstats = { Strength = 4, MainHandDps = 20 } } })
  local gun = fakeSug({ e = E, slot = 18, points = 2, pct = 0.2, equipped = eqInfo[18],
    cand = { spellID = 9104, itemID = 9104, recipe = rec() }, info = { name = "Craft Gun", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9104|h[Craft Gun]|h", cstats = { Agility = 5, RangedDps = 30 }, speed = 3.0 } })
  local UIx = GCA.UI
  check(UIx.RowPair(offH) == "off hand" and UIx.RowPair(twoH) == nil and UIx.RowPair({ kind = "item", slot = 12 }) == "Ring 2",
    "RowPair: 'off hand' for a one-hander scored in the off hand; rings keep 'Ring 2'")
  local tags = {}
  for _, t in ipairs(UIx.CraftTags(partner)) do tags[#tags + 1] = t[1] end
  local tags2 = {}
  for _, t in ipairs(UIx.CraftTags(twoH)) do tags2[#tags2 + 1] = t[1] end
  local shieldP = fakeSug({ e = E, slot = 17, status = "needs-partner", equipped = eqInfo[16] })
  check(table.concat(tags, "|"):find("needs an off hand", 1, true) and table.concat(tags2, "|"):find("replaces both hands", 1, true)
    and UIx.CraftTags(shieldP)[1][1] == "needs a main hand", "tags: 'needs an off hand' / 'needs a main hand' / 'replaces both hands'")
  local okUnnamed, unnamedTags = pcall(UIx.CraftTags, { kind = "enchant", item = { name = "Cloak" }, equipped = {} })
  check(okUnnamed and unnamedTags[1][1] == "replaces ? on Cloak",
    "enchant tag with an unnamed current enchant: 'replaces ? on Cloak': " .. tostring(okUnnamed and unnamedTags[1][1] or unnamedTags))
  local d1 = UIx.StatDiff(twoH)
  check(d1[1].speed == 3.4 and UIx.StatText(d1[1]) == "Speed 2.60 → 3.40", "stat differences: speed first, 'Speed 2.60 → 3.40': " .. UIx.StatText(d1[1]))
  local dps = {}
  for _, r in ipairs(d1) do if r.key == "TwoHandDps" or r.key == "MainHandDps" or r.key == "OffHandDps" then dps[#dps + 1] = UIx.StatText(r) end end
  check(table.concat(dps, ", "):find("+45 DPS", 1, true), "DPS lines in the stat differences: " .. table.concat(dps, ", "))
  local same = fakeSug({ e = E, equipped = eq("Same", { MainHandDps = 1 }, 2.6), info = { name = "S", cstats = { MainHandDps = 2 }, speed = 2.6 } })
  check(UIx.StatDiff(same)[1].key ~= "Speed" and UIx.StatDiff(partner)[1].key ~= "Speed", "same speed / no speed read: no speed line")
  GCA.UI:Toggle(); advance(1)
  UIx.current = { key = "Bud Stone", online = true, prof = "Blacksmithing", level = 40, class = "WARRIOR" }
  UIx.sugList:SetData(UIx.SectionRows(fakeSections({ [16] = { twoH, partner }, [17] = { offH }, [18] = { gun } })))
  local secs, titles = {}, {}
  for _, x in ipairs(UIx.sugList.pools.section) do if x._shown ~= false and x.data and x.data.sec then secs[x.data.sec.key] = x; titles[x.data.sec.key] = UIx.SectionTitle(x.data.sec) end end
  check(secs[16] and secs[17] and secs[18] and titles[16] == "Main Hand" and titles[17] == "Off Hand" and titles[18] == "Ranged",
    "list: weapon sections Main Hand / Off Hand / Ranged: " .. tostring(titles[16]) .. "/" .. tostring(titles[17]) .. "/" .. tostring(titles[18]))
  local cards = {}
  for _, b in ipairs(UIx.sugList.pools.default) do if b.data and b.data.cand then cards[b.data.cand.itemID] = b end end
  check(cards[9102] and plain(cards[9102].title._text) == "Craft Sword (off hand)" and cards[9102].offer._shown,
    "card: 'Craft Sword (off hand)', Offer shown as for armour")
  check(cards[9103] and plain(cards[9103].sub._text):find("needs an off hand", 1, true), "card: the needs-partner row says 'needs an off hand': " .. plain(cards[9103] and cards[9103].sub._text))
  check(cards[9101] and not plain(cards[9101].sub._text):find("Speed", 1, true) and plain(cards[9101].sub._text):find("replaces both hands", 1, true),
    "card: second line = 'replaces both hands' (no speed/stat changes on cards): " .. plain(cards[9101] and cards[9101].sub._text))
  check(UIx.NeedsCatTitle(16) == "Main Hand" and UIx.NeedsCatTitle(17) == "Off Hand" and UIx.NeedsCatTitle(18) == "Ranged", "guild needs categories Main Hand / Off Hand / Ranged")
  captureTip(); cards[9101]._scripts.OnEnter(cards[9101])
  check(plainTip("9101"), "a weapon row's tooltip = the item + only the stat-change block: " .. tipText())
  ns.locale = "deDE"
  check(UIx.StatText(UIx.StatDiff(twoH)[1]) == "Tempo 2,60 → 3,40" and UIx.NeedsCatTitle(16) == "Haupthand" and UIx.NeedsCatTitle(17) == "Nebenhand"
    and UIx.NeedsCatTitle(18) == "Distanz" and UIx.RowPair(offH) == "Nebenhand" and UIx.CraftTags(partner)[1][1] == "braucht eine Nebenhand"
    and UIx.CraftTags(twoH)[1][1] == "ersetzt beide Hände", "German: 'Tempo 2,60 → 3,40', Haupthand/Nebenhand/Distanz, 'braucht eine Nebenhand', 'ersetzt beide Hände'")
  ns.locale = "enUS"
  UIx.frame:Hide()
  local function member(key, rowsBy)
    local list = {}
    for _, rows in pairs(rowsBy) do for _, r in ipairs(rows) do list[#list + 1] = r end end
    table.sort(list, GCA.SuggestionOrder)
    list.sections = GCA:BuildSections(rowsBy, {}, items, eqInfo, {}, E)
    return { key = key, online = true, class = "WARRIOR", level = 40, prof = "Blacksmithing", state = "ok", weights = E,
      member = { items = items, time = time(), source = "inspect" }, suggestions = list, best = list[1], knownCount = #list,
      spec = "FURY", specHow = "manual" }
  end
  local wm = member("Wes Arms", { [16] = { twoH, partner }, [17] = { offH }, [18] = { gun } })
  local origML = GCA.GetMemberList
  GCA.GetMemberList = function() return { wm } end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  UIx:SetMemberMode("sheet")
  UIx.selected, UIx.autoKey = "Wes Arms", nil
  UIx:SetView("member")
  local sh, c = UIx.sheet, UIx.sheet.centre
  check(sh.slots[16].badge._shown and sh.slots[17].badge._shown and sh.slots[18].badge._shown and not sh.slots[5].badge._shown,
    "sheet: upgrade badges on main hand, off hand and ranged")
  sh.slots[16]._scripts.OnClick(sh.slots[16])
  local st = {}
  for i = 1, c.nStats do st[i] = plain(c.stats[i]._text) end
  check(UIx.sheetSlot == 16 and c.featured == twoH and plain(c.best.name._text) == "Craft Greatsword" and st[1] == "Speed 2.60 → 3.40"
    and plain(c.tags._text):find("replaces both hands", 1, true), "sheet main hand: the greatsword featured, speed line first, 'replaces both hands': " .. table.concat(st, ", "))
  sh.slots[17]._scripts.OnClick(sh.slots[17])
  check(c.featured == offH and c.offer._shown, "sheet off hand: the off-hand one-hander, Offer shown")
  check((UIx.errorCount or 0) == errBefore, "W: no error reported: " .. tostring(GCA:Diag().lastError and GCA:Diag().lastError.msg or ""))
  UIx.frame:Hide()
  GCA.GetMemberList = origML
  UIx:SetMemberMode("list")
end

H.finish()
