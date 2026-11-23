local Data = {}

Data.GLOBALS = {
  HEADSLOT = "Kopf", NECKSLOT = "Hals", SHOULDERSLOT = "Schulter", BACKSLOT = "Rücken", CHESTSLOT = "Brust", SHIRTSLOT = "Hemd",
  TABARDSLOT = "Wappenrock", WRISTSLOT = "Handgelenke", HANDSSLOT = "Hände", WAISTSLOT = "Taille", LEGSSLOT = "Beine",
  FEETSLOT = "Füße", FINGER0SLOT = "Finger", FINGER1SLOT = "Finger", TRINKET0SLOT = "Schmuck", TRINKET1SLOT = "Schmuck",
  MAINHANDSLOT = "Waffenhand", SECONDARYHANDSLOT = "Schildhand", RANGEDSLOT = "Distanz",
  ITEM_CLASSES_ALLOWED = "Klassen: %s", ITEM_REQ_SKILL = "Benötigt %s",
  ITEM_QUALITY0_DESC = "Schlecht", ITEM_QUALITY1_DESC = "Verbreitet", ITEM_QUALITY2_DESC = "Selten", ITEM_QUALITY3_DESC = "Rar",
  ITEM_QUALITY4_DESC = "Episch", ITEM_QUALITY5_DESC = "Legendär",
}

local function cc(r, g, b, hex) return { r = r, g = g, b = b, colorStr = "ff" .. hex, GenerateHexColor = function() return "ff" .. hex end } end
Data.CLASS_COLORS = {
  WARRIOR = cc(0.78, 0.61, 0.43, "c79c6e"), MAGE = cc(0.41, 0.8, 0.94, "69ccf0"), ROGUE = cc(1, 0.96, 0.41, "fff569"),
  DRUID = cc(1, 0.49, 0.04, "ff7d0a"), HUNTER = cc(0.67, 0.83, 0.45, "abd473"), SHAMAN = cc(0, 0.44, 0.87, "0070de"),
  PRIEST = cc(1, 1, 1, "ffffff"), WARLOCK = cc(0.58, 0.51, 0.79, "9482c9"), PALADIN = cc(0.96, 0.55, 0.73, "f58cba"),
}
Data.CLASS_NAMES = setmetatable({ WARRIOR = "Krieger", MAGE = "Magier", PRIEST = "Priester", ROGUE = "Schurke", PALADIN = "Paladin",
  DRUID = "Druide", HUNTER = "Jäger", WARLOCK = "Hexenmeister", SHAMAN = "Schamane" }, { __index = function(_, k) return k end })
Data.ZONES = { [1429] = "Wald von Elwynn", [1428] = "Brennende Steppe", [1446] = "Tanaris", [1423] = "Östliche Pestländer",
  [1417] = "Arathihochland", [1452] = "Winterquell", [1433] = "Rotkammgebirge" }
Data.QUALITY = { [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 },
  [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 } }

Data.ROSTER = {
  { name = "Lyra Distelbach", class = "MAGE", level = 40, zone = "Wald von Elwynn", online = true },
  { name = "Rika Steinbeck", class = "WARRIOR", level = 58, zone = "Brennende Steppe", online = true, peer = true, pos = { 1428, 0.62, 0.38, "", 12 } },
  { name = "Hanne Moosgrund", class = "ROGUE", level = 39, zone = "Arathihochland", online = true, peer = true, pos = { 1417, 0.45, 0.55, "s", 40 } },
  { name = "Ole Fichtental", class = "DRUID", level = 44, zone = "Tanaris", online = true, peer = true, pos = { 1446, 0.51, 0.29, "", 8 } },
  { name = "Mira Sturmfeder", class = "PRIEST", level = 60, zone = "Östliche Pestländer", online = true, peer = true, pos = { 1423, 0.75, 0.52, "", 400 } },
  { name = "Ilsa Brunnhold", class = "SHAMAN", level = 36, zone = "Rotkammgebirge", online = true },
  { name = "Tamo Eichengrund", class = "HUNTER", level = 41, zone = "Feralas", online = false, peer = true },
  { name = "Bodo Kesselring", class = "PALADIN", level = 52, zone = "Winterquell", online = false, peer = true },
  { name = "Kael Wintermoor", class = "WARLOCK", level = 50, zone = "Silithus", online = false },
}

local ICON = "Interface\\Icons\\"
local ITEMS = {
  [8176] = { name = "Stirnband des Nachtschleichers", q = 2, il = 37, ml = 32, loc = "INVTYPE_HEAD", icon = ICON .. "INV_Misc_Bandana_03" },
  [8175] = { name = "Tunika des Nachtschleichers", q = 2, il = 37, ml = 32, loc = "INVTYPE_CHEST", icon = ICON .. "INV_Chest_Leather_04" },
  [8204] = { name = "Zähe Skorpidhandschuhe", q = 2, il = 40, ml = 35, loc = "INVTYPE_HAND", icon = ICON .. "INV_Gauntlets_21" },
  [8187] = { name = "Schildkrötenschuppenhandschuhe", q = 2, il = 36, ml = 31, loc = "INVTYPE_HAND", icon = ICON .. "INV_Gauntlets_11" },
  [8207] = { name = "Zähe Skorpidschultern", q = 2, il = 43, ml = 38, loc = "INVTYPE_SHOULDER", icon = ICON .. "INV_Shoulder_08" },
  [8193] = { name = "Hose des Nachtschleichers", q = 2, il = 41, ml = 36, loc = "INVTYPE_LEGS", icon = ICON .. "INV_Pants_Leather_08" },
  [8211] = { name = "Wildlederweste", q = 2, il = 40, ml = 35, loc = "INVTYPE_CHEST", icon = ICON .. "INV_Chest_Leather_09" },
  [8214] = { name = "Wildlederhelm", q = 2, il = 40, ml = 35, loc = "INVTYPE_HEAD", icon = ICON .. "INV_Helmet_41" },
  [8213] = { name = "Wildlederstiefel", q = 2, il = 44, ml = 39, loc = "INVTYPE_FEET", icon = ICON .. "INV_Boots_Wolf" },
  [8198] = { name = "Schildkrötenschuppenarmschienen", q = 2, il = 39, ml = 34, loc = "INVTYPE_WRIST", icon = ICON .. "INV_Bracer_07" },
  [2041] = { name = "Tunika von Westfall", q = 3, il = 26, ml = 21, loc = "INVTYPE_CHEST", icon = ICON .. "INV_Chest_Leather_03" },
  [9624] = { name = "Stolperläufer-Latzhose", q = 3, il = 33, ml = 28, loc = "INVTYPE_LEGS", icon = ICON .. "INV_Pants_Leather_03" },
  [2278] = { name = "Schulterklappen des Fährtenlesers", q = 3, il = 30, ml = 25, loc = "INVTYPE_SHOULDER", icon = ICON .. "INV_Shoulder_07" },
  [4253] = { name = "Gestärkte Lederhandschuhe", q = 2, il = 30, ml = 25, loc = "INVTYPE_HAND", icon = ICON .. "INV_Gauntlets_05" },
  [6713] = { name = "Kopftuch des Pfadfinders", q = 2, il = 28, ml = 23, loc = "INVTYPE_HEAD", icon = ICON .. "INV_Misc_Bandana_01" },
  [6716] = { name = "Kettenstiefel des Wegelagerers", q = 2, il = 33, ml = 28, loc = "INVTYPE_FEET", icon = ICON .. "INV_Boots_03" },
  [6714] = { name = "Weste aus Wolfspelz", q = 2, il = 36, ml = 31, loc = "INVTYPE_CHEST", icon = ICON .. "INV_Chest_Leather_01" },
  [6717] = { name = "Lederkappe des Wanderers", q = 2, il = 34, ml = 29, loc = "INVTYPE_HEAD", icon = ICON .. "INV_Helmet_15" },
  [6718] = { name = "Armschienen des Jägers", q = 1, il = 30, ml = 25, loc = "INVTYPE_WRIST", icon = ICON .. "INV_Bracer_02" },
  [4304] = { name = "Dickes Leder", q = 1, il = 40, loc = "", icon = ICON .. "INV_Misc_LeatherScrap_08" },
  [4291] = { name = "Seidenfaden", q = 1, il = 25, loc = "", icon = ICON .. "INV_Fabric_Silk_02" },
  [8343] = { name = "Schwerer Seidenfaden", q = 1, il = 40, loc = "", icon = ICON .. "INV_Fabric_Silk_03" },
  [8154] = { name = "Skorpidschuppe", q = 1, il = 40, loc = "", icon = ICON .. "INV_Misc_Monsterscales_09" },
  [8167] = { name = "Schildkrötenschuppe", q = 1, il = 40, loc = "", icon = ICON .. "INV_Misc_Monsterscales_15" },
  [8153] = { name = "Wildranke", q = 1, il = 40, loc = "", icon = ICON .. "INV_Misc_Herb_03" },
  [8172] = { name = "Geheilter dicker Balg", q = 1, il = 40, loc = "", icon = ICON .. "INV_Misc_LeatherScrap_11" },
  [4338] = { name = "Magiestoff", q = 1, il = 35, loc = "", icon = ICON .. "INV_Fabric_Mageweave_01" },
}
for id, it in pairs(ITEMS) do it.id = id end
Data.ITEMS = ITEMS

function Data.ItemFor(v)
  local id = tonumber(v) or tonumber(tostring(v):match("item:(%d+)"))
  return id and ITEMS[id]
end

function Data.Link(it)
  local hex = ({ [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" })[it.q] or "ffffffff"
  return "|c" .. hex .. "|Hitem:" .. it.id .. "::::::::40:::::::::|h[" .. it.name .. "]|h|r"
end

function Data.Icons(newsItems)
  local names = { [5001] = "INV_Sword_39", [5002] = "INV_Jewelry_Ring_04", [5003] = "INV_Sword_27", [5004] = "INV_Misc_Book_11" }
  for id, it in pairs(newsItems) do if names[id] then it.icon = ICON .. names[id] end end
end

local function ClassOf(name)
  for _, r in ipairs(Data.ROSTER) do if r.name == name then return r.class end end
end

function Data.Highlights(NK)
  local At = NK.At
  local function E(k, who, t, fields)
    local e = NK.E(k, who, t, fields)
    e.cls = ClassOf(who)
    return e
  end
  return {
    E("boss", "Rika Steinbeck", At(20, 0, 23), { inst = "Geschmolzener Kern", boss = "Lucifron", enc = 1 }),
    E("boss", "Rika Steinbeck", At(20, 0, 51), { inst = "Geschmolzener Kern", boss = "Magmadar", enc = 2 }),
    E("gear", "Hanne Moosgrund", At(20, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }),
    E("level", "Ole Fichtental", At(20, 9, 5), { lvl = 44 }),
    E("skill", "Ilsa Brunnhold", At(20, 11, 11), { skill = "Leatherworking", rank = 225 }),
    E("quest", "Mira Sturmfeder", At(20, 13), { qid = 11, title = "Einstimmung auf den Kern", tag = "special" }),
    E("mount", "Bodo Kesselring", At(20, 17), { lvl = 40 }),
    E("rep", "Mira Sturmfeder", At(20, 19), { st = 8, fac = "Argentumdämmerung" }),
    E("loot", "Rika Steinbeck", At(20, 20, 40), { item = 5001, q = 4, il = 50 }),
    E("level", "Tamo Eichengrund", At(19, 22, 14), { lvl = 40 }),
    E("boss", "Ole Fichtental", At(19, 21, 3), { inst = "Scharlachrotes Kloster", boss = "Hochinquisitor Weißsträhne", enc = 4 }),
  }
end

Data.FOCUS = "Hanne Moosgrund"

local function Info(id, cstats)
  local it = ITEMS[id]
  return { name = it.name, link = Data.Link(it), quality = it.q, icon = it.icon, minLevel = it.ml, itemLevel = it.il,
    equipLoc = it.loc, cstats = cstats or {}, scores = {} }
end

local MEMBERS = {
  ["Hanne Moosgrund"] = {
    class = "ROGUE", level = 39, spec = "COMBAT", source = "inspect", ago = 12 * 60,
    weights = { Agility = 1, Stamina = 0.5, Armor = 0.05, MeleeHit = 10, Strength = 0.8, AttackPower = 0.4 },
    worn = { [1] = { 6713, { Agility = 4, Stamina = 3 } }, [3] = { 2278, { Agility = 6, Stamina = 2 } }, [5] = { 2041, { Agility = 8, Stamina = 5 } },
      [7] = { 9624, { Agility = 9, Stamina = 6 } }, [8] = { 6716, { Agility = 4 } }, [9] = { 6718, { Stamina = 2 } }, [10] = { 4253, { Agility = 3 } } },
    sugs = {
      { slot = 10, spell = 10542, item = 8204, points = 18, cstats = { Agility = 9, Stamina = 4 } },
      { slot = 10, spell = 10509, item = 8187, points = 9, extra = true, cstats = { Agility = 5, Stamina = 5 } },
      { slot = 1, spell = 10507, item = 8176, points = 12, cstats = { Agility = 8, Stamina = 6 } },
      { slot = 3, spell = 10564, item = 8207, points = 11, cstats = { Agility = 10, Stamina = 4 } },
      { slot = 7, spell = 10548, item = 8193, points = 15, future = true, wearAt = 41, cstats = { Agility = 14, Stamina = 8 } },
      { slot = 5, spell = 10499, item = 8175, points = 4, cstats = { Agility = 9, Stamina = 7 } },
    },
  },
  ["Ole Fichtental"] = {
    class = "DRUID", level = 44, spec = "FERAL_CAT", source = "sync", ago = 3 * 3600,
    weights = { Agility = 1, Strength = 1.2, Stamina = 0.4, Armor = 0.05 },
    worn = { [1] = { 6717, { Agility = 5 } }, [5] = { 6714, { Agility = 7, Strength = 4 } }, [8] = { 6716, { Agility = 4 } } },
    sugs = {
      { slot = 5, spell = 10544, item = 8211, points = 21, cstats = { Agility = 12, Strength = 8 } },
      { slot = 1, spell = 10546, item = 8214, points = 14, cstats = { Agility = 10, Strength = 6 } },
      { slot = 8, spell = 10566, item = 8213, points = 9, cstats = { Agility = 8, Stamina = 5 } },
    },
  },
  ["Tamo Eichengrund"] = {
    class = "HUNTER", level = 41, spec = "MARKSMANSHIP", source = "sync", ago = 26 * 3600,
    weights = { Agility = 1, Stamina = 0.4, AttackPower = 0.5 },
    worn = { [9] = { 6718, { Stamina = 2 } } },
    sugs = { { slot = 9, spell = 10518, item = 8198, points = 7, cstats = { Agility = 5, Stamina = 6 } } },
  },
  ["Rika Steinbeck"] = { class = "WARRIOR", level = 58, spec = "FURY", source = "sync", ago = 40 * 60, weights = { Strength = 1 },
    worn = {}, sugs = {} },
}

function Data.Craft(GCA, env)
  local now = env.time()
  GCA.db.members = GCA.db.members or {}
  for key, m in pairs(MEMBERS) do
    local items = {}
    for slot, w in pairs(m.worn) do items[slot] = "item:" .. w[1] .. "::::::::40" end
    GCA.db.members[key] = { items = items, time = now - m.ago, source = m.source, class = m.class, level = m.level }
  end
  local realSpec = GCA.MemberSpec
  GCA.MemberSpec = function(self, key, class, items)
    local m = MEMBERS[key]
    if m then return m.spec, m.source == "inspect" and "inspected" or "synced", false end
    return realSpec(self, key, class, items)
  end
  GCA.MemberSuggestions = function(self, view)
    local m = MEMBERS[view.key]
    if not m then return {}, nil, "ok", nil end
    local E = { key = view.key, set = { weights = m.weights, source = {} }, raw = { source = { kind = "sim", minLevel = m.level - 5, maxLevel = m.level + 5 } },
      class = m.class, spec = m.spec, level = m.level, share = 0.5, t = 1 }
    local eqInfo, rowsBy, list = {}, {}, {}
    for slot, w in pairs(m.worn) do eqInfo[slot] = Info(w[1], w[2]) end
    for _, s in ipairs(m.sugs) do
      local recipe = { skill = 200, src = "pattern", r = {} }
      for _, prof in pairs(GCA.Recipes or {}) do if prof[s.spell] then recipe = prof[s.spell] end end
      local d = { kind = "item", cand = { spellID = s.spell, itemID = s.item, recipe = recipe }, info = Info(s.item, s.cstats),
        slot = s.slot, known = true, status = "upgrade", pct = s.points / 100, points = s.points, tier = 1, oldScore = 10,
        newScore = 10 + s.points, e = E, equipped = eqInfo[s.slot], extra = s.extra, future = s.future, wearAt = s.wearAt,
        levelsToGo = s.wearAt and (s.wearAt - m.level) or nil }
      rowsBy[s.slot] = rowsBy[s.slot] or {}
      table.insert(rowsBy[s.slot], d)
      list[#list + 1] = d
    end
    if GCA.SuggestionOrder then table.sort(list, GCA.SuggestionOrder) end
    local items = GCA.db.members[view.key] and GCA.db.members[view.key].items or {}
    local ok, sections = pcall(GCA.BuildSections, GCA, rowsBy, {}, items, eqInfo, {}, E)
    if ok then list.sections = sections else io.write("BuildSections failed: ", tostring(sections), "\n") end
    return list, nil, "ok", E
  end
  if GCA.InvalidateScores then GCA:InvalidateScores() end
end

return Data
