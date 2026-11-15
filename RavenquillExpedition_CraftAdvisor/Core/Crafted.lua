local ADDON, ns = ...
local GCA = ns.GCA
local priv = GCA.priv
local ItemIDFrom, EMPTY = priv.ItemIDFrom, priv.EMPTY

---------------------------------------------------------------------------
-- "Crafted" marks: a local reminder per character, keyed member -> profession -> recipe spellID.
-- Not synced. Cleared when a new gear record of that member shows the item in a slot that didn't hold it when
-- you ticked, or more copies of it than then (review M-3); for an enchant, when the marked slot carries that
-- enchant ID. Otherwise kept until unticked.
-- db.crafted[charKey][memberKey][prof][spellID] = { item = itemID, had = { [slot] = true }, count | enchant = enchantID, slot, t }
---------------------------------------------------------------------------
function GCA:CraftedStore(create)
  if not (self.db and self.charKey) then return nil end
  if not self.db.crafted then
    if not create then return nil end
    self.db.crafted = {}
  end
  local t = self.db.crafted[self.charKey]
  if not t and create then t = {}; self.db.crafted[self.charKey] = t end
  return t
end

function GCA:CraftedMark(member, prof, spellID)
  local t = self:CraftedStore(false)
  local p = t and member and t[member] and t[member][prof]
  return p and spellID and p[spellID] or nil
end

function GCA:SetCrafted(member, prof, sug, on)
  if not (member and prof and sug and sug.cand and sug.cand.spellID) then return end
  local spellID = sug.cand.spellID
  if on then
    local t = self:CraftedStore(true)
    if not t then return end
    t[member] = t[member] or {}
    t[member][prof] = t[member][prof] or {}
    local isEnchant = sug.kind == "enchant"
    local mark = {
      item = (not isEnchant) and sug.cand.itemID or nil,
      enchant = isEnchant and sug.enchant and sug.enchant.enchant or nil,
      slot = sug.slot, t = time(),
    }
    -- review M-3: the slots that already hold this item when you tick (e.g. one ring of a pair you made earlier);
    -- only a NEW slot with it, or more copies than now, counts as "wearing the one you crafted"
    if mark.item then
      local m = self.db.members and self.db.members[member]
      mark.had, mark.count = {}, 0
      for slot, link in pairs(m and m.items or EMPTY) do
        if ItemIDFrom(link) == mark.item then mark.had[slot] = true; mark.count = mark.count + 1 end
      end
    end
    t[member][prof][spellID] = mark
  else
    local t = self:CraftedStore(false)
    local p = t and t[member] and t[member][prof]
    if not p then return end
    p[spellID] = nil
    if not next(p) then t[member][prof] = nil end
    if not next(t[member]) then t[member] = nil end
  end
end

local function MarkWorn(self, mark, items)
  if mark.enchant then
    return mark.slot ~= nil and self:EnchantIDOf(items[mark.slot]) == mark.enchant
  end
  if not mark.item then return false end
  -- review M-3: marks ticked before this fix have no `had`/`count`: then any slot with the item counts (as in 0.5.0)
  local had, n = mark.had or EMPTY, 0
  for slot, link in pairs(items) do
    if ItemIDFrom(link) == mark.item then
      n = n + 1
      if not had[slot] then return true end
    end
  end
  return n > (mark.count or 0)
end

-- Called for every stored record (own inspect, own gear, guild sync). Marks of all your characters are checked:
-- once the member wears it, nobody needs the reminder. Returns the number of marks cleared.
function GCA:ClearWornCrafted(member, items)
  if not (self.db and self.db.crafted and member and type(items) == "table") then return 0 end
  local n = 0
  for _, byMember in pairs(self.db.crafted) do
    local profs = byMember[member]
    if profs then
      for prof, marks in pairs(profs) do
        for spellID, mark in pairs(marks) do
          if MarkWorn(self, mark, items) then marks[spellID] = nil; n = n + 1 end
        end
        if not next(marks) then profs[prof] = nil end
      end
      if not next(profs) then byMember[member] = nil end
    end
  end
  return n
end
