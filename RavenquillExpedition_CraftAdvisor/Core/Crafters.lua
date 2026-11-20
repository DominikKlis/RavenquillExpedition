local ADDON, ns = ...
local GCA = ns.GCA
local RQ = GCA.RQ
local EMPTY = {}

local LOW, HIGH = "0123456789abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
GCA.MAX_SPELL_ID = 1e7

local function Token(n)
  local low = n % 36
  local s, q = LOW:sub(low + 1, low + 1), (n - low) / 36
  while q > 0 do
    local d = q % 26
    s = HIGH:sub(d + 1, d + 1) .. s
    q = (q - d) / 26
  end
  return s
end
GCA.RecipeToken = Token

function GCA.EncodeIDs(ids)
  local out, prev = {}, 0
  for i, id in ipairs(ids) do out[i] = Token(id - prev); prev = id end
  return table.concat(out)
end

local function TokenValue(high, low)
  local q = 0
  for i = 1, #high do q = q * 26 + high:byte(i) - 65 end
  return q * 36 + tonumber(low, 36)
end

function GCA.DecodeIDs(s)
  if type(s) ~= "string" or s:find("[^%w]") then return nil end
  local ids, prev, used = {}, 0, 0
  for high, low in s:gmatch("([A-Z]*)([0-9a-z])") do
    local id = prev + TokenValue(high, low)
    if id <= prev or id >= GCA.MAX_SPELL_ID then return nil end
    ids[#ids + 1], prev, used = id, id, used + #high + 1
  end
  if used ~= #s then return nil end
  return ids
end

GCA.crafterGen = 0

function GCA:CrafterEntries()
  local all = self.db and self.db.crafters
  return type(all) == "table" and all or EMPTY
end

local function Changed(self)
  self.crafterGen = self.crafterGen + 1
  self:Invalidate()
end

local function SortedUnique(ids)
  local sorted, out = {}, {}
  for i, id in ipairs(ids) do sorted[i] = id end
  table.sort(sorted)
  for _, id in ipairs(sorted) do if id ~= out[#out] then out[#out + 1] = id end end
  return out
end

function GCA:ForgetCrafter(key)
  local all = self:CrafterEntries()
  if all[key] == nil then return false end
  all[key] = nil
  Changed(self)
  return true
end

function GCA:StoreCrafter(key, ts, profs)
  local old = self:CrafterEntries()[key]
  if type(old) == "table" and (tonumber(old.ts) or 0) > ts then return false end
  if not next(profs) then return self:ForgetCrafter(key) end
  local stored = {}
  for prof, p in pairs(profs) do stored[prof] = { rank = p.rank, ids = self.EncodeIDs(SortedUnique(p.ids)) } end
  self.db.crafters = type(self.db.crafters) == "table" and self.db.crafters or {}
  self.db.crafters[key] = { ts = ts, time = time(), profs = stored }
  Changed(self)
  return true
end

local index = { gen = -1, byProf = {} }

local function SavedProfs(entry)
  return type(entry) == "table" and type(entry.profs) == "table" and entry.profs or EMPTY
end

local function IndexEntry(byProf, key, entry)
  for prof, p in pairs(SavedProfs(entry)) do
    local bySpell = byProf[prof] or {}
    byProf[prof] = bySpell
    for _, id in ipairs(type(p) == "table" and GCA.DecodeIDs(p.ids) or EMPTY) do
      bySpell[id] = bySpell[id] or {}
      table.insert(bySpell[id], { key = key, rank = tonumber(p.rank) or 0 })
    end
  end
end

local function Index(self)
  if index.gen ~= self.crafterGen or index.db ~= self.db then
    index.byProf, index.gen, index.db = {}, self.crafterGen, self.db
    for key, entry in pairs(self:CrafterEntries()) do IndexEntry(index.byProf, key, entry) end
  end
  return index.byProf
end

local function CrafterOrder(a, b)
  if a.online ~= b.online then return a.online end
  if a.rank ~= b.rank then return a.rank > b.rank end
  return a.key < b.key
end

function GCA:CraftersOf(prof, spellID)
  local bySpell = Index(self)[prof]
  local out = {}
  for _, c in ipairs(bySpell and bySpell[spellID] or EMPTY) do
    local r = c.key ~= self.playerKey and RQ:RosterEntry(c.key)
    if r then out[#out + 1] = { key = c.key, rank = c.rank, online = r.online == true } end
  end
  table.sort(out, CrafterOrder)
  return out
end

function GCA:OnAdvisorShown()
  self:RefreshKnown()
  if self.RequestCrafters then self:RequestCrafters() end
end

function GCA:OwnRecipeSet()
  local own, trusted = self:OwnProfessions()
  if not trusted then return nil end
  local set = {}
  for _, p in ipairs(self.PROFESSIONS) do
    local mine = own[p.key]
    if mine then
      local ids = {}
      for id in pairs(self.knownNow[p.key] or EMPTY) do ids[#ids + 1] = id end
      table.sort(ids)
      set[#set + 1] = { prof = p.key, line = p.skillLine, rank = tonumber(mine.rank) or 0, ids = ids }
    end
  end
  return set
end

function GCA.RecipeSignature(set)
  local parts = {}
  for i, p in ipairs(set) do parts[i] = p.line .. ":" .. GCA.EncodeIDs(p.ids) end
  return table.concat(parts, ",")
end
