local ADDON, ns = ...

local GS = {}
_G.RavenquillExpedition = GS
GS.API = 2

local function IsSecret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if canaccessvalue and v ~= nil and not canaccessvalue(v) then return true end
  return false
end
GS.IsSecret = IsSecret

function GS.Plain(v, typ)
  if v == nil or IsSecret(v) then return nil end
  if typ and type(v) ~= typ then return nil end
  return v
end

function GS.Bool(v)
  if IsSecret(v) then return false end
  return v and true or false
end

local function pack(...) return { n = select("#", ...), ... } end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end
GS.SafeCall = SafeCall

function GS:AddOnVersion(addon)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return GS.Plain(SafeCall(get, addon, "Version"), "string") or "dev"
end
GS.version = GS:AddOnVersion(ADDON)

function GS:Trace(cat, msg, data) end

function GS:Call(fn, ...)
  if type(fn) ~= "function" then return end
  local args = pack(...)
  local r = pack(xpcall(function() return fn(unpack(args, 1, args.n)) end, function(err)
    local msg = tostring(err)
    GS:Trace("err", msg, debugstack and debugstack(2, 8, 4))
    if RavenquillExpeditionDB then RavenquillExpeditionDB.lastError = { t = time(), msg = msg, trace = debugstack and debugstack(2, 8, 4) } end
    local h = geterrorhandler and geterrorhandler()
    if h then pcall(h, msg) end
    return msg
  end))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end

function GS.Print(tag, ...)
  local head = "|cff33ff99Ravenquill Expedition|r"
  if tag then head = head .. " |cffbbbbbb" .. tag .. "|r" end
  print(head .. ":", ...)
end

local build = select(4, GetBuildInfo()) or 0
GS.IS_FOREVER = build >= 16000 and build < 20000

function GS:Now()
  local t = GS.Plain(SafeCall(GetServerTime), "number")
  return t or time()
end

function GS:InInstance()
  local inside = SafeCall(IsInInstance)
  return (GS.Plain(inside) and true) or false
end

function GS:MaxLevel()
  return math.max(60, GS.Plain(SafeCall(GetMaxPlayerLevel), "number") or 60)
end

function GS.FormatToPattern(fmt)
  fmt = GS.Plain(fmt, "string")
  if not fmt then return end
  local f = fmt:gsub("%%(%d+)%$([sd])", "%%%2")
  local out, i = {}, 1
  while i <= #f do
    local c = f:sub(i, i)
    if c == "%" then
      local n = f:sub(i + 1, i + 1)
      if n == "s" then out[#out + 1] = "(.+)"
      elseif n == "d" then out[#out + 1] = "(%d+)"
      elseif n == "%" then out[#out + 1] = "%%"
      else return end
      i = i + 2
    else
      out[#out + 1] = c:find("[%(%)%.%[%]%*%+%-%?%^%$]") and ("%" .. c) or c
      i = i + 1
    end
  end
  local p = "^" .. table.concat(out) .. "$"
  if not pcall(string.match, "", p) then return end
  return p
end

function GS.Cut(s, n)
  if type(s) ~= "string" then return "" end
  if #s <= n then return s end
  s = s:sub(1, n)
  local i = #s
  while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
  if i > 0 and s:byte(i) >= 0xC0 then
    local need = s:byte(i) >= 0xF0 and 4 or s:byte(i) >= 0xE0 and 3 or 2
    if #s - i + 1 < need then s = s:sub(1, i - 1) end
  end
  return s
end

ns.GS = GS
