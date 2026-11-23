local Json = {}

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function Str(s)
  return '"' .. s:gsub('[%c"\\]', function(ch) return ESC[ch] or string.format("\\u%04x", ch:byte()) end) .. '"'
end

local function IsArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local function Encode(v, seen)
  local kind = type(v)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return tostring(v) end
  if kind == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    return string.format("%.2f", v):gsub("%.?0+$", "")
  end
  if kind == "string" then return Str(v) end
  if kind ~= "table" then return Str(tostring(v)) end
  if seen[v] then return "null" end
  seen[v] = true
  local out = {}
  if IsArray(v) then
    for i = 1, #v do out[i] = Encode(v[i], seen) end
    seen[v] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local val = v[k]
    local t = type(val)
    if t ~= "function" and t ~= "userdata" and t ~= "thread" then out[#out + 1] = Str(k) .. ":" .. Encode(val, seen) end
  end
  seen[v] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

function Json.encode(v) return Encode(v, {}) end

return Json
