local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check
local RECORD = arg[1] == "--record"
local Golden = dofile(Kit.ADDONS .. "RavenquillExpedition/dev/golden.lua")
local gold = Golden.open(DEV .. "fixtures/compat_golden.lua", RECORD)

local EPOCH = 1800000000
local sched = Kit.Scheduler({ start = 100 })
local bus = Kit.Bus(sched)
local me = Kit.Client(sched, bus, "Me Smith", { guild = "Die Gilde", realm = "Forever", class = "ROGUE", level = 30,
  epoch = EPOCH, random = Kit.Random(99), addons = { "RavenquillExpedition_Highlights" }, setup = function(env)
    env.RAID_CLASS_COLORS = {}
    env.Enum = { QuestTag = {} }
    env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
    env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
    env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
    env.C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end }
    function env.GetInventoryItemLink() end
    env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
    env.LOOT_ITEM_SELF, env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
    env.LOOT_ITEM, env.LOOT_ITEM_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d."
  end })
local env, coreNS, fire = me.env, me.coreNs, me.fire
local H = me.ns.RavenquillExpedition_Highlights.H
local function sentSince(mark)
  local out = {}
  for i = mark + 1, #me.sent do local s = me.sent[i]; out[#out + 1] = s.prefix .. "|" .. s.chat .. "|" .. s.msg end
  return out
end
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Highlights")
fire("PLAYER_LOGIN")
sched:advance(5)

local ME = "Me Smith"
local T = EPOCH - 5000
local ENTRIES = {
  { k = "gear", t = T, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. T .. "#1", item = 12345, il = 33, q = 3, oil = 20, slot = 1 },
  { k = "loot", t = T + 1, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 1) .. "#2", item = 19019, q = 5, src = "bag" },
  { k = "loot", t = T + 2, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 2) .. "#3", item = 2000, q = 4 },
  { k = "loot", t = T + 3, who = "Bud Stone", lvl = 28, cls = "DRUID", by = ME, item = 3000, q = 4 },
  { k = "boss", t = T + 4, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 4) .. "#4", enc = 1084, first = true, raid = true,
    boss = "Onyxia", inst = "Onyxias Hort", grp = true, n = 12 },
  { k = "boss", t = T + 5, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 5) .. "#5", enc = 227, boss = "Taragaman der Hungerleider",
    inst = "Der Flammenschlund" },
  { k = "quest", t = T + 6, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 6) .. "#6", qid = 4321, ql = 32, tag = "elite",
    title = "Die Prüfung der Schädel – Grünäugige Gnolle" },
  { k = "quest", t = T + 7, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 7) .. "#7", qid = 4322, ql = 60, tag = "nonsense",
    title = string.rep("Überlange Questbeschreibung ", 6) },
  { k = "boss", t = T + 8, who = ME, lvl = 30, cls = "ROGUE", id = ME .. "#" .. (T + 8) .. "#8", enc = 9, boss = string.rep("Ä", 60),
    inst = string.rep("Ö", 60), grp = true, n = 3 },
  { k = "level", t = T + 9, who = ME, lvl = 40, cls = "ROGUE", id = ME .. "#" .. (T + 9) .. "#9" },
  { k = "gear", t = T + 10, who = ME, lvl = 30, cls = "SHAMAN", id = ME .. "#" .. (T + 10) .. "#10", item = 1 },
}

Kit.section("Encoder layer")
local bodies = {}
for i, e in ipairs(ENTRIES) do bodies[i] = H.Encode(e) or "<nil>" end
gold:compare("hl.encode", bodies, check)

Kit.section("Lane layer")
local laneMark = #me.sent
for i, b in ipairs(bodies) do if b ~= "<nil>" then H.channel:Send(H.ToMessage(ENTRIES[i])) end end
sched:advance(600)
gold:compare("hl.lane", sentSince(laneMark), check)

Kit.section("Decoder layer")
local goldBodies = RECORD and bodies or (gold.data["hl.encode"] or {})
local okDec, total = 0, 0
for i, e in ipairs(ENTRIES) do
  local b = goldBodies[i]
  if b and b ~= "<nil>" then
    total = total + 1
    local sender = e.by or e.who
    local d = H.Decode(sender, b)
    local same = d and d.k == e.k and d.t == e.t and d.who == e.who and d.lvl == e.lvl and d.cls == e.cls
      and (d.item == e.item or e.item == nil) and (d.enc == e.enc) and (d.qid == e.qid)
      and ((e.id and d.id == e.id) or (e.by and d.by == e.by))
    if same then okDec = okDec + 1 else print("    mismatch for entry " .. i) end
  end
end
check(okDec == total and total >= 10, ("%d/%d golden bodies decode to their entries"):format(okDec, total))

Kit.section("SavedVariables layer: old shapes load into the same tables as before")
local function lines(s) local out = {} for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end return out end
local SV_CASES = {
  fresh = { nil, nil },
  v2 = { { v = 2, settings = { share = false, questRedLevels = 4, migratedV2 = true }, guilds = { ["G@R"] = { events = { { k = "level", t = 1 } } } } },
    { seq = 7, installedAt = 1700000000, outbox = { x = { t = 1 } } } },
  noVersionRed4 = { { settings = { questRedLevels = 4 } }, { seq = "3" } },
  junk = { { settings = "broken", guilds = 5 }, { outbox = "x", seq = "abc" } },
}
local names = {}
for name in pairs(SV_CASES) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local c = SV_CASES[name]
  env.RavenquillExpeditionHighlightsDB, env.RavenquillExpeditionHighlightsCharDB = c[1], c[2]
  coreNS.SetupModuleDB(H)
  H:OnLoad()
  local cdb = env.RavenquillExpeditionHighlightsCharDB
  if cdb.installedAt == env.time() then cdb.installedAt = "<now>" end
  gold:compare("sv." .. name, lines(Golden.Serialize({ db = env.RavenquillExpeditionHighlightsDB, cdb = cdb })), check)
end

gold:finish()
Kit.finish()
