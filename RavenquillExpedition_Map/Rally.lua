local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local GS = RavenquillExpedition
local SafeCall, Plain = GS.SafeCall, GS.Plain
local W = GS.Wire
local b36, n36 = W.b36, W.n36
local C = M.C

local NEXT = {
  none = { call = "active" },
  active = { call = "active", join = "active", cancel = "cancelled", expire = "expired" },
  cancelled = { call = "active", expire = "expired" },
}

local function Size(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

local function NewRally(ev)
  return { state = "active", key = ev.key, caller = GS:StripRealm(ev.key) or ev.key, id = ev.id, mapID = ev.mapID,
    x = ev.x, y = ev.y, label = ev.label, expires = ev.id + C.RALLY_TIME, base = ev.n, since = {} }
end

local GUARD = {
  call = function(r, ev) return not r or ev.id > r.id or (ev.id == r.id and r.state == "active") end,
  join = function(r, ev) return ev.id == r.id end,
  cancel = function(r, ev) return ev.id == r.id end,
  expire = function(r, ev) return ev.now >= r.expires end,
}

local APPLY = {
  call = function(r, ev)
    if r and r.id == ev.id then r.base, r.since = ev.n, {}; return r end
    return NewRally(ev)
  end,
  join = function(r, ev) r.since[ev.who] = true; return r end,
  cancel = function(r) r.state = "cancelled"; return r end,
  expire = function() return nil end,
}

function M.StepRally(r, ev)
  local to = NEXT[r and r.state or "none"][ev.kind]
  if not to or not GUARD[ev.kind](r, ev) then return r, false end
  return APPLY[ev.kind](r, ev), true
end

function M.RallyCount(r) return r.base + Size(r.since) end

local function Me() return GS:PlayerKey() end

function M:RallyEvent(key, ev)
  if not key then return false end
  local r, changed = M.StepRally(self.rallies[key], ev)
  if not changed then return false end
  self.rallies[key] = r
  self:RallyChanged()
  return true
end

local function XY(v) return b36(v * M.XY_MAX + 0.5) end

function M.EncodeRally(r)
  return table.concat({ "R", b36(r.id), b36(r.mapID), XY(r.x), XY(r.y), b36(M.RallyCount(r)), r.label }, ";")
end
function M.EncodeJoin(key, id) return "J;" .. key .. ";" .. b36(id) end
function M.EncodeCancel(id) return "X;" .. b36(id) end

local function RallyProblem(id, n, now)
  if id > now + C.FUTURE_SLACK then return "future rally" end
  if id + C.RALLY_TIME <= now then return "expired rally" end
  if n > 1000 then return "rally count" end
end

function M.DecodeRally(f, now)
  if #f ~= 7 then return nil, "field count" end
  local id, mapID, xi, yi, n = n36(f[2]), n36(f[3]), n36(f[4]), n36(f[5]), n36(f[6])
  if not (id and mapID and xi and yi and n) then return nil, "not a number" end
  local problem = M.PlaceProblem(mapID, xi, yi) or RallyProblem(id, n, now)
  if problem then return nil, problem end
  return { kind = "call", id = id, mapID = mapID, x = xi / M.XY_MAX, y = yi / M.XY_MAX, n = n,
    label = W.Clean(f[7], C.RALLY_LABEL) }
end

local function OnCall(self, key, f)
  local ev, why = M.DecodeRally(f, GS:Now())
  if not ev then return M.Reject(why) end
  ev.key = key
  self:RallyEvent(key, ev)
end

local function CallerKey(name)
  if GS:IsMe(name) then return Me() end
  return GS:NormName(name)
end

local function OnJoin(self, key, f)
  local id = n36(f[3] or "")
  if #f ~= 3 or not id then return M.Reject("bad join") end
  self:RallyEvent(CallerKey(f[2]), { kind = "join", id = id, who = key })
end

local function OnCancel(self, key, f)
  local id = n36(f[2] or "")
  if #f ~= 2 or not id then return M.Reject("bad cancel") end
  self:RallyEvent(key, { kind = "cancel", id = id })
end

M.handlers.R, M.handlers.J, M.handlers.X = OnCall, OnJoin, OnCancel

local function FreshKeys(self)
  local out = {}
  for key, m in pairs(self.members) do
    if not m.fake and not m.isSelf and self:State(m) == "fresh" then out[key] = true end
  end
  return out
end

local function SubZone()
  return W.Clean(Plain(SafeCall(_G.GetSubZoneText), "string"), C.RALLY_LABEL)
end

function M:RallyWait()
  return math.max(0, (self.rallyCalledAt or -math.huge) + C.RALLY_GAP - GS:Now())
end

function M:OwnRally()
  local r = self.rallies[Me() or ""]
  if r and r.state == "active" then return r end
end

function M:CallRally()
  local wait = self:RallyWait()
  if wait > 0 then return self:Print(L.RALLY_WAIT:format(wait)) end
  local mapID, x, y = self:ReadOwnPosition()
  if not mapID then return self:Print(L.RALLY_NOPOS) end
  local ev = { kind = "call", key = Me(), id = GS:Now(), mapID = mapID, x = x, y = y, n = 0, label = SubZone() }
  if not self.raw:Send(M.EncodeRally(NewRally(ev))) then return self:Print(L.RALLY_FAILED) end
  self.rallyCalledAt = ev.id
  self:RallyEvent(ev.key, ev)
  local own = self:OwnRally()
  if own then own.reached, own.sentAt = FreshKeys(self), ev.id end
end

function M:JoinRally(key)
  local r = self.rallies[key]
  if not r or r.state ~= "active" or r.joined or key == Me() then return end
  if not self.raw:Send(M.EncodeJoin(r.key, r.id)) then return self:Print(L.RALLY_FAILED) end
  r.joined = true
  self:RallyEvent(key, { kind = "join", id = r.id, who = Me() })
end

function M:CancelRally()
  local r = self:OwnRally()
  if not r then return end
  if not self.raw:Send(M.EncodeCancel(r.id)) then return self:Print(L.RALLY_FAILED) end
  self:RallyEvent(r.key, { kind = "cancel", id = r.id })
end

function M:RallyHeardFrom(key)
  local r = self:OwnRally()
  if not (r and r.reached) or r.reached[key] then return end
  r.reached[key] = true
  r.resendAt = r.resendAt or math.max(GS:Now() + C.RALLY_RESEND_DELAY, (r.sentAt or 0) + C.RALLY_RESEND_GAP)
  self:Wake()
end

local function Resend(self, r, now)
  if not (r.resendAt and now >= r.resendAt) then return end
  if not self.raw:Send(M.EncodeRally(r)) then return end
  r.resendAt, r.sentAt = nil, now
  for key in pairs(FreshKeys(self)) do r.reached[key] = true end
end

function M:RallyTick()
  local now = GS:Now()
  for key in pairs(self.rallies) do self:RallyEvent(key, { kind = "expire", now = now }) end
  local own = self:OwnRally()
  if own then Resend(self, own, now) end
end

function M:ShownRallies()
  local out, me, ignore = {}, Me(), self.settings and self.settings.ignoreRally == true
  for key, r in pairs(self.rallies) do
    if r.state == "active" and (key == me or not ignore) then out[#out + 1] = r end
  end
  table.sort(out, function(a, b)
    if a.id ~= b.id then return a.id > b.id end
    return a.key < b.key
  end)
  return out
end

local SAVED = { key = "string", caller = "string", id = "number", mapID = "number", x = "number", y = "number",
  label = "string", expires = "number", base = "number", since = "table" }
local SAVED_OPTIONAL = { reached = "table", sentAt = "number", resendAt = "number", joined = "boolean", dismissed = "boolean" }

local function Typed(r, spec, optional)
  for field, typ in pairs(spec) do
    local v = r[field]
    if not (optional and v == nil) and type(v) ~= typ then return false end
  end
  return true
end

local function Intact(key, r, now)
  if type(r) ~= "table" or r.key ~= key or not NEXT[r.state] or r.state == "none" then return false end
  return Typed(r, SAVED) and Typed(r, SAVED_OPTIONAL, true) and now < r.expires
end

local function Pruned(saved, now)
  local out = {}
  for key, r in pairs(type(saved) == "table" and saved or {}) do
    if Intact(key, r, now) then out[key] = r end
  end
  return next(out) and out or nil
end

local function SaveRallies(self)
  local me = Me()
  if not (self.db and me) then return end
  local all = type(self.db.rallies) == "table" and self.db.rallies or {}
  all[me] = next(self.rallies) and self.rallies or nil
  self.db.rallies = next(all) and all or nil
end

function M:LoadRallies()
  local now, all = GS:Now(), {}
  for char, saved in pairs(type(self.db.rallies) == "table" and self.db.rallies or {}) do all[char] = Pruned(saved, now) end
  self.db.rallies = all
  self.rallies = all[Me() or ""] or {}
  self:RallyChanged()
end

function M:ForgetRallies()
  wipe(self.rallies)
  self:RallyChanged()
end

function M:RefreshRally()
  self:RefreshFlags()
  self:RefreshRallyNotice()
end

function M:RallyChanged()
  if not self.settings then return end
  SaveRallies(self)
  self:RefreshRally()
  self:Wake()
end
