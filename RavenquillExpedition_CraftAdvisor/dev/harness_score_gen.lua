-- Score harness, generated data: dev/gen_recipes.lua (row counts, quotes, IDs, faction, shipped = regenerated)
-- and the CanWear matrix against SimGear's Classes.lua. SimGear Forever is needed (see dev/scorekit.lua).
-- Run: lua dev/harness_score_gen.lua [SimGear unzip dir]
local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, ROOT, SG, check, CJ_DATA, ns, GCA = H.section, H.ROOT, H.SG, H.check, H.CJ_DATA, H.ns, H.GCA
local sgEnv, SGns, CLASSES = H.sgEnv, H.SGns, H.CLASSES

---------------------------------------------------------------------------
section("G: generator (row counts, escaped quotes, negative IDs, intermediates, faction, shipped = regenerated)")
---------------------------------------------------------------------------
local GEN_OUT = os.getenv("TEMP") and (os.getenv("TEMP"):gsub("\\", "/") .. "/gca_gen_test/") or nil
do
  local function runGen(cjDir, outDir)
    local savedArg = arg
    arg = { [0] = ROOT .. "dev/gen_recipes.lua", cjDir or "", SG, outDir }
    local realStderr = io.stderr
    local errLines = {}
    io.stderr = { write = function(_, ...) for i = 1, select("#", ...) do errLines[#errLines + 1] = select(i, ...) end end }
    local ok, err = pcall(function() assert(loadfile(ROOT .. "dev/gen_recipes.lua"))() end)
    io.stderr = realStderr
    arg = savedArg
    return ok, err, table.concat(errLines)
  end
  local function readAll(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("a"); f:close(); return s end
  if not GEN_OUT then
    check(false, "TEMP not set: generator test skipped")
  elseif not CJ_DATA then
    H.skips = H.skips + 1
    print("SKIP score:craftersjournal-source: CraftersJournal not installed next to this addon (or set RQ_CRAFTERSJOURNAL)")
  else
    os.execute('mkdir "' .. (GEN_OUT .. "Data"):gsub("/", "\\") .. '" 2>nul')
    local ok, err, report = runGen(nil, GEN_OUT)
    check(ok, "generator runs and its own row-count asserts pass " .. (ok and "" or tostring(err)))
    local same = true
    for _, f in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting", "Enchants" }) do
      local a, b = readAll(GEN_OUT .. "Data/" .. f .. ".lua"), readAll(ROOT .. "Data/" .. f .. ".lua")
      if not a or a ~= b then same = false; print("    differs: " .. f) end
    end
    check(same, "shipped Data/*.lua are byte-identical to a fresh generator run")
    check(report:find("Leatherworking: 501 item rows (skipped 0 negative, 2 intermediate)", 1, true)
      and report:find("Enchanting: 62 item rows (skipped 10 negative", 1, true), "report: LW 2 intermediates, Enchanting 10 negative IDs skipped")
    -- a source with one extra row must fail the count assert (copy CJ's Blacksmithing with a fake recipe added)
    local cj = CJ_DATA
    local fake = GEN_OUT .. "cj/"
    os.execute('mkdir "' .. fake:gsub("/", "\\") .. '" 2>nul')
    for _, f in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
      local src = readAll(cj .. f .. ".lua")
      if f == "Blacksmithing" then
        local n
        src, n = src:gsub("(  recipes = {\r?\n)", "%1    [999999] = { name = \"Fake\", t = { 1, 1, 1, 1 }, r = { { 1, 1 } }, out = { 999998, 1 } },\n", 1)
        assert(n == 1, "fake row not inserted")
      end
      local o = io.open(fake .. f .. ".lua", "wb"); o:write(src); o:close()
    end
    local ok2, err2 = runGen(fake, GEN_OUT)
    check(not ok2 and tostring(err2):find("Blacksmithing: 439 rows, expected 438", 1, true), "an extra source row fails the count assert: " .. tostring(err2):sub(1, 80))
    runGen(nil, GEN_OUT) -- leave a clean copy
  end
  local R = ns.Recipes
  local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  check(count(R.Leatherworking) == 501 and count(R.Blacksmithing) == 438 and count(R.Tailoring) == 398
    and count(R.Engineering) == 251 and count(R.Enchanting) == 62,
    ("loaded rows LW %d, BS %d, Tailoring %d, Engineering %d, Enchanting items %d"):format(count(R.Leatherworking),
      count(R.Blacksmithing), count(R.Tailoring), count(R.Engineering), count(R.Enchanting)))
  check(R.Engineering[12720] and R.Engineering[12720].name == 'Goblin "Boom" Box' and R.Engineering[12720].item == 10580,
    "Goblin \"Boom\" Box present, escaped quotes round-trip")
  local neg = false
  for _, prof in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
    for id in pairs(R[prof]) do if id < 0 then neg = true end end
  end
  check(not neg, "no negative recipe IDs (conversions) anywhere")
  local inter = false
  for _, r in pairs(R.Leatherworking) do if r.item == 10482 or r.item == 22331 then inter = true end end
  check(not inter, "intermediates Cured Thick Hide / Rugged Leather left out")
  check(R.Tailoring[1229504].faction == "Horde" and R.Tailoring[1263425].faction == "Alliance", "faction carried (Tailoring 1229504 Horde, 1263425 Alliance)")
  check(R.Tailoring[461692] and R.Leatherworking[461692] and R.Leatherworking[22815].item == 18258 and R.Tailoring[22813].item == 18258,
    "461692 in Tailoring and LW; item 18258 made by 22815 (LW) and 22813 (Tailoring)")
  local E = ns.Enchants.rows
  local kinds = {}
  for _, r in ipairs(E) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
  check(#E == 175 and kinds.stats == 122 and kinds.damage == 10 and kinds.utility == 27 and kinds.proc == 16,
    ("enchant table %d rows: stats %d, damage %d, utility %d, proc %d"):format(#E, kinds.stats or 0, kinds.damage or 0, kinds.utility or 0, kinds.proc or 0))
  local d = GCA:EnchantData()
  check(d.bySpell[1217203] == nil and d.bySpell[435481] == nil and d.bySpell[13419] ~= nil, "SimGear-only 1217203 and CJ-only 435481 not in the table")
end

---------------------------------------------------------------------------
section("G: CanWear matrix (class x level 39/40 x subclass) against SimGear's Classes.lua")
---------------------------------------------------------------------------
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
    -- held off-hand (subclass 0) and cloak: SimGear's noHoldable rule; cloaks for all
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
