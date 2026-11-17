local ADDON, ns = ...
local GCA = ns.GCA
local ItemIDFrom = GCA.ItemIDFrom
local EMPTY = {}

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

local function CountWornCopies(self, member, mark)
  local m = self.db.members and self.db.members[member]
  mark.had, mark.count = {}, 0
  for slot, link in pairs(m and m.items or EMPTY) do
    if ItemIDFrom(link) == mark.item then mark.had[slot] = true; mark.count = mark.count + 1 end
  end
end

local function NewMark(self, member, sug)
  local isEnchant = sug.kind == "enchant"
  local mark = {
    item = (not isEnchant) and sug.cand.itemID or nil,
    enchant = isEnchant and sug.enchant and sug.enchant.enchant or nil,
    slot = sug.slot, t = time(),
  }
  if mark.item then CountWornCopies(self, member, mark) end
  return mark
end

local function AddMark(self, member, prof, spellID, sug)
  local t = self:CraftedStore(true)
  if not t then return end
  t[member] = t[member] or {}
  t[member][prof] = t[member][prof] or {}
  t[member][prof][spellID] = NewMark(self, member, sug)
end

local function RemoveMark(self, member, prof, spellID)
  local t = self:CraftedStore(false)
  local p = t and t[member] and t[member][prof]
  if not p then return end
  p[spellID] = nil
  if not next(p) then t[member][prof] = nil end
  if not next(t[member]) then t[member] = nil end
end

function GCA:SetCrafted(member, prof, sug, on)
  if not (member and prof and sug and sug.cand and sug.cand.spellID) then return end
  if on then
    AddMark(self, member, prof, sug.cand.spellID, sug)
  else
    RemoveMark(self, member, prof, sug.cand.spellID)
  end
end

local function MarkWorn(self, mark, items)
  if mark.enchant then
    return mark.slot ~= nil and self:EnchantIDOf(items[mark.slot]) == mark.enchant
  end
  if not mark.item then return false end
  local had, n = mark.had or EMPTY, 0
  for slot, link in pairs(items) do
    if ItemIDFrom(link) == mark.item then
      n = n + 1
      if not had[slot] then return true end
    end
  end
  return n > (mark.count or 0)
end

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
