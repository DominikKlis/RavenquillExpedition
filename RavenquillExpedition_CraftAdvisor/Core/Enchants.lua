local ADDON, ns = ...
local GCA = ns.GCA
local priv = GCA.priv
local IsSecret, SafeCall, Scoring, EMPTY, Better = priv.IsSecret, priv.SafeCall, priv.Scoring, priv.EMPTY, priv.Better

---------------------------------------------------------------------------
-- Enchants
---------------------------------------------------------------------------
-- Enchant slot rows a worn item takes (SimGear Enchants.lua:17-36, 113-119). Weapon rows also go on a
-- two-hander; shield/off-hand rows by the worn item's equip location; an empty slot takes none.
GCA.ENCHANT_SLOTS = { [15] = "back", [5] = "chest", [9] = "wrist", [10] = "hands", [8] = "feet", [2] = "neck" }
local ENCHANT_HAND = { INVTYPE_2HWEAPON = { "twohand", "weapon" }, INVTYPE_WEAPON = { "weapon" }, INVTYPE_WEAPONMAINHAND = { "weapon" } }
local ENCHANT_OFF = { INVTYPE_SHIELD = { "shield" }, INVTYPE_HOLDABLE = { "offhand" } }
function GCA:EnchantKeysFor(slot, equipLoc)
  if self.ENCHANT_SLOTS[slot] then return { self.ENCHANT_SLOTS[slot] } end
  if slot == 16 then return ENCHANT_HAND[equipLoc or ""] end
  if slot == 17 then return ENCHANT_OFF[equipLoc or ""] end
end

-- Enchant ID in link field 2, or nil for none.
function GCA:EnchantIDOf(link)
  local f = self:ParseLink(link)
  local id = f and tonumber(f[2])
  if id and id > 0 then return id end
end

-- The same item string with field 2 (enchant) blanked: the item as it scores without its enchant.
function GCA:WithoutEnchant(link)
  if type(link) ~= "string" then return link end
  return (link:gsub("(item:%-?%d+):%d*", "%1:", 1))
end

-- A school's spell power the set doesn't weigh while it weighs spell power: not simmed for this spec, can't be
-- scored (SimGear Enchants.lua:100-110). GCA: our data leaves exact-zero weights out, so a school SimGear lists
-- with 0 is "unsimmed" here too; both ways the enchant is not suggested.
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

-- Display info for an enchant row, shaped like item info for the UI (name, icon, quality, cstats).
GCA.enchantInfo = {}
function GCA:EnchantInfo(row)
  local c = self.enchantInfo[row.spell]
  if c then return c end
  local name, icon
  if C_Spell and C_Spell.GetSpellName then name = SafeCall(C_Spell.GetSpellName, row.spell) end
  if C_Spell and C_Spell.GetSpellTexture then icon = SafeCall(C_Spell.GetSpellTexture, row.spell) end
  if (not name or not icon) and GetSpellInfo then
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

-- Weapon-damage enchants (W5, SimGear Enchants.statsOf): damage per hit ÷ the WORN weapon's speed (fallback SimGear's
-- assumed 2.6 one-hand / 3.5 two-hand) as MainHandDps, or TwoHandDps on a two-hander. Stat rows: their own stats.
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

-- EnchantInfo with cstats = what the row adds on this weapon (W5: damage rows depend on the worn weapon's speed).
function GCA:EnchantInfoOn(row, stats)
  local base = self:EnchantInfo(row)
  if row.kind ~= "damage" then return base end
  local c = {}
  for k, v in pairs(base) do c[k] = v end
  c.cstats = stats
  return c
end

-- Adds enchant suggestions into `best` (one per slot and known/unlearned). Returns the number of items still loading.
-- Gain = (new − current enchant value) ÷ the item's own score, in the usual tiers: % upgrade (≥ 1 %), or points only
-- when the item scores ≤ 0 (no-baseline). W5: weapons have a real score now, so the weapon slot gets a % like armour,
-- and weapon-damage enchants (Striking/Impact) are scored (EnchantStats).
function GCA:AddEnchantSuggestions(best, ctx)
  local data = self:EnchantData()
  local e, items, prof = ctx.e, ctx.items, ctx.prof
  local faction = PlayerFaction()
  local pending = 0
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local info = ctx.equippedInfo[slot]
    local keys = info and not ctx.unknownSlot[slot] and self:EnchantKeysFor(slot, info.equipLoc)
    if keys then
      local curID = self:EnchantIDOf(items[slot])
      local curRow = curID and data.byEnchant[curID]
      -- unknown enchant ID, proc/utility (never replaced) or an unsimmed school: we can't value what is
      -- on the item, so nothing is suggested for this slot (weapon damage is valued since W5)
      local usable = curID == nil or (curRow ~= nil and SCORED_ENCHANT[curRow.kind] and not self.UnsimmedSchool(curRow.stats, e.set))
      local base = usable and info or nil
      if usable and curID then
        -- the item without its enchant, in case GetItemStats includes the enchant on an enchanted link
        local plain, failed = self:GetInfo(self:WithoutEnchant(items[slot]))
        if plain then base = plain elseif not failed then base = nil; pending = pending + 1 end
      end
      if base then
        local baseScore = self:Score(base, e)
        local curStats = curRow and self:EnchantStats(curRow, info)
        local curValue = curRow and Scoring.value(curStats, e.set) or 0
        for _, key in ipairs(keys) do
          for _, row in ipairs(data.bySlot[key] or EMPTY) do
            local known = not ctx.browse and self:IsKnown(row.spell, prof)
            if SCORED_ENCHANT[row.kind] and row.enchant ~= curID and (known or ctx.showAll)
               and (known or not (row.faction and faction and row.faction ~= faction))
               and not self.UnsimmedSchool(row.stats, e.set) then
              local rowStats = self:EnchantStats(row, info)
              local value = Scoring.value(rowStats, e.set)
              local gain = value - curValue
              local pts = self:ToPoints(e, gain)
              local status, pct, tier
              if gain > 0 then
                if baseScore <= 0 then
                  if pts >= self.MIN_POINTS then status, tier = "no-baseline", 1 end
                else
                  pct = gain / baseScore
                  if pct >= self.MIN_PCT then status, tier = "upgrade", 1 else pct = nil end
                end
              end
              if tier then
                local sug = {
                  kind = "enchant", enchant = row, current = curRow, hasEnchant = curID ~= nil,
                  cand = { spellID = row.spell, recipe = row, enchant = true },
                  info = self:EnchantInfoOn(row, rowStats), item = info, slot = slot, known = known, future = false,
                  status = status, pct = pct, tier = tier, gain = gain, points = pts,
                  newScore = baseScore + value, oldScore = baseScore + curValue, baseScore = baseScore,
                  equipped = curRow and { name = self:EnchantInfo(curRow).name, cstats = curStats } or nil, e = e,
                }
                -- one per slot and known/unlearned; rows sharing an enchant ID never show twice
                local gkey = "E" .. slot .. "|w" .. (known and "k" or "u")
                local cur = best[gkey]
                if not cur or Better(sug, cur) then best[gkey] = sug end
                if ctx.all then -- section I: every enchant row goes to its slot's section (top 3 there)
                  ctx.all[slot] = ctx.all[slot] or {}
                  ctx.all[slot][#ctx.all[slot] + 1] = sug
                end
              end
            end
          end
        end
      end
    end
  end
  return pending
end

-- shared with the files loaded after this one (priv)
priv.PlayerFaction = PlayerFaction
