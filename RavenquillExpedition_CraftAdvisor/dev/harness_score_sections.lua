local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, setProfs, GCA, Files, env, check, ns = H.section, H.setProfs, H.GCA, H.Files, H.env, H.check, H.ns
local itemDB, addItem, known, link, reloadDB, Scoring = H.itemDB, H.addItem, H.known, H.link, H.reloadDB, H.Scoring
H.professionMocks()

section("H: look-ahead order (H5.2), crafted marks (H5.1), locale + whisper (H4/U2), offline Offer (U3)")
do
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local uiNs = { GCA = GCA }
  local savedUI = GCA.UI
  Files.loadUI(uiNs, env)
  local UIx = GCA.UI
  GCA.UI = savedUI

  local O, B = GCA.SuggestionOrder, GCA.BetterSuggestion
  local list = {
    { tier = 1, points = 9, known = true, slot = 1, future = true, name = "future9" },
    { tier = 1, points = 2, known = true, slot = 2, name = "now2" },
    { tier = 1, points = 50, known = true, slot = 3, future = true, name = "future50" },
    { tier = 1, points = 5, known = true, slot = 4, name = "now5" },
    { tier = 1, points = 4, known = true, slot = 6, name = "now4" },
    { tier = GCA.TIER_PARTNER, points = 1, known = true, slot = 7, name = "partner" },
  }
  table.sort(list, O)
  local order = {}
  for i, x in ipairs(list) do order[i] = x.name end
  check(table.concat(order, ",") == "now5,now4,now2,future50,future9,partner",
    "order: look-ahead after the wearable ones in each tier: " .. table.concat(order, ","))
  check(B(list[4], list[1]), "per-slot pick (Better) still takes the bigger look-ahead gain")

  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local sLegs, sHands = spells[1], spells[2]
  local iLegs, iHands = ns.Recipes.Leatherworking[sLegs].item, ns.Recipes.Leatherworking[sHands].item
  local saved = { [iLegs] = itemDB[iLegs], [iHands] = itemDB[iHands] }
  addItem(iLegs, "Now Legs", "INVTYPE_LEGS", 38, { ITEM_MOD_AGILITY_SHORT = 14, RESISTANCE0_NAME = 100 })
  addItem(iHands, "Later Gloves", "INVTYPE_HAND", 43, { ITEM_MOD_AGILITY_SHORT = 30 })
  addItem(990001, "Worn Legs", "INVTYPE_LEGS", 30, { ITEM_MOD_AGILITY_SHORT = 10, RESISTANCE0_NAME = 100 })
  addItem(990002, "Worn Gloves", "INVTYPE_HAND", 30, { ITEM_MOD_AGILITY_SHORT = 8 })
  GCA.infoCache[iLegs], GCA.infoCache[iHands] = nil, nil
  GCA.candidates = nil
  known[sLegs], known[sHands] = true, true
  GCA:RefreshKnown()
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local items = { [7] = link(990001), [10] = link(990002) }
  GCA.sugCache = {}
  local l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local legs, hands
  for i, s in ipairs(l) do if s.slot == 7 then legs = i elseif s.slot == 10 then hands = i end end
  local handRow = hands and l[hands]
  check(legs and hands and legs < hands and handRow.future and handRow.wearAt == 43 and handRow.levelsToGo == 3 and not l[legs].future
    and handRow.points > l[legs].points, "Lv43 gloves (bigger gain) listed after the wearable legs; wearAt 43, 3 levels to go")
  check(UIx.WearableText(handRow) == "wearable at level 43 (in 3 levels)", "label: " .. tostring(handRow and UIx.WearableText(handRow)))
  GCA.db.settings.lookahead = false
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local anyFuture = false
  for _, s in ipairs(l) do if s.future then anyFuture = true end end
  check(not anyFuture and #l >= 1, "look-ahead off: no too-high-level items")
  GCA.db.settings.lookahead = true

  local sNowHands, sWorseLater = spells[3], spells[4]
  local iNowHands, iWorseLater = ns.Recipes.Leatherworking[sNowHands].item, ns.Recipes.Leatherworking[sWorseLater].item
  saved[iNowHands], saved[iWorseLater] = itemDB[iNowHands], itemDB[iWorseLater]
  addItem(iNowHands, "Now Gloves", "INVTYPE_HAND", 38, { ITEM_MOD_AGILITY_SHORT = 12 })
  addItem(iWorseLater, "Worse Later Gloves", "INVTYPE_HAND", 44, { ITEM_MOD_AGILITY_SHORT = 11 })
  GCA.infoCache[iNowHands], GCA.infoCache[iWorseLater] = nil, nil
  GCA.candidates = nil
  known[sNowHands] = true
  GCA:RefreshKnown()
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local nowI, laterI
  for i, s in ipairs(l) do
    if s.cand.itemID == iNowHands then nowI = i elseif s.cand.itemID == iHands then laterI = i end
  end
  check(nowI and laterI and nowI < laterI and not l[nowI].future and l[laterI].future,
    "M-2: wearable gloves AND the bigger Lv43 gloves both listed, wearable first (" .. tostring(nowI) .. ", " .. tostring(laterI) .. ")")
  local _, bestNow = GCA.KnownOnly(l)
  check(bestNow and not bestNow.future, "M-2: the member's best is a wearable craft")
  known[sHands] = nil
  known[sWorseLater] = true
  GCA:RefreshKnown()
  GCA.sugCache = {}
  l = GCA:ComputeSuggestions({ key = "Kit Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }, false)
  local hasNow, hasWorse = false, false
  for _, s in ipairs(l) do
    if s.cand.itemID == iNowHands then hasNow = true elseif s.cand.itemID == iWorseLater then hasWorse = true end
  end
  check(hasNow and not hasWorse, "M-2: a look-ahead craft no better than the wearable one is not listed")
  known[sHands], known[sWorseLater], known[sNowHands] = true, nil, nil
  GCA:RefreshKnown()
  GCA.sugCache = {}
  local syn = { { known = true, future = true, tier = 1, name = "f1" }, { known = false, tier = 1, name = "u1" }, { known = true, tier = 2, name = "w2" } }
  local nk, bk = GCA.KnownOnly(syn)
  check(nk == 2 and bk == syn[3], "M-2: KnownOnly counts known rows and picks the first wearable as best")
  check(select(2, GCA.KnownOnly({ syn[1] })) == syn[1], "M-2: only look-ahead known -> that one is the best")

  local who = "Kit Paw"
  GCA.db.members[who] = { class = "DRUID", level = 40, items = items, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", handRow, true)
  local mark = GCA:CraftedMark(who, "Leatherworking", sHands)
  check(mark and mark.item == iHands and mark.slot == 10 and GCA.db.crafted[GCA.charKey][who].Leatherworking[sHands] == mark,
    "mark stored per character / member / profession / spellID")
  GCA:StoreRecord(who, "DRUID", 40, { [7] = link(990001), [10] = link(990002) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "a record without the item keeps the mark")
  GCA:StoreRecord("Other Guy", "DRUID", 40, { [10] = link(iHands) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "someone else wearing it doesn't clear it")
  GCA.db.members["Other Guy"] = nil
  GCA:StoreRecord(who, "DRUID", 43, { [7] = link(990001), [10] = link(iHands) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", sHands) == nil and GCA.db.crafted[GCA.charKey][who] == nil, "a record showing it worn clears the mark")
  GCA:SetCrafted(who, "Leatherworking", handRow, true)
  reloadDB()
  check(GCA:CraftedMark(who, "Leatherworking", sHands) ~= nil, "mark survives ADDON_LOADED (SavedVariables)")
  GCA:SetCrafted(who, "Leatherworking", handRow, false)
  check(GCA:CraftedMark(who, "Leatherworking", sHands) == nil, "untick removes it")
  addItem(990020, "Crafted Ring", "INVTYPE_FINGER", 30, { ITEM_MOD_AGILITY_SHORT = 5 })
  local ring = { kind = "item", cand = { spellID = 990021, itemID = 990020 }, slot = 12 }
  GCA.db.members[who] = { class = "DRUID", level = 40, items = { [11] = link(990020), [10] = link(990002) }, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", ring, true)
  local rm = GCA:CraftedMark(who, "Leatherworking", 990021)
  check(rm and rm.had and rm.had[11] and rm.count == 1, "M-3: mark remembers the slots already holding the item (11, count 1)")
  GCA:StoreRecord(who, "DRUID", 41, { [11] = link(990020), [10] = link(990002) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) ~= nil, "M-3: the old copy in the same slot does NOT clear the mark")
  GCA:StoreRecord(who, "DRUID", 41, { [11] = link(990020), [12] = link(990020) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) == nil, "M-3: a second copy (new slot, count 2) clears it")
  GCA.db.members[who] = { class = "DRUID", level = 40, items = { [11] = link(990020) }, ts = 1, source = "inspect" }
  GCA:SetCrafted(who, "Leatherworking", ring, true)
  GCA:StoreRecord(who, "DRUID", 41, { [12] = link(990020) }, "inspect")
  check(GCA:CraftedMark(who, "Leatherworking", 990021) == nil, "M-3: the item showing up in a slot that didn't hold it clears it")
  GCA.db.members[who] = { class = "DRUID", level = 40, items = items, ts = 1, source = "inspect" }
  local ench = { kind = "enchant", cand = { spellID = 7779, enchant = true }, enchant = { enchant = 247 }, slot = 9 }
  GCA:SetCrafted(who, "Enchanting", ench, true)
  local em = GCA:CraftedMark(who, "Enchanting", 7779)
  check(em and em.enchant == 247 and em.slot == 9 and em.item == nil, "enchant mark keeps the enchant ID and slot")
  GCA:StoreRecord(who, "DRUID", 43, { [9] = "item:990003:248::::::::40:1488", [10] = "item:990004:247::::::::40:1488" }, "inspect")
  check(GCA:CraftedMark(who, "Enchanting", 7779) ~= nil, "a different enchant on the slot (or 247 on another slot) keeps it")
  GCA:StoreRecord(who, "DRUID", 43, { [9] = "item:990003:247::::::::40:1488" }, "inspect")
  check(GCA:CraftedMark(who, "Enchanting", 7779) == nil, "enchant 247 on the wrist clears it")
  GCA.db.crafted["Alt Char-Realm"] = { [who] = { Leatherworking = { [sHands] = { item = iHands, slot = 10, t = 1 } } } }
  GCA:StoreRecord(who, "DRUID", 43, { [10] = link(iHands) }, "inspect")
  check(GCA.db.crafted["Alt Char-Realm"][who] == nil, "an alt's mark for the same member is cleared as well")
  GCA.db.members[who] = nil

  check(UIx.CanOffer({ key = who, online = true }, handRow) and not UIx.CanOffer({ key = who, online = false }, handRow)
    and not UIx.CanOffer({ key = who, online = false }, { kind = "enchant", known = true }), "Offer only for online members (craft + enchant)")

  local L = ns.L
  ns.Locales.enUS.__TEST_ONLY_EN = "English only"
  ns.locale = "deDE"
  check(L.OPT_OPEN == "Fenster öffnen" and L.__TEST_ONLY_EN == "English only" and ns.LGet("__NOPE__") == nil and L.__NOPE__ == "__NOPE__"
    and ns.missingL.__NOPE__, "deDE: German; key missing in deDE -> English; missing everywhere -> key (noted)")
  check(GCA:SpecName("ROGUE", "COMBAT") == "Kampf" and GCA:SpecName("PRIEST", "SMITE") == "Göttliche Pein (Schaden)", "spec names in German")
  local d = { kind = "item", info = { link = "|cff1eff00|Hitem:4244::::|h[Hillmans Lederweste]|h|r", name = "Hillmans Lederweste" }, slot = 5 }
  local txt = UIx.OfferText("Leatherworking", d, "Bud Stone")
  check(txt:find("^Hallo Bud! Ich bin Lederverarbeiter und könnte dir |cff1eff00|Hitem:4244::::|h%[Hillmans Lederweste%]|h|r herstellen") and txt:find("Interesse%?$"),
    "German craft whisper: " .. txt)
  local et = UIx.OfferText("Enchanting", { kind = "enchant", info = { name = "Armschiene - Beweglichkeit" }, slot = 9 }, "Bud Stone")
  check(et:find("Ich bin Verzauberer", 1, true) and et:find("Armschiene - Beweglichkeit", 1, true) and et:find("wenn wir uns treffen", 1, true), "German enchant whisper: " .. et)
  GCA.db.settings.whisperCraft = "Moin {name}: {item} ({slot}) – 100%? {crafter}"
  local d2 = { kind = "item", info = { link = "[50% off]", name = "x" }, slot = 5 }
  check(UIx.OfferText("Tailoring", d2, "Bud Stone") == "Moin Bud: [50% off] (Chest) – 100%? Schneider", "template with %: " .. UIx.OfferText("Tailoring", d2, "Bud Stone"))
  check(UIx.OfferText("Tailoring", d2, nil) == "Moin: [50% off] (Chest) – 100%? Schneider", "no name: " .. UIx.OfferText("Tailoring", d2, nil))
  GCA.db.settings.whisperCraft = "   "
  check(UIx.Template("craft") == ns.Locales.deDE.WHISPER_CRAFT, "blank saved template -> default of the client language")
  local longLink = "|cff1eff00|Hitem:4244" .. string.rep(":", 100) .. "|h[Hillmans Lederweste]|h|r"
  local dl = { kind = "item", info = { link = longLink, name = "Hillmans Lederweste" }, slot = 5 }
  GCA.db.settings.whisperCraft = string.rep("\195\164", 60) .. " {item}"
  local t1 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  check(#(string.rep("\195\164", 60) .. " " .. longLink) > 255 and t1 == string.rep("\195\164", 60) .. " Hillmans Lederweste",
    "too long with the link -> item name (" .. #t1 .. " bytes)")
  local printedMark = #H.printed
  UIx.warnedLong = nil
  GCA.db.settings.whisperCraft = "xy" .. string.rep("\195\164", 200) .. " {item}"
  local t2 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  local t3 = UIx.OfferText("Leatherworking", dl, "Bud Stone")
  local warned = 0
  for i = printedMark + 1, #H.printed do if H.printed[i].text:find("255 Bytes", 1, true) then warned = warned + 1 end end
  check(#t2 == 254 and t2 == "xy" .. string.rep("\195\164", 126) and t3 == t2 and warned == 1,
    "cut to " .. #t2 .. " bytes on a character boundary (not inside an umlaut), told once (" .. warned .. ")")
  check(UIx.Utf8Cut("ab|", 3) == "ab|" and UIx.Utf8Cut("abc|d", 4) == "abc" and UIx.Utf8Cut("a\226\130\172b", 3) == "a"
    and UIx.Utf8Cut("a\226\130\172b", 4) == "a\226\130\172", "Utf8Cut: no split characters, no dangling '|'")
  GCA.db.settings.whisperCraft = "{name}: {item}"
  check(UIx.OfferText("Leatherworking", dl, "Bud Stone") == "Bud: " .. longLink, "short enough -> the link stays")
  GCA.db.settings.whisperCraft = nil
  check(GCA:SourceLine(GCA:WeightSetFor("ROGUE", "COMBAT", 40)):find("Kampf Lv40 · simuliert · Levelbonus 50%", 1, true), "source line in German: "
    .. GCA:SourceLine(GCA:WeightSetFor("ROGUE", "COMBAT", 40)))
  ns.locale = "enUS"
  ns.Locales.enUS.__TEST_ONLY_EN = nil
  ns.missingL.__NOPE__ = nil

  local en, de = ns.Locales.enUS, ns.Locales.deDE
  local used, missingUse = {}, {}
  for _, f in ipairs({ "Core", "UI", "Sync.lua", "Spec.lua", "Auction.lua" }) do
    local src = Files.source(f:find("%.lua$") and { f } or Files.group(f))
    for k in src:gmatch("[^%w_]L%.([%u_][%u%d_]*)") do used[k] = true end
    for k in src:gmatch("[^%w_]L%[\"([%u_][%u%d_]*)\"%]") do used[k] = true end
  end
  for _, def in ipairs(UIx.FILTERS) do used[def.label] = true; used[def.tip] = true end
  local nUsed = 0
  for k in pairs(used) do nUsed = nUsed + 1; if en[k] == nil then missingUse[#missingUse + 1] = k end end
  table.sort(missingUse)
  check(nUsed > 150 and #missingUse == 0, "all " .. nUsed .. " keys used in the code exist in enUS; missing: " .. table.concat(missingUse, ","))
  local extra, badFmt, untranslated = {}, {}, {}
  local function specs(s) local t = {} for sp in s:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([cdeEfgGiouxXqs])") do t[#t + 1] = sp end return table.concat(t) end
  for k, v in pairs(de) do
    if not k:find("^SPEC:") then
      if en[k] == nil then extra[#extra + 1] = k elseif specs(en[k]) ~= specs(v) then badFmt[#badFmt + 1] = k end
    end
  end
  for k in pairs(en) do if de[k] == nil then untranslated[#untranslated + 1] = k end end
  table.sort(extra); table.sort(badFmt); table.sort(untranslated)
  check(#extra == 0, "every German key exists in English: " .. table.concat(extra, ","))
  check(#badFmt == 0, "format specifiers match enUS for every German text: " .. table.concat(badFmt, ","))
  check(#untranslated == 0, "every English key has a German text (else it falls back to English): " .. table.concat(untranslated, ","))
  local INDIRECT = { "HEAD_ENCHANTS", "HEAD_CRAFTS" }
  local FMT_SITES = { ["d.kind"] = true, ["what,"] = true }
  local fmtKeys, oddSites = {}, {}
  for _, k in ipairs(INDIRECT) do fmtKeys[k] = true end
  for _, f in ipairs({ "Core", "UI", "Sync.lua", "Spec.lua", "Scoring.lua" }) do
    local src = Files.source(f:find("%.lua$") and { f } or Files.group(f))
    for k in src:gmatch("format%(%s*L%.([%u_][%u%d_]*)") do fmtKeys[k] = true end
    for k in src:gmatch('format%(%s*L%["([^"]+)"%]') do fmtKeys[k] = true end
    for first in src:gmatch("[^%w_]format%(%s*([^%s\"'%)][^%s%)]*)") do
      if not first:find("^L[%.%[]") and not FMT_SITES[first] then oddSites[#oddSites + 1] = f .. ": format(" .. first end
    end
  end
  check(#oddSites == 0, "every non-literal format string is L.KEY or a known indirect site: " .. table.concat(oddSites, "; "))
  local function dummies(v)
    local args = {}
    for spec in v:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*(%a)") do
      if spec == "s" or spec == "q" then args[#args + 1] = "x"
      elseif spec == "f" or spec == "g" or spec == "e" or spec == "G" or spec == "E" then args[#args + 1] = 1.5
      else args[#args + 1] = 7 end
    end
    return args
  end
  local nFmt, badRun = 0, {}
  for k in pairs(fmtKeys) do
    for _, loc in ipairs({ "enUS", "deDE" }) do
      local v = ns.Locales[loc][k]
      if v == nil and loc == "enUS" then badRun[#badRun + 1] = loc .. "." .. k .. " missing" end
      if v ~= nil then
        nFmt = nFmt + 1
        local ok, err = pcall(string.format, v, (table.unpack or unpack)(dummies(v)))
        if not ok then badRun[#badRun + 1] = loc .. "." .. k .. ": " .. tostring(err) end
      end
    end
  end
  table.sort(badRun)
  check(nFmt > 100 and #badRun == 0, "string.format works on all " .. nFmt .. " format texts (enUS + deDE): " .. table.concat(badRun, "; "))
  local specMissing = {}
  for _, e in ipairs(GCA.SPEC_LIST) do if not de["SPEC:" .. e[3]] then specMissing[#specMissing + 1] = e[3] end end
  check(#specMissing == 0, "all 31 spec names have a German text: " .. table.concat(specMissing, ","))

  known[sLegs], known[sHands] = nil, nil
  itemDB[iLegs], itemDB[iHands] = saved[iLegs], saved[iHands]
  GCA.infoCache[iLegs], GCA.infoCache[iHands] = nil, nil
  GCA.candidates = nil
  GCA:RefreshKnown()
end

section("I: slot sections (grouping, top 3, order, grey lines, rings/trinkets, enchants, browse, badge meaning)")
do
  local savedKnown, savedStore = {}, GCA.db.known[GCA.charKey]
  for k, v in pairs(known) do savedKnown[k] = v; known[k] = nil end
  GCA.db.known[GCA.charKey] = {}
  local savedSettings = { lookahead = GCA.db.settings.lookahead, showUnlearned = GCA.db.settings.showUnlearned }
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = false, false
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local saved, nextSpell = {}, 20
  local function craft(name, loc, minLevel, raw, sub, learn)
    nextSpell = nextSpell + 1
    local sp = spells[nextSpell]
    local id = ns.Recipes.Leatherworking[sp].item
    if saved[id] == nil then saved[id] = itemDB[id] or false end
    addItem(id, name, loc, minLevel, raw, sub)
    if learn ~= false then known[sp] = true end
    return sp, id
  end
  local function agi(n) return { ITEM_MOD_AGILITY_SHORT = n } end
  for _, a in ipairs({ 9, 10, 11, 12, 13 }) do craft("Gloves " .. a, "INVTYPE_HAND", 30, agi(a)) end
  local _, iLegs = craft("Big Legs", "INVTYPE_LEGS", 30, agi(40))
  local _, iRing = craft("Craft Ring", "INVTYPE_FINGER", 30, agi(5), 0)
  local _, iTrink = craft("Craft Trinket", "INVTYPE_TRINKET", 30, agi(3), 0)
  addItem(991001, "Worn Gloves", "INVTYPE_HAND", 30, agi(8))
  addItem(991002, "Worn Legs", "INVTYPE_LEGS", 30, agi(10))
  addItem(991003, "Robe", "INVTYPE_CHEST", 30, agi(10))
  addItem(991004, "Ring A", "INVTYPE_FINGER", 30, agi(6), 0)
  addItem(991005, "Ring B", "INVTYPE_FINGER", 30, agi(3), 0)
  addItem(991006, "Trinket One", "INVTYPE_TRINKET", 30, agi(4), 0)
  GCA.infoCache = {}
  GCA.candidates = nil
  GCA:RefreshKnown()
  local items = { [10] = link(991001), [7] = link(991002), [5] = link(991003), [11] = link(991004), [12] = link(991005), [13] = link(991006) }
  local view = { key = "Sec Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }
  local function run(prof)
    GCA.sugCache = {}
    return GCA:ComputeSuggestions(view, false, prof)
  end
  local function sec(l, key) for _, s in ipairs(l.sections or {}) do if s.key == key then return s end end end
  local function names(rows) local t = {} for i, s in ipairs(rows) do t[i] = s.info.name end return table.concat(t, ",") end

  local l = run()
  check(l.sections and #l.sections == 15, "15 sections (rings and trinkets one each): " .. tostring(l.sections and #l.sections))
  local inSec, total, bad = {}, 0, 0
  for _, s in ipairs(l.sections) do
    for _, r in ipairs(s.rows) do
      total = total + 1
      if GCA.SECTION_OF[r.slot] ~= s.key or inSec[r] then bad = bad + 1 end
      inSec[r] = true
    end
  end
  for _, r in ipairs(l) do if not inSec[r] then bad = bad + 1 end end
  check(bad == 0 and total == #l, "grouping: every row in its slot's section exactly once (" .. total .. " rows, " .. bad .. " misplaced)")
  local hands = sec(l, 10)
  check(hands and #hands.rows == 3 and hands.total == 5 and names(hands.rows) == "Gloves 13,Gloves 12,Gloves 11",
    "top 3 of 5 gloves, best first: " .. (hands and names(hands.rows) or "-") .. " (total " .. tostring(hands and hands.total) .. ")")
  check(hands and not hands.rows[1].extra and hands.rows[2].extra and hands.rows[3].extra, "only the slot's best is a primary row; #2/#3 are extra")
  local n, best = GCA.KnownOnly(l)
  check(#l == 6 and n == 4 and best == l[1], "KnownOnly counts 4 (one per slot) of " .. #l .. " rows; best = first row")
  local keys, orderOK, seenNone = {}, true, false
  for i, s in ipairs(l.sections) do
    keys[i] = s.key
    if #s.rows == 0 then seenNone = true elseif seenNone then orderOK = false end
    local nx = l.sections[i + 1]
    if nx and #s.rows > 0 and #nx.rows > 0 and GCA.SuggestionOrder(nx.rows[1], s.rows[1]) then orderOK = false end
  end
  check(orderOK and keys[1] == 7, "sections with an upgrade first, by their best row's points (legs first; the empty-trinket fill by its points too): "
    .. table.concat(keys, ","))
  check(table.concat(keys, ",", 5) == "1,2,3,15,5,9,6,8,16,17,18", "no-upgrade sections after, in character order: " .. table.concat(keys, ",", 5))
  local chest = sec(l, 5)
  check(chest and #chest.rows == 0 and chest.worn[1].info and chest.worn[1].info.name == "Robe" and type(chest.worn[1].score) == "number"
    and chest.worn[1].score > 0, "no-upgrade chest: no rows, worn Robe with its score")
  local head = sec(l, 1)
  check(head and #head.rows == 0 and head.worn[1].link == nil and head.worn[1].info == nil, "empty head slot: grey line with nothing worn")
  local rings = sec(l, 11)
  check(rings and #rings.worn == 2 and rings.worn[1].slot == 11 and rings.worn[2].slot == 12 and rings.worn[1].info.name == "Ring A"
    and rings.worn[2].info.name == "Ring B" and #rings.rows == 1 and rings.rows[1].slot == 12 and rings.rows[1].cand.itemID == iRing,
    "rings: one section with Ring A + Ring B; the ring craft (replaces slot 12) is listed there")
  check(sec(l, 12) == nil and sec(l, 14) == nil, "no separate sections for slots 12 and 14")
  local tr = sec(l, 13)
  check(tr and #tr.worn == 2 and tr.worn[1].info.name == "Trinket One" and tr.worn[2].link == nil and #tr.rows == 1
    and tr.rows[1].status == "empty-slot" and tr.rows[1].cand.itemID == iTrink, "trinkets: one section, worn + empty slot, the craft fills the empty one")
  check(sec(l, 7).rows[1].cand.itemID == iLegs, "legs section: the legs craft")

  local _, iWorse = craft("Gloves 9.5 unlearned", "INVTYPE_HAND", 30, agi(9), nil, false)
  craft("Gloves 50 unlearned", "INVTYPE_HAND", 30, agi(50), nil, false)
  GCA.infoCache = {}; GCA.candidates = nil
  GCA.db.settings.showUnlearned = true
  l = run()
  hands = sec(l, 10)
  local hasWorse, has13 = false, false
  for _, r in ipairs(hands.rows) do
    if r.cand.itemID == iWorse then hasWorse = true end
    if r.info.name == "Gloves 13" then has13 = true end
  end
  check(not hasWorse and has13 and #hands.rows == 3 and hands.rows[1].info.name == "Gloves 50 unlearned",
    "show unlearned: better unlearned first, worse unlearned dropped (real unlearned LW gloves may fill in): " .. names(hands.rows))
  craft("Gloves 49 unlearned", "INVTYPE_HAND", 30, agi(49), nil, false)
  craft("Gloves 48 unlearned", "INVTYPE_HAND", 30, agi(48), nil, false)
  GCA.infoCache = {}; GCA.candidates = nil
  l = run()
  hands = sec(l, 10)
  check(names(hands.rows) == "Gloves 50 unlearned,Gloves 49 unlearned,Gloves 13" and not hands.rows[3].extra,
    "three better unlearned gloves: the known best takes the 3rd place (never cut): " .. names(hands.rows))
  check(select(1, GCA.KnownOnly(l)) == 4, "badge count unchanged with show unlearned (4)")
  GCA.db.settings.showUnlearned = false

  craft("Later Gloves 30", "INVTYPE_HAND", 43, agi(30))
  craft("Later Gloves 29", "INVTYPE_HAND", 44, agi(29))
  GCA.infoCache = {}; GCA.candidates = nil
  GCA:RefreshKnown()
  GCA.db.settings.lookahead = true
  l = run()
  hands = sec(l, 10)
  check(names(hands.rows) == "Gloves 13,Gloves 12,Later Gloves 30" and hands.rows[3].future and not hands.rows[3].extra,
    "look-ahead: cut in tier order (wearable first, Lv44 gloves out), the bigger Lv43 gloves kept in the top 3 (counts as before): " .. names(hands.rows))
  n, best = GCA.KnownOnly(l)
  check(n == 5 and best and not best.future, "badge: 5 (hands now + hands look-ahead, legs, ring, trinket), best wearable (" .. n .. ")")
  GCA.db.settings.lookahead = false

  local function syn(o) o.tier = o.tier or 1; o.points = o.points or 10; o.slot = o.slot or 9; o.kind = o.kind or "item"; return o end
  local a1 = syn({ known = false, cand = { itemID = 5 }, points = 20 })
  local a2 = syn({ known = true, cand = { itemID = 5 }, points = 20 })
  local b1 = syn({ known = true, cand = { itemID = 6 }, points = 15 })
  local shown, tot = GCA:SectionCut({ a1, b1, a2 }, { [a2] = true })
  check(#shown == 2 and tot == 2 and shown[1] == a2 and shown[2] == b1, "same item from two recipes: listed once (the known/primary one)")
  local e1 = syn({ kind = "enchant", known = true, enchant = { enchant = 247 }, cand = {}, points = 9 })
  local e2 = syn({ kind = "enchant", known = true, enchant = { enchant = 247 }, cand = {}, points = 9 })
  shown = GCA:SectionCut({ e1, e2 }, {})
  check(#shown == 1, "two enchant rows with the same enchant ID: listed once")

  setProfs({ { "Lederverarbeitung", 300, 300, 165 }, { "Verzauberkunst", 300, 300, 333 } })
  for id in pairs(known) do known[id] = nil end
  GCA.db.known[GCA.charKey] = {}
  local d = GCA:EnchantData()
  local e40 = GCA:WeightSetFor("DRUID", "FERAL_CAT", 40)
  local nWrist = 0
  for _, key in ipairs({ "wrist", "back", "chest" }) do
    for _, r in ipairs(d.bySlot[key] or {}) do
      if r.kind == "stats" and Scoring.value(r.stats, e40.set) > 0 and not GCA.UnsimmedSchool(r.stats, e40.set) then
        known[r.spell] = true
        if key == "wrist" then nWrist = nWrist + 1 end
      end
    end
  end
  addItem(991007, "Bracers", "INVTYPE_WRIST", 30, agi(4))
  addItem(991008, "Cloak", "INVTYPE_CLOAK", 30, agi(4), 1)
  GCA.infoCache = {}; GCA.candidates = nil
  GCA:RefreshKnown()
  local eItems = { [9] = link(991007), [15] = link(991008), [5] = link(991003) }
  view = { key = "Ench Paw", class = "DRUID", level = 40, items = eItems, spec = "FERAL_CAT" }
  l = run("Enchanting")
  local wrist, back, ch = sec(l, 9), sec(l, 15), sec(l, 5)
  local allEnch, ids, dup = true, {}, false
  for _, s in ipairs(l) do
    if s.kind ~= "enchant" then allEnch = false end
    local k = s.slot .. ":" .. s.enchant.enchant
    if ids[k] then dup = true end
    ids[k] = true
  end
  check(wrist and #wrist.rows == 3 and wrist.total >= 3 and nWrist >= 3 and back and #back.rows >= 1 and allEnch and not dup,
    ("enchants: wrist section %d of %d, cloak section %d; all enchant rows, no enchant twice in a slot"):format(wrist and #wrist.rows or -1, wrist and wrist.total or -1, back and #back.rows or -1))
  local placed = true
  for _, s in ipairs(l.sections) do for _, r in ipairs(s.rows) do if r.slot ~= s.key then placed = false end end end
  check(placed and ch and #ch.rows >= 1 and ch.rows[1].kind == "enchant", "every enchant row is in its slot's section (chest too)")
  local withRows = 0
  for _, s in ipairs(l.sections) do if #s.rows > 0 then withRows = withRows + 1 end end
  check(select(1, GCA.KnownOnly(l)) == withRows and withRows == 3, "enchant badge: one per slot (" .. withRows .. " slots)")

  setProfs({ { "Verzauberkunst", 300, 300, 333 } })
  GCA:RefreshKnown()
  view = { key = "Sec Paw", class = "DRUID", level = 40, items = items, spec = "FERAL_CAT" }
  l = run("Leatherworking")
  local maxRows, anyKnown = 0, false
  for _, s in ipairs(l.sections) do maxRows = math.max(maxRows, #s.rows) end
  for _, s in ipairs(l) do if s.known then anyKnown = true end end
  hands = sec(l, 10)
  check(GCA:IsBrowse("Leatherworking") and #l > 0 and maxRows <= 3 and not anyKnown and select(1, GCA.KnownOnly(l)) == 0
    and hands and #hands.rows == 3, ("browse: %d rows, at most %d per section, none known, badge 0"):format(#l, maxRows))

  for id, v in pairs(saved) do itemDB[id] = v or nil end
  for i = 991001, 991008 do itemDB[i] = nil end
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.db.known[GCA.charKey] = savedStore
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedSettings.lookahead, savedSettings.showUnlearned
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
end

section("look-ahead offers mail/plate that becomes wearable at 40, marked as a future row")
do
  setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  GCA:RefreshKnown()
  GCA:SelectProfession("Leatherworking")
  local spells = {}
  for spellID, r in pairs(ns.Recipes.Leatherworking) do
    if not GCA:ItemSets().ofItem[r.item] then spells[#spells + 1] = spellID end
  end
  table.sort(spells)
  local sMail, sLeather = spells[1], spells[2]
  local iMail, iLeather = ns.Recipes.Leatherworking[sMail].item, ns.Recipes.Leatherworking[sLeather].item
  local saved = { [iMail] = itemDB[iMail] or false, [iLeather] = itemDB[iLeather] or false }
  local savedKnown = {}
  for k, v in pairs(known) do savedKnown[k] = v end
  addItem(iMail, "Mail Vest", "INVTYPE_CHEST", 35, { ITEM_MOD_AGILITY_SHORT = 30, RESISTANCE0_NAME = 200 }, 3)
  addItem(iLeather, "Leather Boots", "INVTYPE_FEET", 30, { ITEM_MOD_AGILITY_SHORT = 12 }, 2)
  addItem(992001, "Worn Vest", "INVTYPE_CHEST", 30, { ITEM_MOD_AGILITY_SHORT = 5, RESISTANCE0_NAME = 80 }, 2)
  addItem(992002, "Worn Boots", "INVTYPE_FEET", 30, { ITEM_MOD_AGILITY_SHORT = 4 }, 2)
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  known[sMail], known[sLeather] = true, true
  GCA:RefreshKnown()
  local savedLA, savedUn = GCA.db.settings.lookahead, GCA.db.settings.showUnlearned
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = true, false
  local items = { [5] = link(992001), [8] = link(992002) }
  local function run(level)
    GCA.sugCache = {}
    local l = GCA:ComputeSuggestions({ key = "Hunt Er", class = "HUNTER", level = level, items = items, spec = "MARKSMANSHIP" }, false)
    local mail, boots
    for _, sg in ipairs(l) do
      if sg.cand and sg.cand.itemID == iMail then mail = sg elseif sg.cand and sg.cand.itemID == iLeather then boots = sg end
    end
    return mail, boots
  end
  local mail, boots = run(37)
  check(mail and mail.future and mail.wearAt == 40 and mail.levelsToGo == 3 and boots and not boots.future,
    "Lv37 Hunter: mail vest (item Lv35) offered as future, wearable at 40 (in 3); leather boots wearable now")
  mail = run(34)
  check(mail == nil, "Lv34 Hunter: 40 is beyond the 5-level look-ahead -> no mail")
  mail = run(41)
  check(mail and not mail.future and mail.wearAt == nil, "Lv41 Hunter: mail is a normal row")
  GCA.db.settings.lookahead = false
  mail, boots = run(37)
  check(mail == nil and boots ~= nil, "look-ahead off: no mail before 40")
  GCA.db.settings.lookahead, GCA.db.settings.showUnlearned = savedLA, savedUn
  for id, v in pairs(saved) do itemDB[id] = v or nil end
  itemDB[992001], itemDB[992002] = nil, nil
  for k in pairs(known) do known[k] = nil end
  for k, v in pairs(savedKnown) do known[k] = v end
  GCA.infoCache = {}; GCA.candidates = nil; GCA.sugCache = {}
  GCA:RefreshKnown()
end

section("Stored records: what a new read of a member's gear changes")
do
  local members, key = GCA.db.members, "Rec Paw"
  local viewer40 = "item:990001::::::::40:1488"
  local full = { [7] = viewer40, [10] = link(990002), [9] = link(990003) }
  check(GCA:StoreRecord(nil, "DRUID", 40, full, "inspect") == false, "no key -> nothing stored")
  check(GCA:StoreRecord(key, "DRUID", 40, full, "inspect") == true, "first read of a member -> stored as a change")
  local m = members[key]
  local ts0 = m.ts
  check(m.class == "DRUID" and m.level == 40 and m.items == full and m.source == "inspect" and ts0 == GCA:Now() and m.time == H.env.time(),
    "new record: class, level, gear, source, change stamp and last-seen time")
  H.advance(30)
  local viewer41 = "item:990001::::::::41:1488"
  local again = { [7] = viewer41, [10] = link(990002), [9] = link(990003) }
  check(GCA:StoreRecord(key, nil, 0, again, "sync") == false and m.items == full and m.items[7] == viewer41 and m.ts == ts0
    and m.time == H.env.time() and m.source == "inspect" and m.class == "DRUID" and m.level == 40,
    "same gear again: not a change, newer link strings kept, stamp and source kept, last-seen moved, no class or level 0 kept")
  check(GCA:StoreRecord(key, "DRUID", 41, { [7] = viewer41 }, "inspect") == false and m.items == full and m.level == 41,
    "an inspect that read fewer slots of the same gear is a partial read, not a change")
  local fewer = { [7] = viewer41 }
  check(GCA:StoreRecord(key, "DRUID", 41, fewer, "self") == true and m.items == fewer and m.source == "self" and m.ts == GCA:Now(),
    "fewer slots from the member's own record is a change")
  members[key] = { class = "DRUID", level = 40, time = 5 }
  local empty = {}
  check(GCA:StoreRecord(key, "DRUID", 40, empty, "inspect") == true and members[key].items == empty,
    "a record that never had gear takes the first read, even an empty one")
  members[key] = { class = "DRUID", level = 40, time = 5, items = { [7] = viewer40 } }
  check(GCA:StoreRecord(key, "DRUID", 40, { [7] = viewer40 }, "inspect") == false and members[key].ts == GCA:Now()
    and members[key].source == "inspect", "an old record without stamp or source gets both from an unchanged read")
  members[key] = nil
end

H.finish()
