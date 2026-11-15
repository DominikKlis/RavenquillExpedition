local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall = GCA.SafeCall
-- ns.L from Locales\*.lua; GCA.L is the same table (harnesses load the UI files with a bare ns)
local L = ns.L or GCA.L
local G = ns.G or GCA.G
local LGet = ns.LGet or GCA.LGet

local UI = {}
GCA.UI = UI
UI.P = {} -- locals the UI files share (UI/*.lua, in .toc order)
local P = UI.P

-- Window size: resizable from MIN (the 0.5.0 size; nothing may overlap there) up to the screen;
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
-- Colour palette: one meaning per colour
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

-- One line, no wrapping: a long text is cut with "..." instead of growing into the next row.
local function SingleLine(fs)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end

---------------------------------------------------------------------------
-- Error reporter (diagnostics, 2026-11-13): WoW hides Lua errors by default, so a failing
-- Create/Refresh left an empty window with no message. Runs under RQ:Call (BugSack); the first error per text is
-- also reported in chat and the last one kept in our SavedVariables (db.diag.lastError) to read after /reload.
-- Also wraps every tooltip (OnEnter) handler (review H-1), so a broken text is reported, not silent.
---------------------------------------------------------------------------
UI.reported = {}
UI.errorCount = 0
local function Guard(name, fn)
  return function(...)
    local done = false
    RavenquillExpedition:Call(function(...) fn(...); done = true end, ...)
    if done then return end
    UI.errorCount = UI.errorCount + 1
    local core = RavenquillExpeditionDB and RavenquillExpeditionDB.lastError
    local err = type(core) == "table" and tostring(core.msg) or "?"
    local first = err:match("^[^\n]*") or err
    if GCA.db then
      GCA:Diag().lastError = { where = name, msg = err .. "\n" .. tostring(type(core) == "table" and core.trace or ""),
        at = date and date("%Y-%m-%d %H:%M:%S") or "?" }
    end
    if not UI.reported[first] then
      UI.reported[first] = true
      GCA:Print("|cffff5555" .. string.format(L.ERROR_IN, name) .. "|r " .. first .. "  " .. L.ERROR_SAVED)
    end
  end
end
UI.Guard = Guard
-- frame:SetScript("OnEnter", ...) through the reporter
local function SetTip(frame, name, fn)
  frame:SetScript("OnEnter", Guard("tooltip: " .. name, fn))
end

-- shared with the files loaded after this one (P)
P.SafeCall = SafeCall
P.G = G
P.MIN_W = MIN_W
P.MIN_H = MIN_H
P.DEFAULT_W = DEFAULT_W
P.DEFAULT_H = DEFAULT_H
P.LEFT_W = LEFT_W
P.RIGHT_X = RIGHT_X
P.RightW = RightW
P.PANEL_TOP = PANEL_TOP
P.PANEL_BOTTOM = PANEL_BOTTOM
P.DETAIL_HEAD = DETAIL_HEAD
P.MEMBER_ROW_H = MEMBER_ROW_H
P.GROUP_ROW_H = GROUP_ROW_H
P.NEED_ROW_H = NEED_ROW_H
P.MEMBER_LIST_TOP = MEMBER_LIST_TOP
P.COUNT_H = COUNT_H
P.C = C
P.SUB_TINT = SUB_TINT
P.SetAtlasSafe = SetAtlasSafe
P.FileOK = FileOK
P.TexOK = TexOK
P.SingleLine = SingleLine
P.Guard = Guard
P.SetTip = SetTip
P.HasAtlas = HasAtlas
P.NEED_SUB_H = NEED_SUB_H
P.SUG_ROW_H = SUG_ROW_H
P.LGet = LGet
