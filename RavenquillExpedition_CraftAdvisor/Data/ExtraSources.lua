-- Pattern sources CraftersJournal doesn't know (its data comes from QuestieDB = Classic; Forever's own creatures and
-- drops, and some vendors, are missing there). Read from Wowhead's WoW Forever database (wowhead.com/forever/item=<pattern>),
-- 2026-11-15. Used by Src.Build (UI/Sources.lua) only when CJ has no vendor / quest / drop for the recipe.
-- [recipe spellID] = {
--   v = { { npc ID, English name, area ID, English zone, price in copper, side ("A"/"H", nil = both) }, ... },
--   d = { { npc ID, English name, area ID, English zone, min level, max level, drop % }, ... },  (levels nil = boss)
--   c = { { item ID, English name }, ... },  -- the pattern comes out of this item (a bag, clippings...)
-- }
-- Zones: C_Map.GetAreaInfo(area ID) in game (localized), else the English name here.
-- Checked on Wowhead with NO source listed (left out): Blessed Plate Helm 251445, Champion's Legplates 251450,
-- Evergreen Shield 279311, Depleted Thorium Sabatons 279312, Azerothium Legplates 279314.
-- Not on Wowhead Forever at all (404): 211846, 12817, 12831, 12832, 228307, 228306, 234488.
local _, ns = ...
ns.ExtraSources = {
  -- Leatherworking ------------------------------------------------------------------------------------------------
  [10550] = { d = { -- Pattern: Nightscape Cloak (8388)
    { 253526, "Bristleback Skullcrusher", 16651, "Shen'dralas", 42, 43, 1.46 },
    { 253524, "Bristleback Nomad", 16651, "Shen'dralas", 42, 43, 0.99 },
  } },

  -- Blacksmithing: Lokhtos Darkbargainer (Thorium Brotherhood, Blackrock Depths) --------------------------------
  [20872] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 95294 } } },  -- Fiery Chain Girdle (17049)
  [20874] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 74117 } } },  -- Dark Iron Bracers (17051)
  [20876] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 190588 } } }, -- Dark Iron Leggings (17052)
  [20890] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 232941 } } }, -- Dark Iron Reaver (17059)
  [20897] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 232941 } } }, -- Dark Iron Destroyer (17060)
  [23636] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 63529 } } },  -- Dark Iron Helm (19206)
  [23637] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 84705 } } },  -- Dark Iron Gauntlets (19207)
  [23638] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 74117 } } },  -- Black Amnesty (19208)
  [23639] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 74117 } } },  -- Blackfury (19209)
  [23650] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 108000 } } }, -- Ebon Hand (19210)
  [23652] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 108000 } } }, -- Blackguard (19211)
  [24399] = { v = { { 12944, "Lokhtos Darkbargainer", 1584, "Blackrock Depths", 72000 } } },  -- Dark Iron Boots (20040)

  -- Blacksmithing: other ---------------------------------------------------------------------------------------------
  [22757] = { d = { -- Elemental Sharpening Stone (18264): Molten Core bosses
    { 11988, "Golemagg the Incinerator", 2717, "Molten Core", nil, nil, 1.17 },
    { 12057, "Garr", 2717, "Molten Core", nil, nil, 1.22 },
    { 12056, "Baron Geddon", 2717, "Molten Core", nil, nil, 1.06 },
    { 12264, "Shazzrah", 2717, "Molten Core", nil, nil, 0.86 },
    { 11982, "Magmadar", 2717, "Molten Core", nil, nil, 1.25 },
    { 12259, "Gehennas", 2717, "Molten Core", nil, nil, 0.76 },
    { 12118, "Lucifron", 2717, "Molten Core", nil, nil, 0.68 },
  } },
  [24912] = { c = { { 20469, "Decoded True Believer Clippings" } } }, -- Darkrune Gauntlets (20553)
  [24914] = { c = { { 20469, "Decoded True Believer Clippings" } } }, -- Darkrune Breastplate (20554)
  [24913] = { c = { { 20469, "Decoded True Believer Clippings" } }, -- Darkrune Helm (20555)
    d = { { 15184, "Cenarion Hold Infantry", 1377, "Silithus", 60, 60 } } },
  [1252337] = { d = { { 7155, "Deadwood Pathfinder", 361, "Felwood", 49, 50, 2.09 } } },    -- Blessed Plate Gauntlet (251440)
  [1252340] = { d = { { 7451, "Raging Owlbeast", 618, "Winterspring", 54, 56, 2.05 } } },   -- Blessed Plate Leggings (251443)
  [1252341] = { d = { { 8600, "Plaguebat", 139, "Eastern Plaguelands", 53, 55, 2.28 } } },  -- Blessed Plate Belt (251444)
  [1252343] = { d = { -- Blessed Plate Chest (251446)
    { 249221, "Wormwing Windwitch", 616, "Hyjal", 57, 59, 0.56 },
    { 249222, "Wormwing Ambusher", 616, "Hyjal", 57, 58, 3.57 },
  } },
  [1252350] = { d = { { 247248, "Legashi Summoner", 16554, nil, nil, nil, 2.86 } } },        -- Breastplate of Salvation (251453)
  [1252367] = { v = { { 11557, "Meilosh", 361, "Felwood", 105263 } } },                      -- Bagh Nakh (251470, Timbermaw)
}
