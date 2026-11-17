local ADDON, ns = ...
local GS = ns.GS
local Plain = GS.Plain
local W = GS.Wire
local MAX_MSG = W.MAX_MSG

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function Listed(list, v)
  for _, e in ipairs(list or {}) do if e == v then return true end end
  return false
end

local function BoundedInt(f, v)
  if not Finite(v) then return nil end
  v = math.floor(v)
  if (f[3] and v < f[3]) or (f[4] and v > f[4]) then return nil end
  return v
end

local function ValidWord(f, s) return s:match("^%w*$") and #s <= (f[3] or 16) end

local FieldEncoders = {
  int = function(f, v) local n = BoundedInt(f, v) return n and ("%d"):format(n) end,
  time = function(_, v)
    if not Finite(v) or v < 1 then return nil end
    return ("%d"):format(math.floor(v))
  end,
  b36 = function(f, v) local n = BoundedInt(f, v) return n and W.b36(n) end,
  text = function(f, v) return W.Clean(v, f[3] or MAX_MSG) end,
  class = function(_, v) local i = W.CLASS_IDX[v] return i and tostring(i) or nil end,
  flag = function(_, v) return v and "1" or "0" end,
  enum = function(f, v) return Listed(f[3], v) and v or nil end,
  key = function(_, v)
    v = Plain(v, "string")
    if not v or v == "" or v:find("[;|%c]") then return nil end
    return v
  end,
  word = function(f, v) v = tostring(v) return ValidWord(f, v) and v or nil end,
}

local function EncodeField(f, v)
  if v == nil then return f.opt and "" or nil end
  local encode = FieldEncoders[f[2]]
  if encode then return encode(f, v) end
end

local function DecodedOrFail(ok, v) if ok then return true, v end return false end

local FieldDecoders = {
  int = function(f, s)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < (f[3] or -math.huge) or n > (f[4] or math.huge) then return false end
    return DecodedOrFail(s:match("^%-?%d+$"), n)
  end,
  time = function(_, s, now)
    local n = tonumber(s)
    return DecodedOrFail(n and s:match("^%d+$") and n >= 1 and n <= now + 300, n)
  end,
  b36 = function(f, s)
    local n = W.n36(s)
    return DecodedOrFail(n and n >= (f[3] or 0) and n <= (f[4] or math.huge), n)
  end,
  text = function(f, s) return true, W.Clean(s, f[3] or MAX_MSG) end,
  class = function(_, s)
    local n = tonumber(s)
    local c = n and W.CLASSES[n]
    return DecodedOrFail(c, c)
  end,
  flag = function(_, s) return DecodedOrFail(s == "0" or s == "1", s == "1") end,
  enum = function(f, s) return DecodedOrFail(Listed(f[3], s), s) end,
  key = function(_, s) return DecodedOrFail(not s:find("[|%c]") and #s <= 64, s) end,
  word = function(f, s) return DecodedOrFail(ValidWord(f, s), s) end,
}

local EMPTY_ALLOWED = { text = true, word = true }

local function DecodeField(f, s, now)
  local kind = f[2]
  if s == "" and f.opt then return true, nil end
  if s == "" and not EMPTY_ALLOWED[kind] then return false end
  local decode = FieldDecoders[kind]
  if not decode then return false end
  return decode(f, s, now)
end

local Channel = {}
Channel.__index = Channel
ns.Channel = Channel

function Channel:Define(typ, def)
  assert(type(typ) == "string" and typ ~= "" and not typ:find("[;|]"), "Define: bad type")
  assert(type(def) == "table" and type(def.fields) == "table", "Define: fields missing")
  assert(def.lane == nil or def.lane == "event", "Define: schema types are always lane event; use NewRawChannel for state")
  self.types[typ] = def
end

function Channel:Encode(typ, msg)
  local def = self.types[typ]
  if not def then return nil, "unknown type" end
  local function build(half)
    local out = { self.tag, tostring(self.version), typ }
    for _, f in ipairs(def.fields) do
      local v = msg[f[1]]
      if half and f[2] == "text" and type(v) == "string" then v = GS.Cut(v, math.floor((f[3] or MAX_MSG) / 2)) end
      local s = EncodeField(f, v)
      if s == nil then return nil, "field " .. f[1] end
      out[#out + 1] = s
    end
    return table.concat(out, ";")
  end
  local text, why = build(false)
  if text and #text > MAX_MSG then text, why = build(true) end
  if not text then return nil, why end
  if #text > MAX_MSG then return nil, "too long" end
  return text
end

function Channel:Decode(sender, body)
  if type(body) ~= "string" then return nil, "no body" end
  local f = W.Split(body)
  if f[1] ~= tostring(self.version) then return nil, "version", f[1] end
  local def = self.types[f[2] or ""]
  if not def then return nil, "unknown type", f[2] end
  local msg, now = {}, GS:Now()
  for i, fd in ipairs(def.fields) do
    local ok, v = DecodeField(fd, f[i + 2] or "", now)
    if not ok then return nil, "field " .. fd[1] end
    msg[fd[1]] = v
    if def.from == "self" and fd[2] == "key" and v ~= nil and GS:NormName(v) ~= sender then return nil, "not the sender" end
  end
  return f[2], msg
end
