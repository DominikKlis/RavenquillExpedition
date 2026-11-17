local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain

local function SurnameSeparator()
  local c = Constants and Constants.CharacterNameSeparatorConsts
  local sep = Plain(c and c.CHARACTERNAME_SURNAME_SEPARATOR, "string")
  if sep and sep ~= "" then return sep end
  return " "
end
GS.SurnameSeparator = SurnameSeparator

local playerKey, realmSuffixes

function ns.ResetNameCache() playerKey, realmSuffixes = nil, nil end

local function RealmSuffixes()
  if realmSuffixes then return realmSuffixes end
  local out = {}
  for _, r in ipairs({ Plain(SafeCall(GetNormalizedRealmName), "string") or false,
                       Plain(SafeCall(GetRealmName), "string") or false }) do
    if r and r ~= "" then
      out[#out + 1] = "-" .. r
      out[#out + 1] = "-" .. r:gsub("[%s%-]", "")
    end
  end
  if out[1] then realmSuffixes = out end
  return out
end

function GS:StripRealm(key)
  if type(key) ~= "string" or GS.IsSecret(key) then return end
  for _, suffix in ipairs(RealmSuffixes()) do
    if #key > #suffix and key:sub(-#suffix) == suffix then return key:sub(1, -#suffix - 1) end
  end
end

function GS:NormName(n)
  n = Plain(n, "string")
  if not n or n == "" then return end
  if Ambiguate then n = Plain(SafeCall(Ambiguate, n, "none"), "string") or n end
  return self:StripRealm(n) or n
end

function GS:UnitKey(unit)
  local read = UnitNameUnmodified or UnitName
  local name, second = SafeCall(read, unit)
  name, second = Plain(name, "string"), Plain(second, "string")
  if not name or name == "" or name == UNKNOWNOBJECT then return end
  if second and second ~= "" then
    local sep = self.IS_FOREVER and SurnameSeparator() or "-"
    if name:sub(-(#sep + #second)) ~= sep .. second then name = name .. sep .. second end
  end
  return self:NormName(name)
end

function GS:PlayerKey()
  if not playerKey then playerKey = self:UnitKey("player") end
  return playerKey
end

function GS:IsMe(key)
  local me = self:PlayerKey()
  return me ~= nil and key ~= nil and (key == me or self:StripRealm(key) == me)
end

function GS:GuildKey()
  local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
  local realm = Plain(SafeCall(GetNormalizedRealmName), "string")
  if not g or g == "" or not realm or realm == "" then return end
  return g .. "@" .. realm
end
