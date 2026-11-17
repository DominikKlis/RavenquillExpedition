local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, SG, check, GCA = H.section, H.SG, H.check, H.GCA
local sgEnv, SGns, CLASSES = H.sgEnv, H.SGns, H.CLASSES

section("G: CanWear matrix (class x level 39/40 x subclass) against SimGear's Classes.lua")
do
  assert(loadfile(SG .. "SimGearForever/Classes.lua", "t", sgEnv()))("SimGearForever", SGns)
  local SGC = SGns.Classes
  local LEVEL_GATE = { [3] = { HUNTER = 40, SHAMAN = 40 }, [4] = { WARRIOR = 40, PALADIN = 40 } }
  local LOC = { [1] = "INVTYPE_CHEST", [2] = "INVTYPE_CHEST", [3] = "INVTYPE_CHEST", [4] = "INVTYPE_CHEST", [6] = "INVTYPE_SHIELD",
    [7] = "INVTYPE_RELIC", [8] = "INVTYPE_RELIC", [9] = "INVTYPE_RELIC" }
  local bad, n = 0, 0
  for _, class in ipairs(CLASSES) do
    for sub, loc in pairs(LOC) do
      for _, level in ipairs({ 39, 40 }) do
        local barred = SGC.barredType(class, { classID = 4, subclassID = sub, equipLoc = loc })
        local gate = LEVEL_GATE[sub] and LEVEL_GATE[sub][class]
        local expect = barred == nil and not (gate and level < gate)
        local got = GCA:CanWear(class, level, { classID = 4, subClassID = sub, equipLoc = loc })
        n = n + 1
        if got ~= expect then bad = bad + 1; print(("    %s lvl %d sub %d: got %s, expected %s"):format(class, level, sub, tostring(got), tostring(expect))) end
      end
    end
    local hold = GCA:CanWear(class, 40, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" })
    local sgHold = SGC.barredType(class, { classID = 4, subclassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) == nil
    if hold ~= sgHold then bad = bad + 1; print("    holdable " .. class) end
    if not GCA:CanWear(class, 1, { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK" }) then bad = bad + 1 end
    n = n + 2
  end
  check(bad == 0, ("%d class/level/subclass cases match SimGear's equip tables + level gates (%d differ)"):format(n, bad))
  check(GCA:CanWear("PALADIN", 20, { classID = 4, subClassID = 7, equipLoc = "INVTYPE_RELIC" }) and
    not GCA:CanWear("SHAMAN", 20, { classID = 4, subClassID = 7, equipLoc = "INVTYPE_RELIC" }) and
    GCA:CanWear("DRUID", 20, { classID = 4, subClassID = 8, equipLoc = "INVTYPE_RELIC" }) and
    GCA:CanWear("SHAMAN", 20, { classID = 4, subClassID = 9, equipLoc = "INVTYPE_RELIC" }), "relics: libram Paladin, idol Druid, totem Shaman only")
  check(not GCA:CanWear("ROGUE", 60, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) and
    not GCA:CanWear("HUNTER", 60, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }) and
    GCA:CanWear("MAGE", 1, { classID = 4, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE" }), "held off-hands: not for Hunters/Rogues")
  check(GCA:CanWear("WARRIOR", 60, { classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON" }), "W: a Warrior can wield a one-handed sword")
  check(GCA.SLOTS_FOR.INVTYPE_RELIC[1] == 18 and GCA.SLOTS_FOR.INVTYPE_WEAPON[2] == 17 and GCA.SLOTS_FOR.INVTYPE_2HWEAPON[1] == 16
    and GCA.SLOTS_FOR.INVTYPE_RANGEDRIGHT[1] == 18 and GCA.SLOTS_FOR.INVTYPE_THROWN[1] == 18 and GCA.SLOTS_FOR.INVTYPE_WEAPONOFFHAND[1] == 17,
    "SLOTS_FOR (W1): relic -> 18, one-hander 16/17, two-hander 16, off-hand weapon 17, ranged/wand/thrown 18")
end

H.finish()
