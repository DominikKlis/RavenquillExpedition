local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local SGns, CLASSES, GCA, check, W, known, Scoring = H.SGns, H.CLASSES, H.GCA, H.check, H.W, H.known, H.Scoring
local env, addItem, itemDB, link, setProfs, ns = H.env, H.addItem, H.itemDB, H.link, H.setProfs, H.ns
H.professionMocks()
H.section("W: weapons - proficiency, dual wield, speed parse, crafts end to end")
assert(loadfile(H.SG .. "SimGearForever/Classes.lua", "t", H.sgEnv()))("SimGearForever", H.SGns)

do
  local SGC = SGns.Classes
  local bad, n = 0, 0
  for _, class in ipairs(CLASSES) do
    for sub = 0, 20 do
      for _, level in ipairs({ 19, 20, 39, 40 }) do
        local item = { classID = 2, subclassID = sub, equipLoc = "INVTYPE_WEAPON" }
        local barred = SGC.barredType(class, item)
        local gate = sub == 6 and (class == "HUNTER" or class == "WARRIOR") and 20 or nil
        local expect = barred == nil and not (gate and level < gate)
        local got = GCA:CanWear(class, level, { classID = 2, subClassID = sub, equipLoc = "INVTYPE_WEAPON" })
        n = n + 1
        if got ~= expect then bad = bad + 1; if bad <= 5 then print(("    %s Lv%d weapon sub %d: got %s, expected %s"):format(class, level, sub, tostring(got), tostring(expect))) end end
      end
    end
  end
  check(bad == 0 and n == 9 * 21 * 4, ("%d class/level/weapon-subclass cases = SimGear's equip.weapons + polearm gate (%d differ)"):format(n, bad))
  check(GCA:CanWear("MAGE", 1, { classID = 2, subClassID = 19, equipLoc = "INVTYPE_RANGEDRIGHT" }) and GCA:CanWear("PRIEST", 1, { classID = 2, subClassID = 19 })
    and GCA:CanWear("WARLOCK", 1, { classID = 2, subClassID = 19 }) and not GCA:CanWear("ROGUE", 60, { classID = 2, subClassID = 19 })
    and not GCA:CanWear("HUNTER", 60, { classID = 2, subClassID = 19 }), "wands: Mage/Priest/Warlock only")
  check(GCA:WearFrom("WARRIOR", { classID = 2, subClassID = 6 }) == 20 and GCA:WearFrom("PALADIN", { classID = 2, subClassID = 6 }) == 0
    and GCA:WearFrom("PALADIN", { classID = 2, subClassID = 15 }) == nil and GCA:WearFrom("ROGUE", { classID = 2, subClassID = 20 }) == 0,
    "WearFrom: polearms Warrior 20 / Paladin any level; Paladin never daggers; fishing pole for anyone")
  local same = true
  for _, class in ipairs(CLASSES) do
    local ours, sg = W.classWeapons[class], SGC[class]
    local a, b = {}, {}
    for i, v in ipairs(ours.weapons) do a[i] = v end
    for i, v in ipairs(sg.equip.weapons) do b[i] = v end
    table.sort(a); table.sort(b)
    if table.concat(a, ",") ~= table.concat(b, ",") or ours.dualWieldFrom ~= sg.dualWieldFrom or ours.noHoldable ~= (sg.equip.noHoldable == true) then same = false end
    for k in pairs(sg.dualWield or {}) do if not ours.dualWield[k] then same = false end end
    local holdable = GCA:WearFrom(class, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" })
    if (holdable == nil) ~= (ours.noHoldable == true) then same = false end
  end
  check(same, "Data/Weights.lua classWeapons = SimGear Classes.lua (weapons, dualWield, dualWieldFrom, noHoldable; held off-hands follow noHoldable)")
end

do
  local saved674 = known[674]
  local function dw(class, spec, level, isSelf) return GCA:DualWieldFrom(class, spec, level, isSelf) end
  check(dw("ROGUE", "COMBAT", 9) == 10 and dw("ROGUE", "ASSASSINATION", 10) == 10, "guildie Rogue: dual wield from 10")
  check(dw("WARRIOR", "FURY", 19) == 20 and dw("WARRIOR", "ARMS", 40) == nil and dw("WARRIOR", "PROTECTION", 40) == nil,
    "guildie Warrior: Fury from 20; Arms / Prot never (not simmed with two weapons)")
  check(dw("HUNTER", "MARKSMANSHIP", 30) == 20 and dw("HUNTER", "SURVIVAL_MELEE", 30) == 20, "guildie Hunter: from 20")
  check(dw("SHAMAN", "ENHANCEMENT", 60) == nil and dw("SHAMAN", "ENHANCEMENT_DW", 30) == 0 and dw("SHAMAN", "ELEMENTAL", 60) == nil,
    "Shaman: only as ENHANCEMENT_DW (one-hander seen in the off hand), at any level")
  check(dw("MAGE", "FIRE", 60) == nil and dw("PALADIN", "RETRIBUTION", 60) == nil and dw("DRUID", "FERAL_CAT", 60) == nil, "no dual wield for Mage/Paladin/Druid")
  known[674] = nil
  check(dw("WARRIOR", "FURY", 30, true) == nil and dw("WARRIOR", "FURY", 18, true) == 20, "own Fury Warrior without spell 674: no (Lv30); Lv18 -> from 20 (look-ahead)")
  known[674] = true
  check(dw("WARRIOR", "FURY", 30, true) == 0 and dw("ROGUE", "COMBAT", 8, true) == 0 and dw("WARRIOR", "ARMS", 30, true) == nil,
    "own character: Dual Wield known wins (any level); Arms still not")
  known[674] = saved674
end

do
  local function L(t) return { { leftText = "x" }, { leftText = "45 - 85 Damage", rightText = t } } end
  check(Scoring.weaponSpeedFromLines(L("Speed 2.60"), "Speed") == 2.6 and Scoring.weaponSpeedFromLines(L("Tempo 2,60"), "Tempo") == 2.6
    and Scoring.weaponSpeedFromLines(L("Speed 2.60"), "Tempo") == 2.6 and Scoring.weaponSpeedFromLines(L("Speed 2.60"), nil) == 2.6,
    "speed parse: 'Speed 2.60', deDE 'Tempo 2,60', English fallback, no label")
  check(Scoring.weaponSpeedFromLines(L("Tempo 2,60"), nil) == nil and Scoring.weaponSpeedFromLines(L("Speed 12.00"), "Speed") == nil
    and Scoring.weaponSpeedFromLines({ { leftText = "Tempo 2,60" } }, "Tempo") == nil and Scoring.weaponSpeedFromLines(nil, "Speed") == nil
    and Scoring.weaponSpeedFromLines(L("  Tempo 3  "), "Tempo") == 3,
    "speed parse: unknown label, >= 10 s, left text, nil lines -> nil; '3' without decimals and padding ok")
  local agree = true
  for _, t in ipairs({ "Speed 2.60", "Tempo 2,60", "Speed 1.8", "Tempo 3", "Speed 10.0", "Speed x" }) do
    for _, lab in ipairs({ "Speed", "Tempo" }) do
      if SGns.Stats.weaponSpeedFromLines(L(t), lab) ~= Scoring.weaponSpeedFromLines(L(t), lab) then agree = false end
    end
  end
  check(agree, "speed parse = SimGear's weaponSpeedFromLines on the same lines")
  local savedTI, savedSPEED = env.C_TooltipInfo, env.SPEED
  local calls = 0
  env.SPEED = "Tempo"
  env.C_TooltipInfo = { GetItemByID = function(id) calls = calls + 1; if id == 993001 then return { lines = { { leftText = "Dolch" }, { leftText = "10 - 20 Schaden", rightText = "Tempo 1,80" } } } end end }
  GCA.speedCache = {}
  addItem(993001, "Fake Dagger", "INVTYPE_WEAPON", 30, { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }, 15); itemDB[993001].classID = 2
  GCA.infoCache[993001] = nil
  local info = GCA:GetInfo(993001)
  GCA.infoCache[link(993001)] = nil
  local info2 = GCA:GetInfo(link(993001))
  check(info.speed == 1.8 and info.dagger and info.cstats.MainHandDps == 20 and info2.speed == 1.8 and calls == 1,
    "GetInfo of a weapon: speed 1.80 read from the deDE tooltip (cached: 1 tooltip call), dagger, DPS as MainHandDps")
  local byLink = 0
  env.C_TooltipInfo = {
    GetItemByID = function() return { lines = "broken" } end,
    GetHyperlink = function(l) byLink = byLink + 1; if l == "item:993002" then return { lines = { "junk", { rightText = 7 }, { rightText = "  Tempo 2,60 " } } } end end,
  }
  GCA.speedCache = {}
  check(GCA:WeaponSpeed(993002, "item:993002") == 2.6 and GCA.speedCache[993002] == 2.6 and GCA:WeaponSpeed(993002, "item:993002") == 2.6
    and byLink == 1, "WeaponSpeed: falls back to the hyperlink tooltip, skips odd lines, caches by item ID")
  check(GCA:WeaponSpeed(nil, "item:993002") == 2.6 and GCA:WeaponSpeed(nil, 993002) == nil and next(GCA.speedCache, next(GCA.speedCache)) == nil,
    "WeaponSpeed: no item ID reads the link without caching; no string link, no tooltip")
  env.issecretvalue = function(v) return v == "Tempo" or v == "  Tempo 2,60 " end
  GCA.speedCache = {}
  check(GCA:WeaponSpeed(993002, "item:993002") == nil, "WeaponSpeed: secret speed label and secret right texts are ignored")
  env.issecretvalue = nil
  env.SPEED = 42
  check(GCA:WeaponSpeed(993002, "item:993002") == nil, "WeaponSpeed: a non-string SPEED label only matches the English one")
  env.C_TooltipInfo = nil
  GCA.speedCache = {}
  check(GCA:WeaponSpeed(993002, "item:993002") == nil, "WeaponSpeed: no C_TooltipInfo, no speed")
  GCA.speedCache = {}
  env.C_TooltipInfo, env.SPEED = savedTI, savedSPEED
end

do
  setProfs({ { "Schmiedekunst", 300, 300, 164 } })
  GCA:RefreshKnown()
  local savedBS = ns.Recipes.Blacksmithing
  local savedKnown = {}
  for k, v in pairs(known) do savedKnown[k] = v end
  local savedLA, savedUn = GCA.db.settings.lookahead, GCA.db.settings.showUnlearned
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local function Weapon(id, name, loc, lvl, raw, sub) addItem(id, name, loc, lvl, raw, sub); itemDB[id].classID = 2 end
  Weapon(994001, "Craft Sword", "INVTYPE_WEAPON", 30, { ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }, 7)
  Weapon(994002, "Craft Greatsword", "INVTYPE_2HWEAPON", 30, { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 45 }, 8)
  Weapon(994003, "Craft Polearm", "INVTYPE_2HWEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 25, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }, 6)
  Weapon(994004, "Craft Dagger", "INVTYPE_WEAPON", 30, { ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 28 }, 15)
  Weapon(994005, "Craft Left Blade", "INVTYPE_WEAPONOFFHAND", 30, { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 }, 7)
  Weapon(994006, "Craft Gun", "INVTYPE_RANGEDRIGHT", 30, { ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }, 3)
  Weapon(994007, "Craft Wand", "INVTYPE_RANGEDRIGHT", 30, { ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 }, 19)
  addItem(994008, "Craft Shield", "INVTYPE_SHIELD", 30, { ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 900 }, 6)
  Weapon(994101, "Old 2H", "INVTYPE_2HWEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }, 8)
  Weapon(994102, "Old Sword", "INVTYPE_WEAPON", 20, { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 }, 7)
  Weapon(994103, "Old Offhand Sword", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, 7)
  Weapon(994104, "Old Dagger", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 }, 15)
  Weapon(994105, "Old Wand", "INVTYPE_RANGEDRIGHT", 20, { ITEM_MOD_INTELLECT_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 }, 19)
  local recipes = {}
  for i, id in ipairs({ 994001, 994002, 994003, 994004, 994005, 994006, 994007, 994008 }) do
    recipes[995000 + i] = { item = id, skill = 1, src = "trainer", name = itemDB[id].name, r = {} }
    known[995000 + i] = true
  end
  ns.Recipes.Blacksmithing = recipes
  GCA.itemToSpellOf = {}
  GCA:SelectProfession("Blacksmithing")
  GCA:RefreshKnown()
  GCA.infoCache = {}; GCA.candidates = nil
  local function run(class, spec, level, items, isSelf)
    GCA.sugCache = {}
    local list = GCA:ComputeSuggestions({ key = "Weap Test", class = class, level = level, items = items, spec = spec }, isSelf)
    local by = {}
    for _, s in ipairs(list) do by[s.cand.itemID] = s end
    return by, list
  end
  local nCand = 0
  for _, c in ipairs(GCA:GetCandidates("Blacksmithing")) do if recipes[c.spellID] then nCand = nCand + 1 end end
  check(nCand == 8, "all 8 weapon/shield crafts are candidates (sword, 2H, polearm, dagger, off-hand blade, gun, wand, shield): " .. nCand)
  local by, list = run("WARRIOR", "ARMS", 40, { [16] = link(994101) })
  local gs, sw = by[994002], by[994001]
  check(gs and gs.tier == 1 and gs.slot == 16 and gs.status == "upgrade" and gs.pct and gs.pct > 0, "Arms Lv40 with a 2H: Craft Greatsword is an upgrade (main hand)")
  check(sw and sw.status == "needs-partner" and sw.tier == GCA.TIER_PARTNER and sw.slot == 16 and sw.pct == nil
    and math.abs(sw.points - GCA:ToPoints(gs.e, sw.newScore)) < 1e-9 and sw.equipped and sw.equipped.name == "Old 2H",
    "a one-hander next to a worn 2H: own tier, scored alone (points = its own score), replaces the 2H")
  check(by[994008] and by[994008].status == "needs-partner" and by[994008].slot == 17, "a shield next to a worn 2H: needs a main hand, off-hand section")
  check(by[994005] == nil, "Arms: no off-hand weapon (no dual wield)")
  check(GCA:CanWear("WARRIOR", 40, { classID = 2, subClassID = 15 }) and by[994006] and by[994006].slot == 18
    and (GCA:WeightSetFor("WARRIOR", "ARMS", 40).set.weights.RangedDps or 0) == 0,
    "Warrior: daggers allowed; the gun is offered on its stats only (no RangedDps weight)")
  local order = {}
  for i, s in ipairs(list) do order[s] = i end
  check(order[gs] < order[sw], "the % upgrade sorts before the needs-partner row")
  local secKeys = {}
  for _, sec in ipairs(list.sections) do if #sec.rows > 0 then secKeys[sec.key] = #sec.rows end end
  check(secKeys[16] and secKeys[17] and secKeys[18], "rows reach the main hand, off hand and ranged sections")
  by = run("WARRIOR", "ARMS", 19, { [16] = link(994101) })
  check(by[994003] and by[994003].future and by[994003].wearAt == 20, "polearm for a Lv19 Warrior: look-ahead row, wearable at 20")
  by = run("WARRIOR", "ARMS", 20, { [16] = link(994101) })
  check(by[994003] and not by[994003].future, "polearm at 20: a normal row")
  by = run("WARRIOR", "PROTECTION", 40, { [16] = link(994102), [17] = link(994008) })
  check(by[994002] == nil and by[994003] == nil and by[994001] ~= nil, "Prot Warrior: no two-handers; a one-hander is compared")
  by = run("WARRIOR", "FURY", 40, { [16] = link(994102), [17] = link(994103) })
  local g2 = by[994002]
  check(g2 and g2.bothHands and g2.equipped and g2.equipped.name == "Old Sword + Old Offhand Sword" and g2.equipped.pair,
    "Fury with two swords: a two-hander says 'replaces both hands', compared against both: " .. tostring(g2 and g2.equipped and g2.equipped.name))
  check(by[994005] and by[994005].slot == 17, "Fury Lv40 (dual wield): the off-hand blade is offered for the off hand")
  Weapon(994106, "Strong Dagger", "INVTYPE_WEAPON", 20, { ITEM_MOD_AGILITY_SHORT = 25, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 45 }, 15)
  by = run("ROGUE", "COMBAT", 30, { [16] = link(994106), [17] = link(994104) })
  check(by[994004] and by[994004].hand == "off" and by[994004].slot == 17 and by[994004].equipped.name == "Old Dagger",
    "dual wield: a one-hander better in the off hand is offered for the off hand (hand 'off', section 17, replaces the off-hand dagger)")
  itemDB[994005].minLevel = 1; GCA.infoCache = {}
  by = run("ROGUE", "COMBAT", 8, {})
  check(by[994005] and by[994005].future and by[994005].wearAt == 10, "Rogue Lv8: the off-hand blade is a look-ahead row, wearable at 10 (Dual Wield)")
  GCA.db.settings.lookahead = false
  by = run("ROGUE", "COMBAT", 8, {})
  check(by[994005] == nil, "...and not offered without look-ahead")
  GCA.db.settings.lookahead = true
  itemDB[994005].minLevel = 30; GCA.infoCache = {}
  by = run("ROGUE", "COMBAT", 30, { [16] = link(994102), [17] = link(994104) })
  local dg = by[994004]
  local e = GCA:WeightSetFor("ROGUE", "COMBAT", 30)
  local direct = Scoring.compare(GCA:ScoreItem(GCA:GetInfo(994004)), { [16] = GCA:ScoreItem(GCA:GetInfo(link(994102))), [17] = GCA:ScoreItem(GCA:GetInfo(link(994104))) },
    e.set, nil, nil, { dualWield = true })
  check(dg and dg.hand == direct.hand and dg.slot == (direct.hand == "off" and 17 or 16), "Rogue dual wield: the dagger's hand = the compare's better hand (" .. tostring(direct.hand) .. ")")
  check(by[994002] == nil and by[994003] == nil and by[994007] == nil, "Rogue: no two-handed swords, polearms or wands")
  by = run("MAGE", "FIRE", 40, { [18] = link(994105) })
  check(by[994007] and by[994007].slot == 18 and by[994006] == nil and by[994002] == nil, "Mage: the wand (ranged section), no gun, no 2H sword")
  do
    local saved674 = known[674]
    local me = { key = "Me Rogue", class = "ROGUE", level = 30, items = { [16] = link(994102) }, spec = "COMBAT" }
    local function offersBlade()
      for _, s in ipairs(GCA:MemberSuggestions(me, true, "Blacksmithing")) do if s.cand.itemID == 994005 then return true end end
      return false
    end
    GCA.sugCache = {}
    known[674] = nil
    local before = offersBlade()
    known[674] = true
    check(not before and offersBlade(), "own Rogue Lv30 learns Dual Wield: the off-hand blade appears (not the cached list from before)")
    known[674] = saved674
  end
  by = run("HUNTER", "MARKSMANSHIP", 40, {})
  check(by[994006] and by[994006].slot == 18 and by[994006].status == "empty-slot" and by[994008] == nil, "Hunter: the gun fills an empty ranged slot; no shield")
  GCA.loadState[994999] = { first = 0, tries = 99, failed = true }
  by = run("WARRIOR", "FURY", 40, { [16] = link(994102), [17] = link(994999) })
  check(by[994001] == nil and by[994002] == nil and by[994008] == nil and by[994006] ~= nil, "unknown off hand: no hand crafts, ranged still")
  GCA.loadState[994999] = nil
  ns.Recipes.Blacksmithing = savedBS
  GCA.itemToSpellOf = {}
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedLA, savedUn
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:SelectProfession("Leatherworking")
  GCA:RefreshKnown()
end

H.finish()
