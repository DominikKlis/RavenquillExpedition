local ADDON, ns = ...
local GCA = ns.GCA
local IsSecret, SafeCall, Plain, PlainCall, ItemAPI = GCA.IsSecret, GCA.SafeCall, GCA.Plain, GCA.PlainCall, GCA.ItemAPI
local function Print(...) GCA:Print(...) end
local ItemIDFrom, Scoring = GCA.ItemIDFrom, ns.Scoring
local EMPTY = {}

local WEAPON_DPS_KEYS = { "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }

local function SortedEntries(t, entryText)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = entryText(k, v) end
  table.sort(out)
  return out
end

local function RawStatsLine(raw)
  local keys = SortedEntries(raw, function(k, v) return tostring(k) .. "=" .. tostring(v) end)
  return "GetItemStats: " .. (#keys > 0 and table.concat(keys, ", ") or "(empty)")
end

local function CanonicalLine(stats, unknown)
  local out = SortedEntries(stats, function(k, v) return string.format("%s=%g", k, v) end)
  local unmapped = #unknown > 0 and ("  |cffff8800unmapped: " .. table.concat(unknown, ", ") .. "|r") or ""
  return "Canonical: " .. (#out > 0 and table.concat(out, ", ") or "(none)") .. unmapped
end

local function FirstDps(stats)
  for _, k in ipairs(WEAPON_DPS_KEYS) do
    if stats[k] then return stats[k] end
  end
end

local function WeaponLine(speed, dps, subClassID)
  local label = Plain(SPEED, "string") or "nil"
  return string.format("Weapon: speed %s (label %s), DPS %s, dagger %s", speed and string.format("%.2f", speed) or "not read",
    tostring(label), dps and string.format("%.2f", dps) or "-", tostring(subClassID == 15))
end

local function ScoreLine(self, equipLoc, stats, speed, subClassID)
  local key = self.UI and self.UI.selected or self.playerKey
  local entry = key and self.UI and self.UI.current
  local e = entry and entry.weights
  if not e then return nil end
  local v = Scoring.itemValue({ equipLoc = equipLoc, stats = stats, speed = speed, dagger = subClassID == 15 or nil }, e.set)
  return string.format("Score for %s (%s): %.2f %s  [%s]", key, self:SpecName(e.class, e.spec), self:ToPoints(e, v),
    self:UnitLabel(e), self:SourceLine(e))
end

local function RequestItemStats(link, P)
  local id = ItemIDFrom(link)
  if id and ItemAPI.Request then SafeCall(ItemAPI.Request, id) end
  P("No stats returned yet (item data loading?). Try again in a moment.")
end

function GCA:StatsDebug(link, P)
  P = P or Print
  if not link or not link:find("item:", 1, true) then P("Usage: /rq craft stats <shift-click an item>") return end
  local raw = PlainCall("table", ItemAPI.Stats, link)
  if not raw then
    RequestItemStats(link, P)
    return
  end
  P(RawStatsLine(raw))
  local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subClassID = SafeCall(ItemAPI.Info, link)
  local stats, unknown = Scoring.normalize(raw)
  Scoring.addWeaponDps(stats, equipLoc)
  local speed
  if classID == 2 then
    speed = self:WeaponSpeed(ItemIDFrom(link), link)
    P(WeaponLine(speed, FirstDps(stats), subClassID))
  end
  P(CanonicalLine(stats, unknown))
  local score = ScoreLine(self, equipLoc, stats, speed, subClassID)
  if score then P(score) end
end

local function ProfessionsHeader(trusted)
  local raw = { SafeCall(GetProfessions or function() end) }
  local parts = {}
  for i = 1, 6 do parts[#parts + 1] = tostring(raw[i]) end
  return "GetProfessions: " .. table.concat(parts, ", ")
    .. (trusted and "  (trusted)" or "  (not trusted yet: nothing is cleared, nothing is 'browse')")
end

local function ProfessionLine(self, p, own)
  local o = own[p.key]
  return string.format("%s (skill line %d): %s, selected=%s", p.key, p.skillLine,
    o and string.format("yours %s/%s \"%s\"", tostring(o.rank), tostring(o.maxRank), tostring(o.name)) or "not yours",
    tostring(p.key == self:SelectedProfession()))
end

local function TallySpell(tally, id, saved)
  local a = C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, id)
  local b = IsPlayerSpell and SafeCall(IsPlayerSpell, id)
  tally.n = tally.n + 1
  if a and not IsSecret(a) then tally.spellKnown = tally.spellKnown + 1 end
  if b and not IsSecret(b) then tally.playerSpell = tally.playerSpell + 1 end
  if saved[id] then tally.saved = tally.saved + 1 end
  if (a or b) and #tally.sample < 3 then tally.sample[#tally.sample + 1] = id end
end

local function ProbeLine(text, spells, saved)
  local t = { n = 0, spellKnown = 0, playerSpell = 0, saved = 0, sample = {} }
  for id in pairs(spells) do TallySpell(t, id, saved) end
  return string.format("  %s: %d in data, IsSpellKnown %d, IsPlayerSpell %d, saved %d%s", text, t.n, t.spellKnown,
    t.playerSpell, t.saved, #t.sample > 0 and (" (e.g. " .. table.concat(t.sample, ", ") .. ")") or "")
end

local function ProbeLines(self, P, own, trusted)
  local store = self:KnownStore()
  for _, p in ipairs(self.PROFESSIONS) do
    if own[p.key] or not trusted then
      local saved = store[p.key] or EMPTY
      P(ProbeLine(p.key .. " item recipes", self:RecipeTable(p.key), saved))
      if p.key == "Enchanting" then P(ProbeLine("Enchanting enchant spells", self:EnchantData().bySpell, saved)) end
    end
  end
end

local function InAnyRecipeTable(self, id)
  for _, p in ipairs(self.PROFESSIONS) do
    if self:RecipeTable(p.key)[id] then return true end
  end
  return false
end

local function RecipeLearned(api, id)
  local info = SafeCall(api.GetRecipeInfo, id)
  return type(info) == "table" and info.learned and not IsSecret(info.learned)
end

local function CountRecipeIDs(self, api, ids)
  local items, enchants, learned = 0, 0, 0
  local ench = self:EnchantData().bySpell
  for _, id in ipairs(ids) do
    local isEnch = ench[id] ~= nil
    local isItem = InAnyRecipeTable(self, id)
    if isEnch then enchants = enchants + 1 elseif isItem then items = items + 1 end
    if (isEnch or isItem) and api.GetRecipeInfo and RecipeLearned(api, id) then learned = learned + 1 end
  end
  return items, enchants, learned
end

local function TradeSkillUILine(self)
  local api = C_TradeSkillUI
  if not (api and api.GetAllRecipeIDs) then return "C_TradeSkillUI.GetAllRecipeIDs: not available" end
  local ids = SafeCall(api.GetAllRecipeIDs)
  if type(ids) ~= "table" then
    return "C_TradeSkillUI.GetAllRecipeIDs: no list (open a profession window and run this again)"
  end
  local items, enchants, learned = CountRecipeIDs(self, api, ids)
  return string.format("C_TradeSkillUI.GetAllRecipeIDs: %d IDs (open window), %d item recipes + %d enchants in our data, %d learned",
    #ids, items, enchants, learned)
end

local function LegacyWindowLine()
  local n = SafeCall(GetNumTradeSkills)
  local line = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
  local rl = GetTradeSkillRecipeLink and SafeCall(GetTradeSkillRecipeLink, 1)
  return string.format("Legacy trade skill window: line %s, %s rows, recipe link 1 = %s", tostring(line), tostring(n), tostring(rl))
end

local function KnownCountsLine(self)
  local t = {}
  for _, p in ipairs(self.PROFESSIONS) do t[#t + 1] = p.key .. "=" .. (self.knownCounts[p.key] or 0) end
  return string.format("Known counts: %s", table.concat(t, ", "))
end

function GCA:KnownDebug(P)
  P = P or Print
  local own, trusted = self:ReadProfessions()
  P(ProfessionsHeader(trusted))
  for _, p in ipairs(self.PROFESSIONS) do P(ProfessionLine(self, p, own)) end
  ProbeLines(self, P, own, trusted)
  P(TradeSkillUILine(self))
  if GetNumTradeSkills then P(LegacyWindowLine()) end
  P(KnownCountsLine(self))
end

local function EnchantedLinks(self, link)
  if link and link:find("item:", 1, true) then return { link } end
  local links = {}
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local l = PlainCall("string", GetInventoryItemLink, "player", slot)
    if l and self:EnchantIDOf(l) then links[#links + 1] = l end
  end
  return links
end

local function CanonicalStats(link)
  local raw = PlainCall("table", ItemAPI.Stats, link)
  if not raw then return nil end
  return (Scoring.normalize(raw))
end

local function StatDifferences(a, b)
  local keys, diff = {}, {}
  for k in pairs(a) do keys[k] = true end
  for k in pairs(b) do keys[k] = true end
  for k in pairs(keys) do
    local d = (a[k] or 0) - (b[k] or 0)
    if math.abs(d) > 1e-9 then diff[#diff + 1] = string.format("%s%+g", k, d) end
  end
  table.sort(diff)
  return diff
end

local function EnchantVerdict(link, plainLink)
  local a, b = CanonicalStats(link), CanonicalStats(plainLink)
  if not (a and b) then return "stats not loaded yet, try again" end
  local diff = StatDifferences(a, b)
  if #diff == 0 then return "NOT included (enchanted and plain link give the same stats)" end
  return "INCLUDED: " .. table.concat(diff, ", ")
end

function GCA:EnchantDebug(link, P)
  P = P or Print
  local links = EnchantedLinks(self, link)
  if #links == 0 then P("No enchanted item found. Usage: /rq craft enchant debug [shift-click an enchanted item]") return end
  local data = self:EnchantData()
  for _, l in ipairs(links) do
    local id = self:EnchantIDOf(l)
    local row = id and data.byEnchant[id]
    P(string.format("%s enchant %s = %s: %s", l, tostring(id),
      row and (row.name .. " [" .. row.kind .. "]") or "|cffff8800not in our table (no suggestion for this slot)|r",
      EnchantVerdict(l, self:WithoutEnchant(l))))
  end
  P("Enchant suggestions always score the item without its enchant (link field 2 blanked), so both cases are handled.")
end
