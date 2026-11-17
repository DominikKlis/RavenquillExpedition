local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, G, LGet, C = P.SafeCall, P.G, P.LGet, P.C

local SLOT_INFO = {
  [1] = { "HeadSlot", HEADSLOT or "Head" }, [2] = { "NeckSlot", NECKSLOT or "Neck" },
  [3] = { "ShoulderSlot", SHOULDERSLOT or "Shoulder" }, [5] = { "ChestSlot", CHESTSLOT or "Chest" },
  [6] = { "WaistSlot", WAISTSLOT or "Waist" }, [7] = { "LegsSlot", LEGSSLOT or "Legs" },
  [8] = { "FeetSlot", FEETSLOT or "Feet" }, [9] = { "WristSlot", WRISTSLOT or "Wrist" },
  [10] = { "HandsSlot", HANDSSLOT or "Hands" }, [11] = { "Finger0Slot", FINGER0SLOT or "Finger" },
  [12] = { "Finger1Slot", FINGER1SLOT or "Finger" }, [13] = { "Trinket0Slot", TRINKET0SLOT or "Trinket" },
  [14] = { "Trinket1Slot", TRINKET1SLOT or "Trinket" }, [15] = { "BackSlot", BACKSLOT or "Back" },
  [16] = { "MainHandSlot", MAINHANDSLOT or "Main Hand" }, [17] = { "SecondaryHandSlot", SECONDARYHANDSLOT or "Off Hand" },
  [18] = { "RangedSlot", RANGEDSLOT or "Ranged" },
}
local function SlotName(slot) return SLOT_INFO[slot] and SLOT_INFO[slot][2] or ("Slot " .. slot) end
UI.SlotName = SlotName
local function SlotTexture(slot)
  local token = SLOT_INFO[slot] and SLOT_INFO[slot][1]
  local _, tex = SafeCall(GetInventorySlotInfo, token)
  return tex or "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end

local function ClassColor(class)
  local t = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and t and t[class]
  if c then return c.r, c.g, c.b end
  return 0.8, 0.8, 0.8
end
local function ClassName(class)
  return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class or "?"
end
local function QualityColor(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end
local function Hex(r, g, b)
  local f = math.floor
  return string.format("|cff%02x%02x%02x", f(r * 255 + 0.5), f(g * 255 + 0.5), f(b * 255 + 0.5))
end
local function ColoredItemName(item)
  return Hex(QualityColor(item.quality)) .. (item.name or "?") .. "|r"
end
local function FirstName(key)
  if type(key) ~= "string" then return "" end
  return key:match("^([^%s%-]+)") or key
end

function UI.GainNum(points)
  local v = points or 0
  if math.abs(v) >= 9.95 then return string.format("%+d", v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5)) end
  return string.format("%+.1f", v)
end

function UI.GainUnit(d) return UI.GainNum(d.points) .. " " .. GCA:UnitLabel(d.e) end

local function GainText(d)
  local t = C.upgrade .. UI.GainUnit(d) .. "|r"
  if d.status == "empty-slot" then t = t .. " " .. C.muted .. L.GAIN_EMPTY .. "|r" end
  return t
end
UI.GainText = GainText

local function RowGainText(d)
  local t = UI.GainUnit(d)
  if d.status == "empty-slot" then t = t .. " " .. C.muted .. L.GAIN_EMPTY .. "|r" end
  return t
end
UI.RowGainText = RowGainText

local function PairSlotName(slot)
  if slot == 11 or slot == 12 then return string.format(L.SLOT_RING_N, slot - 10) end
  if slot == 13 or slot == 14 then return string.format(L.SLOT_TRINKET_N, slot - 12) end
end
UI.PairSlotName = PairSlotName
local function ShortSlotName(slot) return PairSlotName(slot) or SlotName(slot) end
UI.ShortSlotName = ShortSlotName

local function TagLine(tags)
  local out, coloured = {}, 0
  for _, t in ipairs(tags) do
    if t[2] and coloured < 2 then
      coloured = coloured + 1
      out[#out + 1] = t[2] .. t[1] .. "|r"
    else
      out[#out + 1] = t[1]
    end
  end
  return table.concat(out, "  ·  ")
end
UI.TagLine = TagLine

local STAT_GLOBAL = { Strength = "SPELL_STAT1_NAME", Agility = "SPELL_STAT2_NAME", Stamina = "SPELL_STAT3_NAME",
  Intellect = "SPELL_STAT4_NAME", Spirit = "SPELL_STAT5_NAME", Armor = "ARMOR", Defense = "DEFENSE" }
local function StatLabel(key)
  local lkey = "STAT_" .. tostring(key):upper()
  if STAT_GLOBAL[key] then return G(STAT_GLOBAL[key], lkey) end
  return (LGet and LGet(lkey)) or key
end

local SPEC_WHY = { ["no-class"] = "SPEC_WHY_CLASS", ["not-read"] = "SPEC_WHY_NOT_READ",
  ["no-talents"] = "SPEC_WHY_NO_TALENTS", ["no points"] = "SPEC_WHY_NO_TALENTS", tie = "SPEC_WHY_TIE" }
local function SpecWhyText(why) return L[SPEC_WHY[why] or "SPEC_WHY_UNREADABLE"] end
UI.SpecWhyText = SpecWhyText

local function SpecHowText(d)
  if not d.spec then
    if d.specHow == "unknown" then return C.warn .. L.SPEC_UNKNOWN_PICK .. "|r" end
    return C.warn .. L.SPEC_UNKNOWN_PICK .. "|r " .. C.dim .. "(" .. SpecWhyText(d.specHow) .. ")|r"
  end
  local how = ({ manual = L.SPEC_HOW_MANUAL, talents = L.SPEC_HOW_TALENTS, synced = L.SPEC_HOW_SYNCED,
    own = L.SPEC_HOW_OWN, inspected = L.SPEC_HOW_INSPECTED })[d.specHow] or d.specHow
  local t = GCA:SpecName(d.class, d.spec) .. " " .. C.dim .. "(" .. tostring(how) .. ")|r"
  if d.specAssumed then t = t .. " " .. C.future .. L.SPEC_ASSUMED .. "|r" end
  return t
end

local function Ago(t)
  if not t then return L.AGO_NEVER end
  local d = time() - t
  if d < 90 then return L.AGO_NOW end
  if d < 5400 then return string.format(L.AGO_MIN, math.floor(d / 60)) end
  if d < 129600 then return string.format(L.AGO_HOURS, math.floor(d / 3600)) end
  return string.format(L.AGO_DAYS, math.floor(d / 86400))
end
UI.Ago = Ago

local function ItemIcon(item)
  local api = GCA.ItemAPI; local _, _, _, _, icon = SafeCall(api.Instant, item)
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ItemName(id)
  local byID = GCA.ItemAPI.NameByID; local n = byID and SafeCall(byID, id)
  if n and not GCA.IsSecret(n) then return n end
  local info = GCA:GetInfo(id)
  return info and info.name or string.format(L.ITEM_FALLBACK, id)
end

function UI.Coins(c)
  if type(GetMoneyString) == "function" then
    local ok, s = pcall(GetMoneyString, c, true)
    if ok and type(s) == "string" then return s end
  end
  return UI.Src.Money(c) or "0"
end

local function Backdrop(f, bgAlpha)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0.06, 0.06, 0.08, bgAlpha or 0.95)
  f:SetBackdropBorderColor(0.45, 0.4, 0.3, 1)
end

local function SourceText(m)
  if not m then return "" end
  if m.from then return string.format(L.SRC_VIA, m.from) end
  if m.source == "self" then return L.SRC_SELF end
  if m.source == "inspect" then return L.SRC_INSPECT end
  if m.source == "relay" then return L.SRC_RELAY end
  return m.source or ""
end

local function ProfName(prof)
  local own = GCA:OwnProfessions()
  if own[prof] and own[prof].name then return own[prof].name end
  return (LGet and LGet("PROF_" .. tostring(prof):upper())) or prof
end
UI.ProfName = ProfName

local function ProfLabel(prof, withKnown)
  if GCA:IsBrowse(prof) then return ProfName(prof) .. " " .. C.browse .. L.PROF_BROWSE_TAG .. "|r" end
  local rank, maxRank = GCA:GetSkill(prof)
  local t = rank and string.format(L.PROF_SKILL, ProfName(prof), rank, maxRank or 300) or ProfName(prof)
  if withKnown then t = t .. "  " .. C.muted .. string.format(L.PROF_KNOWN, GCA:KnownCount(prof)) .. "|r" end
  return t
end
UI.ProfLabel = ProfLabel

local function SpecialisationText(prof, name)
  if prof == "Engineering" and type(name) == "string" and (name:find("Gnomish", 1, true) or name:find("Goblin", 1, true)) then
    return string.format(L.SPECIALISATION_NAME, name:find("Gnomish", 1, true) and L.SPECIALISATION_GNOMISH or L.SPECIALISATION_GOBLIN)
  end
  local p = GCA.PROF_BY_KEY[prof]
  if p and p.spec then return L.SPECIALISATION_UNKNOWN end
end
UI.SpecialisationText = SpecialisationText

P.Ago = Ago
P.Backdrop = Backdrop
P.ClassColor = ClassColor
P.ClassName = ClassName
P.ColoredItemName = ColoredItemName
P.FirstName = FirstName
P.GainText = GainText
P.Hex = Hex
P.ItemIcon = ItemIcon
P.ItemName = ItemName
P.PairSlotName = PairSlotName
P.ProfLabel = ProfLabel
P.ProfName = ProfName
P.QualityColor = QualityColor
P.RowGainText = RowGainText
P.ShortSlotName = ShortSlotName
P.SlotName = SlotName
P.SlotTexture = SlotTexture
P.SourceText = SourceText
P.SpecHowText = SpecHowText
P.StatLabel = StatLabel
P.TagLine = TagLine
