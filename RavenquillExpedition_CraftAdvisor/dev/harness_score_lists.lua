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

H.finish()
