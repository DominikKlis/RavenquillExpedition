local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env, GCA, check, section, advance = H.env, H.GCA, H.check, H.section, H.advance
local fakeSug, plain, captureTip, tipText = H.fakeSug, H.plain, H.captureTip, H.tipText
H.lateGlobals()

local roster = { { "Alice Wren", "MAGE", true }, { "Bob Marsh", "WARRIOR", false }, { "Cora Vale", "HUNTER", true } }
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
  local r = roster[i]
  if r then return r[1], "Member", 1, 40, r[2], "Zone", "", "", r[3], 0, r[2] end
end
local function setOnline(i, on)
  roster[i][3] = on
  GCA.RQ:ReadRoster()
  GCA:Invalidate()
  advance(1)
end
GCA.RQ:ReadRoster()
local printed = {}
GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function lastPrinted() return printed[#printed] or "" end

local fakeUpgrades, upgradeGen = {}, 0
GCA.GuildUpgrades = function(_, _, prof) return fakeUpgrades[prof] or {}, upgradeGen end
local function setUpgrades(t) fakeUpgrades, upgradeGen = t, upgradeGen + 1 end
local vestUp = fakeSug({ known = false, points = 12, slot = 5 })
setUpgrades({ Leatherworking = { [3762] = vestUp } })

local UIx = GCA.UI
local function openCrafters()
  UIx.frame = nil
  UIx:Toggle(); advance(1)
  UIx = GCA.UI
  UIx.tabs[3]._scripts.OnClick(UIx.tabs[3])
end
local function listKinds(list)
  local out = {}
  for i, d in ipairs(list.data or {}) do
    if d.rowKind == "all" then out[i] = "*" elseif d.rowKind == "cat" then out[i] = "#" .. d.prof .. ":" .. d.n else out[i] = d.key or d.spellID end
  end
  return table.concat(out, ",")
end
local function recipeRow(spellID)
  for _, b in ipairs(UIx.recipeList.pools.default or {}) do
    if b._shown and b.data and b.data.spellID == spellID then return b end
  end
end
local function crafterRow(key)
  for _, b in ipairs(UIx.crafterList.pools.default or {}) do
    if b._shown and b.data and b.data.key == key then return b end
  end
end
local function typeInto(box, text) box:SetText(text); box._scripts.OnTextChanged(box) end

section("Before anyone shared recipes: the tab explains where the list comes from")
openCrafters()
check(UIx.view == "crafters" and UIx.crafterView._shown and not UIx.memberView._shown and not UIx.needsView._shown,
  "the third tab shows the crafters view and hides the other two")
check(listKinds(UIx.crafterList) == "*" and listKinds(UIx.recipeList) == "", "only the 'All crafters' entry, no recipes")
check(UIx.recipeEmpty._text:find("No guildmate has shared their recipes yet", 1, true)
  and UIx.recipeEmpty._text:find("as they come online", 1, true), "empty text: guildmates need the addon, the list fills as they come online")

GCA:StoreCrafter("Alice Wren", 100, { Leatherworking = { rank = 300, ids = { 3762, 2160 } }, Enchanting = { rank = 225, ids = { 7779 } } })
GCA:StoreCrafter("Bob Marsh", 100, { Leatherworking = { rank = 250, ids = { 3762, 2153 } } })
GCA:StoreCrafter("Cora Vale", 100, { Tailoring = { rank = 120, ids = { 9999999 } } })
GCA:StoreCrafter("Me Stone", 100, { Leatherworking = { rank = 150, ids = { 2149 } } })
advance(1)

section("Left list: All crafters on top, then guildmates online first with their professions")
check(listKinds(UIx.crafterList) == "*,Alice Wren,Cora Vale,Bob Marsh", "the list refreshes when recipes arrive; you are not in it: "
  .. listKinds(UIx.crafterList))
local alice, bob = crafterRow("Alice Wren"), crafterRow("Bob Marsh")
check(plain(alice.name._text) == "Alice Wren" and alice.name._text:find("StatusIcon-Online", 1, true)
  and plain(alice.right._text) == "300  225" and alice.right._text:find("Trade_LeatherWorking", 1, true)
  and alice.right._text:find("Trade_Engraving", 1, true), "Alice: online dot, profession icons with ranks: " .. plain(alice.right._text))
check(bob.name._text:find("StatusIcon-Offline", 1, true) and plain(bob.right._text) == "250", "Bob: offline dot, his rank")
local allRow = UIx.crafterList.pools.all[1]
check(plain(allRow.name._text) == "All crafters" and plain(allRow.right._text) == "3" and allRow.sel._shown and not alice.sel._shown,
  "'All crafters' selected by default, with the number of crafters")
captureTip(); alice._scripts.OnEnter(alice)
check(tipText():find("Alice Wren", 1, true) and tipText():find("recipes: 2", 1, true) and tipText():find("Recipes shared just now", 1, true),
  "crafter tooltip: name, professions with recipe counts, when they were shared: " .. plain(tipText()):gsub("\n", " / "))
typeInto(UIx.crafterSearch, "bo")
check(listKinds(UIx.crafterList) == "*,Bob Marsh", "searching the crafters by name")
typeInto(UIx.crafterSearch, "")

section("All crafters: every recipe once, grouped by profession, groups closed")
check(plain(UIx.crafterName._text) == "All crafters" and plain(UIx.crafterSub._text) == "Crafters: 3 (2 online)  ·  recipes: 4",
  "header: crafters, online, recipes: " .. plain(UIx.crafterSub._text))
check(listKinds(UIx.recipeList) == "#Leatherworking:3,#Enchanting:1", "two closed profession groups with their counts: " .. listKinds(UIx.recipeList))
local cat = UIx.recipeList.pools.cat[1]
check(plain(cat.text._text) == "Leatherworking (3)  1 upgrade for you", "the group names its upgrades: " .. plain(cat.text._text))
cat._scripts.OnClick(cat)
check(listKinds(UIx.recipeList) == "#Leatherworking:3,3762,2160,2153,#Enchanting:1", "opening a group: the upgrade first: " .. listKinds(UIx.recipeList))
local vest = recipeRow(3762)
check(vest.ask._shown and vest.gain._text == "+12" and plain(vest.name._text) == "Hillman's Vest" and plain(vest.skill._text) == "75",
  "row: item name, required skill, gain chip, Ask (Alice is online)")
check(not recipeRow(2153).ask._shown, "only Bob (offline) knows the pants: no Ask")
check(plain(vest.cost._text) == "" and vest.cost._w == 0, "no Auctionator: no cost column")

section("Hover: item, upgrade, reagents and who can craft it")
captureTip(); vest._scripts.OnEnter(vest)
local tip = tipText()
check(H.hyper[1] and H.hyper[1]:find("item:4244", 1, true) and tip:find("Leatherworking  ·  Skill 75", 1, true)
  and tip:find("Upgrade for you: +12", 1, true) and tip:find("Reagents:", 1, true) and tip:find("Guildmates who can craft it", 1, true)
  and tip:find("Alice Wren | online", 1, true) and tip:find("Bob Marsh | offline", 1, true), "tooltip: " .. tip:gsub("\n", " / "))
local linked
env.HandleModifiedItemClick = function(l) linked = l end
env.IsShiftKeyDown = function() return true end
vest._scripts.OnClick(vest, "LeftButton")
env.IsShiftKeyDown = function() return false end
check(linked == "|Hitem:4244|h[Hillman's Vest]|h", "shift-click links the item: " .. tostring(linked))

section("Ask: whispers the first online crafter with the item link")
vest.ask._scripts.OnClick(vest.ask)
check(lastPrinted():find("Hi Alice! Could you craft |Hitem:4244|h[Hillman's Vest]|h for me? I'd bring the materials.", 1, true),
  "Ask writes the whisper to Alice: " .. lastPrinted())
captureTip(); vest.ask._scripts.OnEnter(vest.ask)
check(tipText():find("Ask Alice to craft it for you", 1, true), "Ask tooltip names Alice")
env.Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return ({ [4243] = 1000, [4231] = 300 })[id] end,
  GetVendorPriceByItemID = function(_, id) return ({ [2320] = 10 })[id] end,
} } }
local sent
env.IsShiftKeyDown = function() return true end
env.SendChatMessage = function(msg, kind, _, name) sent = { msg = msg, kind = kind, name = name } end
UIx:RefreshCrafters()
vest = recipeRow(3762)
vest.ask._scripts.OnClick(vest.ask)
env.IsShiftKeyDown, env.SendChatMessage = function() return false end, nil
check(sent and sent.name == "Alice Wren" and sent.kind == "WHISPER" and lastPrinted() == "Asked Alice Wren."
  and sent.msg:find("I'd bring the materials (about 16s 20c on the AH).", 1, true),
  "shift-click sends right away and names the mat cost (1000 + 2x300 + 2x10 vendor): " .. tostring(sent and sent.msg))
check(plain(vest.cost._text) == "16s 20c" and vest.cost._w > 0, "with Auctionator the row shows the mat cost")
captureTip(); vest._scripts.OnEnter(vest)
tip = plain(tipText())
check(tip:find("0/1 Hillman's Vest | 10s", 1, true) and tip:find("0/2 Hillman's Vest | 6s", 1, true) and tip:find("0/2 Hillman's Vest | 20c", 1, true)
  and tip:find("To craft: 16s 20c", 1, true), "reagent lines with have/need and their price, then the total: " .. tip:gsub("\n", " / "))
env.Auctionator = nil
setOnline(1, false)
vest = recipeRow(3762)
check(not vest.ask._shown, "Alice logs off and Bob is offline: no Ask")
setOnline(1, true)

section("One crafter: their recipes, groups open, Ask goes to them")
crafterRow("Bob Marsh")._scripts.OnClick(crafterRow("Bob Marsh"))
check(UIx.crafterSel == "Bob Marsh" and crafterRow("Bob Marsh").sel._shown and not UIx.crafterList.pools.all[1].sel._shown,
  "clicking Bob selects him")
check(plain(UIx.crafterName._text) == "Bob Marsh" and plain(UIx.crafterSub._text):find("Leatherworking 250  ·  Offline  ·  recipes shared just now", 1, true),
  "header: name, professions with ranks, status, when shared: " .. plain(UIx.crafterSub._text))
check(listKinds(UIx.recipeList) == "#Leatherworking:2,3762,2153", "Bob's two recipes, the group open: " .. listKinds(UIx.recipeList))
check(not recipeRow(3762).ask._shown, "Bob is offline: no Ask, even though Alice could craft it")
crafterRow("Alice Wren")._scripts.OnClick(crafterRow("Alice Wren"))
check(listKinds(UIx.recipeList) == "#Leatherworking:2,3762,2160,#Enchanting:1,7779", "Alice: both professions open")
local ench = recipeRow(7779)
ench.ask._scripts.OnClick(ench.ask)
check(plain(ench.name._text) == "Enchant Bracer - Minor Agility" and lastPrinted():find("Hi Alice! Could you do Enchant Bracer - Minor Agility for me when we meet?", 1, true),
  "an enchant row and its whisper: " .. lastPrinted())

section("Filters: search, only upgrades, and what they say when nothing is left")
typeInto(UIx.recipeSearch, "vest")
check(listKinds(UIx.recipeList) == "#Leatherworking:2,3762,2160", "searching 'vest': both vests in their group")
typeInto(UIx.recipeSearch, "dragon")
check(listKinds(UIx.recipeList) == "" and UIx.recipeEmpty._text == 'No recipe matches "dragon".', "no match: " .. UIx.recipeEmpty._text)
typeInto(UIx.recipeSearch, "")
UIx.upgradesOnly:SetChecked(true)
UIx.upgradesOnly._scripts.OnClick(UIx.upgradesOnly)
check(listKinds(UIx.recipeList) == "#Leatherworking:1,3762" and UIx.recipeEmpty._text == "", "only upgrades for me: Hillman's vest")
crafterRow("Cora Vale")._scripts.OnClick(crafterRow("Cora Vale"))
check(listKinds(UIx.recipeList) == "" and UIx.recipeEmpty._text:find("Cora Vale shares no recipe the advisor has data for", 1, true),
  "Cora shares only a recipe without data: " .. UIx.recipeEmpty._text)
UIx.crafterList.pools.all[1]._scripts.OnClick(UIx.crafterList.pools.all[1])
check(UIx.upgradesOnly._checked and listKinds(UIx.recipeList) == "#Leatherworking:1" and UIx.recipeEmpty._text == "",
  "back on All crafters the toggle stays on, the group closed again")
setUpgrades({})
UIx:RefreshCrafters()
check(listKinds(UIx.recipeList) == "" and UIx.recipeEmpty._text == "None of these crafts would be an upgrade for you.", "no upgrade at all: says so")
UIx.upgradesOnly:SetChecked(false)
UIx.upgradesOnly._scripts.OnClick(UIx.upgradesOnly)
check(listKinds(UIx.recipeList) == "#Leatherworking:3,3762,2160,2153,#Enchanting:1,7779", "toggle off: every recipe again, groups open")

section("A crafter who leaves the guild drops out, the selection falls back to All")
crafterRow("Bob Marsh")._scripts.OnClick(crafterRow("Bob Marsh"))
table.remove(roster, 2)
GCA.RQ:ReadRoster()
UIx:RefreshCrafters()
check(UIx.crafterSel == nil and listKinds(UIx.crafterList) == "*,Alice Wren,Cora Vale" and UIx.crafterList.pools.all[1].sel._shown,
  "Bob left: gone from the list, All crafters selected")

section("German texts")
H.ns.locale = "deDE"
openCrafters()
check(UIx.tabs[3]._text == "Handwerker" and plain(UIx.crafterName._text) == "Alle Handwerker" and UIx.upgradesOnly.label._text == "Nur Verbesserungen für mich",
  "tab, header and toggle in German")
H.ns.locale = "enUS"
UIx.frame:Hide()

check((UIx.errorCount or 0) == 0, "no error reported")
H.finish()
