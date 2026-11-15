local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, G, LGet, C = P.SafeCall, P.G, P.LGet, P.C

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
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
local function FirstName(key)
  if type(key) ~= "string" then return "" end
  return key:match("^([^%s%-]+)") or key
end

-- The gain number (user 2026-11-14: no more %): "+8.4", whole numbers from 10 on ("+12").
function UI.GainNum(points)
  local v = points or 0
  if math.abs(v) >= 9.95 then return string.format("%+d", v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5)) end
  return string.format("%+.1f", v)
end

-- "+8.4 AP" (AP/SP/RAP-equivalents, "pts" without a unit stat)
function UI.GainUnit(d) return UI.GainNum(d.points) .. " " .. GCA:UnitLabel(d.e) end

-- (User 2026-11-15: the size pips are gone again; the gain is the number only.)
-- tooltips: "+8.4 AP", "+8.4 AP (empty slot)"
local function GainText(d)
  local t = C.upgrade .. UI.GainUnit(d) .. "|r"
  if d.status == "empty-slot" then t = t .. " " .. C.muted .. L.GAIN_EMPTY .. "|r" end
  return t
end
UI.GainText = GainText

-- K1: the gain on a row in GameFontHighlight (white, not big green); "(empty slot)" muted.
local function RowGainText(d)
  local t = UI.GainUnit(d)
  if d.status == "empty-slot" then t = t .. " " .. C.muted .. L.GAIN_EMPTY .. "|r" end
  return t
end
UI.RowGainText = RowGainText

-- K1 (J3): rows no longer start with "Slot:"; only the pair slots get a disambiguator ("Ring 2", "Trinket 1").
local function PairSlotName(slot)
  if slot == 11 or slot == 12 then return string.format(L.SLOT_RING_N, slot - 10) end
  if slot == 13 or slot == 14 then return string.format(L.SLOT_TRINKET_N, slot - 12) end
end
UI.PairSlotName = PairSlotName
-- slot as shown on a guild-needs row: the pair name where there are two, else the slot name
local function ShortSlotName(slot) return PairSlotName(slot) or SlotName(slot) end
UI.ShortSlotName = ShortSlotName

-- K1: a sub-line from { text, colour } tags: the first two coloured tags keep their colour, the rest (and every
-- plain tag) take the font string's tint, so a row never shows more than two tag colours.
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

-- Stat names in the Shift breakdown: the client's own words where it has them (H4), else ours.
local STAT_GLOBAL = { Strength = "SPELL_STAT1_NAME", Agility = "SPELL_STAT2_NAME", Stamina = "SPELL_STAT3_NAME",
  Intellect = "SPELL_STAT4_NAME", Spirit = "SPELL_STAT5_NAME", Armor = "ARMOR", Defense = "DEFENSE" }
local function StatLabel(key)
  local lkey = "STAT_" .. tostring(key):upper()
  if STAT_GLOBAL[key] then return G(STAT_GLOBAL[key], lkey) end
  return (LGet and LGet(lkey)) or key
end

-- why a spec is unknown, in the client's language (Spec.lua reasons; technical ones = "not readable")
local SPEC_WHY = { ["class unknown"] = "SPEC_WHY_CLASS", ["talents not read yet"] = "SPEC_WHY_NOT_READ",
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

local CFU = ChatFrameUtil

local function ActiveEditBox()
  local eb = CFU and CFU.GetActiveWindow and SafeCall(CFU.GetActiveWindow)
  if not eb and ChatEdit_GetActiveWindow then eb = SafeCall(ChatEdit_GetActiveWindow) end
  return eb
end

-- names are "First Surname" (space), so "/w First Surname text" whispers "First". Preferred route:
-- set the edit box to WHISPER with the full name as tell target (ForeverLFG_GroupQuest\QuestWhisper.lua:55-60),
-- then put the text in. Returns true only when the box verifiably targets `name`.
local function NativeWhisper(name, msg)
  if not (CFU and type(CFU.OpenChat) == "function") then return false end
  local ok, done = pcall(function()
    local eb = CFU.OpenChat("", DEFAULT_CHAT_FRAME)
    if not eb and type(CFU.ChooseBoxForSend) == "function" then eb = CFU.ChooseBoxForSend(DEFAULT_CHAT_FRAME) end
    if not eb then eb = ActiveEditBox() end
    if not (eb and eb.SetChatType and eb.SetTellTarget and eb.SetText) then return false end
    eb:SetChatType("WHISPER")
    eb:SetTellTarget(name)
    if eb.UpdateHeader then eb:UpdateHeader() end
    local kind = eb.GetChatType and eb:GetChatType()
    local target = eb.GetTellTarget and eb:GetTellTarget()
    if GCA.IsSecret(kind) or GCA.IsSecret(target) or kind ~= "WHISPER" or target ~= name then
      eb:SetText("")
      return false
    end
    eb:SetText(msg)
    if eb.SetFocus then eb:SetFocus() end
    return true
  end)
  return ok and done == true
end
UI.NativeWhisper = NativeWhisper

-- Puts msg into the chat box as a whisper to name; you press Enter to send.
local function OpenWhisper(name, msg)
  if NativeWhisper(name, msg) then return end
  -- Fallback (0.5.0 behaviour): open chat with "/w Name text" - the chat box turns it into a whisper.
  local open = (CFU and CFU.OpenChat) or ChatFrame_OpenChat
  if open and pcall(open, "/w " .. name .. " " .. msg) then
    C_Timer.After(0.05, function()
      local eb = ActiveEditBox()
      local text = eb and eb.GetText and SafeCall(eb.GetText, eb)
      if eb and text and text:find(msg, 1, true) then return end
      -- Didn't take: fall back to opening a tell and inserting the text.
      local tell = (CFU and CFU.SendTell) or ChatFrame_SendTell
      if tell then pcall(tell, name) end
      C_Timer.After(0.05, function()
        local eb2 = ActiveEditBox()
        if eb2 and eb2.SetText then
          eb2:SetText(msg)
        elseif CFU and CFU.InsertLink then
          pcall(CFU.InsertLink, msg)
        else
          GCA:Print(string.format(L.WHISPER_TEXT, msg))
        end
      end)
    end)
    return
  end
  GCA:Print(string.format(L.WHISPER_TEXT, msg))
end
UI.OpenWhisper = OpenWhisper

local function SendWhisper(name, msg)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send and pcall(send, msg, "WHISPER", nil, name) then
    GCA:Print(string.format(L.WHISPER_SENT, name))
  else
    OpenWhisper(name, msg)
  end
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

-- Where a member's gear record came from
local function SourceText(m)
  if not m then return "" end
  if m.from then return string.format(L.SRC_VIA, m.from) end
  if m.source == "self" then return L.SRC_SELF end
  if m.source == "inspect" then return L.SRC_INSPECT end
  if m.source == "relay" then return L.SRC_RELAY end
  return m.source or ""
end

-- Profession display name: your client's name when you have it, else ours (localized, H4).
local function ProfName(prof)
  local own = GCA:OwnProfessions()
  if own[prof] and own[prof].name then return own[prof].name end
  return (LGet and LGet("PROF_" .. tostring(prof):upper())) or prof
end
UI.ProfName = ProfName

-- Button: "Leatherworking 120/150" / "Blacksmithing (browse)" (L4: no "known" count on the button);
-- the popup adds the known count.
local function ProfLabel(prof, withKnown)
  if GCA:IsBrowse(prof) then return ProfName(prof) .. " " .. C.browse .. L.PROF_BROWSE_TAG .. "|r" end
  local rank, maxRank = GCA:GetSkill(prof)
  local t = rank and string.format(L.PROF_SKILL, ProfName(prof), rank, maxRank or 300) or ProfName(prof)
  if withKnown then t = t .. "  " .. C.muted .. string.format(L.PROF_KNOWN, GCA.knownCounts[prof] or 0) .. "|r" end
  return t
end
UI.ProfLabel = ProfLabel

-- Specialisation recipes aren't marked in the data; the name tells only for Gnomish/Goblin engineering.
-- `name` is the recipe name from our data (English); the word shown is localized (review M-1).
local function SpecialisationText(prof, name)
  if prof == "Engineering" and type(name) == "string" and (name:find("Gnomish", 1, true) or name:find("Goblin", 1, true)) then
    return string.format(L.SPECIALISATION_NAME, name:find("Gnomish", 1, true) and L.SPECIALISATION_GNOMISH or L.SPECIALISATION_GOBLIN)
  end
  local p = GCA.PROF_BY_KEY[prof]
  if p and p.spec then return L.SPECIALISATION_UNKNOWN end
end
UI.SpecialisationText = SpecialisationText

-- shared with the files loaded after this one (P)
P.Ago = Ago
P.Backdrop = Backdrop
P.ClassColor = ClassColor
P.ClassName = ClassName
P.FirstName = FirstName
P.GainText = GainText
P.Hex = Hex
P.ItemIcon = ItemIcon
P.ItemName = ItemName
P.OpenWhisper = OpenWhisper
P.PairSlotName = PairSlotName
P.ProfLabel = ProfLabel
P.ProfName = ProfName
P.QualityColor = QualityColor
P.RowGainText = RowGainText
P.SendWhisper = SendWhisper
P.ShortSlotName = ShortSlotName
P.SlotName = SlotName
P.SlotTexture = SlotTexture
P.SourceText = SourceText
P.SpecHowText = SpecHowText
P.StatLabel = StatLabel
P.TagLine = TagLine
