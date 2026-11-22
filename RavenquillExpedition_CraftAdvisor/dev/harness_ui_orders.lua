local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env, GCA, check, section, advance = H.env, H.GCA, H.check, H.section, H.advance
local plain, layoutChecks = H.plain, H.layoutChecks
H.lateGlobals()

local roster = { { "Alice Wren", "MAGE", true }, { "Bob Marsh", "WARRIOR", true }, { "Cora Vale", "HUNTER", true } }
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i)
  local r = roster[i]
  if r then return r[1], "Member", 1, 40, r[2], "Zone", "", "", r[3], 0, r[2] end
end
env.RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 } }
GCA.RQ:ReadRoster()
local printed = {}
GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
local REAGENTS = { [4243] = "Fine Leather Tunic", [4231] = "Cured Light Hide", [2320] = "Coarse Thread" }
GCA.ItemAPI.NameByID = function(id) return REAGENTS[id] end
GCA.ItemAPI.Count = function(id) return ({ [4231] = 3 })[id] or 0 end
GCA:StoreCrafter("Bob Marsh", 100, { Leatherworking = { rank = 250, ids = { 3762, 3763 } } })

local LW = "Leatherworking"
local function incoming(from, id, crafter, spell, state, gain)
  return GCA:MergeOrder(from, { requester = from, id = id, crafter = crafter, prof = LW, spell = spell, state = state, gain = gain })
end
local toMe = incoming("Alice Wren", 101, "Me Stone", 3762, "requested", 18)
local mine = GCA:PlaceOrder("Bob Marsh", LW, 3763, 7)
GCA:MergeOrder("Bob Marsh", { requester = "Me Stone", id = mine.id, crafter = "Bob Marsh", prof = LW, spell = 3763, state = "done" })
GCA:MergeOrder("Cora Vale", { requester = "Alice Wren", id = 102, crafter = "Cora Vale", prof = LW, spell = 3762, state = "accepted" })
local closed = incoming("Alice Wren", 103, "Me Stone", 2160, "requested")
GCA:OrderAction(closed, "decline")

local UIx = GCA.UI
local function openOrders()
  UIx.frame = nil
  UIx:Toggle(); advance(1)
  UIx = GCA.UI
  UIx.tabs[4]._scripts.OnClick(UIx.tabs[4])
end
local function rows(list) local out = {} for _, b in ipairs(list.pools.default or {}) do if b._shown then out[#out + 1] = b end end return out end
local function card(o)
  for _, b in ipairs(UIx.orderCards.pools.default or {}) do
    if b._shown and b.data and b.data.order == o then return b end
  end
end
local function kinds()
  local out = {}
  for i, d in ipairs(UIx.orderCards.data or {}) do
    out[i] = d.rowKind == "head" and ("#" .. d.list .. ":" .. d.n) or d.rowKind == "empty" and "-" or d.order.state
  end
  return table.concat(out, ",")
end
local function heldBy(key) local b = UIx.orderCards.pools.head; for _, h in ipairs(b or {}) do if h._shown and h.data.list == key then return h end end end

section("A fourth tab, Orders, with its four lists")
openOrders()
check(UIx.tabs[4]._text == "Orders" and UIx.view == "orders" and UIx.ordersView._shown and not UIx.memberView._shown
  and not UIx.needsView._shown and not UIx.crafterView._shown, "the fourth tab 'Orders' shows the orders view alone")
local left = rows(UIx.orderLists)
local names = {}
for i, b in ipairs(left) do names[i] = plain(b.name._text) .. " " .. plain(b.right._text) end
check(table.concat(names, "|") == "To me 1|From me 1|Open in the guild 1|Finished 1" and left[1].sel._shown and not left[2].sel._shown,
  "left: To me, From me, Open in the guild, Finished with their counts, 'To me' selected: " .. table.concat(names, "|"))
check(plain(UIx.ordersTitle._text) == "Orders" and UIx.ordersHint._text == "Requests for your recipes land here automatically.",
  "title above the lists, the hint at the bottom")
check(kinds() == "#tome:1,requested,#mine:1,done,#guild:1,accepted,#finished:1,declined", "right: every list as a section: " .. kinds())
local head = heldBy("tome")
check(plain(head.title._text) == "To me (1)" and head.sub._text == "Guildmates ask you to craft something. Accepting tells them.",
  "section head 'To me (1)' with what it holds")

section("Cards: item, for whom, the gain, materials with what you have, who brings them, the status pill")
local c1 = card(toMe)
check(plain(c1.name._text) == "Hillman's Vest" and c1.icon._tex == 134, "name and icon of the crafted item")
check(plain(c1.who._text) == "for Alice Wren  ·  +18 pts" and c1.who._text:find("|cff69ccf0Alice Wren", 1, true) ~= nil,
  "for whom (class-coloured) and the gain: " .. plain(c1.who._text))
check(plain(c1.mats._text) == "Materials: 1× Fine Leather Tunic, 2× Cured Light Hide (you have 3), 2× Coarse Thread  ·  Alice brings them",
  "reagents from the recipe data, 'you have 3' from your bags, who brings them: " .. plain(c1.mats._text))
check(c1.pill.text._text == "Asked" and c1.pill._shown and c1.primary._shown and c1.primary._text == "Accept"
  and c1.secondary._shown and c1.secondary._text == "Decline", "pill 'Asked', buttons Decline and Accept")
local c2 = card(mine)
check(plain(c2.who._text) == "by Bob Marsh (Leatherworking 250)  ·  +7 pts" and plain(c2.mats._text):find("you bring them$") ~= nil,
  "your own order: by whom with his rank, and you bring the materials: " .. plain(c2.who._text))
check(c2.pill.text._text == "Done" and c2.primary._text == "Got it" and c2.primary._shown and not c2.secondary._shown,
  "done: pill 'Done', one button 'Got it'")
local guildOrder = GCA:OrderLists().guild[1]
local c3 = card(guildOrder)
check(plain(c3.who._text) == "for Alice Wren  ·  by Cora Vale" and c3.pill.text._text == "Accepted" and not c3.primary._shown
  and not c3.secondary._shown, "someone else's order: both names, the pill, no buttons")
check(card(closed).pill.text._text == "Declined" and not card(closed).primary._shown, "finished: 'Declined', no buttons")

section("Buttons move the order")
c1.primary._scripts.OnClick(c1.primary)
c1 = card(toMe)
check(toMe.state == "accepted" and c1.pill.text._text == "Accepted" and c1.primary._text == "Done" and c1.secondary._text == "Decline",
  "Accept: pill 'Accepted', now Decline and Done")
c2.primary._scripts.OnClick(c2.primary)
check(mine.state == "received" and kinds() == "#tome:1,accepted,#mine:0,-,#guild:1,accepted,#finished:2,received,declined",
  "Got it: received, moved to Finished; 'From me' says it is empty: " .. kinds())
local empty = UIx.orderCards.pools.empty[1]
check(empty._shown and empty.text._text == "No orders here.", "the empty list's line")

section("The left list jumps to its section")
for i = 1, 8 do
  local o = incoming("Alice Wren", 200 + i, "Me Stone", 3762, "requested")
  GCA:OrderAction(o, "decline")
end
UIx:RefreshOrders()
left = rows(UIx.orderLists)
left[4]._scripts.OnClick(left[4])
local want = 3 * UIx.ORDER_HEAD_H + 2 * UIx.ORDER_CARD_H + UIx.ORDER_EMPTY_H
check(UIx.orderList == "finished" and left[4].sel._shown and not left[1].sel._shown and UIx.orderCards.scrolledTo == want,
  ("'Finished' selected, the cards scrolled to its head (%s, want %d)"):format(tostring(UIx.orderCards.scrolledTo), want))
left[1]._scripts.OnClick(left[1])
check(UIx.orderList == "tome" and UIx.orderCards.scrolledTo == 0, "'To me' scrolls back to the top")

section("The card tooltip is the recipe's")
H.captureTip()
c1._scripts.OnEnter(c1)
check(H.tipText():find("Reagents:", 1, true) ~= nil and H.tipText():find("0/1 Fine Leather Tunic", 1, true) ~= nil,
  "hovering a card shows the item and its reagents with have/need: " .. H.tipText():gsub("\n", " / "))

section("German")
H.ns.locale = "deDE"
openOrders()
left = rows(UIx.orderLists)
names = {}
for i, b in ipairs(left) do names[i] = plain(b.name._text) end
check(UIx.tabs[4]._text == "Aufträge" and table.concat(names, "|") == "An mich|Von mir|Offen in der Gilde|Erledigt"
  and plain(UIx.ordersTitle._text) == "Aufträge", "tab, title and lists: " .. table.concat(names, "|"))
c1 = card(toMe)
check(plain(heldBy("tome").title._text) == "An mich (1)" and c1.pill.text._text == "Angenommen" and c1.primary._text == "Fertig"
  and c1.secondary._text == "Ablehnen", "head 'An mich (1)', pill 'Angenommen', buttons Ablehnen and Fertig")
check(plain(c1.who._text) == "für Alice Wren  ·  +18 Pkt"
  and plain(c1.mats._text) == "Material: 1× Fine Leather Tunic, 2× Cured Light Hide (du hast 3), 2× Coarse Thread  ·  bringt Alice mit",
  "German card lines: " .. plain(c1.who._text) .. " / " .. plain(c1.mats._text))
local pills = {}
for state, def in pairs(UIx.ORDER_PILLS) do pills[#pills + 1] = state .. "=" .. H.ns.Locales.deDE[def.label] end
table.sort(pills)
check(table.concat(pills, ",") == "accepted=Angenommen,declined=Abgelehnt,done=Fertig,received=Erhalten,requested=Angefragt,withdrawn=Zurückgezogen",
  "every pill has a German text: " .. table.concat(pills, ","))
for _, sz in ipairs({ { 840, 560 }, { 980, 640 } }) do
  UIx.frame:SetSize(sz[1], sz[2]); UIx:Layout()
  layoutChecks(UIx, UIx.frame, "German " .. sz[1] .. "x" .. sz[2])
end
H.ns.locale = "enUS"
UIx.frame:Hide()

section("/rq home: orders waiting on you are one row with 'View'")
local row = GCA:OverviewNow()[1]
check(row and row.title == "Orders" and row.line == "1 order to you" and row.action == "View",
  "the accepted order to you, still to be crafted, is one row: " .. tostring(row and row.line))
local ready = GCA:PlaceOrder("Bob Marsh", LW, 3762, 5)
GCA:MergeOrder("Bob Marsh", { requester = "Me Stone", id = ready.id, crafter = "Bob Marsh", prof = LW, spell = 3762, state = "done" })
row = GCA:OverviewNow()[1]
check(row and row.line == "1 order to you · Hillman's Leather Vest is ready for you" and #GCA:OverviewNow() == 1,
  "an order crafted for you joins the same row: " .. tostring(row and row.line))
UIx.frame:Hide()
UIx.orderList = "finished"
row.open()
UIx = GCA.UI
check(UIx.frame:IsShown() and UIx.view == "orders" and UIx.orderList == "tome",
  "'View' opens the Orders tab on 'To me'")
GCA:OrderAction(toMe, "done")
row = GCA:OverviewNow()[1]
check(row and row.line == "Hillman's Leather Vest is ready for you", "with only the crafted order left: " .. tostring(row and row.line))
UIx.frame:Hide()
row.open()
check(UIx.frame:IsShown() and UIx.view == "orders" and UIx.orderList == "mine", "'View' then opens 'From me'")
GCA:OrderAction(ready, "receive")
check(#GCA:OverviewNow() == 0, "nothing waiting on you: no row")

check((UIx.errorCount or 0) == 0, "no error reported")
H.finish()
