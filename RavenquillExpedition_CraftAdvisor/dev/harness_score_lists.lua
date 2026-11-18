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

H.finish()
