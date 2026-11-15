-- Ravenquill Expedition core: the namespace and the basic helpers every other file uses.
-- Files (load order in the .toc): Core (this) - Names - Roster - Locale - Module - Wire - Comm - Options - Overview -
-- Launcher.
-- The public API is RavenquillExpedition (RQ / GS in the code), version RQ.API; docs/module-api.md lists it.
-- Modules are separate addons (RavenquillExpedition_<Name>, "## Dependencies: RavenquillExpedition").
local ADDON, ns = ...

local GS = {}
_G.RavenquillExpedition = GS
-- Integer, raised on breaking changes. A module asks for a minimum with NewModule(name, { api = n }).
GS.API = 2

---------------------------------------------------------------------------
-- Secrets, plain values, calls
---------------------------------------------------------------------------
-- A secret / protected value: even comparing it can raise on Forever, so test before touching.
local function IsSecret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if canaccessvalue and v ~= nil and not canaccessvalue(v) then return true end
  return false
end
GS.IsSecret = IsSecret

-- A plain (non-secret) value of the given Lua type, else nil.
function GS.Plain(v, typ)
  if v == nil or IsSecret(v) then return nil end
  if typ and type(v) ~= typ then return nil end
  return v
end

-- A plain boolean from an API result: secret or non-boolean-ish values count as false.
function GS.Bool(v)
  if IsSecret(v) then return false end
  return v and true or false
end

local function pack(...) return { n = select("#", ...), ... } end

-- Quiet call: returns the results, or nothing when fn is missing or fails. ONLY for probing client APIs that may
-- be missing or raise; our own code goes through GS:Call, so its bugs reach BugSack.
local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then return end
  return unpack(r, 2, r.n)
end
GS.SafeCall = SafeCall

-- An addon's "## Version" from its .toc (stamped by scripts/package.ps1 at release), or "dev".
function GS:AddOnVersion(addon)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return GS.Plain(SafeCall(get, addon, "Version"), "string") or "dev"
end
GS.version = GS:AddOnVersion(ADDON)

-- Developer trace: a no-op here. The RavenquillExpedition_Dev addon (never packaged) replaces it with a logger that
-- writes into its SavedVariables. Always call it as GS:Trace(...) at call time, never cache it in a local.
--   cat: "comm.tx", "comm.rx", "comm.echo", "comm.lost", "err", "event", "ui", "state", ...
function GS:Trace(cat, msg, data) end

-- Loud call: like SafeCall, but our own bugs reach BugSack and RavenquillExpeditionDB.lastError.
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

---------------------------------------------------------------------------
-- Client facts
---------------------------------------------------------------------------
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

-- The highest player level this client knows (never below 60).
function GS:MaxLevel()
  return math.max(60, GS.Plain(SafeCall(GetMaxPlayerLevel), "number") or 60)
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- Client format string -> anchored Lua pattern. Handles deDE positional "%1$s".
-- Captures come back in the order they appear in the string (fine for the loot strings used here).
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

-- Cut a string to at most n bytes without splitting a UTF-8 character (German umlauts).
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
