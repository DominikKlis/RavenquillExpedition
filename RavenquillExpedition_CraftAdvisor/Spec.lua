local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall, IsSecret, Plain, PlainCall = GCA.SafeCall, GCA.IsSecret, GCA.Plain, GCA.PlainCall

GCA.SPEC_LIST = {
  { "DRUID", "BALANCE", "Balance" }, { "DRUID", "FERAL_CAT", "Feral (Cat)" },
  { "DRUID", "FERAL_BEAR", "Feral (Bear)" }, { "DRUID", "RESTORATION", "Restoration" },
  { "HUNTER", "BEAST_MASTERY", "Beast Mastery" }, { "HUNTER", "MARKSMANSHIP", "Marksmanship" },
  { "HUNTER", "SURVIVAL", "Survival (ranged)" }, { "HUNTER", "SURVIVAL_MELEE", "Survival (melee)" },
  { "MAGE", "ARCANE", "Arcane" }, { "MAGE", "FIRE", "Fire" }, { "MAGE", "FROST", "Frost" },
  { "PALADIN", "HOLY", "Holy" }, { "PALADIN", "PROTECTION", "Protection" }, { "PALADIN", "RETRIBUTION", "Retribution" },
  { "PRIEST", "DISCIPLINE", "Discipline" }, { "PRIEST", "HOLY", "Holy" },
  { "PRIEST", "SHADOW", "Shadow" }, { "PRIEST", "SMITE", "Smite (damage)" },
  { "ROGUE", "ASSASSINATION", "Assassination" }, { "ROGUE", "COMBAT", "Combat" }, { "ROGUE", "SUBTLETY", "Subtlety" },
  { "SHAMAN", "ELEMENTAL", "Elemental" }, { "SHAMAN", "ENHANCEMENT", "Enhancement" },
  { "SHAMAN", "ENHANCEMENT_DW", "Enhancement (dual-wield)" }, { "SHAMAN", "RESTORATION", "Restoration" },
  { "WARLOCK", "AFFLICTION", "Affliction" }, { "WARLOCK", "DEMONOLOGY", "Demonology" }, { "WARLOCK", "DESTRUCTION", "Destruction" },
  { "WARRIOR", "ARMS", "Arms" }, { "WARRIOR", "FURY", "Fury" }, { "WARRIOR", "PROTECTION", "Protection" },
}
GCA.SPEC_INDEX, GCA.SPECS_OF, GCA.SPEC_NAME = {}, {}, {}
for i, e in ipairs(GCA.SPEC_LIST) do
  local class, key, name = e[1], e[2], e[3]
  GCA.SPEC_INDEX[class .. "/" .. key] = i
  GCA.SPECS_OF[class] = GCA.SPECS_OF[class] or {}
  table.insert(GCA.SPECS_OF[class], key)
  GCA.SPEC_NAME[class .. "/" .. key] = name
end

function GCA:SpecName(class, spec)
  if not spec then return "?" end
  local name = self.SPEC_NAME[(class or "") .. "/" .. spec]
  if not name then return spec end
  return (ns.LGet and ns.LGet("SPEC:" .. name)) or name
end
function GCA:ValidSpec(class, spec) return spec ~= nil and self.SPEC_INDEX[(class or "") .. "/" .. spec] ~= nil end

GCA.TREES = {
  DRUID = { "BALANCE", "FERAL", "RESTORATION" }, HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" },
  MAGE = { "ARCANE", "FIRE", "FROST" }, PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
  PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" }, ROGUE = { "ASSASSINATION", "COMBAT", "SUBTLETY" },
  SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" }, WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
  WARRIOR = { "ARMS", "FURY", "PROTECTION" },
}

GCA.SPEC_TREE = { FERAL_CAT = "FERAL", FERAL_BEAR = "FERAL", ENHANCEMENT_DW = "ENHANCEMENT", SMITE = "DISCIPLINE", SURVIVAL_MELEE = "SURVIVAL" }
function GCA:TreeOfSpec(spec) return spec and (self.SPEC_TREE[spec] or spec) end

GCA.GEAR_RULES = {
  ["DRUID/FERAL_CAT"] = { INVTYPE_HOLDABLE = true }, ["DRUID/FERAL_BEAR"] = { INVTYPE_HOLDABLE = true },
  ["PALADIN/PROTECTION"] = { INVTYPE_2HWEAPON = true, INVTYPE_HOLDABLE = true },
  ["WARRIOR/PROTECTION"] = { INVTYPE_2HWEAPON = true, INVTYPE_HOLDABLE = true },
}

local TREE_X = { 1020, 5020, 9080 }
local X_SLACK = 100
local CANVAS_MAX_X = 11000

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

function GCA:OffHandIsWeapon(items)
  local link = items and items[17]
  if not link then return false end
  local instant = self.ItemAPI.Instant
  local _, _, _, equipLoc = SafeCall(instant, link)
  local rule = ns.Scoring.EQUIP_LOCS[equipLoc or ""]
  return rule ~= nil and rule.oneHand == true
end

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

local function TraitsAPIMissing()
  return not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo)
end

local function NumberOr0(v) return type(v) == "number" and v or 0 end

local function ReadNode(configID, nodeID)
  local info = PlainCall("table", C_Traits.GetNodeInfo, configID, Plain(nodeID))
  if not info then return nil end
  local x = Plain(info.posX)
  if type(x) ~= "number" then return nil end
  return { posX = x, rp = NumberOr0(Plain(info.ranksPurchased)), ar = NumberOr0(Plain(info.activeRank)) }
end

local function ReadTreeNodes(configID, treeID, raw)
  treeID = Plain(treeID)
  local nodeIDs = treeID and SafeCall(C_Traits.GetTreeNodes, treeID)
  if type(nodeIDs) ~= "table" then return end
  for _, nodeID in ipairs(nodeIDs) do
    local node = ReadNode(configID, nodeID)
    if node then raw[#raw + 1] = node end
  end
end

local function SummarizeNodes(configID, treeID, raw)
  local r = { configID = configID, treeID = treeID, nodes = {}, purchased = 0, active = 0, nodeCount = #raw }
  for _, n in ipairs(raw) do r.purchased = r.purchased + n.rp; r.active = r.active + n.ar end
  local byPurchase = r.purchased > 0
  r.used = byPurchase and "ranksPurchased" or "activeRank"
  for _, n in ipairs(raw) do
    r.nodes[#r.nodes + 1] = { posX = n.posX, ranks = byPurchase and n.rp or n.ar }
  end
  return r
end

function GCA:ReadTraitConfig(configID, allTrees)
  if TraitsAPIMissing() then return nil, "no C_Traits" end
  if type(configID) ~= "number" then return nil, "no config ID" end
  local config = PlainCall("table", C_Traits.GetConfigInfo, configID)
  if not config then return nil, "no config info" end
  local treeIDs = Plain(config.treeIDs)
  if type(treeIDs) ~= "table" or not Plain(treeIDs[1]) then return nil, "config has no tree" end
  local raw = {}
  for _, treeID in ipairs(allTrees and treeIDs or { treeIDs[1] }) do ReadTreeNodes(configID, treeID, raw) end
  return SummarizeNodes(configID, Plain(treeIDs[1]), raw)
end

function GCA:ReadOwnTalents()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return nil, "no C_ClassTalents" end
  local id = SafeCall(C_ClassTalents.GetActiveConfigID)
  if IsSecret(id) then return nil, "secret" end
  return self:ReadTraitConfig(id, false)
end

function GCA:CatFormKnown()
  for _, fn in ipairs({ IsPlayerSpell or false, C_SpellBook and C_SpellBook.IsSpellKnown or false }) do
    local v = PlainCall("boolean", fn, 768)
    if v ~= nil then return v end
  end
  return nil
end

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
      local cat
      if class == "DRUID" then cat = self:CatFormKnown() end
      o.spec, o.assumed = self:ResolveTree(tree, class, items, cat)
    end
  end
  local old = self.ownSpec
  self.ownSpec = o
  local changed = not old or old.spec ~= o.spec
  if changed then
    self:InvalidateScores()
    if self.CheckOwnSpec then self:CheckOwnSpec() end
  end
  return changed
end

local function NodeSig(nodes)
  local parts = {}
  for _, n in ipairs(nodes or {}) do
    if (n.ranks or 0) > 0 then parts[#parts + 1] = n.posX .. ":" .. n.ranks end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function PointsProblem(read, level)
  if read.total == 0 then return "no points" end
  local maxPoints = (type(level) == "number" and level >= 10) and (level - 9) or 51
  if read.total > maxPoints then return "more points than the level allows" end
  if read.unplaced > 0 then return "ranks outside the three trees" end
end

local function OwnTalentsProblem(self, class, read)
  local own = self:ReadOwnTalents()
  if not own then return nil end
  if class ~= self.playerClass and own.treeID == read.treeID then return "same tree as yours (another class)" end
  if class == self.playerClass and NodeSig(own.nodes) == NodeSig(read.nodes) then return "identical to your own talents" end
end

function GCA:ReadInspectTalents(class, level)
  local id = Constants and Constants.TraitConsts and Plain(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
  local read, why = self:ReadTraitConfig(id, true)
  if not read then return nil, why or "no data", { configID = id } end
  local points, unplaced = self:PointsFromNodes(read.nodes, class)
  read.points, read.unplaced, read.total = points, unplaced, 0
  for _, n in pairs(points) do read.total = read.total + n end
  local problem = PointsProblem(read, level) or OwnTalentsProblem(self, class, read)
  if problem then return nil, problem, read end
  local tree, reason = self:InferTree(points, class)
  if not tree then return nil, reason, read end
  return tree, "ok", read
end

function GCA:InspectTalentsOn() return self.db and self.db.settings.inspectTalents == true end

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
      if self:InspectTalentsOn() then
        self:StoreSpec(key, class, { tree = tree, src = "inspect", ts = self:Now() })
      end
    end
  end
  try()
  C_Timer.After(0.3, function() try() end)
  C_Timer.After(1, function() try() end)
end

local SYNCED_SOURCES = { sync = true, self = true }

local function KeepsCurrentSpec(self, cur, rec, class)
  if not (cur and cur.class == class) then return false end
  if cur.src == "inspect" and not self:InspectTalentsOn() then return false end
  local sameTree = (cur.tree or self:TreeOfSpec(cur.spec)) == (rec.tree or self:TreeOfSpec(rec.spec))
  local curSync, recSync = SYNCED_SOURCES[cur.src] == true, SYNCED_SOURCES[rec.src] == true
  if sameTree and curSync and rec.src == "inspect" then return true end
  local inspectGivesWayToSync = sameTree and cur.src == "inspect" and recSync
  return not inspectGivesWayToSync and (cur.ts or 0) > (rec.ts or 0)
end

function GCA:StoreSpec(key, class, rec)
  if not (key and class and self.db) then return false end
  local cur = self.db.specs[key]
  if KeepsCurrentSpec(self, cur, rec, class) then return false end
  rec.class = class
  local same = cur and cur.class == class and cur.spec == rec.spec and cur.tree == rec.tree
  self.db.specs[key] = rec
  if not same then self:Invalidate() end
  return not same
end

function GCA:SetManualSpec(key, class, spec)
  if not key then return end
  if spec and not self:ValidSpec(class, spec) then return end
  self.db.specManual[key] = spec and { class = class, spec = spec } or nil
  if key == self.playerKey and self.CheckOwnSpec then self:CheckOwnSpec() end
  self:InvalidateScores()
end

local function OwnTalentSpec(self, class)
  local o = self.ownSpec
  if o and o.spec and self:ValidSpec(class, o.spec) then return o.spec, "talents", o.assumed end
  return nil, o and o.reason or "talents not read yet"
end

local STORED_SPEC_HOW = { sync = "synced", self = "own" }
local function StoredSpec(self, rec, class, items)
  if STORED_SPEC_HOW[rec.src] and self:ValidSpec(class, rec.spec) then return rec.spec, STORED_SPEC_HOW[rec.src] end
  if rec.src == "inspect" and rec.tree and self:InspectTalentsOn() then
    local spec, assumed = self:ResolveTree(rec.tree, class, items, nil)
    if self:ValidSpec(class, spec) then return spec, "inspected", assumed end
  end
  return nil, "unknown"
end

function GCA:MemberSpec(key, class, items)
  if not class then return nil, "class unknown" end
  local man = self.db.specManual[key]
  if man and man.class == class and self:ValidSpec(class, man.spec) then return man.spec, "manual" end
  if key == self.playerKey then return OwnTalentSpec(self, class) end
  local rec = self.db.specs[key]
  if not (rec and rec.class == class) then return nil, "unknown" end
  return StoredSpec(self, rec, class, items)
end

function GCA:StoreOwnSpec(spec, ts)
  if not (spec and self.playerKey and self.playerClass and self.db and self.db.specs) then return false end
  return self:StoreSpec(self.playerKey, self.playerClass, { spec = spec, src = "self", ts = ts or self:Now() })
end

function GCA:OwnAnnouncedSpec()
  local class = self.playerClass
  local spec = self:MemberSpec(self.playerKey, class, self.playerKey and self.db.members[self.playerKey] and self.db.members[self.playerKey].items)
  return spec and self.SPEC_INDEX[class .. "/" .. spec], spec
end

local function fmtPoints(points, class)
  local parts = {}
  for _, t in ipairs(GCA.TREES[class or ""] or {}) do parts[#parts + 1] = t .. " " .. (points and points[t] or 0) end
  return table.concat(parts, " / ")
end

function GCA:SpecDebug(P)
  P = P or function(line) self:Print(line) end
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
    P("  inspected talents are " .. (self:InspectTalentsOn() and "used when plausible" or "ignored (off by default)") .. " (option 'spec from inspected talents').")
  else
    P("No inspect read yet: inspect a guild member, then " .. "open this box again.")
  end
end
