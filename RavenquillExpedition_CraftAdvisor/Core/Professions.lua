local ADDON, ns = ...
local GCA = ns.GCA
local priv = GCA.priv
local IsSecret, SafeCall, ItemIDFrom = priv.IsSecret, priv.SafeCall, priv.ItemIDFrom

---------------------------------------------------------------------------
-- Recipes you know
---------------------------------------------------------------------------
-- Professions. Order = default choice order and the order in the selector.
GCA.PROFESSIONS = {
  { key = "Leatherworking", skillLine = 165, icon = "Interface\\Icons\\Trade_LeatherWorking", crafter = "a leatherworker", spec = true },
  { key = "Blacksmithing", skillLine = 164, icon = "Interface\\Icons\\Trade_BlackSmithing", crafter = "a blacksmith", spec = true },
  { key = "Tailoring", skillLine = 197, icon = "Interface\\Icons\\Trade_Tailoring", crafter = "a tailor" },
  { key = "Engineering", skillLine = 202, icon = "Interface\\Icons\\Trade_Engineering", crafter = "an engineer", spec = true },
  { key = "Enchanting", skillLine = 333, icon = "Interface\\Icons\\Trade_Engraving", crafter = "an enchanter" },
}
GCA.PROF_BY_KEY, GCA.PROF_BY_LINE = {}, {}
for _, p in ipairs(GCA.PROFESSIONS) do GCA.PROF_BY_KEY[p.key], GCA.PROF_BY_LINE[p.skillLine] = p, p end
GCA.DEFAULT_PROFESSION = "Leatherworking"
-- GetProfessions() may return nothing for a moment after login: an empty answer is trusted only this long after login
GCA.PROF_TRUST_DELAY = 10

local EMPTY = {}
-- Item recipes of a profession: [spellID] = { item, skill, src, name, r, faction }.
function GCA:RecipeTable(prof)
  prof = prof or self:SelectedProfession()
  return ns.Recipes and ns.Recipes[prof] or EMPTY
end

-- Enchant rows (Data/Enchants.lua) and the lookups built from them (a separate table, deduplicated by enchant ID).
function GCA:EnchantData()
  if self.enchantData then return self.enchantData end
  local rows = ns.Enchants and ns.Enchants.rows or EMPTY
  local d = { rows = rows, bySpell = {}, byEnchant = {}, bySlot = {} }
  for _, r in ipairs(rows) do
    d.bySpell[r.spell] = r
    d.byEnchant[r.enchant] = d.byEnchant[r.enchant] or r
    d.bySlot[r.slot] = d.bySlot[r.slot] or {}
    table.insert(d.bySlot[r.slot], r)
  end
  self.enchantData = d
  return d
end

-- Every spell of a profession that can be "known": item recipes, plus the enchants for Enchanting.
function GCA:KnowableSpells(prof)
  local out = {}
  for spellID in pairs(self:RecipeTable(prof)) do out[spellID] = true end
  if prof == "Enchanting" then
    for spellID in pairs(self:EnchantData().bySpell) do out[spellID] = true end
  end
  return out
end

-- itemID -> recipe spell of one profession (spell and item IDs repeat across professions, so per profession).
GCA.itemToSpellOf = {}
function GCA:ItemToSpell(prof)
  local m = self.itemToSpellOf[prof]
  if not m then
    m = {}
    for spellID, r in pairs(self:RecipeTable(prof)) do m[r.item] = spellID end
    self.itemToSpellOf[prof] = m
  end
  return m
end

---------------------------------------------------------------------------
-- Your professions (GetProfessions) and the selected one
---------------------------------------------------------------------------
-- Returns own, trusted. own = { [key] = { rank, maxRank, name } }. trusted = the answer can be used to
-- clear known recipes / mark "browse" (the API answered with at least one profession, or long enough after login).
function GCA:ReadProfessions()
  local own = {}
  if not (GetProfessions and GetProfessionInfo) then self.ownProfs, self.profsTrusted = own, false return own, false end
  local list = { SafeCall(GetProfessions) }
  local any = false
  for i = 1, 6 do
    local idx = list[i]
    if idx ~= nil and not IsSecret(idx) then
      any = true
      local name, _, rank, maxRank, _, _, skillLine = SafeCall(GetProfessionInfo, idx)
      local p = type(skillLine) == "number" and not IsSecret(skillLine) and self.PROF_BY_LINE[skillLine]
      if p then
        own[p.key] = { rank = (not IsSecret(rank)) and rank or nil, maxRank = (not IsSecret(maxRank)) and maxRank or nil,
          name = (type(name) == "string" and not IsSecret(name)) and name or nil }
      end
    end
  end
  local trusted = any or (self.loginTime ~= nil and GetTime() - self.loginTime >= self.PROF_TRUST_DELAY)
  self.ownProfs, self.profsTrusted = own, trusted
  return own, trusted
end

function GCA:OwnProfessions()
  if not self.ownProfs then self:ReadProfessions() end
  return self.ownProfs, self.profsTrusted
end

-- Browse = a profession you don't have. Only when GetProfessions gave a trusted answer;
-- without one (API missing / not loaded yet) every profession is treated as yours.
function GCA:IsBrowse(prof)
  prof = prof or self:SelectedProfession()
  local own, trusted = self:OwnProfessions()
  return trusted and not own[prof] or false
end

-- The selected profession (saved per character), else your first gear profession, else Leatherworking.
function GCA:SelectedProfession()
  local sel = self.db and self.db.profSel and self.charKey and self.db.profSel[self.charKey]
  if sel and self.PROF_BY_KEY[sel] then return sel end
  local own = self:OwnProfessions()
  for _, p in ipairs(self.PROFESSIONS) do if own[p.key] then return p.key end end
  return self.DEFAULT_PROFESSION
end

function GCA:SelectProfession(prof)
  if not self.PROF_BY_KEY[prof] or not (self.db and self.charKey) then return end
  self.db.profSel = self.db.profSel or {}
  self.db.profSel[self.charKey] = prof
  self:OnProfessionChanged()
end

-- Per-profession state that follows the selection: itemToSpell, knownCount; then refresh.
function GCA:OnProfessionChanged()
  local prof = self:SelectedProfession()
  self.itemToSpell = self:ItemToSpell(prof)
  self.knownCount = self.knownCounts[prof] or 0
  self:PreloadItems()
  self:Invalidate()
end

---------------------------------------------------------------------------
-- Recipes you know (per profession)
---------------------------------------------------------------------------
GCA.knownNow, GCA.knownCounts, GCA.itemToSpell = {}, {}, {}

local function SpellKnown(spellID)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID)
    if ok and not IsSecret(v) and v then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, spellID)
    if ok and not IsSecret(v) and v then return true end
  end
  return false
end
GCA.SpellKnown = SpellKnown

-- db.known[charKey] = { [profession] = { [spellID] = true } }. Older builds stored a flat { [spellID] = true }
-- (Leatherworking only): moved once.
function GCA:KnownStore()
  local store = self.db.known[self.charKey]
  if type(store) ~= "table" then store = {}; self.db.known[self.charKey] = store end
  local flat
  for k in pairs(store) do if type(k) == "number" then flat = true break end end
  if flat then
    local lw = type(store.Leatherworking) == "table" and store.Leatherworking or {}
    for k, v in pairs(store) do
      if type(k) == "number" then lw[k] = v; store[k] = nil end
    end
    store.Leatherworking = lw
  end
  return store
end

local function SameSet(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

-- Re-reads which recipes you know for every profession. A profession that GetProfessions (trusted answer)
-- no longer lists loses its saved IDs. Returns true when any known set changed.
function GCA:RefreshKnown()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local changed = false
  for _, p in ipairs(self.PROFESSIONS) do
    local now, n = {}, 0
    if trusted and not own[p.key] then
      store[p.key] = nil
    else
      local saved = store[p.key] or {}
      store[p.key] = saved
      local knowable = self:KnowableSpells(p.key)
      -- once the profession window answered for this profession, its list is the truth: spell-API hits that
      -- it didn't confirm are not added (they caused wrong "known" marks); new recipes come via NEW_RECIPE_LEARNED
      local auth = self.db.knownAuth and self.db.knownAuth[self.charKey] and self.db.knownAuth[self.charKey][p.key]
      for spellID in pairs(knowable) do
        if saved[spellID] or (not auth and SpellKnown(spellID)) then
          now[spellID] = true
          saved[spellID] = true
          n = n + 1
        end
      end
      -- saved IDs that no longer exist in our data stay saved but don't count
    end
    if not SameSet(now, self.knownNow[p.key] or EMPTY) then changed = true end
    self.knownNow[p.key], self.knownCounts[p.key] = now, n
  end
  self.knownCount = self.knownCounts[self:SelectedProfession()] or 0
  self.itemToSpell = self:ItemToSpell(self:SelectedProfession())
  -- knownGen is part of the suggestion cache key: bump it only when a set really changed
  if changed then
    self.knownGen = (self.knownGen or 0) + 1
    self:Invalidate()
  end
  return changed
end

-- Known in the given (default: selected) profession. Browse mode never counts anything as known.
function GCA:IsKnown(spellID, prof)
  prof = prof or self:SelectedProfession()
  local set = self.knownNow[prof]
  return set ~= nil and set[spellID] == true
end

-- Extra safety net: read the open profession window directly.
function GCA:ScanTradeSkill()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local profs = {}
  for _, p in ipairs(self.PROFESSIONS) do
    if not trusted or own[p.key] then profs[#profs + 1] = p.key end
  end
  local function mark(prof, spellID)
    store[prof] = store[prof] or {}
    store[prof][spellID] = true
  end
  local api = C_TradeSkillUI
  local modernAnswered = false
  if api and api.GetAllRecipeIDs and api.GetRecipeInfo then
    local ids = SafeCall(api.GetAllRecipeIDs)
    if type(ids) == "table" then
      local knowable, seen, learned = {}, {}, {}
      for _, prof in ipairs(profs) do knowable[prof] = self:KnowableSpells(prof); seen[prof] = 0; learned[prof] = {} end
      for _, id in ipairs(ids) do
        local info
        for _, prof in ipairs(profs) do
          if knowable[prof][id] then
            info = info or SafeCall(api.GetRecipeInfo, id)
            if type(info) == "table" and info.learned ~= nil and not IsSecret(info.learned) then
              seen[prof] = seen[prof] + 1
              if info.learned == true then learned[prof][id] = true end
            end
          end
        end
      end
      -- The open profession window lists that profession's recipes, learned or not: when it answered for
      -- enough of them, it is the truth for that profession and replaces the saved set (drops wrong old marks).
      for _, prof in ipairs(profs) do
        if seen[prof] >= 10 then
          modernAnswered = true
          store[prof] = learned[prof]
          self.db.knownAuth = self.db.knownAuth or {}
          self.db.knownAuth[self.charKey] = self.db.knownAuth[self.charKey] or {}
          self.db.knownAuth[self.charKey][prof] = time()
        else
          for id in pairs(learned[prof]) do mark(prof, id) end
        end
      end
    end
  end
  if GetNumTradeSkills and not modernAnswered then
    -- which profession's window is open: by its localized name, else every profession of yours
    local lineName = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
    local which = {}
    for _, prof in ipairs(profs) do
      if type(lineName) == "string" and own[prof] and own[prof].name == lineName then which = { prof } break end
    end
    if #which == 0 then which = profs end
    local n = SafeCall(GetNumTradeSkills) or 0
    if IsSecret(n) then n = 0 end
    for i = 1, n do
      local id = GetTradeSkillItemLink and ItemIDFrom(SafeCall(GetTradeSkillItemLink, i))
      -- enchants have no item; their recipe link names the spell ("enchant:13419")
      local rlink = GetTradeSkillRecipeLink and SafeCall(GetTradeSkillRecipeLink, i)
      local spell = type(rlink) == "string" and not IsSecret(rlink) and tonumber(rlink:match("enchant:(%d+)"))
      for _, prof in ipairs(which) do
        local s1 = id and self:ItemToSpell(prof)[id]
        if s1 then mark(prof, s1) end
        if spell and self:KnowableSpells(prof)[spell] then mark(prof, spell) end
      end
    end
  end
  self:RefreshKnown()
end

-- rank, maxRank, localized name of a profession you have (default: the selected one).
function GCA:GetSkill(prof)
  prof = prof or self:SelectedProfession()
  local own = self:ReadProfessions()
  local p = own[prof]
  if p and p.rank then return p.rank, p.maxRank, p.name end
end

-- shared with the files loaded after this one (priv)
priv.EMPTY = EMPTY
