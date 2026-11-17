local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, GCA, check, setProfs, known, advance = H.section, H.GCA, H.check, H.setProfs, H.known, H.advance
local Files, env, ns, addItem, RQ, itemDB, Scoring = H.Files, H.env, H.ns, H.addItem, H.RQ, H.itemDB, H.Scoring
H.professionMocks()

section("G: professions, known recipes per profession, selector, browse, caches")
do
  GCA.db.known[GCA.charKey] = { [2149] = true, [2160] = true }
  local store = GCA:KnownStore()
  check(store.Leatherworking and store.Leatherworking[2149] and store[2149] == nil, "0.3.0 flat known IDs moved under Leatherworking")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schneiderei", 200, 300, 197 } })
  known[461692] = true
  GCA:RefreshKnown()
  check(GCA:IsKnown(461692, "Leatherworking") and GCA:IsKnown(461692, "Tailoring") and not GCA:IsKnown(461692, "Blacksmithing"),
    "461692 known in LW and Tailoring (both yours), not in Blacksmithing")
  check(GCA:ItemToSpell("Leatherworking")[18258] == 22815 and GCA:ItemToSpell("Tailoring")[18258] == 22813
    and GCA:ItemToSpell("Leatherworking")[227855] == 461692 and GCA:ItemToSpell("Tailoring")[227855] == 461692,
    "itemToSpell per profession: 18258 -> 22815 (LW) / 22813 (Tailoring)")
  check(GCA:SelectedProfession() == "Leatherworking" and not GCA:IsBrowse(), "default selection: your first gear profession (LW)")
  GCA:SelectProfession("Tailoring")
  check(GCA:SelectedProfession() == "Tailoring" and GCA.db.profSel[GCA.charKey] == "Tailoring", "switch to Tailoring: selected, choice saved per character")
  GCA:SelectProfession("Blacksmithing")
  check(GCA:IsBrowse() and GCA:IsBrowse("Blacksmithing") and not GCA:IsBrowse("Leatherworking"), "Blacksmithing is browse (not yours)")
  GCA:SelectProfession("Leatherworking")
  local gen = GCA.knownGen
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  check(GCA.db.known[GCA.charKey].Tailoring == nil and not GCA:IsKnown(461692, "Tailoring") and GCA.knownGen == gen + 1,
    "Tailoring dropped: its saved known IDs cleared, knownGen bumped")
  setProfs({})
  GCA.loginTime = H.now
  local _, trusted = GCA:ReadProfessions()
  GCA:RefreshKnown()
  check(not trusted and GCA.db.known[GCA.charKey].Leatherworking ~= nil, "empty GetProfessions within 10 s of login: not trusted, LW kept")
  advance(11)
  _, trusted = GCA:ReadProfessions()
  check(trusted, "... trusted 10 s after login (a character without professions)")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
end

do
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  Files.loadUI(uiNs, env)
  local UIx = GCA.UI
  GCA.UI = savedUI
  local bsSpell, bsItem
  for spellID, r in pairs(ns.Recipes.Blacksmithing) do if not bsSpell or spellID < bsSpell then bsSpell, bsItem = spellID, r.item end end
  addItem(bsItem, "BS Chest", "INVTYPE_CHEST", 40, { ITEM_MOD_STRENGTH_SHORT = 10, RESISTANCE0_NAME = 300 }, 4)
  known[bsSpell] = true
  GCA.candidates = nil
  local key = "Pala Plate"
  GCA.db.members[key] = { class = "PALADIN", level = 45, items = {}, ts = 1, source = "inspect" }
  RQ.roster[key] = { class = "PALADIN", level = 45, online = true }
  GCA:SetManualSpec(key, "PALADIN", "RETRIBUTION")
  local view = { key = key, class = "PALADIN", level = 45, items = {}, spec = "RETRIBUTION" }
  local lwList = GCA:MemberSuggestions(view, false, "Leatherworking")
  GCA:SelectProfession("Blacksmithing")
  local bsList = GCA:MemberSuggestions(view, false)
  local chest
  for _, s in ipairs(bsList) do if s.cand.itemID == bsItem then chest = s end end
  check(chest and chest.known == false, "browse forces show-unlearned and nothing counts as known (even a spell the game reports known)")
  check(bsList ~= lwList and GCA:MemberSuggestions(view, false, "Leatherworking") == lwList, "suggestion cache per profession: switching doesn't serve LW's list, LW's stays cached")
  GCA.knownNow.Blacksmithing = { [bsSpell] = true }
  GCA.sugCache = {}
  local again
  for _, s in ipairs(GCA:MemberSuggestions(view, false)) do if s.cand.itemID == bsItem then again = s end end
  check(again and again.known == false, "browse ignores a stale known set of that profession")
  GCA:RefreshKnown()
  local en
  for _, e in ipairs(GCA:GetMemberList()) do if e.key == key then en = e end end
  check(en and en.browse and en.knownCount == 0 and en.best == nil and #en.suggestions > 0, "browse: member badge/order count nothing (knownCount 0, no best)")
  check(not UIx.CanOffer(en, chest), "browse: Offer hidden")
  check(GCA:IsBrowse("Blacksmithing") and not GCA:IsBrowse("Leatherworking"), "browse = a profession you don't have (Blacksmithing), not your own (LW)")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  local own = GCA:MemberSuggestions(view, false)
  local chest2
  for _, s in ipairs(own) do if s.cand.itemID == bsItem then chest2 = s end end
  check(chest2 and chest2.known and not GCA:IsBrowse(), "Blacksmithing now yours: same recipe known (cache invalidated by browse flag + knownGen)")
  check(UIx.CanOffer({ key = key, online = true }, chest2) and not UIx.CanOffer({ key = key, online = false }, chest2)
    and UIx.OfferText("Blacksmithing", chest2):find("I'm a blacksmith", 1, true),
    "item Offer only while the member is online (H3 U3); whisper says blacksmith")
  check(not UIx.CanOffer({ key = key, online = true }, { kind = "item", known = false }), "unlearned row: no Offer")
  check(UIx.OfferText("Leatherworking", chest2):find("leatherworker", 1, true) and UIx.OfferText("Engineering", chest2):find("an engineer", 1, true),
    "whisper text per profession")
  local en2
  for _, e in ipairs(GCA:GetMemberList()) do if e.key == key then en2 = e end end
  check(en2 and en2.knownCount >= 1 and en2.best and en2.best.known, "own profession: badge counts known suggestions")
  env.UnitFactionGroup = function() return "Alliance" end
  check(GCA.PlayerFaction() == "Alliance", "faction read")
  local tipLines = {}
  env.C_TooltipInfo = { GetItemByID = function(id) local l = tipLines[id]; if l then local t = {} for i, s in ipairs(l) do t[i] = { leftText = s } end return { lines = t } end end }
  tipLines[bsItem] = { "BS Chest", "Requires Level 40", "Classes: Warrior" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and GCA:PassesRestrictions(bsItem, "WARRIOR", false), "Classes: Warrior bars a Paladin; \"Requires Level 40\" isn't a skill (no localized class table: token match)")
  env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_SKILL = "Klassen: %s", "Benötigt %s"
  env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Krieger", PALADIN = "Paladin" }
  tipLines[bsItem] = { "BS Chest", "Benötigt Stufe 40", "Klassen: Krieger" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and GCA:PassesRestrictions(bsItem, "WARRIOR", false), "German client: \"Klassen: Krieger\" bars a Paladin")
  env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_SKILL, env.LOCALIZED_CLASS_NAMES_MALE = nil, nil, nil
  tipLines[bsItem] = { "BS Chest", "Requires Engineering (225)" }
  GCA.restrCache = nil
  check(not GCA:PassesRestrictions(bsItem, "PALADIN", false) and not GCA:PassesRestrictions(bsItem, "PALADIN", true),
    "Requires Engineering: not for guildies, not for you without Engineering")
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Engineering", 250, 300, 202 } })
  GCA:ReadProfessions()
  check(GCA:PassesRestrictions(bsItem, "PALADIN", true), "... for you with Engineering: yes")
  do
    tipLines[bsItem] = { "Requires Engineering (225)", "Classes:  Warrior , Death Knight", "Requires Mining", "Classes: Secret" }
    env.issecretvalue = function(v) return v == "Classes: Secret" end
    GCA.restrCache = nil
    local r = GCA:ItemRestrictions(bsItem)
    local names = {}
    for name in pairs(r.classes or {}) do names[#names + 1] = name end
    table.sort(names)
    check(r.skill == "Engineering" and table.concat(names, ",") == "death knight,warrior" and GCA:ItemRestrictions(bsItem) == r,
      "ItemRestrictions: skill with rank, classes trimmed and lowercased, secret and rankless lines skipped, cached")
    env.issecretvalue = nil
    local savedTip = env.C_TooltipInfo
    env.C_TooltipInfo = { GetItemByID = function() return { lines = "broken" } end }
    local broken = GCA:ItemRestrictions(bsItem + 1)
    env.C_TooltipInfo = nil
    local none = GCA:ItemRestrictions(bsItem + 2)
    check(next(broken) == nil and broken == none and GCA.restrCache[bsItem + 1] == nil and GCA.restrCache[bsItem + 2] == nil,
      "ItemRestrictions: no tooltip or broken lines -> shared empty result, not cached")
    env.C_TooltipInfo = savedTip
  end
  do
    local savedSpell, savedInfo, savedCache = env.C_Spell, env.GetSpellInfo, GCA.enchantInfo
    local function info(spell, name)
      GCA.enchantInfo = {}
      local c = GCA:EnchantInfo({ spell = spell, name = name, stats = { Agility = 1 } })
      return table.concat({ tostring(c.name), tostring(c.icon), c.quality, c.minLevel, c.cstats.Agility,
        tostring(GCA.enchantInfo[spell] == c) }, "|")
    end
    env.C_Spell = { GetSpellName = function(id) return id == 1 and "Both" or id == 2 and "Name only" or id == 4 and 42 or id == 5 and "Hidden" or nil end,
      GetSpellTexture = function(id) return id == 1 and "both.tga" or id == 5 and "hidden.tga" or nil end }
    env.GetSpellInfo = function(id) if id == 2 or id == 3 or id == 4 then return "Old " .. id, nil, "old" .. id .. ".tga" end end
    env.issecretvalue = function(v) return v == "Hidden" or v == "hidden.tga" end
    local got = table.concat({ info(1, "row"), info(2, "row"), info(3, "row"), info(4, "row"), info(5, "row"), info(6, "row") }, ";")
    env.C_Spell, env.GetSpellInfo = nil, nil
    got = got .. ";" .. info(1, "row")
    env.issecretvalue = nil
    env.C_Spell, env.GetSpellInfo, GCA.enchantInfo = savedSpell, savedInfo, savedCache
    local fallback = "Interface\\Icons\\Trade_Engraving"
    check(got == "Both|both.tga|1|0|1|true;Name only|old2.tga|1|0|1|true;Old 3|old3.tga|1|0|1|true;row|old4.tga|1|0|1|false;"
      .. "row|" .. fallback .. "|1|0|1|false;row|" .. fallback .. "|1|0|1|false;row|" .. fallback .. "|1|0|1|false",
      "EnchantInfo: C_Spell first, GetSpellInfo fills gaps, secret or odd names fall back to the row and aren't cached: " .. got)
  end
  tipLines[bsItem] = nil
  GCA.restrCache = nil
  env.C_TooltipInfo = nil
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  known[bsSpell] = nil
  GCA.db.known[GCA.charKey].Blacksmithing = {}
  GCA:RefreshKnown()
  GCA:SelectProfession("Blacksmithing")
  GCA.db.settings.showUnlearned = false
  local gen0 = GCA.knownGen
  local ownList = GCA:MemberSuggestions(view, false)
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  local browseList = GCA:MemberSuggestions(view, false)
  check(#ownList == 0 and GCA.knownGen == gen0 and #browseList > 0 and browseList ~= ownList,
    ("own BS with nothing known: %d rows; dropped -> browse (knownGen unchanged): %d rows, not the cached list"):format(#ownList, #browseList))
  setProfs({ { "Lederverarbeitung", 225, 300, 165 }, { "Schmiedekunst", 250, 300, 164 } })
  GCA:RefreshKnown()
  known[bsSpell] = true
  GCA:RefreshKnown()
  local wSpell = 999990
  addItem(999991, "Some Sword", "INVTYPE_WEAPON", 40, { ITEM_MOD_STRENGTH_SHORT = 99 }, 7); itemDB[999991].classID = 2
  ns.Recipes.Blacksmithing[wSpell] = { item = 999991, skill = 1, src = "trainer", name = "Some Sword", r = {} }
  GCA.candidates = nil
  local isCand = false
  for _, c in ipairs(GCA:GetCandidates("Blacksmithing")) do if c.itemID == 999991 then isCand = true end end
  check(isCand, "W1: a crafted weapon is a candidate")
  ns.Recipes.Blacksmithing[wSpell] = nil
  GCA.candidates = nil
  GCA.db.members[key], RQ.roster[key] = nil, nil
  known[bsSpell] = nil
  GCA:SelectProfession("Leatherworking")
end

section("G: enchant suggestions (G4 + G7.1, G7.2, G7.7, G7.8, G7.9)")
do
  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  for id in pairs(known) do known[id] = nil end
  GCA:RefreshKnown()
  GCA:SelectProfession("Enchanting")
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  Files.loadUI(uiNs, env)
  local UIx = GCA.UI
  GCA.UI = savedUI
  local SUPERIOR, GREATER, MINOR = 1248599, 1248500, 7779
  local function learn(...) for _, id in ipairs({ ... }) do known[id] = true end GCA:RefreshKnown() end
  local function unlearn(id) known[id] = nil; GCA.db.known[GCA.charKey].Enchanting[id] = nil; GCA:RefreshKnown() end
  learn(SUPERIOR, GREATER, 13419 , 23800 , 27837 , 20030 ,
    1219577 , 20017 , 13746 )
  check(GCA:IsKnown(SUPERIOR) and GCA.knownCounts.Enchanting >= 9, "enchant spells counted as known Enchanting spells (" .. GCA.knownCounts.Enchanting .. ")")
  addItem(910001, "Agile Bracers", "INVTYPE_WRIST", 40, { ITEM_MOD_AGILITY_SHORT = 5, RESISTANCE0_NAME = 40 })
  addItem(910002, "Plain Cloak", "INVTYPE_CLOAK", 40, { ITEM_MOD_AGILITY_SHORT = 4, RESISTANCE0_NAME = 30 }, 1)
  addItem(910003, "Robe", "INVTYPE_CHEST", 40, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 80 })
  addItem(910004, "Big Staff", "INVTYPE_2HWEAPON", 40, { ITEM_MOD_AGILITY_SHORT = 10 }, 10); itemDB[910004].classID = 2
  addItem(910005, "Boots", "INVTYPE_FEET", 40, { ITEM_MOD_AGILITY_SHORT = 6, RESISTANCE0_NAME = 50 })
  local function lnk(id, ench) return "item:" .. id .. ":" .. (ench or "") .. ":::::::40:1488" end
  local function sugs(items, class, spec, level)
    GCA.sugCache = {}
    local list = GCA:ComputeSuggestions({ key = "Ench Test", class = class or "DRUID", level = level or 58, items = items, spec = spec or "FERAL_CAT" }, false)
    local by = {}
    for _, s in ipairs(list) do if s.kind == "enchant" and not by[s.slot] then by[s.slot] = s end end
    return by, list
  end
  local e = GCA:WeightSetFor("DRUID", "FERAL_CAT", 58)
  local by = sugs({ [9] = lnk(910001) })
  local w = by[9]
  local base = GCA:Score(GCA:GetInfo(lnk(910001)), e)
  local val = Scoring.value({ Agility = 9 }, e.set)
  check(w and w.cand.spellID == SUPERIOR and w.tier == 1 and math.abs(w.pct - val / base) < 1e-9 and w.known,
    ("no enchant: Superior Agility, gain %% = enchant value / item score (%.1f%%)"):format(w and w.pct * 100 or -1))
  by = sugs({ [9] = lnk(910001, 1887) })
  w = by[9]
  local val7 = Scoring.value({ Agility = 7 }, e.set)
  check(w and w.cand.spellID == SUPERIOR and math.abs(w.pct - (val - val7) / base) < 1e-9 and w.current and w.current.enchant == 1887,
    "current Greater Agility: gain = (new − current) ÷ item score")
  by = sugs({ [9] = lnk(910001, 7656) })
  check(by[9] == nil, "already the best known enchant: no wrist suggestion")
  by = sugs({ [9] = lnk(910001, 8483) })
  check(by[9] == nil, "unknown enchant 8483 on the wrist: no suggestion for that slot")
  local bestChest, bestV
  for _, r in ipairs(GCA:EnchantData().bySlot.chest) do
    local v = r.kind == "stats" and Scoring.value(r.stats, e.set) or 0
    if v > 0 and (not bestV or v > bestV) then bestChest, bestV = r.spell, v end
  end
  learn(bestChest, 1219587 )
  by = sugs({ [5] = lnk(910003), [15] = lnk(910002), [9] = lnk(910001) })
  check(by[5] and by[15] and by[9], "control: chest, cloak and wrist without enchants all get a suggestion")
  by = sugs({ [5] = lnk(910003, 44), [15] = lnk(910002, 65), [9] = lnk(910001) })
  check(by[5] == nil and by[15] == nil and by[9] ~= nil, "proc enchant on the chest / utility on the cloak: never replaced; wrist still suggested")
  local anyBad = false
  for _, s in ipairs(select(2, sugs({ [5] = lnk(910003), [15] = lnk(910002), [9] = lnk(910001), [8] = lnk(910005) }))) do
    if s.kind == "enchant" and s.enchant.kind ~= "stats" then anyBad = true end
  end
  check(not anyBad, "only stat enchants are suggested (no utility/proc/damage rows)")
  by = sugs({ [15] = lnk(910002, 247) })
  local d = GCA:EnchantData()
  check(d.byEnchant[247] and d.byEnchant[247].stats.Agility == 3, "shared enchant 247 looked up once (Agility 3)")
  local v5, v3 = Scoring.value({ Agility = 5 }, e.set), Scoring.value({ Agility = 3 }, e.set)
  check(by[15] and by[15].cand.spellID == 1219587 and by[15].current.enchant == 247 and math.abs(by[15].gain - (v5 - v3)) < 1e-9,
    "cloak with shared 247: recognised as +3 Agility, Cloak Agility (+5) suggested for the difference")
  by = sugs({ [9] = nil, [15] = lnk(910002) })
  check(by[9] == nil, "empty wrist slot: no enchant suggestion")
  by = sugs({ [16] = lnk(910004) })
  w = by[16]
  local staff = GCA:Score(GCA:GetInfo(lnk(910004)), e)
  check(w and w.cand.spellID == 27837 and w.status == "upgrade" and w.tier == 1
    and math.abs(w.pct - Scoring.value({ Agility = 25 }, e.set) / staff) < 1e-9,
    ("W5: 2H Agility on a two-hander: a real %% of the weapon's own score (%.0f%%)"):format(w and w.pct and w.pct * 100 or -1))
  unlearn(27837)
  by = sugs({ [16] = lnk(910004) })
  check(by[16] and by[16].cand.spellID == 23800, "2H: an Enchant Weapon (one-hand) row also goes on a two-hander")
  unlearn(23800)
  by = sugs({ [16] = lnk(910004) })
  local imp = Scoring.value({ TwoHandDps = 9 / 3.5 }, e.set)
  check(by[16] and by[16].cand.spellID == 20030 and math.abs(by[16].gain - imp) < 1e-9 and by[16].info.cstats.TwoHandDps,
    "W5: 2H Superior Impact (damage 9) scored as 9 ÷ 3.5 TwoHandDps (no speed read -> SimGear's assumed 3.5)")
  by = sugs({ [16] = lnk(910004, 943) })
  local str = Scoring.value({ TwoHandDps = 3 / 3.5 }, e.set)
  check(by[16] and by[16].cand.spellID == 20030 and math.abs(by[16].gain - (imp - str)) < 1e-9 and by[16].current.enchant == 943,
    "W5: Striking (943, damage 3) on the weapon is valued now: Superior Impact for the difference")
  GCA.infoCache[lnk(910004)] = nil
  local savedWS = GCA.WeaponSpeed
  GCA.WeaponSpeed = function() return 2.0 end
  by = sugs({ [16] = lnk(910004) })
  check(by[16] and math.abs(by[16].gain - Scoring.value({ TwoHandDps = 9 / 2.0 }, e.set)) < 1e-9,
    "W5: damage ÷ the worn weapon's speed (2.0) when it is known")
  GCA.WeaponSpeed = savedWS
  GCA.infoCache[lnk(910004)] = nil
  addItem(910006, "Club", "INVTYPE_WEAPON", 40, { ITEM_MOD_AGILITY_SHORT = 4 }, 4); itemDB[910006].classID = 2
  check(math.abs(GCA:EnchantStats(GCA:EnchantData().byEnchant[943], GCA:GetInfo(lnk(910006))).MainHandDps - 3 / 2.6) < 1e-9,
    "W5: Striking on a one-hander = 3 ÷ 2.6 MainHandDps")
  learn(27837, 23800)
  addItem(910010, "Tome", "INVTYPE_HOLDABLE", 40, { ITEM_MOD_INTELLECT_SHORT = 6 }, 0)
  addItem(910011, "Buckler", "INVTYPE_SHIELD", 40, { ITEM_MOD_STAMINA_SHORT = 6, RESISTANCE0_NAME = 600 }, 6)
  by = sugs({ [17] = lnk(910010) }, "MAGE", "FIRE", 58)
  check(by[17] and by[17].enchant.slot == "offhand", "held off-hand: an Off-Hand enchant (" .. (by[17] and by[17].enchant.name or "none") .. ")")
  by = sugs({ [17] = lnk(910011) }, "WARRIOR", "PROTECTION", 58)
  check(by[17] and by[17].enchant.slot == "shield", "shield: a Shield enchant (" .. (by[17] and by[17].enchant.name or "none") .. ")")
  local realStats = env.C_Item.GetItemStats
  GCA.ItemAPI.Stats = function(l)
    local raw = realStats(l)
    local ench = tonumber(tostring(l):match("item:%d+:(%d+)"))
    local row = ench and d.byEnchant[ench]
    if not row or not row.stats then return raw end
    local copy = {}
    for k, v in pairs(raw) do copy[k] = v end
    copy.ITEM_MOD_AGILITY_SHORT = (copy.ITEM_MOD_AGILITY_SHORT or 0) + (row.stats.Agility or 0)
    return copy
  end
  GCA.infoCache = {}
  local inc = GCA:GetInfo(lnk(910001, 1887))
  check(inc and inc.cstats.Agility == 12, "mock: the enchanted link's stats now include the enchant (Agility 5 + 7)")
  by = sugs({ [9] = lnk(910001, 1887) })
  w = by[9]
  check(w and math.abs(w.pct - (val - val7) / base) < 1e-9 and math.abs(w.baseScore - base) < 1e-9,
    "GetItemStats including the enchant: base = item without enchant, same % as before")
  H.printed = {}
  GCA:OnSlash("enchant debug " .. lnk(910001, 1887))
  check(table.concat(H.printed, "\n"):find("INCLUDED: Agility+7", 1, true), "/gca enchant debug reports 'included' in that case")
  GCA.ItemAPI.Stats = realStats
  GCA.infoCache = {}
  H.printed = {}
  GCA:OnSlash("enchant debug " .. lnk(910001, 1887))
  check(table.concat(H.printed, "\n"):find("NOT included", 1, true), "... and 'NOT included' when the stats are the same")
  check(GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { SpellPower = 1 } }) == "FirePower"
    and GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { SpellPower = 1, FirePower = 1 } }) == nil
    and GCA.UnsimmedSchool({ FirePower = 20 }, { weights = { AttackPower = 1 } }) == nil, "unsimmed-school rule")
  by = sugs({ [9] = lnk(910001) })
  w = by[9]
  check(UIx.CanOffer({ online = true }, w) and not UIx.CanOffer({ online = false }, w), "enchant Offer only for online members")
  local txt = UIx.OfferText("Enchanting", w)
  check(txt:find("an enchanter", 1, true) and txt:find("when we meet", 1, true) and txt:find("Wrist", 1, true), "enchant whisper: " .. txt)
  setProfs({ { "Lederverarbeitung", 225, 300, 165 } })
  GCA:RefreshKnown()
  by = sugs({ [9] = lnk(910001) })
  check(by[9] and not by[9].known and not UIx.CanOffer({ online = true }, by[9]), "browse Enchanting: enchants shown as not learned, no Offer")
  env.GameTooltip = setmetatable({}, { __index = function() return function() end end })
  local tipOk = pcall(UIx.ShowSuggestionTooltip, {}, by[9])
  check(tipOk, "suggestion tooltip renders an enchant row")
  H.printed = {}
  local okD = pcall(GCA.KnownDebug, GCA)
  check(okD and table.concat(H.printed, "\n"):find("Enchanting enchant spells", 1, true) == nil
    and table.concat(H.printed, "\n"):find("Leatherworking item recipes", 1, true), "/gca known debug runs (only your professions probed)")
  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  GCA:RefreshKnown()
  H.printed = {}
  pcall(GCA.KnownDebug, GCA)
  check(table.concat(H.printed, "\n"):find("Enchanting enchant spells: 175 in data", 1, true), "/gca known debug probes enchant spells separately")
  for id in pairs(known) do known[id] = nil end
  GCA:SelectProfession("Leatherworking")
end

H.finish()
