local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local FILES = Files.kitFiles(Files.list({ except = { "Data/Sources.lua", "Data/ExtraSources.lua", "Sync", "RecipeSources.lua", "UI" } }))

local worn = { [8] = "item:2302::::", [9] = "item:9001::::" }
local itemMeta = {
  [2302] = { loc = "INVTYPE_FEET", lvl = 1, stats = { RESISTANCE0_NAME = 30 } },
  [2300] = { loc = "INVTYPE_CHEST", lvl = 8, stats = { RESISTANCE0_NAME = 60, ITEM_MOD_AGILITY_SHORT = 1 } },
  [4244] = { loc = "INVTYPE_CHEST", lvl = 20, stats = { RESISTANCE0_NAME = 90, ITEM_MOD_AGILITY_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3 } },
  [4242] = { loc = "INVTYPE_LEGS", lvl = 10, stats = { RESISTANCE0_NAME = 70, ITEM_MOD_AGILITY_SHORT = 3 } },
  [2303] = { loc = "INVTYPE_LEGS", lvl = 10, stats = { RESISTANCE0_NAME = 70, ITEM_MOD_AGILITY_SHORT = 3 }, bind = 1 },
  [9001] = { loc = "INVTYPE_WRIST", lvl = 10, stats = { RESISTANCE0_NAME = 20 } },
}
local roster = {
  { "Buddy Stone", "DRUID", true }, { "Cora Vale", "HUNTER", true }, { "Offy Lane", "ROGUE", false }, { "Me", "ROGUE", true },
}

local function idOf(item) return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)")) end
local sched = Kit.Scheduler()
local client = Kit.Client(sched, nil, "Me", { class = "ROGUE", level = 30, files = FILES, setup = function(env)
  env.C_ChatInfo = nil
  env.GetInventoryItemLink = function(u, slot) if u == "player" then return worn[slot] end end
  env.GetInventorySlotInfo = function() return 1, "tex" end
  env.UnitGUID = function(u) if u == "player" then return "G-me" end end
  env.UnitIsPlayer = function(u) return u == "player" end
  env.UnitIsUnit = function(a, b) return a == b end
  env.GetNumSubgroupMembers = function() return 0 end
  env.GetNumGuildMembers = function() return #roster end
  env.GetGuildRosterInfo = function(i)
    local r = roster[i]
    if r then return r[1], "Member", 1, 30, r[2], "Zone", "", "", r[3], 0, r[2] end
  end
  env.GetProfessions = function() return 1 end
  env.GetProfessionInfo = function() return "Leatherworking", nil, 120, 150, nil, nil, 165 end
  env.C_SpellBook = { IsSpellKnown = function() return false end }
  env.C_Item = {
    GetItemInfoInstant = function(item)
      local m = itemMeta[idOf(item)]
      if not m then return idOf(item), "Misc", "Misc", "", 1, 15, 0 end
      return idOf(item), "Armor", "x", m.loc, 1, 4, 2
    end,
    GetItemInfo = function(item)
      local id = idOf(item)
      local m = itemMeta[id] or { loc = "", lvl = 1 }
      return "Item" .. id, "|Hitem:" .. id .. "|h[Item" .. id .. "]|h", 2, 20, m.lvl, nil, nil, nil, m.loc, 1, nil, 4, 2, m.bind or 2
    end,
    GetItemStats = function(link) local m = itemMeta[idOf(link)]; return m and m.stats or {} end,
    RequestLoadItemDataByID = function() end,
  }
end })
local GCA = client.ns[CA].GCA
client.login()
sched:flush(200)
GCA:SetManualSpec("Me", "ROGUE", "COMBAT")

local function byID(rows)
  local out = {}
  for _, r in ipairs(rows) do out[r.spellID] = r end
  return out
end
local function crafterKeys(list)
  local out = {}
  for i, c in ipairs(list or {}) do out[i] = c.key .. (c.online and "+" or "-") end
  return table.concat(out, ",")
end
local function spells(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.spellID end
  return table.concat(out, ",")
end
local function profsText(entry)
  local out = {}
  for i, p in ipairs(entry.profs) do out[i] = p.prof .. " " .. p.rank .. "/" .. p.count end
  return table.concat(out, ", ")
end

section("No crafter data yet: an empty roster and no recipes")
check(#GCA:CrafterRoster() == 0 and #GCA:CrafterRecipes() == 0, "nothing synced: no crafters, no recipes")

GCA:StoreCrafter("Buddy Stone", 100, { Leatherworking = { rank = 300, ids = { 3762, 2160, 2149, 9999999 } },
  Enchanting = { rank = 225, ids = { 7779, 7421 } } })
GCA:StoreCrafter("Cora Vale", 100, { Leatherworking = { rank = 280, ids = { 3762 } }, Tailoring = { rank = 150, ids = { 2385 } } })
GCA:StoreCrafter("Offy Lane", 100, { Leatherworking = { rank = 120, ids = { 2153, 3759 } } })
GCA:StoreCrafter("Left Guild", 100, { Leatherworking = { rank = 300, ids = { 2158 } } })
GCA:StoreCrafter("Me", 100, { Leatherworking = { rank = 150, ids = { 3762 } } })
local syncedAt = client.env.time()

section("Roster: guildmates who shared recipes, online first, then by name")
local roster1 = GCA:CrafterRoster()
local names = {}
for i, e in ipairs(roster1) do names[i] = e.key .. (e.online and "+" or "-") end
check(table.concat(names, ",") == "Buddy Stone+,Cora Vale+,Offy Lane-",
  "Buddy and Cora (online) before Offy (offline); you and a crafter who left the guild are left out: " .. table.concat(names, ","))
check(profsText(roster1[1]) == "Leatherworking 300/3, Enchanting 225/2" and profsText(roster1[2]) == "Leatherworking 280/1, Tailoring 150/1",
  "professions in the advisor's order with rank and the recipes it has data for (an unknown spell ID is not counted): "
  .. profsText(roster1[1]) .. " | " .. profsText(roster1[2]))
check(roster1[1].time == syncedAt and roster1[1].class == "DRUID", "each entry says when its recipes arrived and the class")

section("One crafter's recipes: data from the recipe tables, who else crafts them")
local buddy = GCA:CrafterRecipes("Buddy Stone")
local b = byID(buddy)
check(#buddy == 5 and b[9999999] == nil, "five recipes; the spell ID without recipe data is skipped: " .. spells(buddy))
local vest = b[3762]
check(vest and vest.prof == "Leatherworking" and vest.kind == "craft" and vest.name == "Hillman's Leather Vest" and vest.itemID == 4244
  and vest.skill == 75 and #vest.regs == 3 and vest.regs[1][1] == 4243,
  "a craft row: profession, name, crafted item, required skill and reagents from the recipe data")
check(crafterKeys(vest.crafters) == "Buddy Stone+,Cora Vale+", "who can craft it: Buddy and Cora (by rank), not you: " .. crafterKeys(vest.crafters))
local ench = b[7779]
check(ench and ench.kind == "enchant" and ench.prof == "Enchanting" and ench.name == "Enchant Bracer - Minor Agility" and ench.itemID == nil
  and ench.skill == 80 and #ench.regs == 2 and b[7421] and b[7421].kind == "craft" and b[7421].itemID == 6218,
  "Enchanting: an enchant row (no item) and a crafted rod")

section("Upgrades for you: what each craft would give you, best first in its profession")
check(vest.upgrade and vest.upgrade.points > 0 and vest.upgrade.slot == 5 and b[2160].upgrade
  and b[2160].upgrade.points < vest.upgrade.points, "both vests fill your empty chest slot; Hillman's gains more")
check(b[2149].upgrade == nil, "the boots you already wear are no upgrade")
check(ench.upgrade and ench.upgrade.kind == "enchant" and ench.upgrade.slot == 9 and ench.upgrade.points > 0,
  "the bracer enchant would improve your worn bracers")
check(spells(buddy) == "3762,2160,2149,7779,7421", "Leatherworking before Enchanting, upgrades first (by gain), then by skill: " .. spells(buddy))
local offy = byID(GCA:CrafterRecipes("Offy Lane"))
check(offy[3759].upgrade and offy[3759].upgrade.slot == 7 and offy[2153].upgrade == nil,
  "legs: the tradeable pants are an upgrade, the bind-on-pickup pair is not (a guildmate cannot hand it over)")

section("All crafters: one row per recipe across the guild")
local all = GCA:CrafterRecipes()
local a = byID(all)
check(#all == 8 and a[2158] == nil and a[2385] and a[2153],
  "eight recipes from Buddy, Cora and Offy; the one only a former member knew is not listed: " .. spells(all))
local n3762 = 0
for _, r in ipairs(all) do if r.spellID == 3762 then n3762 = n3762 + 1 end end
check(n3762 == 1 and crafterKeys(a[3762].crafters) == "Buddy Stone+,Cora Vale+" and crafterKeys(a[2153].crafters) == "Offy Lane-",
  "a recipe two crafters know is one row naming both; an offline crafter is listed as offline")
check(spells(all) == "3762,3759,2160,2153,2149,2385,7779,7421", "grouped by profession, upgrades first, then by skill: " .. spells(all))

section("Cache: the same rows until something changes")
check(GCA:CrafterRecipes("Buddy Stone") == buddy and GCA:CrafterRecipes() == all, "asking again returns the same rows (nothing rebuilt)")
GCA:StoreCrafter("Buddy Stone", 200, { Leatherworking = { rank = 300, ids = { 3762, 2160, 2149, 3759 } } })
local buddy2 = byID(GCA:CrafterRecipes("Buddy Stone"))
check(buddy2[3759] and buddy2[3759].upgrade and buddy2[7779] == nil and crafterKeys(byID(GCA:CrafterRecipes())[3759].crafters) == "Buddy Stone+,Offy Lane-",
  "a newer recipe set arrives: the new recipe shows up, the dropped profession is gone, the guild view names both crafters")
roster[2][3] = false
GCA.RQ:ReadRoster()
check(crafterKeys(byID(GCA:CrafterRecipes())[3762].crafters) == "Buddy Stone+,Cora Vale-", "Cora logs off: her crafter entry says offline")
worn[5] = "item:4244::::"
GCA:CaptureSelf()
local after = byID(GCA:CrafterRecipes("Buddy Stone"))
check(after[3762].upgrade == nil and after[2160].upgrade == nil and after[3759].upgrade ~= nil,
  "you equip Hillman's vest: neither vest is an upgrade any more, the pants still are")

section("No gear record for you: recipes still listed, nothing marked")
GCA.db.members.Me = nil
local bare = GCA:CrafterRecipes("Buddy Stone")
local marked = 0
for _, r in ipairs(bare) do if r.upgrade then marked = marked + 1 end end
check(#bare == 4 and marked == 0, "four recipes, no upgrade marks")

check(#client.errors == 0, "no Lua error reported: " .. table.concat(client.errors, " | "))
Kit.finish()
