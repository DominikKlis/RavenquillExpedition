local ADDON, ns = ...
local GCA = ns.GCA
local IsSecret, SafeCall, Scoring = GCA.IsSecret, GCA.SafeCall, ns.Scoring
local EMPTY = {}

GCA.ENCHANT_SLOTS = { [15] = "back", [5] = "chest", [9] = "wrist", [10] = "hands", [8] = "feet", [2] = "neck" }
function GCA:EnchantKeysFor(slot, equipLoc)
  if self.ENCHANT_SLOTS[slot] then return { self.ENCHANT_SLOTS[slot] } end
  local rule = Scoring.EQUIP_LOCS[equipLoc or ""]
  if rule and rule.enchant and rule.slots[1] == slot then return rule.enchant end
end

function GCA:EnchantIDOf(link)
  local f = self:ParseLink(link)
  local id = f and tonumber(f[2])
  if id and id > 0 then return id end
end

function GCA:WithoutEnchant(link)
  if type(link) ~= "string" then return link end
  return (link:gsub("(item:%-?%d+):%d*", "%1:", 1))
end

local SCHOOLS = { HolyPower = true, FirePower = true, FrostPower = true, ShadowPower = true, ArcanePower = true, NaturePower = true }
function GCA.UnsimmedSchool(stats, set)
  local w = set and set.weights or EMPTY
  if (w.SpellPower or 0) <= 0 then return nil end
  for k in pairs(stats or EMPTY) do
    if SCHOOLS[k] and w[k] == nil then return k end
  end
end

local function PlayerFaction()
  local f = UnitFactionGroup and SafeCall(UnitFactionGroup, "player")
  if type(f) == "string" and not IsSecret(f) then return f end
end
GCA.PlayerFaction = PlayerFaction

GCA.enchantInfo = {}
function GCA:EnchantInfo(row)
  local c = self.enchantInfo[row.spell]
  if c then return c end
  local spellAPI = C_Spell or EMPTY
  local name, icon = SafeCall(spellAPI.GetSpellName, row.spell), SafeCall(spellAPI.GetSpellTexture, row.spell)
  if not name or not icon then
    local n, _, ic = SafeCall(GetSpellInfo, row.spell)
    name, icon = name or n, icon or ic
  end
  if IsSecret(name) or type(name) ~= "string" then name = nil end
  if IsSecret(icon) then icon = nil end
  c = { name = name or row.name, icon = icon or "Interface\\Icons\\Trade_Engraving", quality = 1, minLevel = 0,
    cstats = row.stats or {}, enchantRow = row }
  if name then self.enchantInfo[row.spell] = c end
  return c
end

GCA.ENCHANT_SPEED = { weapon = 2.6, twohand = 3.5 }
function GCA:EnchantStats(row, worn)
  if row.kind ~= "damage" then return row.stats or EMPTY end
  local stats = {}
  for k, v in pairs(row.stats or EMPTY) do stats[k] = v end
  local two = worn and worn.equipLoc == "INVTYPE_2HWEAPON"
  local speed = worn and type(worn.speed) == "number" and worn.speed > 0 and worn.speed
    or (two and self.ENCHANT_SPEED.twohand or self.ENCHANT_SPEED.weapon)
  local key = two and "TwoHandDps" or "MainHandDps"
  if row.damage and row.damage ~= 0 then stats[key] = (stats[key] or 0) + row.damage / speed end
  return stats
end
local SCORED_ENCHANT = { stats = true, damage = true }

function GCA:EnchantInfoOn(row, stats)
  local base = self:EnchantInfo(row)
  if row.kind ~= "damage" then return base end
  local c = {}
  for k, v in pairs(base) do c[k] = v end
  c.cstats = stats
  return c
end

local function UsableCurrent(self, curID, curRow, set)
  if curID == nil then return true end
  return curRow ~= nil and SCORED_ENCHANT[curRow.kind] and not self.UnsimmedSchool(curRow.stats, set)
end

local function EnchantBase(self, link, worn, set)
  if not UsableCurrent(self, worn.curID, worn.curRow, set) then return nil, 0 end
  if not worn.curID then return worn.info, 0 end
  local plain, failed = self:GetInfo(self:WithoutEnchant(link))
  if plain then return plain, 0 end
  if failed then return worn.info, 0 end
  return nil, 1
end

local function EnchantVerdict(self, gain, pts, baseScore)
  local gained = gain > 0
  if baseScore <= 0 then
    if gained and pts >= self.MIN_POINTS then return "no-baseline", nil, 1 end
    return nil
  end
  local pct = gain / baseScore
  if gained and pct >= self.MIN_PCT then return "upgrade", pct, 1 end
  return nil
end

local function EnchantOffered(self, scan, worn, row, known)
  return SCORED_ENCHANT[row.kind] and row.enchant ~= worn.curID
    and GCA.Offerable(known, scan.showAll, row, scan.faction)
    and not self.UnsimmedSchool(row.stats, scan.e.set)
end

local function ConsiderEnchant(self, scan, worn, row)
  local known = not scan.browse and self:IsKnown(row.spell, scan.prof)
  if not EnchantOffered(self, scan, worn, row, known) then return end
  local e = scan.e
  local rowStats = self:EnchantStats(row, worn.info)
  local value = Scoring.value(rowStats, e.set)
  local gain = value - worn.curValue
  local pts = self:ToPoints(e, gain)
  local status, pct, tier = EnchantVerdict(self, gain, pts, worn.baseScore)
  if not tier then return end
  local curRow = worn.curRow
  local sug = {
    kind = "enchant", enchant = row, current = curRow, hasEnchant = worn.curID ~= nil,
    cand = { spellID = row.spell, recipe = row, enchant = true },
    info = self:EnchantInfoOn(row, rowStats), item = worn.info, slot = worn.slot, known = known, future = false,
    status = status, pct = pct, tier = tier, gain = gain, points = pts,
    newScore = worn.baseScore + value, oldScore = worn.baseScore + worn.curValue, baseScore = worn.baseScore,
    equipped = curRow and { name = self:EnchantInfo(curRow).name, cstats = worn.curStats } or nil, e = e,
  }
  GCA.KeepSuggestion(scan.best, scan.all, "E" .. worn.slot .. "|w" .. (known and "k" or "u"), worn.slot, sug)
end

local function ScoreWorn(self, worn, base, e)
  worn.baseScore = self:Score(base, e)
  worn.curStats = worn.curRow and self:EnchantStats(worn.curRow, worn.info)
  worn.curValue = worn.curRow and Scoring.value(worn.curStats, e.set) or 0
end

local function ScanSlotEnchants(self, scan, slot)
  local info = scan.equippedInfo[slot]
  local keys = info and not scan.unknownSlot[slot] and self:EnchantKeysFor(slot, info.equipLoc)
  if not keys then return 0 end
  local link = scan.items[slot]
  local curID = self:EnchantIDOf(link)
  local worn = { slot = slot, info = info, curID = curID, curRow = curID and scan.data.byEnchant[curID] }
  local base, pending = EnchantBase(self, link, worn, scan.e.set)
  if not base then return pending end
  ScoreWorn(self, worn, base, scan.e)
  for _, key in ipairs(keys) do
    for _, row in ipairs(scan.data.bySlot[key] or EMPTY) do ConsiderEnchant(self, scan, worn, row) end
  end
  return 0
end

function GCA:AddEnchantSuggestions(best, ctx)
  local scan = {
    data = self:EnchantData(), e = ctx.e, items = ctx.items, prof = ctx.prof, browse = ctx.browse, showAll = ctx.showAll,
    equippedInfo = ctx.equippedInfo, unknownSlot = ctx.unknownSlot, faction = PlayerFaction(), best = best, all = ctx.all,
  }
  local pending = 0
  for _, slot in ipairs(self.SYNC_SLOTS) do pending = pending + ScanSlotEnchants(self, scan, slot) end
  return pending
end
