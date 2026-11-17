local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local windowChecks, GCA, descendants, check, advance = H.windowChecks, H.GCA, H.descendants, H.check, H.advance
local menuOf, menuTexts, fakeSug, plain, captureTip = H.menuOf, H.menuTexts, H.fakeSug, H.plain, H.captureTip
local plainTip, tipText, New, ns, fakeSections = H.plainTip, H.tipText, H.New, H.ns, H.fakeSections
local longList, manyMembers, layoutChecks, Frame = H.longList, H.manyMembers, H.layoutChecks, H.Frame

H.templateMode = "ok"; windowChecks("PortraitFrameTemplate path")
do
  local f, n = GCA.UI.frame, 0
  for _, c in ipairs(descendants(f)) do if c.NineSlice and c ~= f and c.Bg then n = n + 1 end end
  check(n == 0, "no InsetFrameTemplate panels while the list atlas exists (" .. n .. ")")
end

do
  print("== Window: profession selector (G3/G6.1/G7.11)")
  local profs = { 165, 333 }
  GetProfessions = function() return 1, 2 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
    if i == 2 then return "Verzauberkunst", nil, 90, 150, nil, nil, 333 end
  end
  GCA:RefreshKnown()
  GCA.UI:Toggle(); advance(1)
  local f, pb, pop = GCA.UI.frame, GCA.UI.profButton, GCA.UI.profPopup
  check(pb and (pb.label._text or "") == "Lederverarbeitung  120 / 150" and pb.art == "atlas" and pb.bg._atlas == "Professions-skillbar-bg"
    and pb.border._atlas == "Professions-skillbar-frame" and pb._h == 29 and math.abs(pb.ratio - 0.8) < 1e-9 and pb.barKind == "fill"
    and math.abs(pb.fill._w - (GCA.UI.PROF_BAR_W - 10) * 0.8) < 1e-9 and pb.drop.native and pb.drop.arrow._atlas == "common-dropdown-a-button"
    and pb.drop.ring == nil and pop == nil,
    "the profession window's rank bar (skillbar-bg/-frame, 29 px, fill 80 %; plain fill: no StatusBar texture API in this mock) with its dropdown arrow (no disc): " .. tostring(pb and pb.label._text))
  local pm = menuOf(pb.drop)
  local radios = menuTexts(pm, "radio")
  check(#pm == 7 and pm[1]:on() and radios:find("^Lederverarbeitung.*|Verzauberkunst.*|Blacksmithing %(browse%)") and pm[3].kind == "divider"
    and pm[4].kind == "title" and pm[4].text:find("Browse", 1, true), "profession menu: your 2 (radio, picked one on), divider, 'Browse' title, 3 others: " .. radios)
  pm[5]:click()
  GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Blacksmithing" and GCA:IsBrowse(), "picked Blacksmithing: browse")
  check((pb.label._text or ""):find("(browse)", 1, true) and f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_BlackSmithing",
    "button says browse, portrait follows: " .. tostring(f.PortraitContainer.portrait._tex))
  menuOf(pb.drop)[2]:click(); GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Enchanting" and not GCA:IsBrowse(), "picked Enchanting (yours)")
  menuOf(pb.drop)[1]:click(); GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Leatherworking" and f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_LeatherWorking", "back to Leatherworking")
  GetProfessions = function() return 2 end
  GCA.UI:Refresh()
  local firstLabel, firstHeader = pb.label._text or "", GCA.UI.sugHeader._text or ""
  check(firstLabel:find("(browse)", 1, true) and firstHeader:find("browsing", 1, true),
    "a dropped profession shows as browse on the very first refresh, button and header alike: " .. firstLabel .. " / " .. firstHeader)
  GetProfessions = function() return 1, 2 end
  GCA:RefreshKnown()
  GCA.UI:Refresh()
  f:Hide()
  GetProfessions = function() return nil end
end
do
  print("== Window: suggestion rows (L1, L6, H5.1, H5.2, U3)")
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  local f = UIx.frame
  local cur = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local function show(d, c)
    UIx.current = c or cur
    UIx.sugList:SetData({ d })
    return UIx.sugList.rows[1]
  end
  local d = fakeSug()
  local b = show(d)
  check(b.title._SetWordWrap and b.title._SetWordWrap[1] == false and b.title._SetMaxLines and b.title._SetMaxLines[1] == 1
    and b.sub._SetWordWrap and b.sub._SetWordWrap[1] == false, "title and sub-line are single-line")
  check(b.iconBorder._atlas == "Professions-Slot-Frame" and b.frameArt == "atlas" and b.slotBg and b.qual._atlas == "Professions-Slot-bg"
    and b.iconBorder._SetVertexColor and b.iconBorder._SetVertexColor[2] == 1 and b.icon._w == 38,
    "card: 38 px icon in the reagent slot (Professions-Slot-bg + Professions-Slot-Frame tinted by quality)")
  check(plain(b.title._text) == "Hillman's Leather Vest" and not plain(b.title._text):find(":", 1, true),
    "title = the item name only, no 'Slot:' prefix: " .. plain(b.title._text))
  check(b.offer._shown and not b.offer.isIcon and b.offer._text == "Offer" and b.offer._w == 84
    and b.crafted._shown and b.craftedLabel == nil and b.gainAnchor == b.crafted,
    "card: online known craft: 'Offer' text button + crafted box (no label), gain left of the box (K1 had the whisper icon)")
  check(plain(b.gain._text) == "+12 pts" and plain(b.points._text) == "" and b.gain._SetTextColor and b.gain._SetTextColor[2] > 0.8
    and b._SetHeight[1] == 50 and b.alt == nil and b.treeV == nil, "card: 50 px, green '+12 pts' (no size line without a share); K6: no row shading, no tree lines")
  check(b.title._alpha == 1 and not b.dimmed, "wearable row not dimmed")
  local off = { key = "Bud Stone", online = false, prof = "Leatherworking", level = 39, class = "ROGUE" }
  b = show(d, off)
  check(not b.offer._shown and b.crafted._shown and b.crafted._points[1][2] == b, "offline: no Offer, crafted box moves to the right edge")
  check(not UIx.CanOffer(off, d) and UIx.CanOffer(cur, d), "CanOffer: online yes, offline no (craft)")
  check(not UIx.CanOffer(off, fakeSug({ kind = "enchant" })), "CanOffer: offline enchant no")
  captureTip()
  b._scripts.OnEnter(b)
  check(plainTip("item:4244"), "row tooltip = the plain item tooltip (no Offer/Shift/gain lines): " .. tipText())
  do
    local function fakeCompare()
      local t = New("GameTooltip")
      t.links, t.lines = {}, {}
      t.SetHyperlink = function(self, l) self.links[#self.links + 1] = l end
      t.SetText = function(self, s) self.lines[#self.lines + 1] = tostring(s) end
      t.AddLine = function(self, s) self.lines[#self.lines + 1] = tostring(s) end
      t.GetWidth = function() return 200 end
      t.SetOwner = function() end
      t:Hide()
      return t
    end
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    local ownerOf
    local savedShown, savedOwner, savedRight = GameTooltip.IsShown, GameTooltip.GetOwner, GameTooltip.GetRight
    GameTooltip.IsShown = function() return true end
    GameTooltip.GetOwner = function() return ownerOf end
    GameTooltip.GetRight = function() return 600 end
    local savedSetOwner = GameTooltip.SetOwner
    GameTooltip.SetOwner = function(self, o, ...) ownerOf = o; if savedSetOwner then return savedSetOwner(self, o, ...) end end
    local wb = show(fakeSug({ equipped = { name = "Old Vest", link = "item:2105", quality = 1 } }))
    wb._scripts.OnEnter(wb)
    local s1 = ShoppingTooltip1
    check(s1._shown and s1.links[1] == "item:2105" and plain(s1.lines[#s1.lines]) == "Equipped by Bud Stone" and not ShoppingTooltip2._shown,
      "hovering a craft: compare tooltip = the member's worn Old Vest, 'Equipped by Bud Stone': " .. table.concat(s1.lines, " | "))
    s1.links = {}
    UIx.FillCompare()
    check(s1.links[1] == "item:2105", "a later Blizzard compare is overwritten with the member's item")
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    wb = show(fakeSug({ equipped = nil, status = "empty-slot" }))
    wb._scripts.OnEnter(wb)
    check(ShoppingTooltip1._shown and #ShoppingTooltip1.links == 0 and ShoppingTooltip1.lines[1] == "Nothing equipped in this slot"
      and plain(ShoppingTooltip1.lines[2]) == "Equipped by Bud Stone", "empty slot: the compare tooltip says nothing is equipped")
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    local pairInfo = { name = "Sword + Shield", pair = { { name = "Sword", link = "item:1" }, { name = "Shield", link = "item:2" } } }
    wb = show(fakeSug({ equipped = pairInfo, bothHands = true }))
    wb._scripts.OnEnter(wb)
    check(ShoppingTooltip1.links[1] == "item:1" and ShoppingTooltip2.links[1] == "item:2" and ShoppingTooltip2._shown,
      "a two-hander: both worn hands in the two compare tooltips")
    UIx.HideCompare()
    ShoppingTooltip1, ShoppingTooltip2 = nil, nil
    GameTooltip.IsShown, GameTooltip.GetOwner, GameTooltip.GetRight, GameTooltip.SetOwner = savedShown, savedOwner, savedRight, savedSetOwner
    captureTip()
  end
  b = show(fakeSug({ known = false }), { key = "Bud Stone", online = true, prof = "Blacksmithing", browse = true, level = 39 })
  check(not b.offer._shown and not b.crafted._shown and b.gainAnchor == b and b.nl._shown and plain(b.nl.text._text) == "Trainer (skill 100)"
    and not plain(b.sub._text):find("Not learned", 1, true),
    "browse: no Offer, no box, gain at the right edge, the source button (trainer) starts the second line: " .. plain(b.nl.text._text))
  do
    local opened, savedTS, savedPrint = {}, C_TradeSkillUI, GCA.Print
    local said = {}
    GCA.Print = function(_, m) said[#said + 1] = tostring(m) end
    C_TradeSkillUI = setmetatable({ OpenRecipe = function(id) opened[#opened + 1] = id end }, { __index = savedTS })
    UIx.frame:Show()
    local kb = show(fakeSug())
    kb._scripts.OnClick(kb, "LeftButton")
    check(opened[1] == 3762 and UIx.frame._shown, "click on a known craft: C_TradeSkillUI.OpenRecipe(3762), our window stays open")
    ProfessionsFrame = New("Frame"); ProfessionsFrame:Hide()
    UIx.StepBehindProfessions()
    ProfessionsFrame:Show()
    local behind = UIx.frame._strata
    ProfessionsFrame:Hide()
    check(behind == "MEDIUM" and UIx.frame._strata == "HIGH",
      "while the profession window is open ours drops to MEDIUM (it can be on top), HIGH again when it closes: " .. tostring(behind))
    ProfessionsFrame = nil
    UIx.frame:Show()
    kb = show(fakeSug({ known = false }))
    kb._scripts.OnClick(kb, "LeftButton")
    check(#opened == 1 and said[#said] == ns.L.OPEN_NOT_KNOWN and UIx.frame._shown, "click on an unlearned craft: not opened, a chat line says why")
    InCombatLockdown = function() return true end
    kb = show(fakeSug())
    kb._scripts.OnClick(kb, "LeftButton")
    check(#opened == 1 and said[#said] == ns.L.OPEN_COMBAT, "in combat: not opened")
    InCombatLockdown = nil
    C_TradeSkillUI = { OpenRecipe = function() error("nope") end }
    kb._scripts.OnClick(kb, "LeftButton")
    check(said[#said] == ns.L.OPEN_FAIL and UIx.frame._shown, "OpenRecipe failing: no Lua error, a chat hint, window stays")
    C_TradeSkillUI, GCA.Print = savedTS, savedPrint
  end
  do
    local opened, linked, savedTS, savedLink = {}, {}, C_TradeSkillUI, HandleModifiedItemClick
    C_TradeSkillUI = { OpenRecipe = function(id) opened[#opened + 1] = id end }
    HandleModifiedItemClick = function(l) linked[#linked + 1] = l end
    UIx.frame:Show()
    local kb = show(fakeSug())
    kb._scripts.OnClick(kb, "RightButton")
    IsControlKeyDown = function() return true end
    kb._scripts.OnClick(kb, "LeftButton")
    local eb = show(fakeSug({ kind = "enchant", info = { name = "Enchant Chest", quality = 1, icon = "x" } }))
    eb._scripts.OnClick(eb, "LeftButton")
    IsControlKeyDown = nil
    C_TradeSkillUI, HandleModifiedItemClick = savedTS, savedLink
    check(#opened == 0 and #linked == 1 and linked[1] == "|Hitem:4244|h[Hillman's Leather Vest]|h",
      "right-click on a learned craft opens nothing; ctrl-click links it; ctrl-click on an enchant (no link) does nothing")
  end
  b = show(fakeSug({ future = true, wearAt = 42, levelsToGo = 3, info = { name = "Future Vest", quality = 3, icon = "x", minLevel = 42 } }))
  check(b.chip == nil and plain(b.sub._text):find("^from level 42 · 3 to go") and b.sub._text:find("|cfff0b44c", 1, true),
    "too-high-level row: the level tag is orange TEXT first on the second line (no chip box): " .. plain(b.sub._text))
  check(b.dimmed and b.title._alpha < 1 and b.icon._alpha < 1 and b.sub._alpha < 1, "row dimmed")
  check(b.qual._alpha == 0.55 and b.iconBorder._alpha == 0.55 and (b.offer._alpha or 1) == 1 and (b.crafted._alpha or 1) == 1,
    "quality square + icon border dimmed too; Offer and the crafted box not")
  b = show(fakeSug({ future = true, wearAt = 40, levelsToGo = 1 }))
  check(plain(b.sub._text):find("^from level 40 · 1 to go"), "level tag with 1 level to go: " .. plain(b.sub._text))
  b = show(fakeSug())
  check(b.qual._alpha == 1 and b.iconBorder._alpha == 1, "a wearable row on the same (pooled) frame is full alpha again")
  b = show(fakeSug({ equipped = { name = "Old Vest", quality = 2 } }))
  check(plain(b.sub._text) == "" and b.title._points[1][1] == "LEFT", "chest row: no 'replaces Old Vest', title centred (no sub-line)")
  b = show(fakeSug({ slot = 13, equipped = { name = "Old Charm", quality = 2 } }))
  check(plain(b.sub._text) == "replaces Old Charm" and plain(b.title._text) == "Hillman's Leather Vest (Trinket 1)" and b.title._points[1][1] == "TOPLEFT",
    "trinket row: '(Trinket 1)' + 'replaces Old Charm': " .. plain(b.sub._text))
  b = show(fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
    equipped = { name = "Minor Stamina" }, cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } } }))
  check(plain(b.sub._text) == "replaces Minor Stamina on Bracers", "enchant row keeps 'replaces X on Y': " .. plain(b.sub._text))
  captureTip(); show(fakeSug({ equipped = { name = "Old Vest", quality = 2 } }))._scripts.OnEnter(UIx.sugList.rows[1])
  check(plainTip("item:4244"), "no 'replaces' line in the item tooltip either")
  b = show(d)
  b.crafted:SetChecked(true); b.crafted._scripts.OnClick(b.crafted)
  local mark = GCA:CraftedMark("Bud Stone", "Leatherworking", 3762)
  check(mark and mark.item == 4244 and RavenquillExpeditionCraftDB.crafted[GCA.charKey]["Bud Stone"].Leatherworking[3762] == mark,
    "ticking stores the mark in SavedVariables (per character)")
  b = show(d)
  check(b.crafted._checked == true, "box shows the mark after a refresh")
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(H.tip[1] == "Crafted" and tipText():find("Crafted for Bud Stone", 1, true) and tipText():find("wearing it", 1, true),
    "box tooltip = the label as title + the explanation")
  b.crafted:SetChecked(false); b.crafted._scripts.OnClick(b.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) == nil and RavenquillExpeditionCraftDB.crafted[GCA.charKey]["Bud Stone"] == nil,
    "unticking removes the mark (and empty tables)")
  b = show(fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
    cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } } }))
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(H.tip[1] == "Enchanted", "enchant row: box tooltip title 'Enchanted'")
  check(UIx.OfferText("Leatherworking", d, "Bud Stone"):find("^Hi Bud! I'm a leatherworker and could craft you |Hitem:4244"),
    "whisper: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))

  print("== Window: K6 Filter dropdowns (L5 toggles), whisper editor (U2), help (U6)")
  local fb, mf = UIx.filterButton, UIx.memberFilter
  check(UIx.optionsButton == nil and UIx.optionsPopup == nil and fb.native and mf.native and fb._template == "WowStyle1FilterDropdownTemplate"
    and mf._template == "WowStyle1FilterDropdownTemplate" and fb._w == 90 and fb._h == 18 and UIx.filterPopup == nil,
    "no Options button/popup; two native Filter dropdowns (needs bar + member list), 90x18 as the recipe list's")
  check(mf._points[1][1] == "TOPRIGHT" and mf._points[1][2] == UIx.memberInset and mf._points[1][4] == -8 and mf._points[1][5] == -9,
    "member list Filter at TOPRIGHT -8,-9 of its panel (the recipe list's own spot)")
  check(UIx.survival._parent == f.content and not UIx.survival._shown and UIx.helpButton == nil,
    "the bottom slider is hidden with the native Filter menu; no '?' help button")
  local op = menuOf(fb)
  check(#op == 8 and op[1].kind == "check" and op[5].kind == "check" and op[6].kind == "divider" and op[7].kind == "button"
    and #op[7].sub == 5 and op[8].kind == "button",
    "filter menu: 4 settings + offline members, divider, leveling bonus submenu (5 values), edit whisper (" .. #op .. ")")
  check(menuTexts(op) == "Show missing recipes|Look ahead 5 levels|Read gear automatically|Guild sync|Include offline members (0)|Leveling bonus (Stamina/Spirit): 50%|Edit whisper text…",
    "menu labels: " .. menuTexts(op))
  check(op[1].tip ~= nil and op[7].tip ~= nil and op[8].tip ~= nil, "every entry has its tooltip")
  check(op[7].sub[3]:on() and not op[7].sub[4]:on(), "50 % is the selected bonus")
  op[7].sub[4]:click()
  check(math.abs(GCA.db.settings.survival - 0.75) < 1e-9 and menuOf(fb)[7].sub[4]:on(), "picking 75 % sets the bonus")
  menuOf(fb)[7].sub[3]:click()
  check(math.abs(GCA.db.settings.survival - 0.5) < 1e-9, "...and back to 50 %")
  local before = GCA.db.settings.showUnlearned
  op[1]:click()
  check(GCA.db.settings.showUnlearned == not before and menuOf(fb)[1]:on() == GCA.db.settings.showUnlearned and (fb._generated or 0) > 0,
    "entry 1 toggles showUnlearned, the check follows, the open menu is regenerated")
  menuOf(fb)[1]:click()
  check(GCA.db.settings.showUnlearned == before, "...and back")
  local la = GCA.db.settings.lookahead
  menuOf(fb)[2]:click()
  check(GCA.db.settings.lookahead == not la, "entry 2 toggles lookahead")
  menuOf(fb)[2]:click()
  local ai = GCA.db.settings.autoInspect
  menuOf(mf)[3]:click(); check(ai == true and GCA.db.settings.autoInspect == false, "entry 3 toggles autoInspect (default on; the member list's Filter too)")
  menuOf(mf)[3]:click()
  menuOf(fb)[8]:click()
  local ed = UIx.whisperEditor
  check(ed and ed._shown, "last entry opens the whisper editor")
  check(ed.craft._text == UIx.DefaultTemplate("craft") and ed.enchant._text == UIx.DefaultTemplate("enchant"), "editor starts with the defaults")
  ed.craft:SetText("Yo {name}, {item} for your {slot}? {nope}")
  ed.saveBtn._scripts.OnClick(ed.saveBtn)
  check(GCA.db.settings.whisperCraft == "Yo {name}, {item} for your {slot}? {nope}" and GCA.db.settings.whisperEnchant == nil and not ed._shown,
    "Save stores the edited craft text only (unchanged enchant text stays default = nil)")
  check(UIx.OfferText("Leatherworking", d, "Bud Stone") == "Yo Bud, |Hitem:4244|h[Hillman's Leather Vest]|h for your Chest? {nope}",
    "custom template filled, unknown placeholder kept: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))
  GCA.UI:OpenWhisperEditor()
  check(ed._shown and ed.craft._text == "Yo {name}, {item} for your {slot}? {nope}", "/gca whisper reopens it with the saved text")
  ed.resetBtn._scripts.OnClick(ed.resetBtn)
  check(GCA.db.settings.whisperCraft == nil and ed.craft._text == UIx.DefaultTemplate("craft"), "Reset to default clears the saved text")
  ed.closeBtn._scripts.OnClick(ed.closeBtn)
  captureTip(); UIx.memberSearch._scripts.OnEnter(UIx.memberSearch)
  check(UIx.memberHeader == nil and tipText():find("Search member", 1, true) and tipText():find("by name", 1, true),
    "a member search box on top of the list (replaces the column header / badge legend)")
  local mr = UIx.memberList.rows[1]
  check(mr and mr.name._SetWordWrap and mr.name._SetWordWrap[1] == false, "member rows single-line")
  check(UIx.survival.label._text == "Leveling bonus (Stamina/Spirit): 50%", "slider renamed: " .. tostring(UIx.survival.label._text))
  f:Hide()
end

do
  print("== Window: German client (H4)")
  ns.locale = "deDE"
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  check(UIx.filterButton.native and UIx.optionsButton == nil, "German window has the native Filter dropdown (its text is the template's own)")
  check(UIx.survival.label._text == "Levelbonus (Ausdauer/Willenskraft): 50%", "slider in German (our fallback words): " .. tostring(UIx.survival.label._text))
  check(plain(UIx.subText._text):find("^Stufe 36 "), "sub-line uses our 'Stufe' when LEVEL is missing: " .. plain(UIx.subText._text))
  LEVEL, SPELL_STAT3_NAME = "StufeCL", "AusdauerCL"
  UIx:Refresh()
  check(plain(UIx.subText._text):find("^StufeCL 36") and UIx.survival.label._text:find("AusdauerCL", 1, true), "client globals win where they exist")
  LEVEL, SPELL_STAT3_NAME = nil, nil
  local d = fakeSug()
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39 }
  UIx.sugList:SetData({ d })
  local b = UIx.sugList.rows[1]
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(H.tip[1] == "Hergestellt" and UIx.WearableText({ wearAt = 42, levelsToGo = 3 }) == "tragbar ab Stufe 42 (in 3 Stufen)", "row texts in German")
  check(UIx.SpecialisationText("Engineering", "Gnomish Goggles"):find("Gnomen-Ingenieurskunst", 1, true)
    and UIx.SpecialisationText("Engineering", "Goblin Rocket Boots"):find("Goblin-Ingenieurskunst", 1, true),
    "M-1: specialisation word in German: " .. UIx.SpecialisationText("Engineering", "Gnomish Goggles"))
  check(UIx.OfferText("Leatherworking", d, "Bud Stone") == "Hallo Bud! Ich bin Lederverarbeiter und könnte dir |Hitem:4244|h[Hillman's Leather Vest]|h herstellen – das wäre eine Verbesserung (Chest). Interesse?",
    "German whisper: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
end

do
  print("== Window: slot sections (plan I)")
  GCA.UI:Toggle(); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local before = UIx.errorCount
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local s1, s2 = fakeSug(), fakeSug({ info = { name = "Second Vest", quality = 2, icon = "x", minLevel = 20 }, pct = 0.05, sortPct = 5, extra = true })
  local ring = fakeSug({ slot = 12, info = { name = "Craft Ring", quality = 2, icon = "x", minLevel = 20 }, equipped = { name = "Ring B", quality = 2 } })
  local list = fakeSections({ [5] = { s1, s2 }, [11] = { ring } }, { [5] = 5 })
  local data = UIx.SectionRows(list)
  local shape = {}
  for i, d in ipairs(data) do shape[i] = d.rowKind == "fold" and ("F" .. #d.secs) or (d.rowKind and ("H" .. d.sec.key)) or d.info.name end
  check(#data == 6 and table.concat(shape, ",") == "H5,Hillman's Leather Vest,Second Vest,H11,Craft Ring,F13",
    "SectionRows: header + its rows per section with an upgrade, then ONE folded line for the 13 others: " .. table.concat(shape, ","))
  check(#UIx.SectionRows(fakeSections({})) == 0 and #UIx.SectionRows({}) == 0, "no suggestion at all: empty list (the empty-state text explains why)")
  local sl = UIx.sugList
  sl:SetData(data)
  local H = sl.pools.section
  local FP = sl.pools.fold
  check(H and #H == 2 and FP and #FP == 1 and sl.rows[1].data == s1 and sl.rows[3].data == ring and (sl.rows[4] == nil or not sl.rows[4]._shown),
    "row kinds: 2 section rows + 1 folded line (own pools) + 3 suggestion rows")
  local foldH = sl.rowY[6][2]
  check(sl.rows[1]._points[1][3] == -56 and sl.rows[2]._points[1][3] == -108 and H[2]._points[1][3] == -160 and FP[1]._points[1][3] == -268,
    "rows stacked by kind height (worn row 56, card 52, then the folded box; K4 had a 30 px header)")
  check(sl.contentH == 2 * 56 + 3 * 52 + foldH and foldH >= 30, "content height = 2 worn rows + 3 cards + the folded box (" .. tostring(sl.contentH) .. ", box " .. foldH .. ")")
  local h = H[1]
  check(h.name == nil and h.label == nil and plain(h.wornName._text) == "Worn Vest" and h.wornName._text:find("^|cff")
    and h.wornName._points[1][1] == "LEFT" and h.wornName._points[1][2] == h.box.qual and h.wornName._points[1][4] == 12
    and h.count._text == "2 upgrades" and not h.empty and h.box.bg == nil and h.box.edges == nil and h.box.line._SetColorTexture and h.box._points[1][5] == -6,
    "chest worn row: icon + the worn name only (centred, 12 px gap; no slot name, no 'Equipped'), '2 upgrades' on the right, a box 6 px below the row top: " .. plain(h.wornName._text))
  check(h.box.icon._tex == 134 and h.box.icon._w == 34 and h.box.iconBorder._SetVertexColor
    and h.wornName._SetWordWrap[1] == false, "worn row: 34 px item icon in its quality frame, single-line texts")
  local r = H[2]
  check(r.name == nil and plain(r.wornName._text) == "Ring A  ·  Ring B" and r.count._text == "1 upgrade",
    "rings worn row: both rings named, '1 upgrade': " .. plain(r.wornName._text))
  local c1, c2, c3 = sl.rows[1], sl.rows[2], sl.rows[3]
  check(c1.treeV == nil and c1.treeH == nil and c1.alt == nil and UIx.TREE_X == nil and c1.qual._points[1][4] == UIx.CARD_INDENT + 4 and UIx.CARD_INDENT == 16,
    "cards indented 16 px under their worn row, no tree lines / row shading")
  local g = FP[1]
  check(g.text._text == "No craftable upgrade: Head, Neck, Shoulder, Back, Wrist, Hands, Waist, Legs, Feet, Trinkets (not loaded), Main Hand, Off Hand, Ranged"
    and g.text._SetWordWrap and g.text._SetWordWrap[1] == true and g.text._SetMaxLines == nil and g.text._SetWidth[1] == UIx.sugList.viewW - 20 and g.edges == nil and g.line ~= nil,
    "one folded, wrapping line names the 13 slots (unloaded trinket marked): " .. tostring(g.text._text))
  check(not (g.text._text or ""):find("–", 1, true), "no '– no upgrade –' lines any more")
  local gt = g
  local b = sl.rows[1]
  check(b.offer._shown and b.crafted._shown and plain(b.title._text) == "Hillman's Leather Vest", "suggestion rows inside a section (K1 title)")
  check(plain(sl.rows[3].title._text) == "Craft Ring (Ring 2)" and plain(sl.rows[3].sub._text):find("replaces", 1, true)
    and not plain(b.sub._text):find("replaces", 1, true),
    "ring row keeps a disambiguator '(Ring 2)' and 'replaces …'; a normal slot's row doesn't repeat the worn item: " .. plain(sl.rows[3].title._text))
  captureTip(); h._scripts.OnEnter(h)
  check(plainTip(), "worn row (section header) tooltip = the worn item's plain tooltip: " .. tipText())
  captureTip(); g._scripts.OnEnter(g)
  check(tipText():find("Slots without an upgrade", 1, true) and tipText():find("Wrist: Bracers", 1, true) and tipText():find("Head: nothing equipped", 1, true)
    and tipText():find("Nothing in this list beats", 1, true), "folded line tooltip lists each slot's worn item and explains")
  captureTip(); gt._scripts.OnEnter(gt)
  check(tipText():find("didn't load", 1, true), "unloaded trinket: tooltip says it wasn't compared")
  captureTip(); r._scripts.OnEnter(r)
  check(tipText():find("Rings", 1, true) and tipText():find("Ring 1: Ring A", 1, true) and tipText():find("Ring 2: Ring B", 1, true) or tipText():find("Finger", 1, true),
    "rings worn row tooltip lists both rings")
  local clicked
  HandleModifiedItemClick = function(l) clicked = l end
  h._scripts.OnClick(h)
  check(clicked == nil, "a plain click on the equipped item does nothing")
  local savedShift = IsShiftKeyDown
  IsShiftKeyDown = function() return true end
  h._scripts.OnClick(h)
  IsShiftKeyDown = savedShift
  check(clicked == "|Hitem:4244|h[Worn Vest]|h", "worn row Shift-click links the real hyperlink")
  local saveData = sl.data
  sl:SetData(UIx.SectionRows(fakeSections({ [1] = { fakeSug({ slot = 1 }), fakeSug({ slot = 1 }), fakeSug({ slot = 1 }) },
    [3] = { fakeSug({ slot = 3 }), fakeSug({ slot = 3 }), fakeSug({ slot = 3 }) }, [5] = { fakeSug(), fakeSug(), fakeSug() },
    [7] = { fakeSug({ slot = 7 }), fakeSug({ slot = 7 }), fakeSug({ slot = 7 }) } })))
  local viewH = sl.viewH
  check(sl.contentH > viewH and sl:ScrollTo(1e6) == sl.contentH - viewH and sl:Offset() == sl.contentH - viewH and sl:ScrollTo(-5) == 0,
    "ScrollTo clamped to [0, content - view]")
  sl:SetData(saveData)
  check(data[1].anchor == nil, "section entries carry no jump anchor any more")
  local origML = GCA.GetMemberList
  local long = fakeSections({ [1] = { fakeSug({ slot = 1 }), fakeSug({ slot = 1 }), fakeSug({ slot = 1 }) },
    [5] = { fakeSug(), fakeSug(), fakeSug() }, [9] = { fakeSug({ slot = 9 }), fakeSug({ slot = 9 }), fakeSug({ slot = 9 }) },
    [10] = { fakeSug({ slot = 10 }), fakeSug({ slot = 10 }), fakeSug({ slot = 10 }) } })
  GCA.GetMemberList = function()
    return { { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", state = "ok",
      member = { items = {}, time = time(), source = "inspect" }, suggestions = long, best = long[1], knownCount = 1 } }
  end
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  GCA.db.settings.memberView = "list"
  UIx:Refresh()
  sl:ScrollTo(100)
  UIx.listKey = "Someone Else|Leatherworking"
  UIx:Refresh()
  check(sl.contentH > sl.viewH + 100 and sl:Offset() == 0 and UIx.listKey == "Bud Stone|Leatherworking",
    "member/profession change scrolls the list to the top")
  sl:ScrollTo(50)
  UIx:Refresh()
  check(sl:Offset() == 50, "a refresh of the same member keeps the scroll position")
  GCA.db.settings.memberView = "sheet"
  GCA.GetMemberList = origML
  sl:SetData(UIx.SectionRows(fakeSections({ [9] = { fakeSug({ slot = 9 }) } })))
  local shownH = 0
  for _, x in ipairs(H) do if x._shown then shownH = shownH + 1 end end
  check(shownH == 1 and FP[1]._shown and sl.rows[1]._shown and not sl.rows[2]._shown and not sl.rows[3]._shown, "pools reused; unused rows hidden")
  check(UIx.errorCount == before, "no error reported")
  HandleModifiedItemClick = function() end

  print("== Window: slot sections in German (plan I)")
  ns.locale = "deDE"
  f:Hide()
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  UIx.sugList:SetData(UIx.SectionRows(fakeSections({ [5] = { fakeSug() } })))
  local byKey = {}
  for _, x in ipairs(UIx.sugList.pools.section) do byKey[x.data.sec.key] = x end
  local gf = UIx.sugList.pools.fold[1]
  check((gf.text._text or ""):find("^Keine herstellbare Verbesserung: Head, ") and gf.text._text:find("Ringe", 1, true)
    and gf.text._text:find("Schmuckstücke (nicht geladen)", 1, true), "German folded line: " .. tostring(gf.text._text))
  captureTip(); gf._scripts.OnEnter(gf)
  check(tipText():find("Plätze ohne Verbesserung", 1, true) and tipText():find("nichts angelegt", 1, true), "German folded-line tooltip")
  captureTip(); byKey[5]._scripts.OnEnter(byKey[5])
  check(plainTip(), "German header tooltip = the plain item tooltip: " .. tipText():gsub("\n", " / "))
  check(UIx.errorCount == before, "no error reported (German)")
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
end

do
  print("== Window: resizable (plan J2)")
  GCA.db.settings.window = nil
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local before = UIx.errorCount
  local g = UIx.resizeGrip
  check(g and f._resizable == true and UIx.boundsVia == "SetResizeBounds" and f._bounds[1] == 840 and f._bounds[2] == 560
    and f._bounds[3] == 1920 and f._bounds[4] == 1080, "grip created; SetResizable(true); SetResizeBounds(840, 560, screen)")
  check(g._SetNormalTexture[1] == "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" and g._SetPushedTexture[1]:find("Down$")
    and g._level > f.content._level and g._level > f.NineSlice._level, "grip: size-grabber art, above the content and the border")
  check(f._w == 980 and f._h == 640 and UIx.layoutW == 980 and UIx.layoutH == 640, "default 980x640, laid out for it")
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  UIx.sugList:SetData(UIx.SectionRows(longList()))
  UIx.memberList:SetData(UIx.MemberRows(manyMembers()))

  local function drag(w, h, steps)
    g._scripts.OnMouseDown(g, "LeftButton")
    local n0 = UIx.layoutCount
    for i = 1, steps or 1 do f:SetSize(f._w + (w - f._w) * i / (steps or 1), f._h + (h - f._h) * i / (steps or 1)) end
    local during = UIx.layoutCount - n0
    advance(0.06)
    local afterTimer = UIx.layoutCount - n0
    g._scripts.OnMouseUp(g, "LeftButton")
    return during, afterTimer
  end
  local left0, top0 = f:GetLeft(), f:GetTop()
  g._scripts.OnMouseDown(g, "LeftButton")
  check(f.isSizing and f._sizingFrom == "BOTTOMRIGHT" and f._points[1][1] == "TOPLEFT" and f._points[1][4] == left0 and f._points[1][5] == top0,
    "mouse down: StartSizing(\"BOTTOMRIGHT\") with the window pinned by its top-left corner (" .. left0 .. ", " .. top0 .. ")")
  g._scripts.OnMouseUp(g, "LeftButton")
  check(not f.isSizing, "mouse up: sizing stopped")
  local during, afterTimer = drag(1400, 900, 10)
  check(during == 0 and afterTimer == 1, "10 size changes while dragging -> no relayout until the 50 ms timer, then exactly one (" .. during .. "/" .. afterTimer .. ")")

  local vis = {}
  for _, sz in ipairs({ { 840, 560, "minimum" }, { 980, 640, "default" }, { 1600, 1000, "large" } }) do
    drag(sz[1], sz[2], 3)
    check(f._w == sz[1] and f._h == sz[2] and UIx.layoutW == sz[1] and UIx.layoutH == sz[2], sz[3] .. ": " .. sz[1] .. "x" .. sz[2] .. " laid out")
    layoutChecks(UIx, f, sz[3] .. " " .. sz[1] .. "x" .. sz[2])
    UIx.sugList:ScrollTo(0); UIx.memberList:ScrollTo(0)
    vis[#vis + 1] = { UIx.sugList:VisibleRows(), UIx.memberList:VisibleRows(), UIx.sugList.viewH, UIx.memberList.viewH }
  end
  check(vis[1][3] == 366 and vis[1][4] == 419, "minimum: list views 366 px (inside the member detail panel) and 419 px (" .. vis[1][3] .. ", " .. vis[1][4] .. ")")
  check(vis[1][1] < vis[2][1] and vis[2][1] < vis[3][1] and vis[1][2] < vis[2][2] and vis[2][2] < vis[3][2],
    string.format("visible rows grow with the height: suggestions %d/%d/%d, members %d/%d/%d", vis[1][1], vis[2][1], vis[3][1], vis[1][2], vis[2][2], vis[3][2]))
  check(vis[1][2] == 16 and vis[3][2] == 34, "25 px recipe-list member rows visible (incl. the Online header): 16 at 560 high, 34 at 1000 high (K6: 11/23 with 34 px rows) ("
    .. vis[1][2] .. "/" .. vis[3][2] .. ")")
  local hdr, card, fold = UIx.sugList.pools.section[1], UIx.sugList.rows[1], UIx.sugList.pools.fold[1]
  local function lineW() return hdr.textW end
  local wide = { lineW(), card.textW, fold.text._SetWidth[1] }
  drag(840, 560)
  local narrow = { lineW(), card.textW, fold.text._SetWidth[1] }
  check(wide[1] - narrow[1] == 1600 - 840 and wide[2] - narrow[2] == 1600 - 840 and wide[3] - narrow[3] == 1600 - 840,
    "worn-row text, card texts and the folded box grow with the width (" .. narrow[1] .. "/" .. narrow[2] .. "/" .. narrow[3]
    .. " -> " .. wide[1] .. "/" .. wide[2] .. "/" .. wide[3] .. ")")
  UIx.sugList:ScrollTo(1e6)
  local endAt = UIx.sugList.scrolledTo
  drag(840, 1000)
  check(UIx.sugList.scrolledTo == math.max(0, UIx.sugList.contentH - UIx.sugList.viewH) and UIx.sugList.scrolledTo < endAt,
    "taller window: scroll offset clamped to the new range (" .. endAt .. " -> " .. UIx.sugList.scrolledTo .. ")")

  drag(1200, 800)
  local win = GCA.db.settings.window
  check(win and win.w == 1200 and win.h == 800 and win.left == left0 and win.top == top0, "size and position saved after the drag")
  check(f._SetUserPlaced and f._SetUserPlaced[1] == false, "client layout cache not used (SetUserPlaced(false)): SavedVariables own the geometry")
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 900)
  UIx.dragBar._scripts.OnMouseDown(UIx.dragBar, "LeftButton")
  UIx.dragBar._scripts.OnMouseUp(UIx.dragBar, "LeftButton")
  check(GCA.db.settings.window.left == 100 and GCA.db.settings.window.top == 900 and GCA.db.settings.window.w == 1200, "moving saves the position")
  f:Hide()
  local function reopen()
    GCA.UI.frame = nil
    GCA.UI:Toggle(); advance(1)
    return GCA.UI.frame
  end
  f = reopen()
  local p = f._points[1]
  check(f._w == 1200 and f._h == 800 and p[1] == "TOPLEFT" and p[2] == UIParent and p[3] == "BOTTOMLEFT" and p[4] == 100 and p[5] == 900
    and GCA.UI.layoutW == 1200, "reopened (new session): 1200x800 at (100, 900), laid out")
  GCA.db.settings.window = { w = 5000, h = 3000, left = -500, top = 5000 }
  f:Hide(); f = reopen()
  check(f._w == 1920 and f._h == 1080 and f._points[1][4] == 0 and f._points[1][5] == 1080, "too big / off screen -> screen size at (0, 1080)")
  GCA.db.settings.window = { w = 100, h = 100, left = 1800, top = 50 }
  f:Hide(); f = reopen()
  check(f._w == 840 and f._h == 560 and f._points[1][4] == 1920 - 840 and f._points[1][5] == 560, "too small -> 840x560, pushed back on screen")
  GCA.db.settings.window = "junk"
  f:Hide(); f = reopen()
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "corrupt saved value -> default, centred")
  GCA.db.settings.window = { w = 0 / 0, h = "x", left = 0 / 0, top = 10 }
  f:Hide(); f = reopen()
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "NaN / strings -> default, centred")
  UIx = GCA.UI
  local gg = UIx.resizeGrip
  gg._scripts.OnMouseDown(gg, "LeftButton"); f:SetSize(1500, 900); gg._scripts.OnMouseUp(gg, "LeftButton")
  gg._scripts.OnMouseUp(gg, "RightButton")
  check(f._w == 980 and f._h == 640 and GCA.db.settings.window.w == 980 and UIx.layoutW == 980, "right-click on the grip: back to 980x640, saved")
  gg._scripts.OnMouseDown(gg, "LeftButton"); f:SetSize(1111, 777)
  f:Hide()
  check(not f.isSizing and GCA.db.settings.window.w == 1111 and GCA.db.settings.window.h == 777 and UIx.layoutW == 1111, "hidden while sizing: stopped, laid out, saved")
  advance(1)
  GCA.UI:Toggle(); advance(1)
  captureTip(); gg._scripts.OnEnter(gg)
  check(tipText():find("Resize", 1, true) and tipText():find("Right-click: back to the default size", 1, true), "grip tooltip")
  check(UIx.errorCount == before, "no error reported (J2)")
  f:Hide()

  print("== Window: resize on older / missing APIs (J2)")
  local srb = Frame.SetResizeBounds
  Frame.SetResizeBounds = nil
  local minCalls = {}
  Frame.SetMinResize = function(self, w, h) minCalls[#minCalls + 1] = { w, h } end
  f = reopen()
  check(GCA.UI.boundsVia == "SetMinResize" and minCalls[1] and minCalls[1][1] == 840 and minCalls[1][2] == 560, "no SetResizeBounds: SetMinResize(840, 560)")
  f:Hide()
  Frame.SetMinResize = nil
  f = reopen()
  local g3 = GCA.UI.resizeGrip
  check(g3 and GCA.UI.boundsVia == nil, "no bounds API at all: grip still there")
  g3._scripts.OnMouseDown(g3, "LeftButton"); f:SetSize(500, 300); g3._scripts.OnMouseUp(g3, "LeftButton")
  check(f._w == 840 and f._h == 560 and GCA.UI.layoutW == 840 and GCA.db.settings.window.w == 840, "...a drag below the minimum is clamped to 840x560 on release")
  g3._scripts.OnMouseDown(g3, "LeftButton"); f:SetSize(3000, 2000); g3._scripts.OnMouseUp(g3, "LeftButton")
  check(f._w == 1920 and f._h == 1080, "...and above the screen to the screen size")
  f:Hide()
  Frame.SetResizeBounds = srb
  local sr, ss = Frame.SetResizable, Frame.StartSizing
  Frame.SetResizable, Frame.StartSizing = nil, nil
  local errs = GCA.UI.errorCount
  f = reopen()
  check(f._shown and GCA.UI.resizeGrip == nil and GCA.UI.errorCount == errs and GCA.UI.layoutW == f._w, "no SetResizable/StartSizing: no grip, window works, no error")
  f:Hide()
  Frame.SetResizable, Frame.StartSizing = sr, ss
  GCA.db.settings.window = nil

  print("== Window: resize grip in German (J2)")
  ns.locale = "deDE"
  f = reopen()
  local g4 = GCA.UI.resizeGrip
  captureTip(); g4._scripts.OnEnter(g4)
  check(tipText():find("Größe ändern", 1, true) and tipText():find("Rechtsklick", 1, true), "German grip tooltip")
  f:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
  GCA.db.settings.window = nil
end

H.finish(true)
