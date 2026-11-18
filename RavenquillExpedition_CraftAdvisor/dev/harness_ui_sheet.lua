local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env = H.env
local section = H.section
local GCA, fakeSug, advance, menuOf, check, menuTexts = H.GCA, H.fakeSug, H.advance, H.menuOf, H.check, H.menuTexts
local plain, captureTip, tipText, plainTip, ns = H.plain, H.captureTip, H.tipText, H.plainTip, H.ns
local rectOf, rstr, overlap, layoutChecks, Frame = H.rectOf, H.rstr, H.overlap, H.layoutChecks, H.Frame
local Files, descendants, Tex = H.Files, H.descendants, H.Tex
H.lateGlobals()
H.templateMode = "fail"

do
  section("member view variants (character sheet / list)")
  local savedTM, savedBrowse = H.templateMode, GCA.IsBrowse
  H.templateMode = "ok"
  GCA.IsBrowse = function() return false end
  env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
  local printFn = GCA.Print
  local printed = {}
  GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
  local linked
  env.HandleModifiedItemClick = function(l) linked = l end
  local E = { key = "k4", set = { weights = { Agility = 1, Stamina = 0.5, Armor = 0.05, MeleeHit = 10, Strength = 0.8 }, source = {} },
    raw = { source = { kind = "sim", minLevel = 30, maxLevel = 40 } }, class = "ROGUE", spec = "COMBAT", level = 39, share = 0.5, t = 1 }
  local function eq(name, q, cstats) return { name = name, quality = q, icon = 134, link = "|Hitem:9|h[" .. name .. "]|h", cstats = cstats or {}, scores = {} } end
  local eqInfo = { [5] = eq("Worn Vest", 2, { Strength = 2 }), [11] = eq("Ring A", 3), [12] = eq("Ring B", 2), [9] = eq("Bracers", 1) }
  local items = { [5] = "item:4244", [11] = "item:5001", [12] = "item:5002", [9] = "item:4245" }
  local function rec(id) return { skill = 100, src = "trainer", r = {} } end
  local s1 = fakeSug({ e = E, equipped = eqInfo[5], oldScore = 1.6, newScore = 20, sortPct = 12, hint = nil,
    info = { name = "Hillman's Leather Vest", link = "|Hitem:4244|h[Hillman's Leather Vest]|h", quality = 2, icon = "x", minLevel = 20,
      cstats = { Agility = 6, Stamina = 4, Armor = 35, MeleeHit = 1, SpellHit = 1 } } })
  local s2 = fakeSug({ e = E, equipped = eqInfo[5], pct = 0.05, sortPct = 5, extra = true,
    cand = { spellID = 3763, itemID = 4245, recipe = rec() }, info = { name = "Second Vest", quality = 2, icon = "x", minLevel = 20, cstats = { Agility = 2 } } })
  local ring = fakeSug({ e = E, slot = 12, equipped = eqInfo[12], pct = 0.5, sortPct = 50,
    cand = { spellID = 3770, itemID = 5, recipe = rec() }, info = { name = "Craft Ring", quality = 3, icon = "x", minLevel = 20, link = "|Hitem:5|h[Craft Ring]|h" } })
  local glove = fakeSug({ e = E, slot = 10, future = true, wearAt = 42, levelsToGo = 3, pct = 0.2, sortPct = 20,
    cand = { spellID = 3771, itemID = 6, recipe = rec() }, info = { name = "Future Gloves", quality = 2, icon = "x", minLevel = 42 } })
  local ench1 = fakeSug({ e = E, kind = "enchant", slot = 9, pct = 0.08, sortPct = 8, enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" },
    cand = { spellID = 7779, enchant = true, recipe = rec() }, info = { name = "Enchant Bracer - Minor Agility", quality = 1, icon = "x", cstats = { Agility = 1 } },
    equipped = { name = "Minor Stamina", cstats = { Stamina = 1 } } })
  local ench2 = fakeSug({ e = E, kind = "enchant", slot = 9, pct = 0.04, sortPct = 4, extra = true, enchant = { enchant = 248, name = "Minor Spirit" }, item = { name = "Bracers" },
    cand = { spellID = 7780, enchant = true, recipe = rec() }, info = { name = "Enchant Bracer - Minor Spirit", quality = 1, icon = "x", cstats = {} },
    equipped = { name = "Minor Stamina", cstats = { Stamina = 1 } } })
  local sh1 = fakeSug({ e = E, slot = 3, pct = 0.3, sortPct = 30, hint = "Set hint", known = false,
    cand = { spellID = 3780, itemID = 7, recipe = rec() }, info = { name = "Shoulders of Many Stats", quality = 2, icon = "x", minLevel = 20,
      cstats = { Agility = 1, Stamina = 1, Armor = 1, Strength = 1, Intellect = 1, Spirit = 1, Defense = 1 }, unknownStats = { "ITEM_MOD_X" } } })
  local sh2 = fakeSug({ e = E, slot = 3, pct = 0.2, sortPct = 20, extra = true, cand = { spellID = 3781, itemID = 8, recipe = rec() },
    info = { name = "Second Shoulders", quality = 2, icon = "x", minLevel = 20 } })
  local sh3 = fakeSug({ e = E, slot = 3, pct = 0.1, sortPct = 10, extra = true, future = true, wearAt = 44, levelsToGo = 5,
    cand = { spellID = 3782, itemID = 10, recipe = rec() }, info = { name = "Third Shoulders", quality = 2, icon = "x", minLevel = 44 } })
  local function member(key, rowsBy, online)
    local list = {}
    for _, rows in pairs(rowsBy) do for _, r in ipairs(rows) do list[#list + 1] = r end end
    table.sort(list, GCA.SuggestionOrder)
    list.sections = GCA:BuildSections(rowsBy, {}, items, eqInfo, {}, E)
    return { key = key, online = online ~= false, class = "ROGUE", level = 39, prof = "Leatherworking", state = "ok", weights = E,
      member = { items = items, time = env.time(), source = "inspect" }, suggestions = list, best = list[1], knownCount = #list,
      spec = "COMBAT", specHow = "manual" }
  end
  local bud = member("Bud Stone", { [5] = { s1, s2 }, [11] = { ring }, [10] = { glove }, [9] = { ench1, ench2 }, [3] = { sh1, sh2, sh3 } })
  local cara = member("Cara Field", {})
  cara.best, cara.knownCount = nil, 0
  local olga = member("Olga Field", { [5] = { s1 } }, false)
  local nogear = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20, prof = "Leatherworking" }
  local list = { bud, cara, olga, nogear }
  local origML = GCA.GetMemberList
  GCA.GetMemberList = function() return list end
  GCA.db.settings.memberView = nil
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  local f = UIx.frame
  local errs = UIx.errorCount
  local mt = UIx.modeToggle
  local mm = menuOf(mt)
  check(UIx.MemberMode() == "sheet" and mt.native and mt._template == "WowStyle1DropdownTemplate" and mt.buttons == nil and #mm == 2
    and menuTexts(mm) == "Character sheet|List" and mm[1].kind == "radio" and mm[1]:on() and not mm[2]:on() and mt._override == "View: Character sheet",
    "the view switch is a WowStyle1DropdownTemplate (radios Character sheet|List, text View: Character sheet), the sheet is the default")
  GCA.db.settings.memberView = "junk"
  check(UIx.MemberMode() == "sheet", "a junk saved value means the sheet")
  GCA.db.settings.memberView = nil
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local sh, c = UIx.sheet, UIx.sheet.centre
  check(sh._shown and not UIx.sugList._shown and UIx.current == bud and UIx.emptyText._text == "", "member view: the sheet is shown, the list hidden")

  section("sheet: default slot, badges, selection")
  check(UIx.sheetSlot == 12 and UIx.sheetAuto and UIx.SheetDefaultSlot(bud.suggestions) == 12,
    "default slot = the biggest upgrade (Craft Ring +50% replaces Ring 2), not the first in character order")
  local badges, sel = {}, {}
  for slot, b in pairs(sh.slots) do
    if b.badge._shown then badges[#badges + 1] = slot end
    if b.sel._shown then sel[#sel + 1] = slot end
  end
  table.sort(badges)
  check(table.concat(badges, ",") == "3,5,9,10,12" and table.concat(sel, ",") == "12",
    "up-arrow badge on the 5 slots with an upgrade (ring badge on Ring 2 only), the selected slot keeps the item-button highlight: " .. table.concat(badges, ","))
  local b12 = sh.slots[12]
  check(b12.badgeKind == "file" and b12.badge._tex == "Interface\\BUTTONS\\Arrow-Up-Up" and b12.badge._SetVertexColor[2] == 1
    and b12.badge._alpha ~= 0.5, "badge = GearQuestForever's Arrow-Up-Up file tinted green")
  check(sh.slots[10].badge._alpha == 0.5, "a slot with only too-high-level crafts: dimmed badge")
  check(b12.gain._shown and b12.gain._text == "+50" and not sh.slots[1].gain._shown and sh.slots[10].gain._alpha == 0.5,
    "sheet rework: the slot's best gain on the icon (dimmed for level-locked crafts), none without an upgrade")
  check(sh.wornW == sh.iw and sh.bestW == sh.iw and c.arrowKind == "file", "sheet rework: Equipped / craft cards stacked at full width, down arrow between")
  check(sh.slots[5].icon._tex == 134 and not sh.slots[5].icon._SetDesaturated[1] and sh.slots[5].iconBorder._tex == "Interface\\Common\\WhiteIconFrame"
    and sh.slots[5].iconBorder._SetVertexColor[2] == 1, "worn item: its icon in a quality-coloured frame")
  check(sh.slots[1].icon._tex == "Interface\\PaperDoll\\UI-PaperDoll-Slot-HeadSlot" and sh.slots[1].icon._SetDesaturated[1] == true
    and sh.slots[1].icon._alpha == 0.45 and sh.slots[1].empty, "empty slot: the character window's slot art, desaturated and dimmed")
  check(plain(c.header._text) == "Ring 2" and c.count._text == "1 craftable upgrade" and c.mode == "upgrade" and c.featured == ring
    and plain(c.worn.name._text) == "Ring B" and c.worn.label._text == "Equipped" and c.best.label._text == "Best craft"
    and plain(c.best.name._text) == "Craft Ring" and c.best.gain._text == "+50 pts" and c.best.points._text == ""
    and c.best._shown and c.arrow._shown, "middle: 'Ring 2 · 1 craftable upgrade', Ring B -> Craft Ring, big '+50 pts' (no size line without a share)")
  check(c.worn.score._text == "1.0 pts" and c.best.score._text == "2.0 pts", "card scores = the comparison's old/new score (as the tooltip)")
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  check(UIx.sheetSlot == 5 and not UIx.sheetAuto and sh.slots[5].sel._shown and not sh.slots[12].sel._shown and c.featured == s1
    and c.count._text == "2 craftable upgrades" and plain(c.header._text) == "Chest", "slot click: the chest in the middle, highlight moves")
  local stats = {}
  for i = 1, c.nStats do stats[i] = plain(c.stats[i]._text) end
  check(c.nStats == 5 and table.concat(stats, ", ") == "+1% Hit, +6 Agility, +4 Stamina, +35 Armor, -2 Strength"
    and c.stats[5]._text:find("|cffff5555-2", 1, true) and c.stats[1]._text:find("|cff33ff33+1%", 1, true),
    "stat differences new - worn, biggest weighted first, hit twins merged, loss in red: " .. table.concat(stats, ", "))
  check(c.nAlts == 1 and c.alts[1]._shown and c.alts[1].data == s2 and c.moreTitle._text == "More options" and c.moreTitle._shown and c.sep._shown,
    "'More options': the slot's other craft")
  check(c.offer._shown and c.offer._text == "Offer" and c.crafted._shown and c.craftedLabel._text == "Crafted" and not c.crafted._checked,
    "actions: 'Crafted' box + 'Offer' button")
  c.crafted:SetChecked(true); c.crafted._scripts.OnClick(c.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) ~= nil and c.crafted._checked == true and UIx.sheetSlot == 5,
    "sheet crafted box stores the mark for Bud, the box shows it after the refresh, slot kept")
  captureTip(); c.crafted._scripts.OnEnter(c.crafted)
  check(H.tip[1] == "Crafted" and tipText():find("Crafted for Bud Stone", 1, true), "sheet crafted box tooltip (shared)")
  c.crafted:SetChecked(false); c.crafted._scripts.OnClick(c.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) == nil, "...unticked: mark gone")
  printed = {}
  c.offer._scripts.OnClick(c.offer)
  check(table.concat(printed, "\n"):find("Hi Bud! I'm a leatherworker and could craft you |Hitem:4244", 1, true), "sheet Offer writes the whisper for the featured craft")
  captureTip(); c.offer._scripts.OnEnter(c.offer)
  check(H.tip[1] == "Offer" and #H.tip >= 5, "sheet Offer tooltip (shared with the rows)")
  c.alts[1]._scripts.OnClick(c.alts[1])
  check(c.featured == s2 and c.best.label._text == "Compared" and c.alts[1].data == s1 and UIx.sheetSlot == 5, "alternative clicked: compared above ('Compared'), the best one listed below")
  captureTip(); c.alts[1]._scripts.OnEnter(c.alts[1])
  check(plainTip(), "alternative tooltip = the plain item tooltip (no click hint): " .. tipText())
  linked = nil
  env.IsShiftKeyDown = function() return true end
  c.alts[1]._scripts.OnClick(c.alts[1])
  sh.slots[11]._scripts.OnClick(sh.slots[11])
  env.IsShiftKeyDown = function() return false end
  check(linked == "|Hitem:9|h[Ring A]|h" and UIx.sheetSlot == 5 and c.featured == s2, "shift-click on a slot links the worn item (selection unchanged)")
  linked = nil
  env.IsShiftKeyDown = function() return true end
  c.best._scripts.OnClick(c.best, "LeftButton")
  local bestLinked = linked
  c.worn._scripts.OnClick(c.worn, "LeftButton")
  env.IsShiftKeyDown = function() return false end
  check(bestLinked == nil and linked == "|Hitem:9|h[Worn Vest]|h" and c.featured == s2,
    "shift-click on the compared card without a link does nothing; on the worn card it links the worn item")
  do
    local opened, savedTS = {}, env.C_TradeSkillUI
    env.C_TradeSkillUI = { OpenRecipe = function(id) opened[#opened + 1] = id end }
    c.worn._scripts.OnClick(c.worn, "LeftButton")
    c.best._scripts.OnClick(c.best, "LeftButton")
    env.C_TradeSkillUI = savedTS
    check(#opened == 1 and opened[1] == 3763, "plain click: the worn card does nothing, the compared card opens its recipe")
  end
  sh.slots[9]._scripts.OnClick(sh.slots[9])
  check(c.featured == ench1 and c.best.label._text == "Best enchant" and c.alts[1].data == ench2 and c.alts[1].tag._shown
    and plain(c.alts[1].tag._text) == "Enchant" and c.craftedLabel._text == "Enchanted"
    and plain(c.tags._text) == "replaces Minor Stamina on Bracers", "enchants: 'Best enchant', alternative with an 'Enchant' marker, 'Enchanted' box")
  local es = {}
  for i = 1, c.nStats do es[i] = plain(c.stats[i]._text) end
  check(table.concat(es, ", ") == "+1 Agility, -1 Stamina", "enchant stat differences = new enchant - current enchant: " .. table.concat(es, ", "))
  sh.slots[10]._scripts.OnClick(sh.slots[10])
  check(c.featured == glove and c.best.dimmed and c.best.icon._alpha == 0.55 and plain(c.tags._text) == "from level 42 · 3 to go"
    and c.tags._text:find("|cfff0b44c", 1, true), "too-high-level craft: dimmed card, orange 'from level 42 · 3 to go'")
  sh.slots[1]._scripts.OnClick(sh.slots[1])
  check(c.mode == "none" and not c.best._shown and not c.arrow._shown and not c.offer._shown and c.none._shown
    and c.none._text == "No craftable upgrade" and plain(c.worn.name._text) == "nothing equipped" and c.count._text == "0 craftable upgrades",
    "slot without an upgrade: worn card + 'No craftable upgrade', nothing else")
  sh.slots[2]._scripts.OnClick(sh.slots[2])
  check(c.mode == "none" and c.none._shown, "...also for another empty slot")
  captureTip(); sh.slots[5]._scripts.OnEnter(sh.slots[5])
  check(plainTip(), "slot with a worn item: the plain item tooltip only: " .. tipText())
  captureTip(); sh.slots[1]._scripts.OnEnter(sh.slots[1])
  check(tipText():find("Head (empty / unknown)", 1, true) and tipText():find("Nothing in this list beats", 1, true), "empty slot tooltip")
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  captureTip(); c.best._scripts.OnEnter(c.best)
  check(plainTip("4244") and UIx.modWatcher == nil, "best card tooltip = the plain item tooltip (no Shift re-render any more)")
  captureTip(); c.worn._scripts.OnEnter(c.worn)
  check(plainTip(), "worn card tooltip = the plain item tooltip: " .. tipText())
  sh.slots[3]._scripts.OnClick(sh.slots[3])
  check(c.nStats == 6 and c.nAlts == 2 and plain(c.tags._text):find("+1 more", 1, true) and plain(c.tags._text):find("some stats not readable", 1, true)
    and c.source._shown and c.source.text._text == UIx.LearnText(c.featured, UIx.current) and not c.offer._shown,
    "7 stat changes: 6 shown + '+1 more', 'some stats not readable'; the shared source button (no Offer for an unlearned recipe)")
  check(c.alts[2].data == sh3 and c.alts[2].offer._shown and plain(c.alts[2].tag._text) == "from level 44 · 5 to go" and c.alts[2].dimmed
    and (c.alts[2].offer._alpha or 1) == 1, "alternatives: level tag (orange text) + dimmed for too-high-level (Offer stays at full alpha)")
  section("switch keeps the member and the slot; saved (K6: the dropdown's radios)")
  menuOf(UIx.modeToggle)[2]:click()
  check(GCA.db.settings.memberView == "list" and UIx.selected == "Bud Stone" and UIx.current == bud and UIx.sugList._shown and not sh._shown
    and menuOf(UIx.modeToggle)[2]:on() and not menuOf(UIx.modeToggle)[1]:on() and UIx.modeToggle._override == "View: List",
    "-> List: saved, Bud still selected, cards shown, dropdown text 'View: List'")
  local sl = UIx.sugList
  check(sl.pools.section and sl.pools.section[1]._shown and sl.pools.default[1]._shown and sl.pools.default[1].data == ring, "list: section headers + cards, biggest first")
  menuOf(UIx.modeToggle)[1]:click()
  check(GCA.db.settings.memberView == "sheet" and UIx.selected == "Bud Stone" and UIx.sheetSlot == 3 and sh._shown and not sl._shown,
    "-> Character sheet: Bud and the shoulders slot kept")
  f:Hide(); GCA.UI:Toggle(); advance(1)
  UIx:SetMemberMode("list")
  f:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(UIx.MemberMode() == "list" and menuOf(UIx.modeToggle)[2]:on() and UIx.modeToggle._override == "View: List" and not UIx.sheet._shown,
    "a new window (reload) opens the saved variant: List")
  UIx:SetMemberMode("sheet")
  sh, c = UIx.sheet, UIx.sheet.centre
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  UIx:Refresh()
  check(UIx.sheetSlot == 5, "a refresh keeps the picked slot")
  UIx.selected = "Olga Field"; UIx:Refresh()
  check(UIx.current == olga and UIx.sheetSlot == 5 and UIx.sheetAuto and not c.offer._shown and c.crafted._shown,
    "another member (offline Olga): her best slot, no Offer (offline), crafted box")
  UIx.selected = "Bud Stone"; UIx:Refresh()
  check(UIx.sheetSlot == 12 and UIx.sheetAuto, "back to Bud: his best slot again (the pick belonged to the member shown then)")

  section("members without upgrades / without gear")
  UIx.selected = "Cara Field"; UIx:Refresh()
  local anyBadge = false
  for _, b in pairs(sh.slots) do if b.badge._shown then anyBadge = true end end
  check(sh._shown and not anyBadge and UIx.sheetSlot == 1 and c.mode == "none" and c.none._shown
    and c.none._text == string.format(ns.Locales.enUS.EMPTY_NOKNOWN, "Leatherworking", "Leatherworking") and UIx.emptyText._text == "", "no upgrade at all: the sheet (worn gear), no badge, the empty-state reason in the middle: " .. tostring(c.none._text))
  UIx.selected = "Nobody Yet"; UIx:Refresh()
  check(not sh._shown and UIx.emptyText._text == ns.Locales.enUS.EMPTY_NOGEAR, "no gear recorded: no sheet, the empty-state text explains: " .. tostring(UIx.emptyText._text))

  section("list cards (MemberCards)")
  UIx.selected = "Bud Stone"
  UIx:SetMemberMode("list")
  sl = UIx.sugList
  local card
  for _, r in ipairs(sl.pools.default) do if r._shown and r.data == s1 then card = r end end
  check(card and plain(card.title._text) == "Hillman's Leather Vest" and plain(card.sub._text) == ""
    and card.gain._text == "+12 pts" and card.points._text == "" and card.offer._shown and card.crafted._shown,
    "card (user 2026-11-15): name, no stat-difference line, '+12 pts', box, Offer: " .. plain(card and card.sub._text))
  check(card.textW + (16 + 4 + 38 + 4 + 10) + (6 + 84 + 4 + 22 + 6 + 84 + 10) == UIx.sugList.viewW, "card texts (16 px indent) end where the gain / box / Offer block starts (no overlap)")
  card.crafted:SetChecked(true); card.crafted._scripts.OnClick(card.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) ~= nil, "card crafted box stores the mark")
  GCA:SetCrafted("Bud Stone", "Leatherworking", s1, false)
  printed = {}
  for _, r in ipairs(sl.pools.default) do if r._shown and r.data == s1 then card = r end end
  card.offer._scripts.OnClick(card.offer)
  check(table.concat(printed, "\n"):find("could craft you |Hitem:4244", 1, true), "card Offer writes the whisper")
  local hdr
  for _, h in ipairs(sl.pools.section) do if h._shown and h.data.sec.key == 11 then hdr = h end end
  check(hdr and plain(hdr.wornName._text) == "Ring A  ·  Ring B" and hdr.label == nil and hdr.count._text == "1 upgrade",
    "ring worn row: 'EQUIPPED', both rings named, '1 upgrade'")
  local fold = sl.pools.fold[1]
  check(fold._shown and fold.edges == nil and fold.line and fold.text._text:find("^No craftable upgrade: Head, Neck, ") and sl.data[#sl.data].rowKind == "fold",
    "the slots without an upgrade: one grey line at the end (K6: no box border)")
  local glHdr
  for _, h in ipairs(sl.pools.section) do if h._shown and h.data.sec.key == 10 then glHdr = h end end
  check(glHdr and plain(glHdr.wornName._text) == UIx.SectionTitle(glHdr.data.sec) .. " (empty)" and glHdr.empty and glHdr.box.bg == nil and glHdr.box.icon._SetDesaturated[1] == true
    and glHdr.box.icon._alpha == 0.45, "empty slot: dimmed '<Slot> (empty)', (K6: no box at all), the slot art desaturated")
  local gcard
  for _, r in ipairs(sl.pools.default) do if r._shown and r.data == glove then gcard = r end end
  check(gcard and gcard.dimmed and gcard.chip == nil and plain(gcard.sub._text):find("^from level 42 · 3 to go") and gcard.title._alpha == 0.55,
    "too-high-level card: dimmed, the orange level tag first on its second line")
  local ecard
  for _, r in ipairs(sl.pools.default) do if r._shown and r.data == ench1 then ecard = r end end
  check(ecard and plain(ecard.sub._text) == "replaces Minor Stamina on Bracers", "enchant card: what it replaces (no stat changes): " .. plain(ecard and ecard.sub._text))
  check(UIx.errorCount == errs, "no error reported (K4 English)")

  section("German")
  ns.locale = "deDE"
  f = UIx.frame
  f:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  check(menuTexts(menuOf(UIx.modeToggle)) == "Charakterbogen|Liste" and UIx.modeToggle._override:find("^Ansicht: "), "German switch: radios Charakterbogen|Liste, text Ansicht: …")
  local sl2 = UIx.sugList
  local gh
  for _, h in ipairs(sl2.pools.section) do if h._shown and h.data.sec.key == 10 then gh = h end end
  check(gh and gh.label == nil and plain(gh.wornName._text) == UIx.SectionTitle(gh.data.sec) .. " (leer)" and gh.count._text == "1 Verbesserung"
    and sl2.pools.fold[1].text._text:find("^Keine herstellbare Verbesserung: "),
    "German cards: '<Platz> (leer)', '1 Verbesserung', 'Keine herstellbare Verbesserung: …'")
  UIx:SetMemberMode("sheet")
  sh, c = UIx.sheet, UIx.sheet.centre
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  check(c.worn.label._text == "Getragen" and c.best.label._text == "Beste Herstellung" and c.count._text == "2 herstellbare Verbesserungen"
    and c.moreTitle._text == "Weitere Möglichkeiten" and c.craftedLabel._text == "Hergestellt" and c.offer._text == "Anbieten",
    "German sheet: Getragen / Beste Herstellung / 2 herstellbare Verbesserungen / Weitere Möglichkeiten / Hergestellt / Anbieten")
  check(plain(c.stats[1]._text) == "+1% Treffer" and plain(c.stats[2]._text) == "+6 Beweglichkeit", "German stat names: " .. plain(c.stats[1]._text))
  sh.slots[1]._scripts.OnClick(sh.slots[1])
  check(c.none._text == "Keine herstellbare Verbesserung", "German: 'Keine herstellbare Verbesserung'")
  sh.slots[10]._scripts.OnClick(sh.slots[10])
  check(plain(c.tags._text) == "ab Stufe 42 · noch 3", "German level tag: " .. plain(c.tags._text))

  section("layout of both variants (840x560 / 980x640 / 1600x1000, both languages)")
  local function sheetLayout(UIy, label)
    local fw = UIy.frame
    local R = function(fr) return rectOf(fr, fw) end
    local sheetFrame, c3 = UIy.sheet, UIy.sheet.centre
    local si, sr, cr = R(UIy.sugInset), R(sheetFrame), R(c3)
    local bad = {}
    local function inside(a, b) return a.l >= b.l and a.r <= b.r and a.t >= b.t and a.b <= b.b end
    if not inside(sr, si) then bad[#bad + 1] = "sheet outside the panel " .. rstr(sr) end
    local slots = {}
    for slot, b in pairs(sheetFrame.slots) do
      local r = R(b)
      slots[#slots + 1] = { slot, r }
      if not inside(r, sr) then bad[#bad + 1] = "slot " .. slot .. " outside " .. rstr(r) end
      if overlap(r, cr) then bad[#bad + 1] = "slot " .. slot .. " over the middle panel " .. rstr(r) end
      if r.r - r.l ~= 40 or r.b - r.t ~= 40 then bad[#bad + 1] = "slot " .. slot .. " not 40x40" end
    end
    for i = 1, #slots do for j = i + 1, #slots do
      if overlap(slots[i][2], slots[j][2]) then bad[#bad + 1] = "slots " .. slots[i][1] .. "/" .. slots[j][1] .. " overlap" end
    end end
    local parts = { { "header", c3.header }, { "count", c3.count }, { "worn card", c3.worn } }
    if c3.mode == "upgrade" then
      for _, x in ipairs({ { "best card", c3.best }, { "arrow", c3.arrow } }) do parts[#parts + 1] = x end
      for i = 1, c3.nStats do parts[#parts + 1] = { "stat " .. i, c3.stats[i] } end
      if c3.hasTags then parts[#parts + 1] = { "tags", c3.tags } end
      if c3.offer._shown then parts[#parts + 1] = { "offer", c3.offer } end
      if c3.crafted._shown then parts[#parts + 1] = { "crafted", c3.crafted }; parts[#parts + 1] = { "crafted label", c3.craftedLabel } end
      if (c3.nAltsShown or c3.nAlts) > 0 then parts[#parts + 1] = { "sep", c3.sep }; parts[#parts + 1] = { "more", c3.moreTitle } end
      for i = 1, c3.nAltsShown or c3.nAlts do parts[#parts + 1] = { "alt " .. i, c3.alts[i] } end
    else
      parts[#parts + 1] = { "message", c3.none }
    end
    local rects = {}
    for _, p in ipairs(parts) do
      local r = R(p[2])
      rects[#rects + 1] = { p[1], r }
      if not inside(r, cr) then bad[#bad + 1] = p[1] .. " outside the middle " .. rstr(r) .. " in " .. rstr(cr) end
    end
    for i = 1, #rects do for j = i + 1, #rects do
      local a, b = rects[i], rects[j]
      if overlap(a[2], b[2]) and not (a[1] == "sep" or b[1] == "sep") then bad[#bad + 1] = a[1] .. " x " .. b[1] end
    end end
    if c3.contentH > cr.b - cr.t then bad[#bad + 1] = "content " .. c3.contentH .. " > panel " .. (cr.b - cr.t) end
    for i = 1, c3.nAltsShown or c3.nAlts do
      local a = c3.alts[i]
      local ar, nr, gr = R(a), R(a.name), R(a.gain)
      if nr.r > (a.tag._shown and R(a.tag).l or gr.l) then bad[#bad + 1] = "alt " .. i .. " name runs under its tag/gain" end
      if a.offer._shown and gr.r > R(a.offer).l then bad[#bad + 1] = "alt " .. i .. " gain under the Offer button" end
      if R(a.offer).r > ar.r then bad[#bad + 1] = "alt " .. i .. " Offer outside" end
    end
    check(#bad == 0, label .. ": sheet slots inside the panel, the middle panel's parts inside it, nothing overlaps " .. table.concat(bad, "; "))
  end
  for _, loc in ipairs({ "deDE" }) do
    ns.locale = loc
    UIx.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
    UIx = GCA.UI
    UIx.selected, UIx.autoKey = "Bud Stone", nil
    UIx:SetView("member")
    for _, sz in ipairs({ { 840, 560 }, { 980, 640 } }) do
      UIx.frame:SetSize(sz[1], sz[2]); UIx:Layout()
      for _, slot in ipairs({ 3, 5, 9, 1 }) do
        UIx.sheet.slots[slot]._scripts.OnClick(UIx.sheet.slots[slot])
        sheetLayout(UIx, loc .. " " .. sz[1] .. "x" .. sz[2] .. " slot " .. slot)
      end
      layoutChecks(UIx, UIx.frame, "" .. loc .. " " .. sz[1] .. "x" .. sz[2] .. " (sheet)")
      UIx:SetMemberMode("list")
      layoutChecks(UIx, UIx.frame, "" .. loc .. " " .. sz[1] .. "x" .. sz[2] .. " (list)")
      local okCards = true
      for _, r in ipairs(UIx.sugList.pools.default) do
        if r._shown and r.textW then
          local showO, showC = r.offer._shown, r.crafted._shown
          local rightW = 6 + (showO and 88 or 0) + (showC and 28 or 0) + 84 + 10
          if r.textW + 72 + rightW ~= UIx.sugList.viewW or r.textW < 60 then okCards = false end
        end
      end
      check(okCards, "" .. loc .. " " .. sz[1] .. "x" .. sz[2] .. ": every card's texts end at its right block, at least 60 px wide (K6: 16 px indent)")
      UIx:SetMemberMode("sheet")
    end
  end
  ns.locale = "enUS"
  local function fits(text, px, per) return #plain(text):gsub("[\128-\191]", "") * per <= px end
  local tooWide = {}
  local function fit(name, text, px, per) if not fits(text, px, per) then tooWide[#tooWide + 1] = name .. " '" .. plain(text) .. "'" end end
  local D = ns.Locales.deDE
  fit("switch sheet", D.MVIEW_SHEET, 100 - 8, 5.6)
  fit("switch list", D.MVIEW_LIST, 56 - 8, 5.6)
  UIx.frame:SetSize(840, 560); UIx:Layout()
  local shx = UIx.sheet
  fit("worn label", D.SHEET_WORN, shx.wornW - 58 - 10, 5.6)
  fit("best label", D.SHEET_BEST_ENCH, shx.bestW - 58 - 90, 5.6)
  fit("compared label", D.SHEET_PICKED, shx.bestW - 58 - 90, 5.6)
  fit("more title", D.SHEET_MORE, shx.iw, 5.6)
  fit("count", string.format(D.SHEET_COUNT_ENCH, 3), shx.iw - 100, 5.6)
  fit("level tag", string.format(D.LEVEL_TAG, 60, 10), 160, 5.6)
  check(#tooWide == 0, "German text fit at 840x560 (estimate): " .. table.concat(tooWide, "; "))

  section("fallbacks")
  env.GetFileIDFromPath = function() return nil end
  UIx.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local s12 = UIx.sheet.slots[12]
  check(s12.badgeKind == "text" and s12.badge._text == "+" and s12.badge._shown and not s12.frameArt and s12.qual._SetColorTexture[2] == 1
    and not s12.iconBorder._shown, "no files: badge = a green '+', the quality colour as a square behind the icon")
  UIx:SetMemberMode("list")
  check(UIx.sugList.pools.default[1].frameArt == "atlas" and UIx.sugList.pools.default[1].slotBg and UIx.errorCount == errs, "no files: cards keep the reagent-slot atlas (no file needed)")
  UIx:SetMemberMode("sheet")
  env.GetFileIDFromPath = nil
  env.GameFontGreenLarge = {}
  local fontSet
  Frame.SetFontObject = function(self, fo) self._font = fo; fontSet = true end
  UIx.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(fontSet and UIx.sheet.centre.best.gain._font == env.GameFontGreenLarge and UIx.sheet.centre.best.gain.nativeFont == "GameFontGreenLarge", "GameFontGreenLarge exists: the sheet's big gain uses it")
  env.GameFontGreenLarge, Frame.SetFontObject = nil, nil
  local origCF = env.CreateFrame
  env.CreateFrame = function(otype, name, parent, template)
    if template == "UIPanelButtonTemplate" or template == "UICheckButtonTemplate" or template == "MinimalCheckboxTemplate" then error("no " .. template) end
    return origCF(otype, name, parent, template)
  end
  local tb = UIx.NewTextButton(UIx.frame, 84, 22, "Offer")
  local cb = UIx.NewCheck(UIx.frame, 22)
  env.CreateFrame = origCF
  check(tb.plain and tb:GetText() == "Offer" and tb.label._text == "Offer" and tb._w == 84 and tb.edges and cb.plain and cb._w == 22 and cb.edges,
    "button / check-box templates missing: plain button with its own label, bordered box")
  check(UIx.StatDiff(fakeSug()) == nil and UIx.StatDiff(fakeSug({ info = { cstats = {} }, equipped = { name = "x" } })) == nil
    and #UIx.StatDiff(fakeSug({ info = { cstats = { Agility = 2 } } })) == 1, "StatDiff: no stats on a side -> nil; empty slot -> all stats of the new item")
  UIx.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  local errs2 = UIx.errorCount
  for _, fr in ipairs({ UIx.sheet.slots[1], UIx.sheet.centre.worn, UIx.sheet.centre.best }) do
    captureTip(); pcall(fr._scripts.OnEnter, fr); pcall(fr._scripts.OnClick, fr, "LeftButton")
  end
  check(UIx.errorCount == errs2, "sheet handlers before any data: no error")
  check(UIx.errorCount == errs2 and H.badAtlas == 0, "no error reported (K4)")
  UIx.frame:Hide()
  GCA.GetMemberList = origML
  GCA.Print = printFn
  env.HandleModifiedItemClick = function() end
  env.IsShiftKeyDown = function() return false end
  env.ITEM_QUALITY_COLORS = nil
  GCA.db.settings.memberView = nil
  GCA.UI.frame = nil
  H.templateMode, GCA.IsBrowse = savedTM, savedBrowse
end

check(H.badAtlas == 0, "SetAtlas was never called for an atlas the client lacks (" .. H.badAtlas .. ")")
do
  section("native look (no mockup gimmicks left, atlases from the probe, slot art, fallbacks)")
  local src = Files.source(Files.group("UI"))
  local gone = {}
  for _, word in ipairs({ "CreateRing", "CreateModeToggle", "CreateChip", "CreateMemberChip", "SetRingColor",
    "selectBar", "treeLine", "chipBg", "sectionHeader", "rowAlt", "BigFont", "CreateOptionsMenu", "CreateOfflineBox" }) do
    if src:find(word, 1, true) then gone[#gone + 1] = word end
  end
  check(#gone == 0, "no custom circle / segmented control / chip / select-bar / tree-line / Options-popup code left in UI.lua " .. table.concat(gone, ", "))
  local PROBE = { ["Profession-Background-Overview"] = 1, ["Profession-Background-Template2"] = 1, ["Professions-Slot-Frame"] = 1,
    ["Professions-Slot-bg"] = 1, ["Professions-background-summarylist"] = 1, ["Professions-skillbar-bg"] = 1, ["Professions-skillbar-frame"] = 1,
    ["UI-Character-Info-GearSlot"] = 1, ["common-dropdown-a-button"] = 1, ["search-highlight"] = 1,
    ["UI-Frame-InnerTopLeft"] = 1, ["UI-Frame-InnerTopRight"] = 1, ["UI-Frame-InnerBotLeftCorner"] = 1, ["UI-Frame-InnerBotRight"] = 1,
    ["_UI-Frame-InnerTopTile"] = 1, ["_UI-Frame-InnerBotTile"] = 1, ["!UI-Frame-InnerLeftTile"] = 1, ["!UI-Frame-InnerRightTile"] = 1,
    ["Skillbar_Fill_Flipbook_Leatherworking"] = 1, ["Skillbar_Flare_Leatherworking"] = 1,
    ["Professions_Recipe_Hover"] = 1, ["Professions_Recipe_Active"] = 1, ["common-button-list-collapseExpand"] = 1,
    ["auctionhouse-ui-filter-redx"] = 1,
    ["common-insideframe"] = 1 }
  for _, pair in ipairs(GCA.UI.SKIN.collapseIcon.pairs) do PROBE[pair[1]] = 1; PROBE[pair[2]] = 1 end
  local OLD = { ["common-dropdown-bg"] = 1, ["glueannouncementpopup-icon-info"] = 1, ["classicon-"] = 1 }
  local unknown, n = {}, 0
  for _, pat in ipairs({ 'SetAtlasSafe%([^,]+, "([^"]+)"', 'HasAtlas%("([^"]+)"%)', 'atlas = "([^"]+)"', 'INFO_ATLAS = "([^"]+)"' }) do
    for name in src:gmatch(pat) do
      n = n + 1
      if not (PROBE[name] or OLD[name]) then unknown[#unknown + 1] = name end
    end
  end
  check(n >= 12 and #unknown == 0, "every atlas named in UI.lua (" .. n .. ") is from the probe or an older guarded one " .. table.concat(unknown, ", "))
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  local s5 = UIx.sheet.slots[5]
  check(s5.gearArt and s5.bg._atlas == "UI-Character-Info-GearSlot" and s5.bg._w == 59 and s5.frameArt == "file"
    and s5.iconBorder._tex == "Interface\\Common\\WhiteIconFrame" and s5.hl._tex == UIx.TEX.iconHL and s5.selKind == "file",
    "sheet slot: UI-Character-Info-GearSlot behind (55/37 scaled), WhiteIconFrame border, ButtonHilight-Square hover + kept on when selected")
  check(UIx.sheet.centre.edges == nil and UIx.sheet.centre.bg == nil and UIx.sheet.centre.best.edges == nil and UIx.sheet.centre.best.tint == nil,
    "sheet: no hand-drawn boxes / green tint around the middle panel and the cards")
  local cb, tb = UIx.NewCheck(UIx.frame, 22), UIx.NewTextButton(UIx.frame, 84, 22, "x")
  check(cb.template == "MinimalCheckboxTemplate" and not cb.plain and not tb.plain, "check boxes from MinimalCheckboxTemplate, buttons from UIPanelButtonTemplate")
  check(UIx.MemberRun == nil and UIx.expanded == nil and UIx.NEED_RIGHT_W == nil and not src:find("caretText", 1, true)
    and not src:find("membersShown", 1, true), "no member text runs / carets / expand state left (the detail panel lists the members)")
  local boxy = {}
  local function scanRow(name, b)
    for _, t in ipairs(descendants(b)) do
      if t._SetColorTexture or t.edges or t._backdrop then boxy[#boxy + 1] = name end
    end
    if b.edges or b._backdrop then boxy[#boxy + 1] = name end
  end
  scanRow("member row", UIx.memberList.pools.default[1])
  scanRow("group header", UIx.memberList.pools.group[1])
  if UIx.needsList.pools.default[1] then scanRow("craft row", UIx.needsList.pools.default[1]) end
  if UIx.needsList.pools.cat then scanRow("slot category", UIx.needsList.pools.cat[1]) end
  check(UIx.memberList.pools.default[1] and #boxy == 0, "list rows and category headers draw no colour boxes / borders (atlas art only) " .. table.concat(boxy, ", "))
  local skinDB = UIx.SKIN.detailBorder
  UIx.SKIN.detailBorder = { pieces = { { key = "TopLeftCorner", atlas = "UI-Frame-InnerTopLeft", w = 12, p = { "TOPLEFT", -2, 2 } },
    { key = "TopRightCorner", atlas = "UI-Frame-InnerTopRight", w = 12, p = { "TOPRIGHT", 2, 2 } },
    { key = "TopEdge", atlas = "_UI-Frame-InnerTopTile", h = 5, a = { "TOPLEFT", "TopLeftCorner", "TOPRIGHT" }, b = { "TOPRIGHT", "TopRightCorner", "TOPLEFT" }, horiz = true } } }
  local pb = UIx.AddDetailBorder(env.CreateFrame("Frame", nil, env.UIParent))
  check(pb.how == "pieces" and pb.role == "detailBorder" and pb.TopLeftCorner._w == 12 and pb.TopEdge._h == 5 and pb.TopLeftCorner._points[1][4] == -2,
    "detailBorder: a piece list from the skin (sizes / offsets per piece)")
  UIx.SKIN.detailBorder = { pieces = { { key = "TopLeftCorner", atlas = "NotAnAtlas-K8", p = { "TOPLEFT", 0, 0 } } } }
  local pf = UIx.AddDetailBorder(env.CreateFrame("Frame", nil, env.UIParent))
  check(pf.how == "atlas" and pf.role == "detailBorder" and pf.TopLeftCorner._atlas == "UI-Frame-InnerTopLeft", "detailBorder: a missing piece atlas -> the inner border")
  env.NineSliceUtil = { ApplyLayoutByName = function(f, name) if name == "K8TestLayout" then f.TopLeftCorner = { layout = name } else error("no layout") end end }
  UIx.SKIN.detailBorder = { layout = "K8TestLayout" }
  local pl = UIx.AddDetailBorder(env.CreateFrame("Frame", nil, env.UIParent))
  check(pl.how == "layout" and pl.TopLeftCorner.layout == "K8TestLayout", "detailBorder: a NineSliceUtil layout name from the skin")
  UIx.SKIN.detailBorder = { layout = "Missing" }
  local pm = UIx.AddDetailBorder(env.CreateFrame("Frame", nil, env.UIParent))
  check(pm.how == "atlas" and pm.role == "detailBorder", "detailBorder: an unknown layout -> the inner border")
  env.NineSliceUtil = nil
  UIx.SKIN.detailBorder = skinDB
  local rf = env.CreateFrame("Button", nil, env.UIParent)
  local masked
  rf.CreateMaskTexture = function(self) local m = Tex(); m._parent = self; return m end
  local origCT = Frame.CreateTexture
  Frame.CreateTexture = function(self, ...) local t = origCT(self, ...); t.AddMaskTexture = function(tt, m) masked = m end; return t end
  UIx.AddRoundIcon(rf, 46)
  Frame.CreateTexture = origCT
  check(rf.iconShape == "round" and masked == rf.mask and rf.mask._tex == "Interface\\CharacterFrame\\TempPortraitAlphaMask" and rf.ring._tex == "Interface\\Common\\GoldRing"
    and rf.ring._w == 57 and rf.icon._w == 46, "round icon: TempPortraitAlphaMask on the icon, GoldRing 57 px around 46 px (FDJ's 37/30)")
  local sq = env.CreateFrame("Button", nil, env.UIParent)
  UIx.AddRoundIcon(sq, 46)
  check(sq.iconShape == "square" and sq.iconBorder._atlas == "Professions-Slot-Frame", "round icon: no mask API -> the square reagent-slot icon")
  UIx.frame:Hide()
end

H.finish()
