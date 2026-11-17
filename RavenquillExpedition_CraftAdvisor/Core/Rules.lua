local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local IsSecret, SafeCall, ItemAPI, Scoring = GCA.IsSecret, GCA.SafeCall, GCA.ItemAPI, ns.Scoring
local EMPTY = {}

local CLOTH_ONLY = { MAGE = true, PRIEST = true, WARLOCK = true }
GCA.NO_HOLDABLE = { HUNTER = true, ROGUE = true }
GCA.RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

GCA.ARMOR_PROF_LEVEL = 40
GCA.BARRABLE_WEAPON = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
  [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true, [19] = true }
GCA.WEAPON_FROM = { [6] = { HUNTER = 20, WARRIOR = 20 } }
function GCA:ClassWeapons(class)
  local cw = ns.Weights and ns.Weights.classWeapons
  return class and cw and cw[class]
end
local TRAINED = "trained"
local ARMOR_FROM = {
  [3] = { WARRIOR = 0, PALADIN = 0, HUNTER = TRAINED, SHAMAN = TRAINED },
  [4] = { WARRIOR = TRAINED, PALADIN = TRAINED },
  [6] = { WARRIOR = 0, PALADIN = 0, SHAMAN = 0 },
}
local function ListHas(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end
local function WeaponFrom(self, class, sub)
  if not class or not self.BARRABLE_WEAPON[sub] then return 0 end
  local cw = self:ClassWeapons(class)
  if not cw then return 0 end
  if not ListHas(cw.weapons, sub) then return nil end
  local byClass = self.WEAPON_FROM[sub]
  return byClass and byClass[class] or 0
end
local function ArmorFrom(self, class, sub)
  if sub == 2 then return not CLOTH_ONLY[class] and 0 or nil end
  local byClass = ARMOR_FROM[sub]
  if byClass then
    local from = byClass[class]
    if from == TRAINED then return self.ARMOR_PROF_LEVEL end
    return from
  end
  if self.RELIC_CLASS[sub] == class then return 0 end
  return nil
end
function GCA:WearFrom(class, cand)
  local sub = cand.subClassID
  if cand.equipLoc == "INVTYPE_HOLDABLE" and class and self.NO_HOLDABLE[class] then return nil end
  if cand.classID == 2 then return WeaponFrom(self, class, sub) end
  if cand.classID ~= 4 then return nil end
  if cand.equipLoc == "INVTYPE_CLOAK" or sub == 0 or sub == 1 then return 0 end
  if not class then return 0 end
  return ArmorFrom(self, class, sub)
end
function GCA:CanWear(class, level, cand)
  local from = self:WearFrom(class, cand)
  return from ~= nil and (level or 0) >= from
end

GCA.DUAL_WIELD_SPELL = 674
function GCA:DualWieldFrom(class, spec, level, isSelf)
  local cw = self:ClassWeapons(class)
  if not (cw and spec) then return nil end
  local dwSpec = cw.dualWield[spec] == true
  for base, dw in pairs(cw.dualWieldSets or EMPTY) do
    if dw == spec then dwSpec = true end
    if base == spec and cw.dualWield[spec] and not cw.dualWieldFrom then dwSpec = false end
  end
  if not dwSpec then return nil end
  if isSelf then
    if self.SpellKnown(self.DUAL_WIELD_SPELL) then return 0 end
    if cw.dualWieldFrom and (level or 0) < cw.dualWieldFrom then return cw.dualWieldFrom end
    return nil
  end
  return cw.dualWieldFrom or 0
end

local function FormatToPattern(fmt)
  if type(fmt) ~= "string" or IsSecret(fmt) then return end
  local f = fmt:gsub("%%(%d+)%$([sd])", "%%%2")
  local out, i = {}, 1
  while i <= #f do
    local c = f:sub(i, i)
    if c == "%" then
      local n = f:sub(i + 1, i + 1)
      if n == "s" then out[#out + 1] = "(.+)"
      elseif n == "d" then out[#out + 1] = "(%d+)"
      elseif n == "%" then out[#out + 1] = "%%"
      else return end
      i = i + 2
    else
      out[#out + 1] = c:find("[%(%)%.%[%]%*%+%-%?%^%$]") and ("%" .. c) or c
      i = i + 1
    end
  end
  local p = "^" .. table.concat(out) .. "$"
  if not pcall(string.match, "", p) then return end
  return p
end
GCA.FormatToPattern = FormatToPattern
local function ClassNameSet(list)
  local set = {}
  for name in list:gmatch("[^,]+") do set[(name:gsub("^%s+", ""):gsub("%s+$", "")):lower()] = true end
  return set
end

local function ReadRestrictionLine(c, text, reqSkill, classes)
  local what = reqSkill and SafeCall(string.match, text, reqSkill)
  local skill = what and what:match("^(.-) %(%d+%)$")
  if skill then c.skill = skill end
  local list = classes and SafeCall(string.match, text, classes)
  if list then c.classes = ClassNameSet(list) end
end

function GCA:ItemRestrictions(itemID)
  self.restrCache = self.restrCache or {}
  if self.restrCache[itemID] then return self.restrCache[itemID] end
  local get = C_TooltipInfo and C_TooltipInfo.GetItemByID
  local data = get and SafeCall(get, itemID)
  if type(data) ~= "table" or type(data.lines) ~= "table" or IsSecret(data.lines) then return EMPTY end
  local c = {}
  local reqSkill = FormatToPattern(ITEM_REQ_SKILL or "Requires %s")
  local classes = FormatToPattern(ITEM_CLASSES_ALLOWED or "Classes: %s")
  for _, line in ipairs(data.lines) do
    local text = type(line) == "table" and line.leftText
    if type(text) == "string" and not IsSecret(text) then ReadRestrictionLine(c, text, reqSkill, classes) end
  end
  self.restrCache[itemID] = c
  return c
end

function GCA:PassesRestrictions(itemID, class, isSelf)
  local r = self:ItemRestrictions(itemID)
  if r.classes and class then
    local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
    if not ((m and r.classes[m:lower()]) or (f and r.classes[f:lower()]) or r.classes[class:lower()]) then return false end
  end
  if r.skill then
    if not isSelf then return false end
    for key, p in pairs(self:OwnProfessions()) do
      if key == r.skill or p.name == r.skill then return true end
    end
    return false
  end
  return true
end

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

local function NextSetBonus(set, have)
  for _, bonus in ipairs(set.bonuses or {}) do
    if bonus.n > have then return bonus end
  end
end

local function MissingPieceName(self, id, prof)
  local info = self:GetInfo(id)
  local name = info and info.name or string.format(L.ITEM_FALLBACK, id)
  local spell = self:ItemToSpell(prof)[id]
  if spell and not self:IsBrowse(prof) and self:IsKnown(spell, prof) then name = string.format(L.HINT_YOU_CRAFT, name) end
  return name
end

local function MissingPieces(self, set, afterIDs, prof)
  local wearing, missing = {}, {}
  for _, id in ipairs(afterIDs) do wearing[id] = true end
  for _, id in ipairs(set.items) do
    if not wearing[id] then missing[#missing + 1] = MissingPieceName(self, id, prof) end
  end
  return missing
end

function GCA:SetHint(itemID, afterIDs, prof)
  local sets = self:ItemSets()
  local setID = sets.ofItem[itemID]
  local set = setID and sets.bySet[setID]
  if not set then return end
  local have = Scoring.piecesOf(afterIDs, sets)[setID] or 0
  local bonus = NextSetBonus(set, have)
  if not bonus then return end
  local missing = MissingPieces(self, set, afterIDs, prof or self:SelectedProfession())
  local need = bonus.n - have
  local what = next(bonus.stats or {}) and self:BonusText(bonus.stats) or L.HINT_UNSCORED
  if need == 1 then return string.format(L.HINT_ONE, set.name, what, table.concat(missing, L.HINT_OR)) end
  return string.format(L.HINT_MORE, set.name, what, need, table.concat(missing, ", "))
end

local function Better(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if math.abs(a.points - b.points) > 1e-9 then return a.points > b.points end
  if a.known ~= b.known then return a.known end
  if (a.kind == "enchant") ~= (b.kind == "enchant") then return b.kind == "enchant" end
  return a.slot < b.slot
end
GCA.BetterSuggestion = Better

local function OtherFaction(row, faction)
  return row.faction and faction and row.faction ~= faction
end
function GCA.Offerable(known, showAll, row, faction)
  if known then return true end
  return showAll and not OtherFaction(row, faction)
end
function GCA.KeepSuggestion(best, all, bestKey, group, sug)
  local cur = best[bestKey]
  if not cur or Better(sug, cur) then best[bestKey] = sug end
  if not all then return end
  local rows = all[group] or {}
  all[group] = rows
  rows[#rows + 1] = sug
end
GCA.TIER_PARTNER = 2
GCA.HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

function GCA:PairInfo(mh, oh)
  local stats = {}
  for k, v in pairs(mh.cstats or EMPTY) do stats[k] = v end
  local off = Scoring.inOffHand({ stats = oh.cstats or EMPTY })
  for k, v in pairs(off.stats or EMPTY) do stats[k] = (stats[k] or 0) + v end
  return { name = (mh.name or "?") .. " + " .. (oh.name or "?"), quality = mh.quality, icon = mh.icon, link = mh.link,
    cstats = stats, speed = mh.speed, pair = { mh, oh } }
end

local function Order(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  local fa, fb = a.future and true or false, b.future and true or false
  if fa ~= fb then return fb end
  return Better(a, b)
end
GCA.SuggestionOrder = Order

