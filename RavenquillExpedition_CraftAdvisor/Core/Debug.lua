local ADDON, ns = ...
local GCA = ns.GCA
local priv = GCA.priv
local Print, IsSecret, SafeCall, ItemAPI = priv.Print, priv.IsSecret, priv.SafeCall, priv.ItemAPI
local ItemIDFrom, Scoring, EMPTY = priv.ItemIDFrom, priv.Scoring, priv.EMPTY

---------------------------------------------------------------------------
-- /rq craft stats <item link>: raw GetItemStats keys + our canonical result (F3)
---------------------------------------------------------------------------
function GCA:StatsDebug(link, P)
  P = P or Print -- P(line): where the lines go (the options' copy box), default chat
  if not link or not link:find("item:", 1, true) then P("Usage: /rq craft stats <shift-click an item>") return end
  local raw = SafeCall(ItemAPI.Stats, link)
  if type(raw) ~= "table" or IsSecret(raw) then
    local id = ItemIDFrom(link)
    if id and ItemAPI.Request then SafeCall(ItemAPI.Request, id) end
    P("No stats returned yet (item data loading?). Try again in a moment.")
    return
  end
  local keys = {}
  for k, v in pairs(raw) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(keys)
  P("GetItemStats: " .. (#keys > 0 and table.concat(keys, ", ") or "(empty)"))
  local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subClassID = SafeCall(ItemAPI.Info, link)
  local stats, unknown = Scoring.normalize(raw)
  Scoring.addWeaponDps(stats, equipLoc)
  local speed
  if classID == 2 then -- W7: speed + DPS of a weapon
    speed = self:WeaponSpeed(ItemIDFrom(link), link)
    local dps
    for _, k in ipairs({ "MainHandDps", "TwoHandDps", "OffHandDps", "RangedDps" }) do dps = dps or stats[k] end
    P(string.format("Weapon: speed %s (label %s), DPS %s, dagger %s", speed and string.format("%.2f", speed) or "not read",
      tostring(type(SPEED) == "string" and not IsSecret(SPEED) and SPEED or "nil"), dps and string.format("%.2f", dps) or "-",
      tostring(subClassID == 15)))
  end
  local out = {}
  for k, v in pairs(stats) do out[#out + 1] = string.format("%s=%g", k, v) end
  table.sort(out)
  P("Canonical: " .. (#out > 0 and table.concat(out, ", ") or "(none)") ..
    (#unknown > 0 and ("  |cffff8800unmapped: " .. table.concat(unknown, ", ") .. "|r") or ""))
  local key = self.UI and self.UI.selected or self.playerKey
  local entry = key and self.UI and self.UI.current
  local e = entry and entry.weights
  if e then
    local v = Scoring.itemValue({ equipLoc = equipLoc, stats = stats, speed = speed, dagger = subClassID == 15 or nil }, e.set)
    P(string.format("Score for %s (%s): %.2f %s  [%s]", key, self:SpecName(e.class, e.spec), self:ToPoints(e, v), self:UnitLabel(e), self:SourceLine(e)))
  end
end

---------------------------------------------------------------------------
-- Known recipes debug: which APIs see your recipes, item recipes vs enchant spells
---------------------------------------------------------------------------
function GCA:KnownDebug(P)
  P = P or Print -- P(line): where the lines go (the options' copy box), default chat
  local own, trusted = self:ReadProfessions()
  local raw = { SafeCall(GetProfessions or function() end) }
  local parts = {}
  for i = 1, 6 do parts[#parts + 1] = tostring(raw[i]) end
  P("GetProfessions: " .. table.concat(parts, ", ") .. (trusted and "  (trusted)" or "  (not trusted yet: nothing is cleared, nothing is 'browse')"))
  for _, p in ipairs(self.PROFESSIONS) do
    local o = own[p.key]
    P(string.format("%s (skill line %d): %s, selected=%s", p.key, p.skillLine,
      o and string.format("yours %s/%s \"%s\"", tostring(o.rank), tostring(o.maxRank), tostring(o.name)) or "not yours",
      tostring(p.key == self:SelectedProfession())))
  end
  local store = self:KnownStore()
  local function probe(label, spells)
    local isk, isp, saved, n, sample = 0, 0, 0, 0, {}
    local sp = store[label.prof] or EMPTY
    for id in pairs(spells) do
      n = n + 1
      local a = C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, id)
      local b = IsPlayerSpell and SafeCall(IsPlayerSpell, id)
      if a and not IsSecret(a) then isk = isk + 1 end
      if b and not IsSecret(b) then isp = isp + 1 end
      if sp[id] then saved = saved + 1 end
      if (a or b) and #sample < 3 then sample[#sample + 1] = id end
    end
    P(string.format("  %s: %d in data, IsSpellKnown %d, IsPlayerSpell %d, saved %d%s", label.text, n, isk, isp, saved,
      #sample > 0 and (" (e.g. " .. table.concat(sample, ", ") .. ")") or ""))
  end
  for _, p in ipairs(self.PROFESSIONS) do
    if own[p.key] or not trusted then
      probe({ prof = p.key, text = p.key .. " item recipes" }, self:RecipeTable(p.key))
      if p.key == "Enchanting" then probe({ prof = p.key, text = "Enchanting enchant spells" }, self:EnchantData().bySpell) end
    end
  end
  local api = C_TradeSkillUI
  if api and api.GetAllRecipeIDs then
    local ids = SafeCall(api.GetAllRecipeIDs)
    if type(ids) == "table" then
      local items, enchants, learned = 0, 0, 0
      local ench = self:EnchantData().bySpell
      for _, id in ipairs(ids) do
        local isEnch = ench[id] ~= nil
        local isItem = false
        for _, p in ipairs(self.PROFESSIONS) do if self:RecipeTable(p.key)[id] then isItem = true end end
        if isEnch then enchants = enchants + 1 elseif isItem then items = items + 1 end
        if (isEnch or isItem) and api.GetRecipeInfo then
          local info = SafeCall(api.GetRecipeInfo, id)
          if type(info) == "table" and info.learned and not IsSecret(info.learned) then learned = learned + 1 end
        end
      end
      P(string.format("C_TradeSkillUI.GetAllRecipeIDs: %d IDs (open window), %d item recipes + %d enchants in our data, %d learned", #ids, items, enchants, learned))
    else
      P("C_TradeSkillUI.GetAllRecipeIDs: no list (open a profession window and run this again)")
    end
  else
    P("C_TradeSkillUI.GetAllRecipeIDs: not available")
  end
  if GetNumTradeSkills then
    local n = SafeCall(GetNumTradeSkills)
    local line = GetTradeSkillLine and SafeCall(GetTradeSkillLine)
    local rl = GetTradeSkillRecipeLink and SafeCall(GetTradeSkillRecipeLink, 1)
    P(string.format("Legacy trade skill window: line %s, %s rows, recipe link 1 = %s", tostring(line), tostring(n), tostring(rl)))
  end
  P(string.format("Known counts: %s", (function()
    local t = {}
    for _, p in ipairs(self.PROFESSIONS) do t[#t + 1] = p.key .. "=" .. (self.knownCounts[p.key] or 0) end
    return table.concat(t, ", ")
  end)()))
end

---------------------------------------------------------------------------
-- /rq craft enchant debug [item link]: does GetItemStats on an enchanted link include the enchant?
---------------------------------------------------------------------------
function GCA:EnchantDebug(link, P)
  P = P or Print -- P(line): where the lines go (the options' copy box), default chat
  local links = {}
  if link and link:find("item:", 1, true) then links[1] = link
  else
    for _, slot in ipairs(self.SYNC_SLOTS) do
      local l = SafeCall(GetInventoryItemLink, "player", slot)
      if type(l) == "string" and not IsSecret(l) and self:EnchantIDOf(l) then links[#links + 1] = l end
    end
  end
  if #links == 0 then P("No enchanted item found. Usage: /rq craft enchant debug [shift-click an enchanted item]") return end
  local data = self:EnchantData()
  local function canon(l)
    local raw = SafeCall(ItemAPI.Stats, l)
    if type(raw) ~= "table" or IsSecret(raw) then return nil end
    return (Scoring.normalize(raw))
  end
  for _, l in ipairs(links) do
    local id = self:EnchantIDOf(l)
    local row = id and data.byEnchant[id]
    local a, b = canon(l), canon(self:WithoutEnchant(l))
    local diff = {}
    if a and b then
      local keys = {}
      for k in pairs(a) do keys[k] = true end
      for k in pairs(b) do keys[k] = true end
      for k in pairs(keys) do
        local d = (a[k] or 0) - (b[k] or 0)
        if math.abs(d) > 1e-9 then diff[#diff + 1] = string.format("%s%+g", k, d) end
      end
      table.sort(diff)
    end
    local verdict
    if not (a and b) then verdict = "stats not loaded yet, try again"
    elseif #diff == 0 then verdict = "NOT included (enchanted and plain link give the same stats)"
    else verdict = "INCLUDED: " .. table.concat(diff, ", ") end
    P(string.format("%s enchant %s = %s: %s", l, tostring(id),
      row and (row.name .. " [" .. row.kind .. "]") or "|cffff8800not in our table (no suggestion for this slot)|r", verdict))
  end
  P("Enchant suggestions always score the item without its enchant (link field 2 blanked), so both cases are handled.")
end
