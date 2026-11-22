local ADDON, ns = ...
local GS = RavenquillExpedition
local SafeCall, Plain = GS.SafeCall, GS.Plain

local G = GS:NewModule("Groups", {
  addon = ADDON, api = 2, slash = "groups", icon = "Interface\\Icons\\INV_Misc_Bandana_01",
  sv = "RavenquillExpeditionGroupsDB", dbVersion = 1, locale = ns.Locales,
  defaults = { announce = true },
})
local L = G.L
G.title = L.TITLE
ns.G, ns.L = G, L

G.ANNOUNCE_WITHIN = 600

local function Me() return GS:PlayerKey() end
local function Store(name) return G:GuildStore(name) end

function G:PlayerLevel() return Plain(SafeCall(UnitLevel, "player"), "number") end

function G:Fits(p) return ns.Activities.Fits(ns.Activities.Get(p.activity), self:PlayerLevel()) end

function G:PosterOnline(key)
  local e = GS:RosterEntry(key)
  return e ~= nil and e.online == true
end

function G:ActivePosts() return ns.Posts.Sorted(Store("posts"), GS:Now(), Me()) end

function G:OwnPost()
  local p = Store("posts")[Me()]
  if p and p.expires > GS:Now() then return p end
end

function G:OthersPosts()
  local out = {}
  for _, p in ipairs(self:ActivePosts()) do if p.poster ~= Me() then out[#out + 1] = p end end
  return out
end

function G:MySignup(p)
  local m = Store("mine")[p.poster]
  if m and m.id == p.id then return m end
end

function G:Refresh() GS:RefreshOverview() end

local function Announce(self, p)
  if p.poster == Me() or not self.settings.announce or not self:Fits(p) then return end
  if GS:Now() - p.t > self.ANNOUNCE_WITHIN then return end
  self:Print(ns.View.AnnounceLine(p))
end

function G:Receive(p)
  local closed = Store("closed")[p.poster]
  if closed and p.id <= closed.id then return "closed" end
  local posts = Store("posts")
  local merged, how = ns.Posts.Merge(posts[p.poster], p)
  posts[p.poster] = merged
  if how == "new" then
    local mine = Store("mine")
    if mine[p.poster] and mine[p.poster].id ~= p.id then mine[p.poster] = nil end
    Announce(self, merged)
  end
  if how ~= "stale" and how ~= "same" then self:Refresh() end
  return how
end

function G:ReceiveSignup(who, poster, id, role, again)
  local p = Store("posts")[poster]
  if not p or p.id ~= id or (again and poster ~= Me()) then return false end
  if not ns.Posts.AddSignup(p, who, role) then return false end
  if poster == Me() then self:Print(L.SIGNUP_NOTE:format(who, ns.View.RoleName(role))) end
  self:Refresh()
  return true
end

local function Tombstone(poster, id, expires)
  local P = ns.Posts
  Store("closed")[poster] = { id = id, expires = expires or (GS:Now() + P.PLAN_AHEAD + P.RAID_RUNS) }
end

function G:ReceiveClose(poster, id)
  local posts = Store("posts")
  local p = posts[poster]
  if p and p.id > id then return end
  Tombstone(poster, id, p and p.expires)
  posts[poster] = nil
  Store("mine")[poster] = nil
  self:Refresh()
end

function G:HeardFrom(key)
  local m, p = Store("mine")[key], Store("posts")[key]
  if not (m and m.undelivered and p and p.id == m.id) then return end
  m.undelivered, m.pending, m.again = nil, true, true
  ns.Sync.Flush()
end

local function NextId(now)
  local own, closed = Store("posts")[Me()], Store("closed")[Me()]
  return math.max(now, own and own.id + 1 or 0, closed and closed.id + 1 or 0)
end

function G:Post(spec)
  local me, now = Me(), GS:Now()
  local posts = Store("posts")
  local old = posts[me]
  local keep = old ~= nil and old.activity == spec.activity
  local id = keep and old.id or NextId(now)
  local p = ns.Posts.New({ id = id, t = keep and math.max(now, old.t + 1) or id, poster = me, activity = spec.activity,
    when = spec.when, note = spec.note, roles = spec.roles })
  if keep then p.signups = old.signups end
  posts[me] = p
  Store("outbox").post = p.t
  ns.Sync.Flush()
  self:Refresh()
  return p
end

function G:Close()
  local me = Me()
  local posts = Store("posts")
  local p = posts[me]
  if not p then return end
  posts[me] = nil
  Tombstone(me, p.id, p.expires)
  local out = Store("outbox")
  out.post, out.close = nil, p.id
  ns.Sync.Flush()
  self:Refresh()
end

function G:Whisper(p, role)
  local text = ns.View.WhisperText(p, role)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send and pcall(send, text, "WHISPER", nil, p.poster) then return end
  SafeCall((ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell, p.poster)
end

function G:SignUp(poster, role)
  local p = Store("posts")[poster]
  if not p or poster == Me() or not ns.Posts.AddSignup(p, Me(), role) then return false end
  Store("mine")[poster] = { id = p.id, role = role, pending = true }
  GS:RequestRoster()
  ns.Sync.Flush()
  self:Refresh()
  return true
end

function G:Invite(who)
  SafeCall((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit, who)
end

local function PruneBy(store, alive)
  for k, v in pairs(store) do
    if not alive(k, v) then store[k] = nil end
  end
end

function G:Prune(now)
  local posts = Store("posts")
  PruneBy(posts, function(_, p) return p.expires > now end)
  PruneBy(Store("closed"), function(_, c) return c.expires > now end)
  PruneBy(Store("mine"), function(poster, m) return posts[poster] ~= nil and posts[poster].id == m.id end)
end

G:SetOptions({
  { type = "toggle", key = "announce", label = L.OPT_ANNOUNCE, tooltip = L.OPT_ANNOUNCE_TIP },
})
