local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local priv = GCA.priv
local IsSecret, SafeCall, ItemAPI, Scoring, EMPTY = priv.IsSecret, priv.SafeCall, priv.ItemAPI, priv.Scoring, priv.EMPTY

---------------------------------------------------------------------------
-- Suggestions: who can wear what, the candidates, set hints and the order of suggestions
---------------------------------------------------------------------------
local CLOTH_ONLY = { MAGE = true, PRIEST = true, WARLOCK = true }
-- Classes that can't hold an off-hand item (SimGear Classes.lua equip.noHoldable)
GCA.NO_HOLDABLE = { HUNTER = true, ROGUE = true }
-- Relics (armor subclass 7 libram, 8 idol, 9 totem; SimGear Classes.lua equip.armor)
GCA.RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

-- Armor: SimGear's equip tables: plate Warrior/Paladin 40+, mail Warrior/Paladin always and Hunter/Shaman 40+,
-- shields Warrior/Paladin/Shaman, relics per class, no held off-hand for Hunter/Rogue.
-- Weapons: the class's weapon subclasses from SimGear Classes.lua equip.weapons (Data/Weights.lua
-- classWeapons, generated); a subclass SimGear never bars (fishing poles, miscellaneous) any class can use;
-- polearms for Hunter/Warrior from 20 (client SkillRaceClassInfo, per SimGear's Warrior comment). Weapon skill
-- levels are ignored (we can't read a guildie's).
-- WearFrom returns the level from which the class can use the item (0 = any level) or nil (never).
-- callers pass the look-ahead level to CanWear; a piece only wearable later is then a future row.
GCA.ARMOR_PROF_LEVEL = 40
-- Weapon subclasses SimGear's Classes.barredType can bar (its WEAPON_TYPE names; golden-tested in harness_score).
GCA.BARRABLE_WEAPON = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
  [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [19] = true }
GCA.WEAPON_FROM = { [6] = { HUNTER = 20, WARRIOR = 20 } } -- polearms
function GCA:ClassWeapons(class)
  local cw = ns.Weights and ns.Weights.classWeapons
  return class and cw and cw[class]
end
function GCA:WearFrom(class, cand)
  local sub = cand.subClassID
  if cand.equipLoc == "INVTYPE_HOLDABLE" and class and self.NO_HOLDABLE[class] then return nil end
  if cand.classID == 2 then
    if not class or not self.BARRABLE_WEAPON[sub] then return 0 end
    local cw = self:ClassWeapons(class)
    if not cw then return 0 end -- no data: never bar (SimGear: unknown never bars)
    local ok = false
    for _, s in ipairs(cw.weapons) do if s == sub then ok = true end end
    if not ok then return nil end
    return self.WEAPON_FROM[sub] and self.WEAPON_FROM[sub][class] or 0
  end
  if cand.classID ~= 4 then return nil end
  if cand.equipLoc == "INVTYPE_CLOAK" or sub == 0 or sub == 1 then return 0 end
  if not class then return 0 end
  if sub == 2 then return not CLOTH_ONLY[class] and 0 or nil end
  if sub == 3 then
    if class == "WARRIOR" or class == "PALADIN" then return 0 end
    if class == "HUNTER" or class == "SHAMAN" then return self.ARMOR_PROF_LEVEL end
    return nil
  end
  if sub == 4 then return (class == "WARRIOR" or class == "PALADIN") and self.ARMOR_PROF_LEVEL or nil end
  if sub == 6 then return (class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN") and 0 or nil end
  if self.RELIC_CLASS[sub] then return self.RELIC_CLASS[sub] == class and 0 or nil end
  return nil
end
function GCA:CanWear(class, level, cand)
  local from = self:WearFrom(class, cand)
  return from ~= nil and (level or 0) >= from
end

-- Dual wield (SimGear Spec.canDualWield + Classes dualWield/dualWieldFrom/dualWieldSets). Returns the
-- level from which this member's spec holds a weapon in each hand (0 = now), or nil. The spec must dual-wield in
-- SimGear's sims (Rogue all, Hunter all, Warrior Fury, Shaman only as ENHANCEMENT_DW = a one-hander was seen in the
-- off hand). Your own character: Dual Wield (spell 674) known wins (not known = no, whatever the level; known = yes).
-- Guildies: the class trainer level (Rogue 10, Hunter/Warrior 20); a class without one (Shaman) needs the DW spec.
GCA.DUAL_WIELD_SPELL = 674
function GCA:DualWieldFrom(class, spec, level, isSelf)
  local cw = self:ClassWeapons(class)
  if not (cw and spec) then return nil end
  local dwSpec = cw.dualWield[spec] == true
  for base, dw in pairs(cw.dualWieldSets or EMPTY) do
    if dw == spec then dwSpec = true end
    if base == spec and cw.dualWield[spec] and not cw.dualWieldFrom then dwSpec = false end -- Shaman 2H sim
  end
  if not dwSpec then return nil end
  if isSelf then
    if self.SpellKnown(self.DUAL_WIELD_SPELL) then return 0 end
    -- not known: only a later level (look-ahead) can bring it, from the trainer level
    if cw.dualWieldFrom and (level or 0) < cw.dualWieldFrom then return cw.dualWieldFrom end
    return nil
  end
  return cw.dualWieldFrom or 0
end

-- Tooltip restrictions of a crafted item (a judgement call): "Requires Engineering (225)" and "Classes: Paladin".
-- Read from C_TooltipInfo where the client has it; nothing readable = no restriction (unknown never bars).
-- Returns { skill = "Engineering", classes = { [localized class name] = true } } (fields nil when absent).
-- Client format string -> anchored Lua pattern, or nil. Handles positional specifiers used by localized
-- clients ("%1$s" on deDE: the old version turned "%1" into a back-reference -> "invalid capture index").
local function FormatToPattern(fmt)
  if type(fmt) ~= "string" or IsSecret(fmt) then return end
  local f = fmt:gsub("%%(%d+)%$([sd])", "%%%2")            -- "%1$s" -> "%s"
  local out, i = {}, 1
  while i <= #f do
    local c = f:sub(i, i)
    if c == "%" then
      local n = f:sub(i + 1, i + 1)
      if n == "s" then out[#out + 1] = "(.+)"
      elseif n == "d" then out[#out + 1] = "(%d+)"
      elseif n == "%" then out[#out + 1] = "%%"
      else return end                                      -- an unknown specifier: don't guess
      i = i + 2
    else
      out[#out + 1] = c:find("[%(%)%.%[%]%*%+%-%?%^%$]") and ("%" .. c) or c
      i = i + 1
    end
  end
  local p = "^" .. table.concat(out) .. "$"
  if not pcall(string.match, "", p) then return end         -- never hand an invalid pattern to match()
  return p
end
GCA.FormatToPattern = FormatToPattern
function GCA:ItemRestrictions(itemID)
  self.restrCache = self.restrCache or {}
  local c = self.restrCache[itemID]
  if c then return c end
  local get = C_TooltipInfo and C_TooltipInfo.GetItemByID
  local data = get and SafeCall(get, itemID)
  if type(data) ~= "table" or type(data.lines) ~= "table" or IsSecret(data.lines) then return EMPTY end
  c = {}
  local reqSkill = FormatToPattern(ITEM_REQ_SKILL or "Requires %s")
  local classes = FormatToPattern(ITEM_CLASSES_ALLOWED or "Classes: %s")
  for _, line in ipairs(data.lines) do
    local t = type(line) == "table" and line.leftText
    if type(t) == "string" and not IsSecret(t) then
      local what = reqSkill and SafeCall(string.match, t, reqSkill)
      -- a skill requirement has a rank in brackets ("Engineering (225)"); "Requires Level 40" has none
      local skill = what and what:match("^(.-) %(%d+%)$")
      if skill then c.skill = skill end
      local list = classes and SafeCall(string.match, t, classes)
      if list then
        c.classes = {}
        for name in list:gmatch("[^,]+") do c.classes[(name:gsub("^%s+", ""):gsub("%s+$", "")):lower()] = true end
      end
    end
  end
  self.restrCache[itemID] = c
  return c
end

-- false when the tooltip bars `class` (class list) or the wearer can't have the required skill.
function GCA:PassesRestrictions(itemID, class, isSelf)
  local r = self:ItemRestrictions(itemID)
  if r.classes and class then
    -- localized names (male/female), and the token itself where no localized table exists (case-insensitive)
    local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
    if not ((m and r.classes[m:lower()]) or (f and r.classes[f:lower()]) or r.classes[class:lower()]) then return false end
  end
  if r.skill then
    -- we don't know a guildie's professions: only you, and only for a skill you have
    if not isSelf then return false end
    local ok = false
    for _, p in pairs(self:OwnProfessions()) do if p.name == r.skill then ok = true end end
    for key in pairs(self:OwnProfessions()) do if key == r.skill then ok = true end end
    return ok
  end
  return true
end

-- Equippable crafted items of a profession (needs only the client's static item DB), weapons included (W1).
function GCA:GetCandidates(prof)
  prof = prof or self:SelectedProfession()
  self.candidates = self.candidates or {}
  if self.candidates[prof] then return self.candidates[prof] end
  local list, missing = {}, false
  for spellID, r in pairs(self:RecipeTable(prof)) do
    local _, _, _, equipLoc, icon, classID, subClassID = SafeCall(ItemAPI.Instant, r.item)
    if equipLoc == nil then
      missing = true
    elseif self.SLOTS_FOR[equipLoc] then
      list[#list + 1] = {
        spellID = spellID, itemID = r.item, recipe = r, equipLoc = equipLoc,
        icon = icon, classID = classID, subClassID = subClassID,
      }
    end
  end
  if not missing then self.candidates[prof] = list end
  return list
end

-- Short text for set-bonus stats: "+2% hit", "+20 spell power" (stat words localized, H4 / review M-1).
local BONUS_KEYS = { AttackPower = "BONUS_ATTACKPOWER", RangedAttackPower = "BONUS_RANGEDATTACKPOWER",
  SpellPower = "BONUS_SPELLPOWER", HealingPower = "BONUS_HEALINGPOWER", Stamina = "BONUS_STAMINA",
  Strength = "BONUS_STRENGTH", Agility = "BONUS_AGILITY", Intellect = "BONUS_INTELLECT", Spirit = "BONUS_SPIRIT",
  Armor = "BONUS_ARMOR", Defense = "BONUS_DEFENSE", BlockValue = "BONUS_BLOCKVALUE" }
local PCT_KEYS = { MeleeHit = "BONUS_MELEEHIT", SpellHit = "BONUS_SPELLHIT", MeleeCrit = "BONUS_MELEECRIT",
  SpellCrit = "BONUS_SPELLCRIT", Dodge = "BONUS_DODGE", Parry = "BONUS_PARRY", Block = "BONUS_BLOCK" }
function GCA:BonusText(stats)
  local parts, used = {}, {}
  for _, pair in ipairs({ { "MeleeHit", "SpellHit", "BONUS_HIT" }, { "MeleeCrit", "SpellCrit", "BONUS_CRIT" } }) do
    local a, b = stats[pair[1]], stats[pair[2]]
    if a and b and a == b then
      parts[#parts + 1] = string.format("+%g%% %s", a, L[pair[3]]); used[pair[1]], used[pair[2]] = true, true
    end
  end
  local keys = {}
  for k in pairs(stats) do if not used[k] then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if PCT_KEYS[k] then
      parts[#parts + 1] = string.format("+%g%% %s", stats[k], L[PCT_KEYS[k]])
    else
      parts[#parts + 1] = string.format("+%g %s", stats[k], BONUS_KEYS[k] and L[BONUS_KEYS[k]] or k)
    end
  end
  return table.concat(parts, ", ")
end

-- "Devilsaur Armor: +2% hit with Devilsaur Gauntlets": the next bonus of the candidate's set not reached yet.
-- Whole localized sentences (HINT_ONE / HINT_MORE), so German can use its own word order (review M-1).
function GCA:SetHint(itemID, afterIDs, prof)
  local sets = self:ItemSets()
  local setID = sets.ofItem[itemID]
  local set = setID and sets.bySet[setID]
  if not set then return end
  local have = Scoring.piecesOf(afterIDs, sets)[setID] or 0
  local wearing = {}
  for _, id in ipairs(afterIDs) do wearing[id] = true end
  for _, bonus in ipairs(set.bonuses or {}) do
    if bonus.n > have then
      local missing = {}
      for _, id in ipairs(set.items) do
        if not wearing[id] then
          local info = self:GetInfo(id)
          local name = info and info.name or string.format(L.ITEM_FALLBACK, id)
          prof = prof or self:SelectedProfession()
          local spell = self:ItemToSpell(prof)[id]
          if spell and not self:IsBrowse(prof) and self:IsKnown(spell, prof) then name = string.format(L.HINT_YOU_CRAFT, name) end
          missing[#missing + 1] = name
        end
      end
      local need = bonus.n - have
      local what = next(bonus.stats or {}) and self:BonusText(bonus.stats) or L.HINT_UNSCORED
      if need == 1 then return string.format(L.HINT_ONE, set.name, what, table.concat(missing, L.HINT_OR)) end
      return string.format(L.HINT_MORE, set.name, what, need, table.concat(missing, ", "))
    end
  end
end

-- Order of suggestions (user 2026-11-14: no more %, sorted by the gain itself): tier 1 = real gains (upgrades,
-- empty-slot fills, no-baseline upgrades) by points (AP/SP/RAP-equivalents), tier TIER_PARTNER = one-handers /
-- off hands next to a worn two-hander (scored alone, not a real gain) by points.
-- The member list ranks members by their best suggestion with the same order.
local function Better(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if math.abs(a.points - b.points) > 1e-9 then return a.points > b.points end
  if a.known ~= b.known then return a.known end
  if (a.kind == "enchant") ~= (b.kind == "enchant") then return b.kind == "enchant" end -- items before enchants
  return a.slot < b.slot
end
GCA.BetterSuggestion = Better
-- tier of one-handers / off hands next to a worn two-hander (scored alone): after the real gains.
GCA.TIER_PARTNER = 2
-- Equip locations compared as the main hand + off hand pair.
GCA.HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

-- The worn main hand + off hand as one "item" for a two-hander's comparison (W4: it replaces both): name "A + B",
-- canonical stats summed with the off hand counted as it weighs there (SimGear inOffHand).
function GCA:PairInfo(mh, oh)
  local stats = {}
  for k, v in pairs(mh.cstats or EMPTY) do stats[k] = v end
  local off = Scoring.inOffHand({ stats = oh.cstats or EMPTY })
  for k, v in pairs(off.stats or EMPTY) do stats[k] = (stats[k] or 0) + v end
  return { name = (mh.name or "?") .. " + " .. (oh.name or "?"), quality = mh.quality, icon = mh.icon, link = mh.link,
    cstats = stats, speed = mh.speed, pair = { mh, oh } }
end

-- Display order: Better's tiers, but inside each tier the items the member can wear now come first and
-- the look-ahead ones (too high level yet) after them. Better alone still picks the best suggestion per slot.
local function Order(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  local fa, fb = a.future and true or false, b.future and true or false
  if fa ~= fb then return fb end
  return Better(a, b)
end
GCA.SuggestionOrder = Order

-- shared with the files loaded after this one (priv)
priv.Better = Better
priv.Order = Order
