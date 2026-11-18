local ADDON, ns = ...
local GCA = ns.GCA
local RQ = RavenquillExpedition
local Scoring, Better, Order = ns.Scoring, GCA.BetterSuggestion, GCA.SuggestionOrder
local EQUIP_LOCS = Scoring.EQUIP_LOCS
local EMPTY = {}
local PlayerFaction, Offerable, KeepSuggestion = GCA.PlayerFaction, GCA.Offerable, GCA.KeepSuggestion

local function MissingInput(m)
  if not m.class then return "no-class" end
  if type(m.level) ~= "number" or m.level < 1 then return "no-level" end
  if not m.spec then return "no-spec" end
end

local function ReadEquipped(self, items)
  local equipped, equippedInfo, unknownSlot, pending = {}, {}, {}, 0
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local link = items[slot]
    if link then
      local info, failed = self:GetInfo(link)
      if failed then
        unknownSlot[slot] = true
      elseif not info then
        pending = pending + 1
      else
        equipped[slot] = self:ScoreItem(info)
        equippedInfo[slot] = info
      end
    end
  end
  return equipped, equippedInfo, unknownSlot, pending
end

local function TouchesUnknown(unknownSlot, loc)
  local rule = EQUIP_LOCS[loc]
  if not rule then return false end
  for _, sl in ipairs(rule.slots) do if unknownSlot[sl] then return true end end
  return rule.hand ~= nil and (unknownSlot[16] == true or unknownSlot[17] == true)
end

local function OffersCandidate(self, ctx, cand, known)
  if not Offerable(known, ctx.showAll, cand.recipe, ctx.faction) then return false end
  if not self:CanWear(ctx.class, ctx.maxLevel, cand) then return false end
  if ctx.excluded[cand.equipLoc] or TouchesUnknown(ctx.unknownSlot, cand.equipLoc) then return false end
  if cand.equipLoc ~= "INVTYPE_WEAPONOFFHAND" then return true end
  return ctx.dwFrom and ctx.dwFrom <= ctx.maxLevel
end

local function NeedLevel(self, ctx, cand, info)
  local need = math.max(info.minLevel, self:WearFrom(ctx.class, cand) or 0)
  if cand.equipLoc == "INVTYPE_WEAPONOFFHAND" then need = math.max(need, ctx.dwFrom) end
  return need
end

local function Obtainable(self, ctx, cand, info, needLevel)
  if needLevel > ctx.maxLevel then return false end
  if not ctx.isSelf and info.bind == 1 then return false end
  return self:PassesRestrictions(cand.itemID, ctx.class, ctx.isSelf)
end

local function UpgradeTier(self, r, gain, points)
  local enough = points >= self.MIN_POINTS
  if r.status == "empty-slot" then return r.newValue > 0 and enough and 1 or nil end
  if r.status == "no-baseline" then return gain > 0 and enough and 1 or nil end
  return r.pct and r.pct >= self.MIN_PCT and 1 or nil
end

local function ItemTier(self, e, r)
  local gain = r.newValue - r.oldValue
  if r.status == "needs-partner" then
    local points = self:ToPoints(e, r.newValue)
    return r.newValue > 0 and points >= self.MIN_POINTS and self.TIER_PARTNER or nil, gain, points
  end
  local points = self:ToPoints(e, gain)
  return UpgradeTier(self, r, gain, points), gain, points
end

local function CompareCandidate(self, ctx, cand, info)
  local candItem = self:ScoreItem(info)
  candItem.equipLoc = info.equipLoc or cand.equipLoc
  local r = Scoring.compare(candItem, ctx.equipped, ctx.e.set, ctx.sets, ctx.valueOf, ctx.opts)
  if r and r.status ~= "equipped" then return r end
end

local function TargetSlot(self, cand, r, equippedInfo)
  local rule = EQUIP_LOCS[cand.equipLoc]
  local slot = r.replaces and r.replaces[1] or rule.slots[1]
  if r.status == "needs-partner" then
    return rule.hand == "off" and 17 or 16, equippedInfo[16]
  end
  if cand.equipLoc == "INVTYPE_2HWEAPON" and equippedInfo[16] and equippedInfo[17] then
    return slot, self:PairInfo(equippedInfo[16], equippedInfo[17])
  end
  return slot, equippedInfo[slot]
end

local function ItemSuggestion(self, ctx, cand, info, known, needLevel)
  local r = CompareCandidate(self, ctx, cand, info)
  if not r then return nil end
  local tier, gain, points = ItemTier(self, ctx.e, r)
  if not tier then return nil end
  local slot, worn = TargetSlot(self, cand, r, ctx.equippedInfo)
  local future = needLevel > ctx.level
  return {
    kind = "item", cand = cand, info = info, slot = slot, known = known, future = future,
    wearAt = future and needLevel or nil,
    levelsToGo = future and (needLevel - ctx.level) or nil,
    status = r.status, pct = r.status ~= "needs-partner" and r.pct or nil, tier = tier,
    gain = gain, points = points, newScore = r.newValue, oldScore = r.oldValue,
    equipped = worn, sets = r.sets, setDelta = r.setDelta, e = ctx.e,
    hand = r.hand,
    bothHands = (cand.equipLoc == "INVTYPE_2HWEAPON" and ctx.equippedInfo[17] ~= nil) or nil,
  }, r
end

local function ItemIDsAfter(equipped, slot, replaces, itemID)
  local ids = {}
  for sl, it in pairs(equipped) do
    local gone = sl == slot or (replaces and (replaces[1] == sl or replaces[2] == sl))
    if not gone then ids[#ids + 1] = it.itemID end
  end
  ids[#ids + 1] = itemID
  return ids
end

local function KeepItemSuggestion(self, ctx, sug, r)
  local cand = sug.cand
  sug.afterIDs = ItemIDsAfter(ctx.equipped, sug.slot, r.replaces, cand.itemID)
  local rule = EQUIP_LOCS[cand.equipLoc]
  local group = rule.hand and sug.slot or rule.slots[1]
  local bestKey = group .. "|" .. (sug.future and "f" or "w") .. (sug.known and "k" or "u")
  KeepSuggestion(ctx.best, ctx.all, bestKey, group, sug)
end

local function ConsiderCandidate(self, ctx, cand)
  local known = not ctx.browse and self:IsKnown(cand.spellID, ctx.prof)
  if not OffersCandidate(self, ctx, cand, known) then return end
  local info, failed = self:GetInfo(cand.itemID)
  if not info then
    if not failed then ctx.pending = ctx.pending + 1 end
    return
  end
  local needLevel = NeedLevel(self, ctx, cand, info)
  if not Obtainable(self, ctx, cand, info, needLevel) then return end
  local sug, r = ItemSuggestion(self, ctx, cand, info, known, needLevel)
  if sug then KeepItemSuggestion(self, ctx, sug, r) end
end

local function Covers(other, sug)
  return (other.known or not sug.known) and (sug.future or not other.future) and not Better(sug, other)
end

local AVAILABILITY_FLAGS = { "wk", "wu", "fk", "fu" }
local function Overshadowed(best, bestKey, sug)
  local group = bestKey:match("^(.*)|")
  for _, flags in ipairs(AVAILABILITY_FLAGS) do
    local other = best[group .. "|" .. flags]
    if other and other ~= sug and Covers(other, sug) then return true end
  end
  return false
end

local function PrimarySuggestions(best)
  local primary = {}
  for bestKey, sug in pairs(best) do
    if not Overshadowed(best, bestKey, sug) then primary[sug] = true end
  end
  return primary
end

local function SuggestionList(self, ctx)
  local primary = PrimarySuggestions(ctx.best)
  local list, shownBy, totals = {}, {}, {}
  for group, rows in pairs(ctx.all) do
    local shown, total = self:SectionCut(rows, primary)
    shownBy[group], totals[group] = shown, total
    for _, sug in ipairs(shown) do list[#list + 1] = sug end
  end
  for _, sug in ipairs(list) do
    if sug.kind == "item" then sug.hint = self:SetHint(sug.cand.itemID, sug.afterIDs, ctx.prof) end
  end
  table.sort(list, Order)
  if next(ctx.unknownSlot) then list.unknownSlots = ctx.unknownSlot end
  list.sections = self:BuildSections(shownBy, totals, ctx.items, ctx.equippedInfo, ctx.unknownSlot, ctx.e)
  return list
end

local function NewContext(self, m, isSelf, prof, e)
  local s = self.db.settings
  local class, level = m.class, m.level
  local browse = self:IsBrowse(prof)
  local dwFrom = self:DualWieldFrom(class, m.spec, level, isSelf)
  return {
    class = class, level = level, isSelf = isSelf, prof = prof, browse = browse, showAll = s.showUnlearned or browse,
    maxLevel = level + (s.lookahead and self.LOOKAHEAD_LEVELS or 0), e = e, pending = 0,
    excluded = self.GEAR_RULES[class .. "/" .. m.spec] or {}, sets = self:ItemSets(), faction = PlayerFaction(),
    dwFrom = dwFrom, opts = { dualWield = dwFrom ~= nil and level >= dwFrom },
    valueOf = function(item) return item.info and self:Score(item.info, e) end,
    best = {}, all = {},
  }
end

function GCA:ComputeSuggestions(m, isSelf, prof)
  prof = prof or self:SelectedProfession()
  local missing = MissingInput(m)
  if missing then return {}, 0, missing end
  local e = self:WeightSetFor(m.class, m.spec, m.level)
  if not e then return {}, 0, "no-weights" end
  local items = m.items or {}
  local equipped, equippedInfo, unknownSlot, pending = ReadEquipped(self, items)
  if pending > 0 then return {}, pending, "loading", e end
  local ctx = NewContext(self, m, isSelf, prof, e)
  ctx.items, ctx.equipped, ctx.equippedInfo, ctx.unknownSlot = items, equipped, equippedInfo, unknownSlot
  for _, cand in ipairs(self:GetCandidates(prof)) do ConsiderCandidate(self, ctx, cand) end
  if prof == "Enchanting" then
    ctx.pending = ctx.pending + self:AddEnchantSuggestions(ctx.best, ctx)
  end
  return SuggestionList(self, ctx), ctx.pending, "ok", e
end

GCA.SECTION_TOP = 3
GCA.SECTION_SLOTS = { { 1 }, { 2 }, { 3 }, { 15 }, { 5 }, { 9 }, { 10 }, { 6 }, { 7 }, { 8 }, { 11, 12 }, { 13, 14 }, { 16 }, { 17 }, { 18 } }
GCA.SECTION_OF = {}
for _, slots in ipairs(GCA.SECTION_SLOTS) do for _, sl in ipairs(slots) do GCA.SECTION_OF[sl] = slots[1] end end

local function SuggestionID(s)
  if s.kind == "enchant" then return "E" .. tostring(s.enchant and s.enchant.enchant) end
  return "I" .. tostring(s.cand and s.cand.itemID)
end

local function UniqueByID(sorted, primary)
  local uniq, at = {}, {}
  for _, s in ipairs(sorted) do
    local id = SuggestionID(s)
    local i = at[id]
    if not i then
      uniq[#uniq + 1] = s
      at[id] = #uniq
    elseif primary[s] and not primary[uniq[i]] then
      uniq[i] = s
    end
  end
  return uniq
end

local function MoreAvailable(other, sug)
  return (other.known and not sug.known) or (sug.future and not other.future)
end

local function OutclassedWithin(rows, s)
  for _, o in ipairs(rows) do
    if o ~= s and o.kind == s.kind and MoreAvailable(o, s) and Covers(o, s) then return true end
  end
  return false
end

local function WithoutOutclassed(uniq, primary)
  local kept = {}
  for _, s in ipairs(uniq) do
    if primary[s] or not OutclassedWithin(uniq, s) then kept[#kept + 1] = s end
  end
  return kept
end

local function IsKnownPrimary(s, primary) return primary[s] and s.known end

local function ReplaceLastOrdinary(shown, s, primary)
  for j = #shown, 1, -1 do
    if not IsKnownPrimary(shown[j], primary) then shown[j] = s; return end
  end
end

local function TopRows(kept, primary, top)
  local shown = {}
  for i = 1, math.min(top, #kept) do shown[i] = kept[i] end
  for i = top + 1, #kept do
    if IsKnownPrimary(kept[i], primary) then ReplaceLastOrdinary(shown, kept[i], primary) end
  end
  return shown
end

function GCA:SectionCut(rows, primary)
  local sorted = {}
  for i, s in ipairs(rows) do sorted[i] = s end
  table.sort(sorted, Order)
  local kept = WithoutOutclassed(UniqueByID(sorted, primary), primary)
  local shown = TopRows(kept, primary, self.SECTION_TOP)
  table.sort(shown, Order)
  for _, s in ipairs(shown) do s.extra = (not primary[s]) or nil end
  return shown, #kept
end

local function OrderOptional(a, b)
  if (a ~= nil) ~= (b ~= nil) then return a ~= nil end
  if not (a and b) then return nil end
  if Order(a, b) then return true end
  if Order(b, a) then return false end
  return nil
end

local function SectionOrder(a, b)
  local byTopRow = OrderOptional(a.rows[1], b.rows[1])
  if byTopRow ~= nil then return byTopRow end
  return a.index < b.index
end

local function WornInSection(self, slots, items, equippedInfo, unknownSlot, e)
  local worn, unknown = {}, false
  for _, sl in ipairs(slots) do
    local info = equippedInfo[sl]
    worn[#worn + 1] = { slot = sl, link = items[sl], info = info, unknown = unknownSlot[sl] or nil,
      score = info and self:ToPoints(e, self:Score(info, e)) or nil }
    if unknownSlot[sl] then unknown = true end
  end
  return worn, unknown
end

function GCA:BuildSections(shownBy, totals, items, equippedInfo, unknownSlot, e)
  local secs = {}
  for i, slots in ipairs(self.SECTION_SLOTS) do
    local key = slots[1]
    local worn, unknown = WornInSection(self, slots, items, equippedInfo, unknownSlot, e)
    secs[#secs + 1] = { key = key, slots = slots, index = i, rows = shownBy[key] or {}, total = totals[key] or 0,
      worn = worn, unknown = unknown }
  end
  table.sort(secs, SectionOrder)
  return secs
end

GCA.sugCache = {}
GCA.knownGen = 0
function GCA:MemberSuggestions(view, isSelf, prof)
  local s = self.db.settings
  prof = prof or self:SelectedProfession()
  local sig = table.concat({ self:GearSignature(view.items), tostring(view.class), tostring(view.level), tostring(view.spec),
    s.showUnlearned and "u" or "", s.lookahead and "l" or "", tostring(self:SurvivalShare()), self.knownGen,
    prof, self:IsBrowse(prof) and "b" or "", tostring(self:DualWieldFrom(view.class, view.spec, view.level, isSelf)) }, "|")
  local ck = tostring(view.key) .. "|" .. prof
  local c = self.sugCache[ck]
  if c and c.sig == sig then return c.list, c.pending, c.state, c.e end
  local list, pending, state, e = self:ComputeSuggestions(view, isSelf, prof)
  if (pending or 0) == 0 then
    self.sugCache[ck] = { sig = sig, list = list, pending = pending, state = state, e = e }
  else
    self:ScheduleLoadRetry()
  end
  return list, pending, state, e
end

local function KnownOnly(list)
  local n, first, firstFuture = 0, nil, nil
  for _, sug in ipairs(list or EMPTY) do
    if sug.known and not sug.extra then
      n = n + 1
      if sug.future then firstFuture = firstFuture or sug else first = first or sug end
    end
  end
  return n, first or firstFuture
end
GCA.KnownOnly = KnownOnly

local function ValidLevel(level)
  if type(level) == "number" and level >= 1 then return level end
  return nil
end

local function AttachSuggestions(self, e, list)
  local view = { key = e.key, class = e.class, level = e.level, items = e.member.items, spec = e.spec }
  e.suggestions, e.pending, e.state, e.weights = self:MemberSuggestions(view, e.isSelf, list.prof)
  if list.browse then e.knownCount = 0 else e.knownCount, e.best = KnownOnly(e.suggestions) end
end

local function HiddenFromList(isSelf, r, m, hideOffline)
  if isSelf then return false end
  if not m then return not r or (hideOffline and not r.online) end
  return not r and m.source == "self"
end

local function MemberEntry(self, key, list)
  local m, r = self.db.members[key], RQ:RosterEntry(key)
  local isSelf = key == self.playerKey
  if HiddenFromList(isSelf, r, m, list.hideOffline) then return nil end
  local roster, record = r or EMPTY, m or EMPTY
  local e = {
    key = key, isSelf = isSelf, online = isSelf or roster.online or false, member = m, browse = list.browse, prof = list.prof,
    class = roster.class or record.class, level = ValidLevel(roster.level or record.level),
  }
  e.spec, e.specHow, e.specAssumed = self:MemberSpec(key, e.class, record.items)
  if m then AttachSuggestions(self, e, list) end
  return e
end

local function MemberOrder(a, b)
  if a.isSelf ~= b.isSelf then return a.isSelf end
  local ai, bi = a.member and 1 or 0, b.member and 1 or 0
  if ai ~= bi then return ai > bi end
  local byBest = OrderOptional(a.best, b.best)
  if byBest ~= nil then return byBest end
  if a.online ~= b.online then return a.online end
  return a.key < b.key
end

function GCA:GetMemberList()
  local prof = self:SelectedProfession()
  local list = { prof = prof, browse = self:IsBrowse(prof), hideOffline = self.db.settings.hideOffline }
  local entries, seen = {}, {}
  local function add(key)
    if seen[key] then return end
    seen[key] = true
    local e = MemberEntry(self, key, list)
    if e then entries[#entries + 1] = e end
  end
  if self.playerKey then add(self.playerKey) end
  for key in pairs(self.db.members) do add(key) end
  for key in RQ:EachMember() do add(key) end
  table.sort(entries, MemberOrder)
  return entries
end

local function NeedsCacheValid(c, sugCache, entries)
  if not (c and c.sugCache == sugCache and #c.keys == #entries) then return false end
  for i, e in ipairs(entries) do
    local k = c.keys[i]
    if k[1] ~= e.key or k[2] ~= e.suggestions or k[3] ~= e.online or k[4] ~= e.class then return false end
  end
  return true
end

local function AddNeedRows(e, into)
  for _, s in ipairs(e.suggestions or EMPTY) do
    if not s.extra then into[#into + 1] = { rowKind = "need", sug = s, member = e } end
  end
end

local function SplitNeeds(entries)
  local online, offline, keys = {}, {}, {}
  for i, e in ipairs(entries) do
    keys[i] = { e.key, e.suggestions, e.online, e.class }
    if not e.isSelf and e.member then AddNeedRows(e, e.online and online or offline) end
  end
  return online, offline, keys
end

local function NeedOrder(a, b)
  if Order(a.sug, b.sug) then return true end
  if Order(b.sug, a.sug) then return false end
  if a.member.key ~= b.member.key then return a.member.key < b.member.key end
  return (a.sug.cand and a.sug.cand.spellID or 0) < (b.sug.cand and b.sug.cand.spellID or 0)
end

local function CraftKey(s)
  return (s.kind == "enchant" and "e" or "i") .. tostring(s.cand and s.cand.spellID or (s.info and s.info.name) or "?")
end

local function GroupByCraft(rows)
  local out, byKey = {}, {}
  for _, r in ipairs(rows) do
    local s = r.sug
    local key = CraftKey(s)
    local g = byKey[key]
    if not g then
      g = { rowKind = "craft", key = key, sug = s, rows = {}, seen = {}, future = s.future and true or false }
      byKey[key] = g
      out[#out + 1] = g
    end
    if not g.seen[r.member.key] then
      g.seen[r.member.key] = true
      g.rows[#g.rows + 1] = r
    end
  end
  for _, g in ipairs(out) do g.best = g.rows[1]; g.seen = nil end
  return out
end

function GCA:GuildNeeds(entries)
  entries = entries or self:GetMemberList()
  local c = self.needsCache
  if NeedsCacheValid(c, self.sugCache, entries) then return c.result end
  local online, offline, keys = SplitNeeds(entries)
  table.sort(online, NeedOrder)
  table.sort(offline, NeedOrder)
  local all = {}
  for _, r in ipairs(online) do all[#all + 1] = r end
  for _, r in ipairs(offline) do all[#all + 1] = r end
  table.sort(all, NeedOrder)
  local result = { online = online, offline = offline, crafts = GroupByCraft(online), craftsAll = GroupByCraft(all) }
  self.needsCache = { sugCache = self.sugCache, keys = keys, result = result }
  self.needsBuilds = (self.needsBuilds or 0) + 1
  return result
end

function GCA:GuildNeedsByCraft(entries, withOffline)
  local needs = self:GuildNeeds(entries)
  return withOffline and needs.craftsAll or needs.crafts, needs
end
