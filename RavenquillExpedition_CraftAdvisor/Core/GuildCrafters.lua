local ADDON, ns = ...
local GCA = ns.GCA
local RQ = GCA.RQ
local OrderOptional, SafeCall, ItemAPI, EQUIP_LOCS = GCA.OrderOptional, GCA.SafeCall, GCA.ItemAPI, ns.Scoring.EQUIP_LOCS
local SECTION_OF = GCA.SECTION_OF
local EMPTY = {}
local ALL = "*"

local PROF_ORDER = {}
for i, p in ipairs(GCA.PROFESSIONS) do PROF_ORDER[p.key] = i end

local ENCHANT_SECTION = { weapon = 16, twohand = 16, shield = 17, offhand = 17 }
for slot, key in pairs(GCA.ENCHANT_SLOTS) do ENCHANT_SECTION[key] = slot end

local function CraftSection(itemID)
  local _, _, _, equipLoc = SafeCall(ItemAPI.Instant, itemID)
  local rule = EQUIP_LOCS[equipLoc or ""]
  return rule and SECTION_OF[rule.slots[1]]
end

local function Recipe(self, prof, spellID)
  local r = self:RecipeTable(prof)[spellID]
  if r then
    return { spellID = spellID, prof = prof, kind = "craft", name = r.name, itemID = r.item, skill = r.skill or 0, regs = r.r or EMPTY,
      section = CraftSection(r.item) }
  end
  local e = prof == "Enchanting" and self:EnchantData().bySpell[spellID]
  if e then
    return { spellID = spellID, prof = prof, kind = "enchant", name = e.name, skill = e.skill or 0, regs = e.r or EMPTY,
      section = ENCHANT_SECTION[e.slot] }
  end
end

local function KnownRecipes(self, prof, ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = Recipe(self, prof, id) end
  return out
end

local catalog = { gen = -1 }
local function Catalog(self)
  if catalog.gen == self.crafterGen and catalog.db == self.db then return catalog.byKey end
  local byKey = {}
  for key, profs in pairs(self:CrafterProfessions()) do
    local own = {}
    for prof, p in pairs(profs) do own[prof] = { rank = p.rank, recipes = KnownRecipes(self, prof, p.ids) } end
    byKey[key] = own
  end
  catalog.gen, catalog.db, catalog.byKey = self.crafterGen, self.db, byKey
  return byKey
end

local function ProfSummary(own)
  local out = {}
  for _, p in ipairs(GCA.PROFESSIONS) do
    local mine = own[p.key]
    if mine then out[#out + 1] = { prof = p.key, rank = mine.rank, count = #mine.recipes } end
  end
  return out
end

local function SyncedAt(entry)
  return type(entry) == "table" and tonumber(entry.time) or nil
end

local function RosterOrder(a, b)
  if a.online ~= b.online then return a.online end
  return a.key < b.key
end

function GCA:CrafterRoster()
  local out, entries = {}, self:CrafterEntries()
  for key, own in pairs(Catalog(self)) do
    local r = key ~= self.playerKey and next(own) and RQ:RosterEntry(key)
    if r then
      out[#out + 1] = { key = key, online = r.online == true, class = r.class, time = SyncedAt(entries[key]),
        profs = ProfSummary(own) }
    end
  end
  table.sort(out, RosterOrder)
  return out
end

local function SelfView(self)
  local key = self.playerKey
  local m = key and self.db.members[key]
  if type(m) ~= "table" then return nil end
  return { key = key, class = m.class, level = m.level, items = m.items, spec = (self:MemberSpec(key, m.class, m.items)) }
end

function GCA:SelfUpgrades(profs)
  local view, byProf, gens = SelfView(self), {}, {}
  if not view then return byProf, "" end
  for i, prof in ipairs(profs) do byProf[prof], gens[i] = self:GuildUpgrades(view, prof) end
  return byProf, table.concat(gens, ",")
end

local function RecipeOrder(a, b)
  if a.prof ~= b.prof then return PROF_ORDER[a.prof] < PROF_ORDER[b.prof] end
  local byUpgrade = OrderOptional(a.upgrade, b.upgrade)
  if byUpgrade ~= nil then return byUpgrade end
  if a.skill ~= b.skill then return a.skill > b.skill end
  if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
  return a.spellID < b.spellID
end

local function NewRow(self, rec, upgrades)
  local row = {}
  for k, v in pairs(rec) do row[k] = v end
  row.crafters = self:CraftersOf(rec.prof, rec.spellID)
  row.upgrade = (upgrades[rec.prof] or EMPTY)[rec.spellID]
  if row.upgrade then row.section = SECTION_OF[row.upgrade.slot] end
  return row
end

local function AddRows(self, rows, seen, own, upgrades)
  for _, p in pairs(own) do
    for _, rec in ipairs(p.recipes) do
      if not seen[rec.spellID] then
        seen[rec.spellID] = true
        rows[#rows + 1] = NewRow(self, rec, upgrades)
      end
    end
  end
end

local function BuildRows(self, keys, upgrades)
  local rows, seen, cat = {}, {}, Catalog(self)
  for _, key in ipairs(keys) do AddRows(self, rows, seen, cat[key] or EMPTY, upgrades) end
  table.sort(rows, RecipeOrder)
  return rows
end

local function ProfessionsOf(cat, keys)
  local set, list = {}, {}
  for _, key in ipairs(keys) do
    for prof in pairs(cat[key] or EMPTY) do set[prof] = true end
  end
  for _, p in ipairs(GCA.PROFESSIONS) do
    if set[p.key] then list[#list + 1] = p.key end
  end
  return list
end

local function RosterKeys(roster)
  local keys, parts = {}, {}
  for i, c in ipairs(roster) do keys[i], parts[i] = c.key, c.key .. (c.online and "+" or "-") end
  return keys, table.concat(parts, ",")
end

local recipeCache = {}
function GCA:CrafterRecipes(key)
  local all, rosterSig = RosterKeys(self:CrafterRoster())
  local keys = key and { key } or all
  local upgrades, upgradeSig = self:SelfUpgrades(ProfessionsOf(Catalog(self), keys))
  local sig = table.concat({ self.crafterGen, rosterSig, upgradeSig }, "|")
  local c = recipeCache[key or ALL]
  if c and c.sig == sig and c.db == self.db then return c.rows end
  local rows = BuildRows(self, keys, upgrades)
  recipeCache[key or ALL] = { sig = sig, db = self.db, rows = rows }
  return rows
end
