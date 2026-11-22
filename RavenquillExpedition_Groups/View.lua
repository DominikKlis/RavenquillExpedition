local ADDON, ns = ...
local GS = RavenquillExpedition
local G, L, A, P = ns.G, ns.L, ns.Activities, ns.Posts

local V = {}
ns.View = V

V.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

function V.RoleName(role) return L["ROLE_" .. role] end

function V.Title(p) return A.Title(A.Get(p.activity)) end

function V.DayStart(t)
  local d = date("*t", t)
  return t - (d.hour * 3600 + d.min * 60 + d.sec)
end

function V.DaysAhead(t, now) return math.floor((V.DayStart(t) - V.DayStart(now)) / 86400 + 0.5) end

function V.DayName(t, now)
  local days = V.DaysAhead(t, now)
  return (days == 0 and L.TODAY) or (days == 1 and L.TOMORROW) or L["WEEKDAY_" .. date("*t", t).wday]
end

function V.WhenText(when, now) return L.WHEN:format(V.DayName(when, now), date("%H:%M", when)) end

function V.AgeText(t, now)
  local secs = math.max(0, now - t)
  if secs < 60 then return L.AGO_NOW end
  if secs < 3600 then return L.AGO_MIN:format(math.floor(secs / 60)) end
  return L.AGO_HOURS:format(math.floor(secs / 3600))
end

function V.NeedText(p)
  local names = {}
  for _, role in ipairs(P.OpenRoles(p)) do names[#names + 1] = V.RoleName(role) end
  return table.concat(names, ", ")
end

function V.AnnounceLine(p)
  if p.when then return L.ANNOUNCE_RAID:format(p.poster, V.Title(p), V.WhenText(p.when, GS:Now())) end
  return L.ANNOUNCE:format(p.poster, V.Title(p), V.NeedText(p))
end

function V.WhisperText(p, role)
  if p.when then return L.WHISPER_WHEN:format(V.Title(p), V.WhenText(p.when, GS:Now()), V.RoleName(role)) end
  return L.WHISPER:format(V.Title(p), V.RoleName(role))
end

function V.RolePill(role, r)
  local name = V.RoleName(role)
  if r.have >= r.need then return { text = name .. " " .. V.CHECK, style = "full" } end
  if r.have == 0 then return { text = L.ROLE_WANTED:format(name), style = "wanted" } end
  return { text = L.ROLE_COUNT:format(name, r.have, r.need), style = "part" }
end

function V.Pills(p)
  local out = {}
  for _, r in ipairs(P.ROLES) do
    local role = p.roles[r.key]
    if role.need > 0 then out[#out + 1] = V.RolePill(r.key, role) end
  end
  return out
end

local function ClassHex(class)
  local c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[class or ""]
  if not c then return "ffffffff" end
  return ("ff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function Add(list, v) if v then list[#list + 1] = v end end

local function Details(p, e, now)
  local parts = {}
  Add(parts, e.level and tostring(e.level))
  if p.when then
    Add(parts, V.WhenText(p.when, now))
  else
    Add(parts, A.Range(A.Get(p.activity)))
    Add(parts, e.zone)
    Add(parts, V.AgeText(p.t, now))
  end
  Add(parts, p.note)
  return table.concat(parts, " · ")
end

function V.Line(p, now)
  local e = GS:RosterEntry(p.poster) or {}
  return ("|c%s%s|r  |cffc8c8c8%s|r"):format(ClassHex(e.class), p.poster, Details(p, e, now))
end

function V.Action(p, me, mine)
  if p.poster == me then return nil end
  local raid = p.kind == "raid"
  if mine then return { label = raid and L.COMMITTED or L.SIGNED_UP, enabled = false } end
  if not P.OpenRoles(p)[1] then return { label = L.FULL, enabled = false } end
  return { label = raid and L.COMMIT or L.SIGN_UP, enabled = true }
end

function V.Signups(p)
  local out = {}
  for i, s in ipairs(p.signups) do out[i] = { who = s.who, text = L.SIGNUP_ROW:format(s.who, V.RoleName(s.role)) } end
  return out
end

function V.Card(p)
  local me, now = GS:PlayerKey(), GS:Now()
  local have, need = P.Filled(p)
  local own = p.poster == me
  return { post = p, title = V.Title(p), total = have .. "/" .. need, line = V.Line(p, now), pills = V.Pills(p),
    fits = not own and G:Fits(p), own = own, action = V.Action(p, me, G:MySignup(p)),
    signups = own and V.Signups(p) or nil }
end

local function OwnHeadline(own)
  local n = #own.signups
  if n == 1 then return L.HEAD_SIGNUP:format(own.signups[1].who, V.RoleName(own.signups[1].role)) end
  if n > 1 then return L.HEAD_SIGNUPS:format(n) end
end

local function Short(p) return A.ShortName(A.Get(p.activity)) end

local function PostHeadline(p)
  if p.when then return L.HEAD_RAID:format(p.poster, Short(p), V.WhenText(p.when, GS:Now())) end
  return L.HEAD_POST:format(p.poster, Short(p)) .. (G:Fits(p) and L.HEAD_FITS or "")
end

local function FirstFitting(list)
  for _, p in ipairs(list) do if G:Fits(p) then return p end end
end

function V.Headline()
  local own = G:OwnPost()
  local line = own and OwnHeadline(own)
  if line then return line end
  local others = G:OthersPosts()
  local pick = FirstFitting(others) or others[1]
  if pick then return PostHeadline(pick) end
  if own then return L.HEAD_OWN:format(Short(own)) end
  return L.HEAD_NONE
end

function V.Status(open, online)
  if open == 0 then return L.STATUS_NONE:format(online) end
  if open == 1 then return L.STATUS_ONE:format(online) end
  return L.STATUS:format(open, online)
end
