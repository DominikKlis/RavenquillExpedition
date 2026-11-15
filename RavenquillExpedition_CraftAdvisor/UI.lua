local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall = GCA.SafeCall
-- Locale (plan H4): ns.L from Locales\*.lua; GCA.L is the same table (harnesses load UI.lua with a bare ns)
local L = ns.L or GCA.L
local G = ns.G or GCA.G
local LGet = ns.LGet or GCA.LGet

local UI = {}
GCA.UI = UI

-- Window size (plan J2): resizable from MIN (the 0.5.0 size; nothing may overlap there) up to the screen;
-- DEFAULT on first open (clamped to the screen). Size and position live in db.settings.window.
local MIN_W, MIN_H = 840, 560
local DEFAULT_W, DEFAULT_H = 980, 640
UI.MIN_W, UI.MIN_H, UI.DEFAULT_W, UI.DEFAULT_H = MIN_W, MIN_H, DEFAULT_W, DEFAULT_H
UI.RESIZE_THROTTLE = 0.05 -- s: at most one relayout per 50 ms while the corner is dragged
-- K8 (native profession window layout): BOTH views = the recipe list on the left (search + Filter on top, category
-- headers + plain one-line rows) and the framed detail panel on the right (the schematic form's place).
local LEFT_W = 260      -- left list column: fixed width (J2); K8: 250 -> 260 (wider squeezes the character sheet at 840)
local RIGHT_X = LEFT_W + 22
local function RightW(w) return w - RIGHT_X - 12 end
local PANEL_TOP = -62   -- K8: panels start right under the rank bar (centred under the title, -27..-56); was -78
local PANEL_BOTTOM = 40 -- room for the bottom button bar
local DETAIL_HEAD = 76  -- K8: member detail: name / sub-line / list header above the sheet or list inside the detail panel
local SUG_ROW_H = 52 -- K4: list cards (50 px + 2 px gap; was 42)
local MEMBER_ROW_H = 25 -- K8: ProfessionsRecipeListRecipeTemplate pitch: one plain text line per member (25 px)
local GROUP_ROW_H = 27  -- K8: ProfessionsRecipeListCategoryTemplate = 25 px high + 2 px gap
local NEED_ROW_H = 25   -- K8: guild needs = one plain recipe row per craft (name [n], gain)
local NEED_SUB_H = 42   -- K5: a member of the selected craft (K8: in the detail panel; K10: two lines, worn item)
local MEMBER_LIST_TOP = 34 -- K5: the list starts below its search box (inside the list panel; both views since K8)
local COUNT_H = 18      -- K8: the guild-needs count line at the bottom of the left list panel
UI.MEMBER_ROW_H, UI.GROUP_ROW_H, UI.NEED_ROW_H, UI.NEED_SUB_H = MEMBER_ROW_H, GROUP_ROW_H, NEED_ROW_H, NEED_SUB_H
UI.LEFT_W, UI.PANEL_TOP = LEFT_W, PANEL_TOP

---------------------------------------------------------------------------
-- Colour palette (plan H3 A1): one meaning per colour
---------------------------------------------------------------------------
local C = {
  upgrade = "|cff33ff33",   -- gains, badges
  known = "|cff8cb4ff",     -- recipe known
  set = "|cffd28cff",       -- set bonus gained / set hint
  setLoss = "|cffff6644",   -- set bonus broken
  unlearned = "|cffff8833", -- recipe not learned (own profession)
  browse = "|cff4fd2c8",    -- browsing another profession
  future = "|cffffd100",    -- too high level to wear yet
  offline = "|cff8a8a8a",   -- offline marker
  muted = "|cffaaaaaa",
  dim = "|cff888888",
  warn = "|cffff8800",
  bad = "|cffff5555",
  levelTag = "|cfff0b44c",  -- K4: "from level N · X to go" chip (orange, as the mockups)
}
-- K1 typography (CraftersJournal ProfessionUI.lua:771-784): sub-lines in GameFontHighlightSmall with this tint;
-- at most two coloured tags per sub-line (TagLine), everything else in the tint.
local SUB_TINT = { 0.75, 0.72, 0.65 }
UI.SUB_TINT = SUB_TINT
UI.COLORS = C

---------------------------------------------------------------------------
-- Atlas art with a way out (H1; Spoken Compendium.lua:110-121, CraftersJournal Core.lua:64-66):
-- a missing atlas draws nothing at all, so every SetAtlas is guarded and has a fallback.
---------------------------------------------------------------------------
local function HasAtlas(name)
  if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
  local info = SafeCall(C_Texture.GetAtlasInfo, name)
  return info ~= nil and not GCA.IsSecret(info)
end
UI.HasAtlas = HasAtlas
local function SetAtlasSafe(tex, atlas, useSize)
  if not (tex and tex.SetAtlas and HasAtlas(atlas)) then return false end
  return (pcall(tex.SetAtlas, tex, atlas, useSize)) and true or false
end

-- Texture FILES (not atlases) can't go through GetAtlasInfo. Same check as ForeverDungeonJournal
-- Systems\LFGButton.lua:393-396: where the client has GetFileIDFromPath, the file must resolve to an ID; where it
-- hasn't, the file is trusted only because another Forever addon draws it (the callers name which one).
local function FileOK(path)
  if type(GetFileIDFromPath) ~= "function" then return nil end -- can't tell
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and id ~= nil and not GCA.IsSecret(id)
end
UI.FileOK = FileOK
-- Proven on Forever by other installed addons (each guarded by FileOK where the API exists):
UI.TEX = {
  offer = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up",       -- ForeverLFG_GroupQuest QuestMatchesUI.lua:402
  caretDown = "Interface\\Buttons\\Arrow-Down-Up",           -- CraftersJournal HeaderUI.lua:224, ForeverDungeonJournal Journal.lua:9777
  caretUp = "Interface\\BUTTONS\\Arrow-Up-Up",               -- GearQuestForever Indicator.lua:5
  plus = "Interface\\Buttons\\UI-PlusButton-Up",             -- GearQuestForever Log.lua, CraftersJournal HomeUI.lua
  minus = "Interface\\Buttons\\UI-MinusButton-Up",
  check = "Interface\\Buttons\\UI-CheckBox-Check",           -- (0.5.0 options menu)
  iconHL = "Interface\\Buttons\\ButtonHilight-Square",       -- CraftersJournal UI.lua, ForeverDungeonJournal LFGButton.lua:1008
  rowHL = "Interface\\QuestFrame\\UI-QuestTitleHighlight",   -- CraftersJournal CalculatorUI.lua:162
  search = "Interface\\Common\\UI-Searchbox-Icon",           -- ForeverDungeonJournal Journal.lua:8856
  clear = "Interface\\Buttons\\UI-StopButton",               -- ForeverDungeonJournal Journal.lua:8867
  -- K4 (member view variants): item icon frame, tinted by quality (empty slots use the character window's own
  -- slot art from GetInventorySlotInfo, as the section headers already do)
  iconFrame = "Interface\\Common\\WhiteIconFrame",           -- GearQuestForever Popup.lua:95; K6: file 651080 = the
                                                             -- IconBorder of the client's own item/gear slot buttons (probe)
  -- K5: the skill bar fill, the class icons
  skillBar = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", -- CraftersJournal CollectionUI.lua:376
  classIcons = "Interface\\TargetingFrame\\UI-Classes-Circles",    -- ForeverLFG_GroupQuest QuestMatchesUI.lua:163-169
}
-- A proven file is drawn unless GetFileIDFromPath exists and says it is not there.
local function TexOK(key) return FileOK(UI.TEX[key]) ~= false end
UI.TexOK = TexOK

-- K5: ONE place for the art of the row/panel parts (roles -> atlas / proven file / fallback colour).
-- K6 (native look): every role is now the art the client's OWN windows draw, read from the in-game probe of
-- ProfessionsFrame / CharacterFrame (session scratchpad probe\digest.txt, 2026-11-14):
--   listBg      Professions-background-summarylist = ProfessionsFrame.CraftingPage.RecipeList.Background
--   rowHover    the classic list-row hover file (UI.TEX.rowHL, FriendsFrame / quest log rows), ADD blend
--   rowSelected search-highlight = the selected row of the profession window's search results (OVERLAY)
--   skillBar    the fill of the rank bar (Professions-skillbar-bg/-frame around it, see CreateProfessionPicker)
-- UI.Skin(tex, role) draws a role on a texture and returns how ("atlas", "file", "color"); UI.SkinTint recolours.
-- The mockup roles (alternating rows, gold select bar, chip/badge/button boxes, borders, tree lines, discs) are gone.
-- K8 (exact recipe-list rows, probe tpl:ProfessionsRecipeListRecipeTemplate / ...CategoryTemplate):
--   rowHover    Professions_Recipe_Hover 309x21, HIGHLIGHT, alpha 0.5, CENTER 0,-1 (the recipe row's HighlightOverlay)
--   rowSelected Professions_Recipe_Active 267x19, OVERLAY, CENTER 0,-1 (its SelectedOverlay: the gold bar under the row)
--   category    common-button-list-collapseExpand filling the 25 px category button (ARTWORK); categoryHover = the
--               same atlas on HIGHLIGHT, ADD, alpha 0.4
--   collapseIcon the category's CollapseButton.Icon: its atlas is set by the client's mixin at runtime and NOT in the
--               probe -> candidate pairs (minus = expanded, plus = collapsed), the first pair GetAtlasInfo has both of
--               is used; none -> a gold "–" / "+" in GameFontNormal (UI.collapseIconKind records which)
--   detailBorder the bronze frame around the detail panel (the schematic form's border). Pluggable: `layout` = a
--               NineSliceUtil layout name, or `pieces` = a list like UI.INNER_BORDER ({ key, atlas, w, h, p | a/b,
--               horiz }); empty (default) -> the probe-confirmed inner border (UI.AddInnerBorder). The lead fills in the
--               confirmed atlas names after the next probe.
--   detailRing  the bronze ring around the round item icon of the detail panel (ForeverDungeonJournal
--               LFGButton.lua:367-403 draws this file around its masked round icon on Forever)
UI.SKIN = {
  rowHover = { atlas = "Professions_Recipe_Hover", alpha = 0.5, size = { 309, 21 }, file = "rowHL", blend = "ADD", color = { 1, 1, 1, 0.07 } },
  rowSelected = { atlas = "Professions_Recipe_Active", size = { 267, 19 }, file = "rowHL", blend = "ADD", color = { 1, 0.82, 0, 0.14 } },
  listBg = { atlas = "Professions-background-summarylist", color = { 0, 0, 0, 0.45 } },
  separator = { color = { 1, 1, 1, 0.08 } }, -- 1 px row separator (WhatsTraining Crafting\RecipeList.lua:122-127)
  skillBar = { file = "skillBar", tint = { 0.2, 0.32, 0.9, 1 }, color = { 0.2, 0.32, 0.9, 1 } },
  category = { atlas = "common-button-list-collapseExpand", color = { 0.20, 0.13, 0.07, 0.95 } },
  categoryHover = { atlas = "common-button-list-collapseExpand", atlasBlend = "ADD", alpha = 0.4, color = { 1, 0.82, 0, 0.08 } },
  collapseIcon = { pairs = { { "common-button-collapseExpand-minus", "common-button-collapseExpand-plus" },
    { "Professions-recipe-header-collapse", "Professions-recipe-header-expand" } } },
  -- K9 (probe of the OPEN profession window, ProfessionsFrame@open): the schematic form's visible frame is ONE
  -- stretched atlas "common-insideframe" (BORDER, 360x484, TOPLEFT 0,0 over the whole form); its NineSlice (the
  -- thin inner border) is hidden. Behind it: "Profession-background-card-<profession lower case>" (BACKGROUND).
  detailBorder = { atlas = "common-insideframe", card = "Profession-background-card-" },
  detailRing = { file = "Interface\\Common\\GoldRing", mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask" },
}
function UI.Skin(tex, role)
  local def = UI.SKIN[role] or {}
  local function blend() if def.blend and tex.SetBlendMode then pcall(tex.SetBlendMode, tex, def.blend) end end
  if def.atlas and SetAtlasSafe(tex, def.atlas) then
    if def.atlasBlend and tex.SetBlendMode then pcall(tex.SetBlendMode, tex, def.atlasBlend) end
    if def.alpha and tex.SetAlpha then tex:SetAlpha(def.alpha) end
    return "atlas"
  end
  if def.file and TexOK(def.file) then
    tex:SetTexture(UI.TEX[def.file])
    local c = def.tint
    if c and tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], c[4]) end
    blend()
    return "file"
  end
  local c = def.color or { 1, 1, 1, 1 }
  tex:SetColorTexture(c[1], c[2], c[3], c[4])
  return "color"
end
function UI.SkinTint(tex, kind, r, g, b, a)
  if kind == "color" then tex:SetColorTexture(r, g, b, a or 1) elseif tex.SetVertexColor then tex:SetVertexColor(r, g, b, a or 1) end
end

-- One line, no wrapping (L1/L2): a long text is cut with "..." instead of growing into the next row.
local function SingleLine(fs)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end

---------------------------------------------------------------------------
-- Error reporter (diagnostics, 2026-11-13): WoW hides Lua errors by default, so a failing
-- Create/Refresh left an empty window with no message. Report the first error per message text in
-- chat and keep the last one in SavedVariables (db.lastError) so it can be read after /reload.
-- Also wraps every tooltip (OnEnter) handler (review H-1), so a broken text is reported, not silent.
---------------------------------------------------------------------------
local reported = {}
UI.errorCount = 0
local function Guard(name, fn)
  return function(...)
    local args = { n = select("#", ...), ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, args.n)) end, function(e)
      local stack = debugstack and debugstack(2, 6, 0) or ""
      return tostring(e) .. "\n" .. tostring(stack)
    end)
    if not ok then
      UI.errorCount = UI.errorCount + 1
      local first = tostring(err):match("^[^\n]*") or tostring(err)
      if GCA.db then
        GCA.db.lastError = { where = name, msg = tostring(err), at = date and date("%Y-%m-%d %H:%M:%S") or "?" }
      end
      if not reported[first] then
        reported[first] = true
        GCA.Print("|cffff5555" .. string.format(L.ERROR_IN, name) .. "|r " .. first .. "  " .. L.ERROR_SAVED)
      end
    end
  end
end
UI.Guard = Guard
-- frame:SetScript("OnEnter", ...) through the reporter
local function SetTip(frame, name, fn)
  frame:SetScript("OnEnter", Guard("tooltip: " .. name, fn))
end

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
-- (UI fields, not locals: UI.lua's main chunk is at Lua's 200-locals limit)
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

-- K0/L3: why a spec is unknown, in the client's language (Spec.lua reasons; technical ones = "not readable")
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
  local _, _, _, _, icon = SafeCall(GCA.ItemAPI.Instant, item)
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ItemName(id)
  local n = GCA.ItemAPI.NameByID and SafeCall(GCA.ItemAPI.NameByID, id)
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

-- K0/L2: names are "First Surname" (space), so "/w First Surname text" whispers "First". Preferred route:
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
          GCA.Print(string.format(L.WHISPER_TEXT, msg))
        end
      end)
    end)
    return
  end
  GCA.Print(string.format(L.WHISPER_TEXT, msg))
end
UI.OpenWhisper = OpenWhisper

local function SendWhisper(name, msg)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send and pcall(send, msg, "WHISPER", nil, name) then
    GCA.Print(string.format(L.WHISPER_SENT, name))
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

-- Specialisation recipes aren't marked in the data (G7.12); the name tells only for Gnomish/Goblin engineering.
-- `name` is the recipe name from our data (English); the word shown is localized (review M-1).
local function SpecialisationText(prof, name)
  if prof == "Engineering" and type(name) == "string" and (name:find("Gnomish", 1, true) or name:find("Goblin", 1, true)) then
    return string.format(L.SPECIALISATION_NAME, name:find("Gnomish", 1, true) and L.SPECIALISATION_GNOMISH or L.SPECIALISATION_GOBLIN)
  end
  local p = GCA.PROF_BY_KEY[prof]
  if p and p.spec then return L.SPECIALISATION_UNKNOWN end
end
UI.SpecialisationText = SpecialisationText

---------------------------------------------------------------------------
-- Offer whisper (G7.11/G7.18; H3 U2: localized, editable template with placeholders)
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
      GCA.Print(L.WHISPER_TOO_LONG)
    end
  end
  return msg
end

-- Offer only for a craft/enchant you know, in your own profession, for someone else who is online now:
-- a whisper doesn't reach an offline player (H3 U3; enchants needed this already, G7.18).
function UI.CanOffer(cur, d)
  if not (cur and d) or cur.isSelf or cur.browse or not d.known then return false end
  if not cur.online then return false end
  return true
end

-- "wearable at level 42 (in 3 levels)" (H5.2)
local function WearableText(d)
  local togo = d.levelsToGo or 0
  if togo == 1 then return string.format(L.WEARABLE_AT_1, d.wearAt or 0) end
  return string.format(L.WEARABLE_AT, d.wearAt or 0, togo)
end
UI.WearableText = WearableText

---------------------------------------------------------------------------
-- K4 helpers (member view variants): thin borders, measured text, guarded templates, gain texts, stat differences
---------------------------------------------------------------------------
-- A 1 px border from four colour textures (no art needed). f:SetBorderColor(r, g, b, a) recolours it.
local function AddBorder(f, r, g, b, a)
  local e = {}
  for i = 1, 4 do e[i] = f:CreateTexture(nil, "BORDER") end
  e[1]:SetPoint("TOPLEFT", f, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT"); e[1]:SetHeight(1)
  e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); e[2]:SetHeight(1)
  e[3]:SetPoint("TOPLEFT", f, "TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); e[3]:SetWidth(1)
  e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); e[4]:SetWidth(1)
  f.edges = e
  function f:SetBorderColor(r2, g2, b2, a2)
    for _, t in ipairs(self.edges) do t:SetColorTexture(r2, g2, b2, a2 or 1) end
  end
  f:SetBorderColor(r, g, b, a)
end
UI.AddBorder = AddBorder

-- Width of a font string's text: the client's measure, else an estimate (~6 px per character; offline harness).
local function TextWidth(fs)
  for _, m in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[m]
    if type(fn) == "function" then
      local w = SafeCall(fn, fs)
      if type(w) == "number" and not GCA.IsSecret(w) and w > 0 then return math.ceil(w) end
    end
  end
  local t = tostring(fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\128-\191]", "")
  return math.ceil(#t * 6)
end
UI.TextWidth = TextWidth

-- Text button: UIPanelButtonTemplate in pcall; a plain button with its own label and border where it fails.
local function NewTextButton(parent, w, h, text)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not (ok and b) then
    b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.3, 0.06, 0.04, 0.95)
    AddBorder(b, 0.72, 0.54, 0.18, 1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end
    b.plain = true
  end
  b:SetSize(w, h)
  b:SetText(text)
  return b
end
UI.NewTextButton = NewTextButton

-- Check box (K6): MinimalCheckboxTemplate (the profession window's own check boxes: checkbox-minimal /
-- checkmark-minimal, probe), else UICheckButtonTemplate, each in pcall; a bordered box with the 0.5.0 check texture
-- where both fail. c.template tells which one was made.
local function NewCheck(parent, size)
  local ok, c
  for _, tpl in ipairs({ "MinimalCheckboxTemplate", "UICheckButtonTemplate" }) do
    ok, c = pcall(CreateFrame, "CheckButton", nil, parent, tpl)
    if ok and c then c.template = tpl; break end
  end
  if not (ok and c) then
    c = CreateFrame("CheckButton", nil, parent)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0.05, 0.05, 0.04, 0.9)
    AddBorder(c, 0.42, 0.38, 0.31, 1)
    if c.SetCheckedTexture and TexOK("check") then pcall(c.SetCheckedTexture, c, UI.TEX.check) end
    c.plain = true
  end
  c:SetSize(size, size)
  return c
end
UI.NewCheck = NewCheck

-- K6: a font object the client's own windows use (probe: GameFontGreen / GameFontGreenLarge in CharacterFrame,
-- Number12FontOutline on the profession rank bar), only where the client has it; else the given colour on the
-- font string's own font. Returns true when the font object was set.
local function NativeFont(fs, name, r, g, b)
  local obj = rawget(_G, name)
  if obj and fs.SetFontObject and pcall(fs.SetFontObject, fs, obj) then fs.nativeFont = name; return true end
  if r and fs.SetTextColor then fs:SetTextColor(r, g, b) end
  return false
end
UI.NativeFont = NativeFont
-- the green gain numbers (K6: the client's green font objects instead of a hand-picked green)
local GAIN_RGB = { 0.31, 0.88, 0.35 }
local function GainFont(fs, large) return NativeFont(fs, large and "GameFontGreenLarge" or "GameFontGreen", GAIN_RGB[1], GAIN_RGB[2], GAIN_RGB[3]) end

-- "from level 42 · 3 to go" (the mockups' orange tag on too-high-level crafts)
local function LevelTag(d) return string.format(L.LEVEL_TAG, d.wearAt or 0, d.levelsToGo or 0) end
UI.LevelTag = LevelTag

-- Big line + small line under it (user 2026-11-15: number only): "+8.4 AP" / "(empty slot)" or "".
local function CardGain(d)
  return UI.GainUnit(d), d.status == "empty-slot" and L.GAIN_EMPTY or ""
end
UI.CardGain = CardGain

-- Stat differences new - worn, from the same canonical stats (GetItemStats -> Scoring.normalize, or the enchant
-- table's stats) the score is computed from; the set bonus part of a score is not per stat (a tag says it).
-- Hit/crit are stored as melee + spell twins: shown once when both changed alike. Order: biggest weighted
-- change first. Returns nil when a side has no stat table (nothing reliable to show), plus `partial` when a
-- side had client stat keys we don't map (those can't be listed).
local PCT_STATS = { MeleeHit = true, SpellHit = true, MeleeCrit = true, SpellCrit = true, Dodge = true, Parry = true, Block = true }
local STAT_TWINS = { { "MeleeHit", "SpellHit", "STATD_HIT" }, { "MeleeCrit", "SpellCrit", "STATD_CRIT" } }
function UI.StatDiff(d)
  local new = d and d.info and d.info.cstats
  if type(new) ~= "table" then return nil end
  local old = {}
  if d.equipped then
    if type(d.equipped.cstats) ~= "table" then return nil end
    old = d.equipped.cstats
  end
  local weights = d.e and d.e.set and d.e.set.weights or {}
  local diff = {}
  for k, v in pairs(new) do if type(v) == "number" then diff[k] = v end end
  for k, v in pairs(old) do if type(v) == "number" then diff[k] = (diff[k] or 0) - v end end
  local rows, done = {}, {}
  local function add(key, amount, label, pct, w)
    rows[#rows + 1] = { key = key, amount = amount, label = label, pct = pct and true or false, value = amount * (w or 0) }
  end
  for _, tw in ipairs(STAT_TWINS) do
    local a, b = diff[tw[1]], diff[tw[2]]
    if a and b and math.abs(a - b) < 1e-9 then
      if math.abs(a) >= 0.005 then add(tw[1], a, L[tw[3]], true, (weights[tw[1]] or 0) + (weights[tw[2]] or 0)) end
      done[tw[1]], done[tw[2]] = true, true
    end
  end
  for k, v in pairs(diff) do
    if not done[k] and math.abs(v) >= 0.005 then add(k, v, (StatLabel(k):gsub("%s*%%$", "")), PCT_STATS[k], weights[k]) end
  end
  table.sort(rows, function(a, b)
    if math.abs(math.abs(a.value) - math.abs(b.value)) > 1e-9 then return math.abs(a.value) > math.abs(b.value) end
    if math.abs(math.abs(a.amount) - math.abs(b.amount)) > 1e-9 then return math.abs(a.amount) > math.abs(b.amount) end
    return a.key < b.key
  end)
  -- W6: a weapon's speed first ("Speed 2.60 → 3.40", deDE "Tempo 2,60 → 3,40"); only when the new one was read
  local ns, os = d.info.speed, d.equipped and d.equipped.speed
  if type(ns) == "number" and (type(os) ~= "number" or math.abs(ns - os) >= 0.005) then
    table.insert(rows, 1, { key = "Speed", speed = ns, oldSpeed = type(os) == "number" and os or nil, amount = 0, value = 0, label = L.STATD_SPEED_LABEL })
  end
  local function unmapped(info) return type(info) == "table" and type(info.unknownStats) == "table" and #info.unknownStats > 0 end
  return rows, unmapped(d.info) or unmapped(d.equipped)
end

-- "+6 Agility", "-2 Strength", "+1% Hit"; coloured = green/red number
function UI.StatText(row, coloured)
  if row.speed then -- W6: "Speed 2.60 → 3.40" / "Tempo 2,60 → 3,40" (decimal mark per locale)
    local function n(v) return (string.format("%.2f", v):gsub("%.", L.DECIMAL_MARK)) end
    if row.oldSpeed then return string.format(L.STATD_SPEED, n(row.oldSpeed), n(row.speed)) end
    return string.format(L.STATD_SPEED_ONE, n(row.speed))
  end
  local a = math.floor(math.abs(row.amount) * 100 + 0.5) / 100
  local t = (row.amount < 0 and "-" or "+") .. string.format("%g", a) .. (row.pct and "%" or "")
  if coloured then t = (row.amount < 0 and C.bad or C.upgrade) .. t .. "|r" end
  return t .. " " .. tostring(row.label)
end

-- K6: a tag is coloured text, as Blizzard's tooltips colour theirs (the K4 boxed "chip" frames are gone).
local function Tag(text, colour) return (colour or "") .. tostring(text) .. (colour and "|r" or "") end
UI.Tag = Tag

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
-- K6: list panel = the profession window's recipe-list panel: Professions-background-summarylist filling the
-- panel (ProfessionsFrame.CraftingPage.RecipeList.Background, BACKGROUND, probe), no inner border (the client's
-- RecipeList.BackgroundNineSlice is hidden). Where the atlas is missing: the K1 inset below.
-- K7 (lead, user feedback on K6 in game): the thin inner border Blizzard draws around each inner segment. Probe:
-- ProfessionsFrame.CraftingPage.RecipeList.BackgroundNineSlice, .SchematicForm.NineSlice and ProfessionsFrameInset.NineSlice
-- = 6x6 corners UI-Frame-InnerTopLeft/-TopRight/-BotLeftCorner/-BotRight (bottom ones at y -1), 3 px tiles
-- _UI-Frame-InnerTopTile/_UI-Frame-InnerBotTile (horizontal) and !UI-Frame-InnerLeftTile/!UI-Frame-InnerRightTile
-- (vertical) between the corners, layer BORDER, on a child frame named NineSlice. That is the "InsetFrameTemplate"
-- NineSlice layout, so: NineSliceUtil.ApplyLayoutByName(ns, "InsetFrameTemplate") (pcall, checked that it really
-- drew the corner), else the same eight pieces by hand. nil when the atlases are missing.
UI.INNER_BORDER = {
  { key = "TopLeftCorner", atlas = "UI-Frame-InnerTopLeft", p = { "TOPLEFT", 0, 0 } },
  { key = "TopRightCorner", atlas = "UI-Frame-InnerTopRight", p = { "TOPRIGHT", 0, 0 } },
  { key = "BottomLeftCorner", atlas = "UI-Frame-InnerBotLeftCorner", p = { "BOTTOMLEFT", 0, -1 } },
  { key = "BottomRightCorner", atlas = "UI-Frame-InnerBotRight", p = { "BOTTOMRIGHT", 0, -1 } },
  { key = "TopEdge", atlas = "_UI-Frame-InnerTopTile", a = { "TOPLEFT", "TopLeftCorner", "TOPRIGHT" }, b = { "TOPRIGHT", "TopRightCorner", "TOPLEFT" }, horiz = true },
  { key = "BottomEdge", atlas = "_UI-Frame-InnerBotTile", a = { "BOTTOMLEFT", "BottomLeftCorner", "BOTTOMRIGHT" }, b = { "BOTTOMRIGHT", "BottomRightCorner", "BOTTOMLEFT" }, horiz = true },
  { key = "LeftEdge", atlas = "!UI-Frame-InnerLeftTile", a = { "TOPLEFT", "TopLeftCorner", "BOTTOMLEFT" }, b = { "BOTTOMLEFT", "BottomLeftCorner", "TOPLEFT" } },
  { key = "RightEdge", atlas = "!UI-Frame-InnerRightTile", a = { "TOPRIGHT", "TopRightCorner", "BOTTOMRIGHT" }, b = { "BOTTOMRIGHT", "BottomRightCorner", "TOPRIGHT" } },
}
-- K8: draws a list of border pieces (UI.INNER_BORDER's shape; optional per piece w/h: corner size / tile thickness,
-- default 6 / 3) on a child frame `ns`; false (nothing drawn) when one atlas is missing.
function UI.DrawBorderPieces(ns, pieces)
  for _, def in ipairs(pieces) do
    if not HasAtlas(def.atlas) then return false end
  end
  for _, def in ipairs(pieces) do
    local t = ns:CreateTexture(nil, "BORDER")
    ns[def.key] = t
    if def.p then
      SetAtlasSafe(t, def.atlas, true)
      t:SetSize(def.w or 6, def.h or def.w or 6)
      t:SetPoint(def.p[1], ns, def.p[1], def.p[2], def.p[3])
    else
      SetAtlasSafe(t, def.atlas)
      t:SetPoint(def.a[1], ns[def.a[2]], def.a[3], 0, 0)
      t:SetPoint(def.b[1], ns[def.b[2]], def.b[3], 0, 0)
      if def.horiz then
        t:SetHeight(def.h or 3)
        if t.SetHorizTile then pcall(t.SetHorizTile, t, true) end
      else
        t:SetWidth(def.w or 3)
        if t.SetVertTile then pcall(t.SetVertTile, t, true) end
      end
    end
  end
  return true
end
function UI.AddInnerBorder(p)
  local ns = CreateFrame("Frame", nil, p)
  ns:SetAllPoints()
  p.NineSlice = ns
  if NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function"
    and pcall(NineSliceUtil.ApplyLayoutByName, ns, "InsetFrameTemplate") and type(ns.TopLeftCorner) == "table" then
    ns.how = "util"
    return ns
  end
  if not UI.DrawBorderPieces(ns, UI.INNER_BORDER) then ns:Hide(); ns.how = nil; return nil end
  ns.how = "atlas"
  return ns
end

-- K8: the detail panel's frame (the profession window's schematic-form border) from the skin role detailBorder:
-- its NineSliceUtil layout, else its own piece list, else (default, and whenever those fail) the inner border.
-- ns.how = "layout" / "pieces" / the inner border's "util" / "atlas"; nil = nothing drawn. ns.role = "detailBorder".
UI.detailPanels = UI.detailPanels or {}
-- K9: the profession's background card behind each detail panel (follows the selected profession).
function UI.UpdateDetailCards()
  local def = UI.SKIN.detailBorder or {}
  if not def.card then return end
  local prof = GCA.SelectedProfession and GCA:SelectedProfession() or "Leatherworking"
  local atlas = def.card .. string.lower(tostring(prof))
  for _, p in ipairs(UI.detailPanels) do
    if p.cardBg then
      if HasAtlas(atlas) and SetAtlasSafe(p.cardBg, atlas) then p.cardBg:Show()
      elseif HasAtlas(def.card .. "leatherworking") and SetAtlasSafe(p.cardBg, def.card .. "leatherworking") then p.cardBg:Show()
      else p.cardBg:Hide() end
    end
  end
end
function UI.AddDetailBorder(p)
  local def = UI.SKIN.detailBorder or {}
  if def.atlas and HasAtlas(def.atlas) then
    p.cardBg = p:CreateTexture(nil, "BACKGROUND")
    p.cardBg:SetAllPoints()
    p.cardBg:Hide()
    local ns = CreateFrame("Frame", nil, p)
    ns:SetAllPoints()
    local t = ns:CreateTexture(nil, "BORDER")
    t:SetAllPoints()
    if SetAtlasSafe(t, def.atlas) then
      ns.frameTex = t
      p.NineSlice, ns.how, ns.role = ns, "atlas1", "detailBorder"
      UI.detailPanels[#UI.detailPanels + 1] = p
      pcall(UI.UpdateDetailCards)
      return ns
    end
    ns:Hide()
  end
  if def.layout and NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function" then
    local ns = CreateFrame("Frame", nil, p)
    ns:SetAllPoints()
    if pcall(NineSliceUtil.ApplyLayoutByName, ns, def.layout) and type(ns.TopLeftCorner) == "table" then
      p.NineSlice, ns.how, ns.role = ns, "layout", "detailBorder"
      return ns
    end
    ns:Hide()
  end
  if type(def.pieces) == "table" and #def.pieces > 0 then
    local ns = CreateFrame("Frame", nil, p)
    ns:SetAllPoints()
    if UI.DrawBorderPieces(ns, def.pieces) then
      p.NineSlice, ns.how, ns.role = ns, "pieces", "detailBorder"
      return ns
    end
    ns:Hide()
  end
  local ns = UI.AddInnerBorder(p)
  if ns then ns.role = "detailBorder" end
  return ns
end

local function NewInset(parent, overArt)
  if HasAtlas(UI.SKIN.listBg.atlas) then
    local p = CreateFrame("Frame", nil, parent)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    UI.Skin(p.bg, "listBg")
    p.native = true
    return p
  end
  return UI.NewPlainInset(parent, overArt)
end
-- Inset panel (modern InsetFrameTemplate, as Spoken uses on Forever); plain backdrop if missing.
-- Review L-3: over the painted profession art the inset background is translucent so the art shows; without the
-- art (fallback look) it stays as it was. K1: 0.4 -> 0.75 (the art showed through too much: text was hard to read).
UI.INSET_ART_ALPHA = 0.75
function UI.NewPlainInset(parent, overArt)
  local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if ok and inset then
    inset.templated = true
    if overArt and type(inset.Bg) == "table" and inset.Bg.SetAlpha then inset.Bg:SetAlpha(UI.INSET_ART_ALPHA) end
    return inset
  end
  inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if inset.SetBackdrop then Backdrop(inset, overArt and UI.INSET_ART_ALPHA or 0.6) end
  return inset
end

-- Keep the inset's border drawn over the scroll content (Spoken Compendium.lua:1872-1873).
local function RaiseInsetBorder(inset, content)
  if type(inset.NineSlice) == "table" and inset.NineSlice.SetFrameLevel and content.GetFrameLevel then
    local lvl = content:GetFrameLevel()
    if type(lvl) == "number" then inset.NineSlice:SetFrameLevel(lvl + 5) end
  end
end

-- Popup list on the native dropdown art (WhatsTraining Forever\Menu.lua:477); tooltip backdrop if missing.
local function NewPopup(parent)
  local pop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  pop:SetFrameStrata("DIALOG")
  pop:EnableMouse(true)
  pop.backing = pop:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(pop.backing, "common-dropdown-bg") then
    pop.backing:SetPoint("TOPLEFT", -10, 3)
    pop.backing:SetPoint("BOTTOMRIGHT", 10, -3)
    if pop.backing.SetAlpha then pop.backing:SetAlpha(0.925) end
    pop.atlas = true
  else
    pop.backing:Hide()
    if pop.SetBackdrop then Backdrop(pop, 0.97) end
  end
  pop:Hide()
  return pop
end
UI.NewPopup = NewPopup

-- Profession-window art. K6: exactly as the client's ProfessionsFrame draws it (probe): ProfessionsFrameBg =
-- Profession-Background-Overview from TOPLEFT 2,-21 over the whole frame, and the crafting page's
-- Profession-Background-Template2 (665x570 = the whole 673x594 frame inside its border, TOPLEFT 3,-21) on top.
-- Our window is larger and resizable, so both fill the inner area (the K5 54 px clipped header strip is gone).
-- Frame levels: canvas at the window's own level, page +1, our content +2 (its children above), portrait +2,
-- border (NineSlice) +3 (GearQuestForever Log.lua:1025-1028), close button +4. Missing atlases: dark fill only,
-- native Bg kept.
local function PaintArt(f)
  local base = f:GetFrameLevel() or 0
  local art = {}
  f.gcaArt = art
  local canvas = CreateFrame("Frame", nil, f)
  canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21)
  canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 3)
  canvas:SetFrameLevel(base)
  art.canvas = canvas
  art.fill = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
  art.fill:SetAllPoints()
  local overview = canvas:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(overview, "Profession-Background-Overview") then
    overview:SetAllPoints()
    art.overview = overview
  else
    overview:Hide()
  end
  if HasAtlas("Profession-Background-Template2") then
    local page = CreateFrame("Frame", nil, canvas)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -21)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    page:SetFrameLevel(base + 1)
    local pageArt = page:CreateTexture(nil, "BACKGROUND")
    if SetAtlasSafe(pageArt, "Profession-Background-Template2") then
      pageArt:SetAllPoints()
      art.page, art.pageArt = page, pageArt
    else
      page:Hide()
    end
  end
  art.painted = art.overview ~= nil or art.page ~= nil
  if art.painted then
    art.fill:SetColorTexture(0.06, 0.05, 0.04, 1)
    if type(f.Bg) == "table" and f.Bg.Hide then f.Bg:Hide() end
  else
    -- no profession art on this client: a dark wash over the template's own background
    art.fill:SetColorTexture(0.06, 0.05, 0.04, 0.85)
  end
  return art
end

local function ApplyLevels(f)
  local art = f.gcaArt
  if not art then return end
  local base = art.canvas:GetFrameLevel() or 0
  local function lift(fr, n)
    if type(fr) == "table" and fr.SetFrameLevel then fr:SetFrameLevel(base + n) end
  end
  lift(f.content, 2)
  lift(f.PortraitContainer, 2)
  lift(f.TitleContainer, 3)
  lift(f.NineSlice, 3)
  lift(f.CloseButton, 4)
end

-- Native portrait window where the client has it; the old dialog look where not (Spoken Compendium.lua:399-421).
local function NewWindow(name, title)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
  if ok and f and type(f.SetTitle) == "function" then
    f.templated = true
    SafeCall(f.SetTitle, f, title)
    if f.SetPortraitToAsset then SafeCall(f.SetPortraitToAsset, f, "Interface\\Icons\\Trade_LeatherWorking") end
    PaintArt(f)
    return f
  end
  f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOP", f, "TOP", 0, -14)
  text:SetText(title)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
  f.CloseButton = close
  return f
end

-- Simple pooled scroll list. Optional `kinds` (plan I): { [rowKind] = { create, update, height } } for data
-- entries with `d.rowKind` (own pool and height each); everything else uses createRow/updateRow/rowHeight.
-- Not virtualised: every entry gets a (pooled) row and the scroll frame clips; sf.rowY keeps each entry's
-- y offset and height so VisibleRows() can tell how many fit in the view (J2).
-- K6: the scroll bar is the client's MinimalScrollBar (the profession recipe list's own bar, 8 px, minimal-scrollbar-*
-- atlases, probe) on a plain ScrollFrame, linked by ScrollUtil.InitScrollFrameWithScrollBar and scrolled by the wheel
-- with ScrollStepInDirection - exactly as ForeverLFG ChatRulesUI.lua:54-60 / ForeverLFG_GroupQuest
-- QuestMatchesUI.lua:229-235 do on Forever. The pooled rows stay (a WowScrollBoxList rewrite would touch every row
-- kind and the layout code for no visible gain). Without ScrollUtil / the template: UIPanelScrollFrameTemplate.
local function NewScrollFrame(parent)
  local link = ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar
  if type(link) == "function" then
    local ok, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
    if ok and bar and bar.ScrollStepInDirection then
      local sf = CreateFrame("ScrollFrame", nil, parent)
      sf.pendingBar = bar
      return sf
    end
    if ok and bar and bar.Hide then bar:Hide() end
  end
  return CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
end
-- after SetScrollChild (ForeverLFG's order): link the bar; if that fails, the wheel still scrolls by 30 px
local function LinkScrollBar(sf)
  local bar = sf.pendingBar
  if not bar then return end
  sf.pendingBar = nil
  if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
  if pcall(ScrollUtil.InitScrollFrameWithScrollBar, sf, bar) then
    sf.minimalBar = bar
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 8, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 8, 0)
    if bar.SetHideIfUnscrollable then pcall(bar.SetHideIfUnscrollable, bar, true) end
    sf:SetScript("OnMouseWheel", function(_, delta) pcall(bar.ScrollStepInDirection, bar, -delta) end)
    -- K12 (user: "shows a scroll bar but there is nothing to scroll"): the bar is a sibling of the scroll frame, so
    -- it must follow the frame's visibility itself, and only show when the content is taller than the view.
    sf:HookScript("OnShow", function(self) if self.UpdateBar then self:UpdateBar() end end)
    sf:HookScript("OnHide", function() bar:Hide() end)
  else
    bar:Hide()
    sf:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:Offset() - delta * 30) end)
  end
end

local function CreateScrollList(parent, width, height, rowHeight, createRow, updateRow, kinds)
  local sf = NewScrollFrame(parent)
  sf:SetSize(width, height)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(width, 1)
  sf:SetScrollChild(content)
  LinkScrollBar(sf)
  sf.content = content
  sf.rows, sf.pools, sf.rowY, sf.viewW, sf.viewH, sf.contentH = {}, {}, {}, width, height, 0
  function sf:SetData(data)
    local used, nRows, y = {}, 0, 0
    self.data = data
    self.rowY = {}
    for _, d in ipairs(data) do
      local kind = kinds and d.rowKind and kinds[d.rowKind]
      local row, h, update, n
      if kind then
        local pool = self.pools[d.rowKind]
        if not pool then pool = {}; self.pools[d.rowKind] = pool end
        n = (used[d.rowKind] or 0) + 1
        used[d.rowKind] = n
        row = pool[n]
        if not row then row = kind.create(content); pool[n] = row end
        h, update = kind.height, kind.update
      else
        nRows = nRows + 1
        n = nRows
        row = self.rows[nRows]
        if not row then row = createRow(content); self.rows[nRows] = row end
        h, update = rowHeight, updateRow
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -y)
      row:SetPoint("RIGHT", content, "RIGHT")
      row.data = d
      -- n: position among the rows of this kind (K1: alternating shading); K5: + the entry's index and the list
      update(row, d, n, #self.rowY + 1, data)
      -- K1: a kind may measure its height after the update (the wrapped "no upgrade" line)
      if type(h) == "function" then
        h = h(row, d)
        row:SetHeight(h - 2)
      end
      self.rowY[#self.rowY + 1] = { y, h }
      row:Show()
      y = y + h
    end
    for i = nRows + 1, #self.rows do self.rows[i]:Hide() end
    for k, pool in pairs(self.pools) do
      for i = (used[k] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.contentH = y
    content:SetHeight(math.max(1, y))
    self:UpdateBar()
  end
  -- K12: the scroll bar only while this list is shown and its content is taller than the view; else it is hidden
  -- (and the list scrolled back to the top).
  function sf:UpdateBar()
    local bar = self.minimalBar
    if not bar then return end
    local need = (self.contentH or 0) > (self.viewH or 0) + 0.5
    local shown = self.IsVisible and self:IsVisible() or (self.IsShown and self:IsShown())
    bar:SetShown(need and shown and true or false)
    if not need and (self.scrolledTo or 0) > 0 then self:ScrollTo(0) end
  end
  -- Scrolls to offset y (clamped to the content). Through the template's scroll bar when it has one (keeps
  -- the thumb in step), else SetVerticalScroll. Returns the offset.
  function sf:ScrollTo(y)
    y = math.max(0, math.min(y, (self.contentH or 0) - (self.viewH or 0)))
    local bar = self.ScrollBar
    if type(bar) == "table" and type(bar.SetValue) == "function" then
      pcall(bar.SetValue, bar, y)
    elseif self.SetVerticalScroll then
      pcall(self.SetVerticalScroll, self, y)
    end
    self.scrolledTo = y
    return y
  end
  -- K2: y offset of the first entry for which match(d) is true (nil when none)
  function sf:FindY(match)
    for i, d in ipairs(self.data or {}) do
      if match(d) and self.rowY[i] then return self.rowY[i][1] end
    end
  end
  -- current scroll offset: the frame's own when it has one (mouse wheel / scroll bar), else our last ScrollTo
  function sf:Offset()
    local v = self.GetVerticalScroll and SafeCall(self.GetVerticalScroll, self)
    if type(v) == "number" and not GCA.IsSecret(v) then return v end
    return self.scrolledTo or 0
  end
  -- entries fully inside the view at the current offset
  function sf:VisibleRows()
    local top = self:Offset()
    local bottom, n = top + (self.viewH or 0), 0
    for _, r in ipairs(self.rowY) do
      if r[1] >= top and r[1] + r[2] <= bottom then n = n + 1 end
    end
    return n
  end
  -- J2: new view size. The content takes the new width (rows are anchored to its right edge); with relayout
  -- the rows are rebuilt from the last data (section headers split their width by it); the offset is clamped
  -- to the new scroll range.
  function sf:Resize(w, h, relayout)
    self:SetSize(w, h)
    content:SetWidth(w)
    self.viewW, self.viewH = w, h
    if relayout and self.data then self:SetData(self.data) end
    local maxY = math.max(0, (self.contentH or 0) - h)
    if self:Offset() > maxY then self:ScrollTo(maxY) end
    self:UpdateBar()
  end
  return sf
end

---------------------------------------------------------------------------
-- Member list rows (K2: two lines - name, level and badge; below it the best craft you know for them) and
-- collapsible groups ("Not recorded (n)", "Offline (n)"). Group state is per session only (nothing saved).
---------------------------------------------------------------------------
UI.collapsed = { online = false, offline = true }

-- The badge of a member (kept for the tooltips / older callers; the K5 rows show the big gain instead).
local function MemberBadge(d)
  local count = d.knownCount or 0 -- only recipes you know count (G7.11)
  if not d.member then return C.dim .. "–|r" end
  if d.state == "no-spec" then return C.warn .. "spec?|r" end
  if d.state == "no-level" then return C.warn .. "lvl?|r" end
  if d.browse then return C.browse .. "·|r" end
  if count > 0 and d.best then return C.upgrade .. UI.GainNum(d.best.points) .. "|r" end
  if count > 0 then return C.upgrade .. "+" .. count .. "|r" end
  return C.dim .. "0|r"
end
UI.MemberBadge = MemberBadge

-- K5 (Member mockup): second line of a member row = "3 upgrades · best: Chest", else why there is none
local function MemberLine(d)
  if not d.member then return C.dim .. L.MEMBER_TIP_NOT_INSPECTED .. "|r" end
  if d.browse then return C.browse .. string.format(L.MEMBER_LINE_BROWSE, d.suggestions and #d.suggestions or 0) .. "|r" end
  if d.best then
    local n = d.knownCount or 0
    if n == 1 then return string.format(L.MEMBER_LINE_UPGRADES_1, n, ShortSlotName(d.best.slot)) end
    return string.format(L.MEMBER_LINE_UPGRADES, n, ShortSlotName(d.best.slot))
  end
  if d.state == "no-spec" then return C.warn .. L.MEMBER_LINE_NOSPEC .. "|r" end
  if d.state == "no-level" then return C.warn .. L.MEMBER_LINE_NOLEVEL .. "|r" end
  if d.state == "loading" then return C.dim .. L.MEMBER_LINE_LOADING .. "|r" end
  return C.dim .. L.MEMBER_LINE_NONE .. "|r"
end
UI.MemberLine = MemberLine

-- K5: the big gain on the right of a member row ("+8.4", the member's AP/SP-equivalents); "" without one
local function MemberGain(d)
  if d.browse or not d.best then return "" end
  return UI.GainNum(d.best.points)
end
UI.MemberGain = MemberGain

UI.MEMBER_GAIN_W = 46
local MEMBER_TEXT_X = 22 -- K8: the recipe row's label indent (the category text sits at 8)
-- K8: the recipe list row's own art (probe tpl:ProfessionsRecipeListRecipeTemplate): HighlightOverlay =
-- Professions_Recipe_Hover (HIGHLIGHT, alpha 0.5) and SelectedOverlay = Professions_Recipe_Active (OVERLAY), both
-- centred on the row at 0,-1 with the atlas height (21 / 19); across the row's width (the client's rows are as wide
-- as the list). Without the atlases: the role's file / colour over the whole row. Sets b.hl, b.sel, b.selKind.
function UI.AddRowArt(b)
  local function place(tex, role)
    local kind = UI.Skin(tex, role)
    local size = UI.SKIN[role].size
    if kind == "atlas" and size then
      tex:SetPoint("LEFT", b, "LEFT", 0, -1)
      tex:SetPoint("RIGHT", b, "RIGHT", 0, -1)
      tex:SetHeight(size[2])
    else
      tex:SetAllPoints()
    end
    return kind
  end
  b.sel = b:CreateTexture(nil, "OVERLAY")
  b.selKind = place(b.sel, "rowSelected")
  b.sel:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hlKind = place(b.hl, "rowHover")
end
-- K8: a recipe row's label font (GameFontHighlight_NoShadow, white), from GameFontHighlight where it is missing
function UI.RowFont(fs)
  NativeFont(fs, "GameFontHighlight_NoShadow")
  return fs
end
-- K8 (native rows, as the recipe list): ONE plain text line per member: the name in class colour + the level in
-- grey, the best gain right in the client's green; hover / selected = the recipe row's own art. No class icon, no
-- second line (it moved into the tooltip), no boxes.
local function CreateMemberRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(MEMBER_ROW_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.AddRowArt(b)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.gain:SetWidth(UI.MEMBER_GAIN_W)
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  b.name = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.name:SetPoint("LEFT", b, "LEFT", MEMBER_TEXT_X, 0)
  b.name:SetJustifyH("LEFT")
  SingleLine(b.name)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" and IsShiftKeyDown() and self.data.member and not self.data.isSelf then
      GCA.db.members[self.data.key] = nil
      GCA.Print(string.format(L.FORGOT, self.data.key))
    else
      UI.selected = self.data.key
      UI.autoKey = nil -- a pick of yours: no more automatic selection (U1)
    end
    UI:Refresh()
  end)
  SetTip(b, "member row", function(self)
    local d = self.data
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.key, ClassColor(d.class))
    local status = d.isSelf and "" or (d.online and G("FRIENDS_LIST_ONLINE") or (C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"))
    GameTooltip:AddLine(string.format(L.MEMBER_TIP_LEVEL, G("LEVEL"), tostring(d.level or "?"), ClassName(d.class)) .. (status ~= "" and ("  ·  " .. status) or ""), 1, 1, 1)
    GameTooltip:AddLine(MemberLine(d), SUB_TINT[1], SUB_TINT[2], SUB_TINT[3]) -- K8: the former second line
    if d.member then
      GameTooltip:AddLine(string.format(L.MEMBER_TIP_GEAR, SourceText(d.member), Ago(d.member.time)), 0.7, 0.7, 0.7)
      GameTooltip:AddLine(string.format(L.MEMBER_TIP_SPEC, SpecHowText(d)), 1, 1, 1)
      if d.browse then
        GameTooltip:AddLine(string.format(L.MEMBER_TIP_BROWSE, ProfName(d.prof), d.suggestions and #d.suggestions or 0), 0.7, 0.7, 0.7)
      elseif d.best then
        GameTooltip:AddLine(string.format(L.MEMBER_TIP_BEST, d.knownCount or 0, GainText(d.best)), 0.3, 1, 0.3)
      elseif d.state == "no-spec" then
        GameTooltip:AddLine(L.MEMBER_TIP_NOSPEC, 1, 0.5, 0.2)
      elseif d.state == "no-level" then
        GameTooltip:AddLine(L.MEMBER_TIP_NOLEVEL, 1, 0.5, 0.2)
      else
        GameTooltip:AddLine(L.MEMBER_TIP_NONE, 0.7, 0.7, 0.7)
      end
      if not d.isSelf then GameTooltip:AddLine(L.MEMBER_TIP_FORGET, 0.5, 0.5, 0.5) end
    else
      GameTooltip:AddLine(L.MEMBER_TIP_NOT_INSPECTED, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- User 2026-11-15: member names always in class colour, with the friends list's online/offline dot in front
-- (Interface\FriendsFrame\StatusIcon-Online / -Offline) instead of a greyed or dimmed name.
function UI.StatusDot(online)
  return online and "|TInterface\\FriendsFrame\\StatusIcon-Online:12:12:0:0|t"
    or "|TInterface\\FriendsFrame\\StatusIcon-Offline:12:12:0:0|t"
end
-- offline: the class colour, half-way to its own grey and a bit darker (still recognisable, clearly quieter)
function UI.OfflineColor(r, g, b)
  local l = 0.3 * r + 0.59 * g + 0.11 * b
  return (r + l) * 0.4, (g + l) * 0.4, (b + l) * 0.4
end
function UI.MemberName(m)
  local online = m.online or m.isSelf
  local r, g, b = ClassColor(m.class)
  if not online then r, g, b = UI.OfflineColor(r, g, b) end
  return UI.StatusDot(online) .. " " .. Hex(r, g, b) .. tostring(m.key or "?") .. "|r"
end

local function UpdateMemberRow(b, d, n)
  local offline = not d.online and not d.isSelf
  b.name:SetText(UI.MemberName(d) .. "  " .. C.muted .. tostring(d.level or "?") .. "|r"
    .. (d.isSelf and (" " .. C.dim .. "(" .. L.YOU .. ")|r") or ""))
  b.gain:SetText(MemberGain(d))
  local rowW = UI.memberListW or (LEFT_W - 30)
  local textW = math.max(40, rowW - MEMBER_TEXT_X - UI.MEMBER_GAIN_W - 10)
  b.name:SetWidth(textW)
  b.textW = textW
  -- offline: the grey dot says it (the name keeps its class colour, no dimming); a best craft that is too high
  -- level yet: its gain dimmed
  b.name:SetAlpha(1)
  b.gain:SetAlpha((d.best and d.best.future) and 0.55 or 1)
  local on = UI.selected == d.key
  b.sel:SetShown(on)
  b.offline = offline
end

-- K5 (Member mockup): only members with recorded gear (and you); "Online n" and "Offline n" as quiet collapsible
-- headers (no "Not recorded" group). query: member search (plain text, ASCII case-insensitive).
function UI.MemberRows(members, query)
  local q = tostring(query or ""):lower():match("^%s*(.-)%s*$") or ""
  local online, offline = {}, {}
  for _, e in ipairs(members or {}) do
    if (e.isSelf or e.member) and (q == "" or tostring(e.key):lower():find(q, 1, true)) then
      if e.isSelf or e.online then online[#online + 1] = e else offline[#offline + 1] = e end
    end
  end
  local out = {}
  local function group(key, list)
    if #list == 0 then return end
    out[#out + 1] = { rowKind = "group", group = key, count = #list, list = "members" }
    if not UI.collapsed[key] then for _, e in ipairs(list) do out[#out + 1] = e end end
  end
  group("online", online)
  group("offline", offline)
  return out
end

-- Collapsible group headers of the member list ("Online" / "Offline"). K6 created the client's
-- ProfessionsRecipeListCategoryTemplate itself; K8 replicates its regions instead (UI.CreateCategoryRow below; the
-- mixin expects profession tree nodes). KeepNativeHover stays for the native dropdowns.
local GROUP_TIP = { online = "GROUP_TIP_ONLINE", offline = "GROUP_TIP_OFFLINE" }
local function GroupLabel(key)
  if key == "online" then return G("FRIENDS_LIST_ONLINE") end
  return G("FRIENDS_LIST_OFFLINE")
end

local function GroupTip(self)
  local d = self.data
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(GroupLabel(d.group) .. " (" .. tostring(d.count) .. ")", 1, 1, 1)
  GameTooltip:AddLine(L[GROUP_TIP[d.group] or "GROUP_TIP_OFFLINE"], nil, nil, nil, true)
  GameTooltip:Show()
end

-- a template made outside its scroll box: keep its own OnEnter/OnLeave (hover look), each in pcall, then ours
local function KeepNativeHover(b, name, tip)
  local onEnter, onLeave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
  SetTip(b, name, function(self)
    if onEnter then pcall(onEnter, self) end
    tip(self)
  end)
  b:SetScript("OnLeave", function(self)
    if onLeave then pcall(onLeave, self) end
    GameTooltip_Hide()
  end)
end

-- K8: the category header, replicated region by region from the probe (tpl:ProfessionsRecipeListCategoryTemplate):
-- a 25 px Button; ButtonText = Game15Font_Shadow in gold (1, 0.82, 0) at LEFT 8,0; common-button-list-collapseExpand
-- on ARTWORK over the whole button and again on HIGHLIGHT (ADD, alpha 0.4); CollapseButton 20x20 at RIGHT -6,0 with
-- its Icon centred (atlas: UI.SKIN.collapseIcon candidates, else a gold "–" / "+" in GameFontNormal). The template
-- itself is NOT created: its mixin expects profession tree nodes. No count, no rank bar (hidden in our lists).
-- b:SetCategory(text, open); b.onToggle(b) runs on a click on the header or its button.
function UI.CollapseAtlases()
  if UI.collapsePair ~= nil then return UI.collapsePair or nil end
  UI.collapsePair = false
  for _, pair in ipairs(UI.SKIN.collapseIcon.pairs or {}) do
    if HasAtlas(pair[1]) and HasAtlas(pair[2]) then UI.collapsePair = pair; break end
  end
  return UI.collapsePair or nil
end
function UI.CreateCategoryRow(parent, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(GROUP_ROW_H - 2)
  b.bg = b:CreateTexture(nil, "ARTWORK")
  b.bg:SetAllPoints()
  b.bgKind = UI.Skin(b.bg, "category")
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  UI.Skin(b.hl, "categoryHover")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.text:SetJustifyH("LEFT")
  NativeFont(b.text, "Game15Font_Shadow")
  b.text:SetTextColor(1, 0.82, 0)
  SingleLine(b.text)
  local cb = CreateFrame("Button", nil, b)
  cb:SetSize(20, 20)
  cb:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  cb.Icon = cb:CreateTexture(nil, "ARTWORK")
  cb.Icon:SetPoint("CENTER", cb, "CENTER", 0, 0)
  cb.hl = cb:CreateTexture(nil, "HIGHLIGHT")
  cb.hl:SetAllPoints(cb.Icon)
  if cb.hl.SetBlendMode then pcall(cb.hl.SetBlendMode, cb.hl, "ADD") end
  cb.hl:SetAlpha(0.4)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cb.text:SetPoint("CENTER", cb, "CENTER", 0, 0)
  cb.text:SetTextColor(1, 0.82, 0)
  b.CollapseButton = cb
  b.onToggle = onToggle
  local function toggle() if b.onToggle then b.onToggle(b) end end
  b:SetScript("OnClick", toggle)
  cb:SetScript("OnClick", toggle)
  function b:SetCategory(text, open)
    self.text:SetText(text)
    self.text:SetWidth(math.max(20, (self.rowW or (LEFT_W - 30)) - 8 - 32))
    self.open = open and true or false
    local pair = UI.CollapseAtlases()
    if pair and SetAtlasSafe(self.CollapseButton.Icon, pair[open and 1 or 2], true) then
      SetAtlasSafe(self.CollapseButton.hl, pair[open and 1 or 2], true)
      self.CollapseButton.Icon:Show(); self.CollapseButton.hl:Show()
      self.CollapseButton.text:SetText("")
      UI.collapseIconKind = "atlas:" .. pair[1]
    else
      self.CollapseButton.Icon:Hide(); self.CollapseButton.hl:Hide()
      self.CollapseButton.text:SetText(open and "–" or "+")
      UI.collapseIconKind = "text"
    end
  end
  return b
end

-- member list groups ("Online" / "Offline") on the K8 category header
local function CreateGroupRow(parent)
  local b = UI.CreateCategoryRow(parent, function(self)
    local d = self.data
    UI.collapsed[d.group] = not UI.collapsed[d.group]
    UI:RefreshMemberList()
  end)
  SetTip(b, "group header", GroupTip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateGroupRow(b, d)
  local open = not UI.collapsed[d.group]
  b.rowW = UI.memberListW
  b:SetCategory(GroupLabel(d.group), open)
end

---------------------------------------------------------------------------
-- Craft rows: the suggestion rows of the member view and the rows of the guild-needs view share one build
-- (icon, title, tinted sub-line, gain, Offer icon, crafted box). RowCtx tells a row's suggestion and member.
---------------------------------------------------------------------------
local function ShiftDown()
  return IsShiftKeyDown and SafeCall(IsShiftKeyDown) and true or false
end

local function RowCtx(b)
  local d = b and b.data
  if d and d.rowKind == "need" then return d.sug, d.member end
  return d, UI.current
end
UI.RowCtx = RowCtx


---------------------------------------------------------------------------
-- K7: where to get a recipe you don't know. The sibling addon CraftersJournal (optional; installed by the user, no
-- license file, so NOTHING of its data is copied here) is read at use time only, never at file load: the pattern
-- item per recipe (CraftersJournal.Data.<Profession>.recipes[spellID].scroll / scrollPrice / fee / trainer / rep /
-- favor) and its Waypoints module (CJ Waypoints.lua: NPC, ZoneName, NPCLevel, Vendors, Usable, Nearest, QuestsFor,
-- Drops, Trainers, SetWaypoint - the same calls its own Collection.lua / CollectionUI.lua make for "where to get").
-- Every access is in pcall and type-checked; CJ missing, renamed or erroring -> our coarse label (Data src field).
-- Built per (profession, recipe), cached 30 s (the nearest vendor depends on where you stand).
---------------------------------------------------------------------------
local Src = { TTL = 30, cache = {}, at = nil }
UI.Src = Src
C.notLearned = "|cff9d9d9d" -- K7: the grey "Not learned" tag (the profession list greys unlearned recipes)
C.notLearnedTag = "|cffff4040" -- user 2026-11-15: the cards' "Not learned" button, red (grey wasn't visible enough)
do -- K7 helpers in a block (UI.lua's main chunk is near Lua's 200-locals limit)

local function Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end
Src.Try = Try

-- CJ's namespace, its Data and Waypoints tables, or nil
function Src.CJ()
  local ok, cj, data, wp = pcall(function()
    local cj = _G["CraftersJournal"]
    if type(cj) ~= "table" then return nil end
    return cj, cj.Data, cj.Waypoints
  end)
  if ok and type(cj) == "table" and type(data) == "table" and type(wp) == "table" then return cj, data, wp end
  return nil
end

local function Num01(v) return type(v) == "number" and v >= 0 and v <= 1 end

-- { id, name, zone?, level?, map?, x?, y? } of a CJ NPC (map/x/y only when CJ has real coordinates)
local function NpcInfo(wp, id)
  if type(id) ~= "number" then return nil end
  local npc = Try(wp.NPC, id)
  if type(npc) ~= "table" or type(npc.name) ~= "string" then return nil end
  local n = { id = id, name = npc.name }
  if type(npc.map) == "number" and Num01(npc.x) and Num01(npc.y) then n.map, n.x, n.y = npc.map, npc.x, npc.y end
  local zone = Try(wp.ZoneName, npc)
  if type(zone) == "string" and zone ~= "" then n.zone = zone end
  local lv = Try(wp.NPCLevel, id)
  if type(lv) == "string" then n.level = lv end
  return n
end

-- the nearest of these NPCs (CJ's choice; the first when it can't tell)
local function NearestNpc(wp, ids)
  if type(ids) ~= "table" or type(ids[1]) ~= "number" then return nil end
  local id = Try(wp.Nearest, ids)
  if type(id) ~= "number" then id = ids[1] end
  return NpcInfo(wp, id)
end

local function StandingName(cj, n)
  local v = type(n) == "number" and _G["FACTION_STANDING_LABEL" .. n]
  if type(v) == "string" and v ~= "" and not GCA.IsSecret(v) then return v end
  v = Try(cj.StandingName, n)
  return type(v) == "string" and v or tostring(n)
end

local function FactionName(cj, id)
  local v = Try(cj.FactionName, cj, id)
  if type(v) == "string" and v ~= "" then return v end
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local d = Try(C_Reputation.GetFactionDataByID, id)
    if type(d) == "table" and type(d.name) == "string" then return d.name end
  end
  return "#" .. tostring(id)
end

-- info = { list = { sources in CJ's priority order: trainer, quest, vendor (incl. Merchant's Favor), drop / world /
-- objects }, coarse = our src, skill, have = your rank (nil: you don't have the profession), cj = CJ knew the
-- recipe, scroll = pattern itemID, rep = { standing, name, met }, canWaypoint }
function Src.Build(prof, spellID, recipe)
  recipe = type(recipe) == "table" and recipe or {}
  local info = { list = {}, coarse = recipe.src or "other", skill = tonumber(recipe.skill) or 0 }
  local own = GCA:OwnProfessions()
  local mine = type(own) == "table" and own[prof]
  info.have = type(mine) == "table" and tonumber(mine.rank) or nil
  local cj, data, wp = Src.CJ()
  local r
  if cj then
    local ok, v = pcall(function() return data[prof].recipes[spellID] end)
    if ok and type(v) == "table" then r = v end
  end
  info.cj = r ~= nil
  local list = info.list
  if r then
    if r.fee or r.trainer or r.basic then
      list[#list + 1] = { kind = "trainer", cost = tonumber(r.fee),
        npc = NearestNpc(wp, (Try(wp.Trainers, prof, info.skill > 0 and info.skill or 1))) }
    end
    local scroll = tonumber(r.scroll)
    info.scroll = scroll
    if scroll then
      local quests = Try(wp.QuestsFor, scroll)
      for _, q in ipairs(type(quests) == "table" and quests or {}) do
        if type(q) == "table" and type(q.name) == "string" then
          list[#list + 1] = { kind = "quest", name = q.name, level = tonumber(q.level), npc = NearestNpc(wp, q.starters) }
        end
      end
      local vendors = Try(wp.Vendors, scroll)
      if type(vendors) == "table" and vendors[1] then
        local usable = Try(wp.Usable, vendors)
        usable = type(usable) == "table" and usable or {}
        local s = { kind = "vendor", cost = tonumber(r.scrollPrice), favor = tonumber(r.favor), count = #usable }
        s.npc = NearestNpc(wp, usable)
        s.otherSide = s.npc == nil
        list[#list + 1] = s
      end
      local d = Try(wp.Drops, scroll)
      if type(d) == "table" then
        local npcs = type(d.npcs) == "table" and d.npcs or {}
        if type(npcs[1]) == "number" then
          local s = { kind = "drop", count = #npcs, npc = NearestNpc(wp, npcs), npcs = {} }
          for i = 1, math.min(#npcs, 6) do
            local n = NpcInfo(wp, npcs[i])
            if n then s.npcs[#s.npcs + 1] = n end
          end
          s.npc = s.npc or s.npcs[1]
          if s.npc then list[#list + 1] = s end -- creatures CJ can't name: no "Drop: ?" line
        elseif tonumber(d.world) then
          local lv = type(d.levels) == "table" and tonumber(d.levels[1]) and tonumber(d.levels[2]) and d.levels or nil
          list[#list + 1] = { kind = "world", count = tonumber(d.world), levels = lv }
        elseif tonumber(d.objects) then
          list[#list + 1] = { kind = "objects", count = tonumber(d.objects) }
        end
      end
    end
    if type(r.rep) == "table" and r.rep[1] then
      local met = Try(cj.RepMet, cj, r.rep)
      info.rep = { standing = StandingName(cj, r.rep[2]), name = FactionName(cj, r.rep[1]), met = met }
    end
  elseif info.coarse == "trainer" then
    list[1] = { kind = "trainer" }
  end
  for _, s in ipairs(list) do if s.npc and s.npc.map then info.canWaypoint = true end end
  return info
end

-- cached; a CJ error anywhere -> the coarse info (never an error in the row or tooltip)
function Src.Get(prof, spellID, recipe)
  local now = GetTime()
  if not Src.at or now - Src.at > Src.TTL then Src.cache, Src.at = {}, now end
  local key = tostring(prof) .. ":" .. tostring(spellID)
  local v = Src.cache[key]
  if v == nil then
    local ok, res = pcall(Src.Build, prof, spellID, recipe)
    if ok and type(res) == "table" then
      v = res
    else
      local rc = type(recipe) == "table" and recipe or {}
      v = { list = {}, coarse = rc.src or "other", skill = tonumber(rc.skill) or 0, failed = true }
      if v.coarse == "trainer" then v.list[1] = { kind = "trainer" } end
    end
    Src.cache[key] = v
  end
  return v
end
function Src.Reset() Src.cache, Src.at = {}, nil end

-- the sources of a suggestion's recipe; nil for a known recipe
function UI.SourceInfo(d, cur)
  if type(d) ~= "table" or d.known or type(d.cand) ~= "table" then return nil end
  local prof = cur and cur.prof or GCA:SelectedProfession()
  return Src.Get(prof, d.cand.spellID, d.cand.recipe)
end

-- one source as a short text: "Vendor: Androd Fadran (Arathi Highlands)", "Trainer (skill 170, you have 150)"
function Src.LineOf(s, info)
  local k = s.kind
  if k == "trainer" then
    local sk = info.skill or 0
    if info.have and sk > 0 then
      if info.have >= sk then return string.format(L.SRC_LINE_TRAINER_OK, sk) end
      return string.format(L.SRC_LINE_TRAINER_HAVE, sk, info.have)
    end
    return string.format(L.SRC_LINE_TRAINER, sk)
  elseif k == "vendor" then
    if not s.npc then return L.SRC_LINE_VENDOR_OTHER end
    local t = s.npc.zone and string.format(L.SRC_LINE_VENDOR, s.npc.name, s.npc.zone) or string.format(L.SRC_LINE_VENDOR_NOZONE, s.npc.name)
    if s.favor then t = t .. " · " .. string.format(L.SRC_LINE_FAVOR, s.favor) end
    return t
  elseif k == "quest" then
    if s.level and s.level > 0 then return string.format(L.SRC_LINE_QUEST_LVL, s.name, s.level) end
    return string.format(L.SRC_LINE_QUEST, s.name)
  elseif k == "drop" then
    local n = s.npc
    local name, zone = n and n.name or "?", n and n.zone or "?"
    if (s.count or 1) > 1 then return string.format(L.SRC_LINE_DROP_N, name, zone, s.count - 1) end
    return string.format(L.SRC_LINE_DROP, name, zone)
  elseif k == "world" then
    if s.levels then return string.format(L.SRC_LINE_WORLD_LVL, s.levels[1], s.levels[2]) end
    return L.SRC_LINE_WORLD
  elseif k == "objects" then
    return string.format(L.SRC_LINE_OBJECTS, s.count or 0)
  end
  return L.SRC_LINE_OTHER
end

-- the row's source line: the first (best) source + "+n more"; without any: the coarse label
function Src.Line(info)
  if type(info) ~= "table" then return nil end
  local list = info.list or {}
  local text
  if list[1] then
    text = Src.LineOf(list[1], info)
  else
    text = info.coarse == "pattern" and L.SRC_LINE_PATTERN or L.SRC_LINE_OTHER
  end
  if #list > 1 then text = text .. "  " .. C.muted .. string.format(L.SRC_LINE_MORE, #list - 1) .. "|r" end
  return text
end
function UI.SourceLine(d, cur) return Src.Line(UI.SourceInfo(d, cur)) end

local function Money(c)
  c = tonumber(c)
  if not c or c <= 0 then return nil end
  local s = Try(GetCoinTextureString, c)
  if type(s) == "string" and s ~= "" then return s end
  local g, si, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if si > 0 then parts[#parts + 1] = si .. "s" end
  if k > 0 then parts[#parts + 1] = k .. "c" end
  return table.concat(parts, " ")
end
Src.Money = Money

-- "Arathi Highlands 45, 60" (coordinates only when CJ has them)
local function Loc(n)
  if not n then return "" end
  if n.map then return string.format("%s %.0f, %.0f", n.zone or "", n.x * 100, n.y * 100) end
  return n.zone or ""
end
Src.Loc = Loc

-- the tooltip block: every source with zone / coordinates, cost, reputation, the pattern item, the click hints
-- (hint: the waypoint click hint for the caller's own button instead of SRC_TIP_WAYPOINT)
function Src.AddTooltip(info, hint)
  if type(info) ~= "table" then return end
  local T = GameTooltip
  T:AddLine(" ")
  T:AddLine(L.SRC_TIP_HEAD, 1, 0.82, 0)
  local function npcLine(n, label)
    if n then T:AddDoubleLine("  " .. (label or n.name), Loc(n), 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end
  end
  local function costLine(label, c)
    local m = Money(c)
    if m then T:AddDoubleLine("  " .. label, m, 0.85, 0.85, 0.85, 1, 1, 1) end
  end
  for _, s in ipairs(info.list or {}) do
    if s.kind == "trainer" then
      local have = ""
      if info.have then have = info.have >= (info.skill or 0) and L.SRC_TIP_REACHED or string.format(L.SRC_TIP_HAVE, info.have) end
      T:AddDoubleLine(string.format(L.SRC_TIP_TRAINER, info.skill or 0), have, 1, 1, 1, 0.7, 0.7, 0.7)
      npcLine(s.npc)
      costLine(L.SRC_TIP_FEE, s.cost)
    elseif s.kind == "vendor" then
      T:AddDoubleLine(s.npc and string.format(L.SRC_LINE_VENDOR_NOZONE, s.npc.name) or L.SRC_LINE_VENDOR_OTHER, Loc(s.npc), 1, 1, 1, 0.6, 0.6, 0.6)
      if s.favor then T:AddLine("  " .. string.format(L.SRC_LINE_FAVOR, s.favor), 0.4, 0.7, 1) end
      costLine(L.SRC_TIP_COST, s.cost)
      if (s.count or 0) > 1 then T:AddLine("  " .. string.format(L.SRC_TIP_VENDORS_MORE, s.count - 1), 0.6, 0.6, 0.6) end
    elseif s.kind == "quest" then
      T:AddLine(Src.LineOf(s, info), 1, 0.82, 0)
      npcLine(s.npc)
    elseif s.kind == "drop" then
      for _, n in ipairs(s.npcs or {}) do
        T:AddDoubleLine(string.format(L.SRC_TIP_DROP, n.name .. (n.level and (" (" .. n.level .. ")") or "")), Loc(n), 1, 1, 1, 0.6, 0.6, 0.6)
      end
      if (s.count or 0) > #(s.npcs or {}) then
        T:AddLine("  " .. string.format(L.SRC_TIP_DROPS_MORE, s.count - #(s.npcs or {})), 0.6, 0.6, 0.6)
      end
    else
      T:AddLine(Src.LineOf(s, info), 1, 1, 1)
    end
  end
  if not (info.list and info.list[1]) then
    T:AddLine(info.cj and L.SRC_TIP_UNKNOWN or Src.Line(info), 0.7, 0.7, 0.7)
  end
  if info.rep then
    local ok = info.rep.met
    T:AddLine(string.format(L.SRC_TIP_REP, info.rep.standing, info.rep.name), ok and 0.3 or 1, ok and 1 or 0.3, 0.3, true)
  end
  if info.scroll then T:AddLine(string.format(L.SRC_TIP_PATTERN, ItemName(info.scroll)), 0.8, 0.8, 0.8) end
  if not info.cj and not Src.CJ() then T:AddLine(L.SRC_TIP_NO_CJ, 0.5, 0.5, 0.5, true) end
  if info.canWaypoint then T:AddLine(hint or L.SRC_TIP_WAYPOINT, 0.5, 0.8, 1) end
  if info.scroll then T:AddLine(L.SRC_TIP_LINK, 0.5, 0.8, 1) end
end

-- waypoint to a CJ NPC: CJ's own helper first (Shortest Path Forever / TomTom / the map's user waypoint, it prints
-- where); without it (or when it errors) the client's user waypoint + super-tracking, each guarded. Only ever for
-- coordinates CJ gave (n.map/x/y); none invented.
function Src.SetWaypoint(n)
  if not (type(n) == "table" and n.map and n.x and n.y) then return false end
  local _, _, wp = Src.CJ()
  if wp and type(wp.SetWaypoint) == "function" and n.id then
    local ok, done = pcall(wp.SetWaypoint, n.id)
    if ok then return done and true or false end
  end
  local ok = pcall(function()
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then error("no waypoint API") end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(n.map) then error("map refuses waypoints") end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(n.map, n.x, n.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  if ok then GCA.Print(string.format(L.SRC_WAYPOINT_SET, n.name, Loc(n))) else GCA.Print(string.format(L.SRC_WAYPOINT_FAIL, n.name)) end
  return ok
end

-- K14 (user: "jump to the location on the map"): waypoint + open the world map on the NPC's zone, so the pin is
-- right there. Map opening: OpenWorldMap(uiMapID) when the client has it, else WorldMapFrame + SetMapID; guarded
-- (in combat the map may refuse to open - the waypoint is set anyway).
function Src.ShowOnMap(n)
  if not (type(n) == "table" and n.map and n.x and n.y) then return false end
  local set = Src.SetWaypoint(n)
  local opened = false
  if type(OpenWorldMap) == "function" then opened = pcall(OpenWorldMap, n.map) end
  if not opened and WorldMapFrame then
    opened = pcall(function()
      if not WorldMapFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) else WorldMapFrame:Show() end
      end
      if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(n.map) end
    end)
  end
  return set, opened
end

-- the pattern item into chat (Shift held: the client's own modified click; else the open / a new chat box)
function Src.LinkPattern(scroll)
  local API = GCA.ItemAPI
  local _, link = Try(API.Info, scroll)
  if type(link) ~= "string" or GCA.IsSecret(link) then
    Try(API.Request, scroll)
    GCA.Print(L.SRC_LINK_LOADING)
    return false
  end
  if ShiftDown() and HandleModifiedItemClick then return (pcall(HandleModifiedItemClick, link)) end
  if CFU and CFU.InsertLink then
    local ok, done = pcall(CFU.InsertLink, link)
    if ok and done then return true end
  end
  local open = (CFU and CFU.OpenChat) or ChatFrame_OpenChat
  if open then return (pcall(open, link)) end
  return false
end

local KIND_WORD = { trainer = "SRC_KIND_TRAINER", vendor = "SRC_KIND_VENDOR", quest = "SRC_KIND_QUEST", drop = "SRC_KIND_DROP" }
-- right-click menu entries: a waypoint per source CJ has coordinates for, then "Link pattern"
function Src.MenuEntries(info)
  local out = {}
  for _, s in ipairs(type(info) == "table" and info.list or {}) do
    local n = s.npc
    if n and n.map and KIND_WORD[s.kind] then
      out[#out + 1] = { label = string.format(L.SRC_MENU_WAYPOINT, n.name, L[KIND_WORD[s.kind]]), waypoint = n,
        fn = function() Src.ShowOnMap(n) end }
    end
  end
  if type(info) == "table" and info.scroll then
    out[#out + 1] = { label = L.SRC_MENU_LINK, fn = function() Src.LinkPattern(info.scroll) end }
  end
  return out
end

-- MenuUtil.CreateContextMenu (guarded); without it the first entry runs directly. false = nothing to offer.
function Src.Menu(owner, info, title)
  local entries = Src.MenuEntries(info)
  if #entries == 0 then return false end
  if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
    local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      if title and root.CreateTitle then root:CreateTitle(title) end
      for _, e in ipairs(entries) do root:CreateButton(e.label, e.fn) end
    end)
    if ok then return true end
  end
  entries[1].fn()
  return true
end

-- row OnClick hook: a right-click is ours (also on known rows, so it never runs the left-click action);
-- Shift-right-click links the pattern, else the menu. Returns true when the click was a right-click.
function UI.SourceClick(owner, button, d, cur)
  if button ~= "RightButton" then return false end
  local info = UI.SourceInfo(d, cur)
  if not info then return true end
  if ShiftDown() then
    if info.scroll then Src.LinkPattern(info.scroll) end
    return true
  end
  Src.Menu(owner, info, d.info and d.info.name)
  return true
end

-- User 2026-11-15: the "Not learned" tag on a card is a button. Hover = where to get the recipe (the source
-- tooltip block); click = a map marker on the source (one with coordinates: straight away; several: the menu);
-- right-click = the menu (all waypoints + "Link pattern").
function UI.NotLearnedTip(owner, d, cur)
  if not d then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.NOT_LEARNED, 1, 0.3, 0.3)
  if d.info and d.info.name then GameTooltip:AddLine(d.info.name, 1, 1, 1) end
  local info = UI.SourceInfo(d, cur)
  if info then Src.AddTooltip(info, L.NL_TIP_CLICK) end
  GameTooltip:Show()
end
function UI.NotLearnedClick(owner, button, d, cur)
  local info = d and UI.SourceInfo(d, cur)
  if not info then return end
  if button == "RightButton" and ShiftDown() then
    if info.scroll then Src.LinkPattern(info.scroll) end
    return
  end
  if button ~= "RightButton" then
    local wps = {}
    for _, e in ipairs(Src.MenuEntries(info)) do if e.waypoint then wps[#wps + 1] = e end end
    if #wps == 1 then wps[1].fn(); return end
  end
  Src.Menu(owner, info, d.info and d.info.name)
end
end -- K7 helpers

-- K17 (user, 2026-11-14: "it says way too much ... nothing extra"): hovering an item anywhere in the window shows ONLY
-- the plain Blizzard tooltip (SetHyperlink / SetItemByID; an enchant = its spell's tooltip). Gain, stat breakdown, set
-- hints, sources, "replaces", level notes and Offer explanations are in the rows / detail panel / sheet, not here.
-- Non-item tooltips (buttons, filter, spec, search, Offer, crafted box, source buttons) keep their texts.
-- (A field of UI, not a local: the main chunk is at Lua's 200-locals limit.)
function UI.PlainItemTip(owner, link, itemID, name, spellID)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local shown = false
  if type(link) == "string" and link:find("item:", 1, true) then
    shown = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
  end
  if not shown and itemID and GameTooltip.SetItemByID then shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
  if not shown and spellID and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) end
  if not shown then GameTooltip:SetText(name or "?") end
  GameTooltip:Show()
end

-- User 2026-11-15: hovering a craft compares it with what THAT member wears (not your own gear). The member's worn
-- item(s) go into the client's compare tooltips (ShoppingTooltip1/2) with "Equipped by <name>" on top; an empty
-- slot = one compare tooltip saying so. Blizzard's own comparison (Shift / "always compare") would put your gear
-- there: GameTooltip_ShowCompareItem and the compare tooltips' OnShow are hooked to put the member's back while
-- one of our item tooltips is up. UI.compare = { owner, list = { worn infos }, who, empty } of the open tooltip.
function UI.CompareTips()
  return { ShoppingTooltip1, ShoppingTooltip2 }
end
function UI.HideCompare()
  UI.compare = nil
  for _, tip in ipairs(UI.CompareTips()) do if tip and tip.Hide then pcall(tip.Hide, tip) end end
end
function UI.FillCompare()
  local c = UI.compare
  if not c or c.filling or not ShoppingTooltip1 then return end
  local okOwner, isOurs = pcall(function() return GameTooltip:IsShown() and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == c.owner) end)
  if not (okOwner and isOurs) then return end
  c.filling = true
  local tips, used = UI.CompareTips(), {}
  local head = string.format(L.COMPARE_WORN_BY, c.who)
  local function fill(tip, x)
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    local shown = false
    if x and type(x.link) == "string" and x.link:find("item:", 1, true) then shown = pcall(tip.SetHyperlink, tip, x.link) end
    if not shown then tip:SetText(x and x.name or L.SLOT_EMPTY_COMPARE, 1, 1, 1) end
    tip:AddLine(head, 1, 0.82, 0)
    tip:Show()
    used[#used + 1] = tip
  end
  pcall(function()
    if c.empty then
      if tips[1] then fill(tips[1], nil) end
    else
      for i, x in ipairs(c.list) do if tips[i] then fill(tips[i], x) end end
    end
    for i = #used + 1, #tips do if tips[i] then tips[i]:Hide() end end
    -- right of the item tooltip, or left when there is no room (as GearQuestForever)
    local total = 0
    for _, t in ipairs(used) do total = total + (t:GetWidth() or 0) end
    local right = GameTooltip:GetRight() or 0
    local screen = (UIParent and UIParent:GetRight()) or right
    local point, rel = "TOPLEFT", "TOPRIGHT"
    if right + total > screen - 8 then point, rel = "TOPRIGHT", "TOPLEFT" end
    local anchor = GameTooltip
    for _, t in ipairs(used) do
      t:ClearAllPoints()
      t:SetPoint(point, anchor, rel, 0, 0)
      anchor = t
    end
  end)
  c.filling = false
end
function UI.ShowWornCompare(owner, d, cur)
  UI.compare = nil
  if not (d and cur and d.kind ~= "enchant") then return end
  local list = {}
  local eq = d.equipped
  if eq and eq.pair then list = { eq.pair[1], eq.pair[2] } elseif eq then list = { eq } end
  local r, g, b = ClassColor(cur.class)
  UI.compare = { owner = owner, list = list, empty = #list == 0, who = Hex(r, g, b) .. tostring(cur.key or "?") .. "|r" }
  UI.FillCompare()
end
function UI.HookCompare()
  if UI.compareHooked then return end
  UI.compareHooked = true
  if hooksecurefunc and type(GameTooltip_ShowCompareItem) == "function" then
    pcall(hooksecurefunc, "GameTooltip_ShowCompareItem", function() UI.FillCompare() end)
  end
  for _, tip in ipairs(UI.CompareTips()) do
    if tip and tip.HookScript then pcall(tip.HookScript, tip, "OnShow", function() UI.FillCompare() end) end
  end
  if GameTooltip.HookScript then pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function() if UI.compare then UI.HideCompare() end end) end
end

-- a suggestion (craft or enchant) row/card: the crafted item's (or the enchant spell's) plain tooltip; for an item
-- the member's worn item(s) beside it (UI.ShowWornCompare)
local function ShowSuggestionTooltip(owner, d, cur)
  if not (d and d.info) then return end
  UI.HookCompare()
  if d.kind == "enchant" then
    UI.PlainItemTip(owner, nil, nil, d.info.name, d.cand and d.cand.spellID)
  else
    UI.PlainItemTip(owner, d.info.link, d.cand and d.cand.itemID, d.info.name)
  end
  UI.AddStatChanges(d, cur)
  UI.ShowWornCompare(owner, d, cur)
end

-- User 2026-11-15: under the item tooltip, the stats the member gains (green) and loses (red) against what they
-- wear now (UI.StatDiff: the same canonical stats the score uses). Nothing when a side has no stat data.
function UI.AddStatChanges(d, cur)
  local rows = UI.StatDiff(d)
  if not rows or #rows == 0 then return end
  GameTooltip:AddLine(" ")
  local who = cur and cur.key
  if who then
    local r, g, b = ClassColor(cur.class)
    GameTooltip:AddLine(string.format(L.TIP_CHANGES_FOR, Hex(r, g, b) .. who .. "|r"), 1, 0.82, 0)
  else
    GameTooltip:AddLine(L.TIP_CHANGES, 1, 0.82, 0)
  end
  for _, row in ipairs(rows) do
    if row.amount < 0 then
      GameTooltip:AddLine(UI.StatText(row), 1, 0.13, 0.13)
    else
      GameTooltip:AddLine(UI.StatText(row), 0.12, 1, 0.12)
    end
  end
  GameTooltip:Show()
end
UI.ShowSuggestionTooltip = ShowSuggestionTooltip

local function HideTip() GameTooltip_Hide() end

-- L6: the gain text sits left of whatever is shown on the right (crafted box, Offer), never over a gap.
-- gainY (K4 cards): the gain sits that much above the middle (the points line goes under it)
local function LayoutRight(b, showOffer, showCheck, gainY)
  b.offer:ClearAllPoints()
  b.offer:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local anchor, point, x = b, "RIGHT", -6
  if showOffer then anchor, point, x = b.offer, "LEFT", -4 end
  b.crafted:ClearAllPoints()
  if showCheck then
    b.crafted:SetPoint("RIGHT", anchor, point, x, 0)
    anchor, point, x = b.crafted, "LEFT", -6
  end
  b.gain:ClearAllPoints()
  b.gain:SetPoint("RIGHT", anchor, point, x, gainY or 0)
  b.gainAnchor = anchor
end

-- K4: the Offer / crafted-mark actions and their tooltips, shared by the guild-needs rows, the list cards and
-- the character sheet (one implementation; the widgets only differ in look). d = suggestion, cur = member entry.
function UI.DoOffer(d, cur)
  local who = cur and cur.key
  if not (d and who and UI.CanOffer(cur, d)) then return false end
  local msg = UI.OfferText(cur.prof or GCA:SelectedProfession(), d, who)
  if IsShiftKeyDown() then SendWhisper(who, msg) else OpenWhisper(who, msg) end
  return true
end

local function OfferTip(owner, d)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.OFFER, 1, 1, 1)
  GameTooltip:AddLine(d and d.kind == "enchant" and L.OFFER_TIP_ENCHANT or L.OFFER_TIP_CRAFT, 1, 0.82, 0)
  GameTooltip:AddLine(L.OFFER_TIP_CLICK, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_SHIFT, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_EDIT, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

function UI.DoCrafted(d, cur, on)
  if not (d and cur) then return end
  GCA:SetCrafted(cur.key, cur.prof or GCA:SelectedProfession(), d, on and true or false)
  UI:Refresh()
end

local function CraftedTip(owner, d, cur)
  if not (d and cur) then return end
  local who = FirstName(cur.key)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(d.kind == "enchant" and L.ENCHANTED or L.CRAFTED, 1, 1, 1)
  GameTooltip:AddLine(string.format(L.CRAFTED_TIP_TITLE, cur.key), 1, 0.82, 0)
  GameTooltip:AddLine(L.CRAFTED_TIP, nil, nil, nil, true)
  if d.kind == "enchant" then
    GameTooltip:AddLine(string.format(L.CRAFTED_TIP_CLEAR_ENCHANT, who, SlotName(d.slot)), nil, nil, nil, true)
  else
    GameTooltip:AddLine(string.format(L.CRAFTED_TIP_CLEAR, who), nil, nil, nil, true)
  end
  local mark = d.cand and GCA:CraftedMark(cur.key, cur.prof, d.cand.spellID)
  if mark then GameTooltip:AddLine(string.format(L.CRAFTED_TIP_SINCE, Ago(mark.t)), 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end

-- what the right side of a craft shows: Offer (online, known, not you, not browse), the crafted box (known
-- recipe or an existing mark) and the mark itself
local function RightState(d, cur)
  local showOffer = UI.CanOffer(cur, d)
  local prof = cur and cur.prof or GCA:SelectedProfession()
  local mark = cur and d.cand and GCA:CraftedMark(cur.key, prof, d.cand.spellID)
  local showCheck = cur ~= nil and not cur.browse and (d.known or mark ~= nil)
  return showOffer, showCheck, mark
end
UI.RightState = RightState

-- K6: Offer everywhere = the red UIPanelButtonTemplate button "Offer" (as the profession window's Create button;
-- K1's whisper icon is gone). Small rows (guild-needs members, the sheet's alternatives): 80 x 20.
UI.OFFER_SMALL_W = 80
local CreateOfferTextButton -- below
local function CreateOfferButton(b)
  return CreateOfferTextButton(b, b, UI.OFFER_SMALL_W, 20)
end

-- K4: the list cards' and the sheet's Offer = a text button "Offer"; same action and tooltip
CreateOfferTextButton = function(parent, row, w, h)
  local o = NewTextButton(parent, w or 84, h or 22, L.OFFER)
  o.row = row
  o:SetScript("OnClick", function(self) UI.DoOffer(RowCtx(self.row)) end)
  SetTip(o, "offer", function(self) OfferTip(self, (RowCtx(self.row))) end)
  o:SetScript("OnLeave", GameTooltip_Hide)
  return o
end

-- K4: crafted box for the list cards and the sheet (the same mark as the guild-needs rows)
local function CreateCraftedBox(parent, row)
  local cb = NewCheck(parent, 22)
  cb.row = row
  cb:SetScript("OnClick", function(self)
    local d, cur = RowCtx(self.row)
    UI.DoCrafted(d, cur, self:GetChecked())
  end)
  SetTip(cb, "crafted box", function(self) CraftedTip(self, RowCtx(self.row)) end)
  cb:SetScript("OnLeave", GameTooltip_Hide)
  return cb
end

-- K4: an item icon with a quality-coloured frame. K6: the profession window's reagent slot (probe:
-- SlotBackground = Professions-Slot-bg, IconBorder = Professions-Slot-Frame; WhatsTraining Crafting\RecipeList.lua:109-113
-- anchors) with the frame tinted by quality, as the client tints an item button's IconBorder; without those atlases
-- GearQuestForever's WhiteIconFrame (= file 651080, the client's own item-slot IconBorder) tinted by quality; without
-- that a quality-coloured square behind the icon (2 px of it show). Fields: qual (slot background / square), icon,
-- iconBorder, frameArt ("atlas" / "file" / nil). SetIconQuality(f, quality) colours it.
local function AddQualityIcon(f, size, point, rel, relPoint, x, y, itemButton)
  f.qual = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.qual:SetSize(size + 4, size + 4)
  f.qual:SetPoint(point, rel, relPoint, x, y)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(size, size)
  f.icon:SetPoint("CENTER", f.qual)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.iconBorder = f:CreateTexture(nil, "OVERLAY")
  -- itemButton (the sheet's gear slots): the item-button frame first, as the client's own character slots
  if not itemButton and HasAtlas("Professions-Slot-Frame") and SetAtlasSafe(f.iconBorder, "Professions-Slot-Frame") then
    f.iconBorder:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -2, 2)
    f.iconBorder:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 2, -2)
    f.frameArt = "atlas"
    f.slotBg = SetAtlasSafe(f.qual, "Professions-Slot-bg")
  elseif TexOK("iconFrame") then
    f.iconBorder:SetTexture(UI.TEX.iconFrame)
    f.iconBorder:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -2, 2)
    f.iconBorder:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 2, -2)
    f.frameArt = "file"
  else
    f.iconBorder:Hide()
  end
end
local function SetIconQuality(f, quality, r, g, b)
  if not r then r, g, b = QualityColor(quality) end
  if f.frameArt then
    f.iconBorder:SetVertexColor(r, g, b)
    if not f.slotBg then f.qual:SetColorTexture(0, 0, 0, 0.6) end
  else
    f.qual:SetColorTexture(r, g, b, 1)
  end
end

-- Sub-line tags of a craft (K1 rules): what an enchant replaces / which ring or trinket a craft replaces, not
-- learned, set bonus, rough weights. withLevel: the "from level N · X to go" tag first (the sheet; the list
-- cards show it as a chip instead).
-- the disambiguator after a row's name: "Ring 2" / "Trinket 1", W4: "off hand" for a dual-wield one-hander scored in
-- the off hand (a field of UI: the main chunk is at Lua's 200-locals limit)
function UI.RowPair(d)
  if d.kind == "enchant" then return nil end
  if d.hand == "off" then return L.HAND_OFF end
  return PairSlotName(d.slot)
end
local function CraftTags(d, cur, withLevel, noLearned)
  local tags = {}
  if withLevel and d.future and d.wearAt then tags[#tags + 1] = { LevelTag(d), C.levelTag } end
  local pair = UI.RowPair(d)
  if d.kind == "enchant" then
    local item = d.item and d.item.name or "?"
    tags[#tags + 1] = { d.equipped and string.format(L.REPLACES_ON, d.equipped.name, item) or string.format(L.NO_ENCHANT_ON, item) }
  elseif pair and d.equipped then
    tags[#tags + 1] = { string.format(L.REPLACES, d.equipped.name or "?") }
  end
  -- W4/W6: weapons: next to a worn two-hander (scored alone, W8.2) / a two-hander replacing both hands
  if d.status == "needs-partner" then
    tags[#tags + 1] = { d.slot == 17 and L.NEEDS_MAIN_HAND or L.NEEDS_OFF_HAND, C.future }
  elseif d.bothHands then
    tags[#tags + 1] = { L.REPLACES_BOTH }
  end
  if not d.known and not noLearned then tags[#tags + 1] = { L.NOT_LEARNED, (cur and cur.browse) and C.browse or C.notLearned } end
  if d.sets and d.setDelta and d.setDelta ~= 0 then
    tags[#tags + 1] = d.setDelta > 0 and { L.SET_PLUS, C.set } or { L.SET_BREAKS, C.setLoss }
  elseif d.hint then
    tags[#tags + 1] = { d.hint, C.set }
  end
  if d.e and GCA.Scoring.isPlaceholder(d.e.raw) then tags[#tags + 1] = { L.ROUGH } end
  return tags
end
UI.CraftTags = CraftTags

-- K4 variant "List": one 50 px row per craft: 38 px icon in the reagent-slot frame, name in quality colour
-- (+ "(Ring 2)" on pair slots), second line = the stat differences (when both sides have stat data) + the K1 tags
-- (K6: the "from level N" tag is orange text in that line, no chip box); right: the gain in the client's green
-- font over the points, the crafted box, the red "Offer" button. Too-high-level rows are dimmed (Offer and the box
-- stay at full alpha). K6: indented a little under their slot's worn row, no tree lines, no row shading.
local CARD_ICON = 38
local CARD_GAIN_W = 84
local CARD_OFFER_W = 84
local CARD_INDENT = 16
UI.CARD_INDENT = CARD_INDENT
local function CreateCardRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SUG_ROW_H - 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetPoint("TOPLEFT", b, "TOPLEFT", CARD_INDENT, 0)
  b.hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  UI.Skin(b.hl, "rowHover")
  AddQualityIcon(b, CARD_ICON, "LEFT", b, "LEFT", CARD_INDENT + 4, 0)
  b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.title:SetJustifyH("LEFT")
  SingleLine(b.title)
  b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.sub:SetJustifyH("LEFT")
  b.sub:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(b.sub)
  -- User 2026-11-15: a missing recipe = a red "Not learned" button at the start of the second line (replaces the K7
  -- third "where to get it" line): hover = the sources, click = map marker (UI.NotLearnedTip / NotLearnedClick)
  b.nl = CreateFrame("Button", nil, b)
  b.nl:SetHeight(14)
  b.nl.text = b.nl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.nl.text:SetPoint("LEFT", b.nl, "LEFT", 0, 0)
  SingleLine(b.nl.text)
  if b.nl.RegisterForClicks then b.nl:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  SetTip(b.nl, "not learned", function(self) UI.NotLearnedTip(self, self.data, self.cur) end)
  b.nl:SetScript("OnLeave", function() GameTooltip_Hide() end)
  b.nl:SetScript("OnClick", function(self, button) UI.NotLearnedClick(self, button, self.data, self.cur) end)
  b.nl:Hide()
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b.offer = CreateOfferTextButton(b, b, CARD_OFFER_W)
  b.crafted = CreateCraftedBox(b, b)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.gain:SetJustifyH("RIGHT")
  b.gain:SetWidth(CARD_GAIN_W)
  GainFont(b.gain, true)
  SingleLine(b.gain)
  b.points = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.points:SetJustifyH("RIGHT")
  b.points:SetWidth(CARD_GAIN_W)
  b.points:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  b.points:SetPoint("TOPRIGHT", b.gain, "BOTTOMRIGHT", 0, -2)
  SingleLine(b.points)
  LayoutRight(b, true, true, 7)
  SetTip(b, "suggestion", function(self)
    local d, cur = RowCtx(self)
    if d then ShowSuggestionTooltip(self, d, cur) end
  end)
  b:SetScript("OnLeave", HideTip)
  b:SetScript("OnClick", function(self, button)
    if UI.SourceClick(self, button, RowCtx(self)) then return end
    if self.data and self.data.info.link then HandleModifiedItemClick(self.data.info.link) end
  end)
  return b
end

local function UpdateCardRow(b, d)
  local cur = UI.current
  b.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(b, d.info.quality)
  local pair = UI.RowPair(d)
  b.title:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r" .. (pair and (" " .. C.muted .. "(" .. pair .. ")|r") or ""))
  -- second line: the "Not learned" button (red), then the K1 tags (level tag first, orange). No stat differences
  -- any more (user 2026-11-15; the character sheet keeps them).
  local tags = CraftTags(d, cur, true, true)
  local learned = d.known
  b.sub:SetText(((not learned and #tags > 0) and "·  " or "") .. TagLine(tags))
  b.nl.data, b.nl.cur = d, cur
  b.nl.text:SetText(learned and "" or (((cur and cur.browse) and C.browse or C.notLearnedTag) .. L.NOT_LEARNED .. "|r"))
  b.nl:SetShown(not learned)
  local nlW = learned and 1 or (TextWidth(b.nl.text) + 2)
  b.nl:SetWidth(nlW)
  local big, small = CardGain(d)
  b.gain:SetText(big)
  b.points:SetText(small)
  local showOffer, showCheck, mark = RightState(d, cur)
  b.offer:SetShown(showOffer)
  b.crafted:SetShown(showCheck)
  b.crafted:SetChecked(mark ~= nil)
  LayoutRight(b, showOffer, showCheck, 7)
  -- texts: one anchor each + an explicit width (the room between the icon and the gain), so they never run
  -- under the gain / box / Offer and need no second anchor with another vertical centre
  local textL = CARD_INDENT + 4 + CARD_ICON + 4 + 10
  local rightW = 6 + (showOffer and (CARD_OFFER_W + 4) or 0) + (showCheck and (22 + 6) or 0) + CARD_GAIN_W + 10
  local avail = math.max(40, UI.listW - textL - rightW)
  b.textW = avail
  -- second line: [Not learned]  ·  tags (the K7 third source line is gone: its content is the button's tooltip)
  b.hasSource = false
  b.nl:ClearAllPoints()
  b.nl:SetPoint("BOTTOMLEFT", b.qual, "BOTTOMRIGHT", 10, 3)
  b.sub:ClearAllPoints()
  if learned then
    b.sub:SetPoint("BOTTOMLEFT", b.qual, "BOTTOMRIGHT", 10, 4)
    b.sub:SetWidth(avail)
  else
    b.sub:SetPoint("LEFT", b.nl, "RIGHT", 6, 0)
    b.sub:SetWidth(math.max(10, avail - nlW - 6))
  end
  b.hasSub = #tags > 0 or not learned
  -- title on the top line when there is a second line, else centred on the row
  b.title:ClearAllPoints()
  if b.hasSub then
    b.title:SetPoint("TOPLEFT", b.qual, "TOPRIGHT", 10, -3)
  else
    b.title:SetPoint("LEFT", b.qual, "RIGHT", 10, 0)
  end
  b.title:SetWidth(avail)
  local a = d.future and 0.55 or 1
  for _, x in ipairs({ b.qual, b.iconBorder, b.icon, b.title, b.sub, b.nl, b.gain, b.points }) do x:SetAlpha(a) end
  b.dimmed = d.future and true or false
end
UI.UpdateCardRow = UpdateCardRow
-- K7: card height (scroll list height function): +10 px for the source line
UI.SOURCE_EXTRA_H = 10
function UI.CardHeight(b) return SUG_ROW_H + (b.hasSource and UI.SOURCE_EXTRA_H or 0) end

---------------------------------------------------------------------------
-- Slot sections (plan I): per slot with an upgrade, the worn item and that slot's craft cards under it; every
-- slot without an upgrade is folded into ONE box at the end ("No craftable upgrade: Head, Neck, …").
-- K5 (latest MemberCards mockup): the section starts with the worn item as its own 48 px row: 34 px icon in its
-- quality frame, gold slot name + small "EQUIPPED", the worn name(s) in quality colour (empty: dim "Slot empty"),
-- "n upgrades" on the right. Rings and trinkets stay one section (both worn items named).
---------------------------------------------------------------------------
local SECTION_H = 56 -- 6 px space above + the 48 px worn row + the 2 px gap
local WORN_ICON = 34
-- width of the suggestion list's content: follows the window (J2, set by UI:Layout)
UI.listW = RightW(MIN_W) - 30
UI.SECTION_H = SECTION_H

-- W6: the weapon sections / guild-needs categories "Main Hand / Off Hand / Ranged" (deDE "Haupthand / Nebenhand /
-- Distanz"; the client's MAINHANDSLOT etc. read differently there)
UI.HAND_SECTION = { [16] = "SECTION_MAINHAND", [17] = "SECTION_OFFHAND", [18] = "SECTION_RANGED" }
local function SectionTitle(sec)
  if #sec.slots > 1 and sec.key == 11 then return L.SECTION_RINGS end
  if #sec.slots > 1 and sec.key == 13 then return L.SECTION_TRINKETS end
  if UI.HAND_SECTION[sec.key] then return L[UI.HAND_SECTION[sec.key]] end
  return SlotName(sec.key)
end
UI.SectionTitle = SectionTitle

-- the worn item's real hyperlink (synced gear is a bare "item:" string; chat linking needs the full link)
local function WornHyperlink(x)
  local link = x and x.info and x.info.link
  if type(link) == "string" and link:find("|H", 1, true) then return link end
  if x and type(x.link) == "string" and x.link:find("|H", 1, true) then return x.link end
end

-- tooltip lines for the worn item(s) of a section: "Slot: name  12.3 AP-eq"
local function WornTipLines(sec, unit)
  for _, x in ipairs(sec.worn) do
    local name = x.info and x.info.name or (x.link and "?") or L.SECTION_NOTHING
    if x.score then
      GameTooltip:AddDoubleLine(SlotName(x.slot) .. ": " .. name, string.format(L.SECTION_SCORE, x.score, unit), 1, 1, 1, 0.6, 0.8, 1)
    else
      GameTooltip:AddLine(SlotName(x.slot) .. ": " .. name, 1, 1, 1)
    end
  end
end

-- the first worn item of a section that is there (has a link)
local function FirstWorn(sec)
  for _, x in ipairs(sec.worn or {}) do if x.link then return x end end
end

local function CreateSectionRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SECTION_H - 2)
  local box = CreateFrame("Frame", nil, b)
  box:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -6)
  box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.box = box
  -- K6: no box: a 1 px separator above the slot (WhatsTraining's recipe-row separator), as a list category
  box.line = box:CreateTexture(nil, "ARTWORK")
  box.line:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  box.line:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  box.line:SetHeight(1)
  UI.Skin(box.line, "separator")
  b.hl = box:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  UI.Skin(b.hl, "rowHover")
  AddQualityIcon(box, WORN_ICON, "LEFT", box, "LEFT", 8, 0)
  -- User 2026-11-15, strict rule for every item icon in the window: the item's name right next to the icon. The slot
  -- header is just that: icon + worn name (centred, 12 px gap) + the count on the right; no slot name, no "Equipped"
  -- (only an empty slot names its slot: "Chest (empty)").
  b.wornName = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.wornName:SetPoint("LEFT", box.qual, "RIGHT", 12, 0)
  b.wornName:SetJustifyH("LEFT")
  SingleLine(b.wornName)
  b.count = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("RIGHT", box, "RIGHT", -14, 0)
  b.count:SetJustifyH("RIGHT")
  b.count:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(b.count)
  SetTip(b, "section", function(self)
    local sec = self.data and self.data.sec
    if not sec then return end
    local unit = GCA:UnitLabel(UI.current and UI.current.weights)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local first = FirstWorn(sec)
    if #sec.worn == 1 and first and first.link then
      UI.PlainItemTip(self, first.link) -- K17: an item: the plain Blizzard tooltip only
      return
    else
      GameTooltip:SetText(SectionTitle(sec), 1, 0.82, 0)
      WornTipLines(sec, unit)
    end
    if sec.unknown and #sec.rows == 0 then
      GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true)
    elseif #sec.rows == 0 then
      GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine(string.format(L.SECTION_TIP_SHOWN, #sec.rows, sec.total or #sec.rows), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  -- (Shift-)click links the worn item (the first one of a ring/trinket pair)
  b:SetScript("OnClick", function(self)
    local sec = self.data and self.data.sec
    local link = sec and WornHyperlink(FirstWorn(sec))
    if link then SafeCall(HandleModifiedItemClick, link) end
  end)
  return b
end

local function UpdateSectionRow(b, d)
  local sec = d.sec
  local parts, first = {}, nil
  for _, wx in ipairs(sec.worn) do
    if wx.info then
      parts[#parts + 1] = Hex(QualityColor(wx.info.quality)) .. (wx.info.name or "?") .. "|r"
    elseif wx.link then
      parts[#parts + 1] = C.dim .. "?|r" -- worn but not loaded
    else
      parts[#parts + 1] = C.dim .. L.CARDS_EMPTY .. "|r"
    end
    if wx.link and not first then first = wx end
  end
  local empty = first == nil
  b.wornName:SetText(empty and (C.dim .. string.format(L.SECTION_EMPTY_NAMED, SectionTitle(sec)) .. "|r")
    or table.concat(parts, C.muted .. "  ·  |r"))
  local box = b.box
  box.icon:SetTexture(first and ItemIcon(first.link) or SlotTexture(sec.key))
  box.icon:SetDesaturated(empty)
  box.icon:SetAlpha(empty and 0.45 or 1)
  if empty then SetIconQuality(box, nil, 0.35, 0.31, 0.26) else SetIconQuality(box, first.info and first.info.quality) end
  local n = #sec.rows
  b.count:SetText(n == 1 and string.format(L.CARDS_COUNT_1, n) or string.format(L.CARDS_COUNT, n))
  local countW = TextWidth(b.count)
  b.textW = math.max(40, UI.listW - (8 + WORN_ICON + 4 + 12) - countW - 14 - 12)
  b.wornName:SetWidth(b.textW)
  b.empty = empty
end
-- K1: one wrapped grey line for every slot without an upgrade (K4: "No craftable upgrade: …" in a box)
local function FoldText(secs)
  local names = {}
  for _, sec in ipairs(secs) do
    names[#names + 1] = SectionTitle(sec) .. (sec.unknown and (" " .. L.FOLD_NOT_LOADED) or "")
  end
  if GCA:SelectedProfession() == "Enchanting" then return string.format(L.CARDS_NONE_ENCH, table.concat(names, ", ")) end
  return string.format(L.CARDS_NONE, table.concat(names, ", "))
end
UI.FoldText = FoldText

local function CreateFoldRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(SECTION_H - 2)
  -- K6: plain grey text under a separator (the K4 bordered box is gone)
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2)
  b.line:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -2)
  b.line:SetHeight(1)
  UI.Skin(b.line, "separator")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.text:SetPoint("TOPLEFT", 10, -9)
  b.text:SetJustifyH("LEFT")
  if b.text.SetWordWrap then b.text:SetWordWrap(true) end
  SetTip(b, "no-upgrade line", function(self)
    local secs = self.data and self.data.secs
    if not secs then return end
    local unit = GCA:UnitLabel(UI.current and UI.current.weights)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.FOLD_TIP_TITLE, 1, 0.82, 0)
    local unknown = false
    for _, sec in ipairs(secs) do
      WornTipLines(sec, unit)
      if sec.unknown then unknown = true end
    end
    GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    if unknown then GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateFoldRow(b, d)
  b.text:SetWidth(UI.listW - 20)
  b.text:SetText(FoldText(d.secs))
end

-- height of the folded line: the client's measure of the wrapped text; without one (offline harness) an estimate
-- of ~5.5 px per byte of GameFontDisableSmall (umlauts are 2 bytes, so it errs on the tall side). K4: + the box
-- padding (9 px above and below the text; the scroll list leaves a 2 px gap under each row).
local function FoldHeight(b)
  local h = b.text.GetStringHeight and SafeCall(b.text.GetStringHeight, b.text)
  if type(h) ~= "number" or GCA.IsSecret(h) or h <= 0 then
    local perLine = math.max(20, math.floor((UI.listW - 20) / 5.5))
    h = math.ceil(#(b.text:GetText() or "") / perLine) * 12
  end
  return math.max(SECTION_H, math.ceil(h) + 20)
end
UI.FoldHeight = FoldHeight

-- The list entries for one member (plan I): per section with an upgrade a header and its rows, then (K1) one
-- folded line for all slots without an upgrade. With no suggestion at all the list stays empty, so the
-- empty-state text explains why (no recipes known, …).
function UI.SectionRows(list)
  local out = {}
  if not list or #list == 0 then return out end
  if not list.sections then
    for i, s in ipairs(list) do out[i] = s end
    return out
  end
  local none = {}
  for _, sec in ipairs(list.sections) do
    if #sec.rows > 0 then
      out[#out + 1] = { rowKind = "section", sec = sec }
      for _, s in ipairs(sec.rows) do out[#out + 1] = s end
    else
      none[#none + 1] = sec -- BuildSections lists them in character order
    end
  end
  if #none > 0 then out[#out + 1] = { rowKind = "fold", secs = none } end
  return out
end

---------------------------------------------------------------------------
-- Guild needs. K5 grouped the list by craft; K8 (native profession window): the LEFT list is the recipe list -
-- category headers per gear slot (rings / trinkets one each), under them one plain text row per craft ("Name [n]",
-- n = members it is an upgrade for, best gain right); the RIGHT detail panel shows the selected craft (round icon,
-- name, slot + tags, "Would be an upgrade for:" with one row per member - class-coloured name, what they wear, gain,
-- the red Offer button, the crafted box; click = that member in "By member" on that slot - then the reagents with
-- have/need and, for a recipe you don't know, where to get it). Offline members only with "Include offline members
-- (n)" (Filter menu; db.settings.needsOffline). Shift/Ctrl-click links the item; right-click = K7 source menu.
---------------------------------------------------------------------------
local function ModifiedDown()
  if ShiftDown() then return true end
  return IsControlKeyDown and SafeCall(IsControlKeyDown) and true or false
end

UI.needsCollapsed = {} -- category (slot section) -> collapsed (per open, not saved)
UI.NEED_GAIN_W = 46

-- the gain of a member under a craft: "+8.4" (that member's AP/SP-equivalents)
-- the gain of a member under a craft: "+8.4" (that member's AP/SP-equivalents)
local function ChipGain(s) return UI.GainNum(s.points) end
UI.ChipGain = ChipGain

local function CraftGroupTip(owner, e)
  local g = e and e.group
  if not g then return end
  ShowSuggestionTooltip(owner, g.sug, g.best and g.best.member) -- K17: plain item tooltip + that member's worn item
end
UI.CraftGroupTip = CraftGroupTip

-- K8: a craft = a recipe-list row: the name (GameFontHighlight_NoShadow, white; a recipe you don't know grey, browse
-- teal), its Count " [n]" right after it, the best gain right; the recipe row's hover / selected art. Too-high-level
-- only crafts dimmed. Click = show it in the detail panel.
local function CreateCraftGroupRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NEED_ROW_H)
  UI.AddRowArt(b)
  b.label = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.label:SetPoint("LEFT", b, "LEFT", MEMBER_TEXT_X, 0)
  b.label:SetJustifyH("LEFT")
  SingleLine(b.label)
  b.count = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.count:SetPoint("LEFT", b.label, "RIGHT", 0, 0)
  b.count:SetJustifyH("LEFT")
  SingleLine(b.count)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.gain:SetWidth(UI.NEED_GAIN_W)
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self, button)
    local e = self.data
    if not (e and e.group) then return end
    if UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) then return end
    if ModifiedDown() and e.group.sug.info.link then HandleModifiedItemClick(e.group.sug.info.link); return end
    UI.needSel = e.group.key
    UI:RefreshNeeds()
  end)
  SetTip(b, "craft row", function(self) CraftGroupTip(self, self.data) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateCraftGroupRow(b, e)
  local g = e.group
  local d = g.sug
  local cur = g.best and g.best.member
  local colour = (cur and cur.browse) and C.browse or ((not d.known) and C.notLearned or nil)
  b.label:SetText(Tag(d.info.name or "?", colour))
  b.count:SetText(" [" .. #e.rows .. "]")
  b.gain:SetText(e.rows[1] and ChipGain(e.rows[1].sug) or "")
  local avail = math.max(40, (UI.needsW or (LEFT_W - 30)) - MEMBER_TEXT_X - UI.NEED_GAIN_W - 10)
  local countW = TextWidth(b.count)
  b.label:SetWidth(math.max(20, math.min(TextWidth(b.label) + 2, avail - countW)))
  b.textW = avail
  local a = g.future and 0.55 or 1
  for _, f in ipairs({ b.label, b.count, b.gain }) do f:SetAlpha(a) end
  b.dimmed = g.future
  b.sel:SetShown(UI.needSel == g.key)
end

-- K8: the slot categories of the needs list (the recipe list's category header)
local function CatTitle(key)
  if key == 11 then return L.SECTION_RINGS end
  if key == 13 then return L.SECTION_TRINKETS end
  if UI.HAND_SECTION[key] then return L[UI.HAND_SECTION[key]] end
  return SlotName(key)
end
UI.NeedsCatTitle = CatTitle
local function CreateNeedsCatRow(parent)
  local b = UI.CreateCategoryRow(parent, function(self)
    local d = self.data
    UI.needsCollapsed[d.cat] = not UI.needsCollapsed[d.cat]
    UI:RefreshNeeds()
  end)
  SetTip(b, "needs category", function(self)
    local d = self.data
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(CatTitle(d.cat), 1, 0.82, 0)
    GameTooltip:AddLine(d.n == 1 and L.NEEDS_CAT_TIP_1 or string.format(L.NEEDS_CAT_TIP, d.n), 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end
local function UpdateNeedsCatRow(b, d)
  b.rowW = UI.needsW
  b:SetCategory(CatTitle(d.cat), not UI.needsCollapsed[d.cat])
end
UI.NEEDS_KINDS = { cat = { create = CreateNeedsCatRow, update = UpdateNeedsCatRow, height = GROUP_ROW_H } }

-- a member of the selected craft (detail panel)
local NEED_SUB_X = 8
local NEED_SUB_NAME_W = 130
UI.NEED_MEMBER_W = 110 -- the member-name column of the detail rows (user 2026-11-15); longer names end in "…"
local function CreateNeedMemberRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NEED_SUB_H - 2)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hlKind = UI.Skin(b.hl, "rowHover")
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.name:SetPoint("LEFT", b, "LEFT", NEED_SUB_X, 0)
  b.name:SetWidth(NEED_SUB_NAME_W)
  b.name:SetJustifyH("LEFT")
  SingleLine(b.name)
  -- K10: line 1 = the member's name (class colour; offline = grey, no "offline" text), line 2 = what they wear
  -- now: a small item icon in the profession slot frame (quality coloured, tooltip/Shift-click = the worn item)
  -- and its name in quality colour; an empty slot / the current enchant as grey text.
  -- K10b (user): the worn item's icon is the row's big left icon (32 px, both lines tall); name + item name beside it
  -- User 2026-11-15: one line. Member name in its own column on the left (class colour), then the worn item's icon
  -- with its name right beside it (strict rule), then gain / Offer / box. Nothing under the item name.
  b.name:ClearAllPoints()
  b.name:SetPoint("LEFT", b, "LEFT", NEED_SUB_X, 0)
  b.name:SetWidth(UI.NEED_MEMBER_W)
  b.wornBtn = CreateFrame("Button", nil, b)
  b.wornBtn:SetSize(34, 34)
  b.wornBtn:SetPoint("LEFT", b, "LEFT", NEED_SUB_X + UI.NEED_MEMBER_W + 8, 0)
  AddQualityIcon(b.wornBtn, 30, "CENTER", b.wornBtn, "CENTER", 0, 0)
  b.wornBtn:SetScript("OnEnter", function(self)
    local link = self.link
    if type(link) == "string" and link:find("|H", 1, true) then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  b.wornBtn:SetScript("OnLeave", GameTooltip_Hide)
  b.wornBtn:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") then HandleModifiedItemClick(self.link) end
  end)
  b.state = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.state:SetPoint("LEFT", b.wornBtn, "RIGHT", 8, 0)
  b.state:SetJustifyH("LEFT")
  SingleLine(b.state)
  b.offer = CreateOfferButton(b)
  b.crafted = CreateCraftedBox(b, b) -- K6: the same (MinimalCheckboxTemplate) box as the cards and the sheet
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  LayoutRight(b, true, true)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self, button)
    local e = self.data
    if not (e and e.sug) then return end
    if UI.SourceClick(self, button, e.sug, e.member) then return end
    if ModifiedDown() and e.sug.info.link then HandleModifiedItemClick(e.sug.info.link); return end
    UI:OpenMember(e.member.key, e.sug.slot, e.sug)
  end)
  SetTip(b, "need member", function(self)
    local d, cur = RowCtx(self)
    if d then ShowSuggestionTooltip(self, d, cur) end
  end)
  b:SetScript("OnLeave", HideTip)
  return b
end

-- "online · wears [X]" / "offline · slot empty"; enchants: what the enchant replaces
local function NeedState(d, m)
  local parts = { m.online and L.NEEDS_STATE_ON or L.NEEDS_STATE_OFF }
  local pair = UI.RowPair(d)
  local wear
  if d.kind == "enchant" then
    local item = d.item and d.item.name or "?"
    wear = d.equipped and string.format(L.REPLACES_ON, d.equipped.name or "?", item) or string.format(L.NO_ENCHANT_ON, item)
  elseif d.equipped then
    wear = string.format(L.NEEDS_WEARS, Hex(QualityColor(d.equipped.quality)) .. (d.equipped.name or "?") .. "|r")
  else
    wear = L.CARDS_EMPTY
  end
  parts[#parts + 1] = (pair and (pair .. ": ") or "") .. wear
  return table.concat(parts, "  ·  ")
end
UI.NeedState = NeedState

UI.NEED_GAIN_SUB_W = 60
local function UpdateNeedMemberRow(b, e)
  local d, m = e.sug, e.member
  -- user 2026-11-15: member column | icon + the worn item's name (quality colour; empty slot dim) followed, as on the
  -- cards' titles, by the muted pair slot "(Ring 1)" and the orange level tag; an enchant: what it replaces, muted
  b.name:SetText(UI.MemberName(m)) -- user 2026-11-15: class colour always + online/offline dot
  local eq = d.kind ~= "enchant" and d.equipped or nil
  local pair = UI.RowPair(d)
  local text
  if d.kind == "enchant" then
    eq = d.item
    text = eq and (Hex(QualityColor(eq.quality)) .. (eq.name or "?") .. "|r") or "?"
    text = text .. "  " .. C.muted .. (d.equipped and string.format(L.REPLACES, d.equipped.name or "?") or L.NO_ENCHANT) .. "|r"
  elseif eq then
    text = Hex(QualityColor(eq.quality)) .. (eq.name or "?") .. "|r"
  else
    text = C.dim .. L.CARDS_EMPTY .. "|r"
  end
  if pair then text = text .. " " .. C.muted .. "(" .. pair .. ")|r" end
  if d.future and d.wearAt then text = text .. "  " .. Tag(LevelTag(d), C.levelTag) end
  b.state:SetText(text)
  if eq and eq.icon then
    b.wornBtn.icon:SetTexture(eq.icon)
    b.wornBtn.icon:Show()
    SetIconQuality(b.wornBtn, eq.quality)
    b.wornBtn.link = eq.link
    b.wornBtn:SetAlpha(1)
  else
    b.wornBtn.icon:SetTexture(nil)
    SetIconQuality(b.wornBtn, 0, 0.3, 0.3, 0.3)
    b.wornBtn.link = nil
    b.wornBtn:SetAlpha(0.5)
  end
  b.gain:SetText(ChipGain(d))
  local showOffer, showCheck, mark = RightState(d, m)
  b.offer:SetShown(showOffer)
  b.crafted:SetShown(showCheck)
  b.crafted:SetChecked(mark ~= nil)
  LayoutRight(b, showOffer, showCheck)
  local rightW = 6 + (showOffer and (UI.OFFER_SMALL_W + 4) or 0) + (showCheck and 28 or 0) + UI.NEED_GAIN_SUB_W
  local avail = math.max(40, (UI.detailListW or 300) - (NEED_SUB_X + UI.NEED_MEMBER_W + 8 + 42) - rightW - 8)
  b.gain:SetWidth(UI.NEED_GAIN_SUB_W)
  b.state:SetWidth(avail)
  b.stateW = avail
  b.name:SetAlpha(1)
  b.state:SetAlpha(1)
  b.wornBtn:SetAlpha(b.wornBtn.link and 1 or 0.5)
  local f = d.future and 0.55 or 1
  b.gain:SetAlpha(f)
  b.dimmed = d.future and true or false
end

-- entries for the needs list (K8): per slot category (order of its best craft) a header and, unless collapsed, its
-- crafts; search = item name (the whole craft) or member name (only those members), plain text, ASCII
-- case-insensitive. Returns the entries, the number of crafts and members shown, how many offline members have
-- upgrades (the Filter entry's count) and every matching craft entry (also those under a collapsed header).
function UI.NeedsRows(needs, query, withOffline)
  local q = tostring(query or ""):lower():match("^%s*(.-)%s*$") or ""
  local groups = needs and (withOffline and needs.craftsAll or needs.crafts) or {}
  local crafts, members, seen = 0, 0, {}
  local cats, byCat, all = {}, {}, {}
  for _, g in ipairs(groups) do
    local rows = g.rows
    if q ~= "" and not tostring(g.sug.info and g.sug.info.name or ""):lower():find(q, 1, true) then
      rows = {}
      for _, r in ipairs(g.rows) do
        if tostring(r.member.key):lower():find(q, 1, true) then rows[#rows + 1] = r end
      end
    end
    if #rows > 0 then
      crafts = crafts + 1
      for _, r in ipairs(rows) do
        if not seen[r.member.key] then seen[r.member.key] = true; members = members + 1 end
      end
      local key = GCA.SECTION_OF[g.sug.slot] or g.sug.slot
      if not byCat[key] then byCat[key] = {}; cats[#cats + 1] = key end
      local e = { group = g, rows = rows, cat = key }
      table.insert(byCat[key], e)
      all[#all + 1] = e
    end
  end
  local out = {}
  for _, key in ipairs(cats) do
    out[#out + 1] = { rowKind = "cat", cat = key, n = #byCat[key] }
    if not UI.needsCollapsed[key] then
      for _, e in ipairs(byCat[key]) do out[#out + 1] = e end
    end
  end
  local off, offN = {}, 0
  for _, r in ipairs(needs and needs.offline or {}) do
    if not off[r.member.key] then off[r.member.key] = true; offN = offN + 1 end
  end
  return out, crafts, members, offN, all
end

-- K8: the detail panel of the selected craft (the schematic form's place): framed by the skin role detailBorder,
-- the window's page art shows through (no own background, as the client's form).
local CD_ICON = 46
UI.CD_ICON = CD_ICON
local function DetailTitle(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  SingleLine(fs)
  return fs
end
-- a round item icon (K8): the icon masked round (TempPortraitAlphaMask, as ForeverDungeonJournal LFGButton.lua:386-390
-- does on Forever) with the bronze ring (UI.SKIN.detailRing) around it; where masks / the files are missing: the
-- square icon in the reagent-slot frame. f.iconShape = "round" / "square".
function UI.AddRoundIcon(f, size)
  local ring = UI.SKIN.detailRing
  if f.CreateMaskTexture and FileOK(ring.mask) ~= false and FileOK(ring.file) ~= false then
    local icon = f:CreateTexture(nil, "ARTWORK")
    local ok, mask = pcall(f.CreateMaskTexture, f)
    if icon.AddMaskTexture and ok and mask and pcall(mask.SetTexture, mask, ring.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
      icon:SetSize(size, size)
      icon:SetPoint("CENTER", f, "CENTER", 0, 0)
      mask:SetAllPoints(icon)
      icon:AddMaskTexture(mask)
      f.icon, f.mask = icon, mask
      f.ring = f:CreateTexture(nil, "OVERLAY")
      f.ring:SetTexture(ring.file)
      local rs = math.floor(size * 37 / 30 + 0.5) -- FDJ: a 37 px ring around a 30 px icon
      f.ring:SetSize(rs, rs)
      f.ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
      f.iconShape = "round"
      return
    end
    icon:Hide()
  end
  AddQualityIcon(f, size - 4, "CENTER", f, "CENTER", 0, 0)
  f.iconShape = "square"
end
function UI.CreateCraftDetail(parent)
  local p = CreateFrame("Frame", nil, parent)
  UI.AddDetailBorder(p)
  local ib = CreateFrame("Button", nil, p)
  ib:SetSize(CD_ICON, CD_ICON)
  ib:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -16)
  UI.AddRoundIcon(ib, CD_ICON)
  if ib.RegisterForClicks then ib:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  ib:SetScript("OnClick", function(self, button)
    local e = p.entry
    if not (e and e.group) then return end
    if UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) then return end
    if e.group.sug.info.link then HandleModifiedItemClick(e.group.sug.info.link) end
  end)
  SetTip(ib, "craft icon", function(self) CraftGroupTip(self, p.entry) end)
  ib:SetScript("OnLeave", GameTooltip_Hide)
  p.iconBtn = ib
  p.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  NativeFont(p.name, "GameFontHighlightLarge")
  p.name:SetPoint("TOPLEFT", ib, "TOPRIGHT", 12, -4)
  p.name:SetJustifyH("LEFT")
  SingleLine(p.name)
  p.desc = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.desc:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -6)
  p.desc:SetJustifyH("LEFT")
  SingleLine(p.desc)
  p.forTitle = DetailTitle(p, L.DETAIL_FOR)
  p.forTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -76)
  p.members = CreateScrollList(p, 300, NEED_SUB_H * 3, NEED_SUB_H, CreateNeedMemberRow, UpdateNeedMemberRow)
  p.members:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -92)
  RaiseInsetBorder(p, p.members)
  p.reagTitle = DetailTitle(p, L.TIP_REAGENTS)
  p.reag = {}
  p.srcTitle = DetailTitle(p, L.SRC_TIP_HEAD .. ":")
  p.srcBox = CreateFrame("Button", nil, p)
  if p.srcBox.RegisterForClicks then p.srcBox:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  p.srcBox:SetScript("OnClick", function(self, button)
    local e = p.entry
    if e and e.group then UI.SourceClick(self, button, e.group.sug, e.group.best and e.group.best.member) end
  end)
  SetTip(p.srcBox, "craft sources", function(self)
    local e = p.entry
    if not (e and e.group) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.group.sug.info.name or "?", 1, 1, 1)
    Src.AddTooltip(UI.SourceInfo(e.group.sug, e.group.best and e.group.best.member))
    GameTooltip:Show()
  end)
  p.srcBox:SetScript("OnLeave", GameTooltip_Hide)
  -- K14: each source line is its own button: click = waypoint + world map on that spot (when CJ has
  -- coordinates; a map pin marks those), right-click = the source menu, Shift-click = link the pattern
  p.src, p.srcBtn = {}, {}
  local PIN = { "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Tracked" }
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, p.srcBox)
    b:SetHeight(16)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    UI.Skin(b.hl, "rowHover")
    b.pin = b:CreateTexture(nil, "ARTWORK")
    b.pin:SetSize(14, 14)
    b.pin:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.pinOK = false
    for _, a in ipairs(PIN) do
      if HasAtlas(a) and SetAtlasSafe(b.pin, a) then b.pinOK = true; break end
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    SingleLine(fs)
    b.text = fs
    b:SetScript("OnClick", function(self, button)
      local e = p.entry
      if not (e and e.group) then return end
      if button == "RightButton" or ShiftDown() then
        UI.SourceClick(self, "RightButton", e.group.sug, e.group.best and e.group.best.member)
      elseif self.npc then
        Src.ShowOnMap(self.npc)
      end
    end)
    SetTip(b, "craft source", function(self)
      local e = p.entry
      if not (e and e.group) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(e.group.sug.info.name or "?", 1, 1, 1)
      Src.AddTooltip(UI.SourceInfo(e.group.sug, e.group.best and e.group.best.member))
      if self.npc then GameTooltip:AddLine(string.format(L.SRC_TIP_SHOWMAP, self.npc.name), 0.5, 0.8, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    p.srcBtn[i] = b
    p.src[i] = fs
  end
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("CENTER")
  return p
end

-- one reagent: the item in the reagent slot frame, "have/need Name" (wraps to two lines), item tooltip on hover,
-- (Shift-)click links it
UI.REAGENT_STEP = 46 -- one reagent row (40 px) + gap, as spaced in the crafting window
local function ReagentRow(p, i)
  local f = p.reag[i]
  if f then return f end
  f = CreateFrame("Button", nil, p)
  f:SetSize(160, 40)
  AddQualityIcon(f, 36, "LEFT", f, "LEFT", 2, 0)
  -- the crafting window's reagent text: GameFontHighlight, "0/5 Name", one line
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("LEFT", f.qual, "RIGHT", 10, 0)
  f.text:SetJustifyH("LEFT")
  SingleLine(f.text)
  SetTip(f, "reagent", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.itemID)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  f:SetScript("OnClick", function(self)
    local info = self.itemID and GCA:GetInfo(self.itemID)
    if info and info.link then SafeCall(HandleModifiedItemClick, info.link) end
  end)
  p.reag[i] = f
  return f
end

-- fills and stacks the detail panel for one craft entry (nil = nothing to show: the empty text)
function UI:UpdateCraftDetail(e, emptyText)
  local p = self.needDetail
  if not p then return end
  p.entry = e
  local w, h = p.w or 400, p.h or 400
  local shown = e ~= nil
  for _, x in ipairs({ p.iconBtn, p.name, p.desc, p.forTitle, p.members, p.reagTitle, p.srcTitle, p.srcBox }) do x:SetShown(shown) end
  p.empty:SetText(shown and "" or (emptyText or ""))
  p.empty:SetWidth(math.max(40, w - 60))
  if not shown then
    for _, f in ipairs(p.reag) do f:Hide() end
    p.members:SetData({})
    return
  end
  local g, d = e.group, e.group.sug
  local cur = g.best and g.best.member
  local ib = p.iconBtn
  ib.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  if ib.iconShape == "square" then SetIconQuality(ib, d.info.quality) end
  local textW = math.max(60, w - 18 - CD_ICON - 12 - 16)
  p.name:SetText(d.info.name or "?")
  p.name:SetWidth(textW)
  local parts = { d.kind == "enchant" and SlotName(d.slot) or CatTitle(e.cat) }
  if not d.known then parts[#parts + 1] = Tag(L.NOT_LEARNED, (cur and cur.browse) and C.browse or C.notLearned) end
  if g.future and d.wearAt then parts[#parts + 1] = Tag(LevelTag(d), C.levelTag) end
  if d.hint then parts[#parts + 1] = Tag(d.hint, C.set) end
  p.desc:SetText(table.concat(parts, "  ·  "))
  p.desc:SetWidth(textW)
  p.forTitle:SetText(#e.rows == 1 and L.DETAIL_FOR or string.format(L.DETAIL_FOR_N, #e.rows))
  p.forTitle:SetWidth(math.max(40, w - 36))
  -- bottom blocks first (their heights decide how much room the member list gets)
  local regs = d.cand.recipe and d.cand.recipe.r or {}
  -- user 2026-11-15: reagents exactly as the crafting window lists them: one column, "0/5 Dickes Leder" beside the
  -- icon (grey while you have too few), UI.REAGENT_STEP px per reagent
  local cols = 1
  local colW = math.floor(w - 36)
  local reagH = #regs > 0 and (18 + #regs * UI.REAGENT_STEP) or 0
  local info = (not d.known) and UI.SourceInfo(d, cur) or nil
  local lines = {}
  if info then
    local list = info.list or {}
    p.srcNpc = {}
    for i = 1, math.min(#list, 4) do
      lines[#lines + 1] = Src.LineOf(list[i], info)
      local n = list[i].npc
      p.srcNpc[#lines] = (n and n.map and n.x and n.y) and n or nil
    end
    if #list > 4 then lines[#lines + 1] = C.muted .. string.format(L.SRC_LINE_MORE, #list - 4) .. "|r" end
    if #list == 0 then lines[1] = Src.Line(info) end
  end
  if not info then p.srcNpc = {} end
  local srcH = #lines > 0 and (18 + #lines * 16 + 4) or 0
  local listTop = 92
  local room = h - listTop - 8 - reagH - srcH - 12
  local listH = math.max(NEED_SUB_H, math.min(#e.rows * NEED_SUB_H, room))
  UI.detailListW = math.max(100, w - 44)
  p.members:Resize(UI.detailListW, listH)
  p.members:SetData(e.rows)
  p.listH = listH
  local y = listTop + listH + 10
  p.reagTitle:ClearAllPoints()
  p.reagTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.reagTitle:SetShown(#regs > 0)
  for i, reg in ipairs(regs) do
    local f = ReagentRow(p, i)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p, "TOPLEFT", 16 + col * colW, -(y + 18 + row * UI.REAGENT_STEP))
    f:SetWidth(colW - 8)
    f.itemID = reg[1]
    f.icon:SetTexture(ItemIcon(reg[1]))
    local have = SafeCall(GCA.ItemAPI.Count, reg[1], true) or 0
    local enough = have >= (reg[2] or 0)
    f.text:SetText(string.format("%d/%d %s", have, reg[2] or 0, ItemName(reg[1])))
    f.text:SetWidth(math.max(20, colW - 8 - 46))
    if enough then f.text:SetTextColor(1, 1, 1) else f.text:SetTextColor(0.62, 0.62, 0.62) end
    SetIconQuality(f, 1)
    f.enough = enough
    f:Show()
  end
  for i = #regs + 1, #p.reag do p.reag[i]:Hide() end
  y = y + reagH
  p.srcTitle:ClearAllPoints()
  p.srcTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -y)
  p.srcTitle:SetShown(#lines > 0)
  p.srcBox:ClearAllPoints()
  p.srcBox:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(y + 16))
  p.srcBox:SetSize(math.max(40, w - 36), math.max(1, #lines * 16))
  p.srcBox:SetShown(#lines > 0)
  for i, b in ipairs(p.srcBtn) do
    local fs, npc = b.text, p.srcNpc and p.srcNpc[i] or nil
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p.srcBox, "TOPLEFT", 0, -(i - 1) * 16)
    b:SetWidth(math.max(40, w - 36))
    b.npc = npc
    local pin = npc and b.pinOK
    b.pin:SetShown(pin and true or false)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", pin and 17 or 0, 0)
    fs:SetWidth(math.max(40, w - 36) - (pin and 17 or 0))
    fs:SetText(lines[i] or "")
    -- clickable lines (coordinates known) in the client's link colour; the rest stays plain
    if npc then fs:SetTextColor(0.40, 0.73, 1.00) else fs:SetTextColor(1, 1, 1) end
    fs:SetShown(lines[i] ~= nil)
    b:SetShown(lines[i] ~= nil)
  end
  p.contentH = y + srcH
end

---------------------------------------------------------------------------
-- K4 variant "Character sheet" (Member mockup): the member's gear slots as square buttons in two columns like
-- the character window, plus the weapon row under the middle (shields, held off-hands, relics and weapon/shield
-- enchants live there; weapons since step W). The middle panel compares the selected slot: worn item ->
-- best craft (gain, stat differences, crafted box, Offer), then the slot's other crafts. Everything comes from
-- the same list.sections the list variant shows (top 3 per slot).
---------------------------------------------------------------------------
local SHEET_S = 40         -- slot button
local SHEET_COL_X = 8      -- slot columns from the panel edge
local SHEET_GAP_X = 10     -- slot column to the middle panel
local SHEET_PAD = 10       -- middle panel padding
local SHEET_CARD_H = 64
local SHEET_ARROW_W = 24
local SHEET_GAIN_W = 74
local SHEET_ALT_H = 26
local SHEET_STAT_H = 16
local SHEET_OFFER_W = 100
UI.SHEET_S, UI.SHEET_PAD, UI.SHEET_CARD_H, UI.SHEET_ALT_H = SHEET_S, SHEET_PAD, SHEET_CARD_H, SHEET_ALT_H
UI.SHEET_LEFT = { 1, 2, 3, 15, 5, 9, 10 }
UI.SHEET_RIGHT = { 6, 7, 8, 11, 12, 13, 14 }
UI.SHEET_BOTTOM = { 16, 17, 18 }

-- K4: which member-view variant is shown ("sheet" by default; db.settings.memberView)
function UI.MemberMode()
  local s = GCA.db and GCA.db.settings
  return (s and s.memberView == "list") and "list" or "sheet"
end

-- The rows of one sheet slot (its section's rows; rings/trinkets: only those that replace THIS ring/trinket),
-- the section and this slot's worn entry.
function UI.SheetRows(list, slot)
  local key = GCA.SECTION_OF[slot] or slot
  for _, sec in ipairs(list and list.sections or {}) do
    if sec.key == key then
      local rows, worn = {}, nil
      for _, r in ipairs(sec.rows) do
        if #sec.slots < 2 or r.slot == slot then rows[#rows + 1] = r end
      end
      for _, x in ipairs(sec.worn) do if x.slot == slot then worn = x end end
      return rows, sec, worn
    end
  end
  return {}, nil, nil
end

-- The slot with the biggest upgrade: BuildSections sorts the sections by their first row (the comparison of the
-- member order), so it is the first section's first row. No upgrade anywhere: the head.
function UI.SheetDefaultSlot(list)
  for _, sec in ipairs(list and list.sections or {}) do
    if sec.rows[1] then return sec.rows[1].slot end
  end
  return UI.SHEET_LEFT[1]
end

local function SheetCountText(n, enchanting)
  if enchanting then
    if n == 1 then return L.SHEET_COUNT_ENCH_1 end
    return string.format(L.SHEET_COUNT_ENCH, n)
  end
  if n == 1 then return L.SHEET_COUNT_1 end
  return string.format(L.SHEET_COUNT, n)
end
UI.SheetCountText = SheetCountText

-- worn item tooltip (a slot button or the worn card): the item, its score, and for a slot button the upgrades
local function WornTip(owner, x, slot, unit, rows)
  slot = slot or (x and x.slot)
  if not slot then return end -- nothing filled in yet
  -- K17: a worn item = the plain Blizzard tooltip only
  if x and x.link then return UI.PlainItemTip(owner, x.link) end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(string.format(L.SLOT_EMPTY, ShortSlotName(slot)))
  if rows then
    if #rows > 0 then
      GameTooltip:AddLine(SheetCountText(#rows, GCA:SelectedProfession() == "Enchanting"), 0.3, 1, 0.3)
      GameTooltip:AddLine(string.format(L.SHEET_SLOT_BEST, rows[1].info.name or "?", GainText(rows[1])), 1, 1, 1, true)
    elseif x and x.unknown then
      GameTooltip:AddLine(L.SECTION_TIP_UNKNOWN, 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine(L.SECTION_TIP_NONE, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(L.SHEET_SLOT_CLICK, 0.5, 0.5, 0.5, true)
  end
  GameTooltip:Show()
end

-- worn item look on a slot button / card: icon + quality frame; not loaded = question mark; empty = the slot art
local function FillWornIcon(f, x, slot)
  if x and x.info then
    f.icon:SetTexture(x.info.icon or ItemIcon(x.link))
    f.icon:SetDesaturated(false)
    f.icon:SetAlpha(1)
    SetIconQuality(f, x.info.quality)
  elseif x and x.link then
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:SetDesaturated(true)
    f.icon:SetAlpha(0.6)
    SetIconQuality(f, nil, 0.3, 0.3, 0.3)
  else
    f.icon:SetTexture(SlotTexture(slot))
    f.icon:SetDesaturated(true)
    f.icon:SetAlpha(0.45)
    SetIconQuality(f, nil, 0.23, 0.2, 0.17)
  end
end

local function CreateSheetSlot(sheet, slot)
  local b = CreateFrame("Button", nil, sheet)
  b:SetSize(SHEET_S, SHEET_S)
  b.slot = slot
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  -- selected: a gold square 3 px larger behind the button
  b.sel = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  b.sel:SetPoint("TOPLEFT", -3, 3)
  b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
  b.sel:SetColorTexture(1, 0.82, 0, 0.9)
  b.sel:Hide()
  -- K6: the character window's own gear slot (probe: CharacterHeadSlot = 37 px button, UI-Character-Info-GearSlot
  -- 55x55 behind it, IconBorder = WhiteIconFrame tinted by quality, HighlightTexture = ButtonHilight-Square ADD);
  -- scaled to our 40 px slot. Without the atlas: the K4 dark square.
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
  if SetAtlasSafe(b.bg, "UI-Character-Info-GearSlot") then
    b.bg:SetSize(math.floor(SHEET_S * 55 / 37 + 0.5), math.floor(SHEET_S * 55 / 37 + 0.5))
    b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.gearArt = true
  else
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
  end
  AddQualityIcon(b, SHEET_S - 4, "CENTER", b, "CENTER", 0, 0, true)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  if TexOK("iconHL") then
    b.hl:SetTexture(UI.TEX.iconHL)
    if b.hl.SetBlendMode then pcall(b.hl.SetBlendMode, b.hl, "ADD") end
  else
    b.hl:SetColorTexture(1, 1, 1, 0.15)
  end
  -- selected: the same highlight, kept on (as a checked item button); the gold square only without the file
  if TexOK("iconHL") then
    b.sel:ClearAllPoints()
    b.sel:SetAllPoints()
    if b.sel.SetDrawLayer then b.sel:SetDrawLayer("OVERLAY", 6) end
    b.sel:SetTexture(UI.TEX.iconHL)
    if b.sel.SetBlendMode then pcall(b.sel.SetBlendMode, b.sel, "ADD") end
    b.selKind = "file"
  end
  -- upgrade badge: the green up arrow GearQuestForever draws (Indicator.lua:5, tinted :731), else a green "+"
  if TexOK("caretUp") then
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.badge:SetTexture(UI.TEX.caretUp)
    b.badge:SetSize(14, 18)
    b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 5, 6)
    b.badge:SetVertexColor(0.12, 1, 0.12)
    b.badgeKind = "file"
  else
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 4)
    b.badge:SetText("+")
    b.badge:SetTextColor(0.3, 1, 0.3)
    b.badgeKind = "text"
  end
  b.badge:Hide()
  b:SetScript("OnClick", function(self)
    if ModifiedDown() then
      local link = WornHyperlink(self.worn)
      if link then SafeCall(HandleModifiedItemClick, link) end
      return
    end
    UI:SelectSheetSlot(self.slot)
  end)
  SetTip(b, "sheet slot", function(self) WornTip(self, self.worn, self.slot, self.unit, self.rows or {}) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- comparison card: worn (left) or the featured craft (right: green tint, big gain)
local function CreateSheetCard(parent, best)
  local k = CreateFrame("Button", nil, parent)
  k:SetHeight(SHEET_CARD_H)
  k.isBest = best
  -- K6: no box, no green tint: the item in its reagent-slot frame and text on the page, as the profession
  -- window's schematic shows its output item
  AddQualityIcon(k, 36, "LEFT", k, "LEFT", 10, 0)
  -- three lines left of the gain (the icon frame is 40 px, centred: its top is 12 px below the card's)
  local right = best and -(SHEET_GAIN_W + 16) or -10
  -- user 2026-11-15: the item name is the first line beside the icon; "Equipped" / "Best craft" under it
  k.name = k:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  k.name:SetPoint("TOPLEFT", k.qual, "TOPRIGHT", 8, 1)
  k.name:SetPoint("TOPRIGHT", k, "TOPRIGHT", right, -11)
  k.name:SetJustifyH("LEFT")
  SingleLine(k.name)
  k.label = k:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  k.label:SetPoint("LEFT", k.qual, "RIGHT", 8, 0)
  k.label:SetPoint("RIGHT", k, "RIGHT", right, 0)
  k.label:SetJustifyH("LEFT")
  SingleLine(k.label)
  k.score = k:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  k.score:SetPoint("BOTTOMLEFT", k.qual, "BOTTOMRIGHT", 8, -1)
  k.score:SetPoint("BOTTOMRIGHT", k, "BOTTOMRIGHT", right, 11)
  k.score:SetJustifyH("LEFT")
  k.score:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(k.score)
  if best then
    k.gain = k:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    GainFont(k.gain, true)
    k.gain:SetPoint("TOPRIGHT", k, "TOPRIGHT", -10, -12)
    k.gain:SetWidth(SHEET_GAIN_W)
    k.gain:SetJustifyH("RIGHT")
    SingleLine(k.gain)
    k.points = k:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k.points:SetPoint("BOTTOMRIGHT", k, "BOTTOMRIGHT", -10, 11)
    k.points:SetWidth(SHEET_GAIN_W)
    k.points:SetJustifyH("RIGHT")
    k.points:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
    SingleLine(k.points)
  end
  SetTip(k, best and "sheet craft" or "sheet worn", function(self)
    if self.isBest then
      if self.data then ShowSuggestionTooltip(self, self.data, UI.current) end
    else
      WornTip(self, self.worn, self.slot, self.unit)
    end
  end)
  k:SetScript("OnLeave", HideTip)
  if best and k.RegisterForClicks then k:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  k:SetScript("OnClick", function(self, button)
    if self.isBest and UI.SourceClick(self, button, self.data, UI.current) then return end
    if not ModifiedDown() then return end
    local link
    if self.isBest then link = self.data and self.data.info.link else link = WornHyperlink(self.worn) end
    if link then SafeCall(HandleModifiedItemClick, link) end
  end)
  return k
end

-- one of the slot's other crafts ("More options"): icon, name, level/enchant/not-learned tag (K6: coloured text),
-- gain, the red Offer button. Click: compare it in the cards above; Shift-click: link.
local function CreateSheetAlt(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(SHEET_ALT_H)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  UI.Skin(r.hl, "rowHover")
  AddQualityIcon(r, 20, "LEFT", r, "LEFT", 3, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.name:SetPoint("LEFT", r.qual, "RIGHT", 8, 0)
  r.name:SetJustifyH("LEFT")
  SingleLine(r.name)
  r.offer = CreateOfferButton(r)
  r.gain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.gain:SetWidth(90)
  r.gain:SetJustifyH("RIGHT")
  SingleLine(r.gain)
  r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.tag:SetPoint("RIGHT", r.gain, "LEFT", -8, 0)
  r.tag:SetJustifyH("RIGHT")
  SingleLine(r.tag)
  SetTip(r, "sheet alternative", function(self)
    if not self.data then return end
    ShowSuggestionTooltip(self, self.data, UI.current) -- K17: plain item tooltip
  end)
  r:SetScript("OnLeave", HideTip)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r:SetScript("OnClick", function(self, button)
    local d = self.data
    if not d then return end
    if UI.SourceClick(self, button, d, UI.current) then return end
    if ModifiedDown() then
      if d.info.link then SafeCall(HandleModifiedItemClick, d.info.link) end
      return
    end
    UI:PickSheetRow(d)
  end)
  return r
end

local function FillSheetAlt(r, d, cur, width)
  r.data = d
  r.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
  SetIconQuality(r, d.info.quality)
  r.name:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r")
  local showOffer = UI.CanOffer(cur, d)
  r.offer:SetShown(showOffer)
  r.offer:ClearAllPoints()
  r.offer:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.gain:ClearAllPoints()
  if showOffer then r.gain:SetPoint("RIGHT", r.offer, "LEFT", -6, 0) else r.gain:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
  r.gain:SetText(RowGainText(d))
  local tag
  if d.future and d.wearAt then
    tag = Tag(LevelTag(d), C.levelTag)
  elseif d.kind == "enchant" then
    tag = Tag(L.ENCHANT_TAG, C.known)
  elseif not d.known then
    tag = Tag(L.NOT_LEARNED, (cur and cur.browse) and C.browse or C.notLearned)
  end
  r.tag:SetText(tag or "")
  local cw = 0
  if tag then
    cw = math.min(TextWidth(r.tag), 160)
    r.tag:SetWidth(cw)
    cw = cw + 8
  end
  r.tag:SetShown(tag ~= nil)
  local offerW = showOffer and ((r.offer.GetWidth and r.offer:GetWidth() or UI.OFFER_SMALL_W) + 4) or 0
  r.name:SetWidth(math.max(20, width - (3 + 24 + 8) - cw - 90 - 6 - offerW - 6))
  local a = d.future and 0.55 or 1
  for _, x in ipairs({ r.qual, r.iconBorder, r.icon, r.name, r.gain, r.tag }) do x:SetAlpha(a) end
  r.dimmed = d.future and true or false
end

local function CreateSheet(parent)
  local sh = CreateFrame("Frame", nil, parent)
  sh.slots = {}
  for _, list in ipairs({ UI.SHEET_LEFT, UI.SHEET_RIGHT, UI.SHEET_BOTTOM }) do
    for _, slot in ipairs(list) do sh.slots[slot] = CreateSheetSlot(sh, slot) end
  end
  local c = CreateFrame("Frame", nil, sh)
  sh.centre = c -- K6: no box of its own: it sits on the list panel's art like the schematic on the page
  c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.header:SetJustifyH("LEFT")
  SingleLine(c.header)
  c.count = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.count:SetJustifyH("LEFT")
  c.count:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.count)
  c.worn = CreateSheetCard(c, false)
  c.best = CreateSheetCard(c, true)
  c.arrow = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  c.arrow:SetWidth(SHEET_ARROW_W)
  c.arrow:SetJustifyH("CENTER")
  c.arrow:SetText(">")
  c.stats = {}
  for i = 1, 6 do
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    SingleLine(fs)
    c.stats[i] = fs
  end
  c.tags = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.tags:SetJustifyH("LEFT")
  c.tags:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.tags)
  c.source = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- K7: where to get a missing recipe
  c.source:SetJustifyH("LEFT")
  c.source:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(c.source)
  c.offer = CreateOfferTextButton(c, c.best, SHEET_OFFER_W)
  c.crafted = CreateCraftedBox(c, c.best)
  c.craftedLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.craftedLabel:SetJustifyH("LEFT")
  SingleLine(c.craftedLabel)
  c.none = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  c.none:SetJustifyH("LEFT")
  c.sep = c:CreateTexture(nil, "ARTWORK")
  c.sep:SetHeight(1)
  UI.Skin(c.sep, "separator")
  c.moreTitle = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.moreTitle:SetJustifyH("LEFT")
  SingleLine(c.moreTitle)
  c.alts = {}
  function c:Alt(i)
    if not self.alts[i] then self.alts[i] = CreateSheetAlt(self) end
    return self.alts[i]
  end
  sh.iw, sh.wornW, sh.bestW = 300, 110, 166
  return sh
end

-- Positions everything that depends on the panel size (UI:Layout): slot columns (spacing follows the height,
-- 4..12 px), weapon row centred under the middle panel, middle panel between the columns, card widths.
-- w, h = the sheet's size (the suggestion inset minus 4 px on each side).
function UI:LayoutSheet(w, h)
  local sh = self.sheet
  if not sh then return end
  sh.w, sh.h = w, h
  local S = SHEET_S
  local gapY = math.max(4, math.min(12, math.floor((h - 16 - 7 * S) / 6)))
  sh.gapY = gapY
  for i, slot in ipairs(UI.SHEET_LEFT) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", sh, "TOPLEFT", SHEET_COL_X, -(8 + (i - 1) * (S + gapY)))
  end
  for i, slot in ipairs(UI.SHEET_RIGHT) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", sh, "TOPRIGHT", -SHEET_COL_X, -(8 + (i - 1) * (S + gapY)))
  end
  local rowW = #UI.SHEET_BOTTOM * S + (#UI.SHEET_BOTTOM - 1) * 12
  for i, slot in ipairs(UI.SHEET_BOTTOM) do
    local b = sh.slots[slot]
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", sh, "BOTTOMLEFT", math.floor((w - rowW) / 2) + (i - 1) * (S + 12), 8)
  end
  local side = SHEET_COL_X + S + SHEET_GAP_X
  local c = sh.centre
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", sh, "TOPLEFT", side, -8)
  c:SetPoint("BOTTOMRIGHT", sh, "BOTTOMRIGHT", -side, 8 + S + 8)
  sh.cw, sh.ch = w - 2 * side, h - 8 - (8 + S + 8)
  sh.iw = sh.cw - 2 * SHEET_PAD
  sh.wornW = math.floor((sh.iw - SHEET_ARROW_W) * 0.31) -- the craft card gets more room (label + name + big gain); K8: 0.36 -> 0.31
  sh.bestW = sh.iw - SHEET_ARROW_W - sh.wornW
  self:PlaceSheet()
end

-- Stacks the middle panel's parts from the top (only the shown ones take room). c.contentH = the height used.
function UI:PlaceSheet()
  local sh = self.sheet
  if not sh then return end
  local c, P, iw = sh.centre, SHEET_PAD, sh.iw
  local y = P
  local headerW = math.min(TextWidth(c.header) + 2, math.floor(iw / 2))
  c.header:ClearAllPoints()
  c.header:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
  c.header:SetWidth(headerW)
  c.count:ClearAllPoints()
  c.count:SetPoint("TOPLEFT", c, "TOPLEFT", P + headerW + 10, -(y + 1))
  c.count:SetWidth(math.max(1, iw - headerW - 10))
  y = y + 22
  c.worn:ClearAllPoints()
  c.worn:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
  c.worn:SetWidth(sh.wornW)
  c.best:ClearAllPoints()
  c.best:SetPoint("TOPLEFT", c.worn, "TOPRIGHT", SHEET_ARROW_W, 0)
  c.best:SetWidth(sh.bestW)
  c.arrow:ClearAllPoints()
  c.arrow:SetPoint("LEFT", c.worn, "RIGHT", 0, 0)
  c.none:ClearAllPoints()
  c.none:SetPoint("TOPLEFT", c.worn, "TOPRIGHT", 16, -8)
  c.none:SetWidth(math.max(1, iw - sh.wornW - 16))
  y = y + SHEET_CARD_H + 10
  if c.mode == "upgrade" then
    local colW = math.floor(iw / 3)
    local n = c.nStats or 0
    for i, fs in ipairs(c.stats) do
      local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", c, "TOPLEFT", P + col * colW, -(y + row * SHEET_STAT_H))
      fs:SetWidth(colW - 6)
    end
    if n > 0 then y = y + math.ceil(n / 3) * SHEET_STAT_H + 4 end
    c.tags:ClearAllPoints()
    c.tags:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
    c.tags:SetWidth(iw)
    if c.hasTags then y = y + SHEET_STAT_H end
    c.source:ClearAllPoints()
    c.source:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
    c.source:SetWidth(iw)
    if c.hasSource then y = y + SHEET_STAT_H end
    -- actions: Offer at the right, the crafted box + its label left of it
    local right = P
    c.offer:ClearAllPoints()
    c.offer:SetPoint("TOPRIGHT", c, "TOPRIGHT", -right, -y)
    if c.offer:IsShown() then right = right + SHEET_OFFER_W + 14 end
    local labelW = TextWidth(c.craftedLabel)
    c.craftedLabel:SetWidth(labelW)
    c.crafted:ClearAllPoints()
    c.crafted:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(right + labelW + 4), -y)
    c.craftedLabel:ClearAllPoints()
    c.craftedLabel:SetPoint("LEFT", c.crafted, "RIGHT", 4, 0)
    if c.offer:IsShown() or c.crafted:IsShown() then y = y + 26 end
    if (c.nAlts or 0) > 0 then
      y = y + 6
      c.sep:ClearAllPoints()
      c.sep:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
      c.sep:SetPoint("TOPRIGHT", c, "TOPRIGHT", -P, -y)
      y = y + 6
      c.moreTitle:ClearAllPoints()
      c.moreTitle:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
      c.moreTitle:SetWidth(iw)
      y = y + 16
      for i = 1, c.nAlts do
        local r = c.alts[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
        r:SetWidth(iw)
        FillSheetAlt(r, r.data, UI.current, iw)
        y = y + SHEET_ALT_H + 2
      end
    end
  end
  c.contentH = y + P - 10
end

-- Fills the sheet for one member. Selected slot: kept while the same member + profession is shown and you
-- picked it; else the slot with the biggest upgrade (recomputed on every refresh until you pick one).
-- why: the empty-state reason when the member has no suggestion at all (shown in the middle panel).
function UI:UpdateSheet(cur, list, prof, why)
  local sh = self.sheet
  local forKey = tostring(cur.key) .. "|" .. tostring(prof)
  if self.sheetFor ~= forKey then self.sheetFor, self.sheetAuto, self.sheetPickSug = forKey, true, nil end
  if self.sheetAuto or not self.sheetSlot then self.sheetSlot = UI.SheetDefaultSlot(list) end
  local unit = GCA:UnitLabel(cur.weights)
  local enchanting = prof == "Enchanting"
  for slot, b in pairs(sh.slots) do
    local rows, _, worn = UI.SheetRows(list, slot)
    b.worn, b.rows, b.unit = worn, rows, unit
    FillWornIcon(b, worn, slot)
    b.empty = not (worn and worn.link)
    b.selected = slot == self.sheetSlot
    b.sel:SetShown(b.selected)
    local allFuture = #rows > 0
    for _, r in ipairs(rows) do if not r.future then allFuture = false end end
    b.hasUpgrade = #rows > 0
    b.badge:SetShown(b.hasUpgrade)
    b.badge:SetAlpha(allFuture and 0.5 or 1) -- only too-high-level crafts: a dimmed arrow
  end
  local c = sh.centre
  local slot = self.sheetSlot
  local rows, sec, worn = UI.SheetRows(list, slot)
  local d = rows[1]
  if self.sheetPickSug then
    for _, r in ipairs(rows) do if r == self.sheetPickSug then d = r end end
  end
  c.slot, c.rows, c.featured = slot, rows, d
  c.header:SetText(ShortSlotName(slot))
  c.count:SetText(SheetCountText(#rows, enchanting))
  c.worn.slot, c.worn.unit = slot, unit
  if d then
    c.mode = "upgrade"
    local dUnit = GCA:UnitLabel(d.e)
    FillWornIcon(c.worn, worn, slot)
    c.worn.worn = worn
    c.worn.label:SetText(L.SHEET_WORN)
    c.worn.name:SetText(worn and worn.info and (Hex(QualityColor(worn.info.quality)) .. (worn.info.name or "?") .. "|r")
      or (C.dim .. (worn and worn.link and "?" or L.SECTION_NOTHING) .. "|r"))
    c.worn.score:SetText(d.status ~= "empty-slot" and string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.oldScore or 0), dUnit) or "")
    local k = c.best
    k.data = d
    local label
    if d ~= rows[1] then label = L.SHEET_PICKED elseif d.kind == "enchant" then label = L.SHEET_BEST_ENCH else label = L.SHEET_BEST end
    k.label:SetText(label)
    k.icon:SetTexture(d.info.icon or ItemIcon(d.cand.itemID))
    SetIconQuality(k, d.info.quality)
    k.name:SetText(Hex(QualityColor(d.info.quality)) .. (d.info.name or "?") .. "|r")
    k.score:SetText(string.format(L.SECTION_SCORE, GCA:ToPoints(d.e, d.newScore or 0), dUnit))
    local big, small = CardGain(d)
    k.gain:SetText(big)
    k.points:SetText(small)
    local a = d.future and 0.55 or 1
    for _, x in ipairs({ k.qual, k.iconBorder, k.icon, k.name, k.gain }) do x:SetAlpha(a) end
    k.dimmed = d.future and true or false
    k:Show()
    c.arrow:Show()
    -- stat differences (only when both sides have stat data) + the tags
    local diffs, partial = UI.StatDiff(d)
    c.nStats = 0
    for i, fs in ipairs(c.stats) do
      local r = diffs and diffs[i]
      if r then fs:SetText(UI.StatText(r, true)); fs:Show(); c.nStats = i else fs:SetText(""); fs:Hide() end
    end
    c.diffs = diffs
    local tags = CraftTags(d, cur, true)
    if diffs and #diffs > #c.stats then tags[#tags + 1] = { string.format(L.STATS_MORE, #diffs - #c.stats) } end
    if partial then tags[#tags + 1] = { L.STATS_PARTIAL } end
    c.tags:SetText(TagLine(tags))
    c.hasTags = #tags > 0
    c.tags:SetShown(c.hasTags)
    local line = UI.SourceLine(d, cur)
    c.hasSource = line ~= nil
    c.source:SetText(line or "")
    c.source:SetShown(c.hasSource)
    local showOffer, showCheck, mark = RightState(d, cur)
    c.offer:SetShown(showOffer)
    c.crafted:SetShown(showCheck)
    c.crafted:SetChecked(mark ~= nil)
    c.craftedLabel:SetText(d.kind == "enchant" and L.ENCHANTED or L.CRAFTED)
    c.craftedLabel:SetShown(showCheck)
    c.none:Hide()
    local others = {}
    for _, r in ipairs(rows) do if r ~= d then others[#others + 1] = r end end
    for i, r in ipairs(others) do
      local alt = c:Alt(i)
      alt.data = r
      alt:Show()
    end
    for i = #others + 1, #c.alts do c.alts[i]:Hide(); c.alts[i].data = nil end
    c.nAlts = #others
    c.sep:SetShown(#others > 0)
    c.moreTitle:SetText(L.SHEET_MORE)
    c.moreTitle:SetShown(#others > 0)
  else
    c.mode = "none"
    FillWornIcon(c.worn, worn, slot)
    c.worn.worn = worn
    c.worn.label:SetText(L.SHEET_WORN)
    c.worn.name:SetText(worn and worn.info and (Hex(QualityColor(worn.info.quality)) .. (worn.info.name or "?") .. "|r")
      or (C.dim .. (worn and worn.link and "?" or L.SECTION_NOTHING) .. "|r"))
    c.worn.score:SetText(worn and worn.score and string.format(L.SECTION_SCORE, worn.score, unit) or "")
    c.best:Hide(); c.best.data = nil
    c.arrow:Hide()
    for _, fs in ipairs(c.stats) do fs:SetText(""); fs:Hide() end
    c.nStats, c.diffs, c.hasTags = 0, nil, false
    c.tags:SetText(""); c.tags:Hide()
    c.hasSource = false
    c.source:SetText(""); c.source:Hide()
    c.offer:Hide(); c.crafted:Hide(); c.craftedLabel:Hide()
    for _, r in ipairs(c.alts) do r:Hide(); r.data = nil end
    c.nAlts = 0
    c.sep:Hide(); c.moreTitle:Hide()
    local msg
    if #list == 0 and why and why ~= "" then
      msg = why
    elseif worn and worn.unknown then
      msg = L.SECTION_TIP_UNKNOWN
    elseif enchanting then
      msg = L.SHEET_NONE_ENCH
    else
      msg = L.SHEET_NONE
    end
    c.none:SetText(msg)
    c.none:Show()
  end
  self:PlaceSheet()
end

function UI:SelectSheetSlot(slot)
  self.sheetSlot, self.sheetAuto, self.sheetPickSug = slot, false, nil
  self:Refresh()
end

-- an alternative clicked: compare it in the cards (the slot stays, now as your pick)
function UI:PickSheetRow(d)
  self.sheetPickSug, self.sheetAuto = d, false
  self:Refresh()
end

-- K6: native dropdowns. A DropdownButton made from the client's WowStyle1DropdownTemplate /
-- WowStyle1FilterDropdownTemplate (both confirmed by the probe; the profession recipe list's "Filter" button IS the
-- filter template, 90x18, common-dropdown-b-button), created in pcall as BugSack config.lua:47 and WhatsTraining
-- Crafting\SkillsRecipeList.lua:30 do, driven by SetupMenu(generator) with the menu description calls Forever
-- addons use: CreateRadio / CreateCheckbox (BugSack config.lua:107-131, ForeverLFG FilterUI.lua:57-115),
-- CreateButton / CreateDivider / CreateTitle (ForeverLFG FilterUI.lua:95-114), OverrideText (Leatrix_Plus
-- .lua:17094). nil where the client can't make one; every caller then builds a plain fallback.
local function NewDropdown(parent, template, w, h)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, template)
  if not (ok and dd and type(dd.SetupMenu) == "function") then
    if ok and dd and dd.Hide then dd:Hide() end
    return nil
  end
  dd:SetSize(w, h)
  dd.native = true
  return dd
end
UI.NewDropdown = NewDropdown
-- rebuild an open menu / the shown text after a setting changed
local function RefreshDropdown(dd, text)
  if not (dd and dd.native) then return end
  if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end
  if text and dd.OverrideText then pcall(dd.OverrideText, dd, text) end
end
UI.RefreshDropdown = RefreshDropdown

local CreateModeSwitch
do
-- The member view's variant (K4: "Character sheet | List"). K6: NOT a custom segmented control any more but a
-- WowStyle1DropdownTemplate "View: Character sheet" with one radio per variant - what Blizzard does for a display
-- mode inside a panel (a dropdown in the panel's header line; the window's own tabs already switch the two
-- views, and side tabs are the profession window's PROFESSION switch). Fallback: one red button that switches
-- to the other variant (its text names the shown one).
UI.MEMBER_MODES = { { "sheet", "MVIEW_SHEET" }, { "list", "MVIEW_LIST" } }
UI.TOGGLE_W = 170
function UI.ModeMenu(_, root)
  for _, def in ipairs(UI.MEMBER_MODES) do
    root:CreateRadio(L[def[2]], function(mode) return UI.MemberMode() == mode end, function(mode) UI:SetMemberMode(mode) end, def[1])
  end
end
local function ModeLabel(mode)
  return string.format(L.MVIEW_LABEL, L[mode == "list" and "MVIEW_LIST" or "MVIEW_SHEET"])
end
UI.ModeLabel = ModeLabel
local function ModeTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
  GameTooltip:SetText(ModeLabel(UI.MemberMode()), 1, 1, 1)
  GameTooltip:AddLine(L.MVIEW_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end
CreateModeSwitch = function(parent)
  local dd = NewDropdown(parent, "WowStyle1DropdownTemplate", UI.TOGGLE_W, 22)
  if dd then
    dd:SetupMenu(UI.ModeMenu)
    KeepNativeHover(dd, "member view", ModeTip)
  else
    dd = NewTextButton(parent, UI.TOGGLE_W, 22, ModeLabel("sheet"))
    dd:SetScript("OnClick", function() UI:SetMemberMode(UI.MemberMode() == "list" and "sheet" or "list") end)
    SetTip(dd, "member view", ModeTip)
    dd:SetScript("OnLeave", GameTooltip_Hide)
  end
  function dd:Paint(mode)
    self.mode = mode
    if self.native then RefreshDropdown(self, ModeLabel(mode)) else self:SetText(ModeLabel(mode)) end
  end
  return dd
end
end

-- Switches the member view's variant; the selected member (and the sheet's slot) stay.
function UI:SetMemberMode(mode)
  if not (GCA.db and GCA.db.settings) then return end
  GCA.db.settings.memberView = mode == "list" and "list" or "sheet"
  self:ApplyMemberMode()
  self:Refresh()
end

function UI:ApplyMemberMode()
  local mode = UI.MemberMode()
  if self.modeToggle then self.modeToggle:Paint(mode) end
  if self.sugList then self.sugList:SetShown(mode == "list") end
  if self.sheet and mode ~= "sheet" then self.sheet:Hide() end
end

---------------------------------------------------------------------------
-- Pickers, menus, dialogs
---------------------------------------------------------------------------
-- top: y of the first row (default 6; the options menu has the slider above its rows)
local function PopupRow(pop, i, width, top)
  local b = pop.buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, pop)
  b:SetSize(width, 18)
  b:SetPoint("TOPLEFT", 6, -(top or 6) - (i - 1) * 18)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 4, 0)
  SingleLine(b.text)
  pop.buttons[i] = b
  return b
end

-- K1: the picked entry of a popup gets the check-mark texture instead of an ASCII "> ". Returns a text prefix
-- (only where the texture can't be drawn).
local function SetRowMark(b, on)
  if not b.mark then
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetSize(14, 14)
    b.mark:SetPoint("LEFT", 2, 0)
    b.markOK = TexOK("check")
    if b.markOK then b.mark:SetTexture(UI.TEX.check) end
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 18, 0)
  end
  b.mark:SetShown(on and b.markOK or false)
  return (on and not b.markOK) and "> " or ""
end
UI.SetRowMark = SetRowMark

-- Spec picker: a plain popup list (no dropdown API needed), manual pick saved per member (F4).
-- K5 (Member mockup): the spec control = icon, small "Spec." label above the spec name, caret. No spec icon is
-- known on this client (Spec.lua has none), so the icon is the class icon: the "classicon-<class>" atlas when
-- GetAtlasInfo has it, else the class-circles file with CLASS_ICON_TCOORDS (ForeverLFG_GroupQuest
-- QuestMatchesUI.lua:163-169), else no icon (text only). Returns "atlas" / "file" / nil.
function UI.SetClassIcon(tex, class)
  if type(class) ~= "string" then return nil end
  if SetAtlasSafe(tex, "classicon-" .. class:lower()) then
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    return "atlas"
  end
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if type(c) == "table" and c[4] and TexOK("classIcons") then
    tex:SetTexture(UI.TEX.classIcons)
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
    return "file"
  end
  return nil
end
local CreateSpecPicker
do
UI.SPEC_BTN_W = 200
-- K6: the spec picker = the class icon + a native WowStyle1DropdownTemplate (radios "Automatic" + the class's specs,
-- the shown text = the member's spec via OverrideText). The K5 custom box (button art, "SPEC." label, caret) is
-- gone. Fallback: the class icon + a red button that opens the 0.5.0 popup list.
local function ChooseSpec(spec)
  local cur = UI.current
  if not (cur and cur.class) then return end
  GCA:SetManualSpec(cur.key, cur.class, spec)
  UI:Refresh()
end
function UI.SpecMenu(_, root)
  local d = UI.current
  if not (d and d.class) then return end
  root:CreateRadio(L.SPEC_AUTOMATIC, function() return not GCA.db.specManual[d.key] end, function() ChooseSpec(nil) end)
  for _, spec in ipairs(GCA.SPECS_OF[d.class] or {}) do
    root:CreateRadio(GCA:SpecName(d.class, spec), function(v)
      local m = GCA.db.specManual[d.key]
      return m ~= nil and m.spec == v
    end, function(v) ChooseSpec(v) end, spec)
  end
end
local function SpecTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.SPEC_TIP_TITLE, 1, 1, 1)
  GameTooltip:AddLine(L.SPEC_TIP, nil, nil, nil, true)
  if UI.current and UI.current.member then GameTooltip:AddLine(SpecHowText(UI.current), 1, 1, 1, true) end
  GameTooltip:Show()
end
CreateSpecPicker = function(parent, window)
  local btn = CreateFrame("Frame", nil, parent)
  btn:SetSize(UI.SPEC_BTN_W, 32)
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetSize(22, 22)
  btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
  local dd = NewDropdown(btn, "WowStyle1DropdownTemplate", UI.SPEC_BTN_W - 28, 22)
  local pop
  if dd then
    dd:SetupMenu(UI.SpecMenu)
    KeepNativeHover(dd, "spec button", SpecTip)
  else
    dd = NewTextButton(btn, UI.SPEC_BTN_W - 28, 22, "?")
    pop = NewPopup(parent)
    pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    pop.buttons = {}
    function pop:Fill(d)
      local list = { { nil, L.SPEC_AUTOMATIC } }
      for _, spec in ipairs(GCA.SPECS_OF[d.class or ""] or {}) do list[#list + 1] = { spec, GCA:SpecName(d.class, spec) } end
      for i, item in ipairs(list) do
        local b = self.buttons[i]
        if not b then
          b = PopupRow(self, i, 190)
          b:SetScript("OnClick", function(selfBtn) self:Hide(); ChooseSpec(selfBtn.spec) end)
        end
        b.spec = item[1]
        local manual = GCA.db.specManual[d.key]
        local picked = (item[1] == nil and not manual) or (manual and manual.spec == item[1])
        b.text:SetText(SetRowMark(b, picked) .. item[2])
        b:Show()
      end
      for i = #list + 1, #self.buttons do self.buttons[i]:Hide() end
      self:SetSize(202, 12 + #list * 18)
    end
    dd:SetScript("OnClick", function()
      if pop:IsShown() then pop:Hide() return end
      if not (UI.current and UI.current.class) then return end
      pop:Fill(UI.current)
      pop:Show()
    end)
    SetTip(dd, "spec button", SpecTip)
    dd:SetScript("OnLeave", GameTooltip_Hide)
    window:HookScript("OnHide", function() pop:Hide() end)
  end
  dd:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
  btn.dropdown = dd
  function btn:SetText(t)
    self.text = t
    if self.dropdown.native then RefreshDropdown(self.dropdown, t) else self.dropdown:SetText(t) end
  end
  function btn:GetText() return self.text end
  -- icon for this class (or none); the dropdown keeps its place
  function btn:SetClass(class)
    if self.iconClass == class and self.iconKind ~= nil then return end
    self.iconClass = class
    self.iconKind = UI.SetClassIcon(self.icon, class)
    self.icon:SetShown(self.iconKind ~= nil)
  end
  btn:SetClass(nil)
  btn:SetText("?")
  return btn, pop
end
end

-- Profession selector (G3/G6.1): your professions, then "browse" the other gear professions.
-- K6: the profession window's own rank bar (probe: ProfessionsFrame.CraftingPage.RankBar - Background =
-- Professions-skillbar-bg 451x29 and Border = Professions-skillbar-frame 451x29 at TOPLEFT 0,0, Fill 441x18 at 5,-3,
-- the rank text in Number12FontOutline centred, ExpansionDropdownButton 19x19 at RIGHT -6,-3 whose arrow is
-- common-dropdown-a-button 27x27 at RIGHT 2,-3). Our fill is a StatusBar with the proven skill-bar file (the
-- client's own Fill draws through a mask texture we don't copy). The arrow is an intrinsic DropdownButton
-- (ForeverLFG SettingsUI.lua:14) whose menu has a radio per profession; without it a plain button with the same
-- arrow opens the 0.5.0 popup (as does a click on the bar then). Missing bar atlases: a dark track, 1 px border.
-- The K5 round button / disc is gone.
UI.PROF_BAR_W, UI.PROF_DROP, UI.PROF_BAR_H = 340, 19, 29 -- K8: 300 -> 340 (centred under the title)
-- K7 (lead): the client's RankBar fill is per profession (probe: ProfessionsFrame.CraftingPage.RankBar.Fill = atlas
-- Skillbar_Fill_Flipbook_Leatherworking 441x18 at 5,-3, a flipbook sheet: texcoords 0.733..0.767 = row 23 of 30;
-- .Flare = Skillbar_Flare_Leatherworking 53x16, ADD, at the fill's right end; the client cuts the fill with the
-- MaskTexture Professions-skillbar-mask). Ours: one still frame of the sheet (row 1), cut by SetWidth + texcoords
-- like a status bar; the other professions' names follow the same pattern and are checked with GetAtlasInfo,
-- else Leatherworking's, else the K5/K6 status bar / plain fill.
-- K8 (probe.rankbar): the client animates the fill with a FlipBook (rows 30, columns 2, 60 frames, 2 s, played once on a
-- change, RankBar.BarAnimation) and fades the flare (Alpha, 1 s). Ours: the fill at its FULL width inside a clipping
-- frame as wide as rank/max (instead of the client's MaskTexture), so the FlipBook can run on it; one still frame
-- (row 1, column 1) at rest; the animation plays once when the window shows a new rank / profession. Without
-- SetClipsChildren: the K7 cut by width + texcoords, no animation. Animation API missing: still frame only.
UI.RANKBAR = { fill = "Skillbar_Fill_Flipbook_", flare = "Skillbar_Flare_", rows = 30, cols = 2, frames = 60, duration = 2,
  defaultFill = { atlas = "Skillbar_Fill_Flipbook_Leatherworking" }, defaultFlare = { atlas = "Skillbar_Flare_Leatherworking" } }
function UI.RankBarAtlases(prof)
  local R = UI.RANKBAR
  local fill, flare = R.fill .. tostring(prof), R.flare .. tostring(prof)
  if not HasAtlas(fill) then fill = R.defaultFill.atlas end
  if not HasAtlas(flare) then flare = R.defaultFlare.atlas end
  local info = HasAtlas(fill) and C_Texture.GetAtlasInfo(fill)
  if type(info) ~= "table" or type(info.leftTexCoord) ~= "number" or type(info.rightTexCoord) ~= "number"
     or type(info.topTexCoord) ~= "number" or type(info.bottomTexCoord) ~= "number" then
    return nil
  end
  return fill, HasAtlas(flare) and flare or nil, info
end
function UI.ProfMenu(_, root)
  local own, trusted = GCA:OwnProfessions()
  local mine, others = {}, {}
  for _, p in ipairs(GCA.PROFESSIONS) do
    if not trusted or own[p.key] then mine[#mine + 1] = p.key else others[#others + 1] = p.key end
  end
  local function radio(k)
    root:CreateRadio(ProfLabel(k, true), function(v) return GCA:SelectedProfession() == v end,
      function(v) GCA:SelectProfession(v); UI:Refresh() end, k)
  end
  for _, k in ipairs(mine) do radio(k) end
  if #others > 0 then
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateTitle then root:CreateTitle(L.PROF_BROWSE_HEADER) end
    for _, k in ipairs(others) do radio(k) end
  end
end
local function CreateProfessionPicker(parent, window)
  local BW, BH = UI.PROF_BAR_W, UI.PROF_BAR_H
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BW, BH)
  -- the fill area (5,-3, 18 px high, as the client's Fill)
  local track = CreateFrame("Frame", nil, btn)
  track:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -3)
  track:SetSize(BW - 10, 18)
  btn.track = track
  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  local top = CreateFrame("Frame", nil, btn) -- border + text above the fill
  top:SetAllPoints(btn)
  btn.top = top
  btn.border = top:CreateTexture(nil, "ARTWORK")
  if SetAtlasSafe(btn.bg, "Professions-skillbar-bg") and SetAtlasSafe(btn.border, "Professions-skillbar-frame") then
    btn.bg:SetAllPoints(btn)
    btn.border:SetAllPoints(btn)
    btn.art = "atlas"
  else
    btn.bg:SetAllPoints(track)
    btn.bg:SetColorTexture(0.04, 0.05, 0.1, 1)
    btn.border:Hide()
    AddBorder(track, 0.54, 0.46, 0.34, 1)
    btn.art = "plain"
  end
  local ok, bar
  if btn.art == "atlas" and UI.RankBarAtlases(GCA:SelectedProfession()) then
    -- K7: the client's per-profession fill + flare (see UI.RANKBAR); K8: inside a clipping frame, animated
    local clip = CreateFrame("Frame", nil, track)
    clip:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    clip:SetSize(BW - 10, 18)
    local holder = track
    if clip.SetClipsChildren and pcall(clip.SetClipsChildren, clip, true) then
      btn.clip = clip
      holder = CreateFrame("Frame", nil, clip)
      holder:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
      holder:SetSize(BW - 10, 18)
    else
      clip:Hide()
    end
    btn.fill = holder:CreateTexture(nil, "ARTWORK")
    btn.fill:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    btn.fill:SetHeight(18)
    if btn.clip then btn.fill:SetWidth(BW - 10) end
    btn.flare = track:CreateTexture(nil, "ARTWORK", nil, 2)
    btn.flare:SetSize(53, 16)
    btn.flare:SetPoint("RIGHT", btn.clip or btn.fill, "RIGHT", 0, 0)
    -- the FlipBook (every call guarded: animation API names as the probe read them back)
    if btn.clip and btn.fill.CreateAnimationGroup then
      local R = UI.RANKBAR
      local ok = pcall(function()
        local ag = btn.fill:CreateAnimationGroup()
        local a = ag:CreateAnimation("FlipBook")
        a:SetFlipBookRows(R.rows); a:SetFlipBookColumns(R.cols); a:SetFlipBookFrames(R.frames); a:SetDuration(R.duration)
        if ag.SetLooping then ag:SetLooping("NONE") end
        -- back to the still frame when it ends (unverified whether the client keeps the last frame itself)
        if ag.SetScript then
          pcall(ag.SetScript, ag, "OnFinished", function()
            local tc = btn.stillTC
            if tc then btn.fill:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
          end)
        end
        btn.anim = ag
      end)
      if not ok then btn.anim = nil end
    end
    if btn.flare.SetBlendMode then pcall(btn.flare.SetBlendMode, btn.flare, "ADD") end
    btn.barKind = "atlas"
  else
    ok, bar = pcall(CreateFrame, "StatusBar", nil, track)
  end
  if btn.barKind == "atlas" then
    -- done above
  elseif ok and bar and bar.SetMinMaxValues and bar.SetValue and bar.SetStatusBarTexture and TexOK("skillBar")
     and pcall(bar.SetStatusBarTexture, bar, UI.TEX.skillBar) then
    bar:SetAllPoints(track)
    bar:SetMinMaxValues(0, 1)
    local c = UI.SKIN.skillBar.tint
    if bar.SetStatusBarColor then pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3]) end
    btn.bar, btn.barKind = bar, "statusbar"
  else
    if ok and bar and bar.Hide then bar:Hide() end
    btn.fill = track:CreateTexture(nil, "ARTWORK")
    btn.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    btn.fill:SetHeight(18)
    local c = UI.SKIN.skillBar.color
    btn.fill:SetColorTexture(c[1], c[2], c[3], c[4])
    btn.barKind = "fill"
  end
  if top.SetFrameLevel and btn.GetFrameLevel then top:SetFrameLevel((btn:GetFrameLevel() or 0) + 3) end
  btn.label = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  NativeFont(btn.label, "Number12FontOutline")
  btn.label:SetPoint("CENTER", track, "CENTER", 0, 0)
  btn.label:SetWidth(BW - 60)
  btn.label:SetJustifyH("CENTER")
  SingleLine(btn.label)
  -- the arrow (ExpansionDropdownButton look)
  local okd, drop = pcall(CreateFrame, "DropdownButton", nil, top)
  if okd and drop and type(drop.SetupMenu) == "function" then
    drop.native = true
    drop:SetupMenu(UI.ProfMenu)
  else
    if okd and drop and drop.Hide then drop:Hide() end
    drop = CreateFrame("Button", nil, top)
  end
  drop:SetSize(UI.PROF_DROP, UI.PROF_DROP)
  drop:SetPoint("RIGHT", btn, "TOPRIGHT", -6, -12)
  drop.arrow = drop:CreateTexture(nil, "ARTWORK")
  if SetAtlasSafe(drop.arrow, "common-dropdown-a-button") then
    drop.arrow:SetSize(27, 27)
    drop.arrow:SetPoint("RIGHT", drop, "RIGHT", 2, -3)
    drop.hl = drop:CreateTexture(nil, "HIGHLIGHT")
    SetAtlasSafe(drop.hl, "common-dropdown-a-button")
    drop.hl:SetAllPoints(drop.arrow)
    if drop.hl.SetBlendMode then pcall(drop.hl.SetBlendMode, drop.hl, "ADD") end
    drop.hl:SetAlpha(0.4)
    drop.arrowKind = "atlas"
  elseif TexOK("caretDown") then
    drop.arrow:SetTexture(UI.TEX.caretDown)
    drop.arrow:SetSize(12, 12)
    drop.arrow:SetPoint("CENTER", drop, "CENTER", 0, -1)
    drop.arrowKind = "file"
  else
    drop.arrow:Hide()
    drop.text = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    drop.text:SetPoint("CENTER")
    drop.text:SetText("v")
    drop.arrowKind = "text"
  end
  btn.drop = drop
  -- text, fill = rank / maxRank (0 when unknown / browsing)
  function btn:SetSkill(text, rank, maxRank, prof)
    self.label:SetText(text)
    local ratio = 0
    if type(rank) == "number" and type(maxRank) == "number" and maxRank > 0 then ratio = math.max(0, math.min(1, rank / maxRank)) end
    self.ratio = ratio
    if self.barKind == "atlas" then
      local fill, flare, info = UI.RankBarAtlases(prof or GCA:SelectedProfession())
      if fill then
        SetAtlasSafe(self.fill, fill)
        -- one frame of the sheet: 1 of 30 rows, 1 of 2 columns
        local l, r, t = info.leftTexCoord, info.rightTexCoord, info.topTexCoord
        local fh = math.min(info.bottomTexCoord - t, 1 / UI.RANKBAR.rows)
        local fw = (r - l) / UI.RANKBAR.cols
        if self.clip then
          self.stillTC = { l, l + fw, t, t + fh }
          self.fill:SetTexCoord(l, l + fw, t, t + fh)
          self.clip:SetWidth(math.max(1, (BW - 10) * ratio))
        else
          self.fill:SetTexCoord(l, l + fw * math.max(ratio, 0.001), t, t + fh)
          self.fill:SetWidth(math.max(1, (BW - 10) * ratio))
        end
        self.fillAtlas, self.flareAtlas = fill, flare
        if flare then SetAtlasSafe(self.flare, flare) end
        -- K8: play the FlipBook once per new rank / profession (as the client does on a change)
        local key = tostring(prof) .. ":" .. tostring(rank) .. "/" .. tostring(maxRank)
        if self.anim and self.animKey ~= key and ratio > 0 then
          self.animKey = key
          if self.anim.Stop then pcall(self.anim.Stop, self.anim) end
          SetAtlasSafe(self.fill, fill) -- the whole sheet for the FlipBook (it steps through its 30x2 frames)
          self.animPlayed = pcall(self.anim.Play, self.anim)
        end
      end
      self.fill:SetShown(ratio > 0 and fill ~= nil)
      self.flare:SetShown(ratio > 0 and ratio < 1 and self.flareAtlas ~= nil and fill ~= nil)
    elseif self.barKind == "statusbar" then
      self.bar:SetValue(ratio)
    else
      self.fill:SetWidth(math.max(1, (BW - 10) * ratio))
      self.fill:SetShown(ratio > 0)
    end
    if self.drop.native then RefreshDropdown(self.drop) end
  end
  function btn:SetLabel(t) self:SetSkill(t) end
  btn:SetLabel(L.PROF_TIP_TITLE)
  local function tip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.PROF_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.PROF_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end
  SetTip(btn, "profession button", tip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  if drop.native then
    KeepNativeHover(drop, "profession button", tip)
    return btn, nil
  end
  -- fallback: the 0.5.0 popup list, opened by the arrow and the bar
  local pop = NewPopup(parent)
  pop.buttons = {}
  function pop:Fill()
    local own, trusted = GCA:OwnProfessions()
    local mine, others = {}, {}
    for _, p in ipairs(GCA.PROFESSIONS) do
      if not trusted or own[p.key] then mine[#mine + 1] = p.key else others[#others + 1] = p.key end
    end
    local list = {}
    for _, k in ipairs(mine) do list[#list + 1] = { prof = k } end
    if #others > 0 then
      list[#list + 1] = { header = L.PROF_BROWSE_HEADER }
      for _, k in ipairs(others) do list[#list + 1] = { prof = k } end
    end
    local sel = GCA:SelectedProfession()
    for i, item in ipairs(list) do
      local b = self.buttons[i]
      if not b then
        b = PopupRow(self, i, 260)
        b:SetScript("OnClick", function(selfBtn)
          if not selfBtn.prof then return end
          GCA:SelectProfession(selfBtn.prof)
          pop:Hide()
          UI:Refresh()
        end)
      end
      b.prof = item.prof
      if item.header then
        SetRowMark(b, false)
        b.text:SetText(C.dim .. item.header .. "|r")
      else
        b.text:SetText(SetRowMark(b, item.prof == sel) .. ProfLabel(item.prof, true))
      end
      b:Show()
    end
    for i = #list + 1, #self.buttons do self.buttons[i]:Hide() end
    self:SetSize(272, 12 + #list * 18)
  end
  pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
  local function toggle()
    if pop:IsShown() then pop:Hide() return end
    pop:Fill()
    pop:Show()
  end
  for _, b in ipairs({ btn, drop }) do
    b:SetScript("OnClick", toggle)
    SetTip(b, "profession button", tip)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  window:HookScript("OnHide", function() pop:Hide() end)
  return btn, pop
end

UI.CreateProfessionPicker = CreateProfessionPicker -- K7: for the rank bar test

-- Filter / options menu (H2 L5: replaces the five bottom checkboxes).
UI.FILTERS = {
  { key = "showUnlearned", label = "FILTER_UNLEARNED", tip = "FILTER_UNLEARNED_TIP" },
  { key = "lookahead", label = "FILTER_LOOKAHEAD", tip = "FILTER_LOOKAHEAD_TIP" },
  -- K5: "Read gear automatically" (target, group, mouseover) replaces "Auto-inspect target"; "Hide offline" is gone
  -- (it only hid offline members without gear, and those are no longer listed at all)
  { key = "autoInspect", label = "FILTER_AUTOINSPECT", tip = "FILTER_AUTOINSPECT_TIP" },
  { key = "sync", label = "FILTER_SYNC", tip = "FILTER_SYNC_TIP" },
}
function UI.ToggleSetting(key)
  local s = GCA.db.settings
  s[key] = not s[key]
  if key == "sync" and s.sync and GCA.SyncRetry then GCA:SyncRetry() end
  UI:Refresh()
  return s[key]
end

local CreateFilterMenu
do
-- K6: the toggles live in the profession window's own "Filter" dropdown (WowStyle1FilterDropdownTemplate): one in
-- the guild-needs filter bar (right of the search), one at the top right of the member list (where the recipe
-- list has its Filter, TOPRIGHT -8,-9, 90x18). Menu: a check box per toggle (with its tooltip), "Include offline
-- members (n)", a divider, "Edit whisper text...". The leveling-bonus slider is no menu entry: it sits in the
-- bottom bar (CreateSurvivalSlider). Fallback: a red "Filter" button opening the 0.5.0 popup with the same rows.
UI.FILTER_W, UI.FILTER_H = 90, 18
local OPTIONS_W = 300
local function FilterEntries()
  local entries = {}
  for _, def in ipairs(UI.FILTERS) do entries[#entries + 1] = def end
  entries[#entries + 1] = { needsOffline = true, label = "NEEDS_OFFLINE", tip = "NEEDS_OFFLINE_TIP" }
  entries[#entries + 1] = { action = "whisper", label = "EDIT_WHISPER", tip = "EDIT_WHISPER_TIP" }
  return entries
end
local function EntryLabel(def)
  if def.needsOffline then return string.format(L.NEEDS_OFFLINE, UI.offlineN or 0) end
  return L[def.label]
end
local function EntryOn(def)
  local s = GCA.db and GCA.db.settings or {}
  if def.needsOffline then return s.needsOffline and true or false end
  return def.key ~= nil and s[def.key] and true or false
end
local function EntryDo(def)
  if def.action == "whisper" then UI:OpenWhisperEditor(); return end
  if def.needsOffline then UI:SetNeedsOffline(not EntryOn(def)); return end
  UI.ToggleSetting(def.key)
end
UI.FilterEntryDo = EntryDo
-- K11 (user): the leveling-bonus slider moved out of the bottom bar into the Filter menu: a submenu with the
-- values 0/25/50/75/100 % as radio entries (the menu can't hold a slider). Applied like the slider did.
UI.SURVIVAL_STEPS = { 0, 25, 50, 75, 100 }
function UI.SetSurvival(v)
  if not (GCA.db and GCA.db.settings) then return end
  if math.abs(GCA:SurvivalShare() * 100 - v) < 0.5 then return end
  GCA.db.settings.survival = v / 100
  GCA:InvalidateScores()
  UI:Refresh()
end
local function SurvivalSubmenu(root)
  local a, b = G("SPELL_STAT3_NAME"), G("SPELL_STAT5_NAME")
  local cur = math.floor(GCA:SurvivalShare() * 100 + 0.5)
  local sub = root:CreateButton(string.format(L.SLIDER_LABEL, a, b, cur))
  if type(sub) ~= "table" or not sub.CreateRadio then return false end
  if sub.SetTooltip then
    pcall(sub.SetTooltip, sub, function(tooltip)
      tooltip:SetText(string.format(L.SLIDER_TIP_TITLE, a, b), 1, 1, 1)
      tooltip:AddLine(string.format(L.SLIDER_TIP, a, b), nil, nil, nil, true)
    end)
  end
  for _, v in ipairs(UI.SURVIVAL_STEPS) do
    sub:CreateRadio(v .. " %", function(x) return math.floor(GCA:SurvivalShare() * 100 + 0.5) == x end,
      function(x) UI.SetSurvival(x) end, v)
  end
  return true
end
function UI.FilterMenu(_, root)
  for _, def in ipairs(FilterEntries()) do
    local e
    if def.action then
      if root.CreateDivider then root:CreateDivider() end
      local ok, made = pcall(SurvivalSubmenu, root)
      UI.survivalInMenu = ok and made == true
      e = root:CreateButton(EntryLabel(def), function() EntryDo(def) end)
    else
      e = root:CreateCheckbox(EntryLabel(def), function() return EntryOn(def) end, function() EntryDo(def) end)
    end
    -- entry tooltips as WarEffortScout MapPins.lua:2004 sets them (guarded)
    if type(e) == "table" and e.SetTooltip then
      pcall(e.SetTooltip, e, function(tooltip)
        tooltip:SetText(EntryLabel(def), 1, 1, 1)
        tooltip:AddLine(L[def.tip], nil, nil, nil, true)
      end)
    end
  end
end
local function FilterTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(L.FILTER_BUTTON, 1, 1, 1)
  GameTooltip:AddLine(L.OPTIONS_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end
-- K8: the Filter button's reset badge (the profession list shows a small red x at its top-right corner while a
-- filter differs from its default; probe: auctionhouse-ui-filter-redx in ProfessionsFrame). Filters = the list
-- filters (missing recipes, look-ahead, offline members), not the options (auto-read, sync). The template's own
-- reset API (SetIsDefaultCallback / SetDefaultCallback, unverified on Forever) when it has it, else our badge.
UI.FILTER_DEFAULTS = { showUnlearned = false, lookahead = true, needsOffline = false }
function UI.FiltersAtDefault()
  local s = GCA.db and GCA.db.settings or {}
  for k, v in pairs(UI.FILTER_DEFAULTS) do
    if (s[k] and true or false) ~= v then return false end
  end
  return true
end
function UI.ResetFilters()
  local s = GCA.db and GCA.db.settings
  if not s then return end
  for k, v in pairs(UI.FILTER_DEFAULTS) do s[k] = v end
  UI:Refresh()
  UI:RefreshFilters()
end
function UI.AddFilterReset(dd)
  if dd.native and type(dd.SetIsDefaultCallback) == "function" and type(dd.SetDefaultCallback) == "function"
    and pcall(dd.SetIsDefaultCallback, dd, UI.FiltersAtDefault) and pcall(dd.SetDefaultCallback, dd, UI.ResetFilters) then
    dd.resetKind = "native"
    return
  end
  local rb = CreateFrame("Button", nil, dd)
  rb:SetSize(20, 20)
  rb:SetPoint("CENTER", dd, "TOPRIGHT", -3, -1)
  rb.icon = rb:CreateTexture(nil, "ARTWORK")
  rb.icon:SetAllPoints()
  if SetAtlasSafe(rb.icon, "auctionhouse-ui-filter-redx") then
    rb.kind = "atlas"
  else
    rb.icon:Hide()
    rb.text = rb:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    rb.text:SetPoint("CENTER")
    rb.text:SetText("x")
    rb.text:SetTextColor(1, 0.2, 0.2)
    rb.kind = "text"
  end
  rb:SetScript("OnClick", function() UI.ResetFilters() end)
  SetTip(rb, "filter reset", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.FILTER_RESET, 1, 1, 1)
    GameTooltip:Show()
  end)
  rb:SetScript("OnLeave", GameTooltip_Hide)
  rb:SetShown(not UI.FiltersAtDefault())
  dd.resetButton, dd.resetKind = rb, "own"
end
CreateFilterMenu = function(parent, window)
  local dd = NewDropdown(parent, "WowStyle1FilterDropdownTemplate", UI.FILTER_W, UI.FILTER_H)
  if dd then
    dd:SetupMenu(UI.FilterMenu)
    KeepNativeHover(dd, "filter button", FilterTip)
    UI.AddFilterReset(dd)
    return dd, nil
  end
  local btn = NewTextButton(parent, UI.FILTER_W, 22, L.FILTER_BUTTON)
  UI.AddFilterReset(btn)
  local pop = NewPopup(parent)
  pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -4)
  pop.buttons = {}
  local entries = FilterEntries()
  function pop:Fill()
    for i, def in ipairs(entries) do
      local b = self.buttons[i]
      if not b then
        b = PopupRow(self, i, OPTIONS_W - 12)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 22, 0)
        b.check = b:CreateTexture(nil, "ARTWORK")
        b.check:SetSize(16, 16)
        b.check:SetPoint("LEFT", 3, 0)
        b.check:SetTexture(UI.TEX.check)
        b:SetScript("OnClick", function(selfBtn)
          if selfBtn.def.action == "whisper" then pop:Hide() end
          EntryDo(selfBtn.def)
          if pop:IsShown() then pop:Fill() end
        end)
        SetTip(b, "options row", function(selfBtn)
          GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
          GameTooltip:SetText(EntryLabel(selfBtn.def), 1, 1, 1)
          GameTooltip:AddLine(L[selfBtn.def.tip], nil, nil, nil, true)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
      end
      b.def = def
      b.text:SetText(EntryLabel(def))
      b.check:SetShown(EntryOn(def))
      b:Show()
    end
    self:SetSize(OPTIONS_W, 12 + #entries * 18)
  end
  btn:SetScript("OnClick", function()
    if pop:IsShown() then pop:Hide() return end
    pop:Fill()
    pop:Show()
  end)
  SetTip(btn, "filter button", FilterTip)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  window:HookScript("OnHide", function() pop:Hide() end)
  return btn, pop
end

-- every Filter dropdown / popup shows the current settings again (after a toggle or a refresh)
function UI:RefreshFilters()
  local atDefault = UI.FiltersAtDefault()
  for _, f in ipairs(self.filters or {}) do
    if f.button.native then RefreshDropdown(f.button) elseif f.popup and f.popup:IsShown() then f.popup:Fill() end
    if f.button.resetButton then f.button.resetButton:SetShown(not atDefault) end
    if f.button.resetKind == "native" and f.button.ValidateResetState then pcall(f.button.ValidateResetState, f.button) end
  end
end
end

-- Whisper template editor (U2): two single-line boxes, Save / Reset to default / Close.
-- Saved in db.settings.whisperCraft / whisperEnchant; nil = the default of the client language.
local function NewEditBox(parent, width)
  local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if not (ok and eb) then
    eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    if eb.SetBackdrop then Backdrop(eb, 0.8) end
    if eb.SetFontObject and ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
  end
  eb:SetSize(width, 20)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end

-- Add / remove a frame name in UISpecialFrames (the frames ESC closes).
local function SetEscCloses(name, on)
  if type(UISpecialFrames) ~= "table" then return end
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == name then
      if on then return end
      table.remove(UISpecialFrames, i)
    end
  end
  if on then tinsert(UISpecialFrames, name) end
end
UI.SetEscCloses = SetEscCloses

-- Review L-1: ESC closes only the editor. While it is open the main window is taken out of UISpecialFrames
-- (CloseSpecialWindows hides EVERY listed frame that is shown), and put back right after the editor hides.
-- Closing without Save (ESC or Close) never drops your typing: the text stays as a draft (UI.whisperDraft),
-- the chat says so, and the next open shows the draft. Save uses it; Reset to default drops it.
local function CreateWhisperEditor()
  local dlg = CreateFrame("Frame", "GuildCraftAdvisorWhisperEditor", UIParent, "BackdropTemplate")
  dlg:SetSize(560, 190)
  dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  dlg:SetFrameStrata("DIALOG")
  dlg:EnableMouse(true)
  dlg:SetClampedToScreen(true)
  dlg.backing = dlg:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(dlg.backing, "common-dropdown-bg") then
    dlg.backing:SetPoint("TOPLEFT", -10, 3)
    dlg.backing:SetPoint("BOTTOMRIGHT", 10, -3)
    dlg.atlas = true
  else
    dlg.backing:Hide()
    if dlg.SetBackdrop then Backdrop(dlg, 0.97) end
  end
  SetEscCloses("GuildCraftAdvisorWhisperEditor", true)
  dlg:Hide()
  dlg:SetScript("OnShow", function() SetEscCloses("GuildCraftAdvisorFrame", false) end)
  dlg:SetScript("OnHide", Guard("whisper editor: hide", function(self)
    if not self.closingSaved then
      local craft, enchant = self.craft:GetText() or "", self.enchant:GetText() or ""
      if craft ~= UI.Template("craft") or enchant ~= UI.Template("enchant") then
        UI.whisperDraft = { craft = craft, enchant = enchant }
        GCA.Print(L.WHISPER_DRAFT_KEPT)
      end
    end
    self.closingSaved = nil
    -- put the main window back after this ESC press has been handled (not while CloseSpecialWindows iterates)
    C_Timer.After(0, function()
      if not self:IsShown() and UI.frame then SetEscCloses("GuildCraftAdvisorFrame", true) end
    end)
  end))
  dlg.title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dlg.title:SetPoint("TOPLEFT", 16, -14)
  dlg.title:SetText(L.WHISPER_EDIT_TITLE)
  dlg.help = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dlg.help:SetPoint("TOPLEFT", 16, -34)
  dlg.help:SetWidth(528)
  dlg.help:SetJustifyH("LEFT")
  dlg.help:SetText(L.WHISPER_EDIT_HELP)
  local function labeled(label, y)
    local fs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(label)
    local eb = NewEditBox(dlg, 528)
    eb:SetPoint("TOPLEFT", 20, y - 14)
    return eb
  end
  dlg.craft = labeled(L.WHISPER_EDIT_CRAFT, -66)
  dlg.enchant = labeled(L.WHISPER_EDIT_ENCHANT, -104)
  dlg.draftNote = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dlg.draftNote:SetPoint("BOTTOMLEFT", 152, 17)
  dlg.draftNote:SetWidth(180)
  dlg.draftNote:SetJustifyH("LEFT")
  dlg.draftNote:SetTextColor(1, 0.82, 0)
  dlg.draftNote:SetText(L.WHISPER_DRAFT_NOTE)
  function dlg:Load()
    local draft = UI.whisperDraft
    self.craft:SetText(draft and draft.craft or UI.Template("craft"))
    self.enchant:SetText(draft and draft.enchant or UI.Template("enchant"))
    self.draftNote:SetShown(draft ~= nil)
    if self.craft.SetCursorPosition then self.craft:SetCursorPosition(0) end
    if self.enchant.SetCursorPosition then self.enchant:SetCursorPosition(0) end
  end
  local function store(key, kind, text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" or text == UI.DefaultTemplate(kind) then GCA.db.settings[key] = nil else GCA.db.settings[key] = text end
  end
  function dlg:Save()
    store("whisperCraft", "craft", self.craft:GetText())
    store("whisperEnchant", "enchant", self.enchant:GetText())
    UI.whisperDraft = nil
    GCA.Print(L.WHISPER_SAVED)
    self.closingSaved = true
    self:Hide()
  end
  function dlg:Reset()
    GCA.db.settings.whisperCraft, GCA.db.settings.whisperEnchant = nil, nil
    UI.whisperDraft = nil
    self:Load()
    GCA.Print(L.WHISPER_RESET)
  end
  local function button(text, w, fn)
    local b = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
  end
  dlg.closeBtn = button(L.CLOSE, 100, function() dlg:Hide() end)
  dlg.closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  dlg.saveBtn = button(L.SAVE, 100, function() dlg:Save() end)
  dlg.saveBtn:SetPoint("RIGHT", dlg.closeBtn, "LEFT", -6, 0)
  dlg.resetBtn = button(L.RESET_DEFAULT, 130, function() dlg:Reset() end)
  dlg.resetBtn:SetPoint("BOTTOMLEFT", 14, 12)
  return dlg
end

function UI:OpenWhisperEditor()
  if not GCA.db then return end
  if not self.whisperEditor then self.whisperEditor = CreateWhisperEditor() end
  -- already open: keep what is being typed (a reload would overwrite it, review L-1)
  if self.whisperEditor:IsShown() then return self.whisperEditor end
  self.whisperEditor:Load()
  self.whisperEditor:Show()
  return self.whisperEditor
end

-- Leveling bonus slider 0-100 %, default 50 % (F8.3; renamed from "Survival" in H0/U4). One setting for everybody.
UI.SLIDER_DEBOUNCE = 0.4
local function BonusStats() return G("SPELL_STAT3_NAME"), G("SPELL_STAT5_NAME") end
-- K1: the game's MinimalSliderWithSteppersTemplate where the client has it (created inside pcall and used as
-- Spoken UI\Layout.lua:1033-1042 does on Forever: Init(value, min, max, steps, formatters) + RegisterCallback(
-- MinimalSliderWithSteppersMixin.Event.OnValueChanged, fn, owner) + SetValue); else the 0.5.0 plain slider.
-- K6: one line in the bottom bar (label, then the slider), no longer inside the custom Options popup.
UI.SLIDER_LABEL_W, UI.SLIDER_W = 250, 200
local function CreateSurvivalSlider(parent)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(UI.SLIDER_LABEL_W + 8 + UI.SLIDER_W, 22)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  holder.label:SetPoint("LEFT", 0, 0)
  holder.label:SetWidth(UI.SLIDER_LABEL_W)
  holder.label:SetJustifyH("LEFT")
  SingleLine(holder.label)
  local function label(v)
    local a, b = BonusStats()
    holder.label:SetText(string.format(L.SLIDER_LABEL, a, b, v))
  end
  local changed -- (value) from either slider kind
  local sl
  local ok, made = pcall(CreateFrame, "Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
  local mixin = MinimalSliderWithSteppersMixin
  if ok and made and made.Init and made.RegisterCallback and made.SetValue and type(mixin) == "table"
     and type(mixin.Event) == "table" and mixin.Event.OnValueChanged ~= nil then
    local inited = pcall(function()
      made:SetWidth(UI.SLIDER_W)
      made:SetPoint("LEFT", holder.label, "RIGHT", 8, 0)
      made:Init(math.floor(GCA:SurvivalShare() * 100 + 0.5), 0, 100, 20, {})
      made:RegisterCallback(mixin.Event.OnValueChanged, function(_, value) changed(value) end, made)
    end)
    if inited then sl = made; holder.templated = true end
  end
  if not sl then
    if made and made.Hide then made:Hide() end
    sl = CreateFrame("Slider", nil, holder)
    sl:SetSize(UI.SLIDER_W - 20, 16)
    sl:SetPoint("LEFT", holder.label, "RIGHT", 8, 0)
    sl:SetOrientation("HORIZONTAL")
    sl:SetMinMaxValues(0, 100)
    sl:SetValueStep(5)
    if sl.SetObeyStepOnDrag then pcall(sl.SetObeyStepOnDrag, sl, true) end
    sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    sl.bar = sl:CreateTexture(nil, "BACKGROUND")
    sl.bar:SetPoint("LEFT", 4, 0)
    sl.bar:SetPoint("RIGHT", -4, 0)
    sl.bar:SetHeight(4)
    sl.bar:SetColorTexture(0.35, 0.3, 0.2, 0.9)
    sl:EnableMouse(true)
    sl:SetScript("OnValueChanged", function(_, value) changed(value) end)
  end
  holder.slider = sl
  function holder:Sync()
    if self.pending then return end -- K0/M3: a drag is waiting to be applied; don't snap back
    local v = math.floor(GCA:SurvivalShare() * 100 + 0.5)
    self.updating = true
    pcall(sl.SetValue, sl, v)
    self.updating = false
    label(v)
  end
  -- K0/M3: the label follows at once; the value (which recomputes every member) is applied
  -- UI.SLIDER_DEBOUNCE s after the last change
  holder.gen = 0
  changed = function(value)
    if holder.updating then return end
    local v = math.floor((value or 0) / 5 + 0.5) * 5
    label(v)
    holder.gen = holder.gen + 1
    local gen = holder.gen
    holder.pending = v
    C_Timer.After(UI.SLIDER_DEBOUNCE, function()
      if holder.gen ~= gen then return end
      holder.pending = nil
      if math.abs(GCA:SurvivalShare() * 100 - v) < 0.5 then return end
      GCA.db.settings.survival = v / 100
      GCA:InvalidateScores()
    end)
  end
  local function tip(self)
    local a, b = BonusStats()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(string.format(L.SLIDER_TIP_TITLE, a, b), 1, 1, 1)
    GameTooltip:AddLine(string.format(L.SLIDER_TIP, a, b), nil, nil, nil, true)
    GameTooltip:Show()
  end
  if holder.templated then
    -- the template's own scripts stay; ours are added (its inner Slider takes the mouse)
    local inner = type(sl.Slider) == "table" and sl.Slider or sl
    if inner.HookScript then
      inner:HookScript("OnEnter", Guard("tooltip: slider", tip))
      inner:HookScript("OnLeave", GameTooltip_Hide)
    end
  else
    SetTip(sl, "slider", tip)
    sl:SetScript("OnLeave", GameTooltip_Hide)
  end
  return holder
end


---------------------------------------------------------------------------
-- Window size and position (plan J2)
---------------------------------------------------------------------------
local function Num(v)
  if type(v) ~= "number" or GCA.IsSecret(v) or v ~= v then return nil end
  return v
end

-- UIParent's size in UI units (our window is a scale-1 child of UIParent); nil when unknown
local function ScreenSize()
  local w = UIParent and UIParent.GetWidth and Num(SafeCall(UIParent.GetWidth, UIParent))
  local h = UIParent and UIParent.GetHeight and Num(SafeCall(UIParent.GetHeight, UIParent))
  return (w and w > 0) and w or nil, (h and h > 0) and h or nil
end

-- at least MIN, at most the screen (the minimum wins on a screen smaller than MIN)
function UI.ClampSize(w, h)
  local sw, sh = ScreenSize()
  w, h = Num(w) or DEFAULT_W, Num(h) or DEFAULT_H
  if sw then w = math.min(w, math.floor(sw)) end
  if sh then h = math.min(h, math.floor(sh)) end
  return math.max(MIN_W, math.floor(w + 0.5)), math.max(MIN_H, math.floor(h + 0.5))
end

-- top-left corner (UIParent BOTTOMLEFT coordinates) kept on the screen; nil when not a usable position
function UI.ClampPos(left, top, w, h)
  left, top = Num(left), Num(top)
  if not (left and top) then return nil end
  local sw, sh = ScreenSize()
  if sw then left = math.max(0, math.min(left, sw - w)) end
  if sh then top = math.min(sh, math.max(top, h)) end
  return math.floor(left + 0.5), math.floor(top + 0.5)
end

local function SavedWindow()
  local s = GCA.db and GCA.db.settings
  local win = s and s.window
  if type(win) == "table" then return win end
end

-- Size and position from db.settings.window (clamped), else the default size, centred.
function UI:RestoreGeometry()
  local f = self.frame
  local win = SavedWindow()
  local w, h = UI.ClampSize(win and win.w or DEFAULT_W, win and win.h or DEFAULT_H)
  f:SetSize(w, h)
  f:ClearAllPoints()
  local left, top
  if win then left, top = UI.ClampPos(win.left, win.top, w, h) end
  if left then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) else f:SetPoint("CENTER") end
  return w, h
end

function UI:SaveGeometry()
  local f = self.frame
  if not (f and GCA.db and GCA.db.settings) then return end
  local w, h = UI.ClampSize(f:GetWidth(), f:GetHeight())
  local win = { w = w, h = h }
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  win.left, win.top = UI.ClampPos(left, top, w, h)
  GCA.db.settings.window = win
  -- our SavedVariables hold the geometry: keep the client's layout cache (StartMoving/StartSizing mark the named
  -- frame "user placed") from restoring an older position over it
  if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
  return win
end

-- Anchor the window by its top-left corner where it is now, so sizing from the bottom-right corner keeps
-- the top-left in place (the first open is anchored at CENTER).
local function PinTopLeft(f)
  local left = f.GetLeft and Num(SafeCall(f.GetLeft, f))
  local top = f.GetTop and Num(SafeCall(f.GetTop, f))
  if not (left and top) then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Engine resize limits: SetResizeBounds on 10.0+ clients (ForeverLFG_GroupQuest QuestMatchesUI.lua:345 calls it
-- on Forever), SetMinResize/SetMaxResize on older ones; neither -> nil and StopSizing clamps afterwards.
local function SetBounds(f)
  local sw, sh = ScreenSize()
  local maxW, maxH = math.max(MIN_W, math.floor(sw or 4096)), math.max(MIN_H, math.floor(sh or 4096))
  if f.SetResizeBounds and pcall(f.SetResizeBounds, f, MIN_W, MIN_H, maxW, maxH) then return "SetResizeBounds" end
  if f.SetMinResize and pcall(f.SetMinResize, f, MIN_W, MIN_H) then
    if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
    return "SetMinResize"
  end
  return nil
end
UI.SetBounds = SetBounds

-- Ends a corner drag: the size is clamped (needed when the client has no resize bounds), laid out at once
-- and saved with the position.
function UI:StopSizing()
  local f = self.frame
  if not (f and f.isSizing) then return end
  f:StopMovingOrSizing()
  f.isSizing = false
  local w, h = f:GetWidth(), f:GetHeight()
  local cw, ch = UI.ClampSize(w, h)
  if cw ~= w or ch ~= h then f:SetSize(cw, ch) end
  self:Layout()
  self:SaveGeometry()
end

-- Right-click on the grip: back to the default size (the top-left corner stays).
function UI:ResetSize()
  local f = self.frame
  if not f then return end
  PinTopLeft(f)
  f:SetSize(UI.ClampSize(DEFAULT_W, DEFAULT_H))
  self:Layout()
  self:SaveGeometry()
end

-- Bottom-right resize grip. No installed Forever addon uses a native grip template (PanelResizeButtonTemplate
-- appears nowhere under AddOns), so it is a small button with the chat frame's size-grabber art, as
-- GearQuestForever Tracker.lua:1363-1368 / CraftersJournal UI.lua:200-204 / ForeverLFG_GroupQuest
-- QuestMatchesUI.lua:435-437 do, and StartSizing("BOTTOMRIGHT") (GearQuestForever Tracker.lua:1147).
local GRIP_ART = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local function CreateResizeGrip(f)
  if not (f.SetResizable and f.StartSizing and pcall(f.SetResizable, f, true)) then return nil end
  UI.boundsVia = SetBounds(f)
  local g = CreateFrame("Button", nil, f)
  g:SetSize(16, 16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  if g.SetNormalTexture then g:SetNormalTexture(GRIP_ART .. "Up") end
  if g.SetHighlightTexture then g:SetHighlightTexture(GRIP_ART .. "Highlight") end
  if g.SetPushedTexture then g:SetPushedTexture(GRIP_ART .. "Down") end
  g:SetScript("OnMouseDown", Guard("resize grip", function(_, button)
    if button ~= "LeftButton" or f.isSizing then return end
    if f.isMoving then f:StopMovingOrSizing(); f.isMoving = false end
    UI.boundsVia = SetBounds(f) -- the screen size may have changed (UI scale)
    PinTopLeft(f)
    f.isSizing = true
    f:StartSizing("BOTTOMRIGHT")
  end))
  g:SetScript("OnMouseUp", Guard("resize grip", function(_, button)
    if button == "RightButton" and not f.isSizing then UI:ResetSize(); return end
    UI:StopSizing()
  end))
  SetTip(g, "resize grip", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(L.RESIZE_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.RESIZE_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  g:SetScript("OnLeave", GameTooltip_Hide)
  return g
end

---------------------------------------------------------------------------
-- K1/K2 header strip and view controls
---------------------------------------------------------------------------
-- Sync status dot (K1: replaces the sync text in the header strip). Colour by GCA:SyncState() (Sync.lua); the
-- full status line is in its tooltip.
UI.SYNC_COLORS = { ok = { 0.25, 0.9, 0.25 }, idle = { 1, 0.82, 0 }, paused = { 1, 0.3, 0.3 }, off = { 0.5, 0.5, 0.5 }, noguild = { 0.5, 0.5, 0.5 } }
function UI.SyncState()
  if GCA.SyncState then return GCA:SyncState() end
  return "off"
end
function UI.SyncLine()
  if GCA.SyncStatusLine then return GCA:SyncStatusLine() or "" end
  return L.CMD_SYNC_NOT_LOADED
end
-- K5: a compact label "Guild sync · 9 recorded" (members with a gear record) with the K1 tooltip. K6: no coloured
-- dot any more: the label itself is coloured by the state (coloured text, as Blizzard colours status words).
local function CreateSyncDot(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.text:SetJustifyH("RIGHT")
  SingleLine(b.text)
  function b:Update(recorded)
    self.state = UI.SyncState()
    local c = UI.SYNC_COLORS[self.state] or UI.SYNC_COLORS.off
    self.text:SetTextColor(c[1], c[2], c[3])
    self.color = c
    if type(recorded) == "number" then self.recorded = recorded end
    self.text:SetText(string.format(L.SYNC_LABEL, self.recorded or 0))
    local tw = math.min(TextWidth(self.text), 200) -- K8: 200 (the centred rank bar ends 10 px left of it at 840)
    self.text:SetWidth(tw)
    self:SetWidth(tw)
  end
  SetTip(b, "sync status", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L.SYNC_DOT_TITLE, 1, 1, 1)
    GameTooltip:AddLine(UI.SyncLine(), 1, 1, 1, true)
    GameTooltip:AddLine(L.SYNC_DOT_TIP, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- (i) icon with the scoring source line in its tooltip (K1: replaces the source-line row). An atlas guarded by
-- GetAtlasInfo, else a file only when the client confirms it (GetFileIDFromPath), else the text "(i)".
UI.INFO_ATLAS = "glueannouncementpopup-icon-info"
UI.INFO_FILE = "Interface\\FriendsFrame\\InformationIcon"
local function CreateInfoIcon(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  if SetAtlasSafe(b.tex, UI.INFO_ATLAS) then
    b.kind = "atlas"
  elseif FileOK(UI.INFO_FILE) == true then
    b.tex:SetTexture(UI.INFO_FILE)
    b.kind = "file"
  else
    b.tex:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText("(i)")
    b.kind = "text"
  end
  SetTip(b, "source info", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.SOURCE_TIP_TITLE, 1, 1, 1)
    GameTooltip:AddLine(UI.sourceLine or "", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- Guild-needs search box: InputBoxTemplate (pcall, backdrop fallback; NewEditBox) with ForeverDungeonJournal's
-- search icon / clear button art (Journal.lua:8852-8869) and a placeholder text.
-- K5: also the member list's search (placeholder / tooltip / what to refresh are parameters)
-- K6: the client's SearchBoxTemplate first (the recipe list's own search box: common-search-border-*, magnifying
-- glass, "Search" instructions, clear button; probe; WhatsTraining Crafting\RecipeList.lua:480-484 on Forever), in
-- pcall; our text hook is added to the template's own OnTextChanged (HookScript), so its instructions / clear
-- button keep working. Fallback: the K2 box below.
local function SearchTip(placeholder, tipText)
  return function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(placeholder or L.NEEDS_SEARCH, 1, 1, 1)
    GameTooltip:AddLine(tipText or L.NEEDS_SEARCH_TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end
end
local function CreateSearchBox(parent, width, placeholder, tipText, onChange)
  local ok, sb = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
  if ok and sb and type(sb.Instructions) == "table" and sb.HookScript then
    sb:SetSize(width or 230, 20)
    sb.native = true
    sb.Instructions:SetText(placeholder or L.NEEDS_SEARCH)
    sb.placeholder = sb.Instructions
    if sb.SetAutoFocus then sb:SetAutoFocus(false) end
    if sb.SetMaxLetters then sb:SetMaxLetters(40) end
    function sb:Changed()
      if onChange then onChange(self:GetText() or "") end
    end
    sb:HookScript("OnTextChanged", Guard("search", function() sb:Changed() end))
    sb:HookScript("OnHide", function(self) if self.ClearFocus then self:ClearFocus() end end)
    sb:HookScript("OnEnter", Guard("tooltip: search", SearchTip(placeholder, tipText)))
    sb:HookScript("OnLeave", GameTooltip_Hide)
    return sb
  end
  if ok and sb and sb.Hide then sb:Hide() end
  local eb = NewEditBox(parent, width or 230)
  eb:SetMaxLetters(40)
  if eb.SetTextInsets then pcall(eb.SetTextInsets, eb, 16, 18, 0, 0) end
  if TexOK("search") then
    eb.icon = eb:CreateTexture(nil, "OVERLAY")
    eb.icon:SetTexture(UI.TEX.search)
    eb.icon:SetSize(12, 12)
    eb.icon:SetPoint("LEFT", 1, 0)
    eb.icon:SetVertexColor(0.72, 0.70, 0.66)
  end
  eb.placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  eb.placeholder:SetPoint("LEFT", 17, 0)
  eb.placeholder:SetText(placeholder or L.NEEDS_SEARCH)
  SingleLine(eb.placeholder)
  eb.clear = CreateFrame("Button", nil, eb)
  eb.clear:SetSize(14, 14)
  eb.clear:SetPoint("RIGHT", -2, 0)
  if TexOK("clear") then
    eb.clear:SetNormalTexture(UI.TEX.clear)
  else
    eb.clear.text = eb.clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eb.clear.text:SetPoint("CENTER")
    eb.clear.text:SetText("x")
  end
  eb.clear:Hide()
  function eb:Changed()
    local text = self:GetText() or ""
    self.placeholder:SetShown(text == "")
    self.clear:SetShown(text ~= "")
    if onChange then onChange(text) end
  end
  eb.clear:SetScript("OnClick", function()
    eb:SetText("")
    if eb.ClearFocus then eb:ClearFocus() end
    eb:Changed()
  end)
  eb:SetScript("OnTextChanged", Guard("search", function() eb:Changed() end))
  SetTip(eb, "search", SearchTip(placeholder, tipText))
  eb:SetScript("OnLeave", GameTooltip_Hide)
  return eb
end

-- K2: the two views. Tabs under the window (PanelTabButtonTemplate, in pcall, as BugSack sack.lua:518-545 and
-- Spoken UI\Compendium.lua:616-634 make them on Forever); where the template is missing, two plain buttons in
-- the header strip right of the profession selector. The view is never saved: every open starts on guild needs.
UI.VIEWS = { { "needs", "VIEW_NEEDS" }, { "member", "VIEW_MEMBER" } }
local function CreateViewTabs(f, c)
  local tabs, templated = {}, true
  for i in ipairs(UI.VIEWS) do
    local ok, tab = pcall(CreateFrame, "Button", "GuildCraftAdvisorFrameTab" .. i, f, "PanelTabButtonTemplate")
    if not (ok and tab) then templated = false; break end
    tabs[i] = tab
  end
  if templated then
    for i, tab in ipairs(tabs) do
      if tab.SetID then tab:SetID(i) end
      tab:SetText(L[UI.VIEWS[i][2]])
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
      if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 3, 0) end
    end
  else
    for _, tab in ipairs(tabs) do tab:Hide() end -- a half-made set
    tabs = {}
    for i, def in ipairs(UI.VIEWS) do
      local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
      b:SetSize(92, 22) -- K8: left of the centred rank bar (60..248 at 840)
      b:SetText(L[def[2]])
      b:SetPoint("TOPLEFT", c, "TOPLEFT", 60 + (i - 1) * 96, -32)
      tabs[i] = b
    end
  end
  for i, tab in ipairs(tabs) do
    tab.view = UI.VIEWS[i][1]
    tab:SetScript("OnClick", function(self) UI:SetView(self.view) end)
  end
  return tabs, templated
end

function UI:PaintTabs()
  for _, tab in ipairs(self.tabs or {}) do
    local on = tab.view == self.view
    tab.selected = on
    if self.tabsTemplated then
      local fn = on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab
      if type(fn) == "function" then pcall(fn, tab) end
    elseif tab.LockHighlight and tab.UnlockHighlight then
      if on then tab:LockHighlight() else tab:UnlockHighlight() end
    end
  end
end

function UI:ApplyView()
  local needs = self.view ~= "member"
  self.needsView:SetShown(needs)
  self.memberView:SetShown(not needs)
  self:PaintTabs()
end

function UI:SetView(view)
  self.view = view == "member" and "member" or "needs"
  if self.frame then
    self:ApplyView()
    self:Refresh()
  end
end

-- K2: a guild-needs row was clicked: that member in the member view, scrolled to the row's slot section. A member
-- in a collapsed group gets the group opened so the selection is visible.
-- K4: in the character sheet the row's slot is selected and the row's craft shown in the cards (sug).
function UI:OpenMember(key, slot, sug)
  self.selected, self.autoKey = key, nil
  for _, e in ipairs(self.lastMembers or {}) do
    if e.key == key and not e.isSelf then
      if e.online then self.collapsed.online = false else self.collapsed.offline = false end
    end
  end
  -- K5: a member search that hides them is cleared
  local ms = self.memberSearch
  local q = ms and tostring(ms:GetText() or ""):lower():match("^%s*(.-)%s*$") or ""
  if q ~= "" and not tostring(key):lower():find(q, 1, true) then ms:SetText(""); ms:Changed() end
  if slot then
    self.sheetFor = tostring(key) .. "|" .. tostring(GCA:SelectedProfession())
    self.sheetSlot, self.sheetAuto, self.sheetPickSug = slot, false, sug
  end
  self:SetView("member")
  local y = self.memberList:FindY(function(d) return d.key == key and d.rowKind == nil end)
  if y then
    local top = self.memberList:Offset()
    if y < top or y + MEMBER_ROW_H > top + (self.memberList.viewH or 0) then self.memberList:ScrollTo(y - MEMBER_ROW_H) end
  end
  if slot and UI.MemberMode() == "list" then
    local secKey = GCA.SECTION_OF[slot] or slot
    local sy = self.sugList:FindY(function(d) return d.rowKind == "section" and d.sec.key == secKey end)
    if sy then self.sugList:ScrollTo(sy) end
  end
end

-- the member list from the last member data (a group header click / the search: no recompute)
function UI:RefreshMemberList()
  local q = self.memberSearch and self.memberSearch:GetText() or ""
  self.memberList:SetData(UI.MemberRows(self.lastMembers or {}, q))
end

-- (K2 name kept) the guild-needs search changed
function UI:SearchChanged()
  if self.searchBox then self.searchBox:Changed() end
end

-- K8: the guild-needs count sits at the bottom of the left list panel (one line, as wide as the panel)
UI.SEARCH_W = LEFT_W - 21 - 90 - 12
function UI:LayoutFilterBar()
  if not (self.needsCount and self.frame) then return end
  self.needsCount:SetWidth(LEFT_W - 20)
end

-- K2/K5: the guild-needs view from the last member data (Core caches the groups; search and the offline toggle
-- only pick from them)
function UI:RefreshNeeds()
  if not (self.needsList and self.frame) then return end
  local prof = GCA:SelectedProfession()
  local s = GCA.db and GCA.db.settings or {}
  local needs = GCA:GuildNeeds(self.lastMembers or {})
  local query = self.searchBox and self.searchBox:GetText() or ""
  local data, crafts, members, offN, all = UI.NeedsRows(needs, query, s.needsOffline)
  -- K8: the selected craft (detail panel): kept while it is listed, else the first (= best) craft
  local sel
  for _, e in ipairs(all) do if e.group.key == UI.needSel then sel = e end end
  sel = sel or all[1]
  UI.needSel = sel and sel.group.key or nil
  self.needsData = data
  self.needsList:SetData(data)
  local who = members == 1 and L.NEEDS_MEMBERS_1 or string.format(L.NEEDS_MEMBERS, members)
  local count
  if prof == "Enchanting" then
    count = crafts == 1 and string.format(L.NEEDS_COUNT_ENCH_1, who) or string.format(L.NEEDS_COUNT_ENCH, crafts, who)
  else
    count = crafts == 1 and string.format(L.NEEDS_COUNT_1, who) or string.format(L.NEEDS_COUNT, crafts, who)
  end
  self.needsMissing = 0
  if GCA:IsBrowse(prof) then
    count = count .. "  " .. C.browse .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r"
  elseif s.showUnlearned then
    -- K7: how many of the listed crafts are recipes you don't know yet (only computed with "Show missing recipes")
    local missing = 0
    for _, e in ipairs(all) do if not e.group.sug.known then missing = missing + 1 end end
    self.needsMissing = missing
    if missing > 0 then
      count = count .. "  ·  " .. C.notLearned .. (missing == 1 and L.NEEDS_MISSING_1 or string.format(L.NEEDS_MISSING, missing)) .. "|r"
    end
  end
  self.needsCount:SetText(count)
  -- the Filter menu's "Include offline members (n)" entry shows this count
  if UI.offlineN ~= offN then
    UI.offlineN = offN
    self:RefreshFilters()
  end
  self:LayoutFilterBar()
  local q = query:match("^%s*(.-)%s*$") or ""
  local empty = ""
  if crafts > 0 then
    empty = ""
  elseif q ~= "" then
    empty = string.format(L.NEEDS_NO_MATCH, q)
  elseif (GCA.knownCount or 0) == 0 and not GCA:IsBrowse(prof) then
    empty = string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof))
  elseif offN > 0 and not s.needsOffline then
    empty = string.format(L.NEEDS_EMPTY_OFFLINE, offN)
  else
    empty = L.NEEDS_EMPTY
  end
  -- K8: the empty text sits in the detail panel (where the craft would be shown)
  self:UpdateCraftDetail(sel, empty)
  local key = tostring(prof)
  if self.needsKey ~= key then
    self.needsKey = key
    self.needsList:ScrollTo(0)
  end
end

-- K5: "Include offline members (n)" (saved in db.settings.needsOffline); K6: a Filter menu entry
function UI:SetNeedsOffline(on)
  if not (GCA.db and GCA.db.settings) then return end
  GCA.db.settings.needsOffline = on and true or false
  self:RefreshNeeds()
  self:RefreshFilters()
end

-- Lays out everything that depends on the window size (J2). K8: both views = the left list panel (fixed width,
-- follows the height) and the detail panel right of it (fills the rest); positions are anchored, only sizes change.
function UI:Layout()
  local f = self.frame
  if not (f and self.sugList) then return end
  local w = math.max(MIN_W, Num(f:GetWidth()) or MIN_W)
  local h = math.max(MIN_H, Num(f:GetHeight()) or MIN_H)
  self.layoutCount = (self.layoutCount or 0) + 1
  self.layoutW, self.layoutH = w, h
  local rw = RightW(w)
  local listH = h + PANEL_TOP - PANEL_BOTTOM
  local dw = rw + 4               -- detail panel width (both views)
  local iw, ih = dw - 12, listH - DETAIL_HEAD - 6 -- the member detail's list / sheet area
  self.memberInset:SetSize(LEFT_W, listH)
  UI.memberListW = LEFT_W - 30
  self.memberList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, true) -- K5: below the member search
  self.memberDetail:SetSize(dw, listH)
  self.nameText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)  -- room for the spec button on its right
  self.subText:SetWidth(dw - 28 - UI.SPEC_BTN_W - 10)
  self.sugHeader:SetWidth(dw - 34 - UI.TOGGLE_W - 22) -- right of the (i) icon, left of the K4 view switch
  self.sugInset:SetSize(iw, ih)
  UI.listW = iw - 34
  self.sugList:Resize(iw - 34, ih - 10, true)
  self.emptyText:SetWidth(iw - 60)
  -- K4: the character sheet fills the same area (4 px inside its edges)
  self.sheet:SetSize(iw, ih)
  self:LayoutSheet(iw, ih)
  -- K8: guild needs = the list panel (left) + the craft detail panel (right)
  self.needsInset:SetSize(LEFT_W, listH)
  UI.needsW = LEFT_W - 30
  self.needsList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, true)
  local nd = self.needDetail
  nd:SetSize(dw, listH)
  nd.w, nd.h = dw, listH
  self:UpdateCraftDetail(nd.entry, nd.empty:GetText())
  self:LayoutFilterBar()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function UI:Create()
  local f = NewWindow("GuildCraftAdvisorFrame", "Guild Craft Advisor")
  self.frame = f
  self:RestoreGeometry() -- J2: saved size/position (clamped), else 980x640 centred
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  -- ESC closes the window, except while the whisper editor is open (review L-1; it puts the window back)
  SetEscCloses("GuildCraftAdvisorFrame", not (self.whisperEditor and self.whisperEditor:IsShown()))
  f:Hide()

  -- everything we draw lives on one content frame above the art (H1 frame levels)
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  f.content = c
  ApplyLevels(f)
  self.view = "needs"

  f:SetScript("OnShow", function()
    -- U1: each open starts on the best guildie again, unless you picked someone yourself
    if UI.selected ~= nil and UI.selected == UI.autoKey then UI.selected = nil end
    -- K2: every open starts on guild needs with the groups collapsed (nothing of this is remembered);
    -- K5: the online group open, the crafts collapsed
    UI.view = "needs"
    UI.collapsed.online, UI.collapsed.offline = false, true
    UI.needsCollapsed, UI.needSel = {}, nil -- K8: every slot category open, the best craft selected
    UI:ApplyView()
    GCA:RequestRoster()
    GCA:RefreshKnown()
    UI:Refresh()
  end)

  -- Close with a plain Hide() so it works in combat (ForeverDungeonJournal Favourites.lua:553-560).
  if type(f.CloseButton) == "table" and f.CloseButton.SetScript then
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
  end

  -- Drag bar between the portrait and the close button (QuestieOptionsWindow.lua:38-61); J2: position saved.
  local dragBar = CreateFrame("Frame", nil, c)
  dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", f.templated and 55 or 0, 0)
  -- fallback close button sits at -10 and is 32 wide: keep the bar off it
  dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", f.templated and -30 or -44, 0)
  dragBar:SetHeight(24)
  dragBar:EnableMouse(true)
  dragBar:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and not f.isMoving and not f.isSizing then f:StartMoving(); f.isMoving = true end
  end)
  dragBar:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and f.isMoving then f:StopMovingOrSizing(); f.isMoving = false; UI:SaveGeometry() end
  end)
  self.dragBar = dragBar
  f:HookScript("OnHide", function()
    if f.isMoving then f:StopMovingOrSizing(); f.isMoving = false; UI:SaveGeometry() end
    UI:StopSizing()
  end)
  -- K17: the U6 Shift re-render of our suggestion tooltip is gone (item tooltips are plain Blizzard ones now)

  -- K8: the rank bar centred right under the title (the profession window's RankBar, with its dropdown arrow); the
  -- sync status ("Guild sync · n recorded", coloured by state) on the right of the same line.
  self.profButton, self.profPopup = CreateProfessionPicker(c, f)
  self.profButton:SetPoint("TOP", f, "TOP", 0, -27)
  self.syncDot = CreateSyncDot(c)
  self.syncDot:SetPoint("TOPRIGHT", -20, -36)

  -- Sizes below are placeholders for the minimum size; UI:Layout() sets the real ones (end of Create, J2).
  local listH = MIN_H + PANEL_TOP - PANEL_BOTTOM
  local painted = f.gcaArt and f.gcaArt.painted or false
  local rw = RightW(MIN_W)

  -- K8: guild-needs view (the default) = the recipe list (search | Filter on top, slot categories + craft rows, the
  -- count at the bottom) and the craft's detail panel on the right
  local nv = CreateFrame("Frame", nil, c)
  nv:SetAllPoints(c)
  self.needsView = nv
  local ni = NewInset(nv, painted)
  ni:SetPoint("TOPLEFT", 10, PANEL_TOP)
  ni:SetSize(LEFT_W, listH)
  self.needsInset = ni
  self.searchBox = CreateSearchBox(ni, UI.SEARCH_W, L.NEEDS_SEARCH, L.NEEDS_SEARCH_TIP, function() UI:RefreshNeeds() end)
  self.searchBox:SetPoint("TOPLEFT", ni, "TOPLEFT", 13, -8)
  self.filterButton, self.filterPopup = CreateFilterMenu(ni, f)
  self.filterButton:SetPoint("TOPRIGHT", ni, "TOPRIGHT", -8, -9)
  UI.needsW = LEFT_W - 30
  self.needsList = CreateScrollList(ni, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5 - COUNT_H, NEED_ROW_H, CreateCraftGroupRow, UpdateCraftGroupRow,
    UI.NEEDS_KINDS)
  self.needsList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(ni, self.needsList)
  self.needsCount = ni:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.needsCount:SetPoint("BOTTOMLEFT", ni, "BOTTOMLEFT", 10, 6)
  self.needsCount:SetWidth(LEFT_W - 20)
  self.needsCount:SetJustifyH("LEFT")
  self.needsCount:SetTextColor(SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  SingleLine(self.needsCount)
  local nd = UI.CreateCraftDetail(nv)
  nd:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  nd:SetSize(rw + 4, listH)
  nd.w, nd.h = rw + 4, listH
  self.needDetail = nd
  self.needsEmpty = nd.empty

  -- K2: member view: the member list (left) and the selected member in the detail panel (right)
  local mv = CreateFrame("Frame", nil, c)
  mv:SetAllPoints(c)
  self.memberView = mv
  local left = NewInset(mv, painted)
  left:SetPoint("TOPLEFT", 10, PANEL_TOP)
  left:SetSize(LEFT_W, listH)
  self.memberInset = left
  -- K5: a member search on top of the list; K6: and the Filter dropdown at its right, as the recipe list has them
  -- (SearchBox TOPLEFT 13,-8; FilterDropdown TOPRIGHT -8,-9, probe)
  self.memberSearch = CreateSearchBox(left, UI.SEARCH_W, L.MEMBER_SEARCH, L.MEMBER_SEARCH_TIP, function() UI:RefreshMemberList() end)
  self.memberSearch:SetPoint("TOPLEFT", left, "TOPLEFT", 13, -8)
  self.memberFilter, self.memberFilterPopup = CreateFilterMenu(left, f)
  self.memberFilter:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -9)
  UI.memberListW = LEFT_W - 30
  self.memberList = CreateScrollList(left, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, MEMBER_ROW_H, CreateMemberRow, UpdateMemberRow,
    { group = { create = CreateGroupRow, update = UpdateGroupRow, height = GROUP_ROW_H } })
  self.memberList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  RaiseInsetBorder(left, self.memberList)

  -- K8: the member's detail panel (detailBorder frame, the page art behind): name, sub-line, spec dropdown, (i) +
  -- list header + view dropdown, then the character sheet or the list
  local md = CreateFrame("Frame", nil, mv)
  md:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  md:SetSize(rw + 4, listH)
  UI.AddDetailBorder(md)
  self.memberDetail = md
  self.nameText = md:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  self.nameText:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -10)
  self.nameText:SetJustifyH("LEFT")
  SingleLine(self.nameText)
  self.subText = md:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.subText:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -32)
  self.subText:SetJustifyH("LEFT")
  SingleLine(self.subText) -- L2
  self.specButton, self.specPopup = CreateSpecPicker(md, f)
  self.specButton:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -8)

  -- suggestions: (i) icon with the scoring source (K1), the list header, then the list
  self.infoIcon = CreateInfoIcon(md)
  self.infoIcon:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -52)
  self.sugHeader = md:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.sugHeader:SetPoint("TOPLEFT", md, "TOPLEFT", 34, -54)
  self.sugHeader:SetJustifyH("LEFT")
  SingleLine(self.sugHeader)
  -- K4: the variant switch at the top right of the member panel, on the list header's line (K6: a dropdown)
  self.modeToggle = CreateModeSwitch(md)
  self.modeToggle:SetPoint("TOPRIGHT", md, "TOPRIGHT", -12, -50)
  local right = CreateFrame("Frame", nil, md) -- K8: no own background / border: the detail panel frames it
  right:SetPoint("TOPLEFT", md, "TOPLEFT", 6, -DETAIL_HEAD)
  right:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sugInset = right
  self.sugList = CreateScrollList(right, rw - 42, listH - DETAIL_HEAD - 16, UI.CardHeight, CreateCardRow, UpdateCardRow,
    { section = { create = CreateSectionRow, update = UpdateSectionRow, height = SECTION_H },
      fold = { create = CreateFoldRow, update = UpdateFoldRow, height = FoldHeight } })
  self.sugList:SetPoint("TOPLEFT", 5, -5)
  self.emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.emptyText:SetPoint("CENTER")
  self.emptyText:SetWidth(rw - 68)
  -- K4: the character sheet, in the same area as the list (one of the two is shown)
  self.sheet = CreateSheet(right)
  self.sheet:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0) -- K8: the detail panel's padding replaces the 4 px inset
  self.sheet:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.sheet:Hide()
  RaiseInsetBorder(md, self.sugList)

  -- bottom bar. K5: the "Inspect target" / "Scan group" buttons are gone (gear is read automatically; the
  -- /gca inspect and /gca scan commands stay). K6: the K1 "Options" button + popup are gone: the toggles are in
  -- the Filter dropdowns, the leveling-bonus slider is here.
  self.filters = { { button = self.filterButton, popup = self.filterPopup }, { button = self.memberFilter, popup = self.memberFilterPopup } }
  self.survival = CreateSurvivalSlider(c)
  self.survival:SetPoint("BOTTOMLEFT", 18, 13)
  -- K11 (user): with the native Filter menu the bonus is set there (submenu); the bottom slider stays only as the
  -- fallback for the non-native popup. The "?" help button is gone (/gca help lists the commands).
  if self.filterButton and self.filterButton.native then self.survival:Hide() end

  -- K2: view tabs (under the window; fallback: buttons in the header strip)
  self.tabs, self.tabsTemplated = CreateViewTabs(f, c)

  -- J2: resize grip in the bottom-right corner, above our content; relayout throttled while dragging
  self.resizeGrip = CreateResizeGrip(f)
  f.resizeGrip = self.resizeGrip
  if self.resizeGrip and self.resizeGrip.SetFrameLevel then
    self.resizeGrip:SetFrameLevel((c:GetFrameLevel() or 0) + 10)
  end
  self:ApplyView()
  self:ApplyMemberMode()
  self:Layout()
  f:HookScript("OnSizeChanged", function()
    if UI.layoutPending then return end
    UI.layoutPending = true
    C_Timer.After(UI.RESIZE_THROTTLE, function()
      UI.layoutPending = false
      UI:Layout()
    end)
  end)
end

function UI:Toggle()
  if not self.frame then self:Create() end
  self.frame:SetShown(not self.frame:IsShown())
end

-- U1: the best guildie (not you) with an upgrade you can craft; the list is already sorted that way.
function UI.PickDefault(members)
  for _, e in ipairs(members) do
    if not e.isSelf and e.best then return e end
  end
end

function UI:Refresh()
  pcall(UI.UpdateDetailCards)
  local f = self.frame
  if not (f and f:IsShown() and GCA.db) then return end

  if self.survival then self.survival:Sync() end
  self:RefreshFilters()

  local prof = GCA:SelectedProfession()
  local browse = GCA:IsBrowse(prof)
  -- K5: skill bar "Leatherworking 150 / 225" (browse: the name + "(browse)", empty bar)
  local rank, maxRank = GCA:GetSkill(prof)
  if browse then
    self.profButton:SetSkill(ProfName(prof) .. " " .. C.browse .. L.PROF_BROWSE_TAG .. "|r")
  elseif rank then
    self.profButton:SetSkill(string.format(L.PROF_SKILL_BAR, ProfName(prof), rank, maxRank or 300), rank, maxRank or 300, prof)
  else
    self.profButton:SetSkill(ProfName(prof))
  end
  if self.profPopup and self.profPopup:IsShown() then self.profPopup:Fill() end
  local pinfo = GCA.PROF_BY_KEY[prof]
  if f.templated and f.SetPortraitToAsset and pinfo and self.portraitFor ~= prof then
    SafeCall(f.SetPortraitToAsset, f, pinfo.icon)
    self.portraitFor = prof
  end

  local members = GCA:GetMemberList()
  local current
  for _, e in ipairs(members) do if e.key == self.selected then current = e end end
  -- U1: nothing picked yet (or the automatic pick has no upgrade): open on the best guildie, you stay listed
  local auto = current == nil or self.selected == self.autoKey
  if auto and not (current and current.best and not current.isSelf) then
    current = UI.PickDefault(members) or current or members[1]
    self.selected = current and current.key
    self.autoKey = self.selected
  end
  self.current = current
  self.lastMembers = members
  self.memberList:SetData(UI.MemberRows(members, self.memberSearch and self.memberSearch:GetText() or ""))
  local recorded = 0
  for _, e in ipairs(members) do if e.member and not e.isSelf then recorded = recorded + 1 end end
  self.syncDot:Update(recorded)
  -- K2: the guild-needs list only while it is shown (switching to it refreshes)
  if self.view ~= "member" then self:RefreshNeeds() end

  if not current then
    -- review L-4: nothing of the previously shown member may stay on screen
    self.nameText:SetText(L.NO_MEMBERS)
    self.subText:SetText("")
    self.sugHeader:SetText("")
    self.emptyText:SetText("")
    self.sugList:SetData({})
    self.sheet:Hide()
    self.specButton:Hide()
    if self.specPopup then self.specPopup:Hide() end
    UI.sourceLine = ""
    self.infoIcon:Hide()
    return
  end
  self.specButton:SetShown(current.class ~= nil)
  self.specButton:SetClass(current.class)
  if current.spec then
    self.specButton:SetText(GCA:SpecName(current.class, current.spec) .. (current.specAssumed and " *" or ""))
  else
    self.specButton:SetText(C.warn .. L.SPEC_PICK .. "|r")
  end
  if self.specPopup then
    if self.specPopup:IsShown() and self.specPopup.forKey ~= current.key then self.specPopup:Hide() end
    self.specPopup.forKey = current.key
  end

  self.nameText:SetText(Hex(ClassColor(current.class)) .. current.key .. "|r")
  local m = current.member
  local status = current.isSelf and L.STATUS_YOU
    or (current.online and (C.upgrade .. G("FRIENDS_LIST_ONLINE") .. "|r") or (C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"))
  if m then
    self.subText:SetText(string.format(L.SUB_LINE, G("LEVEL"), tostring(current.level or "?"), ClassName(current.class), status,
      SourceText(m), Ago(m.time)))
  else
    -- L2: the "not inspected" hint lives in the empty state below
    self.subText:SetText(string.format(L.SUB_LINE_NOGEAR, G("LEVEL"), tostring(current.level or "?"), ClassName(current.class), status))
  end

  local list = current.suggestions or {}
  local what = prof == "Enchanting" and L.HEAD_ENCHANTS or L.HEAD_CRAFTS
  if browse then
    self.sugHeader:SetText(string.format(what, #list) .. " " .. C.browse .. "– " .. string.format(L.HEAD_BROWSE, ProfName(prof)) .. "|r")
  else
    self.sugHeader:SetText(string.format(what, #list))
  end
  -- K1: the scoring source is the (i) icon's tooltip
  UI.sourceLine = current.weights and GCA:SourceLine(current.weights) or ""
  self.infoIcon:SetShown(UI.sourceLine ~= "")
  -- why the list is empty (empty-state text; K4: in the character sheet it goes into the middle panel)
  local why = ""
  if not m then
    why = L.EMPTY_NOGEAR
  elseif current.state == "no-spec" then
    why = L.EMPTY_NOSPEC
  elseif current.state == "no-level" then
    why = L.EMPTY_NOLEVEL
  elseif current.state == "no-weights" or current.state == "no-class" then
    why = L.EMPTY_NOWEIGHTS
  elseif #list == 0 and (current.pending or 0) > 0 then
    why = L.EMPTY_LOADING
  elseif #list == 0 and browse then
    why = string.format(L.EMPTY_BROWSE, ProfName(prof))
  elseif #list == 0 and (GCA.knownCount or 0) == 0 then
    why = string.format(L.EMPTY_NOKNOWN, ProfName(prof), ProfName(prof))
  elseif #list == 0 then
    why = prof == "Enchanting" and L.EMPTY_ENCHANT or L.EMPTY_NONE
  end
  -- K4: only the shown variant is filled. The sheet needs the slot sections (gear compared); without them
  -- (no gear, no spec, loading, ...) the empty-state text explains why, as in the list.
  if UI.MemberMode() == "sheet" then
    self.sugList:Hide()
    if list.sections then
      self.sheet:Show()
      self:UpdateSheet(current, list, prof, why)
      self.emptyText:SetText("")
    else
      self.sheet:Hide()
      self.emptyText:SetText(why)
    end
    return
  end
  self.sheet:Hide()
  self.sugList:Show()
  self.sugList:SetData(UI.SectionRows(list)) -- plan I: grouped per slot
  -- plan I: the list is now always longer than the view; another member or profession starts at the top
  local listKey = tostring(current.key) .. "|" .. tostring(prof)
  if self.listKey ~= listKey then
    self.listKey = listKey
    self.sugList:ScrollTo(0)
  end
  self.emptyText:SetText(#list == 0 and why or "")
end

-- Error reporter: Guard is defined at the top of this file.
UI.Refresh = Guard("UI:Refresh", UI.Refresh)
UI.Toggle = Guard("UI:Toggle", UI.Toggle)
UI.Layout = Guard("UI:Layout", UI.Layout)
UI.StopSizing = Guard("UI:StopSizing", UI.StopSizing)
UI.OpenWhisperEditor = Guard("UI:OpenWhisperEditor", UI.OpenWhisperEditor)
UI.RefreshNeeds = Guard("UI:RefreshNeeds", UI.RefreshNeeds)
UI.RefreshMemberList = Guard("UI:RefreshMemberList", UI.RefreshMemberList)
UI.OpenMember = Guard("UI:OpenMember", UI.OpenMember)
UI.SetView = Guard("UI:SetView", UI.SetView)
UI.SetMemberMode = Guard("UI:SetMemberMode", UI.SetMemberMode)
UI.SelectSheetSlot = Guard("UI:SelectSheetSlot", UI.SelectSheetSlot)
UI.PickSheetRow = Guard("UI:PickSheetRow", UI.PickSheetRow)
UI.UpdateSheet = Guard("UI:UpdateSheet", UI.UpdateSheet)
UI.LayoutSheet = Guard("UI:LayoutSheet", UI.LayoutSheet)
UI.SetNeedsOffline = Guard("UI:SetNeedsOffline", UI.SetNeedsOffline)
