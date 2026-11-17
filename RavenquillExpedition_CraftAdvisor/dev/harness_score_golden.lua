local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "scorekit.lua")
local section, CLASSES, SGW, W, SGns, check, ns = H.section, H.CLASSES, H.SGW, H.W, H.SGns, H.check, H.ns
local SGSets, rnd, Scoring, near, LEVELS, SHARES = H.SGSets, H.rnd, H.Scoring, H.near, H.LEVELS, H.SHARES
local GCA, sgCompose, CRAFT, itemDB, OURSETS, SG = H.GCA, H.sgCompose, H.CRAFT, H.itemDB, H.OURSETS, H.SG
local cap, sgEnv, SGItems = H.cap, H.sgEnv, H.SGItems

section("Generator: Data/Weights.lua equals SimGear's tables (every set, every weight)")
do
  local sets, bad, dungeon = 0, 0, 0
  for _, class in ipairs(CLASSES) do
    for spec, list in pairs(SGW[class]) do
      if spec:match("_DUNGEON$") then
        dungeon = dungeon + 1
        if W.classes[class][spec] then bad = bad + 1; print("    dungeon set kept: " .. spec) end
      else
        local ours = W.classes[class][spec]
        if not ours or #ours ~= #list then bad = bad + 1; print("    count differs: " .. class .. " " .. spec)
        else
          for i, s in ipairs(list) do
            local o = ours[i]
            sets = sets + 1
            local keys = {}
            for k in pairs(s.weights) do keys[k] = true end
            for k in pairs(o.weights) do keys[k] = true end
            for k in pairs(keys) do
              if (s.weights[k] or 0) ~= (o.weights[k] or 0) then bad = bad + 1; print("    weight differs: " .. class .. " " .. spec .. " " .. i .. " " .. k) end
            end
            for k, v in pairs(s.survival or {}) do if (o.survival or {})[k] ~= v then bad = bad + 1 end end
            for k in pairs(o.survival or {}) do if not (s.survival or {})[k] then bad = bad + 1 end end
            if s.source.kind ~= o.source.kind or s.source.minLevel ~= o.source.minLevel or s.source.maxLevel ~= o.source.maxLevel
              or s.source.label ~= o.source.label then bad = bad + 1; print("    source differs: " .. class .. " " .. spec .. " " .. i) end
            if (s.speedCurves ~= nil) ~= (o.speedCurves ~= nil) then bad = bad + 1; print("    speedCurves missing: " .. class .. " " .. spec) end
            if SGns.Plan.unitKey(s) and SGns.Plan.unitKey(s) ~= o.unit then bad = bad + 1; print("    unit differs: " .. class .. " " .. spec .. " " .. i) end
            for _, f in ipairs({ "stdev", "derivation", "hitParts", "pooled", "blend", "effects", "notes", "placeholders", "defensePastCap", "hitPastCap" }) do
              if o[f] ~= nil then bad = bad + 1; print("    not stripped: " .. f) end
            end
          end
        end
      end
    end
  end
  check(bad == 0 and sets == 175, ("%d weight sets identical to SimGear's, %d dungeon specs left out, %d differences"):format(sets, dungeon, bad))
  local recipeOf = {}
  for _, prof in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting" }) do
    for spellID, r in pairs(ns.Recipes[prof]) do recipeOf[r.item] = spellID end
  end
  local missing, extra = 0, 0
  for _, class in ipairs(CLASSES) do
    for id, set in pairs(SGSets[class].bySet) do
      local craftable = false
      for _, item in ipairs(set.items) do if recipeOf[item] then craftable = true end end
      if craftable and not W.itemSets[id] then missing = missing + 1 end
    end
  end
  for id, set in pairs(W.itemSets) do
    local craftable = false
    for _, item in ipairs(set.items) do if recipeOf[item] then craftable = true end end
    if not craftable then extra = extra + 1 end
  end
  local n = 0 for _ in pairs(W.itemSets) do n = n + 1 end
  check(missing == 0 and extra == 0 and n == 15, ("item sets: %d kept (all with a craftable piece of the five professions), %d missing, %d extra"):format(n, missing, extra))
  check(W.itemSets[321] and W.itemSets[1972] and W.itemSets[421], "sets of Blacksmithing (Imperial Plate) and Tailoring (Stormcloth, Bloodvine) kept")
  check(W.itemSets[143] and W.itemSets[143].bonuses[1].stats.MeleeHit == 2, "Devilsaur Armor 2-piece: +2 MeleeHit / SpellHit")
end

section("Stats: our normalize = SimGear Stats.normalize (ratings -> %, Crit/Hit expand)")
do
  local keys = {}
  for k in pairs(SGns.Stats.KEY_MAP) do keys[#keys + 1] = k end
  table.sort(keys)
  local diffs = 0
  for trial = 1, 300 do
    local raw = {}
    for _ = 1, rnd(6) do raw[keys[rnd(#keys)]] = rnd(40) end
    if rnd(5) == 1 then raw.SOME_NEW_KEY = 3 end
    local a, ua = SGns.Stats.normalize(raw)
    local b, ub = Scoring.normalize(raw)
    for k, v in pairs(a) do if not near(v, b[k]) then diffs = diffs + 1 end end
    for k in pairs(b) do if a[k] == nil then diffs = diffs + 1 end end
    if table.concat(ua, ",") ~= table.concat(ub, ",") then diffs = diffs + 1 end
  end
  check(diffs == 0, "300 random raw stat tables normalize identically (" .. diffs .. " differences)")
  local s = Scoring.normalize({ ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 5,
    ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_PARRY_RATING_SHORT = 15, ITEM_MOD_SPELL_POWER = 9, ITEM_MOD_SPELL_POWER_SHORT = 9 })
  check(s.MeleeHit == 1 and s.SpellHit == 1 and s.MeleeCrit == 1 and s.SpellCrit == 1 and s.Block == 1 and s.Dodge == 1 and s.Parry == 1,
    "hit 10 / crit 14 / block 5 / dodge 12 / parry 15 rating = 1 % each (the old ÷14 bug is gone)")
  check(s.SpellPower == 9, "ITEM_MOD_SPELL_POWER counted once when _SHORT is there too")
end

section("Golden: composed weight sets (pickSet + survival layer) = SimGear Score.pickSet + Plan.apply")
do
  local cmp, bad = 0, 0
  for _, class in ipairs(CLASSES) do
    for spec in pairs(W.classes[class]) do
      for _, level in ipairs(LEVELS) do
        for _, share in ipairs(SHARES) do
          GCA.db.settings.survival = share
          local e = GCA:WeightSetFor(class, spec, level)
          local sg, sgRaw = sgCompose(class, spec, level, share)
          cmp = cmp + 1
          local keys = {}
          for k in pairs(sg.weights) do keys[k] = true end
          for k in pairs(e.set.weights) do keys[k] = true end
          local ok = sgRaw.source.minLevel == e.raw.source.minLevel and sgRaw.source.kind == e.raw.source.kind
          for k in pairs(keys) do if not near(sg.weights[k], e.set.weights[k], 1e-12) then ok = false end end
          if not ok then bad = bad + 1; if bad <= 5 then print(("    differs: %s %s Lv%d share %.1f"):format(class, spec, level, share)) end end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  check(bad == 0, ("%d class/spec/level/share combinations identical (%d differ)"):format(cmp, bad))
end

section("Golden: item comparisons (real LW crafts, random worn gear, set bonuses) = SimGear Score.compare")
do
  local cmp, bad, statuses, withSets = 0, 0, {}, 0
  local SLOT_OF = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }
  for _, class in ipairs(CLASSES) do
    local pool = CRAFT[class]
    if #pool > 0 then
      for spec in pairs(W.classes[class]) do
        for _, level in ipairs({ 9, 25, 26, 40, 54, 58, 60 }) do
          local share = SHARES[rnd(3)]
          GCA.db.settings.survival = share
          local e = GCA:WeightSetFor(class, spec, level)
          local sg = sgCompose(class, spec, level, share)
          for _ = 1, 25 do
            local equipped = {}
            for _, it in ipairs(pool) do
              local slots = SLOT_OF[it.equipLoc]
              local slot = slots[rnd(#slots)]
              if rnd(3) == 1 then equipped[slot] = it end
            end
            if rnd(3) == 1 and itemDB[15063] then equipped[10] = { itemID = 15063, equipLoc = "INVTYPE_HAND", stats = Scoring.normalize(itemDB[15063].raw) } end
            local cand = pool[rnd(#pool)]
            local a = SGns.Score.compare(cand, equipped, sg, { sets = SGSets[class] })
            local b = Scoring.compare(cand, equipped, e.set, OURSETS)
            cmp = cmp + 1
            local ok = (a == nil) == (b == nil)
            if a and b then
              ok = ok and a.status == b.status and near(a.newValue, b.newValue) and near(a.oldValue, b.oldValue)
                and ((a.pct == nil and b.pct == nil) or near(a.pct, b.pct)) and near(a.setDelta or 0, b.setDelta or 0)
              statuses[a.status] = (statuses[a.status] or 0) + 1
              if a.sets then withSets = withSets + 1 end
            end
            if not ok then
              bad = bad + 1
              if bad <= 5 then print(("    differs: %s %s Lv%d item %d: %s %s vs %s %s"):format(class, spec, level, cand.itemID,
                a and a.status, a and a.newValue, b and b.status, b and b.newValue)) end
            end
          end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  local st = {}
  for k, v in pairs(statuses) do st[#st + 1] = k .. " " .. v end
  table.sort(st)
  check(bad == 0, ("%d comparisons identical to SimGear (%d differ); %s; %d with a set change"):format(cmp, bad, table.concat(st, ", "), withSets))
end

section("W: weapons - golden compare/speed vs SimGear, proficiency, dual wield, speed parse, crafts end to end")
do
  local WEAPON_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_2HWEAPON = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
  local cmp, bad, statuses, offHand, withSpeed = 0, 0, {}, 0, 0
  local speedCmp, speedBad = 0, 0
  for _, class in ipairs(CLASSES) do
    local ens = {}
    assert(loadfile(SG .. "SimGearForever_" .. cap(class) .. "/data/items/" .. class .. "_extras.lua", "t", sgEnv()))("x", ens)
    local X = ens.Extras[class]
    local pool, byLoc = {}, {}
    local ids = {}
    for id in pairs(SGItems[class]) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local it = SGItems[class][id]
      if WEAPON_LOCS[it.slot] and type(it.stats) == "table" then
        local stats = {}
        for k, v in pairs(it.stats) do stats[k] = v end
        local w = { itemID = id, equipLoc = it.slot, stats = stats, speed = it.speed or (X.speeds and X.speeds[id]),
          dagger = (X.daggers and X.daggers[id]) and true or nil }
        pool[#pool + 1] = w
        byLoc[it.slot] = byLoc[it.slot] or {}
        table.insert(byLoc[it.slot], w)
      end
    end
    local function pick(list) return list and #list > 0 and list[rnd(#list)] or nil end
    local specs = {}
    for spec in pairs(W.classes[class]) do specs[#specs + 1] = spec end
    table.sort(specs)
    for _, spec in ipairs(specs) do
      for _, level in ipairs({ 25, 30, 40, 50, 60 }) do
        local share = SHARES[rnd(3)]
        GCA.db.settings.survival = share
        local e = GCA:WeightSetFor(class, spec, level)
        local sg = sgCompose(class, spec, level, share)
        for _ = 1, 20 do
          local equipped = {}
          local r = rnd(4)
          if r == 1 then equipped[16] = pick(byLoc.INVTYPE_2HWEAPON)
          elseif r == 2 then equipped[16] = pick(byLoc.INVTYPE_WEAPON); equipped[17] = pick(byLoc.INVTYPE_WEAPON) or pick(byLoc.INVTYPE_WEAPONOFFHAND)
          elseif r == 3 then equipped[16] = pick(byLoc.INVTYPE_WEAPONMAINHAND) or pick(byLoc.INVTYPE_WEAPON); equipped[17] = pick(byLoc.INVTYPE_SHIELD) or pick(byLoc.INVTYPE_HOLDABLE)
          end
          if rnd(2) == 1 then equipped[18] = pick(byLoc.INVTYPE_RANGED) or pick(byLoc.INVTYPE_RANGEDRIGHT) end
          local cand = pick(pool)
          if cand then
            local dw = rnd(2) == 1
            local a = SGns.Score.compare(cand, equipped, sg, { dualWield = dw, sets = SGSets[class] })
            local b = Scoring.compare(cand, equipped, e.set, OURSETS, nil, { dualWield = dw })
            cmp = cmp + 1
            local ok = (a == nil) == (b == nil)
            if a and b then
              ok = ok and a.status == b.status and near(a.newValue, b.newValue) and near(a.oldValue, b.oldValue)
                and ((a.pct == nil and b.pct == nil) or near(a.pct, b.pct)) and a.hand == b.hand
                and table.concat(a.replaces or {}, ",") == table.concat(b.replaces or {}, ",") and near(a.setDelta or 0, b.setDelta or 0)
              statuses[a.status] = (statuses[a.status] or 0) + 1
              if a.hand == "off" then offHand = offHand + 1 end
            end
            if cand.speed then withSpeed = withSpeed + 1 end
            if not ok then
              bad = bad + 1
              if bad <= 5 then print(("    differs: %s %s Lv%d item %d dw %s: %s %s vs %s %s"):format(class, spec, level, cand.itemID, tostring(dw),
                a and a.status, a and a.newValue, b and b.status, b and b.newValue)) end
            end
            for _, key in ipairs({ "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }) do
              speedCmp = speedCmp + 1
              if not near(SGns.Score.speedFactor(cand, key, sg), Scoring.speedFactor(cand, key, e.set)) then speedBad = speedBad + 1 end
            end
            speedCmp = speedCmp + 1
            if not near((SGns.Score.speedValue(cand, sg)), (Scoring.speedValue(cand, e.set))) then speedBad = speedBad + 1 end
          end
        end
      end
    end
  end
  GCA.db.settings.survival = 0.5
  local st = {}
  for k, v in pairs(statuses) do st[#st + 1] = k .. " " .. v end
  table.sort(st)
  check(bad == 0 and cmp > 500 and (statuses["needs-partner"] or 0) > 0 and offHand > 0,
    ("W golden: %d weapon comparisons identical to SimGear's compareWeapon (%d differ); %s; %d in the off hand; %d with a speed"):format(
      cmp, bad, table.concat(st, ", "), offHand, withSpeed))
  check(speedBad == 0, ("W golden: speedFactor/speedValue identical to SimGear on %d cases (%d differ)"):format(speedCmp, speedBad))
  local e = GCA:WeightSetFor("PALADIN", "RETRIBUTION", 60)
  local slow = { equipLoc = "INVTYPE_2HWEAPON", stats = { TwoHandDps = 50 }, speed = 3.8 }
  local none = { equipLoc = "INVTYPE_2HWEAPON", stats = { TwoHandDps = 50 } }
  check(Scoring.itemValue(slow, e.set) > Scoring.itemValue(none, e.set) and Scoring.speedFactor({ equipLoc = "INVTYPE_WEAPON", dagger = true, speed = 1.0 }, "MainHandDps", e.set)
    == 1 + e.set.speedCurves.mainHand.perSecond * (1.3 - 1.7), "speed: a slow two-hander scores higher for Ret 60; daggers clamp to 1.3..1.9 around 1.7")
end

H.finish()
