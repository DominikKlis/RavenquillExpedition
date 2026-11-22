local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain

GS.roster = {}
local rosterAsked, rosterRead, rosterCount, rosterOffline, onlineCount, onlineCountAt

function GS:RequestRoster()
  local now = GetTime()
  if rosterAsked and now - rosterAsked < 15 then return end
  rosterAsked = now
  if C_GuildInfo and C_GuildInfo.GuildRoster then SafeCall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then SafeCall(GuildRoster) end
end

function GS:ReadRoster()
  local n = Plain(SafeCall(GetNumGuildMembers), "number") or 0
  local roster, offline = {}, 0
  for i = 1, n do
    local name, _, rank, level, _, zone, _, _, online, _, classFile = SafeCall(GetGuildRosterInfo, i)
    local key = self:NormName(name)
    if key then
      local on = Plain(online) and true or false
      zone = Plain(zone, "string")
      roster[key] = { level = Plain(level, "number"), class = Plain(classFile, "string"), online = on,
        zone = zone ~= "" and zone or nil, rank = Plain(rank, "number") }
      if not on then offline = offline + 1 end
    end
  end
  if n > 0 then
    self.roster, rosterCount, rosterOffline = roster, n, offline
    onlineCountAt = nil
    ns.NoteOnline(roster)
  end
  rosterRead = GetTime()
end

function ns.ForgetRoster()
  GS.roster, rosterCount, rosterOffline, onlineCountAt = {}, nil, nil, nil
  ns.ForgetPresence()
end

function GS:IsGuildMember(key)
  if not key then return false end
  if self:IsMe(key) then return (SafeCall(IsInGuild)) and true or false end
  if not next(self.roster) then self:RequestRoster(); return nil end
  return self:RosterEntry(key) and true or false
end

function GS:RosterEntry(key)
  if not key then return end
  local e = self.roster[key]
  if e then return e end
  local first = self:StripRealm(key)
  return first and self.roster[first] or nil
end

function GS:RosterReadAt() return rosterRead end

local OFFICER_CHAT_LISTEN = 3

local function RankReadsOfficerChat(rank)
  local get = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
  local flags = get and SafeCall(get, rank + 1)
  return type(flags) == "table" and GS.Bool(flags[OFFICER_CHAT_LISTEN])
end

function GS:IsOfficer(key)
  if not next(self.roster) then return nil end
  local e = self:RosterEntry(key)
  local rank = e and e.rank
  if not rank then return false end
  return rank == 0 or RankReadsOfficerChat(rank)
end

function GS:RosterComplete()
  return next(self.roster) ~= nil, rosterCount or 0, rosterOffline or 0
end

function GS:OnlineCount()
  local now = GetTime()
  if onlineCountAt and now - onlineCountAt < 30 then return onlineCount end
  local n = 0
  for _, e in pairs(self.roster) do if e.online then n = n + 1 end end
  onlineCount, onlineCountAt = n, now
  return n
end

function GS:EachMember() return pairs(self.roster) end

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

GS.PEER_MAX_AGE = 14 * 86400

local function FreshPeer(t, now, window) return type(t) == "number" and now - t <= (window or GS.PEER_MAX_AGE) end

local function GuildTable(self, field)
  local db = self.db
  if not db then return end
  local g = self:GuildKey() or self.guildKey
  if not g then return end
  db[field] = type(db[field]) == "table" and db[field] or {}
  local t = db[field][g]
  if type(t) ~= "table" then t = {}; db[field][g] = t end
  return t
end
ns.GuildTable = GuildTable

function GS:Peers()
  local t = GuildTable(self, "peersByGuild")
  local old = t and self.db.peers
  if type(old) == "table" then
    for k, v in pairs(old) do if type(v) == "number" and (t[k] or 0) < v then t[k] = v end end
    self.db.peers = nil
  end
  return t
end

function GS:PeerVersions() return GuildTable(self, "peerVersions") end

local function Supersedes(seen, version)
  if not seen then return true end
  if not version then return false end
  return not seen.version or GS.NewerVersion(version, seen.version)
end

function GS:NoteNewer(key, version)
  if not GS.IsRelease(self.version) or not Supersedes(self.newer, version) then return end
  local said = self.newer ~= nil
  self.newer = { from = key, version = version }
  if said then return end
  local L = self.OverviewL
  self.Print(nil, version and L.NEWER_VERSION:format(key, version, self.version) or L.NEWER_FORMAT:format(key))
end

function GS:NotePeerVersion(key, version)
  local versions = GS.IsRelease(version) and self:PeerVersions()
  if not versions then return end
  versions[key] = version
  if GS.NewerVersion(version, self.version) then self:NoteNewer(key, version) end
end

function GS:CheckPeerVersions()
  local from, newest
  for key, v in pairs(self:PeerVersions() or {}) do
    if GS.NewerVersion(v, newest or self.version) then from, newest = key, v end
  end
  if from then self:NoteNewer(from, newest) end
end

function GS:OverviewVersionLine()
  local own = GS.IsRelease(self.version) and ("v" .. self.version) or self.version
  local newer, L = self.newer, self.OverviewL
  if not newer then return own end
  return own .. "  ·  " .. (newer.version and L.UPDATE_TO:format(newer.version) or L.UPDATE_ANY)
end

function GS:NotePeer(key)
  if not key then return end
  ns.NoteHeard(key)
  local peers = self:Peers()
  if peers then peers[key] = self:Now() end
end

local function PruneVersions(db)
  if type(db.peerVersions) ~= "table" then return end
  for g, versions in pairs(db.peerVersions) do
    local peers = type(db.peersByGuild) == "table" and db.peersByGuild[g]
    if type(versions) ~= "table" or type(peers) ~= "table" then db.peerVersions[g] = nil
    else
      for key in pairs(versions) do if not peers[key] then versions[key] = nil end end
    end
  end
end

function GS:PrunePeers()
  local db = self.db
  if not db then return end
  local now = self:Now()
  local function prune(peers)
    for key, t in pairs(peers) do
      if not FreshPeer(t, now) then peers[key] = nil end
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
  PruneVersions(db)
end

function GS:IsPeer(key)
  if key and self:IsMe(key) then return true end
  local peers = key and self:Peers()
  return FreshPeer(peers and peers[key], self:Now())
end

function ns.PeerCount(window)
  local n, now = 0, GS:Now()
  for _, t in pairs(GS:Peers() or {}) do
    if FreshPeer(t, now, window) then n = n + 1 end
  end
  return n
end

local function FreshRosterPeers()
  local out, now = {}, GS:Now()
  for key, t in pairs(GS:Peers() or {}) do
    local member = FreshPeer(t, now) and GS.roster[key]
    if member then out[key] = member end
  end
  return out
end

function ns.PeersOnRoster()
  local total, online = 0, 0
  for _, member in pairs(FreshRosterPeers()) do
    total = total + 1
    if member.online then online = online + 1 end
  end
  return total, online
end

function GS:PeerVersionLines()
  local members, versions, out = FreshRosterPeers(), self:PeerVersions() or {}, {}
  for key in pairs(members) do out[#out + 1] = key end
  table.sort(out)
  for i, key in ipairs(out) do
    local line = key .. "  " .. (versions[key] or "?")
    out[i] = members[key].online and line or ("|cff999999" .. line .. "|r")
  end
  return out
end

function GS:ElectionRank(candidates)
  local list, me = {}, self:PlayerKey()
  list[1] = me
  for _, k in ipairs(candidates or {}) do if k ~= me and self:IsPeer(k) then list[#list + 1] = k end end
  table.sort(list)
  for i, k in ipairs(list) do if k == me then return i - 1, #list end end
  return 0, #list
end
