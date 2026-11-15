-- Spec per member (plan F4 / F8.2, F8.4, F8.6, F8.7): own talents (C_Traits), synced spec, inspected
-- talents (only when the data looks plausible), manual pick (wins). Unknown -> no suggestions.
--
-- Spec.pointsFromNodes / infer are ported from SimGear Forever 0.14.0 Spec.lua,
-- Copyright (c) 2026 Flavius and SimGear Forever contributors, MIT License (full text in Scoring.lua
-- and NOTICE.txt).
local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall, IsSecret = GCA.SafeCall, GCA.IsSecret

---------------------------------------------------------------------------
-- Fixed spec list. The index is what goes over the wire (S;<index>;<ts>): APPEND ONLY, never reorder.
---------------------------------------------------------------------------
GCA.SPEC_LIST = {
  { "DRUID", "BALANCE", "Balance" }, { "DRUID", "FERAL_CAT", "Feral (Cat)" },          -- 1, 2
  { "DRUID", "FERAL_BEAR", "Feral (Bear)" }, { "DRUID", "RESTORATION", "Restoration" }, -- 3, 4
  { "HUNTER", "BEAST_MASTERY", "Beast Mastery" }, { "HUNTER", "MARKSMANSHIP", "Marksmanship" }, -- 5, 6
  { "HUNTER", "SURVIVAL", "Survival (ranged)" }, { "HUNTER", "SURVIVAL_MELEE", "Survival (melee)" }, -- 7, 8
  { "MAGE", "ARCANE", "Arcane" }, { "MAGE", "FIRE", "Fire" }, { "MAGE", "FROST", "Frost" },     -- 9-11
  { "PALADIN", "HOLY", "Holy" }, { "PALADIN", "PROTECTION", "Protection" }, { "PALADIN", "RETRIBUTION", "Retribution" }, -- 12-14
  { "PRIEST", "DISCIPLINE", "Discipline" }, { "PRIEST", "HOLY", "Holy" },                  -- 15, 16
  { "PRIEST", "SHADOW", "Shadow" }, { "PRIEST", "SMITE", "Smite (damage)" },               -- 17, 18
  { "ROGUE", "ASSASSINATION", "Assassination" }, { "ROGUE", "COMBAT", "Combat" }, { "ROGUE", "SUBTLETY", "Subtlety" }, -- 19-21
  { "SHAMAN", "ELEMENTAL", "Elemental" }, { "SHAMAN", "ENHANCEMENT", "Enhancement" },       -- 22, 23
  { "SHAMAN", "ENHANCEMENT_DW", "Enhancement (dual-wield)" }, { "SHAMAN", "RESTORATION", "Restoration" }, -- 24, 25
  { "WARLOCK", "AFFLICTION", "Affliction" }, { "WARLOCK", "DEMONOLOGY", "Demonology" }, { "WARLOCK", "DESTRUCTION", "Destruction" }, -- 26-28
  { "WARRIOR", "ARMS", "Arms" }, { "WARRIOR", "FURY", "Fury" }, { "WARRIOR", "PROTECTION", "Protection" }, -- 29-31
}
GCA.SPEC_INDEX, GCA.SPECS_OF, GCA.SPEC_NAME = {}, {}, {}
for i, e in ipairs(GCA.SPEC_LIST) do
  local class, key, name = e[1], e[2], e[3]
  GCA.SPEC_INDEX[class .. "/" .. key] = i
  GCA.SPECS_OF[class] = GCA.SPECS_OF[class] or {}
  table.insert(GCA.SPECS_OF[class], key)
  GCA.SPEC_NAME[class .. "/" .. key] = name
end

-- Display name; localized through "SPEC:<English name>" keys when the client language has them (H4).
function GCA:SpecName(class, spec)
  if not spec then return "?" end
  local name = self.SPEC_NAME[(class or "") .. "/" .. spec]
  if not name then return spec end
  return (ns.LGet and ns.LGet("SPEC:" .. name)) or name
end
function GCA:ValidSpec(class, spec) return spec ~= nil and self.SPEC_INDEX[(class or "") .. "/" .. spec] ~= nil end

-- Talent trees left to right (SimGear Classes.lua).
GCA.TREES = {
  DRUID = { "BALANCE", "FERAL", "RESTORATION" }, HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" },
  MAGE = { "ARCANE", "FIRE", "FROST" }, PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
  PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" }, ROGUE = { "ASSASSINATION", "COMBAT", "SUBTLETY" },
  SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" }, WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
  WARRIOR = { "ARMS", "FURY", "PROTECTION" },
}

-- The talent tree of a variant spec (SimGear Classes treeSpecs / specTree / dualWieldSets).
GCA.SPEC_TREE = { FERAL_CAT = "FERAL", FERAL_BEAR = "FERAL", ENHANCEMENT_DW = "ENHANCEMENT", SMITE = "DISCIPLINE", SURVIVAL_MELEE = "SURVIVAL" }
function GCA:TreeOfSpec(spec) return spec and (self.SPEC_TREE[spec] or spec) end

-- Equip locations a spec never uses (SimGear Classes gearRules).
GCA.GEAR_RULES = {
  ["DRUID/FERAL_CAT"] = { INVTYPE_HOLDABLE = true }, ["DRUID/FERAL_BEAR"] = { INVTYPE_HOLDABLE = true },
  ["PALADIN/PROTECTION"] = { INVTYPE_2HWEAPON = true, INVTYPE_HOLDABLE = true },
  ["WARRIOR/PROTECTION"] = { INVTYPE_2HWEAPON = true, INVTYPE_HOLDABLE = true },
}

---------------------------------------------------------------------------
-- Talent points -> tree (SimGear Spec.lua, MIT)
---------------------------------------------------------------------------
local TREE_X = { 1020, 5020, 9080 }
local X_SLACK = 100
local CANVAS_MAX_X = 11000

-- nodes: { { posX, ranks } }. Returns { <tree> = points }, unplaced rank count.
function GCA:PointsFromNodes(nodes, class)
  local trees = self.TREES[class or ""] or {}
  local points, unplaced = {}, 0
  for _, tree in ipairs(trees) do points[tree] = 0 end
  for _, node in ipairs(nodes or {}) do
    local x, ranks = node.posX, node.ranks or 0
    if type(x) == "number" and type(ranks) == "number" and ranks > 0 then
      if x > CANVAS_MAX_X then x = x / 10 end
      local tree
      for i, left in ipairs(TREE_X) do
        if x >= left - X_SLACK then tree = trees[i] end
      end
      if tree then points[tree] = points[tree] + ranks else unplaced = unplaced + ranks end
    end
  end
  return points, unplaced
end

-- Returns tree or nil, reason ("talents", "no-talents", "tie").
function GCA:InferTree(points, class)
  local best, bestPoints, tie, total = nil, 0, false, 0
  for _, tree in ipairs(self.TREES[class or ""] or {}) do
    local n = points and points[tree] or 0
    total = total + n
    if n > bestPoints then best, bestPoints, tie = tree, n, false
    elseif n == bestPoints and n > 0 then tie = true end
  end
  if total == 0 then return nil, "no-talents" end
  if tie then return nil, "tie" end
  return best, "talents"
end

---------------------------------------------------------------------------
-- Tree -> spec, with the variant rules the user chose (F8.7). Returns spec, assumedText or nil.
---------------------------------------------------------------------------
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_WEAPONMAINHAND = true }

function GCA:OffHandIsWeapon(items)
  local link = items and items[17]
  if not link then return false end
  local _, _, _, equipLoc = SafeCall(self.ItemAPI.Instant, link)
  return ONE_HAND[equipLoc or ""] == true
end

-- catKnown: true/false when we could check Cat Form (own character), nil otherwise.
function GCA:ResolveTree(tree, class, items, catKnown)
  if class == "DRUID" and tree == "FERAL" then
    if catKnown == true then return "FERAL_CAT" end
    if catKnown == false then return "FERAL_BEAR" end
    return "FERAL_CAT", "Feral tree → Cat assumed (pick Bear by hand)"
  end
  if class == "SHAMAN" and tree == "ENHANCEMENT" and self:OffHandIsWeapon(items) then
    return "ENHANCEMENT_DW", "one-hand weapon in the off hand → dual-wield assumed"
  end
  return tree
end

---------------------------------------------------------------------------
-- Reading talents (C_Traits; Forever has no GetTalentTabInfo)
---------------------------------------------------------------------------
local function Plain(v) if IsSecret(v) then return nil end return v end

-- Reads a trait config. Returns { configID, treeID, nodes = { {posX, ranks} }, purchased, active, used } or nil, why.
function GCA:ReadTraitConfig(configID, allTrees)
  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil, "no C_Traits" end
  if type(configID) ~= "number" then return nil, "no config ID" end
  local config = SafeCall(C_Traits.GetConfigInfo, configID)
  if type(config) ~= "table" or IsSecret(config) then return nil, "no config info" end
  local treeIDs = Plain(config.treeIDs)
  if type(treeIDs) ~= "table" or not Plain(treeIDs[1]) then return nil, "config has no tree" end
  local raw = {}
  local list = allTrees and treeIDs or { treeIDs[1] }
  for _, treeID in ipairs(list) do
    treeID = Plain(treeID)
    local nodeIDs = treeID and SafeCall(C_Traits.GetTreeNodes, treeID)
    if type(nodeIDs) == "table" then
      for _, nodeID in ipairs(nodeIDs) do
        local info = SafeCall(C_Traits.GetNodeInfo, configID, Plain(nodeID))
        if type(info) == "table" and not IsSecret(info) then
          local x, rp, ar = Plain(info.posX), Plain(info.ranksPurchased), Plain(info.activeRank)
          if type(x) == "number" then
            raw[#raw + 1] = { posX = x, rp = type(rp) == "number" and rp or 0, ar = type(ar) == "number" and ar or 0 }
          end
        end
      end
    end
  end
  local r = { configID = configID, treeID = Plain(treeIDs[1]), nodes = {}, purchased = 0, active = 0, nodeCount = #raw }
  for _, n in ipairs(raw) do r.purchased = r.purchased + n.rp; r.active = r.active + n.ar end
  -- as Leatrix Plus: inspect data may only carry activeRank
  r.used = r.purchased > 0 and "ranksPurchased" or "activeRank"
  for _, n in ipairs(raw) do
    r.nodes[#r.nodes + 1] = { posX = n.posX, ranks = r.purchased > 0 and n.rp or n.ar }
  end
  return r
end

function GCA:ReadOwnTalents()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return nil, "no C_ClassTalents" end
  local id = SafeCall(C_ClassTalents.GetActiveConfigID)
  if IsSecret(id) then return nil, "secret" end
  return self:ReadTraitConfig(id, false)
end

-- Cat Form (768) known? true/false when the client can tell, nil when it can't. IsPlayerSpell first, as
-- SimGear's Client.knowsSpell; C_SpellBook.IsSpellKnown as a fallback.
function GCA:CatFormKnown()
  for _, fn in ipairs({ IsPlayerSpell or false, C_SpellBook and C_SpellBook.IsSpellKnown or false }) do
    if fn then
      local ok, v = pcall(fn, 768)
      if ok and not IsSecret(v) and type(v) == "boolean" then return v end
    end
  end
  return nil
end

-- Own spec from talents (cached in self.ownSpec). Returns true when it changed.
function GCA:RefreshOwnSpec()
  local class = self.playerClass
  if not class then local _, c = SafeCall(UnitClass, "player"); if c and not IsSecret(c) then class = c; self.playerClass = c end end
  local read, why = self:ReadOwnTalents()
  local o = { reason = why or "?" }
  if read then
    local points = self:PointsFromNodes(read.nodes, class)
    o.points = points
    local tree, reason = self:InferTree(points, class)
    o.tree, o.reason = tree, reason
    if tree then
      local items = self.playerKey and self.db and self.db.members[self.playerKey] and self.db.members[self.playerKey].items
      local cat -- true/false only when we could check (own Druid); `x and false or nil` would lose false
      if class == "DRUID" then cat = self:CatFormKnown() end
      o.spec, o.assumed = self:ResolveTree(tree, class, items, cat)
    end
  end
  local old = self.ownSpec
  self.ownSpec = o
  local changed = not old or old.spec ~= o.spec
  if changed then
    self:InvalidateScores()
    if self.CheckOwnSpec then SafeCall(self.CheckOwnSpec, self) end
  end
  return changed
end

---------------------------------------------------------------------------
-- Inspected talents (F8.6): only kept when plausible
---------------------------------------------------------------------------
-- node-by-node fingerprint of the ranked nodes
local function NodeSig(nodes)
  local parts = {}
  for _, n in ipairs(nodes or {}) do
    if (n.ranks or 0) > 0 then parts[#parts + 1] = n.posX .. ":" .. n.ranks end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

function GCA:ReadInspectTalents(class, level)
  local id = Constants and Constants.TraitConsts and Plain(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
  local read, why = self:ReadTraitConfig(id, true)
  if not read then return nil, why or "no data", { configID = id } end
  local points, unplaced = self:PointsFromNodes(read.nodes, class)
  read.points, read.unplaced = points, unplaced
  local total = 0
  for _, n in pairs(points) do total = total + n end
  read.total = total
  if total == 0 then return nil, "no points", read end
  local maxPoints = (type(level) == "number" and level >= 10) and (level - 9) or 51
  if total > maxPoints then return nil, "more points than the level allows", read end
  if unplaced > 0 then return nil, "ranks outside the three trees", read end
  -- the client may hand back OUR talents: reject a read identical to our own tree
  local own = self:ReadOwnTalents()
  if own then
    if class ~= self.playerClass and own.treeID == read.treeID then return nil, "same tree as yours (another class)", read end
    if class == self.playerClass and NodeSig(own.nodes) == NodeSig(read.nodes) then
      return nil, "identical to your own talents", read
    end
  end
  local tree, reason = self:InferTree(points, class)
  if not tree then return nil, reason, read end
  return tree, "ok", read
end

function GCA:InspectTalentsOn() return self.db and self.db.settings.inspectTalents == true end

-- Called from OnInspectReady (Core) with the inspected unit's key/class/level, its GUID and the inspect
-- generation (Core bumps self.inspectGen on every INSPECT_READY and every NotifyInspect): reads at 0, 0.3
-- and 1 s. A retry stops once another inspect started or arrived, so B's talents are never filed under A.
function GCA:TryInspectTalents(key, class, level, guid, gen)
  if not (key and class) then return end
  gen = gen or self.inspectGen
  local done = false
  local function try()
    if done then return end
    if self.inspectGen ~= gen or (guid and self.inspectGUID and self.inspectGUID ~= guid) then done = true return end
    local tree, why, read = self:ReadInspectTalents(class, level)
    self.lastInspectTalents = { key = key, class = class, level = level, tree = tree, why = why, read = read, at = GetTime() }
    if tree then
      done = true
      -- off by default (F8.6 "used only if verified in game"): still read, for /gca spec debug
      if self:InspectTalentsOn() then
        self:StoreSpec(key, class, { tree = tree, src = "inspect", ts = self:Now() })
      end
    end
  end
  try()
  C_Timer.After(0.3, function() try() end)
  C_Timer.After(1, function() try() end)
end

---------------------------------------------------------------------------
-- Stored specs: db.specs[key] = { class, spec | tree, src = "sync"|"self"|"inspect", ts }; db.specManual[key] = spec
-- src "self" (K0/L5) = written by that character itself on this account, so your alts know your main's spec;
-- it ranks like "sync".
---------------------------------------------------------------------------
-- Order: newer ts wins, except on the SAME talent tree a synced spec always beats an inspect read (S carries
-- the sender's last spec change, which can be days older than our inspect; and sync knows Cat/Bear, Smite, ...).
-- An inspect record is ignored entirely while inspected talents are off.
function GCA:StoreSpec(key, class, rec)
  if not (key and class and self.db) then return false end
  local cur = self.db.specs[key]
  if cur and cur.class == class and not (cur.src == "inspect" and not self:InspectTalentsOn()) then
    local sameTree = (cur.tree or self:TreeOfSpec(cur.spec)) == (rec.tree or self:TreeOfSpec(rec.spec))
    local curSync, recSync = cur.src == "sync" or cur.src == "self", rec.src == "sync" or rec.src == "self"
    if sameTree and curSync and rec.src == "inspect" then return false end
    if not (sameTree and cur.src == "inspect" and recSync) and (cur.ts or 0) > (rec.ts or 0) then return false end
  end
  rec.class = class
  local same = cur and cur.class == class and cur.spec == rec.spec and cur.tree == rec.tree
  self.db.specs[key] = rec
  -- K0/M3: the suggestion cache signature includes the spec (Core MemberSuggestions) and weight sets are cached
  -- per class|spec|level|share, so a refresh is enough; no need to drop every member's cached scores
  if not same then self:Invalidate() end
  return not same
end

function GCA:SetManualSpec(key, class, spec)
  if not key then return end
  if spec and not self:ValidSpec(class, spec) then return end
  self.db.specManual[key] = spec and { class = class, spec = spec } or nil
  if key == self.playerKey and self.CheckOwnSpec then SafeCall(self.CheckOwnSpec, self) end
  self:InvalidateScores()
end

-- Returns spec or nil, how ("manual"|"talents"|"synced"|"own"|"inspected"|reason when unknown), assumed text.
function GCA:MemberSpec(key, class, items)
  if not class then return nil, "class unknown" end
  local man = self.db.specManual[key]
  if man and man.class == class and self:ValidSpec(class, man.spec) then return man.spec, "manual" end
  if key == self.playerKey then
    local o = self.ownSpec
    if o and o.spec and self:ValidSpec(class, o.spec) then return o.spec, "talents", o.assumed end
    return nil, o and o.reason or "talents not read yet"
  end
  local rec = self.db.specs[key]
  if rec and rec.class == class then
    if rec.src == "sync" and self:ValidSpec(class, rec.spec) then return rec.spec, "synced" end
    if rec.src == "self" and self:ValidSpec(class, rec.spec) then return rec.spec, "own" end
    if rec.src == "inspect" and rec.tree and self:InspectTalentsOn() then
      local spec, assumed = self:ResolveTree(rec.tree, class, items, nil)
      if self:ValidSpec(class, spec) then return spec, "inspected", assumed end
    end
  end
  return nil, "unknown"
end

-- K0/L5: persist the spec this character announces under its own key, so alts on the account see it.
function GCA:StoreOwnSpec(spec, ts)
  if not (spec and self.playerKey and self.playerClass and self.db and self.db.specs) then return false end
  return self:StoreSpec(self.playerKey, self.playerClass, { spec = spec, src = "self", ts = ts or self:Now() })
end

-- The spec this character announces (manual pick for yourself wins).
function GCA:OwnAnnouncedSpec()
  local class = self.playerClass
  local spec = self:MemberSpec(self.playerKey, class, self.playerKey and self.db.members[self.playerKey] and self.db.members[self.playerKey].items)
  return spec and self.SPEC_INDEX[class .. "/" .. spec], spec
end

---------------------------------------------------------------------------
-- /gca spec debug
---------------------------------------------------------------------------
local function fmtPoints(points, class)
  local parts = {}
  for _, t in ipairs(GCA.TREES[class or ""] or {}) do parts[#parts + 1] = t .. " " .. (points and points[t] or 0) end
  return table.concat(parts, " / ")
end

function GCA:SpecDebug()
  local P = self.Print
  local read, why = self:ReadOwnTalents()
  if read then
    P(string.format("Own talents: config %s, tree %s, %d nodes, ranksPurchased %d, activeRank %d (using %s).",
      tostring(read.configID), tostring(read.treeID), read.nodeCount, read.purchased, read.active, read.used))
    P("  points: " .. fmtPoints(self:PointsFromNodes(read.nodes, self.playerClass), self.playerClass))
  else
    P("Own talents: not readable (" .. tostring(why) .. ").")
  end
  local o = self.ownSpec or {}
  P(string.format("  detected: %s (%s)%s; Cat Form known: %s", tostring(o.spec), tostring(o.reason),
    o.assumed and (" – " .. o.assumed) or "", tostring(self:CatFormKnown())))
  local announced = select(2, self:OwnAnnouncedSpec())
  P("  announced over sync: " .. tostring(announced))
  local li = self.lastInspectTalents
  if li then
    local r = li.read or {}
    P(string.format("Last inspect (%s, %s %s): config %s, tree %s, %s nodes, ranksPurchased %s, activeRank %s → %s (%s).",
      li.key, tostring(li.class), tostring(li.level), tostring(r.configID), tostring(r.treeID), tostring(r.nodeCount),
      tostring(r.purchased), tostring(r.active), tostring(li.tree), tostring(li.why)))
    if r.points then P("  points: " .. fmtPoints(r.points, li.class) .. (r.unplaced and r.unplaced > 0 and (" (+" .. r.unplaced .. " outside the trees)") or "")) end
    P("  inspected talents are " .. (self:InspectTalentsOn() and "used when plausible" or "ignored (off by default)") .. (self.onCore and " (option 'spec from inspected talents')." or " (/gca spec inspect on|off)."))
  else
    P("No inspect read yet: inspect a guild member, then " .. (self.onCore and "open this box again." or "run /gca spec debug again."))
  end
end
