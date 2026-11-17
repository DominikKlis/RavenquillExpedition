local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local IsSecret, SafeCall, PlainCall = GCA.IsSecret, GCA.SafeCall, GCA.PlainCall
local function Print(...) GCA:Print(...) end

function GCA:IsGuildmate(unit)
  if SafeCall(UnitIsUnit, unit, "player") then return true end
  if UnitIsInMyGuild and SafeCall(UnitIsInMyGuild, unit) then return true end
  local key = RQ:UnitKey(unit)
  if key and RQ:RosterEntry(key) then return true end
  local g, mine = SafeCall(GetGuildInfo, unit), SafeCall(GetGuildInfo, "player")
  return g and mine and not IsSecret(g) and g == mine or false
end

function GCA:RosterRead()
  local loaded, n, offline = RQ:RosterComplete()
  if not loaded or type(n) ~= "number" or n <= 0 then return false end
  local live = PlainCall("number", GetNumGuildMembers)
  if live ~= n then return false end
  local read = 0
  for _ in RQ:EachMember() do read = read + 1 end
  return read == n, n, offline
end

GCA.PRUNE_DELAY, GCA.PRUNE_MIN_ROSTER, GCA.PRUNE_AGE = 60, 5, 30 * 86400

function GCA:OwnCharacterKeys()
  local own, realm = {}, PlainCall("string", GetRealmName)
  if self.playerKey then own[self.playerKey] = true end
  local db = self.db
  for _, t in ipairs({ db.known or {}, db.sync or {}, db.profSel or {}, db.crafted or {} }) do
    for charKey in pairs(t) do
      if type(charKey) == "string" then
        own[charKey] = true
        if realm and charKey:sub(-(#realm + 1)) == "-" .. realm then
          own[charKey:sub(1, -(#realm + 2))] = true
        end
        local base = charKey:match("^(.+)%-[^%-]+$")
        if base then own[base] = true end
      end
    end
  end
  return own
end

local function Sightings()
  local lastSeen, keys = {}, {}
  local function note(key, t)
    if type(key) ~= "string" then return end
    keys[key] = true
    if type(t) == "number" and t > (lastSeen[key] or 0) then lastSeen[key] = t end
  end
  return note, lastSeen, keys
end

local function NoteCraftedMarks(note, key, profs)
  note(key, nil)
  if type(profs) ~= "table" then return end
  for _, marks in pairs(profs) do
    if type(marks) == "table" then
      for _, mk in pairs(marks) do note(key, type(mk) == "table" and mk.t) end
    end
  end
end

local function CollectSightings(db)
  local note, lastSeen, keys = Sightings()
  for key, m in pairs(db.members) do note(key, m.time); note(key, m.ts) end
  for key, r in pairs(db.specs or {}) do note(key, type(r) == "table" and r.ts) end
  for _, byMember in pairs(db.crafted or {}) do
    if type(byMember) == "table" then
      for key, profs in pairs(byMember) do NoteCraftedMarks(note, key, profs) end
    end
  end
  return lastSeen, keys
end

local function ForgetMember(db, key)
  db.members[key] = nil
  if db.specs then db.specs[key] = nil end
  for _, byMember in pairs(db.crafted or {}) do
    if type(byMember) == "table" then byMember[key] = nil end
  end
end

local function RemoveStale(self, db)
  local own, cutoff = self:OwnCharacterKeys(), time() - self.PRUNE_AGE
  local lastSeen, keys = CollectSightings(db)
  local removed = 0
  for key in pairs(keys) do
    if not RQ:RosterEntry(key) and not own[key] and lastSeen[key] and lastSeen[key] < cutoff then
      ForgetMember(db, key)
      removed = removed + 1
    end
  end
  return removed
end

local function PruneDue(self)
  if self.pruneDone or not (self.db and IsInGuild()) then return false end
  return self.loginTime and GetTime() - self.loginTime >= self.PRUNE_DELAY
end

local function RosterTrusted(self, n, last, offline)
  return type(last) == "number" and n >= self.PRUNE_MIN_ROSTER and n >= last / 2 and (offline or 0) ~= 0
end

function GCA:PruneStale()
  if not PruneDue(self) then return end
  local complete, n, offline = self:RosterRead()
  if not complete then return end
  local db = self.db
  local last = db.rosterLast
  db.rosterLast = n
  self.pruneDone = true
  if not RosterTrusted(self, n, last, offline) then return end
  local removed = RemoveStale(self, db)
  if removed > 0 then
    self.sugCache = {}
    Print(string.format(L.MSG_PRUNED, removed))
    self:Invalidate()
  end
  return removed
end
