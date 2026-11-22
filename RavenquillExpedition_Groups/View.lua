local ADDON, ns = ...
local GS = RavenquillExpedition
local L, A, P = ns.L, ns.Activities, ns.Posts

local V = {}
ns.View = V

function V.RoleName(role) return L["ROLE_" .. role] end

function V.Title(p) return A.Title(A.Get(p.activity)) end

local function DayStart(t)
  local d = date("*t", t)
  return t - (d.hour * 3600 + d.min * 60 + d.sec)
end

function V.WhenText(when, now)
  local days = math.floor((DayStart(when) - DayStart(now)) / 86400 + 0.5)
  local day = (days == 0 and L.TODAY) or (days == 1 and L.TOMORROW) or L["WEEKDAY_" .. date("*t", when).wday]
  return L.WHEN:format(day, date("%H:%M", when))
end

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
