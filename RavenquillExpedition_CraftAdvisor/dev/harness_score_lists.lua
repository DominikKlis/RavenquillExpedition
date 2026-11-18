local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, GCA, RQ, check = H.section, H.GCA, H.RQ, H.check

local function listed(key)
  for _, e in ipairs(GCA:GetMemberList()) do if e.key == key then return e end end
end

section("Core: forgetting a member's gear (shift-right-click in the member list)")
do
  GCA.db.members["Gone Guy"] = { class = "DRUID", level = 40, items = {}, ts = 1, source = "inspect" }
  GCA.db.members["Roster Gal"] = { class = "DRUID", level = 40, items = {}, ts = 1, source = "inspect" }
  RQ.roster["Roster Gal"] = { class = "DRUID", level = 40, online = true }
  check(listed("Gone Guy") and listed("Gone Guy").member and listed("Roster Gal") and listed("Roster Gal").member,
    "both recorded members are listed with their gear")
  GCA:ForgetGear("Gone Guy")
  GCA:ForgetGear("Roster Gal")
  check(GCA.db.members["Gone Guy"] == nil and listed("Gone Guy") == nil, "a forgotten member outside the roster leaves the list")
  check(listed("Roster Gal") and listed("Roster Gal").member == nil, "a forgotten guildmate stays listed, without gear")
  RQ.roster["Roster Gal"] = nil
end

section("Core: which guild needs match the needs search and the offline box (MatchNeeds)")
do
  local function sug(name, slot) return { info = { name = name }, slot = slot, known = true } end
  local function group(s, keys)
    local g = { sug = s, rows = {} }
    for i, key in ipairs(keys) do g.rows[i] = { sug = s, member = { key = key } } end
    return g
  end
  local vest, belt, ring = sug("Wild Leather Vest", 5), sug("Barbaric Belt", 6), sug("Band of Thorns", 12)
  local gVest, gBelt, gRing = group(vest, { "Bud Stone", "Cara Field" }), group(belt, { "Bud Stone" }), group(ring, { "Cara Field" })
  local gVestAll = group(vest, { "Bud Stone", "Cara Field", "Olga Field" })
  local needs = { crafts = { gVest, gBelt, gRing }, craftsAll = { gVestAll, gBelt, gRing },
    offline = { { sug = vest, member = { key = "Olga Field" } }, { sug = belt, member = { key = "Olga Field" } } } }
  local function shape(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.group.sug.info.name .. "@" .. e.cat .. "x" .. #e.rows end
    return table.concat(out, ",")
  end

  local all, members, offline = GCA:MatchNeeds(needs, "", false)
  check(shape(all) == "Wild Leather Vest@5x2,Barbaric Belt@6x1,Band of Thorns@11x1" and all[1].group == gVest
    and members == 2 and offline == 1,
    "no search: every online craft in order, the ring under the rings section (11), 2 members, 1 offline member: " .. shape(all))
  all, members = GCA:MatchNeeds(needs, "", true)
  check(shape(all) == "Wild Leather Vest@5x3,Barbaric Belt@6x1,Band of Thorns@11x1" and members == 3,
    "offline box: the crafts with offline members, 3 members: " .. shape(all))
  all, members = GCA:MatchNeeds(needs, "  BELT ", false)
  check(shape(all) == "Barbaric Belt@6x1" and members == 1, "a craft name matches without case or outer spaces: " .. shape(all))
  all, members = GCA:MatchNeeds(needs, "cara", false)
  check(shape(all) == "Wild Leather Vest@5x1,Band of Thorns@11x1" and all[1].rows[1].member.key == "Cara Field" and members == 1,
    "a member name keeps only that member's rows: " .. shape(all))
  check(#GCA:MatchNeeds(needs, "olga", false) == 0 and shape(GCA:MatchNeeds(needs, "olga", true)) == "Wild Leather Vest@5x1",
    "an offline member matches only with the offline box")
  check(#GCA:MatchNeeds(needs, "50%", false) == 0, "a '%' is plain text, no match")
  all, members, offline = GCA:MatchNeeds(nil, "", true)
  check(#all == 0 and members == 0 and offline == 0, "no needs yet: nothing matches")
end

section("Core: who the member list shows, the search, the default pick (ListedMembers, MatchesSearch, DefaultMember)")
do
  local me = { key = "Me Stone", isSelf = true, online = true }
  local bud = { key = "Bud Stone", online = true, member = {}, best = { points = 3 } }
  local cara = { key = "Cara Field", online = true, member = {} }
  local olga = { key = "Olga Field", online = false, member = {}, best = { points = 9 } }
  local noGear = { key = "Nogear Nick", online = true }
  local members = { me, bud, cara, olga, noGear }
  local function keys(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.key end
    return table.concat(out, ",")
  end
  local on, off = GCA.ListedMembers(members, "")
  check(keys(on) == "Me Stone,Bud Stone,Cara Field" and keys(off) == "Olga Field",
    "you and recorded members, split online / offline in the given order; a guildmate with no gear is not listed: " .. keys(on) .. " | " .. keys(off))
  on, off = GCA.ListedMembers(members, "  STONE ")
  check(keys(on) == "Me Stone,Bud Stone" and #off == 0, "the search matches names without case or outer spaces: " .. keys(on))
  on, off = GCA.ListedMembers(members, "field")
  check(keys(on) == "Cara Field" and keys(off) == "Olga Field", "the search reaches offline members too")
  check(#GCA.ListedMembers(members, "50%") == 0 and #GCA.ListedMembers(nil, "") == 0, "a '%' is plain text; no members, no rows")
  check(GCA.MatchesSearch("Bud Stone", " bud ") and GCA.MatchesSearch("Bud Stone", nil) and GCA.MatchesSearch("Bud Stone", "")
    and not GCA.MatchesSearch("Bud Stone", "cara"), "MatchesSearch: same rule for a single name; an empty search matches all")
  check(GCA.DefaultMember(members) == bud and GCA.DefaultMember({ cara, olga }) == olga,
    "default pick: the first member other than you with an upgrade, offline ones included")
  check(GCA.DefaultMember({ { key = "Me Stone", isSelf = true, best = {} }, cara }) == nil and GCA.DefaultMember({}) == nil,
    "default pick: none when only you have an upgrade or nobody does")
end


section("Core: member status and why a member shows no suggestions (MemberStatus, EmptyReason)")
do
  local function entry(over)
    local e = { key = "Tess Field", member = { items = {} }, state = "ok" }
    for k, v in pairs(over) do e[k] = v end
    return e
  end
  local best = { slot = 6, points = 12 }
  local cases = {
    { entry({ member = false, best = best }), "uninspected" }, { entry({ browse = true, best = best }), "browse" },
    { entry({ best = best, state = "no-spec" }), "best" }, { entry({ state = "no-spec" }), "no-spec" },
    { entry({ state = "no-level" }), "no-level" }, { entry({ state = "loading" }), "loading" },
    { entry({ state = "no-weights" }), "none" }, { entry({ state = "no-class" }), "none" }, { entry({}), "none" },
  }
  local bad = {}
  for i, c in ipairs(cases) do
    if c[1].member == false then c[1].member = nil end
    if GCA.MemberStatus(c[1]) ~= c[2] then bad[#bad + 1] = i .. ": " .. tostring(GCA.MemberStatus(c[1])) end
  end
  check(#bad == 0, "member status: no gear, browse, an upgrade, then the scoring state (no spec / no level / loading), else none: "
    .. table.concat(bad, "; "))

  H.professionMocks()
  H.setProfs({ { "Lederverarbeitung", 300, 300, 165 } })
  local spell = next(H.ns.Recipes.Leatherworking)
  H.known[spell] = true
  GCA:RefreshKnown()
  local lw, tail = "Leatherworking", "Tailoring"
  check(GCA:KnownCount(lw) > 0 and GCA:KnownCount(tail) == 0, "setup: a known Leatherworking recipe, no Tailoring")
  local R = function(e, n, prof, browse) return GCA:EmptyReason(e, n, prof, browse) end
  check(R(entry({ member = false }), 3, lw) == "no-gear" and R(entry({ state = "no-spec" }), 3, lw) == "no-spec"
    and R(entry({ state = "no-level" }), 3, lw) == "no-level" and R(entry({ state = "no-weights" }), 3, lw) == "no-weights"
    and R(entry({ state = "no-class" }), 3, lw) == "no-weights",
    "no gear, then an unscored member (no spec, no level, no weights or class) explains even with rows")
  check(R(entry({}), 3, lw) == nil and R(entry({ pending = 2 }), 1, lw) == nil, "rows shown: no reason")
  check(R(entry({ pending = 2 }), 0, lw, true) == "loading" and R(entry({}), 0, tail, true) == "browse"
    and R(entry({}), 0, tail) == "no-known" and R(entry({}), 0, lw) == "none",
    "no rows: item data loading, then browsing, then no known recipe, else nothing to offer")
  H.known[spell] = nil
  GCA:RefreshKnown()
end


section("Core: the rows and worn item of one sheet slot, the slot with the top upgrade (SlotRows, TopUpgradeSlot)")
do
  local r11a, r12, r11b, chest = { slot = 11, name = "a" }, { slot = 12, name = "b" }, { slot = 11, name = "c" }, { slot = 5, name = "d" }
  local worn11, worn12, worn5 = { slot = 11 }, { slot = 12 }, { slot = 5 }
  local rings = { key = 11, slots = { 11, 12 }, rows = { r11a, r12, r11b }, worn = { worn11, worn12 } }
  local chestSec = { key = 5, slots = { 5 }, rows = { chest }, worn = { worn5 } }
  local wrist = { key = 9, slots = { 9 }, rows = {}, worn = { { slot = 9 } } }
  local list = { sections = { rings, chestSec, wrist } }
  local function names(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.name end
    return table.concat(out, ",")
  end
  local rows, worn = GCA:SlotRows(list, 12)
  check(names(rows) == "b" and worn == worn12, "a ring slot: only that ring's rows and the ring worn there: " .. names(rows))
  rows, worn = GCA:SlotRows(list, 11)
  check(names(rows) == "a,c" and worn == worn11, "the other ring slot: its two rows in order: " .. names(rows))
  rows, worn = GCA:SlotRows(list, 5)
  check(names(rows) == "d" and worn == worn5, "a one-slot section: all its rows")
  rows, worn = GCA:SlotRows(list, 9)
  local noRows, noWorn = GCA:SlotRows(nil, 5)
  check(#rows == 0 and worn.slot == 9 and #noRows == 0 and noWorn == nil, "no upgrade: no rows, the worn item still; no list: nothing")
  check(GCA.TopUpgradeSlot(list) == 11 and GCA.TopUpgradeSlot({ sections = { wrist, chestSec } }) == 5
    and GCA.TopUpgradeSlot({ sections = { wrist } }) == nil and GCA.TopUpgradeSlot(nil) == nil,
    "top upgrade: the slot of the first row of the first section with rows; none without rows")
end

H.finish()
