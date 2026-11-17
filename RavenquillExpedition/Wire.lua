local ADDON, ns = ...
local GS = ns.GS
local W = {}
GS.Wire = W

W.MAX_MSG = 250
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function digits(n)
  local s = ""
  repeat
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  until n == 0
  return s
end

function W.b36(n)
  n = tonumber(n) or 0
  if n ~= n or n < 0 or n >= 2 ^ 53 then n = 0 end
  n = math.floor(n)
  return digits(n)
end

function W.b36s(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return "-" .. digits(-n) end
  return digits(n)
end

function W.n36(s, loose)
  if type(s) ~= "string" or s == "" or #s > 8 then return nil end
  if not s:match(loose and "^%w+$" or "^[0-9a-z]+$") then return nil end
  return tonumber(s, 36)
end

function W.Split(s, sep)
  sep = sep or ";"
  local out, pos = {}, 1
  while true do
    local i = s:find(sep, pos, true)
    if not i then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, i - 1)
    pos = i + #sep
  end
end

function W.Clean(s, n)
  s = GS.Plain(s, "string")
  if not s then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[;|%c]", "")
  return GS.Cut(s, n or W.MAX_MSG)
end

W.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
  "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
W.CLASS_IDX = {}
for i, c in ipairs(W.CLASSES) do W.CLASS_IDX[c] = i end
