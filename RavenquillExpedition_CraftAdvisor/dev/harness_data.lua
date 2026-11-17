local DEV = (arg[0]:gsub("[^/\\]*$", ""))
if DEV == "" then DEV = "./" end
local Files = dofile(DEV .. "files.lua")
local ROOT = Files.ROOT
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function isInt(v, lo, hi) return math.type(v) == "integer" and v >= lo and (not hi or v <= hi) end
local function readAll(p) local h = assert(io.open(p, "rb")); local s = h:read("a"); h:close(); return s end

local PROFS = { Leatherworking = 165, Blacksmithing = 164, Tailoring = 197, Engineering = 202, Enchanting = 333 }

section("every Data file of the .toc runs with no globals at all")
local dataFiles = {}
for _, f in ipairs(Files.all()) do if f:find("^Data/") then dataFiles[#dataFiles + 1] = f end end
local ns, touched = {}, {}
local env = setmetatable({}, {
  __index = function(_, k) touched[#touched + 1] = "read " .. tostring(k) end,
  __newindex = function(_, k) touched[#touched + 1] = "write " .. tostring(k) end,
})
local ok, err = pcall(Files.load, dataFiles, ns, env)
check(ok and #dataFiles >= 9, ("%d Data files load (%s)"):format(#dataFiles, ok and "ok" or tostring(err)))
check(#touched == 0, "no Data file reads or writes a global (another addon's tables included): " .. table.concat(touched, ", "))

section("recipe rows (Data/<Profession>.lua)")
local R, META = ns.Recipes or {}, ns.RecipeMeta or {}
local EXPECT = { Leatherworking = 501, Blacksmithing = 438, Tailoring = 398, Engineering = 251, Enchanting = 62 }
for prof, line in pairs(PROFS) do
  local rows = R[prof] or {}
  check(count(rows) == EXPECT[prof] and META[prof] and META[prof].rows == EXPECT[prof] and META[prof].skillLine == line,
    ("%s: %d rows, RecipeMeta says %s, skill line %s"):format(prof, count(rows), tostring(META[prof] and META[prof].rows),
      tostring(META[prof] and META[prof].skillLine)))
  local bad = {}
  for id, r in pairs(rows) do
    local why
    if not isInt(id, 1) then why = "id"
    elseif not isInt(r.item, 1) then why = "item"
    elseif not isInt(r.skill, 1, 320) then why = "skill"
    elseif r.src ~= "trainer" and r.src ~= "pattern" and r.src ~= "other" then why = "src"
    elseif type(r.name) ~= "string" or r.name == "" then why = "name"
    elseif r.faction ~= nil and r.faction ~= "Alliance" and r.faction ~= "Horde" then why = "faction"
    elseif type(r.r) ~= "table" or #r.r == 0 then why = "reagents"
    else
      for k in pairs(r) do
        if k ~= "item" and k ~= "skill" and k ~= "src" and k ~= "name" and k ~= "r" and k ~= "faction" then why = "key " .. tostring(k) end
      end
      local seen = {}
      for _, p in ipairs(r.r) do
        if type(p) ~= "table" or #p ~= 2 or not isInt(p[1], 1) or not isInt(p[2], 1, 120) then why = "reagent pair"
        elseif seen[p[1]] then why = "reagent twice"
        else seen[p[1]] = true end
      end
    end
    if why then bad[#bad + 1] = id .. " (" .. why .. ")" end
  end
  table.sort(bad)
  check(#bad == 0, prof .. ": every row is { item, skill 1-320, src, name, r = { {itemID, 1-120}, ... }, faction? } " .. table.concat(bad, ", "))
end
do
  local dup = {}
  for prof, rows in pairs(R) do
    local byItem = {}
    for id, r in pairs(rows) do
      if byItem[r.item] then dup[#dup + 1] = prof .. ":" .. r.item end
      byItem[r.item] = id
    end
  end
  check(#dup == 0, "no item is made by two recipes of the same profession " .. table.concat(dup, ", "))
end
check(R.Engineering[12720] and R.Engineering[12720].name == 'Goblin "Boom" Box' and R.Engineering[12720].item == 10580,
  "Goblin \"Boom\" Box present, escaped quotes round-trip")
do
  local inter = false
  for _, r in pairs(R.Leatherworking) do if r.item == 10482 or r.item == 22331 then inter = true end end
  check(not inter, "intermediates Cured Thick Hide / Rugged Leather left out")
end
check(R.Tailoring[1229504].faction == "Horde" and R.Tailoring[1263425].faction == "Alliance", "faction carried (Tailoring 1229504 Horde, 1263425 Alliance)")
check(R.Tailoring[461692] and R.Leatherworking[461692] and R.Leatherworking[22815].item == 18258 and R.Tailoring[22813].item == 18258,
  "461692 in Tailoring and LW; item 18258 made by 22815 (LW) and 22813 (Tailoring)")

section("game data changes applied by hand (WoW Forever, 2026-11-16)")
local function reagent(r, id) for _, p in ipairs(r.r) do if p[1] == id then return p[2] end end end
check(R.Leatherworking[1263031].skill == 125, "Tanning Rack (1263031) needs Leatherworking 125: " .. R.Leatherworking[1263031].skill)
check(reagent(R.Tailoring[3758], 2997) == 5 and reagent(R.Tailoring[6688], 2997) == 5,
  ("Green / Red Woolen Bag take 5 Bolt of Woolen Cloth: %s / %s"):format(tostring(reagent(R.Tailoring[3758], 2997)),
    tostring(reagent(R.Tailoring[6688], 2997))))

section("enchant rows (Data/Enchants.lua)")
local E = ns.Enchants and ns.Enchants.rows or {}
do
  local kinds, bad, spells = {}, {}, {}
  local SLOTS = { feet = 1, shield = 1, twohand = 1, hands = 1, wrist = 1, weapon = 1, back = 1, neck = 1, offhand = 1, chest = 1 }
  for i, e in ipairs(E) do
    kinds[e.kind] = (kinds[e.kind] or 0) + 1
    local why
    if not isInt(e.spell, 1) or spells[e.spell] then why = "spell"
    elseif not isInt(e.enchant, 1) then why = "enchant"
    elseif not SLOTS[e.slot] then why = "slot"
    elseif not isInt(e.skill, 1, 320) then why = "skill"
    elseif e.src ~= "trainer" and e.src ~= "pattern" then why = "src"
    elseif type(e.name) ~= "string" or e.name == "" then why = "name"
    elseif type(e.r) ~= "table" or #e.r == 0 then why = "reagents"
    elseif (e.kind == "stats") ~= (type(e.stats) == "table") then why = "stats only on kind stats"
    elseif (e.kind == "damage") ~= (e.damage ~= nil) then why = "damage only on kind damage"
    end
    spells[e.spell] = true
    if why then bad[#bad + 1] = i .. " (" .. why .. ")" end
  end
  check(#bad == 0, "every enchant row is well formed, spells unique " .. table.concat(bad, ", "))
  check(#E == 175 and kinds.stats == 122 and kinds.damage == 10 and kinds.utility == 27 and kinds.proc == 16,
    ("enchant table %d rows: stats %d, damage %d, utility %d, proc %d"):format(#E, kinds.stats or 0, kinds.damage or 0,
      kinds.utility or 0, kinds.proc or 0))
  check(not spells[1217203] and not spells[435481] and spells[13419], "1217203 and 435481 (no counterpart in game) not in the table, 13419 is")
end

section("maintained here: no generator, no other addon")
do
  local stale = {}
  for _, f in ipairs(dataFiles) do
    if f ~= "Data/Weights.lua" then
      local head = readAll(ROOT .. f):sub(1, 800)
      if head:find("GENERATED", 1, true) or head:find("regenerate", 1, true) or head:find("CraftersJournal", 1, true) then
        stale[#stale + 1] = f
      end
    end
  end
  check(#stale == 0, "recipe Data headers say the data is maintained here (not generated from another addon) " .. table.concat(stale, ", "))
  local tools = {}
  for _, f in ipairs({ "gen_recipes.lua", "gen_sources.lua" }) do
    if io.open(DEV .. f, "rb") then tools[#tools + 1] = f end
  end
  local refs = {}
  for _, f in ipairs({ "paths.lua", "scorekit.lua" }) do
    local s = readAll(DEV .. f)
    if s:find("CraftersJournal", 1, true) or s:find("QuestieDB", 1, true) then refs[#refs + 1] = f end
  end
  check(#tools == 0 and #refs == 0, "no dev tool reads CraftersJournal or QuestieDB " .. table.concat(tools, ", ") .. " " .. table.concat(refs, ", "))
end

Kit.finish()
