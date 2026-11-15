local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local priv = GCA.priv
local Print, IsSecret, SafeCall = priv.Print, priv.IsSecret, priv.SafeCall

---------------------------------------------------------------------------
-- Names / guild: keys come from the core (RQ:UnitKey / RQ:NormName: "First Surname", our own realm dropped), the
-- roster too (RQ:RosterEntry / RQ:EachMember / RQ:RosterComplete).
---------------------------------------------------------------------------
function GCA:IsGuildmate(unit)
  if SafeCall(UnitIsUnit, unit, "player") then return true end
  if UnitIsInMyGuild and SafeCall(UnitIsInMyGuild, unit) then return true end
  local key = RQ:UnitKey(unit)
  if key and RQ:RosterEntry(key) then return true end
  local g, mine = SafeCall(GetGuildInfo, unit), SafeCall(GetGuildInfo, "player")
  return g and mine and not IsSecret(g) and g == mine or false
end

-- The roster as a complete read: true, members, offline only when every roster index gave a name in the core's
-- last read and the client still reports that many members (an empty read keeps the core's old roster).
function GCA:RosterRead()
  local loaded, n, offline = RQ:RosterComplete()
  if not loaded or type(n) ~= "number" or n <= 0 then return false end
  local live = RQ.Plain(SafeCall(GetNumGuildMembers), "number")
  if live ~= n then return false end
  local read = 0
  for _ in RQ:EachMember() do read = read + 1 end
  return read == n, n, offline
end

---------------------------------------------------------------------------
-- prune SavedVariables of characters that left the guild. Conservative: once per session, at least
-- PRUNE_DELAY s after login, only on a complete roster read (every index gave a name) of at least
-- PRUNE_MIN_ROSTER members, with offline members in it (not an online-only list), not on the first session
-- that records a roster size and not less than half of last session's count; never your own characters
-- (every character key this account has stored); only data older than PRUNE_AGE (newest of m.time, m.ts,
-- spec ts, crafted marks). Touches db.members, db.specs and the crafted marks of every own character.
---------------------------------------------------------------------------
GCA.PRUNE_DELAY, GCA.PRUNE_MIN_ROSTER, GCA.PRUNE_AGE = 60, 5, 30 * 86400

function GCA:OwnCharacterKeys()
  local own, realm = {}, SafeCall(GetRealmName)
  if self.playerKey then own[self.playerKey] = true end
  local db = self.db
  for _, t in ipairs({ db.known or {}, db.sync or {}, db.profSel or {}, db.crafted or {} }) do
    for charKey in pairs(t) do
      if type(charKey) == "string" then
        own[charKey] = true
        if type(realm) == "string" and not IsSecret(realm) and charKey:sub(-(#realm + 1)) == "-" .. realm then
          own[charKey:sub(1, -(#realm + 2))] = true
        end
        local base = charKey:match("^(.+)%-[^%-]+$")
        if base then own[base] = true end
      end
    end
  end
  return own
end

function GCA:PruneStale()
  if self.pruneDone or not (self.db and IsInGuild()) then return end
  if not (self.loginTime and GetTime() - self.loginTime >= self.PRUNE_DELAY) then return end
  local complete, n, offline = self:RosterRead()
  if not complete then return end
  local db = self.db
  local last = db.rosterLast
  db.rosterLast = n
  if type(last) ~= "number" or n < self.PRUNE_MIN_ROSTER or n < last / 2 or (offline or 0) == 0 then
    self.pruneDone = true -- suspicious: not this session
    return
  end
  self.pruneDone = true
  local own, cutoff = self:OwnCharacterKeys(), time() - self.PRUNE_AGE
  local seen, cand = {}, {}
  local function note(key, t)
    if type(key) ~= "string" then return end
    cand[key] = true
    if type(t) == "number" and t > (seen[key] or 0) then seen[key] = t end
  end
  for key, m in pairs(db.members) do note(key, m.time); note(key, m.ts) end
  for key, r in pairs(db.specs or {}) do note(key, type(r) == "table" and r.ts) end
  for _, byMember in pairs(db.crafted or {}) do
    if type(byMember) == "table" then
      for key, profs in pairs(byMember) do
        note(key, nil)
        if type(profs) == "table" then
          for _, marks in pairs(profs) do
            if type(marks) == "table" then for _, mk in pairs(marks) do note(key, type(mk) == "table" and mk.t) end end
          end
        end
      end
    end
  end
  local removed = 0
  for key in pairs(cand) do
    -- no timestamp at all = unknown age: kept
    if not RQ:RosterEntry(key) and not own[key] and seen[key] and seen[key] < cutoff then
      db.members[key] = nil
      if db.specs then db.specs[key] = nil end
      for _, byMember in pairs(db.crafted or {}) do if type(byMember) == "table" then byMember[key] = nil end end
      removed = removed + 1
    end
  end
  if removed > 0 then
    self.sugCache = {}
    Print(string.format(L.MSG_PRUNED, removed))
    self:Invalidate()
  end
  return removed
end
