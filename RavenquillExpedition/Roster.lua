-- Ravenquill Expedition core: the guild roster and the peers (guildies heard running a suite module).
-- Read the roster through these functions; GS.roster itself is internal (still readable during the rework).
local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain

---------------------------------------------------------------------------
-- Roster cache: roster[key] = { class, level, online }
---------------------------------------------------------------------------
GS.roster = {}

function GS:RequestRoster()
  local now = GetTime()
  if self.rosterAsked and now - self.rosterAsked < 15 then return end
  self.rosterAsked = now
  if C_GuildInfo and C_GuildInfo.GuildRoster then SafeCall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then SafeCall(GuildRoster) end
end

function GS:ReadRoster()
  local n = Plain(SafeCall(GetNumGuildMembers), "number") or 0
  local roster, offline = {}, 0
  for i = 1, n do
    local name, _, _, level, _, _, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      local on = Plain(online) and true or false
      roster[key] = { level = Plain(level, "number"), class = Plain(classFile, "string"), online = on }
      if not on then offline = offline + 1 end
    end
  end
  if n > 0 then
    self.roster, self.rosterCount, self.rosterOffline = roster, n, offline
    self.onlineAt = nil
  end
  self.rosterRead = GetTime()
end

-- true / false, or nil while the roster is still unknown
function GS:IsGuildMember(key)
  if not key then return false end
  if self:IsMe(key) then return (SafeCall(IsInGuild)) and true or false end
  if not next(self.roster) then self:RequestRoster(); return nil end
  return self:RosterEntry(key) and true or false
end

-- { class, level, online } for a key (also "Name-<our realm>" spellings), or nil
function GS:RosterEntry(key)
  if not key then return end
  local e = self.roster[key]
  if e then return e end
  local first = self:StripRealm(key)
  return first and self.roster[first] or nil
end

-- GetTime() of the last roster read, or nil
function GS:RosterReadAt() return self.rosterRead end

-- loaded (a non-empty roster was read), number of members, number offline
function GS:RosterComplete()
  return next(self.roster) ~= nil, self.rosterCount or 0, self.rosterOffline or 0
end

-- Online members in the roster (0 while unknown); cached 30 s because it's read often.
function GS:OnlineCount()
  local now = GetTime()
  if self.onlineAt and now - self.onlineAt < 30 then return self.online end
  local n = 0
  for _, e in pairs(self.roster) do if e.online then n = n + 1 end end
  self.online, self.onlineAt = n, now
  return n
end

-- for key, entry in GS:EachMember() do ... end
function GS:EachMember() return pairs(self.roster) end

-- Keys of the guild members in my party/raid (without me).
function GS:GroupGuildies()
  local out = {}
  local n = Plain(SafeCall(GetNumGroupMembers), "number") or 0
  if n == 0 then return out end
  local raid = Plain(SafeCall(IsInRaid)) and true or false
  local me = self:PlayerKey()
  for i = 1, n do
    local key = self:UnitKey((raid and "raid" or "party") .. i)
    if key and key ~= me and self:IsGuildMember(key) == true then out[#out + 1] = key end
  end
  return out
end

---------------------------------------------------------------------------
-- Peers: guildies heard on the suite's lanes (= they run a Ravenquill Expedition module).
---------------------------------------------------------------------------
-- Saved per guild: RavenquillExpeditionDB.peersByGuild["<guild>@<realm>"][key] = last heard (server time), so
-- another guild's members never count. Versions before the rework kept one account-wide table (db.peers); it moves
-- into the first guild known after the update (the guild is often still unknown right at login).
GS.PEER_MAX_AGE = 14 * 86400

-- the current guild's peer table, or nil while the guild is unknown
function GS:Peers()
  local db = RavenquillExpeditionDB
  if not db then return end
  local g = self:GuildKey() or self.guildKey
  if not g then return end
  db.peersByGuild = type(db.peersByGuild) == "table" and db.peersByGuild or {}
  local t = db.peersByGuild[g]
  if type(t) ~= "table" then t = {}; db.peersByGuild[g] = t end
  if type(db.peers) == "table" then -- the old account-wide table
    for k, v in pairs(db.peers) do if type(v) == "number" and (t[k] or 0) < v then t[k] = v end end
    db.peers = nil
  end
  return t
end

function GS:NotePeer(key)
  local peers = key and self:Peers()
  if peers then peers[key] = self:Now() end
end

-- Forget peers not heard for PEER_MAX_AGE, in every guild (called at login, so the saved tables can't grow forever).
function GS:PrunePeers()
  local db = RavenquillExpeditionDB
  if not db then return end
  local now = self:Now()
  local function prune(peers)
    for key, t in pairs(peers) do
      if type(t) ~= "number" or now - t > self.PEER_MAX_AGE then peers[key] = nil end
    end
  end
  if type(db.peers) == "table" then prune(db.peers) end
  for g, peers in pairs(type(db.peersByGuild) == "table" and db.peersByGuild or {}) do
    if type(peers) ~= "table" then db.peersByGuild[g] = nil
    else
      prune(peers)
      if not next(peers) then db.peersByGuild[g] = nil end
    end
  end
end

function GS:IsPeer(key)
  if key and self:IsMe(key) then return true end
  local peers = key and self:Peers()
  local t = peers and peers[key]
  return t and self:Now() - t <= self.PEER_MAX_AGE or false
end

-- Peers of the current guild heard within the last `window` seconds (default PEER_MAX_AGE).
function GS:PeerCount(window)
  local n, now = 0, self:Now()
  for _, t in pairs(self:Peers() or {}) do
    if type(t) == "number" and now - t <= (window or self.PEER_MAX_AGE) then n = n + 1 end
  end
  return n
end

-- My place (0 = first) among the candidates that run the suite, sorted by name. Everyone in the group
-- computes the same order, so the first one reports and the others only step in when it doesn't.
function GS:ElectionRank(candidates)
  local list, me = {}, self:PlayerKey()
  list[1] = me
  for _, k in ipairs(candidates or {}) do if k ~= me and self:IsPeer(k) then list[#list + 1] = k end end
  table.sort(list)
  for i, k in ipairs(list) do if k == me then return i - 1, #list end end
  return 0, #list
end
