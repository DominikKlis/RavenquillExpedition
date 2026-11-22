local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall = GCA.SafeCall
local L = ns.L or GCA.L
local G = ns.G or GCA.G
local LGet = ns.LGet or GCA.LGet

local UI = {}
GCA.UI = UI
UI.P = {}
local P = UI.P

local MIN_W, MIN_H = 840, 560
local DEFAULT_W, DEFAULT_H = 980, 640
UI.MIN_W, UI.MIN_H, UI.DEFAULT_W, UI.DEFAULT_H = MIN_W, MIN_H, DEFAULT_W, DEFAULT_H
UI.RESIZE_THROTTLE = 0.05
local LEFT_W = 260
local RIGHT_X = LEFT_W + 22
local function RightW(w) return w - RIGHT_X - 12 end
local PANEL_TOP = -62
local PANEL_BOTTOM = 40
local DETAIL_HEAD = 76
local SUG_ROW_H = 52
local MEMBER_ROW_H = 25
local GROUP_ROW_H = 27
local NEED_ROW_H = 25
local NEED_SUB_H = 42
local MEMBER_LIST_TOP = 34
local COUNT_H = 18
UI.MEMBER_ROW_H, UI.GROUP_ROW_H, UI.NEED_ROW_H, UI.NEED_SUB_H = MEMBER_ROW_H, GROUP_ROW_H, NEED_ROW_H, NEED_SUB_H
UI.LEFT_W, UI.PANEL_TOP = LEFT_W, PANEL_TOP

local C = {
  upgrade = "|cff33ff33",
  known = "|cff8cb4ff",
  set = "|cffd28cff",
  setLoss = "|cffff6644",
  unlearned = "|cffff8833",
  browse = "|cff4fd2c8",
  future = "|cffffd100",
  offline = "|cff8a8a8a",
  muted = "|cffaaaaaa",
  dim = "|cff888888",
  warn = "|cffff8800",
  bad = "|cffff5555",
  levelTag = "|cfff0b44c",
  link = "|cffffd100",
}
local SUB_TINT = { 0.75, 0.72, 0.65 }
UI.SUB_TINT = SUB_TINT
UI.COLORS = C

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

local function FileOK(path)
  if type(GetFileIDFromPath) ~= "function" then return nil end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and id ~= nil and not GCA.IsSecret(id)
end
UI.FileOK = FileOK
UI.TEX = {
  offer = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up",
  caretDown = "Interface\\Buttons\\Arrow-Down-Up",
  caretUp = "Interface\\BUTTONS\\Arrow-Up-Up",
  plus = "Interface\\Buttons\\UI-PlusButton-Up",
  minus = "Interface\\Buttons\\UI-MinusButton-Up",
  check = "Interface\\Buttons\\UI-CheckBox-Check",
  iconHL = "Interface\\Buttons\\ButtonHilight-Square",
  rowHL = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  search = "Interface\\Common\\UI-Searchbox-Icon",
  clear = "Interface\\Buttons\\UI-StopButton",
  iconFrame = "Interface\\Common\\WhiteIconFrame",
  skillBar = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
  classIcons = "Interface\\TargetingFrame\\UI-Classes-Circles",
}
local function TexOK(key) return FileOK(UI.TEX[key]) ~= false end
UI.TexOK = TexOK

UI.SKIN = {
  rowHover = { atlas = "Professions_Recipe_Hover", alpha = 0.5, size = { 309, 21 }, file = "rowHL", blend = "ADD", color = { 1, 1, 1, 0.07 } },
  rowSelected = { atlas = "Professions_Recipe_Active", size = { 267, 19 }, file = "rowHL", blend = "ADD", color = { 1, 0.82, 0, 0.14 } },
  slotHover = { file = "iconHL", blend = "ADD", color = { 1, 1, 1, 0.15 } },
  listBg = { atlas = "Professions-background-summarylist", color = { 0, 0, 0, 0.45 } },
  separator = { color = { 1, 1, 1, 0.08 } },
  skillBar = { file = "skillBar", tint = { 0.2, 0.32, 0.9, 1 }, color = { 0.2, 0.32, 0.9, 1 } },
  category = { atlas = "common-button-list-collapseExpand", color = { 0.20, 0.13, 0.07, 0.95 } },
  categoryHover = { atlas = "common-button-list-collapseExpand", atlasBlend = "ADD", alpha = 0.4, color = { 1, 0.82, 0, 0.08 } },
  collapseIcon = { pairs = { { "common-button-collapseExpand-minus", "common-button-collapseExpand-plus" },
    { "Professions-recipe-header-collapse", "Professions-recipe-header-expand" } } },
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

local function SingleLine(fs)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end

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
local function SetTip(frame, name, fn)
  frame:SetScript("OnEnter", Guard("tooltip: " .. name, fn))
end

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
