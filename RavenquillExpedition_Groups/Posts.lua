local ADDON, ns = ...

local P = {}
ns.Posts = P

P.ROLES = {
  { key = "tank", code = "t" },
  { key = "heal", code = "h" },
  { key = "dps", code = "d" },
}
P.ROLE_BY_CODE = {}
for _, r in ipairs(P.ROLES) do P.ROLE_BY_CODE[r.code] = r.key end

P.OPEN_FOR = 3600
P.RAID_RUNS = 3 * 3600
P.PLAN_AHEAD = 8 * 86400

function P.Expires(p)
  if p.when then return p.when + P.RAID_RUNS end
  return p.t + P.OPEN_FOR
end

function P.New(f)
  local a = ns.Activities.Get(f.activity)
  local p = { id = f.id, t = f.t, poster = f.poster, activity = f.activity, kind = a.raid and "raid" or "dungeon",
    when = f.when, note = (f.note ~= "" and f.note) or nil, roles = {}, signups = {} }
  for _, r in ipairs(P.ROLES) do
    local src = f.roles[r.key]
    p.roles[r.key] = { need = src.need, have = src.have }
  end
  p.expires = P.Expires(p)
  return p
end

function P.Filled(p)
  local have, need = 0, 0
  for _, r in pairs(p.roles) do have, need = have + r.have, need + r.need end
  return have, need
end

function P.HasRoom(p, role)
  local r = p.roles[role]
  return r ~= nil and r.have < r.need
end

function P.OpenRoles(p)
  local out = {}
  for _, r in ipairs(P.ROLES) do if P.HasRoom(p, r.key) then out[#out + 1] = r.key end end
  return out
end

function P.SignupOf(p, who)
  for _, s in ipairs(p.signups) do if s.who == who then return s end end
end

function P.AddSignup(p, who, role)
  if P.SignupOf(p, who) or not P.HasRoom(p, role) then return false end
  p.signups[#p.signups + 1] = { who = who, role = role }
  p.roles[role].have = p.roles[role].have + 1
  return true
end

local function RaiseCounts(old, new)
  local grew = false
  for key, r in pairs(new.roles) do
    local o = old.roles[key]
    if r.have > o.have then o.have, grew = r.have, true end
  end
  return grew and "grew" or "same"
end

function P.Merge(old, new)
  if not old or new.id > old.id then return new, "new" end
  if new.id < old.id or new.t < old.t then return old, "stale" end
  if new.t > old.t then
    new.signups = old.signups
    return new, "updated"
  end
  return old, RaiseCounts(old, new)
end

local function Order(p, me)
  if p.poster == me then return 0, 0 end
  if p.kind == "raid" then return 2, p.when or p.t end
  return 1, -p.t
end

function P.Sorted(store, now, me)
  local list = {}
  for _, p in pairs(store) do if p.expires > now then list[#list + 1] = p end end
  table.sort(list, function(a, b)
    local ra, ka = Order(a, me)
    local rb, kb = Order(b, me)
    if ra ~= rb then return ra < rb end
    if ka ~= kb then return ka < kb end
    return a.poster < b.poster
  end)
  return list
end
