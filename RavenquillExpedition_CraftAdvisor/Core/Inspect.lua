local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local priv = GCA.priv
local Print, IsSecret, SafeCall = priv.Print, priv.IsSecret, priv.SafeCall

---------------------------------------------------------------------------
-- Gear capture
---------------------------------------------------------------------------
function GCA:ReadUnitItems(unit, into)
  local got = 0
  for slot = 1, 19 do
    local link = SafeCall(GetInventoryItemLink, unit, slot)
    if type(link) == "string" and not IsSecret(link) then
      into[slot] = link
      got = got + 1
    end
  end
  return got
end

function GCA:Now() return RQ:Now() end

-- The 17 slots that are compared and synced (no shirt 4, no tabard 19).
GCA.SYNC_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
GCA.IS_SYNC_SLOT = {}
for _, s in ipairs(GCA.SYNC_SLOTS) do GCA.IS_SYNC_SLOT[s] = true end

-- Split on ":" keeping empty fields (string.gmatch with empty matches differs between Lua 5.1 and 5.4).
local function SplitColon(s)
  local out, pos = {}, 1
  while true do
    local i = s:find(":", pos, true)
    if not i then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, i - 1)
    pos = i + 1
  end
end
GCA.SplitColon = SplitColon

-- Fields of the item string after "item:" (works for full hyperlinks and bare "item:..." strings).
function GCA:ParseLink(link)
  if type(link) ~= "string" then return end
  local s = link:match("item:([^|%[%]]+)")
  if not s or not s:match("^%d") then return end
  return SplitColon(s)
end

-- Item string with the VIEWER's fields blanked (9 = link level, 10 = spec; they hold the level of
-- whoever looked, not the wearer: plan rev 4 B1b) and trailing empty fields trimmed.
function GCA:NormItem(link)
  local f = self:ParseLink(link)
  if not f then return end
  if f[9] then f[9] = "" end
  if f[10] then f[10] = "" end
  local n = #f
  while n > 1 and f[n] == "" do f[n] = nil; n = n - 1 end
  return table.concat(f, ":")
end

-- Fingerprint of a gear set over the 17 synced slots.
function GCA:GearSignature(items)
  local parts = {}
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local n = items and self:NormItem(items[slot])
    if n then parts[#parts + 1] = slot .. "=" .. n end
  end
  return table.concat(parts, ",")
end

local function CountSync(self, items)
  local n = 0
  for _, slot in ipairs(self.SYNC_SLOTS) do if items and self:NormItem(items[slot]) then n = n + 1 end end
  return n
end

-- True when `fresh` read fewer slots than `old` and every slot it did read is identical:
-- an incomplete read, not a gear change.
function GCA:IsPartialRead(old, fresh)
  if not old then return false end
  if CountSync(self, fresh) >= CountSync(self, old) then return false end
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local f = self:NormItem(fresh[slot])
    if f and f ~= self:NormItem(old[slot]) then return false end
  end
  return true
end

-- Stores a gear record for `key`. Returns changed (true only for a real gear change).
-- Unchanged gear only refreshes time/level/class; ts, source and from stay.
function GCA:StoreRecord(key, class, level, items, source)
  if not key then return false end
  local m = self.db.members[key]
  local isNew = m == nil
  m = m or {}
  if class then m.class = class end
  if type(level) == "number" and level > 0 then m.level = level end
  m.time = time()
  local changed = isNew or not m.items or self:GearSignature(m.items) ~= self:GearSignature(items)
  if changed and source == "inspect" and self:IsPartialRead(m.items, items) then changed = false end
  if changed then
    m.items = items
    m.ts = self:Now()
    m.source = source
    m.from = nil
  else
    -- same gear: keep the record, but take fresh real hyperlinks for slots we read
    if m.items then
      for slot, link in pairs(items) do
        if self:NormItem(link) == self:NormItem(m.items[slot]) then m.items[slot] = link end
      end
    end
    if not m.ts then m.ts = self:Now() end
    if not m.source then m.source = source end
  end
  self.db.members[key] = m
  self:ClearWornCrafted(key, m.items) -- a "crafted" mark ends once a record shows it worn
  return changed
end

local function UnitClassLevel(unit)
  local _, class = SafeCall(UnitClass, unit)
  local level = SafeCall(UnitLevel, unit)
  if IsSecret(class) then class = nil end
  if IsSecret(level) or type(level) ~= "number" then level = nil end
  return class, level
end

-- Returns key, changed
function GCA:StoreMember(unit, items, source)
  local key = RQ:UnitKey(unit)
  if not key then return end
  local class, level = UnitClassLevel(unit)
  return key, self:StoreRecord(key, class, level, items, source)
end

function GCA:CaptureSelf()
  if not self.db then return end
  local items = {}
  self:ReadUnitItems("player", items)
  local key, changed = self:StoreMember("player", items, "self")
  self.playerKey = key
  if changed and self.OnOwnGearChanged then self:OnOwnGearChanged() end
  if changed and self.ownSpec and self.playerClass == "SHAMAN" then self:QueueOwnSpecRefresh() end
  self:Invalidate()
end

local UNIT_TOKENS = { "target", "mouseover", "focus", "party1", "party2", "party3", "party4" }
for i = 1, 40 do UNIT_TOKENS[#UNIT_TOKENS + 1] = "raid" .. i end

function GCA:UnitFromGUID(guid)
  if not guid or IsSecret(guid) then return end
  if UnitTokenFromGUID then
    local u = SafeCall(UnitTokenFromGUID, guid)
    if u and not IsSecret(u) then return u end
  end
  if InspectFrame and InspectFrame.unit and not IsSecret(InspectFrame.unit) then
    local ig = SafeCall(UnitGUID, InspectFrame.unit)
    if ig and not IsSecret(ig) and ig == guid then return InspectFrame.unit end
  end
  for _, u in ipairs(UNIT_TOKENS) do
    local g = SafeCall(UnitGUID, u)
    if g and not IsSecret(g) and g == guid then return u end
  end
end

-- INSPECT_READY fires both for our own requests and when you inspect someone
-- with the normal UI. Item links can arrive in pieces, so read a few times.
-- Inspect generation: bumped on every INSPECT_READY and every NotifyInspect (ours or the default UI's), so
-- delayed talent reads of an older inspect can tell that the client's inspect data may be someone else's now.
GCA.inspectGen = 0
function GCA:OnNotifyInspect(unit)
  self.inspectGen = self.inspectGen + 1
  local g = unit and SafeCall(UnitGUID, unit)
  self.inspectGUID = (g and not IsSecret(g)) and g or nil
end
if hooksecurefunc then pcall(hooksecurefunc, "NotifyInspect", function(unit) GCA:OnNotifyInspect(unit) end) end

function GCA:OnInspectReady(guid)
  self.inspectGen = self.inspectGen + 1
  self.inspectGUID = (guid and not IsSecret(guid)) and guid or nil
  local gen = self.inspectGen
  -- our queued inspect got its answer; the queue now waits for the final read below (InspectDone)
  if self.inspecting and self.inspecting == guid then self.inspectAnswered = guid end
  local unit = self:UnitFromGUID(guid)
  if unit and SafeCall(UnitIsPlayer, unit) and not SafeCall(UnitIsUnit, unit, "player")
     and (not self.db.settings.guildOnly or self:IsGuildmate(unit)) then
    -- Who it is is fixed on the first pass; later passes only add items. Only the final pass
    -- stores, and it stores what was collected even if the unit token is gone by then.
    local fresh = {}
    local key = RQ:UnitKey(unit)
    local class, level = UnitClassLevel(unit)
    if not key then self:InspectDone(guid) return end
    if self.TryInspectTalents then RQ:Call(self.TryInspectTalents, self, key, class, level, guid, gen) end
    local function read()
      local u = self:UnitFromGUID(guid)
      if u then self:ReadUnitItems(u, fresh) end
    end
    read()
    C_Timer.After(0.5, read)
    C_Timer.After(GCA.INSPECT_FINAL_READ, function()
      -- under RQ:Call: an error here reaches BugSack, and the queue still moves on below
      RQ:Call(function()
        read()
        if not next(fresh) then return end
        local changed = self:StoreRecord(key, class, level, fresh, "inspect")
        if changed and self.RelayInspect then self:RelayInspect(key) end
        if self.verbose or self.announce == guid then
          self.announce = nil
          Print(string.format(L.MSG_RECORDED, key))
          if self.UI then self.UI.selected = key end
        end
        self:Invalidate()
      end)
      -- only now may the next NotifyInspect go out (it would replace this unit's inspect data)
      self:InspectDone(guid)
    end)
    return
  end
  self:InspectDone(guid)
end

---------------------------------------------------------------------------
-- Inspect queue (for "Inspect target", "Scan group" and auto-inspect)
---------------------------------------------------------------------------
GCA.queue, GCA.lastInspect = {}, {}
-- timings: final storing read after INSPECT_READY; no answer within NO_ANSWER s -> next; HARD_LIMIT s
-- after NotifyInspect the queue moves on whatever happened (a lost timer or an error can't hang it).
GCA.INSPECT_FINAL_READ, GCA.INSPECT_NO_ANSWER, GCA.INSPECT_HARD_LIMIT, GCA.INSPECT_GAP = 1.5, 3, 8, 1
GCA.inspectToken = 0

function GCA:QueueInspect(unit, force)
  local guid = SafeCall(UnitGUID, unit)
  if not guid or IsSecret(guid) then return false end
  if not force and self.lastInspect[guid] and GetTime() - self.lastInspect[guid] < 120 then return false end
  for _, g in ipairs(self.queue) do if g == guid then return true end end
  self.queue[#self.queue + 1] = guid
  self:ProcessQueue()
  return true
end

function GCA:ProcessQueue()
  if self.inspecting then return end
  if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then
    if #self.queue > 0 then C_Timer.After(3, function() self:ProcessQueue() end) end
    return
  end
  while #self.queue > 0 do
    local guid = table.remove(self.queue, 1)
    local unit = self:UnitFromGUID(guid)
    if unit and SafeCall(CanInspect, unit) then
      self.inspecting = guid
      self.inspectAnswered = nil
      self.inspectToken = self.inspectToken + 1
      local token = self.inspectToken
      self.lastInspect[guid] = GetTime()
      SafeCall(NotifyInspect, unit)
      -- no answer (out of range?): move on; an answered inspect waits for its final read instead
      C_Timer.After(self.INSPECT_NO_ANSWER, function()
        if self.inspectToken == token and self.inspecting == guid and self.inspectAnswered ~= guid then
          self.inspecting = nil
          self:ProcessQueue()
        end
      end)
      -- safety net: never stuck on one inspect
      C_Timer.After(self.INSPECT_HARD_LIMIT, function()
        if self.inspectToken == token and self.inspecting == guid then
          self.inspecting = nil
          self:ProcessQueue()
        end
      end)
      return
    end
  end
end

function GCA:InspectDone(guid)
  if self.inspecting and self.inspecting == guid then
    self.inspecting = nil
    self.inspectAnswered = nil
    C_Timer.After(self.INSPECT_GAP, function() self:ProcessQueue() end)
  end
end

function GCA:InspectTarget()
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then
    Print(L.MSG_TARGET_FIRST) return
  end
  if self.db.settings.guildOnly and not self:IsGuildmate("target") then
    Print(L.MSG_NOT_GUILD) return
  end
  if not SafeCall(CanInspect, "target") then Print(L.MSG_CANT_INSPECT) return end
  self.announce = SafeCall(UnitGUID, "target")
  self:QueueInspect("target", true)
  Print(string.format(L.MSG_INSPECTING, RQ:UnitKey("target") or "target"))
end

function GCA:ScanGroup()
  local n = 0
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  for i = 1, count do
    local u = prefix .. i
    if SafeCall(UnitIsPlayer, u) and not SafeCall(UnitIsUnit, u, "player") and self:IsGuildmate(u)
       and SafeCall(CanInspect, u) and self:QueueInspect(u, true) then
      n = n + 1
    end
  end
  Print(n > 0 and string.format(L.MSG_QUEUED, n) or L.MSG_NONE_IN_GROUP)
end

---------------------------------------------------------------------------
-- K5: automatic gear reading (replaces the "Inspect target" / "Scan group" buttons; the slash commands stay).
-- Group members (GROUP_ROSTER_UPDATE, debounced) and guildies under the mouse (UPDATE_MOUSEOVER_UNIT, low
-- priority: only while the queue is idle, at most one per AUTO_MOUSEOVER_GAP s) go through the same inspect
-- queue (one at a time). Rules for every automatic read (AutoInspectCheck):
--   setting "autoInspect" on; not in combat (a group scan asked for in combat runs at PLAYER_REGEN_ENABLED);
--   the default inspect window is not open (never take the user's inspect data away); a player, not you, a
--   guildmate; CanInspect true; not out of range (CheckInteractDistance(unit, 1), pcall'd as Overlord
--   RankProof.lua:1442-1444 does on Forever: only a plain `false` counts, an error / secret / nil doesn't);
--   no gear record younger than AUTO_FRESH s (db.members[key].time = when we last stored or received it);
--   not tried within AUTO_RETRY s (lastInspect, also set for attempts that got no answer); not queued already.
---------------------------------------------------------------------------
GCA.AUTO_FRESH, GCA.AUTO_RETRY, GCA.AUTO_GROUP_DELAY, GCA.AUTO_MOUSEOVER_GAP = 1800, 600, 2, 10

function GCA:AutoInspectCheck(unit)
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return false, "off" end
  if InCombatLockdown() then return false, "combat" end
  if InspectFrame and SafeCall(InspectFrame.IsShown, InspectFrame) then return false, "inspectframe" end
  if not SafeCall(UnitIsPlayer, unit) or SafeCall(UnitIsUnit, unit, "player") then return false, "unit" end
  if not self:IsGuildmate(unit) then return false, "guild" end
  local can = SafeCall(CanInspect, unit)
  if not can or IsSecret(can) then return false, "caninspect" end
  if type(CheckInteractDistance) == "function" then
    local ok, near = pcall(CheckInteractDistance, unit, 1)
    if ok and not IsSecret(near) and near == false then return false, "range" end
  end
  local guid = SafeCall(UnitGUID, unit)
  if not guid or IsSecret(guid) then return false, "unit" end
  local key = RQ:UnitKey(unit)
  local m = key and self.db.members[key]
  if m and type(m.time) == "number" and time() - m.time < self.AUTO_FRESH then return false, "fresh" end
  local last = self.lastInspect[guid]
  if last and GetTime() - last < self.AUTO_RETRY then return false, "recent" end
  if self.inspecting == guid then return false, "queued" end
  for _, g in ipairs(self.queue) do if g == guid then return false, "queued" end end
  return true, guid
end

-- Party/raid members that pass the rules go into the queue. In combat: remembered and run after combat.
function GCA:AutoScanGroup()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return 0 end
  if InCombatLockdown() then self.autoGroupPending = true; return 0 end
  self.autoGroupPending = nil
  local prefix, count = "party", SafeCall(GetNumSubgroupMembers) or 0
  if SafeCall(IsInRaid) then prefix, count = "raid", SafeCall(GetNumGroupMembers) or 0 end
  if IsSecret(count) or type(count) ~= "number" then return 0 end
  local n = 0
  for i = 1, count do
    local u = prefix .. i
    if self:AutoInspectCheck(u) and self:QueueInspect(u, true) then n = n + 1 end
  end
  if n > 0 and self.verbose then Print(string.format(L.MSG_AUTO_QUEUED, n)) end
  return n
end

function GCA:AutoMouseover()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return false end
  if self.inspecting or #self.queue > 0 then return false end -- low priority: only while idle
  local t = GetTime()
  if self.lastAutoMouseover and t - self.lastAutoMouseover < self.AUTO_MOUSEOVER_GAP then return false end
  if not self:AutoInspectCheck("mouseover") then return false end
  self.lastAutoMouseover = t
  return self:QueueInspect("mouseover", true)
end
