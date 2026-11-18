local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall, Plain, PlainCall, ItemIDFrom = GCA.SafeCall, GCA.Plain, GCA.PlainCall, GCA.ItemIDFrom

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
GCA.PROF_TRUST_DELAY = 10

local EMPTY = {}
function GCA:RecipeTable(prof)
  prof = prof or self:SelectedProfession()
  return ns.Recipes and ns.Recipes[prof] or EMPTY
end

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

function GCA:KnowableSpells(prof)
  local out = {}
  for spellID in pairs(self:RecipeTable(prof)) do out[spellID] = true end
  if prof == "Enchanting" then
    for spellID in pairs(self:EnchantData().bySpell) do out[spellID] = true end
  end
  return out
end

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

function GCA:ReadProfessions()
  local own = {}
  if not (GetProfessions and GetProfessionInfo) then self.ownProfs, self.profsTrusted = own, false return own, false end
  local list = { SafeCall(GetProfessions) }
  local any = false
  for i = 1, 6 do
    local idx = Plain(list[i])
    if idx ~= nil then
      any = true
      local name, _, rank, maxRank, _, _, skillLine = SafeCall(GetProfessionInfo, idx)
      local line = Plain(skillLine, "number")
      local p = line and self.PROF_BY_LINE[line]
      if p then
        own[p.key] = { rank = Plain(rank) or nil, maxRank = Plain(maxRank) or nil, name = Plain(name, "string") }
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

function GCA:IsBrowse(prof)
  prof = prof or self:SelectedProfession()
  local own, trusted = self:OwnProfessions()
  return trusted and not own[prof] or false
end

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

function GCA:OnProfessionChanged()
  self:PreloadItems()
  self:Invalidate()
end

GCA.knownNow, GCA.knownCounts = {}, {}
function GCA:KnownCount(prof) return self.knownCounts[prof] or 0 end

local function SpellKnown(spellID)
  local known = PlainCall(nil, C_SpellBook and C_SpellBook.IsSpellKnown, spellID) or PlainCall(nil, IsPlayerSpell, spellID)
  return known and true or false
end
GCA.SpellKnown = SpellKnown

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

local function CollectKnown(self, store, prof, auth)
  local saved = store[prof] or {}
  store[prof] = saved
  local now, n = {}, 0
  for spellID in pairs(self:KnowableSpells(prof)) do
    if saved[spellID] or (not auth and SpellKnown(spellID)) then
      now[spellID] = true
      saved[spellID] = true
      n = n + 1
    end
  end
  return now, n
end

function GCA:RefreshKnown()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local auths = (self.db.knownAuth or EMPTY)[self.charKey] or EMPTY
  local changed = false
  for _, p in ipairs(self.PROFESSIONS) do
    local now, n = {}, 0
    if trusted and not own[p.key] then
      store[p.key] = nil
    else
      now, n = CollectKnown(self, store, p.key, auths[p.key])
    end
    if not SameSet(now, self.knownNow[p.key] or EMPTY) then changed = true end
    self.knownNow[p.key], self.knownCounts[p.key] = now, n
  end
  if changed then
    self.knownGen = (self.knownGen or 0) + 1
    self:Invalidate()
  end
  return changed
end

function GCA:IsKnown(spellID, prof)
  prof = prof or self:SelectedProfession()
  local set = self.knownNow[prof]
  return set ~= nil and set[spellID] == true
end

local MODERN_TRUST_MIN = 10

local function MarkKnown(store, prof, spellID)
  store[prof] = store[prof] or {}
  store[prof][spellID] = true
end

local function LearnedFlag(info)
  if type(info) == "table" then return Plain(info.learned) end
end

local function TallyRecipe(api, id, profs, tally)
  local info
  for _, prof in ipairs(profs) do
    if tally.knowable[prof][id] then
      info = info or SafeCall(api.GetRecipeInfo, id)
      local learned = LearnedFlag(info)
      if learned ~= nil then
        tally.seen[prof] = tally.seen[prof] + 1
        if learned == true then tally.learned[prof][id] = true end
      end
    end
  end
end

local function ReadModernRecipes(self, profs)
  local api = C_TradeSkillUI
  if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return nil end
  local ids = SafeCall(api.GetAllRecipeIDs)
  if type(ids) ~= "table" then return nil end
  local tally = { knowable = {}, seen = {}, learned = {} }
  for _, prof in ipairs(profs) do
    tally.knowable[prof], tally.seen[prof], tally.learned[prof] = self:KnowableSpells(prof), 0, {}
  end
  for _, id in ipairs(ids) do TallyRecipe(api, id, profs, tally) end
  return tally
end

local function MarkAuthoritative(self, prof)
  local db = self.db
  db.knownAuth = db.knownAuth or {}
  db.knownAuth[self.charKey] = db.knownAuth[self.charKey] or {}
  db.knownAuth[self.charKey][prof] = time()
end

local function ApplyModernTally(self, store, profs, tally)
  local answered = false
  for _, prof in ipairs(profs) do
    if tally.seen[prof] >= MODERN_TRUST_MIN then
      answered = true
      store[prof] = tally.learned[prof]
      MarkAuthoritative(self, prof)
    else
      for id in pairs(tally.learned[prof]) do MarkKnown(store, prof, id) end
    end
  end
  return answered
end

local function LegacyWindowProfessions(own, profs)
  local lineName = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
  if type(lineName) ~= "string" then return profs end
  for _, prof in ipairs(profs) do
    if own[prof] and own[prof].name == lineName then return { prof } end
  end
  return profs
end

local function LegacyRow(i)
  local id = GetTradeSkillItemLink and ItemIDFrom(SafeCall(GetTradeSkillItemLink, i))
  local rlink = PlainCall("string", GetTradeSkillRecipeLink, i)
  local spell = rlink and tonumber(rlink:match("enchant:(%d+)"))
  return id, spell
end

local function ScanLegacyWindow(self, store, own, profs)
  local which = LegacyWindowProfessions(own, profs)
  local n = PlainCall(nil, GetNumTradeSkills) or 0
  for i = 1, n do
    local id, spell = LegacyRow(i)
    for _, prof in ipairs(which) do
      local crafted = id and self:ItemToSpell(prof)[id]
      if crafted then MarkKnown(store, prof, crafted) end
      if spell and self:KnowableSpells(prof)[spell] then MarkKnown(store, prof, spell) end
    end
  end
end

function GCA:ScanTradeSkill()
  local store = self:KnownStore()
  local own, trusted = self:ReadProfessions()
  local profs = {}
  for _, p in ipairs(self.PROFESSIONS) do
    if not trusted or own[p.key] then profs[#profs + 1] = p.key end
  end
  local tally = ReadModernRecipes(self, profs)
  local modernAnswered = tally ~= nil and ApplyModernTally(self, store, profs, tally)
  if GetNumTradeSkills and not modernAnswered then ScanLegacyWindow(self, store, own, profs) end
  self:RefreshKnown()
end

function GCA:GetSkill(prof)
  prof = prof or self:SelectedProfession()
  local own = self:ReadProfessions()
  local p = own[prof]
  if p and p.rank then return p.rank, p.maxRank, p.name end
end

