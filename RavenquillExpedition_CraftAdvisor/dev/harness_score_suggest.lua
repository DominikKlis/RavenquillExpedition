local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, GCA, check, near, Scoring, CLASSES, W = H.section, H.GCA, H.check, H.near, H.Scoring, H.CLASSES, H.W
local OURSETS, itemDB, recipeFor, known, addItem = H.OURSETS, H.itemDB, H.recipeFor, H.known, H.addItem
local CRAFT, link, RQ, ns, Files, env, advance = H.CRAFT, H.link, H.RQ, H.ns, H.Files, H.env, H.advance
local requests, fire, talent, reloadDB = H.requests, H.fire, H.talent, H.reloadDB

section("pickSet at levels 9 / 25 / 26 / 58 / 60 and bracket gaps (F8.9)")
do
  local function pick(class, spec, level)
    local e = GCA:WeightSetFor(class, spec, level)
    return e.raw.source.kind .. (e.raw.source.minLevel or "*")
  end
  check(pick("ROGUE", "COMBAT", 9) == "curated20", "Combat Lv9 -> curated Lv20 (lowest set)")
  check(pick("ROGUE", "COMBAT", 25) == "curated20", "Combat Lv25 -> tie 20/30 goes to the lower (curated Lv20)")
  check(pick("ROGUE", "COMBAT", 26) == "sim30", "Combat Lv26 -> sim Lv30")
  check(pick("ROGUE", "COMBAT", 58) == "sim60", "Combat Lv58 -> sim Lv60")
  check(pick("ROGUE", "COMBAT", 60) == "sim60", "Combat Lv60 -> sim Lv60")
  check(pick("DRUID", "FERAL_CAT", 12) == "sim30", "Feral Cat Lv12 -> Lv30, sim beats measured at the same level")
  check(pick("MAGE", "FIRE", 9) == "curated10" and pick("MAGE", "FIRE", 25) == "curated20" and pick("MAGE", "FIRE", 26) == "sim30",
    "Fire 9/25/26 -> curated 10 / curated 20 / sim 30 (same level: sim wins)")
  check(pick("WARLOCK", "DESTRUCTION", 55) == "curated50" and pick("WARLOCK", "DESTRUCTION", 56) == "sim60",
    "Destruction (no sim 30-50): Lv55 tie -> curated 50, Lv56 -> sim 60")
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 12)
  check(GCA:SourceLine(e):find("Lv30 %(nearest set for Lv12%)") ~= nil, "source line shows the gap: " .. GCA:SourceLine(e))
end

section("Survival slider and fade (F8.3)")
do
  GCA.db.settings.survival = 0
  local e0 = GCA:WeightSetFor("ROGUE", "COMBAT", 20)
  local raw = e0.raw
  check(near(e0.set.weights.Stamina, (raw.weights.Stamina or 0) - (raw.survival.Stamina or 0)), "0 %: the set's own survival layer is removed")
  GCA.db.settings.survival = 1
  local e1 = GCA:WeightSetFor("ROGUE", "COMBAT", 20)
  check(near(e1.set.weights.Stamina, raw.weights.Stamina), "100 %: the curated set as SimGear ships it")
  GCA.db.settings.survival = 0.5
  local e40 = GCA:WeightSetFor("ROGUE", "COMBAT", 40)
  local add = e40.ref.survival.Stamina * 0.5 * e40.raw.weights.AttackPower
  check(near(e40.set.weights.Stamina, (e40.raw.weights.Stamina or 0) + add), "Lv40 sim: + ref survival × 0.5 × AP weight (scale)")
  local e54 = GCA:WeightSetFor("ROGUE", "COMBAT", 54)
  check(near(e54.t, 0.5) and GCA:SourceLine(e54):find("fading, 50%% left"), "Lv54: half faded: " .. GCA:SourceLine(e54))
  local e58 = GCA:WeightSetFor("ROGUE", "COMBAT", 58)
  check(e58.set == e58.raw and GCA:SourceLine(e58):find("faded out"), "Lv58+: no survival layer")
  local wp = GCA:WeightSetFor("WARRIOR", "PROTECTION", 30)
  check(wp.ref == nil and GCA:SourceLine(wp):find("no leveling bonus"), "Warrior Prot: no layer, slider does nothing")
  check(GCA:WeightSetFor("ROGUE", "COMBAT", 40) == e40, "weight set cached per (spec, level, share)")
  GCA.db.settings.survival = 0.8
  check(GCA:WeightSetFor("ROGUE", "COMBAT", 40) ~= e40, "another share -> another set")
  GCA.db.settings.survival = 0.5
end

section("Healers: curated placeholders, any level, marked rough (F7.3)")
do
  for _, cs in ipairs({ { "PRIEST", "HOLY" }, { "PRIEST", "DISCIPLINE" }, { "DRUID", "RESTORATION" }, { "SHAMAN", "RESTORATION" }, { "PALADIN", "HOLY" } }) do
    local e9, e60 = GCA:WeightSetFor(cs[1], cs[2], 9), GCA:WeightSetFor(cs[1], cs[2], 60)
    check(e9.raw == e60.raw and Scoring.isPlaceholder(e9.raw) and GCA:SourceLine(e9):find("rough %(healer weights not simulated%)")
      and GCA:SourceLine(e9):find("all levels"), cs[1] .. " " .. cs[2] .. ": " .. GCA:SourceLine(e9))
  end
  local e = GCA:WeightSetFor("PRIEST", "HOLY", 30)
  local st = { HealingPower = 33, SpellPower = 11 }
  check(near(Scoring.value(st, e.set), 33 * e.set.weights.HealingPower), "HealingPower item: its SpellPower counts 0 for healers")
end

section("Display points = score ÷ unit-stat weight (F8.1)")
do
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 60)
  check(e.unit == "AttackPower" and near(e.unitW, e.raw.weights.AttackPower) and near(GCA:ToPoints(e, e.raw.weights.AttackPower * 10), 10),
    ("Feral Cat Lv60 sim: 10 AP = 10 AP-eq (AP weight %.4f)"):format(e.unitW))
  local c = GCA:WeightSetFor("MAGE", "FIRE", 20)
  check(c.unit == "SpellPower" and c.unitW == 1 and GCA:UnitLabel(c) == "SP", "Fire Lv20 curated: SP, unit weight 1")
  local h = GCA:WeightSetFor("HUNTER", "MARKSMANSHIP", 40)
  check(h.unit == "RangedAttackPower" and GCA:UnitLabel(h) == "RAP", "Marksmanship: RAP")
end

section("No baseline, negative scores, sorting, 1 % threshold, cap (F8.5)")
do
  local e = GCA:WeightSetFor("ROGUE", "COMBAT", 40)
  local negSets = 0
  for _, class in ipairs(CLASSES) do
    for spec, list in pairs(W.classes[class]) do
      for _, s in ipairs(list) do
        for _, v in pairs(s.weights) do if v < 0 then negSets = negSets + 1; break end end
      end
    end
  end
  check(negSets >= 1, negSets .. " weight sets have a negative weight")
  local eq = { [5] = { itemID = 1, equipLoc = "INVTYPE_CHEST", stats = { Armor = 50 } } }
  local cand = { itemID = 2, equipLoc = "INVTYPE_CHEST", stats = { Agility = 5, Armor = 60 } }
  local zeroArmor = (e.set.weights.Armor or 0) <= 0
  local r = Scoring.compare(cand, eq, e.set, OURSETS)
  check(not zeroArmor or (r.status == "no-baseline" and r.pct == nil and r.newValue > 0), "armor-only equipped item (score ≤ 0) -> no-baseline, no % (" .. r.status .. ")")
  local neg = Scoring.compare(cand, { [5] = { itemID = 1, equipLoc = "INVTYPE_CHEST", stats = { Agility = -3 } } }, e.set, OURSETS)
  check(neg.status == "no-baseline", "negative equipped score -> no-baseline")
  local B = GCA.BetterSuggestion
  local list = {
    { tier = 1, points = 50, known = true, slot = 1, name = "nobase-50" },
    { tier = 1, points = 3, known = true, slot = 2, name = "up-3" },
    { tier = 1, points = 30, known = true, slot = 3, name = "up-30" },
    { tier = 1, points = 9, known = true, slot = 4, name = "empty-9" },
    { tier = 1, points = 90, known = true, slot = 6, name = "empty-90" },
    { tier = 1, points = 30, known = false, slot = 5, name = "up-30-unlearned" },
    { tier = GCA.TIER_PARTNER, points = 99, known = true, slot = 7, name = "partner-99" },
  }
  table.sort(list, B)
  local order = {}
  for i, x in ipairs(list) do order[i] = x.name end
  check(table.concat(order, ",") == "empty-90,nobase-50,up-30,up-30-unlearned,empty-9,up-3,partner-99",
    "order (user 2026-11-14): real gains by points (known first on a tie), needs-partner after: " .. table.concat(order, ","))
end

section("End to end: Core.ComputeSuggestions with a guildie, sets, threshold, unknown spec/level")
do
  local legs, gloves = 15062, 15063
  check(itemDB[legs] and itemDB[gloves] and recipeFor(legs) and recipeFor(gloves), "Devilsaur Leggings/Gauntlets are LW crafts in the data")
  known[recipeFor(legs)] = true; known[recipeFor(gloves)] = true
  addItem(900001, "Old Pants", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 100 })
  addItem(900002, "Old Gloves", "INVTYPE_HAND", 40, { ITEM_MOD_AGILITY_SHORT = 8 })
  addItem(900003, "Plain Robe", "INVTYPE_CHEST", 40, { RESISTANCE0_NAME = 120 })
  addItem(900004, "Shiny Belt", "INVTYPE_WAIST", 40, { ITEM_MOD_AGILITY_SHORT = 30, ITEM_MOD_STRENGTH_SHORT = 30 })
  local function firstCraft(loc)
    for _, it in ipairs(CRAFT.DRUID) do
      if it.equipLoc == loc and (it.stats.Agility or 0) > 0 and (it.req or 1) <= 58 and itemDB[it.itemID].bind ~= 1 then return it end
    end
  end
  local chestCraft, bootCraft = firstCraft("INVTYPE_CHEST"), firstCraft("INVTYPE_FEET")
  known[recipeFor(chestCraft.itemID)] = true; known[recipeFor(bootCraft.itemID)] = true
  GCA:RefreshKnown()
  GCA.db.settings.showUnlearned = false
  local items = { [7] = link(900001), [10] = link(900002), [5] = link(900003), [6] = link(900004) }
  GCA.db.members["Kat Paw"] = { class = "DRUID", level = 58, items = items, ts = 1, source = "inspect" }
  RQ.roster["Kat Paw"] = { class = "DRUID", level = 58, online = true }
  local list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items }, false)
  check(#list == 0 and state == "no-spec", "spec unknown -> no suggestions (" .. state .. ")")
  list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", items = items, spec = "FERAL_CAT" }, false)
  check(#list == 0 and state == "no-level", "level unknown -> no suggestions (" .. state .. ")")
  list, pending, state = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local bySlot = {}
  for _, s in ipairs(list) do bySlot[s.slot] = s end
  check(state == "ok" and bySlot[7] and bySlot[10], "Devilsaur legs and gloves suggested (" .. #list .. " suggestions)")
  local L = bySlot[7]
  check(L and L.hint and L.hint:find("Devilsaur Armor: %+2%% hit with Devilsaur Gauntlets %(you craft it%)"), "set hint: " .. tostring(L and L.hint))
  ns.locale = "deDE"
  local deHint = L and GCA:SetHint(legs, L.afterIDs, "Leatherworking")
  check(deHint == "Devilsaur Armor: +2% Trefferchance mit Devilsaur Gauntlets (stellst du her)", "German set hint: " .. tostring(deHint))
  check(GCA:BonusText({ SpellPower = 20, MeleeCrit = 1 }) == "+1% kritische Trefferchance (Nahkampf), +20 Zaubermacht",
    "German bonus words: " .. GCA:BonusText({ SpellPower = 20, MeleeCrit = 1 }))
  ns.locale = "enUS"
  check(GCA:BonusText({ SpellPower = 20, MeleeHit = 1, SpellHit = 1 }) == "+1% hit, +20 spell power", "English bonus words unchanged: "
    .. GCA:BonusText({ SpellPower = 20, MeleeHit = 1, SpellHit = 1 }))
  for i = 2, #list do check(not GCA.BetterSuggestion(list[i], list[i - 1]), "list sorted (" .. i .. ")") end
  local items2 = { [7] = link(900001), [10] = link(gloves), [5] = link(900003), [6] = link(900004) }
  local l2 = GCA:ComputeSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items2, spec = "FERAL_CAT" }, false)
  local L2
  for _, s in ipairs(l2) do if s.slot == 7 then L2 = s end end
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local bonus = 2 * (e.set.weights.MeleeHit or 0) + 2 * (e.set.weights.SpellHit or 0)
  check(L2 and L2.sets and near(L2.setDelta, bonus) and L2.hint == nil, ("legs with gloves worn: set gain %.4f counted"):format(L2 and L2.setDelta or -1))
  check(L and L2 and near(L2.newScore - L.newScore, bonus), "set gain = difference of the two cases")
  addItem(900005, "Rival Gloves", "INVTYPE_HAND", 40, { ITEM_MOD_AGILITY_SHORT = 40 })
  local both = { [7] = { itemID = legs, equipLoc = "INVTYPE_LEGS", stats = GCA:GetInfo(legs).cstats },
    [10] = { itemID = gloves, equipLoc = "INVTYPE_HAND", stats = GCA:GetInfo(gloves).cstats } }
  local lose = Scoring.compare({ itemID = 900005, equipLoc = "INVTYPE_HAND", stats = { Agility = 40 } }, both, e.set, OURSETS)
  check(lose.sets and near(lose.setDelta, -bonus), "replacing a set piece subtracts the bonus")
  local p = Scoring.piecesOf({ legs, legs }, OURSETS)
  check(p[143] == 1, "two copies of the same piece count as one")
  addItem(900006, "Pants+", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 101 })
  local tiny = Scoring.compare({ itemID = 900006, equipLoc = "INVTYPE_LEGS", stats = Scoring.normalize(itemDB[900006].raw) },
    { [7] = { itemID = 900001, equipLoc = "INVTYPE_LEGS", stats = Scoring.normalize(itemDB[900001].raw) } }, e.set, OURSETS)
  check(tiny.pct == nil or tiny.pct < GCA.MIN_PCT, ("a 1-armor gain is %.4f%% (< 1 %%) -> would not be listed"):format((tiny.pct or 0) * 100))
  local chest
  for _, s in ipairs(list) do if s.slot == 5 then chest = s end end
  check(chest and chest.status == "no-baseline" and chest.tier == 1 and chest.pct == nil and chest.points > 0,
    "no-baseline chest (" .. chestCraft.name .. " vs armor-only robe): listed with the others by points, no %")
  local feet = bySlot[8]
  local sorted = true
  for i = 2, #list do
    local a, b = list[i - 1], list[i]
    if a.tier == b.tier and (a.future and true or false) == (b.future and true or false) and a.points < b.points - 1e-9 then sorted = false end
  end
  check(feet and feet.status == "empty-slot" and feet.tier == 1 and feet.equipped == nil and sorted,
    ("empty feet slot (%s): same tier as the upgrades, the list sorted by points"):format(bootCraft.name))
  check(bySlot[6] == nil, "no suggestion for the waist (worn belt is better)")
  local c1 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local c2 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" }, false)
  local c3 = GCA:MemberSuggestions({ key = "Kat Paw", class = "DRUID", level = 58, items = items, spec = "FERAL_BEAR" }, false)
  check(c1 == c2 and c3 ~= c1, "suggestions cached per member on gear + spec + level + settings")
  check(GCA.GEAR_RULES["DRUID/FERAL_CAT"].INVTYPE_HOLDABLE, "Feral: held off-hands excluded")
  GCA:SetManualSpec("Kat Paw", "DRUID", "FERAL_CAT")
  local entries = GCA:GetMemberList()
  local kat
  for _, en in ipairs(entries) do if en.key == "Kat Paw" then kat = en end end
  check(kat and kat.spec == "FERAL_CAT" and kat.specHow == "manual" and kat.best ~= nil, "member list: manual spec -> suggestions, best upgrade known")
  check(entries[1].isSelf, "you stay pinned on top")
end

section("Empty-slot tier in the member list (user decision 2026-11-13)")
do
  local fake = {
    ["Pct Paw"] = { { tier = 1, points = 1, known = true, slot = 7, status = "upgrade", pct = 0.02 } },
    ["Empty Paw"] = { { tier = 1, points = 40, known = true, slot = 8, status = "empty-slot" } },
    ["Empty Two"] = { { tier = 1, points = 60, known = true, slot = 8, status = "empty-slot" } },
    ["Nobase Paw"] = { { tier = 1, points = 99, known = true, slot = 5, status = "no-baseline" } },
  }
  for key in pairs(fake) do
    GCA.db.members[key] = { class = "DRUID", level = 58, items = {}, ts = 1, source = "inspect" }
    RQ.roster[key] = { class = "DRUID", level = 58, online = true }
  end
  local real = GCA.MemberSuggestions
  GCA.MemberSuggestions = function(self, view, isSelf)
    if fake[view.key] then return fake[view.key], 0, "ok" end
    return real(self, view, isSelf)
  end
  local order = {}
  for _, en in ipairs(GCA:GetMemberList()) do if fake[en.key] then order[#order + 1] = en.key end end
  GCA.MemberSuggestions = real
  check(table.concat(order, ",") == "Nobase Paw,Empty Two,Empty Paw,Pct Paw",
    "members: by their best gain in points (user 2026-11-14): " .. table.concat(order, ","))
  for key in pairs(fake) do GCA.db.members[key] = nil; RQ.roster[key] = nil end
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  local okUI = pcall(Files.loadUI, uiNs, env)
  local UI = GCA.UI
  GCA.UI = savedUI
  local txt = okUI and UI and UI.GainText and UI.GainText({ status = "empty-slot", points = 7.07 })
  check(txt and txt:find("+7.1", 1, true) and txt:find("empty slot", 1, true) and not txt:find("%%"),
    "empty-slot gain shown as points + \"empty slot\", no %: " .. tostring(txt))
end

section("Post-review: tiny no-baseline gain, unchanged known set, item that never loads")
do
  local view = function(key, items) return { key = key, class = "DRUID", level = 58, items = items, spec = "FERAL_CAT" } end
  local fakeSpell, fakeItem = 990001, 900030
  addItem(900031, "Armor Bracers", "INVTYPE_WRIST", 40, { RESISTANCE0_NAME = 50 })
  addItem(fakeItem, "Faint Bracers", "INVTYPE_WRIST", 40, { RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 0.01 })
  ns.Recipes.Leatherworking[fakeSpell] = { item = fakeItem, skill = 1, src = "trainer", name = "Faint Bracers", r = {} }
  GCA.candidates = nil
  known[fakeSpell] = true
  check(GCA:RefreshKnown() == true, "RefreshKnown reports a changed known set")
  local gen, before = GCA.knownGen, H.refreshes
  advance(1)
  before = H.refreshes
  check(GCA:RefreshKnown() == false and GCA.knownGen == gen, "RefreshKnown with the same set: knownGen unchanged (" .. gen .. ")")
  advance(1)
  check(H.refreshes == before, "... and no window refresh")
  local items = { [9] = link(900031) }
  local list = GCA:ComputeSuggestions(view("Wrist Paw", items), false)
  local wrist
  for _, sug in ipairs(list) do if sug.slot == 9 then wrist = sug end end
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local pts = GCA:ToPoints(e, 0.01 * (e.set.weights.Agility or 0))
  check(pts > 0 and pts < GCA.MIN_POINTS and wrist == nil, ("no-baseline gain of %.4f points (< %.2f) is not listed"):format(pts, GCA.MIN_POINTS))
  itemDB[fakeItem].raw.ITEM_MOD_AGILITY_SHORT = 1; GCA.infoCache[fakeItem] = nil
  list = GCA:ComputeSuggestions(view("Wrist Paw", items), false)
  wrist = nil
  for _, sug in ipairs(list) do if sug.slot == 9 then wrist = sug end end
  check(wrist and wrist.status == "no-baseline" and wrist.points >= GCA.MIN_POINTS and string.format("%+.1f", wrist.points) ~= "+0.0",
    ("control: +1 Agility -> listed (%s points)"):format(wrist and string.format("%.2f", wrist.points) or "-"))
  ns.Recipes.Leatherworking[fakeSpell] = nil; known[fakeSpell] = nil; GCA.candidates = nil
  GCA.db.known[GCA.charKey].Leatherworking[fakeSpell] = nil
  GCA:RefreshKnown()

  local ghost = 900099
  local items2 = { [7] = link(ghost), [10] = link(900002), [5] = link(900003), [6] = link(900004) }
  local v = view("Ghost Paw", items2)
  local calls = 0
  GCA.UI.onRefresh = function() calls = calls + 1; GCA:MemberSuggestions(v, false) end
  H.refreshes = 0
  local l0, p0, st0 = GCA:MemberSuggestions(v, false)
  check(st0 == "loading" and p0 > 0 and requests[ghost] == 1, "first look: loading, one request")
  advance(30)
  local l1, p1, st1 = GCA:MemberSuggestions(v, false)
  local slots = {}
  for _, sug in ipairs(l1) do slots[sug.slot] = sug end
  check(requests[ghost] == GCA.LOAD_TRIES, ("gave up after %d requests (%d)"):format(GCA.LOAD_TRIES, requests[ghost] or 0))
  check(st1 == "ok" and p1 == 0 and slots[10] and slots[8], "other slots still suggested (gloves, empty feet)")
  check(slots[7] == nil and l1.unknownSlots and l1.unknownSlots[7], "legs slot unknown: not offered, not treated as empty")
  check(H.refreshes <= 6, ("bounded refreshes while loading (%d in 30 s)"):format(H.refreshes))
  local r0 = H.refreshes
  advance(60)
  check(H.refreshes == r0 and not GCA.loadRetryPending, "no further refreshes once given up (no endless loop)")
  fire(GCA, "GET_ITEM_INFO_RECEIVED", ghost, false)
  fire(GCA, "GET_ITEM_INFO_RECEIVED", 123456, true)
  advance(5)
  check(H.refreshes == r0, "GET_ITEM_INFO_RECEIVED with success=false or for an item we don't wait for: no refresh")
  addItem(ghost, "Late Pants", "INVTYPE_LEGS", 40, { ITEM_MOD_AGILITY_SHORT = 1 })
  fire(GCA, "GET_ITEM_INFO_RECEIVED", ghost, true)
  advance(1)
  GCA.UI.onRefresh = nil
  local l2 = GCA:MemberSuggestions(v, false)
  local legs2
  for _, sug in ipairs(l2) do if sug.slot == 7 then legs2 = sug end end
  check(legs2 and not l2.unknownSlots, "late arrival: refresh, legs compared again")
end

section("Spec from talents: own C_Traits nodes, ties, variants (F4, F8.2, F8.7)")
do
  local pts = GCA:PointsFromNodes({ { posX = 1020, ranks = 5 }, { posX = 50300, ranks = 3 }, { posX = 9080, ranks = 2 }, { posX = 990, ranks = 1 } }, "ROGUE")
  check(pts.ASSASSINATION == 6 and pts.COMBAT == 3 and pts.SUBTLETY == 2, "posX buckets incl. slack and the stray extra zero (50300 -> 5030)")
  check(GCA:InferTree({ ASSASSINATION = 5, COMBAT = 5 }, "ROGUE") == nil and select(2, GCA:InferTree({}, "ROGUE")) == "no-talents", "tie / zero -> unknown")
  talent.config = 55
  talent.nodes = { { 5020, 5 }, { 5100, 3 }, { 1020, 2 } }
  talent.cat = true
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_CAT" and not GCA.ownSpec.assumed, "own Feral + Cat Form known -> Feral (Cat)")
  talent.cat = false
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_BEAR", "own Feral without Cat Form -> Bear (SimGear's rule)")
  talent.cat = nil
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == "FERAL_CAT" and GCA.ownSpec.assumed, "own Feral, Cat Form not checkable -> Cat, assumed")
  local s, how = GCA:MemberSpec(GCA.playerKey, "DRUID", {})
  check(s == "FERAL_CAT" and how == "talents", "your own spec from talents")
  talent.nodes = { { 1020, 3 }, { 5020, 3 } }
  GCA:RefreshOwnSpec()
  check(GCA.ownSpec.spec == nil and GCA.ownSpec.reason == "tie", "own tie -> spec unknown")
  talent.nodes = { { 5020, 5 }, { 5100, 3 } }
  talent.cat = true
  GCA:RefreshOwnSpec()
  check(GCA:ResolveTree("FERAL", "DRUID", {}, nil) == "FERAL_CAT", "guildie Feral tree -> Cat (assumed)")
  addItem(900010, "Axe", "INVTYPE_WEAPON", 30, {}); itemDB[900010].classID = 2
  addItem(900011, "Shield", "INVTYPE_SHIELD", 30, {}, 6)
  local sp, why = GCA:ResolveTree("ENHANCEMENT", "SHAMAN", { [17] = link(900010) }, nil)
  check(sp == "ENHANCEMENT_DW" and why, "Enhancement + one-hander in slot 17 -> Enhancement (dual-wield), assumed")
  check(GCA:ResolveTree("ENHANCEMENT", "SHAMAN", { [17] = link(900011) }, nil) == "ENHANCEMENT", "Enhancement + shield -> Enhancement")
  check(GCA:ResolveTree("DISCIPLINE", "PRIEST", {}) == "DISCIPLINE" and GCA:ResolveTree("SURVIVAL", "HUNTER", {}) == "SURVIVAL", "Smite / Survival (melee): never inferred")
  GCA:StoreSpec("Bo Hunt", "HUNTER", { spec = "MARKSMANSHIP", src = "sync", ts = 100 })
  check(GCA:MemberSpec("Bo Hunt", "HUNTER", {}) == "MARKSMANSHIP", "synced spec used")
  GCA:SetManualSpec("Bo Hunt", "HUNTER", "SURVIVAL_MELEE")
  local ms, mhow = GCA:MemberSpec("Bo Hunt", "HUNTER", {})
  check(ms == "SURVIVAL_MELEE" and mhow == "manual", "manual pick wins")
  check(not GCA:StoreSpec("Bo Hunt", "HUNTER", { spec = "BEAST_MASTERY", src = "sync", ts = 50 }), "older synced spec rejected")
  GCA:SetManualSpec("Bo Hunt", "HUNTER", nil)
  check(GCA:MemberSpec("Bo Hunt", "HUNTER", {}) == "MARKSMANSHIP", "manual pick cleared -> synced again")
  check(GCA:MemberSpec("Bo Hunt", "MAGE", {}) == nil, "a stored spec of another class is ignored")
end

section("Inspected talents: plausibility gate (F8.6)")
do
  talent.inspect = { tree = 888, nodes = { { 5020, 15 }, { 5200, 6 } } }
  local tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == "COMBAT" and why == "ok", "plausible inspect read -> Combat")
  talent.inspect = { tree = 888, nodes = { { 5020, 0, 15 }, { 1020, 0, 2 } } }
  tree = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == "COMBAT", "ranksPurchased all 0 -> activeRank used (Leatrix Plus' fallback)")
  talent.inspect = { tree = 888, nodes = { { 5020, 40 } } }
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil and why:find("more points"), "more points than level 30 allows -> rejected (" .. why .. ")")
  talent.inspect = { tree = 777, nodes = { { 5020, 5 }, { 5100, 3 } } }
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil and why:find("same tree"), "our own tree handed back for another class -> rejected (" .. why .. ")")
  tree, why = GCA:ReadInspectTalents("DRUID", 30)
  check(tree == nil and why:find("identical"), "same class, node-for-node our own talents -> rejected (" .. why .. ")")
  talent.inspect = nil
  tree, why = GCA:ReadInspectTalents("ROGUE", 30)
  check(tree == nil, "no inspect config -> nothing, no error (" .. tostring(why) .. ")")
  check(GCA.db.settings.inspectTalents == false, "inspected talents default off")
  local db = env.RavenquillExpeditionCraftDB
  db.settings.inspectTalents, db.inspectTalentsOffV1, db.v = true, nil, nil
  reloadDB()
  check(db.settings.inspectTalents == false and db.inspectTalentsOffV1, "0.3.0 dev SavedVariables with true -> reset to off once")
  db.settings.inspectTalents = true
  reloadDB()
  check(db.settings.inspectTalents == true, "turned on by hand afterwards -> stays on")
  GCA.db.settings.inspectTalents = true
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Fera Paw", "DRUID", 40)
  advance(2)
  local s, how, assumed = GCA:MemberSpec("Fera Paw", "DRUID", {})
  check(s == "FERAL_CAT" and how == "inspected" and assumed, "inspected Feral -> Cat (assumed)")
  GCA.db.settings.inspectTalents = false
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  GCA:TryInspectTalents("Bala Paw", "DRUID", 40)
  advance(2)
  check(GCA:MemberSpec("Bala Paw", "DRUID", {}) == nil, "/gca spec inspect off -> not used")
  GCA.db.settings.inspectTalents = true
  GCA.db.settings.inspectTalents = true
  GCA:StoreSpec("Ursa Paw", "DRUID", { spec = "FERAL_BEAR", src = "sync", ts = 5 })
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Ursa Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Ursa Paw", "DRUID", {}) == "FERAL_BEAR", "inspect of the same tree keeps the synced Bear")
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  GCA:TryInspectTalents("Ursa Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Ursa Paw", "DRUID", {}) == "BALANCE", "inspect of another tree (newer) replaces it")
  GCA.db.settings.inspectTalents = true
  talent.inspect = { tree = 889, nodes = { { 5020, 20 } } }
  GCA:TryInspectTalents("Bear Paw", "DRUID", 40); advance(2)
  local s1, h1 = GCA:MemberSpec("Bear Paw", "DRUID", {})
  local stored = GCA:StoreSpec("Bear Paw", "DRUID", { spec = "FERAL_BEAR", src = "sync", ts = GCA:Now() - 86400 })
  local s2, h2 = GCA:MemberSpec("Bear Paw", "DRUID", {})
  check(s1 == "FERAL_CAT" and h1 == "inspected" and stored and s2 == "FERAL_BEAR" and h2 == "synced",
    "inspect first, then an older synced spec on the same tree -> synced wins (" .. tostring(s2) .. ", " .. tostring(h2) .. ")")
  GCA:TryInspectTalents("Bear Paw", "DRUID", 40); advance(2)
  check(GCA:MemberSpec("Bear Paw", "DRUID", {}) == "FERAL_BEAR", "a later inspect of the same tree still doesn't replace it")
  check(not GCA:StoreSpec("Bear Paw", "DRUID", { spec = "BALANCE", src = "sync", ts = GCA:Now() - 99999 }), "an older synced spec still loses to a newer synced one")
  GCA.db.settings.inspectTalents = false
  local s3, h3 = GCA:MemberSpec("Fera Paw", "DRUID", {})
  check(s3 == nil and GCA.db.specs["Fera Paw"].src == "inspect", "inspect off: stored inspect record ignored (" .. tostring(h3) .. ")")
  check(GCA:StoreSpec("Fera Paw", "DRUID", { spec = "BALANCE", src = "sync", ts = 1 }) and GCA:MemberSpec("Fera Paw", "DRUID", {}) == "BALANCE",
    "inspect off: an older synced spec of another tree replaces the ignored inspect record")
  GCA.db.settings.inspectTalents = true
  talent.inspect = nil
  GCA:TryInspectTalents("Late Paw", "DRUID", 40, "G-A", GCA.inspectGen)
  GCA:OnInspectReady("G-B")
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  advance(2)
  check(GCA:MemberSpec("Late Paw", "DRUID", {}) == nil and GCA.db.specs["Late Paw"] == nil, "counter moved -> late retry stores nothing under A")
  talent.inspect = nil
  GCA:TryInspectTalents("Late Two", "DRUID", 40, "G-A2", GCA.inspectGen)
  GCA.inspectGUID = "G-B2"
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  advance(2)
  check(GCA.db.specs["Late Two"] == nil, "inspected GUID changed -> late retry stores nothing")
  local g0 = GCA.inspectGen
  GCA:OnNotifyInspect("player")
  check(GCA.inspectGen == g0 + 1 and GCA.inspectGUID == "G-me", "NotifyInspect hook bumps the counter and records the GUID")
  talent.inspect = nil
  GCA.inspectGUID = "G-C"
  GCA:TryInspectTalents("Late Ok", "DRUID", 40, "G-C", GCA.inspectGen)
  talent.inspect = { tree = 889, nodes = { { 1020, 20 } } }
  advance(2)
  check(GCA:MemberSpec("Late Ok", "DRUID", {}) == "BALANCE", "control: nothing moved -> the 0.3 s retry stores")
  local ok = pcall(GCA.SpecDebug, GCA)
  check(ok, "/gca spec debug runs without error")
end

section("Debug: /gca stats <item link>")
do
  addItem(900020, "Hit Ring", "INVTYPE_FINGER", 30, { ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_STRANGE_SHORT = 1 })
  H.printed = {}
  GCA:OnSlash("stats |cff|Hitem:900020::::::::40:1488|h[Hit Ring]|h|r")
  local all = table.concat(H.printed, "\n")
  check(all:find("ITEM_MOD_HIT_RATING_SHORT=10") and all:find("MeleeHit=1") and all:find("SpellHit=1") and all:find("unmapped: ITEM_MOD_STRANGE_SHORT"),
    "raw keys, canonical result and unmapped keys printed")
end

H.finish()
