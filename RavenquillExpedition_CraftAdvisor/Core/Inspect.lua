local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local IsSecret, SafeCall, Plain, PlainCall = GCA.IsSecret, GCA.SafeCall, GCA.Plain, GCA.PlainCall
local function Print(...) GCA:Print(...) end

function GCA:ReadUnitItems(unit, into)
  local got = 0
  for slot = 1, 19 do
    local link = PlainCall("string", GetInventoryItemLink, unit, slot)
    if link then
      into[slot] = link
      got = got + 1
    end
  end
  return got
end

function GCA:Now() return RQ:Now() end

GCA.SYNC_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
GCA.IS_SYNC_SLOT = {}
for _, s in ipairs(GCA.SYNC_SLOTS) do GCA.IS_SYNC_SLOT[s] = true end

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

function GCA:ParseLink(link)
  if type(link) ~= "string" then return end
  local s = link:match("item:([^|%[%]]+)")
  if not s or not s:match("^%d") then return end
  return SplitColon(s)
end

function GCA:NormItem(link)
  local f = self:ParseLink(link)
  if not f then return end
  if f[9] then f[9] = "" end
  if f[10] then f[10] = "" end
  local n = #f
  while n > 1 and f[n] == "" do f[n] = nil; n = n - 1 end
  return table.concat(f, ":")
end

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

function GCA:IsPartialRead(old, fresh)
  if not old then return false end
  if CountSync(self, fresh) >= CountSync(self, old) then return false end
  for _, slot in ipairs(self.SYNC_SLOTS) do
    local f = self:NormItem(fresh[slot])
    if f and f ~= self:NormItem(old[slot]) then return false end
  end
  return true
end

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
    if m.items then
      for slot, link in pairs(items) do
        if self:NormItem(link) == self:NormItem(m.items[slot]) then m.items[slot] = link end
      end
    end
    if not m.ts then m.ts = self:Now() end
    if not m.source then m.source = source end
  end
  self.db.members[key] = m
  self:ClearWornCrafted(key, m.items)
  return changed
end

local function UnitClassLevel(unit)
  local _, class = SafeCall(UnitClass, unit)
  return Plain(class), PlainCall("number", UnitLevel, unit)
end

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
  local token = PlainCall(nil, UnitTokenFromGUID, guid)
  if token then return token end
  local inspected = Plain(InspectFrame and InspectFrame.unit)
  if inspected and PlainCall(nil, UnitGUID, inspected) == guid then return inspected end
  for _, u in ipairs(UNIT_TOKENS) do
    if PlainCall(nil, UnitGUID, u) == guid then return u end
  end
end

GCA.inspectGen = 0
function GCA:OnNotifyInspect(unit)
  self.inspectGen = self.inspectGen + 1
  self.inspectGUID = unit and PlainCall(nil, UnitGUID, unit) or nil
end
if hooksecurefunc then pcall(hooksecurefunc, "NotifyInspect", function(unit) GCA:OnNotifyInspect(unit) end) end

function GCA:OnInspectReady(guid)
  self.inspectGen = self.inspectGen + 1
  self.inspectGUID = Plain(guid) or nil
  local gen = self.inspectGen
  if self.inspecting and self.inspecting == guid then self.inspectAnswered = guid end
  local unit = self:UnitFromGUID(guid)
  if unit and SafeCall(UnitIsPlayer, unit) and not SafeCall(UnitIsUnit, unit, "player")
     and (not self.db.settings.guildOnly or self:IsGuildmate(unit)) then
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
      self:InspectDone(guid)
    end)
    return
  end
  self:InspectDone(guid)
end

GCA.queue, GCA.lastInspect = {}, {}
GCA.INSPECT_FINAL_READ, GCA.INSPECT_NO_ANSWER, GCA.INSPECT_HARD_LIMIT, GCA.INSPECT_GAP = 1.5, 3, 8, 1
GCA.inspectToken = 0

function GCA:QueueInspect(unit, force)
  local guid = PlainCall(nil, UnitGUID, unit)
  if not guid then return false end
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
      C_Timer.After(self.INSPECT_NO_ANSWER, function()
        if self.inspectToken == token and self.inspecting == guid and self.inspectAnswered ~= guid then
          self.inspecting = nil
          self:ProcessQueue()
        end
      end)
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

GCA.AUTO_FRESH, GCA.AUTO_RETRY, GCA.AUTO_GROUP_DELAY, GCA.AUTO_MOUSEOVER_GAP = 1800, 600, 2, 10

local function AutoInspectOff(self)
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) then return "off" end
  if InCombatLockdown() then return "combat" end
  if InspectFrame and SafeCall(InspectFrame.IsShown, InspectFrame) then return "inspectframe" end
end

local function OutOfInspectRange(unit)
  if type(CheckInteractDistance) ~= "function" then return false end
  local ok, near = pcall(CheckInteractDistance, unit, 1)
  return ok and not IsSecret(near) and near == false
end

local function UnitNotInspectable(self, unit)
  if not SafeCall(UnitIsPlayer, unit) or SafeCall(UnitIsUnit, unit, "player") then return "unit" end
  if not self:IsGuildmate(unit) then return "guild" end
  local can = SafeCall(CanInspect, unit)
  if not can or IsSecret(can) then return "caninspect" end
  if OutOfInspectRange(unit) then return "range" end
end

local function InspectPending(self, guid)
  if self.inspecting == guid then return true end
  for _, g in ipairs(self.queue) do
    if g == guid then return true end
  end
  return false
end

local function ReadRecently(self, unit, guid)
  local key = RQ:UnitKey(unit)
  local m = key and self.db.members[key]
  if m and type(m.time) == "number" and time() - m.time < self.AUTO_FRESH then return "fresh" end
  local last = self.lastInspect[guid]
  if last and GetTime() - last < self.AUTO_RETRY then return "recent" end
  if InspectPending(self, guid) then return "queued" end
end

function GCA:AutoInspectCheck(unit)
  local why = AutoInspectOff(self) or UnitNotInspectable(self, unit)
  if why then return false, why end
  local guid = PlainCall(nil, UnitGUID, unit)
  if not guid then return false, "unit" end
  why = ReadRecently(self, unit, guid)
  if why then return false, why end
  return true, guid
end

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
  if self.inspecting or #self.queue > 0 then return false end
  local t = GetTime()
  if self.lastAutoMouseover and t - self.lastAutoMouseover < self.AUTO_MOUSEOVER_GAP then return false end
  if not self:AutoInspectCheck("mouseover") then return false end
  self.lastAutoMouseover = t
  return self:QueueInspect("mouseover", true)
end
