local ADDON, ns = ...
local GCA = ns.GCA
local RQ = RavenquillExpedition
local priv = GCA.priv
local Scoring, EMPTY, Better, Order = priv.Scoring, priv.EMPTY, priv.Better, priv.Order
local PlayerFaction = priv.PlayerFaction

---------------------------------------------------------------------------
-- Suggestions per member, slot sections, the member list and guild needs
---------------------------------------------------------------------------
-- view = { key, class, level, items, spec }. prof: profession (default: the selected one).
-- Returns list, pending, state, weight entry. state: "ok", "no-level", "no-class", "no-spec", "no-weights", "loading".
function GCA:ComputeSuggestions(m, isSelf, prof)
  local s = self.db.settings
  prof = prof or self:SelectedProfession()
  local browse = self:IsBrowse(prof)
  local showAll = s.showUnlearned or browse -- browse forces show-unlearned
  local class, level = m.class, m.level
  if not class then return {}, 0, "no-class" end
  if type(level) ~= "number" or level < 1 then return {}, 0, "no-level" end
  if not m.spec then return {}, 0, "no-spec" end
  local e = self:WeightSetFor(class, m.spec, level)
  if not e then return {}, 0, "no-weights" end
  local maxLevel = level + (s.lookahead and self.LOOKAHEAD_LEVELS or 0)
  local items = m.items or {}
  local pending = 0

  -- equipped items in SimGear's shape; an item that failed to load makes its slot unknown
  local equipped, equippedInfo, unknownSlot = {}, {}, {}
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
  -- comparing against half-loaded gear would show fake "empty slot" upgrades
  if pending > 0 then return {}, pending, "loading", e end

  local excluded = self.GEAR_RULES[class .. "/" .. m.spec] or {}
  -- a candidate that would be compared with an unknown slot is not offered (rings/trinkets: either slot; weapons,
  -- shields and held off-hands are compared as the main hand + off hand pair)
  local function touchesUnknown(loc)
    for _, sl in ipairs(self.SLOTS_FOR[loc] or {}) do if unknownSlot[sl] then return true end end
    return self.HAND_LOCS[loc] == true and (unknownSlot[16] == true or unknownSlot[17] == true)
  end
  local function valueOf(item) return item.info and self:Score(item.info, e) end
  local sets = self:ItemSets()
  local faction = PlayerFaction()
  -- W4: dual wield now (compare opts) and from which level (off-hand weapons are look-ahead rows before it)
  local dwFrom = self:DualWieldFrom(class, m.spec, level, isSelf)
  local opts = { dualWield = dwFrom ~= nil and level >= dwFrom }
  local best, all = {}, {} -- best: the 0.5.0 per-slot pick (badge meaning); all: every suggestion per section (I)
  for _, cand in ipairs(self:GetCandidates(prof)) do
    local known = not browse and self:IsKnown(cand.spellID, prof)
    local recipe = cand.recipe
    local offWeapon = cand.equipLoc == "INVTYPE_WEAPONOFFHAND" -- only for a dual-wielder (SimGear Advisor.scoreItem)
    if (known or showAll) and (known or not (recipe.faction and faction and recipe.faction ~= faction))
       and self:CanWear(class, maxLevel, cand) and not excluded[cand.equipLoc] and not touchesUnknown(cand.equipLoc)
       and not (offWeapon and not (dwFrom and dwFrom <= maxLevel)) then
      local info, failed = self:GetInfo(cand.itemID)
      -- the level this member can actually wear it at (item level, armor/weapon proficiency, dual wield)
      local needLevel = info and math.max(info.minLevel, self:WearFrom(class, cand) or 0)
      if info and offWeapon then needLevel = math.max(needLevel, dwFrom) end
      if not info then
        if not failed then pending = pending + 1 end
      elseif needLevel <= maxLevel and (isSelf or info.bind ~= 1) and self:PassesRestrictions(cand.itemID, class, isSelf) then
        local candItem = self:ScoreItem(info)
        candItem.equipLoc = info.equipLoc or cand.equipLoc
        local r = Scoring.compare(candItem, equipped, e.set, sets, valueOf, opts)
        local sug
        if r and r.status ~= "equipped" then
          local gain = r.newValue - r.oldValue
          local tier, points = nil, self:ToPoints(e, gain)
          if r.status == "needs-partner" then
            -- a one-hander / off hand next to a worn two-hander: scored alone, its own tier after the real gains
            points = self:ToPoints(e, r.newValue)
            if r.newValue > 0 and points >= self.MIN_POINTS then tier = self.TIER_PARTNER end
          elseif r.status == "empty-slot" then
            if r.newValue > 0 and points >= self.MIN_POINTS then tier = 1 end
          elseif r.status == "no-baseline" then
            if gain > 0 and points >= self.MIN_POINTS then tier = 1 end
          elseif r.pct and r.pct >= self.MIN_PCT then
            tier = 1
          end
          if tier then
            -- the hand/slot the craft goes into (W4): a dual-wield one-hander in the off hand -> 17; a needs-partner
            -- off hand -> 17 even though the worn two-hander is what it displaces
            local slot = r.replaces and r.replaces[1] or self.SLOTS_FOR[cand.equipLoc][1]
            local worn = equippedInfo[slot]
            if r.status == "needs-partner" then
              slot = Scoring.OFF_HAND_TYPES[cand.equipLoc] and 17 or 16
              worn = equippedInfo[16]
            elseif cand.equipLoc == "INVTYPE_2HWEAPON" and equippedInfo[16] and equippedInfo[17] then
              worn = self:PairInfo(equippedInfo[16], equippedInfo[17])
            end
            sug = {
              kind = "item", cand = cand, info = info, slot = slot, known = known, future = needLevel > level,
              wearAt = needLevel > level and needLevel or nil, -- "wearable at level N (in X levels)"
              levelsToGo = needLevel > level and (needLevel - level) or nil,
              status = r.status, pct = r.status ~= "needs-partner" and r.pct or nil, tier = tier,
              gain = gain, points = points, newScore = r.newValue, oldScore = r.oldValue,
              equipped = worn, sets = r.sets, setDelta = r.setDelta, e = e,
              hand = r.hand, -- "off": a dual-wield one-hander scored in the off hand (row says "(off hand)")
              bothHands = (cand.equipLoc == "INVTYPE_2HWEAPON" and equippedInfo[17] ~= nil) or nil, -- "replaces both hands"
            }
          end
        end
        if sug then
          local afterIDs = {}
          for sl, it in pairs(equipped) do
            local gone = sl == sug.slot or (r.replaces and (r.replaces[1] == sl or r.replaces[2] == sl))
            if not gone then afterIDs[#afterIDs + 1] = it.itemID end
          end
          afterIDs[#afterIDs + 1] = cand.itemID
          sug.afterIDs = afterIDs
          -- one per slot, known/unlearned AND wearable/look-ahead (review M-2): a bigger look-ahead craft must not
          -- hide the craft the member can wear now; both are listed (wearable first inside a tier, SuggestionOrder)
          -- W4: weapons go to the section of the hand they are scored in
          local group = self.HAND_LOCS[cand.equipLoc] and sug.slot or self.SLOTS_FOR[cand.equipLoc][1]
          local gkey = group .. "|" .. (sug.future and "f" or "w") .. (known and "k" or "u")
          local cur = best[gkey]
          if not cur or Better(sug, cur) then best[gkey] = sug end
          -- section I: every suggestion is kept per section for the top 3
          all[group] = all[group] or {}
          all[group][#all[group] + 1] = sug
        end
      end
    end
  end
  if prof == "Enchanting" then
    pending = pending + self:AddEnchantSuggestions(best, { e = e, items = items, prof = prof, browse = browse, showAll = showAll,
      equippedInfo = equippedInfo, unknownSlot = unknownSlot, all = all })
  end

  -- The per-slot pick of 0.5.0 ("primary" rows): best per slot × known/unlearned × wearable/look-ahead, hidden when
  -- another one for the same slot is at least as good AND at least as usable: known beats unlearned, wearable now
  -- beats look-ahead (so a look-ahead craft no better than a wearable one isn't listed, and an unlearned recipe no
  -- better than a known one isn't either). A better look-ahead craft stays (M-2). These rows keep the meaning of the
  -- member badge/best, the member order and the minimap counts (section I); the extra rows of the top 3 don't count.
  local primary = {}
  for gkey, sug in pairs(best) do
    local group = gkey:match("^(.*)|")
    local hidden = false
    for _, flags in ipairs({ "wk", "wu", "fk", "fu" }) do
      local other = best[group .. "|" .. flags]
      if other and other ~= sug and (other.known or not sug.known) and (sug.future or not other.future)
         and not Better(sug, other) then
        hidden = true
        break
      end
    end
    if not hidden then primary[sug] = true end
  end

  -- Section I: up to SECTION_TOP rows per section (slot; rings and trinkets one section each), in the display order.
  local list, shownBy, totals = {}, {}, {}
  for group, rows in pairs(all) do
    local shown, total = self:SectionCut(rows, primary)
    shownBy[group], totals[group] = shown, total
    for _, sug in ipairs(shown) do list[#list + 1] = sug end
  end
  for _, sug in ipairs(list) do
    if sug.kind == "item" then sug.hint = self:SetHint(sug.cand.itemID, sug.afterIDs, prof) end
  end
  table.sort(list, Order)
  if next(unknownSlot) then list.unknownSlots = unknownSlot end
  list.sections = self:BuildSections(shownBy, totals, items, equippedInfo, unknownSlot, e)
  return list, pending, "ok", e
end

-- Section I: how many crafts/enchants a slot section lists.
GCA.SECTION_TOP = 3
-- Section order "in character order" for slots without an upgrade; rings and trinkets are one section each.
GCA.SECTION_SLOTS = { { 1 }, { 2 }, { 3 }, { 15 }, { 5 }, { 9 }, { 10 }, { 6 }, { 7 }, { 8 }, { 11, 12 }, { 13, 14 }, { 16 }, { 17 }, { 18 } }
GCA.SECTION_OF = {}
for _, slots in ipairs(GCA.SECTION_SLOTS) do for _, sl in ipairs(slots) do GCA.SECTION_OF[sl] = slots[1] end end

-- The rows of one section (all suggestions for that slot): duplicates dropped (the same item from two recipes, or
-- two enchant rows with the same enchant ID), rows dominated by a more usable one dropped (the rule above:
-- an unlearned recipe no better than a known one, a look-ahead craft no better than a wearable one), then the
-- first SECTION_TOP in SuggestionOrder. A known primary row (it counts for the badge/minimap) is never cut: it takes
-- the place of the last non-primary row. Every row gets `extra = true` unless it is a primary row.
-- Returns the shown rows (SuggestionOrder) and how many rows were eligible before the cut.
function GCA:SectionCut(rows, primary)
  local sorted = {}
  for i, s in ipairs(rows) do sorted[i] = s end
  table.sort(sorted, Order)
  local uniq, at = {}, {}
  for _, s in ipairs(sorted) do
    local id = s.kind == "enchant" and ("E" .. tostring(s.enchant and s.enchant.enchant)) or ("I" .. tostring(s.cand and s.cand.itemID))
    local i = at[id]
    if not i then
      uniq[#uniq + 1] = s
      at[id] = #uniq
    elseif primary[s] and not primary[uniq[i]] then
      uniq[i] = s
    end
  end
  local kept = {}
  for _, s in ipairs(uniq) do
    local hidden = false
    if not primary[s] then
      for _, o in ipairs(uniq) do
        if o ~= s and o.kind == s.kind and ((o.known and not s.known) or (s.future and not o.future))
           and (o.known or not s.known) and (s.future or not o.future) and not Better(s, o) then
          hidden = true
          break
        end
      end
    end
    if not hidden then kept[#kept + 1] = s end
  end
  local top = self.SECTION_TOP
  local shown = {}
  for i = 1, math.min(top, #kept) do shown[i] = kept[i] end
  for i = top + 1, #kept do
    local s = kept[i]
    if primary[s] and s.known then
      for j = #shown, 1, -1 do
        if not (primary[shown[j]] and shown[j].known) then shown[j] = s; break end
      end
    end
  end
  table.sort(shown, Order)
  for _, s in ipairs(shown) do s.extra = (not primary[s]) or nil end
  return shown, #kept
end

-- Sections for the window (section I): one per SECTION_SLOTS entry with the worn item(s) and their scores; the
-- sections with rows first, by their first row (SuggestionOrder, the comparison of the member order), then the
-- ones without an upgrade in character order. sec = { key, slots, rows, total, worn = { {slot, link, info, score,
-- unknown} }, unknown = a worn item didn't load (nothing was compared there), index }.
function GCA:BuildSections(shownBy, totals, items, equippedInfo, unknownSlot, e)
  local secs = {}
  for i, slots in ipairs(self.SECTION_SLOTS) do
    local key = slots[1]
    local worn, unknown = {}, false
    for _, sl in ipairs(slots) do
      local info = equippedInfo[sl]
      worn[#worn + 1] = { slot = sl, link = items[sl], info = info, unknown = unknownSlot[sl] or nil,
        score = info and self:ToPoints(e, self:Score(info, e)) or nil }
      if unknownSlot[sl] then unknown = true end
    end
    secs[#secs + 1] = { key = key, slots = slots, index = i, rows = shownBy[key] or {}, total = totals[key] or 0,
      worn = worn, unknown = unknown }
  end
  table.sort(secs, function(a, b)
    local ra, rb = a.rows[1], b.rows[1]
    if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
    if ra and rb then
      if Order(ra, rb) then return true end
      if Order(rb, ra) then return false end
    end
    return a.index < b.index
  end)
  return secs
end

-- Suggestions for one member and profession, cached on gear signature + spec + level + settings
-- + profession, browse and the known-set revision.
GCA.sugCache = {}
GCA.knownGen = 0
function GCA:MemberSuggestions(view, isSelf, prof)
  local s = self.db.settings
  prof = prof or self:SelectedProfession()
  local sig = table.concat({ self:GearSignature(view.items), tostring(view.class), tostring(view.level), tostring(view.spec),
    s.showUnlearned and "u" or "", s.lookahead and "l" or "", tostring(self:SurvivalShare()), self.knownGen,
    prof, self:IsBrowse(prof) and "b" or "" }, "|")
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

-- Known suggestions only (badges, member order, minimap count only what you can craft).
-- The member's best is the first wearable one (review M-2); a look-ahead one only when nothing known is wearable.
-- Section I: the extra rows of a slot's top 3 (`extra`) don't count, so the badge and the minimap count keep
-- their meaning (one per slot and wearable/look-ahead, as in 0.5.0).
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

-- All members for the left-hand list (guild roster + everyone we have gear for)
function GCA:GetMemberList()
  local s = self.db.settings
  local prof = self:SelectedProfession()
  local browse = self:IsBrowse(prof)
  local entries, seen = {}, {}
  local function add(key)
    if seen[key] then return end
    seen[key] = true
    local m, r = self.db.members[key], RQ:RosterEntry(key)
    local isSelf = key == self.playerKey
    if not isSelf and not r and not (m and m.source ~= "self") then return end
    local online = isSelf or (r and r.online) or false
    if s.hideOffline and not online and not m then return end
    local e = {
      key = key, isSelf = isSelf, online = online, member = m, browse = browse, prof = prof,
      class = (r and r.class) or (m and m.class), level = (r and r.level) or (m and m.level),
    }
    if type(e.level) ~= "number" or e.level < 1 then e.level = nil end
    e.spec, e.specHow, e.specAssumed = self:MemberSpec(key, e.class, m and m.items)
    if m then
      local view = { key = key, class = e.class, level = e.level, items = m.items, spec = e.spec }
      e.suggestions, e.pending, e.state, e.weights = self:MemberSuggestions(view, isSelf, prof)
      -- badges and the member order count only recipes you know; browse counts nothing
      if browse then e.knownCount = 0 else e.knownCount, e.best = KnownOnly(e.suggestions) end
    end
    entries[#entries + 1] = e
  end
  if self.playerKey then add(self.playerKey) end
  for key in pairs(self.db.members) do add(key) end
  for key in RQ:EachMember() do add(key) end

  table.sort(entries, function(a, b)
    if a.isSelf ~= b.isSelf then return a.isSelf end
    local ai, bi = a.member and 1 or 0, b.member and 1 or 0
    if ai ~= bi then return ai > bi end
    -- members with the biggest single % upgrade first
    if (a.best ~= nil) ~= (b.best ~= nil) then return a.best ~= nil end
    if a.best and b.best then
      if Order(a.best, b.best) then return true end
      if Order(b.best, a.best) then return false end
    end
    if a.online ~= b.online then return a.online end
    return a.key < b.key
  end)
  return entries
end

-- K2 "Guild needs": one row per member and suggestion, biggest gain first. Built from GetMemberList's entries
-- (their suggestion lists are the cached MemberSuggestions results, so nothing is scored here). Rows = what the
-- member view lists minus the extra rows of a slot's top 3 (`extra`): the primary per-slot picks that also drive
-- the badge; with "Show unlearned" / browse that includes unlearned recipes, exactly as in the member view.
-- You (isSelf) and members without a gear record have no rows. Order: SuggestionOrder (tiers, wearable before
-- look-ahead, gain), then member key, then recipe. Returns { online = {rows}, offline = {rows} }, rows =
-- { rowKind = "need", sug = suggestion, member = entry }.
-- Cached: the same entries (key, suggestion list, online, class, in the same order) and the same sugCache table
-- (InvalidateScores replaces it) give the same result without sorting again.
function GCA:GuildNeeds(entries)
  entries = entries or self:GetMemberList()
  local c = self.needsCache
  if c and c.sugCache == self.sugCache and #c.keys == #entries then
    local same = true
    for i, e in ipairs(entries) do
      local k = c.keys[i]
      if k[1] ~= e.key or k[2] ~= e.suggestions or k[3] ~= e.online or k[4] ~= e.class then same = false; break end
    end
    if same then return c.result end
  end
  local online, offline, keys = {}, {}, {}
  for i, e in ipairs(entries) do
    keys[i] = { e.key, e.suggestions, e.online, e.class }
    if not e.isSelf and e.member then
      for _, s in ipairs(e.suggestions or EMPTY) do
        if not s.extra then
          local row = { rowKind = "need", sug = s, member = e }
          if e.online then online[#online + 1] = row else offline[#offline + 1] = row end
        end
      end
    end
  end
  local function order(a, b)
    if Order(a.sug, b.sug) then return true end
    if Order(b.sug, a.sug) then return false end
    if a.member.key ~= b.member.key then return a.member.key < b.member.key end
    return (a.sug.cand and a.sug.cand.spellID or 0) < (b.sug.cand and b.sug.cand.spellID or 0)
  end
  table.sort(online, order)
  table.sort(offline, order)
  -- K5: grouped by craft (one entry per recipe that is an upgrade for >= 1 member). Built from the sorted rows, so
  -- a group's first row is its best and the groups come out in the same order as their best rows (wearable
  -- before look-ahead inside a tier, then the gain). One row per member and craft (a ring craft for both rings:
  -- the better one). crafts = online members only (the default), craftsAll = online + offline.
  local function group(rows)
    local out, byKey = {}, {}
    for _, r in ipairs(rows) do
      local s = r.sug
      local key = (s.kind == "enchant" and "e" or "i") .. tostring(s.cand and s.cand.spellID or (s.info and s.info.name) or "?")
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
  local all = {}
  for _, r in ipairs(online) do all[#all + 1] = r end
  for _, r in ipairs(offline) do all[#all + 1] = r end
  table.sort(all, order)
  local result = { online = online, offline = offline, crafts = group(online), craftsAll = group(all) }
  self.needsCache = { sugCache = self.sugCache, keys = keys, result = result }
  self.needsBuilds = (self.needsBuilds or 0) + 1
  return result
end

-- K5: the guild needs grouped by craft, for the UI (and the K6 rebuild). withOffline: include offline members.
-- Returns the cached list of groups { rowKind = "craft", key, sug = best suggestion, best = best row,
-- rows = { { rowKind = "need", sug, member } ... } best first, future = only too-high-level }, best group first.
function GCA:GuildNeedsByCraft(entries, withOffline)
  local needs = self:GuildNeeds(entries)
  return withOffline and needs.craftsAll or needs.crafts, needs
end

-- Upgrades you can craft, per profession of yours (minimap tooltip). Browse never counts.
-- Without a trusted GetProfessions answer: the selected profession only.
function GCA:UpgradeCounts()
  local own, trusted = self:OwnProfessions()
  local sel = self:SelectedProfession()
  local entries = self:GetMemberList()
  local out = {}
  for _, p in ipairs(self.PROFESSIONS) do
    if (trusted and own[p.key]) or (not trusted and p.key == sel) then
      local n, members = 0, 0
      for _, en in ipairs(entries) do
        if en.member and not en.isSelf then
          local list = self:MemberSuggestions({ key = en.key, class = en.class, level = en.level, items = en.member.items, spec = en.spec }, false, p.key)
          local k = KnownOnly(list)
          n = n + k
          if k > 0 then members = members + 1 end
        end
      end
      out[#out + 1] = { prof = p.key, upgrades = n, members = members }
    end
  end
  local recorded = 0
  for _, en in ipairs(entries) do if en.member and not en.isSelf then recorded = recorded + 1 end end
  return out, recorded
end
