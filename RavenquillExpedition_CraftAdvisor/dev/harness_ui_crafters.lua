local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env, GCA, check, section, advance = H.env, H.GCA, H.check, H.section, H.advance
local fakeSug, plain, captureTip, tipText = H.fakeSug, H.plain, H.captureTip, H.tipText
H.lateGlobals()

local roster = { { "Alice Wren", true }, { "Bob Marsh", false } }
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
  local r = roster[i]
  if r then return r[1], "Member", 1, 40, "WARRIOR", "Zone", "", "", r[2], 0, "WARRIOR" end
end
local function setOnline(i, on) roster[i][2] = on; GCA.RQ:ReadRoster() end
GCA.RQ:ReadRoster()
local printed = {}
GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function lastPrinted() return printed[#printed] or "" end

section("Opening the window asks guildmates for their recipes")
local asked = 0
GCA.RequestCrafters = function() asked = asked + 1 end
GCA.UI:Toggle(); advance(1)
GCA.UI:Toggle(); GCA.UI:Toggle(); advance(1)
check(asked == 2, "each time the window opens it asks (the sync side limits it to once per 15 min): " .. asked)
GCA.RequestCrafters = nil

local UIx = GCA.UI
local function show(d, cur)
  UIx.current = cur
  UIx.sugList:SetData({ d })
  return UIx.sugList.pools.default[1]
end
local me = { key = "Me Stone", isSelf = true, online = true, prof = "Leatherworking", browse = true, level = 36, class = "ROGUE" }
GCA:StoreCrafter("Alice Wren", 100, { Leatherworking = { rank = 300, ids = { 3762, 3763 } }, Enchanting = { rank = 300, ids = { 7779 } } })
GCA:StoreCrafter("Bob Marsh", 100, { Leatherworking = { rank = 300, ids = { 3762 } } })

section("List row: an upgrade for you that you can't craft names who can, with Ask")
local d = fakeSug({ known = false })
local b = show(d, me)
check(plain(b.nl.text._text) == "Crafted by Alice (online) +1" and b.nl.text._text:find("|cff66dd88", 1, true) ~= nil,
  "badge: 'Crafted by Alice (online) +1' in green: " .. plain(b.nl.text._text))
check(b.offer._shown and b.offer._text == "Ask" and not b.crafted._shown, "the row's button says Ask; no crafted box")
b.offer._scripts.OnClick(b.offer)
check(lastPrinted():find("Hi Alice! Could you craft |Hitem:4244|h[Hillman's Leather Vest]|h for me? I'd bring the materials.", 1, true) ~= nil,
  "Ask writes the whisper to Alice with the item link: " .. lastPrinted())
captureTip(); b.offer._scripts.OnEnter(b.offer)
local tip = tipText()
check(H.tip[1] == "Ask" and tip:find("Ask Alice to craft it for you", 1, true) and tip:find("Guildmates who can craft it", 1, true)
  and tip:find("Alice Wren | online", 1, true) and tip:find("Bob Marsh | offline", 1, true), "Ask tooltip: whom it asks and every crafter: " .. tip)
captureTip(); b.nl._scripts.OnEnter(b.nl)
tip = tipText()
check(tip:find("Not learned", 1, true) and tip:find("Alice Wren | online", 1, true) and tip:find("Bob Marsh | offline", 1, true),
  "badge tooltip lists the crafters above the recipe sources")
local sentTo
env.IsShiftKeyDown = function() return true end
env.SendChatMessage = function(msg, kind, _, name) sentTo = { msg = msg, kind = kind, name = name } end
b.offer._scripts.OnClick(b.offer)
env.IsShiftKeyDown, env.SendChatMessage = function() return false end, nil
check(sentTo and sentTo.name == "Alice Wren" and sentTo.kind == "WHISPER" and lastPrinted() == "Asked Alice Wren.",
  "Shift-click sends it right away and says so: " .. lastPrinted())

section("Who is offered: online first; offline only means no Ask")
setOnline(1, false)
b = show(d, me)
check(plain(b.nl.text._text) == "Crafted by Alice (offline) +1" and b.nl.text._text:find("|cff9d9d9d", 1, true) ~= nil and not b.offer._shown,
  "everyone offline: grey badge, no Ask: " .. plain(b.nl.text._text))
setOnline(2, true)
b = show(d, me)
check(plain(b.nl.text._text) == "Crafted by Bob (online) +1" and b.offer._shown, "Bob comes online: he leads and Ask asks him")
setOnline(1, true); setOnline(2, false)

section("Rows without guild crafters keep their old look")
local nobody = fakeSug({ known = false, cand = { spellID = 4000, itemID = 4244, recipe = { skill = 100, src = "trainer", r = {} } } })
b = show(nobody, me)
check(not plain(b.nl.text._text):find("Crafted by", 1, true) and not b.offer._shown, "nobody knows it: the source badge, no button")
b = show(fakeSug({ known = true }), { key = "Me Stone", isSelf = true, online = true, prof = "Leatherworking" })
check(not b.nl._shown and not b.offer._shown, "your own known recipe: no badge, no button")
local bud = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
b = show(d, bud)
check(not plain(b.nl.text._text):find("Crafted by", 1, true) and not b.offer._shown,
  "a guildmate's row in your own profession: where to learn it, as before")
b = show(fakeSug({ known = true }), bud)
check(b.offer._shown and b.offer._text == "Offer", "a known recipe for an online guildmate: still Offer")
b = show(d, { key = "Bud Stone", online = true, prof = "Leatherworking", browse = true, level = 39, class = "ROGUE" })
check(plain(b.nl.text._text) == "Crafted by Alice (online) +1" and not b.offer._shown, "browsing for a guildmate: who can craft it, no Ask")

section("Enchants: Ask names the enchant and the slot")
local ench = fakeSug({ kind = "enchant", known = false, slot = 9, enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" },
  cand = { spellID = 7779, enchant = true, recipe = { skill = 100, src = "trainer", r = {} } },
  info = { name = "Enchant Bracer - Minor Agility", quality = 1, icon = "x" } })
b = show(ench, { key = "Me Stone", isSelf = true, online = true, prof = "Enchanting", browse = true, level = 36, class = "ROGUE" })
b.offer._scripts.OnClick(b.offer)
check(b.offer._text == "Ask" and lastPrinted():find("Hi Alice! Could you put Enchant Bracer - Minor Agility on my " .. UIx.SlotName(9) .. " when we meet?", 1, true) ~= nil,
  "enchant whisper: " .. lastPrinted())

section("Character sheet: the craft card and its alternatives offer Ask too")
do
  local E = { key = "k4", set = { weights = { Agility = 1 }, source = {} }, raw = { source = { kind = "sim", minLevel = 30, maxLevel = 40 } },
    class = "ROGUE", spec = "COMBAT", level = 36, share = 0.5, t = 1 }
  local worn = { name = "Worn Vest", quality = 2, icon = 134, link = "|Hitem:9|h[Worn Vest]|h", cstats = {}, scores = {} }
  local items, eqInfo = { [5] = "item:4244" }, { [5] = worn }
  local s1 = fakeSug({ e = E, known = false, equipped = worn, sortPct = 12,
    info = { name = "Hillman's Leather Vest", link = "|Hitem:4244|h[Hillman's Leather Vest]|h", quality = 2, icon = "x", minLevel = 20, cstats = { Agility = 6 } } })
  local s2 = fakeSug({ e = E, known = false, extra = true, equipped = worn, sortPct = 5,
    cand = { spellID = 3763, itemID = 4245, recipe = { skill = 100, src = "trainer", r = {} } },
    info = { name = "Second Vest", quality = 2, icon = "x", minLevel = 20, cstats = { Agility = 2 } } })
  local list = { s1, s2 }
  list.sections = GCA:BuildSections({ [5] = { s1, s2 } }, {}, items, eqInfo, {}, E)
  local self = { key = "Me Stone", isSelf = true, online = true, class = "ROGUE", level = 36, prof = "Leatherworking", browse = true,
    state = "ok", weights = E, member = { items = items, time = env.time(), source = "self" }, suggestions = list, best = list[1],
    knownCount = 0, spec = "COMBAT", specHow = "manual" }
  local origML = GCA.GetMemberList
  GCA.GetMemberList = function() return { self } end
  GCA.db.settings.memberView = "sheet"
  UIx.selected, UIx.autoKey = "Me Stone", nil
  UIx:SetView("member")
  local sh = UIx.sheet
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  local c = sh.centre
  check(UIx.current == self and c.featured == s1 and c.offer._shown and c.offer._text == "Ask"
    and plain(c.source.text._text) == "Crafted by Alice (online) +1" and not c.crafted._shown,
    "craft card: who can craft it and Ask: " .. plain(c.source.text._text))
  check(c.alts[1].data == s2 and c.alts[1].offer._shown and c.alts[1].offer._text == "Ask" and plain(c.alts[1].tag._text) == "Crafted by Alice (online)",
    "alternative row: badge and Ask: " .. plain(c.alts[1].tag._text))
  c.offer._scripts.OnClick(c.offer)
  check(lastPrinted():find("Hi Alice! Could you craft |Hitem:4244", 1, true) ~= nil, "card Ask writes the whisper for the featured craft")
  GCA.GetMemberList = origML
end

check((UIx.errorCount or 0) == 0, "no error reported")
H.finish()
