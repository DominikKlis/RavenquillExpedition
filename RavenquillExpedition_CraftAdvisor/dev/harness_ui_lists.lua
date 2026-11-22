local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env = H.env
local GCA, fakeSug, fakeSections, check, advance = H.GCA, H.fakeSug, H.fakeSections, H.check, H.advance
local plain, captureTip, rectOf, rstr, ns = H.plain, H.captureTip, H.rectOf, H.rstr, H.ns
H.lateGlobals()
H.templateMode = "ok"
GCA.IsBrowse = function() return false end
env.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }

local GAME_FONT_PX_PER_CHAR = 6.8
local MUTED = "|cffaaaaaa"

local function Craft(id, slot, name, points)
  return fakeSug({ slot = slot, points = points, pct = points / 100,
    cand = { spellID = id, itemID = id, recipe = { skill = 100, src = "trainer", r = {} } },
    info = { name = name, quality = 2, icon = "x", minLevel = 20, link = "|Hitem:" .. id .. "|h[" .. name .. "]|h" } })
end

local function Member(key, class, rowsBySlot)
  local list = fakeSections(rowsBySlot)
  table.sort(list, GCA.SuggestionOrder)
  return { key = key, online = true, class = class, level = 39, prof = "Leatherworking", state = "ok", knownCount = #list,
    member = { items = {}, time = env.time(), source = "inspect" }, suggestions = list, best = list[1] }
end

local SCENE = {
  weste = { 8211, 5, "Wildlederweste" }, tunika = { 8175, 5, "Tunika des Nachtschleichers" },
  skorpidHand = { 8204, 10, "Zähe Skorpidhandschuhe" }, schildHand = { 8187, 10, "Schildkrötenschuppenhandschuhe" },
  helm = { 8214, 1, "Wildlederhelm" }, stirnband = { 8176, 1, "Stirnband des Nachtschleichers" },
  schultern = { 8207, 3, "Zähe Skorpidschultern" }, stiefel = { 8213, 8, "Wildlederstiefel" },
  hose = { 8193, 7, "Hose des Nachtschleichers" },
}
local function SceneCraft(key, points)
  local c = SCENE[key]
  return Craft(c[1], c[2], c[3], points)
end

local hanne = Member("Hanne Moosgrund", "ROGUE", {
  [5] = { SceneCraft("weste", 21), SceneCraft("tunika", 4) }, [10] = { SceneCraft("skorpidHand", 18) },
  [1] = { SceneCraft("helm", 14), SceneCraft("stirnband", 12) }, [3] = { SceneCraft("schultern", 11) },
  [8] = { SceneCraft("stiefel", 9) }, [7] = { SceneCraft("hose", 15) } })
local ole = Member("Ole Fichtental", "DRUID", {
  [5] = { SceneCraft("tunika", 6) }, [10] = { SceneCraft("schildHand", 7) } })
local MEMBERS = { hanne, ole }
GCA.GetMemberList = function() return MEMBERS end

local function OpenAdvisor(locale, w, h)
  ns.locale = locale
  if GCA.UI.frame then GCA.UI.frame:Hide() end
  GCA.UI.frame = nil
  GCA.needsCache = nil
  GCA.UI.selected, GCA.UI.autoKey = nil, nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  UIx.frame:SetSize(w, h); UIx:Layout()
  return UIx
end

local function RowRect(part, row, rowW)
  local savedW = row._w
  row._w = rowW
  local r = rectOf(part, row)
  row._w = savedW
  return r
end

local function ShownRows(list, kind)
  local rows = {}
  for _, r in ipairs(list.pools[kind or "default"] or {}) do if r._shown and r.data then rows[#rows + 1] = r end end
  return rows
end

local function Chars(s) return #plain(s):gsub("[\128-\191]", "") end

local function CraftRowColumns(UIx)
  local nl = UIx.needsList
  local short, mixed, counts, rights = {}, {}, {}, {}
  for _, row in ipairs(ShownRows(nl)) do
    local name = plain(row.label._text)
    local lr, cr, gr = RowRect(row.label, row, nl.viewW), RowRect(row.count, row, nl.viewW), RowRect(row.gain, row, nl.viewW)
    if lr.r - lr.l < Chars(name) * GAME_FONT_PX_PER_CHAR then short[#short + 1] = name .. " (" .. (lr.r - lr.l) .. " px)" end
    if not (lr.r <= cr.l and cr.r <= gr.l and row.count._SetJustifyH[1] == "RIGHT") then mixed[#mixed + 1] = name .. " " .. rstr(lr) .. rstr(cr) .. rstr(gr) end
    counts[#counts + 1] = name .. "=" .. plain(row.count._text)
    rights[cr.r] = true
  end
  local nRights = 0
  for _ in pairs(rights) do nRights = nRights + 1 end
  return short, mixed, table.concat(counts, ","), nRights
end

do
  H.section("Guild needs: every craft name in full at the default size, the member count in words in its own column")
  local UIx = OpenAdvisor("deDE", 980, 640)
  UIx:SetView("needs")
  local short, mixed, counts, nRights = CraftRowColumns(UIx)
  check(#ShownRows(UIx.needsList) == 9 and #short == 0,
    "980x640 deDE: no craft name of the scene is cut (" .. GAME_FONT_PX_PER_CHAR .. " px per character): " .. table.concat(short, "; "))
  check(counts:find("Tunika des Nachtschleichers=2 Mitglieder", 1, true) and counts:find("Wildlederweste=1 Mitglied", 1, true)
    and not counts:find("[", 1, true) and #mixed == 0 and nRights == 1,
    "the member count reads '1 Mitglied' / '2 Mitglieder', right-aligned in one column between the name and the gain: " .. counts
    .. " " .. table.concat(mixed, "; "))
  local count1 = ShownRows(UIx.needsList)[1].count._text
  check(count1:find(MUTED, 1, true) == 1, "the member count is grey beside the white name: " .. count1)

  UIx = OpenAdvisor("enUS", 980, 640)
  UIx:SetView("needs")
  local _, enMixed, enCounts = CraftRowColumns(UIx)
  check(enCounts:find("Tunika des Nachtschleichers=2 members", 1, true) and enCounts:find("Wildlederweste=1 member,", 1, true) and #enMixed == 0,
    "English: '1 member' / '2 members' in the same column: " .. enCounts)

  H.section("Guild needs at the minimum size: the detail keeps its room, a cut name is in full in the tooltip")
  UIx = OpenAdvisor("deDE", 840, 560)
  UIx:SetView("needs")
  local ni, nd = rectOf(UIx.needsInset, UIx.frame), rectOf(UIx.needDetail, UIx.frame)
  short, mixed = CraftRowColumns(UIx)
  check(ni.r - ni.l > 260 and nd.r - nd.l >= 500 and nd.r <= 840 - 12 and #mixed == 0,
    "840x560: the list wider than the member view's 260, the detail at least 500 wide, name | count | gain still apart " .. rstr(ni) .. " " .. rstr(nd))
  local cut
  for _, row in ipairs(ShownRows(UIx.needsList)) do
    if plain(row.label._text) == "Stirnband des Nachtschleichers" then cut = row end
  end
  captureTip(); cut._scripts.OnEnter(cut)
  check(#short > 0 and cut and H.hyper[1] == "|Hitem:8176|h[Stirnband des Nachtschleichers]|h",
    "a name too long for the narrow list: its row tooltip is the item, titled with the full name: " .. tostring(H.hyper[1]))
end

local NO_RECT = { l = 0, t = 0, r = 0, b = 0 }
local function LabelOf(crafted) return crafted.label or { _text = "", IsVisible = function() return false end } end

local function CraftedParts(row, rowW)
  local label = row.crafted.label and RowRect(row.crafted.label, row, rowW) or NO_RECT
  return RowRect(row.crafted, row, rowW), label, RowRect(row.offer, row, rowW)
end

local function LabelBetweenBoxAndOffer(box, label, offer)
  return label ~= NO_RECT and box.r < label.l and label.r <= offer.l
end

do
  H.section("Crafted box with its label in the member list, the character sheet and the needs detail")
  local UIx = OpenAdvisor("enUS", 980, 640)
  UIx.selected, UIx.autoKey = "Hanne Moosgrund", nil
  UIx:SetView("member")
  UIx:SetMemberMode("list")
  local card = ShownRows(UIx.sugList)[1]
  local cbox, clabel, coffer = CraftedParts(card, UIx.sugList.viewW)
  check(card.crafted._shown and LabelOf(card.crafted):IsVisible() and plain(LabelOf(card.crafted)._text) == "Crafted"
    and LabelBetweenBoxAndOffer(cbox, clabel, coffer) and RowRect(card.gain, card, UIx.sugList.viewW).r <= cbox.l
    and RowRect(card.title, card, UIx.sugList.viewW).r <= RowRect(card.gain, card, UIx.sugList.viewW).l,
    "member list: 'Crafted' beside its box, between the gain and 'Offer', the title clear of them " .. rstr(cbox) .. rstr(clabel) .. rstr(coffer))
  check(LabelOf(card.crafted)._text == MUTED .. "Crafted|r" and not card.crafted._checked, "unticked: the label is grey")
  local spell = card.data.cand.spellID
  card.crafted:SetChecked(true); card.crafted._scripts.OnClick(card.crafted)
  card = ShownRows(UIx.sugList)[1]
  check(GCA:CraftedMark("Hanne Moosgrund", "Leatherworking", spell) ~= nil and card.crafted._checked and LabelOf(card.crafted)._text == "Crafted",
    "ticking the list box stores the reminder for Hanne, and the label turns bright")
  GCA:SetCrafted("Hanne Moosgrund", "Leatherworking", card.data, false)

  UIx:SetMemberMode("sheet")
  local c = UIx.sheet.centre
  local sbox, soffer = rectOf(c.crafted, UIx.frame), rectOf(c.offer, UIx.frame)
  local slabel = c.crafted.label and rectOf(c.crafted.label, UIx.frame) or NO_RECT
  check(c.crafted._shown and LabelOf(c.crafted):IsVisible() and LabelOf(c.crafted)._text == MUTED .. "Crafted|r"
    and LabelBetweenBoxAndOffer(sbox, slabel, soffer),
    "character sheet: the same grey 'Crafted' label beside its box, left of 'Offer' " .. rstr(sbox) .. rstr(slabel) .. rstr(soffer))
  spell = c.featured.cand.spellID
  c.crafted:SetChecked(true); c.crafted._scripts.OnClick(c.crafted)
  check(GCA:CraftedMark("Hanne Moosgrund", "Leatherworking", spell) ~= nil and LabelOf(UIx.sheet.centre.crafted)._text == "Crafted",
    "ticking the sheet box stores the reminder, the label turns bright")
  GCA:SetCrafted("Hanne Moosgrund", "Leatherworking", c.featured, false)

  for _, size in ipairs({ { 980, 640 }, { 840, 560 } }) do
    UIx = OpenAdvisor("deDE", size[1], size[2])
    UIx:SetView("needs")
    local list = UIx.needDetail.members
    local bad = {}
    for _, row in ipairs(ShownRows(list)) do
      local nr, wr, sr = RowRect(row.name, row, list.viewW), RowRect(row.wornBtn, row, list.viewW), RowRect(row.state, row, list.viewW)
      local gr = RowRect(row.gain, row, list.viewW)
      local box, label, offer = CraftedParts(row, list.viewW)
      if not (row.crafted._shown and LabelOf(row.crafted):IsVisible() and plain(LabelOf(row.crafted)._text) == "Hergestellt") then
        bad[#bad + 1] = "no label"
      end
      if not (nr.r <= wr.l and wr.r <= sr.l and sr.r <= gr.l and gr.r <= box.l and LabelBetweenBoxAndOffer(box, label, offer) and offer.r <= list.viewW) then
        bad[#bad + 1] = rstr(nr) .. rstr(wr) .. rstr(sr) .. rstr(gr) .. rstr(box) .. rstr(label) .. rstr(offer)
      end
    end
    check(#ShownRows(list) > 0 and #bad == 0, size[1] .. "x" .. size[2] .. " needs detail: every member row reads name | item | gain | box 'Hergestellt' | Anbieten, "
      .. "nothing overlaps " .. table.concat(bad, "; "))
  end
  local s1 = ShownRows(UIx.needDetail.members)[1]
  local member, sug = s1.data.member.key, s1.data.sug
  s1.crafted:SetChecked(true); s1.crafted._scripts.OnClick(s1.crafted)
  s1 = ShownRows(UIx.needDetail.members)[1]
  check(GCA:CraftedMark(member, "Leatherworking", sug.cand.spellID) ~= nil and s1.crafted._checked and LabelOf(s1.crafted)._text == "Hergestellt",
    "ticking the needs-detail box stores the reminder for " .. member .. ", 'Hergestellt' turns bright")
  GCA:SetCrafted(member, "Leatherworking", sug, false)
end

H.finish()
