local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local GCA, fakeSug, fakeSections, check, advance = H.GCA, H.fakeSug, H.fakeSections, H.check, H.advance
local plain, menuOf, captureTip, plainTip, tipText = H.plain, H.menuOf, H.captureTip, H.plainTip, H.tipText
local Frame, ATLASES, ns, menuTexts, layoutChecks = H.Frame, H.ATLASES, H.ns, H.menuTexts, H.layoutChecks
H.lateGlobals()
H.templateMode = "fail"

do
  print("== Core GuildNeeds (order, grouping, cache)")
  local savedTM, savedBrowse = H.templateMode, GCA.IsBrowse
  H.templateMode = "ok"
  GCA.IsBrowse = function() return false end
  local UIx = GCA.UI
  local bud = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {} } }
  local olga = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {} } }
  local me = { key = "Me Stone", isSelf = true, online = true, class = "ROGUE", level = 36, prof = "Leatherworking", member = { items = {} } }
  local nobody = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20 }
  local b1 = fakeSug()
  local bx = fakeSug({ extra = true, info = { name = "Extra Vest", quality = 2, icon = "x", minLevel = 20 }, sortPct = 99 })
  local b2 = fakeSug({ slot = 12, future = true, wearAt = 42, levelsToGo = 3, sortPct = 50,
    info = { name = "Craft Ring", quality = 3, icon = "x", minLevel = 42, link = "|Hitem:5|h[Craft Ring]|h" } })
  local o1 = fakeSug({ slot = 9, sortPct = 30, info = { name = "Olga Bracers", quality = 2, icon = "x", minLevel = 20 } })
  local m1 = fakeSug({ sortPct = 80 })
  bud.suggestions = fakeSections({ [5] = { b1, bx }, [11] = { b2 } })
  olga.suggestions = fakeSections({ [9] = { o1 } })
  me.suggestions = fakeSections({ [5] = { m1 } })
  local entries = { me, bud, olga, nobody }
  GCA.needsCache = nil
  local n0 = GCA.needsBuilds or 0
  local needs = GCA:GuildNeeds(entries)
  local function names(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.member.key .. ":" .. r.sug.info.name end return table.concat(t, ",") end
  check(names(needs.online) == "Bud Stone:Hillman's Leather Vest,Bud Stone:Craft Ring" and names(needs.offline) == "Olga Field:Olga Bracers",
    "GuildNeeds: online rows by SuggestionOrder (wearable 12% before the look-ahead 50%), offline apart; no extras, not you, nothing without gear: "
    .. names(needs.online) .. " | " .. names(needs.offline))
  check(needs.online[1].rowKind == "need" and needs.online[1].sug == b1 and needs.online[1].member == bud, "rows carry the suggestion and the member entry")
  local b3 = fakeSug({ sortPct = 40, info = { name = "Big Vest", quality = 2, icon = "x", minLevel = 20 } })
  local cara = { key = "Cara Field", online = true, class = "DRUID", level = 30, prof = "Leatherworking", member = { items = {} },
    suggestions = fakeSections({ [5] = { b3 } }) }
  GCA.needsCache = nil
  local n2 = GCA:GuildNeeds({ bud, cara })
  check(names(n2.online) == "Cara Field:Big Vest,Bud Stone:Hillman's Leather Vest,Bud Stone:Craft Ring", "biggest gain first across members: " .. names(n2.online))
  local nb = GCA.needsBuilds
  check(GCA:GuildNeeds({ bud, cara }) == n2 and GCA.needsBuilds == nb, "cached: same entries give the same rows without a rebuild")
  local cara2 = {}
  for k, v in pairs(cara) do cara2[k] = v end
  cara2.online = false
  local n3 = GCA:GuildNeeds({ bud, cara2 })
  check(n3 ~= n2 and GCA.needsBuilds == nb + 1 and names(n3.offline) == "Cara Field:Big Vest", "an online change rebuilds (Cara now offline)")
  GCA:InvalidateScores()
  local n4 = GCA:GuildNeeds({ bud, cara2 })
  check(n4 ~= n3 and GCA.needsBuilds == nb + 2, "InvalidateScores (new sugCache) rebuilds")
  advance(1)

  print("== GuildNeedsByCraft + NeedsRows (grouped by craft, search, offline box)")
  local function sg(id, over)
    over = over or {}
    over.cand = { spellID = id, itemID = id, recipe = { skill = 100, src = "trainer", r = {} } }
    return fakeSug(over)
  end
  local function vinfo() return { name = "Vest", quality = 2, icon = "x", minLevel = 20, link = "|Hitem:9001|h[Vest]|h" } end
  K5 = {}
  K5.vestA = sg(9001, { sortPct = 12, pct = 0.12, info = vinfo() })
  K5.vestB = sg(9001, { sortPct = 38, pct = 0.38, info = vinfo(), equipped = { name = "Old Vest", quality = 2 } })
  K5.vestO = sg(9001, { sortPct = 60, pct = 0.6, info = vinfo() })
  K5.belt = sg(9002, { slot = 6, sortPct = 20, pct = 0.2, info = { name = "Belt", quality = 2, icon = "x", minLevel = 20, link = "|Hitem:9002|h[Belt]|h" } })
  K5.ringF = sg(9003, { slot = 11, future = true, wearAt = 42, levelsToGo = 3, sortPct = 90, pct = 0.9,
    info = { name = "Future Ring", quality = 3, icon = "x", minLevel = 42, link = "|Hitem:9003|h[Future Ring]|h" } })
  K5.ringF2 = sg(9003, { slot = 12, future = true, wearAt = 42, levelsToGo = 3, sortPct = 80, pct = 0.8, extra = nil,
    info = { name = "Future Ring", quality = 3, icon = "x", minLevel = 42 } })
  K5.mine = sg(9004, { sortPct = 99, pct = 0.99, info = { name = "My Gloves", quality = 2, icon = "x", minLevel = 20 } })
  K5.bud = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {}, time = time(), source = "inspect" },
    suggestions = fakeSections({ [5] = { K5.vestA }, [6] = { K5.belt }, [11] = { K5.ringF, K5.ringF2 } }), best = K5.belt, knownCount = 3, state = "ok" }
  K5.cara = { key = "Cara Field", online = true, class = "DRUID", level = 30, prof = "Leatherworking", member = { items = {}, time = time(), source = "inspect" },
    suggestions = fakeSections({ [5] = { K5.vestB } }), best = K5.vestB, knownCount = 1, state = "ok" }
  K5.olga = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {}, time = time(), source = "relay" },
    suggestions = fakeSections({ [5] = { K5.vestO } }), best = K5.vestO, knownCount = 1, state = "ok" }
  K5.me = { key = "Me Stone", isSelf = true, online = true, class = "ROGUE", level = 36, prof = "Leatherworking", member = { items = {} },
    suggestions = fakeSections({ [10] = { K5.mine } }), best = K5.mine, knownCount = 1, state = "ok" }
  K5.nobody = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20, prof = "Leatherworking" }
  K5.list = { K5.me, K5.bud, K5.cara, K5.olga, K5.nobody }
  GCA.needsCache = nil
  local nb0 = GCA.needsBuilds or 0
  local crafts, nd = GCA:GuildNeedsByCraft(K5.list)
  local function gnames(gs) local t = {} for i, g in ipairs(gs) do t[i] = g.sug.info.name .. "(" .. #g.rows .. ")" end return table.concat(t, ",") end
  local function rnames(g) local t = {} for i, r in ipairs(g.rows) do t[i] = r.member.key end return table.concat(t, ",") end
  check(crafts == nd.crafts and gnames(crafts) == "Vest(2),Belt(1),Future Ring(1)" and crafts[1].rowKind == "craft",
    "one group per craft, online members only by default, best gain first, the look-ahead-only craft last (90% but too high level): " .. gnames(crafts))
  check(rnames(crafts[1]) == "Cara Field,Bud Stone" and crafts[1].best.sug == K5.vestB and crafts[1].sug == K5.vestB and not crafts[1].future,
    "a craft's members best first (Cara +38% before Bud +12%); its best row / suggestion = Cara's")
  check(#crafts[3].rows == 1 and crafts[3].rows[1].sug == K5.ringF and crafts[3].future, "one row per member and craft (the better ring of Bud's two); look-ahead group flagged future")
  local all = GCA:GuildNeedsByCraft(K5.list, true)
  check(all == nd.craftsAll and gnames(all) == "Vest(3),Belt(1),Future Ring(1)" and rnames(all[1]) == "Olga Field,Cara Field,Bud Stone",
    "with offline members: Olga (+60%) leads the vest group: " .. rnames(all[1]))
  check(not gnames(all):find("My Gloves", 1, true), "you get no guild-needs group (as K2)")
  local again = GCA:GuildNeedsByCraft(K5.list)
  check(again == crafts and GCA.needsBuilds == nb0 + 1, "groups cached with the rows (no rebuild for the same entries)")
  UIx.needsCollapsed = {}
  local function kinds(d) local t = {} for i, e in ipairs(d) do t[i] = e.rowKind == "cat" and ("#" .. e.cat) or e.group.sug.info.name end return table.concat(t, ",") end
  local data, nc, nm, offN, allE = UIx.NeedsRows(nd, "", false)
  check(kinds(data) == "#5,Vest,#6,Belt,#11,Future Ring" and data[2].group == crafts[1] and #data[2].rows == 2 and data[2].cat == 5
    and nc == 3 and nm == 2 and offN == 1 and #allE == 3 and data[1].n == 1,
    "NeedsRows: slot categories (Chest, Waist, Rings) each with its crafts, 2 members, 1 offline member with upgrades: " .. kinds(data))
  UIx.needsCollapsed[5] = true
  data, nc, _, _, allE = UIx.NeedsRows(nd, "", false)
  check(kinds(data) == "#5,#6,Belt,#11,Future Ring" and nc == 3 and #allE == 3 and allE[1].group == crafts[1],
    "a collapsed category hides its crafts (still counted, still selectable): " .. kinds(data))
  UIx.needsCollapsed = {}
  data, nc, nm = UIx.NeedsRows(nd, "", true)
  check(#data[2].rows == 3 and nm == 3, "offline box on: Olga's row joins the vest group (3 members)")
  data, nc, nm = UIx.NeedsRows(nd, "  BELT ", false)
  check(kinds(data) == "#6,Belt" and data[2].group == crafts[2] and nc == 1 and nm == 1, "search by item name (case-insensitive, trimmed): the whole craft")
  data, nc, nm = UIx.NeedsRows(nd, "cara", false)
  check(kinds(data) == "#5,Vest" and #data[2].rows == 1 and data[2].rows[1].member.key == "Cara Field" and nm == 1, "search by member name: only that member's rows")
  check(#UIx.NeedsRows(nd, "olga", false) == 0 and #UIx.NeedsRows(nd, "olga", true) == 2, "an offline member is found only with the offline box")
  check(#UIx.NeedsRows(nd, "zzz", false) == 0 and #UIx.NeedsRows(nd, "50%", false) == 0, "no match: nothing; a '%' is plain text")

  print("== TagLine, pair slots, gain text")
  check(plain(UIx.TagLine({ { "a", "|cffff0000" }, { "b" }, { "c", "|cff00ff00" }, { "d", "|cff0000ff" } })) == "a  ·  b  ·  c  ·  d"
    and select(2, UIx.TagLine({ { "a", "|cffff0000" }, { "b" }, { "c", "|cff00ff00" }, { "d", "|cff0000ff" } }):gsub("|c", "")) == 2,
    "TagLine: at most two coloured tags")
  check(UIx.PairSlotName(11) == "Ring 1" and UIx.PairSlotName(14) == "Trinket 2" and UIx.PairSlotName(5) == nil
    and UIx.ShortSlotName(5) == "Chest", "pair slots get 'Ring 1' / 'Trinket 2', others the slot name")
  check(plain(UIx.RowGainText(fakeSug())) == "+12 pts" and not UIx.RowGainText(fakeSug()):find("|cff33ff33", 1, true),
    "row gain: '+12 pts' (user 2026-11-14: no %), not in the big green")
  check(UIx.GainNum(12.4) == "+12" and UIx.GainNum(9.94) == "+9.9" and UIx.GainNum(-12.6) == "-13" and UIx.GainNum(0.05) == "+0.1",
    "gain number: one decimal below 10, whole numbers from 10 on")
  local eb, es = UIx.CardGain(fakeSug({ status = "empty-slot" }))
  check(eb == "+12 pts" and es == "(empty slot)" and UIx.ChipGain(fakeSug({ points = 7 })) == "+7.0" and UIx.Pips == nil,
    "no pips; card '+12 pts' over '(empty slot)', Gildenbedarf '+7.0'")

  print("== window opens on guild needs (grouped by craft); offline box; expand; click-through")
  ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
  local selected = {}
  PanelTemplates_SelectTab = function(t) selected[t] = true end
  PanelTemplates_DeselectTab = function(t) selected[t] = false end
  local origML = GCA.GetMemberList
  local list = K5.list
  GCA.GetMemberList = function() return list end
  GCA.needsCache = nil
  GCA.db.settings.needsOffline = nil
  GCA.UI.frame = nil
  UIx.selected, UIx.autoKey = nil, nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  local f = UIx.frame
  local before = UIx.errorCount
  check(UIx.view == "needs" and UIx.needsView._shown and not UIx.memberView._shown, "opens on guild needs (member view hidden)")
  check(UIx.tabsTemplated and #UIx.tabs == 2 and UIx.tabs[1]._text == "Guild needs" and UIx.tabs[2]._text == "By member"
    and selected[UIx.tabs[1]] == true and selected[UIx.tabs[2]] == false, "two PanelTabButtonTemplate tabs, 'Guild needs' selected")
  check(UIx.inspectButton == nil and UIx.scanButton == nil and UIx.optionsButton == nil and UIx.survival._points[1][1] == "BOTTOMLEFT",
    "no 'Inspect target' / 'Scan group' buttons; K6: no Options button, the slider in the bottom-left corner")
  local nl, nd = UIx.needsList, UIx.needDetail
  local function nkinds() local t = {} for i, e in ipairs(nl.data) do t[i] = e.rowKind == "cat" and ("#" .. e.cat) or e.group.sug.info.name end return table.concat(t, ",") end
  check(nkinds() == "#5,Vest,#6,Belt,#11,Future Ring", "slot categories with their crafts: " .. nkinds())
  local r1, r3 = nl.pools.default[1], nl.pools.default[3]
  check(plain(r1.label._text) == "Vest" and not r1.label._text:find("|c", 1, true) and r1.count._text == " [2]" and r1.count._points[1][2] == r1.label
    and r1.gain._text == "+38" and r1.icon == nil and r1.caret == nil and r1.members == nil and r1._h == 25 and r1.label._points[1][4] == 22,
    "craft row = a recipe row: plain white name, its count ' [2]' right after it, best gain right, no icon / caret / member run, 25 px: " .. plain(r1.label._text))
  check(r1.hl._atlas == "Professions_Recipe_Hover" and r1.hl._alpha == 0.5 and r1.hl._h == 21 and r1.hl._points[1][5] == -1
    and r1.sel._atlas == "Professions_Recipe_Active" and r1.sel._h == 19 and r1.sel._shown and not nl.pools.default[2].sel._shown,
    "row art from the probe: hover Professions_Recipe_Hover (21 px, alpha 0.5, y -1), the selected craft Professions_Recipe_Active (19 px)")
  check(plain(r3.label._text) == "Future Ring" and r3.dimmed and r3.label._alpha == 0.55 and r3.gain._text == "+90",
    "the look-ahead-only craft last and dimmed")
  local cp = nl.pools.cat
  check(cp and cp[1].text._text == "Chest" and cp[2].text._text == "Waist" and cp[3].text._text == "Rings" and cp[1]._h == 25
    and cp[1].bg._atlas == "common-button-list-collapseExpand" and cp[1].hl._atlas == "common-button-list-collapseExpand"
    and cp[1].hl._SetBlendMode[1] == "ADD" and cp[1].hl._alpha == 0.4 and cp[1].text._points[1][1] == "LEFT" and cp[1].text._points[1][4] == 8
    and cp[1].CollapseButton._w == 20 and cp[1].CollapseButton._points[1][1] == "RIGHT" and cp[1].CollapseButton._points[1][4] == -6
    and cp[1].CollapseButton.text._text == "–" and UIx.collapseIconKind == "text" and cp[1].native == nil,
    "category header replicated from the probe: collapseExpand art + ADD hover 0.4, gold text at 8, 20 px CollapseButton at -6 ('–', no icon atlas in this mock)")
  local fm = menuOf(UIx.filterButton)
  check(plain(UIx.needsCount._text) == "3 crafts are worth it for 2 members" and plain(fm[5].text) == "Include offline members (1)" and not fm[5]:on(),
    "count line; K6: Filter menu entry 'Include offline members (1)', off by default: " .. plain(UIx.needsCount._text))
  local s1, s2 = nd.members.pools.default[1], nd.members.pools.default[2]
  check(UIx.needSel == "i9001" and nd.entry and nd.entry.group == K5.crafts1 or (nd.entry and nd.entry.group.key == "i9001"),
    "the best craft is selected and shown in the detail panel")
  check(nd.name._text == "Vest" and plain(nd.desc._text) == "Chest" and nd.forTitle._text == "Would be an upgrade for 2 members:"
    and nd.iconBtn.icon._tex == "x" and nd.iconBtn.iconShape and nd.name._shown and not nd.srcTitle._shown and not nd.reagTitle._shown,
    "detail: icon, name, slot line, 'Would be an upgrade for 2 members:' (known recipe: no sources; no reagents in this fake)")
  check(plain(s1.name._text) == "Cara Field" and plain(s1.state._text) == "Old Vest" and plain(s2.state._text) == "Slot empty" and s1.wornBtn ~= nil
    and s1.state._points[1][1] == "LEFT" and s1.state._points[1][2] == s1.wornBtn and s1.wornBtn._points[1][4] == 8 + UIx.NEED_MEMBER_W + 8
    and s1.offer._shown and not s1.offer.isIcon and s1.offer._text == "Offer" and s1.offer._w == 80 and s1.crafted._shown
    and s1.crafted.template == "MinimalCheckboxTemplate" and plain(s1.gain._text) == "+38" and s1.chip == nil and s1._shown and s2._shown,
    "member row on one line: member column | worn icon + its name beside it | gain, 'Offer', box: " .. plain(s1.state._text))
  check(nd.members.viewH == 2 * 42 and nd.members.viewW == nd.w - 44 and s1.stateW >= 40,
    "the member list is as tall as its rows (2 x 42), as wide as the detail panel")
  fm[5]:click()
  r1 = nl.pools.default[1]
  check(GCA.db.settings.needsOffline == true and r1.count._text == " [3]" and nd.members.pools.default[1].data.member.key == "Olga Field"
    and nd.members.pools.default[1].name._alpha == 1 and nd.members.pools.default[1].name._text:find("StatusIcon-Offline", 1, true)
    and not nd.members.pools.default[1].name._text:find("|cff7f7f7f", 1, true) and not nd.members.pools.default[1].offer._shown and menuOf(UIx.filterButton)[5]:on()
    and plain(UIx.needsCount._text) == "3 crafts are worth it for 3 members", "offline members on: saved, Olga (offline dot + softened class colour, no Offer) leads the vest craft")
  check(UIx.filterButton.resetButton and UIx.filterButton.resetButton._shown and UIx.filterButton.resetButton.icon._atlas == "auctionhouse-ui-filter-redx"
    and UIx.memberFilter.resetButton._shown, "a filter off its default -> the red reset badge on both Filter buttons")
  menuOf(UIx.memberFilter)[5]:click()
  check(GCA.db.settings.needsOffline == false and nl.pools.default[1].count._text == " [2]" and not UIx.filterButton.resetButton._shown,
    "the member list's Filter turns it off again (one setting); the badge goes")
  GCA.db.settings.showUnlearned = true; UIx:RefreshFilters()
  check(UIx.filterButton.resetButton._shown, "badge for 'Show missing recipes' too")
  UIx.filterButton.resetButton._scripts.OnClick(UIx.filterButton.resetButton)
  check(GCA.db.settings.showUnlearned == false and GCA.db.settings.lookahead == true and not UIx.filterButton.resetButton._shown,
    "the badge resets the list filters to their defaults")
  nl.pools.default[2]._scripts.OnClick(nl.pools.default[2])
  check(UIx.needSel == "i9002" and nd.name._text == "Belt" and nl.pools.default[2].sel._shown and not nl.pools.default[1].sel._shown and #nd.members.data == 1,
    "a click on a craft shows it in the detail panel (selection moves)")
  nl.pools.default[1]._scripts.OnClick(nl.pools.default[1])
  s1, s2 = nd.members.pools.default[1], nd.members.pools.default[2]
  captureTip(); s1._scripts.OnEnter(s1)
  check(plainTip(), "member row under a craft: the craft's plain item tooltip: " .. tipText() .. " / " .. table.concat(H.hyper, ","))
  captureTip(); nl.pools.default[1]._scripts.OnEnter(nl.pools.default[1])
  check(plainTip(), "craft row tooltip = the plain item tooltip (no member list / hints): " .. tipText() .. " / " .. table.concat(H.hyper, ","))
  s1.crafted:SetChecked(true); s1.crafted._scripts.OnClick(s1.crafted)
  check(GCA:CraftedMark("Cara Field", "Leatherworking", 9001) ~= nil, "crafted box on a member row marks it for that member")
  GCA:SetCrafted("Cara Field", "Leatherworking", K5.vestB, false)
  local linked
  HandleModifiedItemClick = function(l) linked = l end
  IsShiftKeyDown = function() return true end
  nl.pools.default[1]._scripts.OnClick(nl.pools.default[1])
  check(linked == "|Hitem:9001|h[Vest]|h" and UIx.needSel == "i9001", "shift-click on a craft row links the item (selection unchanged)")
  linked = nil
  nd.members.pools.default[2]._scripts.OnClick(nd.members.pools.default[2])
  IsShiftKeyDown = function() return false end
  check(linked == "|Hitem:9001|h[Vest]|h" and UIx.view == "needs", "shift-click on a member row links, stays on guild needs")
  nd.members.pools.default[2]._scripts.OnClick(nd.members.pools.default[2])
  check(UIx.view == "needs", "a plain click on a member row (their equipped item) does nothing")
  local mrow = nd.members.pools.default[2].data
  UIx:OpenMember(mrow.member.key, mrow.sug.slot, mrow.sug)
  check(UIx.view == "member" and UIx.selected == "Bud Stone" and UIx.autoKey == nil and UIx.memberView._shown and selected[UIx.tabs[2]] == true
    and UIx.current == K5.bud, "OpenMember still opens Bud in 'By member' (tab follows)")
  check(UIx.MemberMode() == "sheet" and UIx.sheet._shown and UIx.sheetSlot == 5 and UIx.sheet.centre.featured == K5.vestA,
    "sheet: that slot selected, that craft compared (" .. tostring(UIx.sheetSlot) .. ")")
  check(UIx.sugList.minimalBar == nil or not UIx.sugList.minimalBar._shown,
    "in the sheet view the hidden list's scroll bar is hidden too")
  GCA.db.settings.memberView = "list"
  UIx:SetView("needs")
  UIx.needSel = "i9003"
  UIx:RefreshNeeds()
  local ringRow = nd.members.pools.default[1]
  check(ringRow and ringRow.data.sug == K5.ringF and ringRow.chip == nil and plain(ringRow.name._text) == "Bud Stone" and plain(ringRow.state._text) == "Slot empty (Ring 1)  from level 42 · 3 to go"
    and ringRow.state._text:find("|cfff0b44c", 1, true) and ringRow.dimmed and plain(nd.desc._text) == "Rings  ·  from level 42 · 3 to go",
    "a look-ahead member row: 'Slot empty (Ring 1)' + the orange level tag beside the icon, dimmed; the detail line names the level: " .. plain(ringRow.state._text))
  UIx:OpenMember(ringRow.data.member.key, ringRow.data.sug.slot, ringRow.data.sug)
  local secY = UIx.sugList:FindY(function(d) return d.rowKind == "section" and d.sec.key == 11 end)
  check(secY and secY > 0 and UIx.sugList.scrolledTo == math.min(secY, math.max(0, UIx.sugList.contentH - UIx.sugList.viewH)),
    "list: ...scrolled to the rings section (" .. tostring(secY) .. ")")
  GCA.db.settings.memberView = "sheet"
  UIx:SetView("needs")
  UIx.needSel = "i9001"; UIx:RefreshNeeds()
  cp[1]._scripts.OnClick(cp[1])
  check(UIx.needsCollapsed[5] and nkinds() == "#5,#6,Belt,#11,Future Ring" and cp[1].CollapseButton.text._text == "+" and UIx.needSel == "i9001"
    and nd.name._text == "Vest", "a click on 'Chest' collapses it ('+'), the selected craft stays in the detail panel")
  cp[1].CollapseButton._scripts.OnClick(cp[1].CollapseButton)
  check(not UIx.needsCollapsed[5] and nkinds() == "#5,Vest,#6,Belt,#11,Future Ring", "the collapse button opens it again")
  local rsug = fakeSug({ known = false, cand = { spellID = 9100, itemID = 9100, recipe = { skill = 100, src = "trainer", r = { { 2318, 5 }, { 2320, 2 }, { 4231, 1 } } } } })
  local rentry = { group = { key = "i9100", sug = rsug, best = { member = K5.bud, sug = rsug }, rows = { { rowKind = "need", member = K5.bud, sug = rsug } } },
    rows = { { rowKind = "need", member = K5.bud, sug = rsug } }, cat = 5 }
  UIx:UpdateCraftDetail(rentry)
  local rg = nd.reag
  check(nd.reagTitle._shown and nd.reagTitle._text == "Reagents:" and rg[1]._shown and rg[3]._shown and plain(rg[1].text._text):find("^0/5 ") and rg[1].count == nil
    and rg[1].iconBorder._atlas == "Professions-Slot-Frame" and rg[1].qual._atlas == "Professions-Slot-bg" and not rg[1].enough
    and rg[1]._points[1][4] == 16 and rg[2]._points[1][4] == 16 and rg[2]._points[1][5] - rg[1]._points[1][5] == -UIx.REAGENT_STEP
    and rg[3]._points[1][5] < rg[2]._points[1][5],
    "reagents as in the crafting window: one column, '0/5 Name' beside the icon: " .. plain(rg[1].text._text))
  check(nd.srcTitle._shown and nd.srcTitle._text == "Where to get it:" and plain(nd.src[1]._text) == "Trainer (skill 100)" and nd.src[1]._shown and not nd.src[2]._shown
    and nd.src[1]._text:find("TrainerGossipIcon", 1, true) and plain(nd.desc._text) == "Chest  ·" and nd.learn._shown
    and nd.learn.text._text == UIx.LearnText(rsug, K5.bud) and nd.srcBox._scripts.OnClick,
    "sources (with their kind icons) under the reagents; the slot line ends in the same source button as the cards: " .. plain(nd.learn.text._text))
  local rTop = -nd.reagTitle._points[1][5]
  check(rTop == 92 + 42 + 10 and -nd.srcTitle._points[1][5] == rTop + 18 + 3 * UIx.REAGENT_STEP, "members, then reagents (one column), then sources stacked")
  check(not nd.cost._shown and not GCA.Auction.Available(), "no Auctionator installed: no 'To craft' / 'Profit' lines")
  do
    local prices = { [2318] = 120, [4231] = 300, [9100] = 2000 }
    local vendor = { [2320] = 10 }
    Auctionator = { Constants = { AfterAHCut = 0.95 }, API = { v1 = {
      GetAuctionPriceByItemID = function(caller, id) assert(type(caller) == "string"); return prices[id] end,
      GetVendorPriceByItemID = function(caller, id) return vendor[id] end,
    } } }
    UIx:UpdateCraftDetail(rentry)
    local t = plain(nd.cost._text)
    check(GCA.Auction.Available() and nd.cost._shown and GCA.Auction.CraftCost(rsug.cand.recipe.r) == 920
      and t:find("^To craft: ") and t:find("\nProfit: ") and not nd.cost._text:find("|cffff2020", 1, true),
      "Auctionator: 'To craft' = 5x120 + 2x10 (vendor) + 300 = 920c, 'Profit' = 2000 x 0.95 - 920: " .. t:gsub("\n", " | "))
    check(-nd.srcTitle._points[1][5] == rTop + 18 + 3 * UIx.REAGENT_STEP + 2 * 15 + 8, "the price lines push the sources down")
    prices[9100] = 500
    UIx:UpdateCraftDetail(rentry)
    check(nd.cost._text:find("|cffff2020-", 1, true) and GCA.Auction.Profit(9100, 920) == math.floor(500 * 0.95 - 920), "a loss is red with a minus")
    prices[4231], prices[9100] = nil, nil
    UIx:UpdateCraftDetail(rentry)
    check(plain(nd.cost._text) :find("(1 without a price)", 1, true) and not plain(nd.cost._text):find("Profit", 1, true),
      "a reagent without a price is named; no item price -> no profit line: " .. plain(nd.cost._text))
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() error("renamed internals") end } } }
    local ok = pcall(UIx.UpdateCraftDetail, UIx, rentry)
    check(ok and GCA.Auction.CraftCost({ { 2318, 1 } }) == 0, "Auctionator erroring: no Lua error")
    Auctionator = nil
    UIx:UpdateCraftDetail(rentry)
    check(not nd.cost._shown, "Auctionator gone again: lines hidden")
  end
  do
    local opened, savedTS = {}, C_TradeSkillUI
    C_TradeSkillUI = { OpenRecipe = function(id) opened[#opened + 1] = id end }
    rsug.known = true
    UIx:UpdateCraftDetail(rentry)
    nd.iconBtn._scripts.OnClick(nd.iconBtn, "LeftButton")
    check(opened[1] == 9100, "Gildenbedarf: click on the craft's icon opens recipe 9100")
    nd.members.pools.default[1]._scripts.OnClick(nd.members.pools.default[1], "LeftButton")
    check(#opened == 1, "Gildenbedarf: a click on a member row (their equipped item) opens nothing")
    local linked, savedLink = {}, HandleModifiedItemClick
    HandleModifiedItemClick = function(l) linked[#linked + 1] = l end
    IsControlKeyDown = function() return true end
    nd.iconBtn._scripts.OnClick(nd.iconBtn, "LeftButton")
    IsControlKeyDown = nil
    nd.iconBtn._scripts.OnClick(nd.iconBtn, "RightButton")
    HandleModifiedItemClick = savedLink
    check(#opened == 1 and #linked == 1 and linked[1] == rsug.info.link,
      "Gildenbedarf: ctrl-click on the craft's icon links it (not opened); a right-click on a learned craft opens nothing")
    rsug.known = false
    UIx:UpdateCraftDetail(rentry)
    C_TradeSkillUI = savedTS
  end
  UIx:RefreshNeeds()
  local sb = UIx.searchBox
  check(sb.native and sb._template == "SearchBoxTemplate" and sb.placeholder == sb.Instructions and sb.Instructions._text == "Search"
    and sb._w == UIx.SEARCH_W and sb._parent == UIx.needsInset, "guild-needs search = SearchBoxTemplate on top of the list panel")
  sb:SetText("belt"); sb._scripts.OnTextChanged(sb)
  check(nkinds() == "#6,Belt" and plain(UIx.needsCount._text) == "1 craft is worth it for 1 member" and nd.name._text == "Belt",
    "search 'belt': one craft, singular count, the detail follows (the selected vest is not listed)")
  sb:SetText("zzz"); sb._scripts.OnTextChanged(sb)
  check(#nl.data == 0 and UIx.needsEmpty._text == 'No upgrade matches "zzz".' and not nd.name._shown and not nd.members._shown,
    "no match: the detail panel's empty text says so")
  sb:SetText(""); sb._scripts.OnTextChanged(sb)
  check(sb._text == "" and UIx.needsEmpty._text == "", "clearing the search resets it")
  local savedKC = GCA.knownCount
  GCA.knownCount = 5
  list = { K5.me, K5.olga }
  GCA.needsCache = nil
  UIx:Refresh()
  check(UIx.needsEmpty._text:find("1 offline member(s) do", 1, true), "nothing online, an offline member needs something: the empty text says so")
  list = K5.list
  GCA.knownCount = savedKC
  GCA.needsCache = nil
  UIx:OpenMember("Olga Field", 5)
  check(UIx.collapsed.offline == false and UIx.selected == "Olga Field" and UIx.current == K5.olga, "opening an offline member expands the offline group")
  UIx.needsCollapsed[6] = true
  f:Hide(); GCA.UI:Toggle(); advance(1)
  check(UIx.view == "needs" and UIx.needsView._shown and next(UIx.needsCollapsed) == nil and UIx.needSel == "i9001" and UIx.collapsed.offline == true
    and UIx.collapsed.online == false, "reopened: guild needs, every category open, the best craft selected, offline group collapsed (not saved)")
  UIx.tabs[2]._scripts.OnClick(UIx.tabs[2])
  check(UIx.view == "member" and UIx.memberView._shown, "tab 2 switches to the member view")
  UIx.tabs[1]._scripts.OnClick(UIx.tabs[1])
  check(UIx.view == "needs", "tab 1 back to guild needs")
  local nbB = GCA.needsBuilds
  f:SetSize(1300, 900); advance(0.1); UIx:Layout(); UIx:Refresh(); UIx:Refresh()
  sb:SetText("vest"); sb._scripts.OnTextChanged(sb); sb:SetText(""); sb._scripts.OnTextChanged(sb)
  check(GCA.needsBuilds == nbB and UIx.layoutW == 1300 and nd.w == 1300 - 290, "resizing, refreshing and searching reuse the cached groups (no rebuild); the detail panel follows")
  f:SetSize(980, 640); advance(0.1)

  print("== member list (search, Online / Offline groups = native category headers, native rows)")
  UIx:SetView("member")
  UIx.collapsed.online, UIx.collapsed.offline = false, true
  UIx.selected = "Bud Stone"
  UIx:Refresh()
  local ml = UIx.memberList
  local kinds = {}
  for i, d in ipairs(ml.data) do kinds[i] = d.rowKind and (d.group .. "(" .. d.count .. ")") or d.key end
  check(table.concat(kinds, ",") == "online(3),Me Stone,Bud Stone,Cara Field,offline(1)",
    "'Online 3' (you + recorded online), 'Offline 1' collapsed, nobody without gear: " .. table.concat(kinds, ","))
  check(ml.rowY[1][2] == 27 and ml.rowY[2][2] == 25 and ml.pools.default[1]._SetHeight[1] == 25, "recipe rows 25 px, category headers 25 (+2) px")
  local gp = ml.pools.group
  check(gp[1].text._text == "Online" and gp[2].text._text == "Offline" and gp[1].open == true and gp[2].open == false
    and gp[1].CollapseButton.text._text == "–" and gp[2].CollapseButton.text._text == "+" and gp[1].bg._atlas == "common-button-list-collapseExpand"
    and gp[1].count == nil and gp[1].RankBar == nil and gp[1]._template == nil,
    "group headers = the replicated category header: 'Online' (open, '–') / 'Offline' (collapsed, '+'), no count, no template instance")
  local mb = ml.pools.default[2]
  check(mb.data == K5.bud and mb.badge == nil and mb.classIcon == nil and mb.line == nil and plain(mb.name._text) == "Bud Stone  39" and mb.name._text:find("^|TInterface\\FriendsFrame\\StatusIcon%-Online") and mb.name._text:find("|cff", 1, true)
    and mb.gain._text == "+20" and mb.name._points[1][4] == 22,
    "member row: online dot + name in class colour + level, '+20' right (no class icon, no second line): " .. plain(mb.name._text))
  check(plain(ml.pools.default[1].name._text) == "Me Stone  36 (you)", "you marked")
  check(mb.sel._shown and mb.sel._atlas == "Professions_Recipe_Active" and not ml.pools.default[1].sel._shown
    and mb.hl._atlas == "Professions_Recipe_Hover" and mb.hl._alpha == 0.5,
    "the selected member = Professions_Recipe_Active, hover = Professions_Recipe_Hover")
  check(mb.textW == UIx.memberList.viewW - 22 - UIx.MEMBER_GAIN_W - 10 and mb.name._SetWordWrap[1] == false, "name left of the gain, one line")
  captureTip(); mb._scripts.OnEnter(mb)
  check(tipText():find("3 upgrades · best: Waist", 1, true), "the former second line is in the row's tooltip")
  captureTip(); ml.pools.default[3]._scripts.OnEnter(ml.pools.default[3])
  check(tipText():find("1 upgrade · best: Chest", 1, true), "singular line (tooltip)")
  do
    local L, lines, savedData, savedAdd = ns.L, {}, mb.data, GameTooltip.AddLine
    GameTooltip.AddLine = function(_, t, r, g, b) lines[#lines + 1] = table.concat({ tostring(t), tostring(r), tostring(g), tostring(b) }, "/") end
    local rec = { items = {}, time = time(), source = "inspect" }
    local function member(over)
      local d = { key = "Tess Field", class = "MAGE", level = 30, online = true, prof = "Leatherworking", member = rec, spec = "FROST", specHow = "manual" }
      for k, v in pairs(over) do d[k] = v end
      return d
    end
    local best = { slot = 6, points = 12 }
    local cases = {
      { d = member({ member = false }), line = L.MEMBER_TIP_NOT_INSPECTED, tip = L.MEMBER_TIP_NOT_INSPECTED .. "/0.7/0.7/0.7" },
      { d = member({ browse = true, suggestions = { 1, 2 } }), line = string.format(L.MEMBER_LINE_BROWSE, 2),
        tip = string.format(L.MEMBER_TIP_BROWSE, UIx.ProfName("Leatherworking"), 2) .. "/0.7/0.7/0.7", forget = true },
      { d = member({ best = best, knownCount = 1 }), line = string.format(L.MEMBER_LINE_UPGRADES_1, 1, UIx.ShortSlotName(6)),
        tip = string.format(L.MEMBER_TIP_BEST, 1, UIx.GainText(best)) .. "/0.3/1/0.3", forget = true },
      { d = member({ state = "no-spec" }), line = L.MEMBER_LINE_NOSPEC, tip = L.MEMBER_TIP_NOSPEC .. "/1/0.5/0.2", forget = true },
      { d = member({ state = "no-level" }), line = L.MEMBER_LINE_NOLEVEL, tip = L.MEMBER_TIP_NOLEVEL .. "/1/0.5/0.2", forget = true },
      { d = member({ state = "loading" }), line = L.MEMBER_LINE_LOADING, tip = L.MEMBER_TIP_NONE .. "/0.7/0.7/0.7", forget = true },
      { d = member({ state = "no-weights" }), line = L.MEMBER_LINE_NONE, tip = L.MEMBER_TIP_NONE .. "/0.7/0.7/0.7", forget = true },
      { d = member({ state = "no-spec", isSelf = true }), line = L.MEMBER_LINE_NOSPEC, tip = L.MEMBER_TIP_NOSPEC .. "/1/0.5/0.2" },
    }
    local bad = {}
    for i, case in ipairs(cases) do
      if case.d.member == false then case.d.member = nil end
      lines = {}
      mb.data = case.d
      mb._scripts.OnEnter(mb)
      local text = UIx.MemberLine(case.d)
      local forgetLine = L.MEMBER_TIP_FORGET .. "/0.5/0.5/0.5"
      local stateLine = lines[#lines - (case.forget and 1 or 0)]
      if plain(text) ~= case.line or lines[3] ~= text .. "/0.75/0.72/0.65" or stateLine ~= case.tip
        or (lines[#lines] == forgetLine) ~= (case.forget == true) then
        bad[#bad + 1] = i .. ": " .. plain(text) .. " | " .. table.concat(lines, " | ")
      end
    end
    GameTooltip.AddLine, mb.data = savedAdd, savedData
    check(#bad == 0, "member line and tooltip per state (not inspected, browse, upgrades, no spec, no level, loading, none, yourself): "
      .. table.concat(bad, "; "))
  end
  gp[2]._scripts.OnClick(gp[2])
  local olgaRow
  for _, r in ipairs(ml.pools.default) do if r._shown and r.data == K5.olga then olgaRow = r end end
  local r, g, b = UIx.OfflineColor(0.25, 0.78, 0.92)
  check(olgaRow and olgaRow.offline and olgaRow.name._alpha == 1 and olgaRow.name._text:find("StatusIcon-Offline", 1, true)
    and UIx.MemberName({ key = "X", class = "MAGE", online = true }):find("StatusIcon-Online", 1, true)
    and r < 0.25 + 0.5 and math.abs(r - g) < math.abs(0.25 - 0.78),
    "offline group expanded: Olga listed with the grey offline dot, class colour softened (not dimmed)")
  captureTip(); gp[2]._scripts.OnEnter(gp[2])
  check(tipText():find("Offline (1)", 1, true), "group header tooltip")
  local ms = UIx.memberSearch
  ms:SetText("cara"); ms._scripts.OnTextChanged(ms)
  kinds = {}
  for i, d in ipairs(ml.data) do kinds[i] = d.rowKind and d.group or d.key end
  check(table.concat(kinds, ",") == "online,Cara Field" and ms.native and ms._template == "SearchBoxTemplate", "member search 'cara': only Cara (K6: SearchBoxTemplate)")
  UIx:OpenMember("Bud Stone")
  check(ms._text == "" and UIx.selected == "Bud Stone", "opening a member hidden by the search clears the search")
  UIx.collapsed.offline = true
  check(UIx.syncDot.text._text == "Guild sync · 3 recorded", "sync label: 'Guild sync · 3 recorded' (members with gear, not you): " .. tostring(UIx.syncDot.text._text))

  print("== header strip, (i) icon, sync label")
  check(UIx.syncText == nil and UIx.syncDot and UIx.syncDot.dot == nil and UIx.survival._parent == f.content, "sync text gone from the header strip; K6: no dot; slider in the bottom bar")
  local sync = GCA.SyncState
  for _, st in ipairs({ "ok", "idle", "paused", "off" }) do
    GCA.SyncState = function() return st end
    UIx.syncDot:Update()
    local c = UIx.SYNC_COLORS[st]
    check(UIx.syncDot.state == st and UIx.syncDot.text._SetTextColor[1] == c[1] and UIx.syncDot.text._SetTextColor[2] == c[2], "sync label coloured for '" .. st .. "'")
  end
  GCA.SyncState = sync
  GCA.SyncStatusLine = function() return "Guild sync: 2 guildie(s) with the addon seen" end
  captureTip(); UIx.syncDot._scripts.OnEnter(UIx.syncDot)
  check(tipText():find("Guild sync", 1, true) and tipText():find("2 guildie", 1, true) and tipText():find("Green:", 1, true), "sync dot tooltip = status line + legend")
  GCA.SyncStatusLine = nil
  check(UIx.infoIcon.kind == "text" and UIx.infoIcon.text._text == "(i)", "(i) icon: text fallback (no info atlas / file check in this mock)")
  UIx:Refresh()
  captureTip(); UIx.infoIcon._scripts.OnEnter(UIx.infoIcon)
  check(H.tip[1] == "Scoring" and (UIx.sourceLine == "" or tipText():find(UIx.sourceLine, 1, true)), "(i) tooltip shows the source line")
  check(UIx.errorCount == before, "no error reported (K2 window)")
  UIx:SetView("needs")
  f:Hide()
  GCA.GetMemberList = origML

  print("== skill bar (StatusBar path), class icon, skin table")
  Frame.SetStatusBarTexture = function(self, t) self._sbTex = t end
  Frame.SetStatusBarColor = function(self, ...) self._sbColor = { ... } end
  UIx.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  local pb2 = GCA.UI.profButton
  pb2:SetSkill("Leatherworking  150 / 225", 150, 225)
  check(pb2.barKind == "statusbar" and pb2.bar._sbTex == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" and pb2.bar._sbColor
    and math.abs(pb2.bar._value - 150 / 225) < 1e-9 and pb2.label._parent == pb2.top and pb2.border._atlas == "Professions-skillbar-frame", "StatusBar API present: skill-bar file, value = 150/225, text + rank-bar frame above the fill")
  pb2:SetSkill("Blacksmithing (browse)")
  check(pb2.bar._value == 0 and pb2.ratio == 0, "no rank (browse): empty bar")
  Frame.SetStatusBarTexture, Frame.SetStatusBarColor = nil, nil
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame:Hide(); GCA.UI.frame = nil; GCA.UI:Toggle(); advance(1)
  pb2 = GCA.UI.profButton
  pb2:SetSkill("x", 60, 300)
  check(pb2.barKind == "fill" and pb2.fill._SetColorTexture and math.abs(pb2.fill._w - (GCA.UI.PROF_BAR_W - 10) * 0.2) < 1e-9, "skill-bar file not there: plain fill in the skin colour, 20 %")
  GetFileIDFromPath = nil
  local ic = GCA.UI.specButton.icon
  CLASS_ICON_TCOORDS = { ROGUE = { 0.5, 0.75, 0, 0.25 } }
  check(GCA.UI.SetClassIcon(ic, "ROGUE") == "file" and ic._tex == "Interface\\TargetingFrame\\UI-Classes-Circles" and ic._SetTexCoord[1] == 0.5,
    "class icon: the class-circles file + CLASS_ICON_TCOORDS where the atlas is missing")
  ATLASES["classicon-rogue"] = true
  check(GCA.UI.SetClassIcon(ic, "ROGUE") == "atlas" and ic._atlas == "classicon-rogue", "class icon: the atlas when GetAtlasInfo knows it")
  ATLASES["classicon-rogue"] = nil
  GetFileIDFromPath = function() return nil end
  check(GCA.UI.SetClassIcon(ic, "MAGE") == nil and GCA.UI.SetClassIcon(ic, nil) == nil, "class icon: neither -> none (text only)")
  GetFileIDFromPath = nil
  CLASS_ICON_TCOORDS = nil
  GCA.UI.specButton:SetClass("WARRIOR")
  check(not GCA.UI.specButton.icon._shown and GCA.UI.specButton.iconKind == nil and GCA.UI.specButton.dropdown._shown ~= false, "spec picker without an icon: just the dropdown")
  local tx = UIx.frame:CreateTexture()
  check(GCA.UI.Skin(tx, "rowSelected") == "atlas" and tx._atlas == "Professions_Recipe_Active" and GCA.UI.Skin(tx, "rowHover") == "atlas"
    and tx._atlas == "Professions_Recipe_Hover" and tx._alpha == 0.5 and GCA.UI.Skin(tx, "listBg") == "atlas"
    and GCA.UI.SKIN.disc == nil and GCA.UI.SKIN.chipBg == nil and GCA.UI.SKIN.selectBar == nil and GCA.UI.SKIN.treeLine == nil and GCA.UI.TEX.disc == nil,
    "skin table: the recipe row's own hover / selected atlases, summarylist panel; no disc/chip/select-bar/tree roles")
  ATLASES["Professions_Recipe_Hover"] = nil
  local tx2 = UIx.frame:CreateTexture()
  check(GCA.UI.Skin(tx2, "rowHover") == "file" and tx2._tex == GCA.UI.TEX.rowHL and tx2._SetBlendMode[1] == "ADD", "skin: without the hover atlas the list-row file (ADD)")
  ATLASES["Professions_Recipe_Hover"] = true
  local sk = GCA.UI.SKIN
  check(type(sk.detailBorder) == "table" and sk.category.atlas == "common-button-list-collapseExpand" and sk.categoryHover.atlasBlend == "ADD"
    and #sk.collapseIcon.pairs >= 1 and sk.detailRing.file == "Interface\\Common\\GoldRing",
    "skin roles: detailBorder (pluggable), category / categoryHover, collapseIcon candidates, detailRing")
  GCA.UI.frame:Hide()
  UIx = GCA.UI

  print("== German texts on the new parts")
  ns.locale = "deDE"
  GCA.GetMemberList = function() return list end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(UIx.tabs[1]._text == "Gildenbedarf" and UIx.tabs[2]._text == "Nach Mitglied", "German tabs")
  check(plain(UIx.needsCount._text) == "3 Herstellungen lohnen für 2 Mitglieder" and UIx.searchBox.placeholder._text == "Suchen"
    and plain(menuOf(UIx.filterButton)[5].text) == "Offline-Mitglieder einbeziehen (1)" and plain(menuOf(UIx.filterButton)[7].text):find("^Levelbonus") and plain(menuOf(UIx.filterButton)[8].text):find("^Flüstertext"),
    "German count, search instructions; K6 Filter menu entries: " .. plain(UIx.needsCount._text))
  local gr1 = UIx.needsList.pools.default[1]
  check(gr1.count._text == " [2]" and UIx.needsList.pools.cat[1].text._text == "Chest" and UIx.needsList.pools.cat[3].text._text == "Ringe"
    and UIx.needDetail.forTitle._text == "Wäre eine Verbesserung für 2 Mitglieder:", "German: craft row ' [2]', categories 'Chest' (client global, absent in the mock) / 'Ringe', detail title")
  local gs = UIx.needDetail.members.pools.default[1]
  check(plain(gs.state._text) == "Old Vest" and gs.offer._text == "Anbieten",
    "German member row: 'Old Vest' beside the icon, K6 red 'Anbieten' button: " .. plain(gs.state._text))
  UIx.searchBox:SetText("zzz"); UIx.searchBox._scripts.OnTextChanged(UIx.searchBox)
  check(UIx.needsEmpty._text == "Keine Verbesserung passt zu „zzz“.", "German no-match text")
  UIx.searchBox:SetText(""); UIx.searchBox._scripts.OnTextChanged(UIx.searchBox)
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local gml = UIx.memberList
  check(gml.pools.group[1].text._text == "Online" and plain(gml.pools.default[2].name._text) == "Bud Stone  39"
    and UIx.modeToggle._override == "Ansicht: Charakterbogen" and UIx.syncDot.text._text == "Gilden-Sync · 3 erfasst" and UIx.memberSearch.placeholder._text == "Mitglied suchen"
    and menuTexts(menuOf(UIx.modeToggle)) == "Charakterbogen|Liste",
    "German: 'Online' header, member row, 'Ansicht: Charakterbogen' (radios Charakterbogen|Liste), 'Gilden-Sync · 3 erfasst', 'Mitglied suchen'")
  check(UIx.MemberRows(list)[1].group == "online" and ns.L.OPT_OPEN == "Fenster öffnen", "German: groups, 'Fenster öffnen'")
  for _, sz in ipairs({ { 840, 560 }, { 980, 640 } }) do
    UIx.frame:SetSize(sz[1], sz[2]); UIx:Layout()
    layoutChecks(UIx, UIx.frame, "German " .. sz[1] .. "x" .. sz[2])
  end
  local function fits(text, px, per) return #plain(text):gsub("[\128-\191]", "") * per <= px end
  local tooWide = {}
  local function fit(name, text, px, per) if not fits(text, px, per) then tooWide[#tooWide + 1] = name .. " '" .. plain(text) .. "'" end end
  UIx.frame:SetSize(840, 560); UIx:Layout()
  fit("rank bar", "Lederverarbeitung  300 / 300", UIx.PROF_BAR_W - 60, 5.6)
  fit("view switch", string.format(ns.Locales.deDE.MVIEW_LABEL, ns.Locales.deDE.MVIEW_SHEET), UIx.TOGGLE_W - 30, 5.6)
  fit("search placeholder", ns.Locales.deDE.NEEDS_SEARCH, UIx.SEARCH_W - 35, 5.6)
  fit("offline filter entry", string.format(ns.Locales.deDE.NEEDS_OFFLINE, 12), 260, 5.6)
  fit("needs count", "12 Herstellungen lohnen für 45 Mitglieder", UIx.LEFT_W - 20, 5.6)
  fit("member row", "Mitglied Nachname  60", UIx.memberList.viewW - 22 - UIx.MEMBER_GAIN_W - 10, 6.5)
  fit("member search", ns.Locales.deDE.MEMBER_SEARCH, UIx.SEARCH_W - 35, 5.6)
  fit("category header", "Schmuckstücke", UIx.needsList.viewW - 8 - 32, 8)
  fit("craft row", "Dunkler Ledergürtel [3]", UIx.needsList.viewW - 22 - UIx.NEED_GAIN_W - 10, 6.5)
  fit("detail title", string.format(ns.Locales.deDE.DETAIL_FOR_N, 12), UIx.needDetail.w - 36, 5.6)
  fit("filter reset tip", ns.Locales.deDE.FILTER_RESET, 200, 6.5)
  fit("spec label", "Göttliche Pein (Schaden)", UIx.SPEC_BTN_W - 28 - 30, 5.6)
  fit("sync label", "Gilden-Sync · 123 erfasst", 200, 5.6)
  fit("member-view sub-line", "tragbar ab Stufe 42 (in 3 Stufen)  ·  nicht erlernt", UIx.subText._w, 5.6)
  fit("fold tip title", ns.Locales.deDE.FOLD_TIP_TITLE, 300, 6.5)
  fit("tab", "Nach Mitglied", 130 - 20, 6.5)
  fit("fallback tab button", "Nach Mitglied", 92 - 6, 6.5)
  check(#tooWide == 0, "German text fit at 840x560 (estimate): " .. table.concat(tooWide, "; "))
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.GetMemberList = origML

  print("== K: fallbacks (no tab template, no texture files, slider template present)")
  local origCF = CreateFrame
  CreateFrame = function(otype, name, parent, template)
    if template == "PanelTabButtonTemplate" then error("Couldn't find inherited node 'PanelTabButtonTemplate'") end
    return origCF(otype, name, parent, template)
  end
  GCA.GetMemberList = function() return list end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  local errs = UIx.errorCount
  check(not UIx.tabsTemplated and #UIx.tabs == 2 and UIx.tabs[1]._parent == UIx.frame.content and UIx.tabs[1]._text == "Guild needs",
    "no tab template: two plain buttons in the header strip")
  UIx.tabs[2]._scripts.OnClick(UIx.tabs[2])
  check(UIx.view == "member" and UIx.errorCount == errs, "fallback buttons switch the view")
  UIx.frame:SetSize(840, 560); UIx:Layout()
  layoutChecks(UIx, UIx.frame, "tab fallback 840x560")
  UIx.frame:Hide()
  CreateFrame = origCF
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  local ns1 = UIx.needDetail.members.pools.default[1]
  check(ns1.offer._shown and not ns1.offer.isIcon and ns1.offer._text == "Offer" and ns1.offer._w == UIx.OFFER_SMALL_W, "Offer = the red text button 'Offer' (no file needed)")
  check(UIx.needsList.pools.cat[1].CollapseButton.text._text == "–" and UIx.needDetail.iconBtn.iconShape == "square",
    "no files: the category's '–' text; K8 the detail icon falls back to the square reagent-slot icon (mask / ring files not confirmed)")
  check(UIx.infoIcon.kind == "text", "info icon file not confirmed: text '(i)'")
  UIx.frame:Hide()
  GetFileIDFromPath = function(p) return 12345 end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(not UIx.needDetail.members.pools.default[1].offer.isIcon and UIx.infoIcon.kind == "file" and UIx.infoIcon.tex._tex == UIx.INFO_FILE, "files confirmed: info file; Offer still the button")
  UIx.frame:Hide()
  GetFileIDFromPath = nil
  for k in pairs(nativeMode) do nativeMode[k] = "fail" end
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame = nil
  local errs4 = UIx.errorCount
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(not UIx.filterButton.native and UIx.filterButton._text == "Filter" and UIx.filterPopup and not UIx.searchBox.native
    and UIx.searchBox.placeholder and UIx.searchBox.clear and UIx.needsList.ScrollBar and UIx.needsList.minimalBar == nil,
    "fallbacks: red 'Filter' button + popup, the K2 search box, UIPanelScrollFrameTemplate")
  UIx.filterButton._scripts.OnClick(UIx.filterButton)
  local fp = UIx.filterPopup
  check(fp._shown and #fp.buttons == 6 and plain(fp.buttons[5].text._text) == "Include offline members (1)", "fallback Filter popup: 4 toggles, offline members, edit whisper")
  fp.buttons[5]._scripts.OnClick(fp.buttons[5])
  check(GCA.db.settings.needsOffline == true and fp.buttons[5].check._shown, "fallback popup toggles 'Include offline members'")
  fp.buttons[5]._scripts.OnClick(fp.buttons[5]); fp:Hide()
  UIx:SetView("member")
  check(not UIx.modeToggle.native and UIx.modeToggle._text == "View: Character sheet", "fallback view switch: a red button naming the shown variant")
  UIx.modeToggle._scripts.OnClick(UIx.modeToggle)
  check(UIx.MemberMode() == "list" and UIx.modeToggle._text == "View: List", "...a click switches to the other variant")
  UIx.modeToggle._scripts.OnClick(UIx.modeToggle)
  local sdd = UIx.specButton.dropdown
  check(not sdd.native and UIx.specPopup, "fallback spec picker: button + popup")
  sdd._scripts.OnClick(sdd)
  check(UIx.specPopup._shown and #UIx.specPopup.buttons >= 2, "fallback spec popup lists Automatic + the specs")
  UIx.specPopup:Hide()
  check(not UIx.profButton.drop.native and UIx.profPopup and UIx.profButton.drop.arrow._atlas == "common-dropdown-a-button", "fallback profession arrow: plain button + popup")
  UIx.profButton._scripts.OnClick(UIx.profButton)
  local picked
  for _, pbn in ipairs(UIx.profPopup.buttons) do if plain(pbn.text._text):find("^> Leatherworking") then picked = pbn end end
  check(UIx.profPopup._shown and picked and not picked.mark._shown, "no check file: '> ' marks the pick in the fallback popup")
  UIx.profPopup:Hide()
  UIx.filterButton._scripts.OnClick(UIx.filterButton)
  captureTip(); fp.buttons[1]._scripts.OnEnter(fp.buttons[1])
  check(fp._shown and H.tip[1] == plain(fp.buttons[1].text._text) and #H.tip >= 2, "fallback Filter popup rows: the label as tooltip title + the explanation")
  fp.buttons[6]._scripts.OnClick(fp.buttons[6])
  check(not fp._shown and UIx.whisperEditor and UIx.whisperEditor._shown, "fallback Filter popup: 'Edit whisper text' closes the popup and opens the editor")
  UIx.whisperEditor:Hide()
  sdd._scripts.OnClick(sdd)
  local sp, specKey = UIx.specPopup, UIx.current.key
  sp.buttons[2]._scripts.OnClick(sp.buttons[2])
  check(not sp._shown and GCA.db.specManual[specKey] ~= nil, "fallback spec popup: picking a spec closes it and saves the pick")
  sdd._scripts.OnClick(sdd)
  sp.buttons[1]._scripts.OnClick(sp.buttons[1])
  check(not sp._shown and GCA.db.specManual[specKey] == nil, "...'Automatic' clears it again")
  local savedProf = GCA:SelectedProfession()
  UIx.profButton.drop._scripts.OnClick(UIx.profButton.drop)
  local otherProf
  for _, pbn in ipairs(UIx.profPopup.buttons) do
    if pbn._shown and not otherProf and not plain(pbn.text._text):find("^> ") then otherProf = pbn end
  end
  otherProf._scripts.OnClick(otherProf)
  check(not UIx.profPopup._shown and GCA:SelectedProfession() ~= savedProf,
    "fallback profession popup (opened from the arrow): picking another one closes it and selects it")
  GCA:SelectProfession(savedProf)
  UIx:Refresh()
  local g1 = UIx.memberList.pools.group and UIx.memberList.pools.group[1]
  check(g1 and not g1.native and g1.text._text and g1.CollapseButton, "group header: the replicated category row (no template involved)")
  check(UIx.errorCount == errs4, "fallbacks: no error reported")
  UIx.frame:Hide()
  for k in pairs(nativeMode) do nativeMode[k] = "ok" end
  GetFileIDFromPath = nil
  ATLASES[UIx.INFO_ATLAS] = true
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  UIx = GCA.UI
  check(UIx.infoIcon.kind == "atlas" and UIx.infoIcon.tex._atlas == UIx.INFO_ATLAS, "info atlas present: drawn from the atlas (GetAtlasInfo-guarded)")
  UIx.frame:Hide()
  ATLASES[UIx.INFO_ATLAS] = nil
  local made
  MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = "OnValueChanged" } }
  CreateFrame = function(otype, name, parent, template)
    local fr = origCF(otype, name, parent, template)
    if template == "MinimalSliderWithSteppersTemplate" then
      made = fr
      fr.Slider = origCF("Slider", nil, fr)
      function fr:Init(v, lo, hi, steps, fmt) self.init = { v, lo, hi, steps, fmt } ; self._value = v end
      function fr:RegisterCallback(ev, fn, owner) self.cb = { ev, fn, owner } end
      function fr:SetValue(v) local old = self._value; self._value = v; if old ~= v and self.cb then self.cb[2](self.cb[3], v) end end
    end
    return fr
  end
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  CreateFrame = origCF
  UIx = GCA.UI
  local hs = UIx.survival
  check(hs.templated and hs.slider == made and made.init[1] == 50 and made.init[2] == 0 and made.init[3] == 100 and made.init[4] == 20
    and made.cb[1] == "OnValueChanged", "slider template: Init(50, 0, 100, 20 steps) + OnValueChanged callback")
  local inv, realInv = 0, GCA.InvalidateScores
  GCA.InvalidateScores = function(...) inv = inv + 1; return realInv(...) end
  made:SetValue(70); advance(0.1); made:SetValue(75)
  check(hs.label._text:find("75%%") and math.abs(GCA:SurvivalShare() - 0.5) < 1e-9, "template slider: label follows at once, value waits (K0 debounce kept)")
  advance(0.5)
  check(math.abs(GCA:SurvivalShare() - 0.75) < 1e-9 and inv == 1, "...applied once after 0.4 s")
  hs:Sync()
  check(made._value == 75, "Sync sets the template slider's value without firing a change")
  GCA.InvalidateScores = realInv
  GCA.db.settings.survival = 0.5
  captureTip(); local okTip = pcall(made.Slider._scripts.OnEnter, made.Slider)
  check(okTip and tipText():find("Leveling bonus", 1, true), "template slider: our tooltip hooked onto its inner Slider")
  UIx.frame:Hide()
  MinimalSliderWithSteppersMixin = nil
  CreateFrame = function(otype, name, parent, template)
    local fr = origCF(otype, name, parent, template)
    if template == "MinimalSliderWithSteppersTemplate" then fr.Init = function() error("bad") end; fr.RegisterCallback = function() end end
    return fr
  end
  MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = 1 } }
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  CreateFrame = origCF
  MinimalSliderWithSteppersMixin = nil
  check(not GCA.UI.survival.templated and GCA.UI.survival.slider._type == "Slider" and GCA.UI.errorCount == errs,
    "a slider template whose Init fails: plain slider instead, no error")
  GCA.UI.frame:Hide()
  GCA.GetMemberList = origML
  ITEM_QUALITY_COLORS = nil
  PanelTemplates_SelectTab, PanelTemplates_DeselectTab = nil, nil
  HandleModifiedItemClick = function() end
  GCA.UI.frame = nil
  H.templateMode, GCA.IsBrowse = savedTM, savedBrowse
end

H.finish(true)
