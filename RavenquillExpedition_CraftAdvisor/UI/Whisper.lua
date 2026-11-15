local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local LGet, SlotName, FirstName = P.LGet, P.SlotName, P.FirstName

---------------------------------------------------------------------------
-- Offer whisper (localized, editable template with placeholders)
---------------------------------------------------------------------------
local function CrafterNoun(prof)
  local v = LGet and LGet("CRAFTER_" .. tostring(prof):upper())
  if v then return v end
  local p = GCA.PROF_BY_KEY[prof] or GCA.PROF_BY_KEY.Leatherworking
  return p.crafter
end

function UI.DefaultTemplate(kind)
  return kind == "enchant" and L.WHISPER_ENCHANT or L.WHISPER_CRAFT
end

-- The saved template (db.settings.whisperCraft / whisperEnchant), else the default of the client language.
function UI.Template(kind)
  local s = GCA.db and GCA.db.settings
  local t = s and (kind == "enchant" and s.whisperEnchant or s.whisperCraft)
  if type(t) == "string" and t:find("%S") then return t end
  return UI.DefaultTemplate(kind)
end

-- {name} {item} {slot} {crafter}; unknown placeholders stay as typed. Values are inserted literally
-- (a function replacement, so "%" in an item link can't break gsub).
function UI.FillTemplate(t, vals)
  if vals.name == nil or vals.name == "" then t = t:gsub("%s*{name}", "") end
  return (t:gsub("{(%a+)}", function(k)
    local v = vals[k:lower()]
    if v ~= nil then return tostring(v) end
  end))
end

-- Cut s to at most max bytes without splitting a UTF-8 character or leaving a dangling "|" escape.
UI.WHISPER_MAX = 255 -- bytes per chat message
function UI.Utf8Cut(s, max)
  if #s <= max then return s end
  local cut = s:sub(1, max)
  local j = #cut
  while j > 0 do
    local c = cut:byte(j)
    if c < 0x80 or c >= 0xC0 then break end -- not a continuation byte
    j = j - 1
  end
  if j > 0 then
    local c = cut:byte(j)
    local len = (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
    if j + len - 1 > #cut then cut = cut:sub(1, j - 1) end
  end
  return (cut:gsub("|+$", ""))
end

-- who = the member key ("First Surname"); the whisper uses the first name.
-- Review L-2: a whisper over 255 bytes uses the item name instead of the link; still too long -> cut on a
-- character boundary and say so once per session.
function UI.OfferText(prof, d, who)
  local kind = d.kind == "enchant" and "enchant" or "craft"
  local item
  if kind == "enchant" then item = d.info.name or d.enchant.name else item = d.info.link or d.info.name end
  local vals = { item = item, slot = SlotName(d.slot), name = FirstName(who), crafter = CrafterNoun(prof) }
  local msg = UI.FillTemplate(UI.Template(kind), vals)
  if #msg > UI.WHISPER_MAX and d.info.name and item ~= d.info.name then
    vals.item = d.info.name
    msg = UI.FillTemplate(UI.Template(kind), vals)
  end
  if #msg > UI.WHISPER_MAX then
    msg = UI.Utf8Cut(msg, UI.WHISPER_MAX)
    if not UI.warnedLong then
      UI.warnedLong = true
      GCA:Print(L.WHISPER_TOO_LONG)
    end
  end
  return msg
end

-- Offer only for a craft/enchant you know, in your own profession, for someone else who is online now:
-- a whisper doesn't reach an offline player (enchants needed this already).
function UI.CanOffer(cur, d)
  if not (cur and d) or cur.isSelf or cur.browse or not d.known then return false end
  if not cur.online then return false end
  return true
end

-- "wearable at level 42 (in 3 levels)"
local function WearableText(d)
  local togo = d.levelsToGo or 0
  if togo == 1 then return string.format(L.WEARABLE_AT_1, d.wearAt or 0) end
  return string.format(L.WEARABLE_AT, d.wearAt or 0, togo)
end
UI.WearableText = WearableText
