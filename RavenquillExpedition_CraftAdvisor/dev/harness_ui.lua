-- Step 1 harness (plan rev 4, C3): window template + fallback path, minimap gap placement.
-- Run: lua dev/harness_ui.lua   (from the addon folder)
-- Unlike dev/harness.lua, frames here only have the methods listed below; any other method call
-- is nil (recorded in `missing`), so a template field we rely on can't silently "exist".
local ROOT = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/RavenquillExpedition_CraftAdvisor/"
unpack = table.unpack
local fails, passes, missing = 0, 0, {}
local function check(cond, label)
  if cond then passes = passes + 1; print("  ok   " .. label) else fails = fails + 1; print("  FAIL " .. label) end
end

---------------------------------------------------------------------------
-- virtual clock + timers
---------------------------------------------------------------------------
local now, timers = 1000, {}
function GetTime() return now end
function GetServerTime() return 1800000000 + now end
time = function() return 1800000000 + now end
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function advance(sec)
  local target = now + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > target then break end
    table.remove(timers, 1); now = t.at; t.fn()
  end
  now = target
end

---------------------------------------------------------------------------
-- frame mock
---------------------------------------------------------------------------
local Frame = {}
local FrameMT = { __index = function(t, k)
  if Frame[k] then return Frame[k] end
  if type(k) == "string" and k:match("^%u") then missing[k] = (missing[k] or 0) + 1 end
  return nil
end }
local function New(otype, parent, name)
  local o = setmetatable({ _type = otype or "Frame", _parent = parent, _children = {}, _scripts = {},
    _shown = true, _w = 0, _h = 0, _points = {}, _level = parent and (parent._level or 0) + 1 or 0,
    _strata = parent and parent._strata or "MEDIUM", _scale = 1 }, FrameMT)
  if parent and parent._children then table.insert(parent._children, o) end
  if name then _G[name] = o; o._name = name end
  return o
end
local function Tex()
  local t = New("Texture")
  t.SetAtlas = function(self, a, useSize)
    if not C_Texture.GetAtlasInfo(a) then badAtlas = badAtlas + 1 end
    self._atlas, self._atlasSize = a, useSize
  end
  return t
end
for _, m in ipairs({ "SetTexCoord", "SetVertexColor", "SetDesaturated", "SetJustifyH",
  "SetHighlightTexture", "SetNormalTexture", "SetPushedTexture", "SetUserPlaced", "RegisterForClicks", "RegisterForDrag", "SetToplevel", "SetClampedToScreen", "SetMovable",
  "EnableMouse", "StartMoving", "StopMovingOrSizing", "SetScrollChild", "SetTextColor", "SetFixedFrameStrata",
  "SetFixedFrameLevel", "SetChecked", "SetBackdropColor", "SetBackdropBorderColor", "RegisterEvent",
  "UnregisterEvent", "SetColorTexture", "SetAllPoints",
  -- Slider (survival slider, plan F8.3)
  "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture",
  -- H: single-line font strings, clipped header, edit boxes (whisper editor)
  "SetWordWrap", "SetMaxLines", "SetNonSpaceWrap", "SetClipsChildren", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
  "SetCursorPosition",
  -- K6: native-look helpers (blend mode of hover textures, mouse wheel on the plain scroll frame, draw layer)
  "SetBlendMode", "EnableMouseWheel", "SetDrawLayer" }) do
  Frame[m] = function(self, ...) self["_" .. m] = { ... } end
end
function Frame:SetTexture(t) self._tex = t end
function Frame:GetTexture() return self._tex end
function Frame:SetText(t) self._text = t end
function Frame:SetValue(v) local old = self._value; self._value = v; if old ~= v and self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end
function Frame:GetValue() return self._value end
-- K6: the list scroll frames are plain ScrollFrames (MinimalScrollBar), scrolled by SetVerticalScroll
function Frame:SetVerticalScroll(v) self._vscroll = v end
function Frame:GetVerticalScroll() return self._vscroll or 0 end
function Frame:GetText() return self._text end
-- J2: a size change fires OnSizeChanged (as in the game); SetWidth/SetHeight are recorded and change the size too
local function sized(self, w, h)
  local changed = w ~= self._w or h ~= self._h
  self._w, self._h = w, h
  if changed and self._scripts.OnSizeChanged then self._scripts.OnSizeChanged(self, w, h) end
end
function Frame:SetSize(w, h) sized(self, w, h) end
function Frame:SetWidth(w) self._SetWidth = { w }; sized(self, w, self._h) end
function Frame:SetHeight(h) self._SetHeight = { h }; sized(self, self._w, h) end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
-- resizing (J2): SetResizable/StartSizing/SetResizeBounds exist on 10.0+ clients; tests remove them to try the
-- older SetMinResize path and "no API at all"
function Frame:SetResizable(v) self._resizable = v end
function Frame:StartSizing(point) self._sizingFrom = point end
function Frame:SetResizeBounds(...) self._bounds = { ... } end
-- GetLeft/GetTop of a window anchored to UIParent (CENTER or TOPLEFT to BOTTOMLEFT); others: _left/_top
function Frame:GetLeft()
  local p = self._points[1]
  if self._parent == UIParent and p then
    if p[1] == "CENTER" then return (UIParent._w - self._w) / 2 end
    if p[1] == "TOPLEFT" and p[2] == UIParent and p[3] == "BOTTOMLEFT" then return p[4] end
  end
  return self._left
end
function Frame:GetTop()
  local p = self._points[1]
  if self._parent == UIParent and p then
    if p[1] == "CENTER" then return (UIParent._h + self._h) / 2 end
    if p[1] == "TOPLEFT" and p[2] == UIParent and p[3] == "BOTTOMLEFT" then return p[5] end
  end
  return self._top
end
function Frame:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Frame:ClearAllPoints() self._points = {} end
function Frame:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function Frame:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() local f = self; while f do if not f._shown then return false end f = f._parent end return true end
function Frame:SetScript(ev, fn) self._scripts[ev] = fn end
function Frame:GetScript(ev) return self._scripts[ev] end
function Frame:HookScript(ev, fn)
  local old = self._scripts[ev]
  self._scripts[ev] = function(...) if old then old(...) end fn(...) end
end
function Frame:CreateTexture() local t = Tex(); t._parent = self; return t end
function Frame:CreateFontString() local t = New("FontString"); t._parent = self; return t end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata() return self._strata end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level end
function Frame:GetName() return self._name end
function Frame:GetObjectType() return self._type end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetEffectiveScale() return self._scale end
function Frame:GetCenter() return self._cx, self._cy end
function Frame:IsForbidden() return self._forbidden or false end
function Frame:GetChecked() return self._checked end
function Frame:SetBackdrop(b) self._backdrop = b end
function Frame:SetChecked(v) self._checked = v and true or false end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha or 1 end
function Frame:GetParent() return self._parent end
-- SetAtlas exists on textures only; it "draws" only atlases the client has (atlas mock below)
badAtlas = 0
local atlasMode = "ok" -- "ok": the Forever profession atlases exist; "missing": GetAtlasInfo returns nil
local ATLASES = { ["Profession-Background-Overview"] = true, ["Profession-Background-Template2"] = true,
  ["Professions-Slot-Frame"] = true, ["common-dropdown-bg"] = true,
  -- K6: atlases the in-game probe found in the client's own ProfessionsFrame / CharacterFrame
  ["Professions-Slot-bg"] = true, ["Professions-background-summarylist"] = true, ["search-highlight"] = true,
  ["Professions-skillbar-bg"] = true, ["Professions-skillbar-frame"] = true, ["common-dropdown-a-button"] = true,
  ["UI-Character-Info-GearSlot"] = true,
  -- K7: the inner nine-slice border (probe: RecipeList.BackgroundNineSlice / SchematicForm.NineSlice)
  ["UI-Frame-InnerTopLeft"] = true, ["UI-Frame-InnerTopRight"] = true, ["UI-Frame-InnerBotLeftCorner"] = true,
  ["UI-Frame-InnerBotRight"] = true, ["_UI-Frame-InnerTopTile"] = true, ["_UI-Frame-InnerBotTile"] = true,
  ["!UI-Frame-InnerLeftTile"] = true, ["!UI-Frame-InnerRightTile"] = true,
  ["Skillbar_Fill_Flipbook_Leatherworking"] = true, ["Skillbar_Flare_Leatherworking"] = true,
  -- K8: the recipe list's row / category art (probe tpl:ProfessionsRecipeList*Template) and the filter reset badge
  ["Professions_Recipe_Hover"] = true, ["Professions_Recipe_Active"] = true, ["common-button-list-collapseExpand"] = true, ["common-insideframe"] = true, ["Profession-background-card-"] = true, ["Profession-background-card-leatherworking"] = true,
  ["auctionhouse-ui-filter-redx"] = true }
C_Texture = { GetAtlasInfo = function(name)
  if atlasMode == "ok" and ATLASES[name] then return { width = 100, height = 100, file = 1 } end
  return nil
end }

local templateMode = "ok" -- "ok": PortraitFrameTemplate works; "fail": CreateFrame with it errors
-- K6: the native templates the probe confirmed; each can be switched to "fail" (CreateFrame errors) to test fallbacks
nativeMode = { dropdown = "ok", search = "ok", category = "ok", scroll = "ok", check = "ok" }
ScrollUtil = { InitScrollFrameWithScrollBar = function(sf, bar) sf._linkedBar = bar end }
function CreateFrame(otype, name, parent, template)
  if otype == "DropdownButton" then
    if nativeMode.dropdown == "fail" then error("Unknown frame type 'DropdownButton'") end
    local f = New(otype, parent, name)
    f._template = template
    function f:SetupMenu(gen) self._gen = gen end
    function f:GenerateMenu() self._generated = (self._generated or 0) + 1 end
    function f:OverrideText(t) self._override = t end
    f._scripts.OnEnter = function(self) self._nativeEnter = (self._nativeEnter or 0) + 1 end
    f._scripts.OnLeave = function() end
    return f
  end
  if template == "SearchBoxTemplate" and nativeMode.search == "fail" then error("Couldn't find inherited node 'SearchBoxTemplate'") end
  if template == "ProfessionsRecipeListCategoryTemplate" and nativeMode.category == "fail" then error("Couldn't find inherited node") end
  if template == "MinimalScrollBar" and nativeMode.scroll == "fail" then error("Couldn't find inherited node 'MinimalScrollBar'") end
  if template == "MinimalCheckboxTemplate" and nativeMode.check == "fail" then error("Couldn't find inherited node 'MinimalCheckboxTemplate'") end
  if template == "SearchBoxTemplate" or template == "ProfessionsRecipeListCategoryTemplate" or template == "MinimalScrollBar" then
    local f = New(otype, parent, name)
    f._template = template
    if template == "SearchBoxTemplate" then f.Instructions = New("FontString", f); f.clearButton = New("Button", f) end
    if template == "ProfessionsRecipeListCategoryTemplate" then
      f.ButtonText = New("FontString", f); f.CollapseButton = New("Button", f); f.RankBar = New("Frame", f)
      function f:SetHeaderText(t) self.ButtonText._text = t end
      function f:UpdateCollapsedState(c) self._collapsed = c end
      f._scripts.OnEnter = function(self) self._nativeEnter = (self._nativeEnter or 0) + 1 end
      f._scripts.OnLeave = function() end
    end
    if template == "MinimalScrollBar" then
      function f:ScrollStepInDirection(d) self._step = d end
      function f:SetHideIfUnscrollable(v) self._hideIf = v end
    end
    return f
  end
  if template == "PortraitFrameTemplate" then
    if templateMode == "fail" then error("Couldn't find inherited node 'PortraitFrameTemplate'") end
    local f = New(otype, parent, name)
    f.Bg = Tex()
    f.NineSlice = New("Frame", f)
    f.PortraitContainer = { portrait = Tex() }
    f.CloseButton = New("Button", f)
    f.CloseButton._scripts.OnClick = function() error("protected HideUIPanel called in combat") end
    function f:SetTitle(t) self._title = t end
    function f:SetPortraitToAsset(p) self.PortraitContainer.portrait._tex = p end
    return f
  end
  local f = New(otype, parent, name)
  if template == "InsetFrameTemplate" then f.NineSlice = New("Frame", f); f.Bg = Tex() end
  if template == "UIPanelScrollFrameTemplate" then f.ScrollBar = New("Slider", f) end
  return f
end

---------------------------------------------------------------------------
-- game API stubs needed to load Core/UI/Minimap
---------------------------------------------------------------------------
function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
UIParent = New("Frame"); UIParent._w, UIParent._h = 1920, 1080; GameTooltip = New("GameTooltip"); GameTooltip_Hide = function() end
for _, m in ipairs({ "SetOwner", "AddLine", "AddDoubleLine", "SetHyperlink" }) do GameTooltip[m] = function() end end
function InCombatLockdown() return false end
function IsInGuild() return true end
function GetRealmName() return "Realm" end
function UnitName(u) if u == "player" then return "Me", "Stone" end end
function UnitNameUnmodified(u) return UnitName(u) end
function UnitClass(u) if u == "player" then return "Schurke", "ROGUE" end end
function UnitLevel(u) if u == "player" then return 36 end end
function UnitIsUnit(a, b) return a == b end
function UnitIsPlayer(u) return u == "player" end
function UnitGUID(u) if u == "player" then return "G-me" end end
function GetInventoryItemLink(u, slot) if u == "player" and slot == 5 then return "item:4244::::::::36:1488::11" end end
function GetInventorySlotInfo(t) return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. t end
function GetNumGuildMembers() return 0 end
function GetProfessions() return nil end
SlashCmdList = {}
C_Item = {
  GetItemInfoInstant = function(item) return 4244, "Armor", "x", "INVTYPE_CHEST", 134, 4, 2 end,
  GetItemInfo = function(item) return "Hillman's Vest", "|Hitem:4244|h[Hillman's Vest]|h", 2, 20, 20, nil, nil, nil, "INVTYPE_CHEST", 134, nil, 4, 2, 2 end,
  GetItemStats = function() return {} end,
}
C_SpellBook = { IsSpellKnown = function() return false end }

Minimap = New("Frame", nil, "Minimap")
Minimap._w, Minimap._h, Minimap._cx, Minimap._cy, Minimap._scale = 140, 140, 1000, 700, 1
local cursor = { 0, 0 }
function GetCursorPosition() return cursor[1], cursor[2] end

-- a Minimap child at `angle` degrees on the rim
local function Child(name, otype, angle, w, opts)
  local c = New(otype, Minimap, name)
  c._w, c._h = w, w
  local r = 75
  c._cx = Minimap._cx + math.cos(math.rad(angle)) * r
  c._cy = Minimap._cy + math.sin(math.rad(angle)) * r
  for k, v in pairs(opts or {}) do c[k] = v end
  return c
end

---------------------------------------------------------------------------
-- load the addon
---------------------------------------------------------------------------
local ns = {}
local function load(f) assert(loadfile(ROOT .. f))("RavenquillExpedition_CraftAdvisor", ns) end
for _, f in ipairs({ "Locales/enUS.lua", "Locales/deDE.lua", "Data/Leatherworking.lua", "Data/Blacksmithing.lua", "Data/Tailoring.lua", "Data/Engineering.lua", "Data/Enchanting.lua",
  "Data/Enchants.lua", "Data/Weights.lua", "Scoring.lua", "Core.lua", "Spec.lua", "UI.lua" }) do load(f) end
-- capture Minimap.lua's event frame (the unnamed, parentless frame it creates)
local pew
do
  local orig = CreateFrame
  CreateFrame = function(otype, name, parent, template)
    local f = orig(otype, name, parent, template)
    if otype == "Frame" and not parent and not name then pew = f end
    return f
  end
  load("Minimap.lua")
  CreateFrame = orig
end
local GCA = ns.GCA
local fire = GCA._scripts.OnEvent
RavenquillExpeditionCraftDB = { settings = { minimapAngle = 200 } } -- a v0.1 user with the untouched default
fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
fire(GCA, "PLAYER_LOGIN")
pew._scripts.OnEvent(pew, "PLAYER_LOGIN")
advance(3) -- CaptureSelf

print("== Minimap: placement")
-- neighbours that exist BEFORE we scan: Overlord 200, Spoken 204, GearQuest 129.5
Child("OverlordMinimapButton", "Button", 200, 33)
Child("SpokenMinimapButton", "Button", 204, 31)
Child("GearQuestMinimapButton", "Button", 129.5, 31)
-- things that must NOT count
Child("HBD_Pin1", "Button", 20, 12)                          -- map pin (small)
Child("QuestiePin", "Frame", 40, 30)                         -- not a button
Child("ForbiddenThing", "Button", 60, 31, { _forbidden = true })
Child("HiddenButton", "Button", 80, 31, { _shown = false })
local inner = Child("InnerButton", "Button", 100, 31); inner._cx, inner._cy = Minimap._cx + 10, Minimap._cy -- not on rim

local btn = _G.GuildCraftAdvisorMinimapButton
check(btn ~= nil, "button created at PLAYER_LOGIN")
check(btn and btn._strata == "MEDIUM" and btn._level == 8, "strata MEDIUM, level 8")

check(GCA.MinimapFreeAngle ~= nil, "MinimapFreeAngle exported")
local a = GCA:MinimapFreeAngle()
-- counted: 129.5, 200, 204 -> largest gap 204..489.5 -> mid 346.75
check(math.abs(a - 346.75) < 0.01, string.format("largest-gap angle = %.2f (expect 346.75)", a))

-- late button (created after our scan would have run at login) is considered when the delayed scan runs
Child("LateAddonButton", "Button", 300, 31)
local a2 = GCA:MinimapFreeAngle()
-- counted: 129.5, 200, 204, 300 -> gaps 70.5, 4, 96, 189.5 (300 -> 489.5) -> mid 34.75
check(math.abs(a2 - 34.75) < 0.01, string.format("with late button: %.2f (expect 34.75)", a2))

print("== Minimap: delayed auto-place, drag, reset")
pew._scripts.OnEvent(pew, "PLAYER_ENTERING_WORLD")
check(GCA.db.settings.minimapAngle == 200, "angle untouched before the 5 s delay")
advance(5)
check(math.abs(GCA.db.settings.minimapAngle - 34.75) < 0.01,
  string.format("auto-placed after 5 s: %.2f", GCA.db.settings.minimapAngle))
local p = btn._points[1]
check(p and p[1] == "CENTER" and p[2] == Minimap, "button anchored to Minimap centre")
-- drag to 90 degrees (cursor straight above the minimap centre)
cursor[1], cursor[2] = 1000, 800
btn._scripts.OnDragStart(btn); btn._scripts.OnUpdate(btn); btn._scripts.OnDragStop(btn)
check(math.abs(GCA.db.settings.minimapAngle - 90) < 0.01 and GCA.db.settings.minimapDragged, "drag sets 90° and marks dragged")
-- a later login must not move a dragged button
GCA.db.settings.minimapAngle = 200 -- even if it happens to be 200
pew._scripts.OnEvent(pew, "PLAYER_ENTERING_WORLD"); advance(6)
check(GCA.db.settings.minimapAngle == 200, "dragged button not auto-moved")
SlashCmdList.GUILDCRAFTADVISOR("minimap reset")
check(math.abs(GCA.db.settings.minimapAngle - 34.75) < 0.01 and not GCA.db.settings.minimapDragged, "/gca minimap reset re-places it")
SlashCmdList.GUILDCRAFTADVISOR("minimap debug")
-- no neighbours at all
local saved = Minimap._children; Minimap._children = { btn }
check(GCA:MinimapFreeAngle() == 225, "no other buttons -> 225")
Minimap._children = saved
-- a scan error must not break anything
Minimap.GetChildren = function() error("boom") end
check(GCA:MinimapFreeAngle() == 225, "scan error -> 225, no Lua error")
Minimap.GetChildren = nil

-- all frames below `f` (the window's content frame holds our panels since H1)
-- K6: run a native dropdown's menu generator on a recording menu description; entries get :on() and :click()
local function menuOf(dd)
  local entries, root = {}, {}
  local function add(kind, text, isSel, set, data)
    local e = { kind = kind, text = text, isSel = isSel, set = set, data = data }
    function e:SetTooltip(fn) self.tip = fn end
    function e:on() return self.isSel ~= nil and self.isSel(self.data) and true or false end
    function e:click() return self.set(self.data) end
    -- K11: a button can carry a submenu (radio entries in e.sub, not in the flat list)
    e.sub = {}
    function e:CreateRadio(t, i, s2, d)
      local r = { kind = "radio", text = t, isSel = i, set = s2, data = d }
      function r:on() return r.isSel(r.data) and true or false end
      function r:click() return r.set(r.data) end
      e.sub[#e.sub + 1] = r
      return r
    end
    entries[#entries + 1] = e
    return e
  end
  function root:CreateRadio(t, i, s, d) return add("radio", t, i, s, d) end
  function root:CreateCheckbox(t, i, s, d) return add("check", t, i, s, d) end
  function root:CreateButton(t, s, d) return add("button", t, nil, s, d) end
  function root:CreateDivider() return add("divider") end
  function root:CreateTitle(t) return add("title", t) end
  dd._gen(dd, root)
  return entries
end
local function menuTexts(entries, kind)
  local out = {}
  for _, e in ipairs(entries) do if e.text and (not kind or e.kind == kind) then out[#out + 1] = (tostring(e.text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end end
  return table.concat(out, "|")
end
local function descendants(f, out)
  out = out or {}
  for _, c in ipairs(f._children or {}) do out[#out + 1] = c; descendants(c, out) end
  return out
end

local function plain(t) return (tostring(t or ""):gsub("|T.-|t ?", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end -- (|T: the online/offline dot)
local function windowChecks(label)
  print("== Window: " .. label)
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR("")
  advance(1)
  local f = GCA.UI.frame
  check(f and f._shown, "window opens")
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "J2: nothing saved -> default size 980x640, centred")
  if templateMode == "ok" then
    check(f._title == "Guild Craft Advisor", "title set via SetTitle")
    check(f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_LeatherWorking", "portrait set")
    -- H1 art: canvas at the window level, header clipped, NineSlice above, Bg hidden
    local art = f.gcaArt
    check(art and art.overview and art.overview._atlas == "Profession-Background-Overview", "overview atlas drawn")
    check(art and art.pageArt and art.pageArt._atlas == "Profession-Background-Template2" and art.header == nil
      and art.page._points[1][4] == 3 and art.page._points[1][5] == -21, "K6: Template2 over the whole page from 3,-21 as the client's CraftingPage (no 54 px clipped strip)")
    check(art and art.fill._SetColorTexture and art.fill._SetColorTexture[4] == 1, "dark fill under the art")
    check(not f.Bg._shown, "template Bg hidden under the art")
    check(art and f.NineSlice._level > art.canvas._level and f.NineSlice._level > art.page._level
      and f.content._level > art.page._level, "levels: canvas < page < content, border above the art")
  else
    check(f._backdrop ~= nil, "fallback backdrop")
  end
  -- close works "in combat": our OnClick must not call the template's protected handler
  local ok, err = pcall(f.CloseButton._scripts.OnClick, f.CloseButton)
  check(ok and not f._shown, "close button hides the window" .. (ok and "" or (": " .. tostring(err))))
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  check(f._shown, "reopens")
  -- K6: the three list panels are the recipe list's panel (Professions-background-summarylist), each scroll list
  -- with the client's MinimalScrollBar linked by ScrollUtil
  local insets = 0
  for _, c in ipairs(descendants(f)) do
    if c.native and c.bg and c.bg._atlas == "Professions-background-summarylist" then
      insets = insets + 1
      local sf
      for _, cc in ipairs(c._children) do if cc.minimalBar then sf = cc end end
      check(sf and sf._linkedBar == sf.minimalBar and sf.minimalBar._template == "MinimalScrollBar" and sf._scripts.OnMouseWheel
        and sf.ScrollBar == nil, "K6: list panel holds a plain scroll frame + MinimalScrollBar (ScrollUtil), wheel scrolls")
    end
  end
  check(insets == 2, "K8: two list panels on Professions-background-summarylist: guild needs, member list (the suggestions sit in the member's detail panel) (" .. insets .. ")")
  -- K8: both views have the detail panel right of the list, framed by the skin role detailBorder (default: inner border)
  local nd, md = GCA.UI.needDetail, GCA.UI.memberDetail
  check(nd and md and nd.NineSlice and md.NineSlice and nd.NineSlice.role == "detailBorder" and md.NineSlice.role == "detailBorder"
    and nd.NineSlice.how == "atlas1" and nd.NineSlice.frameTex._atlas == "common-insideframe" and nd.cardBg and md.cardBg
    and nd.bg == nil and md.bg == nil and GCA.UI.sugInset._parent == md and GCA.UI.sugInset.bg == nil,
    "K9: craft + member detail panels framed by common-insideframe with the profession card behind, the list/sheet inside")
  -- J1: the gear-slot icon row is gone (no slot buttons, no click-to-jump), the list starts 36 px higher
  local slotLike = 0
  for _, c in ipairs(descendants(f)) do if c.slot ~= nil and c.up ~= nil then slotLike = slotLike + 1 end end
  check(GCA.UI.slotButtons == nil and GCA.UI.ScrollToSlot == nil and GCA.UI.sugList.ScrollToAnchor == nil and slotLike == 0,
    "J1: no gear-slot buttons, no ScrollToSlot/ScrollToAnchor (" .. slotLike .. " slot-like frames)")
  check(GCA.DISPLAY_SLOTS == nil, "J1: Core's DISPLAY_SLOTS (only the gear row used it) removed")
  local ins = GCA.UI.sugInset
  check(ins._points[1][5] == -76 and GCA.UI.sugHeader._points[1][5] == -54 and GCA.UI.infoIcon._points[1][5] == -52
    and GCA.UI.sourceText == nil, "K1/K8: header -54 beside the (i) icon, list area -76 inside the member detail panel")
  check((GCA.UI.subText._text or ""):find("self%-reported"), "source line says self-reported: " .. tostring(GCA.UI.subText._text))
  -- spec picker (F4/F8.2): unknown -> button says so; picking Combat stores a manual spec and is shown
  local sb = GCA.UI.specButton
  GCA.db.specManual = {}; GCA:InvalidateScores(); GCA.UI:Refresh()
  local sdd = sb.dropdown
  check(sb._shown and sdd.native and sdd._template == "WowStyle1DropdownTemplate" and plain(sdd._override):find("unknown – pick", 1, true)
    and sb.small == nil, "K6: spec picker = native WowStyle1DropdownTemplate, text 'unknown – pick' (no 'SPEC' label box): " .. plain(sdd._override))
  check((GCA.UI.emptyText._text or ""):find("Spec unknown"), "empty text asks for a spec")
  local sm = menuOf(sdd)
  check(#sm == 4 and sm[1].kind == "radio" and sm[1]:on() and menuTexts(sm):find("^Automatic.*|Assassination|Combat|Subtlety$"),
    "K6: spec menu radios: Automatic (selected) + 3 Rogue specs: " .. menuTexts(sm))
  sm[3]:click() -- COMBAT
  GCA.UI:Refresh()
  check(GCA.db.specManual["Me Stone"] and GCA.db.specManual["Me Stone"].spec == "COMBAT", "manual pick saved")
  check(menuOf(sdd)[3]:on() and not menuOf(sdd)[1]:on(), "K6: the Combat radio is selected now")
  check(plain(sdd._override):find("Combat") and not sb.icon._shown and sb.iconKind == nil,
    "spec dropdown shows the pick; no class icon in this mock (no atlas, no CLASS_ICON_TCOORDS): " .. plain(sdd._override))
  check((GCA.UI.sourceLine or ""):find("SimGear Forever 0.14.0 · Combat Lv40 %(nearest set for Lv36%) · simmed · leveling bonus 50%%")
    and GCA.UI.infoIcon._shown, "K1: source line in the (i) icon's tooltip: " .. tostring(GCA.UI.sourceLine))
  -- survival slider (F8.3)
  local sl = GCA.UI.survival.slider
  check(sl._value == 50 and (GCA.UI.survival.label._text or ""):find("50%%"), "slider starts at 50 %")
  -- K0/M3: dragging over several steps applies once, 0.4 s after the last change
  local invN, realInv = 0, GCA.InvalidateScores
  GCA.InvalidateScores = function(...) invN = invN + 1; return realInv(...) end
  sl:SetValue(60); advance(0.1); sl:SetValue(70); advance(0.1); sl:SetValue(80)
  check(math.abs(GCA.db.settings.survival - 0.5) < 1e-9 and (GCA.UI.survival.label._text or ""):find("80%%"),
    "slider: label follows at once, value not applied yet (debounce)")
  GCA.UI.survival:Sync()
  check(sl._value == 80, "slider: a refresh during the debounce doesn't snap the slider back")
  advance(0.3)
  check(invN == 0, "slider: nothing recomputed 0.3 s after the last change")
  advance(0.2)
  check(math.abs(GCA.db.settings.survival - 0.8) < 1e-9 and invN == 1, "slider sets survival 0.8, one recompute for 3 steps (" .. invN .. ")")
  GCA.InvalidateScores = realInv
  GCA.UI:Refresh()
  check((GCA.UI.sourceLine or ""):find("leveling bonus 80%%"), "source line follows the slider: " .. tostring(GCA.UI.sourceLine))
  sl:SetValue(50); advance(0.5)
  -- automatic again
  menuOf(sdd)[1]:click()
  check(GCA.db.specManual["Me Stone"] == nil, "Automatic clears the pick")
  f:Hide()
end

templateMode = "ok"; windowChecks("PortraitFrameTemplate path")
do
  -- review L-3 (K1 alpha 0.75) applies to the InsetFrameTemplate fallback only; K6 panels are the list atlas
  local f, n = GCA.UI.frame, 0
  for _, c in ipairs(descendants(f)) do if c.NineSlice and c ~= f and c.Bg then n = n + 1 end end
  check(n == 0, "K6: no InsetFrameTemplate panels while the list atlas exists (" .. n .. ")")
end

do
  print("== Window: profession selector (G3/G6.1/G7.11)")
  local profs = { 165, 333 }
  GetProfessions = function() return 1, 2 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
    if i == 2 then return "Verzauberkunst", nil, 90, 150, nil, nil, 333 end
  end
  GCA:RefreshKnown()
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local f, pb, pop = GCA.UI.frame, GCA.UI.profButton, GCA.UI.profPopup
  check(pb and (pb.label._text or "") == "Lederverarbeitung  120 / 150" and pb.art == "atlas" and pb.bg._atlas == "Professions-skillbar-bg"
    and pb.border._atlas == "Professions-skillbar-frame" and pb._h == 29 and math.abs(pb.ratio - 0.8) < 1e-9 and pb.barKind == "fill"
    and math.abs(pb.fill._w - (GCA.UI.PROF_BAR_W - 10) * 0.8) < 1e-9 and pb.drop.native and pb.drop.arrow._atlas == "common-dropdown-a-button"
    and pb.drop.ring == nil and pop == nil,
    "K6: the profession window's rank bar (skillbar-bg/-frame, 29 px, fill 80 %; plain fill: no StatusBar texture API in this mock) with its dropdown arrow (no disc): " .. tostring(pb and pb.label._text))
  local pm = menuOf(pb.drop)
  local radios = menuTexts(pm, "radio")
  check(#pm == 7 and pm[1]:on() and radios:find("^Lederverarbeitung.*|Verzauberkunst.*|Blacksmithing %(browse%)") and pm[3].kind == "divider"
    and pm[4].kind == "title" and pm[4].text:find("Browse", 1, true), "K6: profession menu: your 2 (radio, picked one on), divider, 'Browse' title, 3 others: " .. radios)
  pm[5]:click() -- Blacksmithing
  GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Blacksmithing" and GCA:IsBrowse(), "picked Blacksmithing: browse")
  check((pb.label._text or ""):find("(browse)", 1, true) and f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_BlackSmithing",
    "button says browse, portrait follows: " .. tostring(f.PortraitContainer.portrait._tex))
  menuOf(pb.drop)[2]:click(); GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Enchanting" and not GCA:IsBrowse(), "picked Enchanting (yours)")
  menuOf(pb.drop)[1]:click(); GCA.UI:Refresh()
  check(GCA:SelectedProfession() == "Leatherworking" and f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_LeatherWorking", "back to Leatherworking")
  f:Hide()
  GetProfessions = function() return nil end
end
-- H: suggestion rows, crafted mark, offline Offer, filter menu, whisper editor, help, legend
local tip, hyper = {}, {}
local function captureTip()
  tip, hyper = {}, {}
  GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
  GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = tostring(a) .. " | " .. tostring(b) end
  GameTooltip.SetText = function(_, t) tip[#tip + 1] = tostring(t) end
  GameTooltip.SetHyperlink = function(_, l) hyper[#hyper + 1] = tostring(l) end
end
local function tipText() return table.concat(tip, "\n") end
-- K17: an item tooltip = exactly one SetHyperlink (containing `frag`) and no line of ours
-- user 2026-11-15: ... plus the "Stat changes for X:" block (green/red stat lines) under it, nothing else
local function onlyChanges()
  if #tip == 0 then return true end
  -- a blank line, the header, then only stat lines (any text: "+6 Agility", "Speed 2.60 → 3.40")
  local head = tostring(tip[2] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return tip[1] == " " and (head:find("^Stat changes") or head:find("^Werteänderungen")) ~= nil and #tip >= 3
end
local function plainTip(frag) return onlyChanges() and #hyper == 1 and (frag == nil or hyper[1]:find(frag, 1, true) ~= nil) end
local function plain(t) return (tostring(t or ""):gsub("|T.-|t ?", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function fakeSug(over)
  local d = { kind = "item", cand = { spellID = 3762, itemID = 4244, recipe = { skill = 100, src = "trainer", r = {} } },
    info = { name = "Hillman's Leather Vest", link = "|Hitem:4244|h[Hillman's Leather Vest]|h", quality = 2, icon = "x", minLevel = 20 },
    slot = 5, known = true, status = "upgrade", pct = 0.12, points = 12, tier = 1, oldScore = 1, newScore = 2 }
  for k, v in pairs(over or {}) do d[k] = v end
  -- user 2026-11-14: rows sort by points; the older fixtures give their size as sortPct (a "+38%" row = 38 points)
  if over and over.sortPct and over.points == nil then d.points = over.sortPct end
  d.sortPct = nil
  return d
end
do
  print("== Window: suggestion rows (L1, L6, H5.1, H5.2, U3)")
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  local f = UIx.frame
  local cur = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local function show(d, c)
    UIx.current = c or cur
    UIx.sugList:SetData({ d })
    return UIx.sugList.rows[1]
  end
  local d = fakeSug()
  local b = show(d)
  check(b.title._SetWordWrap and b.title._SetWordWrap[1] == false and b.title._SetMaxLines and b.title._SetMaxLines[1] == 1
    and b.sub._SetWordWrap and b.sub._SetWordWrap[1] == false, "L1: title and sub-line are single-line")
  check(b.iconBorder._atlas == "Professions-Slot-Frame" and b.frameArt == "atlas" and b.slotBg and b.qual._atlas == "Professions-Slot-bg"
    and b.iconBorder._SetVertexColor and b.iconBorder._SetVertexColor[2] == 1 and b.icon._w == 38,
    "K6 card: 38 px icon in the reagent slot (Professions-Slot-bg + Professions-Slot-Frame tinted by quality)")
  check(plain(b.title._text) == "Hillman's Leather Vest" and not plain(b.title._text):find(":", 1, true),
    "K1/J3: title = the item name only, no 'Slot:' prefix: " .. plain(b.title._text))
  check(b.offer._shown and not b.offer.isIcon and b.offer._text == "Offer" and b.offer._w == 84
    and b.crafted._shown and b.craftedLabel == nil and b.gainAnchor == b.crafted,
    "K4 card: online known craft: 'Offer' text button + crafted box (no label), gain left of the box (K1 had the whisper icon)")
  check(plain(b.gain._text) == "+12 pts" and plain(b.points._text) == "" and b.gain._SetTextColor and b.gain._SetTextColor[2] > 0.8
    and b._SetHeight[1] == 50 and b.alt == nil and b.treeV == nil, "K4 card: 50 px, green '+12 pts' (no size line without a share); K6: no row shading, no tree lines")
  check(b.title._alpha == 1 and not b.dimmed, "wearable row not dimmed")
  -- U3: offline -> no Offer; tooltip says why; gain re-anchors (L6)
  local off = { key = "Bud Stone", online = false, prof = "Leatherworking", level = 39, class = "ROGUE" }
  b = show(d, off)
  check(not b.offer._shown and b.crafted._shown and b.crafted._points[1][2] == b, "offline: no Offer, crafted box moves to the right edge")
  check(not UIx.CanOffer(off, d) and UIx.CanOffer(cur, d), "CanOffer: online yes, offline no (craft)")
  check(not UIx.CanOffer(off, fakeSug({ kind = "enchant" })), "CanOffer: offline enchant no")
  captureTip()
  b._scripts.OnEnter(b)
  check(plainTip("item:4244"), "K17: row tooltip = the plain item tooltip (no Offer/Shift/gain lines): " .. tipText())
  do -- user 2026-11-15: the compare tooltips show what THIS member wears, not your gear
    local function fakeCompare()
      local t = New("GameTooltip")
      t.links, t.lines = {}, {}
      t.SetHyperlink = function(self, l) self.links[#self.links + 1] = l end
      t.SetText = function(self, s) self.lines[#self.lines + 1] = tostring(s) end
      t.AddLine = function(self, s) self.lines[#self.lines + 1] = tostring(s) end
      t.GetWidth = function() return 200 end
      t.SetOwner = function() end
      t:Hide()
      return t
    end
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    local ownerOf
    local savedShown, savedOwner, savedRight = GameTooltip.IsShown, GameTooltip.GetOwner, GameTooltip.GetRight
    GameTooltip.IsShown = function() return true end
    GameTooltip.GetOwner = function() return ownerOf end
    GameTooltip.GetRight = function() return 600 end
    local savedSetOwner = GameTooltip.SetOwner
    GameTooltip.SetOwner = function(self, o, ...) ownerOf = o; if savedSetOwner then return savedSetOwner(self, o, ...) end end
    local wb = show(fakeSug({ equipped = { name = "Old Vest", link = "item:2105", quality = 1 } }))
    wb._scripts.OnEnter(wb)
    local s1 = ShoppingTooltip1
    check(s1._shown and s1.links[1] == "item:2105" and plain(s1.lines[#s1.lines]) == "Equipped by Bud Stone" and not ShoppingTooltip2._shown,
      "hovering a craft: compare tooltip = the member's worn Old Vest, 'Equipped by Bud Stone': " .. table.concat(s1.lines, " | "))
    -- Blizzard's own comparison (Shift / always compare) is put back to the member's item
    s1.links = {}
    UIx.FillCompare()
    check(s1.links[1] == "item:2105", "a later Blizzard compare is overwritten with the member's item")
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    wb = show(fakeSug({ equipped = nil, status = "empty-slot" }))
    wb._scripts.OnEnter(wb)
    check(ShoppingTooltip1._shown and #ShoppingTooltip1.links == 0 and ShoppingTooltip1.lines[1] == "Nothing equipped in this slot"
      and plain(ShoppingTooltip1.lines[2]) == "Equipped by Bud Stone", "empty slot: the compare tooltip says nothing is equipped")
    ShoppingTooltip1, ShoppingTooltip2 = fakeCompare(), fakeCompare()
    local pairInfo = { name = "Sword + Shield", pair = { { name = "Sword", link = "item:1" }, { name = "Shield", link = "item:2" } } }
    wb = show(fakeSug({ equipped = pairInfo, bothHands = true }))
    wb._scripts.OnEnter(wb)
    check(ShoppingTooltip1.links[1] == "item:1" and ShoppingTooltip2.links[1] == "item:2" and ShoppingTooltip2._shown,
      "a two-hander: both worn hands in the two compare tooltips")
    UIx.HideCompare()
    ShoppingTooltip1, ShoppingTooltip2 = nil, nil
    GameTooltip.IsShown, GameTooltip.GetOwner, GameTooltip.GetRight, GameTooltip.SetOwner = savedShown, savedOwner, savedRight, savedSetOwner
    captureTip()
  end
  -- browse: no Offer, no box -> gain anchored to the row
  b = show(fakeSug({ known = false }), { key = "Bud Stone", online = true, prof = "Blacksmithing", browse = true, level = 39 })
  check(not b.offer._shown and not b.crafted._shown and b.gainAnchor == b and b.nl._shown and plain(b.nl.text._text) == "Not learned"
    and not plain(b.sub._text):find("Not learned", 1, true),
    "browse: no Offer, no box, gain at the right edge, the 'Not learned' button starts the second line")
  -- H5.2: too high level
  b = show(fakeSug({ future = true, wearAt = 42, levelsToGo = 3, info = { name = "Future Vest", quality = 3, icon = "x", minLevel = 42 } }))
  check(b.chip == nil and plain(b.sub._text):find("^from level 42 · 3 to go") and b.sub._text:find("|cfff0b44c", 1, true),
    "H5.2/K6: too-high-level row: the level tag is orange TEXT first on the second line (no chip box): " .. plain(b.sub._text))
  check(b.dimmed and b.title._alpha < 1 and b.icon._alpha < 1 and b.sub._alpha < 1, "H5.2: row dimmed")
  check(b.qual._alpha == 0.55 and b.iconBorder._alpha == 0.55 and (b.offer._alpha or 1) == 1 and (b.crafted._alpha or 1) == 1,
    "L-5: quality square + icon border dimmed too; Offer and the crafted box not")
  b = show(fakeSug({ future = true, wearAt = 40, levelsToGo = 1 }))
  check(plain(b.sub._text):find("^from level 40 · 1 to go"), "K6 level tag with 1 level to go: " .. plain(b.sub._text))
  b = show(fakeSug())
  check(b.qual._alpha == 1 and b.iconBorder._alpha == 1, "L-5: a wearable row on the same (pooled) frame is full alpha again")
  -- K1: a normal slot's row doesn't repeat the worn item (the section header shows it); ring/trinket rows and
  -- enchants still say what they replace; an empty slot shows no tag either (header + "(empty slot)" gain say it)
  b = show(fakeSug({ equipped = { name = "Old Vest", quality = 2 } }))
  check(plain(b.sub._text) == "" and b.title._points[1][1] == "LEFT", "K1: chest row: no 'replaces Old Vest', title centred (no sub-line)")
  b = show(fakeSug({ slot = 13, equipped = { name = "Old Charm", quality = 2 } }))
  check(plain(b.sub._text) == "replaces Old Charm" and plain(b.title._text) == "Hillman's Leather Vest (Trinket 1)" and b.title._points[1][1] == "TOPLEFT",
    "K1: trinket row: '(Trinket 1)' + 'replaces Old Charm': " .. plain(b.sub._text))
  b = show(fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
    equipped = { name = "Minor Stamina" }, cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } } }))
  check(plain(b.sub._text) == "replaces Minor Stamina on Bracers", "K1: enchant row keeps 'replaces X on Y': " .. plain(b.sub._text))
  captureTip(); show(fakeSug({ equipped = { name = "Old Vest", quality = 2 } }))._scripts.OnEnter(UIx.sugList.rows[1])
  check(plainTip("item:4244"), "K17: no 'replaces' line in the item tooltip either")
  -- H5.1: tick -> mark stored locally; untick -> gone
  b = show(d)
  b.crafted:SetChecked(true); b.crafted._scripts.OnClick(b.crafted)
  local mark = GCA:CraftedMark("Bud Stone", "Leatherworking", 3762)
  check(mark and mark.item == 4244 and RavenquillExpeditionCraftDB.crafted[GCA.charKey]["Bud Stone"].Leatherworking[3762] == mark,
    "ticking stores the mark in SavedVariables (per character)")
  b = show(d)
  check(b.crafted._checked == true, "box shows the mark after a refresh")
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(tip[1] == "Crafted" and tipText():find("Crafted for Bud Stone", 1, true) and tipText():find("wearing it", 1, true),
    "K1: box tooltip = the label as title + the explanation")
  b.crafted:SetChecked(false); b.crafted._scripts.OnClick(b.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) == nil and RavenquillExpeditionCraftDB.crafted[GCA.charKey]["Bud Stone"] == nil,
    "unticking removes the mark (and empty tables)")
  b = show(fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
    cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } } }))
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(tip[1] == "Enchanted", "enchant row: box tooltip title 'Enchanted'")
  -- the row's Offer whisper uses the member's first name
  check(UIx.OfferText("Leatherworking", d, "Bud Stone"):find("^Hi Bud! I'm a leatherworker and could craft you |Hitem:4244"),
    "whisper: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))

  print("== Window: K6 Filter dropdowns (L5 toggles), whisper editor (U2), help (U6)")
  local fb, mf = UIx.filterButton, UIx.memberFilter
  check(UIx.optionsButton == nil and UIx.optionsPopup == nil and fb.native and mf.native and fb._template == "WowStyle1FilterDropdownTemplate"
    and mf._template == "WowStyle1FilterDropdownTemplate" and fb._w == 90 and fb._h == 18 and UIx.filterPopup == nil,
    "K6: no Options button/popup; two native Filter dropdowns (needs bar + member list), 90x18 as the recipe list's")
  check(mf._points[1][1] == "TOPRIGHT" and mf._points[1][2] == UIx.memberInset and mf._points[1][4] == -8 and mf._points[1][5] == -9,
    "K6: member list Filter at TOPRIGHT -8,-9 of its panel (the recipe list's own spot)")
  check(UIx.survival._parent == f.content and not UIx.survival._shown and UIx.helpButton == nil,
    "K11: the bottom slider is hidden with the native Filter menu; no '?' help button")
  local op = menuOf(fb)
  check(#op == 8 and op[1].kind == "check" and op[5].kind == "check" and op[6].kind == "divider" and op[7].kind == "button"
    and #op[7].sub == 5 and op[8].kind == "button",
    "K11: filter menu: 4 settings + offline members, divider, leveling bonus submenu (5 values), edit whisper (" .. #op .. ")")
  check(menuTexts(op) == "Show missing recipes|Look ahead 5 levels|Read gear automatically|Guild sync|Include offline members (0)|Leveling bonus (Stamina/Spirit): 50%|Edit whisper text…",
    "menu labels: " .. menuTexts(op))
  check(op[1].tip ~= nil and op[7].tip ~= nil and op[8].tip ~= nil, "K6: every entry has its tooltip")
  check(op[7].sub[3]:on() and not op[7].sub[4]:on(), "K11: 50 % is the selected bonus")
  op[7].sub[4]:click()
  check(math.abs(GCA.db.settings.survival - 0.75) < 1e-9 and menuOf(fb)[7].sub[4]:on(), "K11: picking 75 % sets the bonus")
  menuOf(fb)[7].sub[3]:click()
  check(math.abs(GCA.db.settings.survival - 0.5) < 1e-9, "K11: ...and back to 50 %")
  local before = GCA.db.settings.showUnlearned
  op[1]:click()
  check(GCA.db.settings.showUnlearned == not before and menuOf(fb)[1]:on() == GCA.db.settings.showUnlearned and (fb._generated or 0) > 0,
    "entry 1 toggles showUnlearned, the check follows, the open menu is regenerated")
  menuOf(fb)[1]:click()
  check(GCA.db.settings.showUnlearned == before, "...and back")
  local la = GCA.db.settings.lookahead
  menuOf(fb)[2]:click()
  check(GCA.db.settings.lookahead == not la, "entry 2 toggles lookahead")
  menuOf(fb)[2]:click()
  local ai = GCA.db.settings.autoInspect
  menuOf(mf)[3]:click(); check(ai == true and GCA.db.settings.autoInspect == false, "K5: entry 3 toggles autoInspect (default on; the member list's Filter too)")
  menuOf(mf)[3]:click()
  menuOf(fb)[8]:click()
  local ed = UIx.whisperEditor
  check(ed and ed._shown, "last entry opens the whisper editor")
  check(ed.craft._text == UIx.DefaultTemplate("craft") and ed.enchant._text == UIx.DefaultTemplate("enchant"), "editor starts with the defaults")
  ed.craft:SetText("Yo {name}, {item} for your {slot}? {nope}")
  ed.saveBtn._scripts.OnClick(ed.saveBtn)
  check(GCA.db.settings.whisperCraft == "Yo {name}, {item} for your {slot}? {nope}" and GCA.db.settings.whisperEnchant == nil and not ed._shown,
    "Save stores the edited craft text only (unchanged enchant text stays default = nil)")
  check(UIx.OfferText("Leatherworking", d, "Bud Stone") == "Yo Bud, |Hitem:4244|h[Hillman's Leather Vest]|h for your Chest? {nope}",
    "custom template filled, unknown placeholder kept: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))
  SlashCmdList.GUILDCRAFTADVISOR("whisper")
  check(ed._shown and ed.craft._text == "Yo {name}, {item} for your {slot}? {nope}", "/gca whisper reopens it with the saved text")
  ed.resetBtn._scripts.OnClick(ed.resetBtn)
  check(GCA.db.settings.whisperCraft == nil and ed.craft._text == UIx.DefaultTemplate("craft"), "Reset to default clears the saved text")
  ed.closeBtn._scripts.OnClick(ed.closeBtn)
  captureTip(); UIx.memberSearch._scripts.OnEnter(UIx.memberSearch)
  check(UIx.memberHeader == nil and tipText():find("Search member", 1, true) and tipText():find("by name", 1, true),
    "K5: a member search box on top of the list (replaces the column header / badge legend)")
  local mr = UIx.memberList.rows[1]
  check(mr and mr.name._SetWordWrap and mr.name._SetWordWrap[1] == false, "member rows single-line")
  check(UIx.survival.label._text == "Leveling bonus (Stamina/Spirit): 50%", "slider renamed: " .. tostring(UIx.survival.label._text))
  f:Hide()
end

do
  print("== Window: German client (H4)")
  ns.locale = "deDE"
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  check(UIx.filterButton.native and UIx.optionsButton == nil, "K6: German window has the native Filter dropdown (its text is the template's own)")
  check(UIx.survival.label._text == "Levelbonus (Ausdauer/Willenskraft): 50%", "slider in German (our fallback words): " .. tostring(UIx.survival.label._text))
  check(plain(UIx.subText._text):find("^Stufe 36 "), "sub-line uses our 'Stufe' when LEVEL is missing: " .. plain(UIx.subText._text))
  LEVEL, SPELL_STAT3_NAME = "StufeCL", "AusdauerCL"
  UIx:Refresh()
  check(plain(UIx.subText._text):find("^StufeCL 36") and UIx.survival.label._text:find("AusdauerCL", 1, true), "client globals win where they exist")
  LEVEL, SPELL_STAT3_NAME = nil, nil
  local d = fakeSug()
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39 }
  UIx.sugList:SetData({ d })
  local b = UIx.sugList.rows[1]
  captureTip(); b.crafted._scripts.OnEnter(b.crafted)
  check(tip[1] == "Hergestellt" and UIx.WearableText({ wearAt = 42, levelsToGo = 3 }) == "tragbar ab Stufe 42 (in 3 Stufen)", "row texts in German")
  check(UIx.SpecialisationText("Engineering", "Gnomish Goggles"):find("Gnomen-Ingenieurskunst", 1, true)
    and UIx.SpecialisationText("Engineering", "Goblin Rocket Boots"):find("Goblin-Ingenieurskunst", 1, true),
    "M-1: specialisation word in German: " .. UIx.SpecialisationText("Engineering", "Gnomish Goggles"))
  check(UIx.OfferText("Leatherworking", d, "Bud Stone") == "Hallo Bud! Ich bin Lederverarbeiter und könnte dir |Hitem:4244|h[Hillman's Leather Vest]|h herstellen – das wäre eine Verbesserung (Chest). Interesse?",
    "German whisper: " .. UIx.OfferText("Leatherworking", d, "Bud Stone"))
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
end

-- Section I: a suggestion list grouped per slot, shaped like Core's (list + list.sections). rowsBySlot = { [key] = rows }.
-- Worn: chest vest (score 12.34), wrist bracers, Ring A + Ring B, trinket 13 not loaded + 14 empty, the rest empty.
local function fakeSections(rowsBySlot, totals)
  local worn = {
    [5] = { { slot = 5, link = "item:4244", info = { name = "Worn Vest", quality = 2, link = "|Hitem:4244|h[Worn Vest]|h" }, score = 12.34 } },
    [9] = { { slot = 9, link = "item:4245", info = { name = "Bracers", quality = 1 }, score = 3 } },
    [11] = { { slot = 11, link = "item:5001", info = { name = "Ring A", quality = 3 }, score = 4 },
      { slot = 12, link = "item:5002", info = { name = "Ring B", quality = 2 }, score = 2 } },
    [13] = { { slot = 13, link = "item:5003", unknown = true }, { slot = 14 } },
  }
  local list, with, without = {}, {}, {}
  for _, slots in ipairs(GCA.SECTION_SLOTS) do
    local key = slots[1]
    local rows = rowsBySlot[key] or {}
    local w = worn[key]
    if not w then w = {}; for _, sl in ipairs(slots) do w[#w + 1] = { slot = sl } end end
    local s = { key = key, slots = slots, rows = rows, total = (totals and totals[key]) or #rows, worn = w, unknown = key == 13 }
    if #rows > 0 then with[#with + 1] = s else without[#without + 1] = s end
    for _, r in ipairs(rows) do list[#list + 1] = r end
  end
  for _, s in ipairs(without) do with[#with + 1] = s end
  list.sections = with
  return list
end

do
  print("== Window: slot sections (plan I)")
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local before = UIx.errorCount
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local s1, s2 = fakeSug(), fakeSug({ info = { name = "Second Vest", quality = 2, icon = "x", minLevel = 20 }, pct = 0.05, sortPct = 5, extra = true })
  local ring = fakeSug({ slot = 12, info = { name = "Craft Ring", quality = 2, icon = "x", minLevel = 20 }, equipped = { name = "Ring B", quality = 2 } })
  local list = fakeSections({ [5] = { s1, s2 }, [11] = { ring } }, { [5] = 5 })
  local data = UIx.SectionRows(list)
  local shape = {}
  for i, d in ipairs(data) do shape[i] = d.rowKind == "fold" and ("F" .. #d.secs) or (d.rowKind and ("H" .. d.sec.key)) or d.info.name end
  check(#data == 6 and table.concat(shape, ",") == "H5,Hillman's Leather Vest,Second Vest,H11,Craft Ring,F13",
    "K1: SectionRows: header + its rows per section with an upgrade, then ONE folded line for the 13 others: " .. table.concat(shape, ","))
  check(#UIx.SectionRows(fakeSections({})) == 0 and #UIx.SectionRows({}) == 0, "no suggestion at all: empty list (the empty-state text explains why)")
  local sl = UIx.sugList
  sl:SetData(data)
  local H = sl.pools.section
  local FP = sl.pools.fold
  check(H and #H == 2 and FP and #FP == 1 and sl.rows[1].data == s1 and sl.rows[3].data == ring and (sl.rows[4] == nil or not sl.rows[4]._shown),
    "row kinds: 2 section rows + 1 folded line (own pools) + 3 suggestion rows")
  local foldH = sl.rowY[6][2]
  check(sl.rows[1]._points[1][3] == -56 and sl.rows[2]._points[1][3] == -108 and H[2]._points[1][3] == -160 and FP[1]._points[1][3] == -268,
    "K5: rows stacked by kind height (worn row 56, card 52, then the folded box; K4 had a 30 px header)")
  check(sl.contentH == 2 * 56 + 3 * 52 + foldH and foldH >= 30, "content height = 2 worn rows + 3 cards + the folded box (" .. tostring(sl.contentH) .. ", box " .. foldH .. ")")
  -- header: slot name + worn item (icon, link, score)
  local h = H[1]
  check(h.name == nil and h.label == nil and plain(h.wornName._text) == "Worn Vest" and h.wornName._text:find("^|cff")
    and h.wornName._points[1][1] == "LEFT" and h.wornName._points[1][2] == h.box.qual and h.wornName._points[1][4] == 12
    and h.count._text == "2 upgrades" and not h.empty and h.box.bg == nil and h.box.edges == nil and h.box.line._SetColorTexture and h.box._points[1][5] == -6,
    "K5 / user 2026-11-15: chest worn row: icon + the worn name only (centred, 12 px gap; no slot name, no 'Equipped'), '2 upgrades' on the right, a box 6 px below the row top: " .. plain(h.wornName._text))
  check(h.box.icon._tex == 134 and h.box.icon._w == 34 and h.box.iconBorder._SetVertexColor
    and h.wornName._SetWordWrap[1] == false, "K5: worn row: 34 px item icon in its quality frame, single-line texts")
  -- rings: one section, both items side by side
  local r = H[2]
  check(r.name == nil and plain(r.wornName._text) == "Ring A  ·  Ring B" and r.count._text == "1 upgrade",
    "K5: rings worn row: both rings named, '1 upgrade': " .. plain(r.wornName._text))
  -- K6: the cards hang under the worn row, indented 16 px; no tree lines, no row shading (mockup gimmicks)
  local c1, c2, c3 = sl.rows[1], sl.rows[2], sl.rows[3]
  check(c1.treeV == nil and c1.treeH == nil and c1.alt == nil and UIx.TREE_X == nil and c1.qual._points[1][4] == UIx.CARD_INDENT + 4 and UIx.CARD_INDENT == 16,
    "K6: cards indented 16 px under their worn row, no tree lines / row shading")
  -- K1: the slots without an upgrade = one wrapped grey line, in character order
  local g = FP[1]
  check(g.text._text == "No craftable upgrade: Head, Neck, Shoulder, Back, Wrist, Hands, Waist, Legs, Feet, Trinkets (not loaded), Main Hand, Off Hand, Ranged"
    and g.text._SetWordWrap and g.text._SetWordWrap[1] == true and g.text._SetMaxLines == nil and g.text._SetWidth[1] == UIx.listW - 20 and g.edges == nil and g.line ~= nil,
    "K1: one folded, wrapping line names the 13 slots (unloaded trinket marked): " .. tostring(g.text._text))
  check(not (g.text._text or ""):find("–", 1, true), "K1: no '– no upgrade –' lines any more")
  local gt = g
  -- the suggestion rows inside a section are the usual rows (Offer, crafted box, gain)
  local b = sl.rows[1]
  check(b.offer._shown and b.crafted._shown and plain(b.title._text) == "Hillman's Leather Vest", "suggestion rows inside a section (K1 title)")
  check(plain(sl.rows[3].title._text) == "Craft Ring (Ring 2)" and plain(sl.rows[3].sub._text):find("replaces", 1, true)
    and not plain(b.sub._text):find("replaces", 1, true),
    "K1: ring row keeps a disambiguator '(Ring 2)' and 'replaces …'; a normal slot's row doesn't repeat the worn item: " .. plain(sl.rows[3].title._text))
  -- tooltips
  captureTip(); h._scripts.OnEnter(h)
  check(plainTip(), "K17: worn row (section header) tooltip = the worn item's plain tooltip: " .. tipText())
  captureTip(); g._scripts.OnEnter(g)
  check(tipText():find("Slots without an upgrade", 1, true) and tipText():find("Wrist: Bracers", 1, true) and tipText():find("Head: nothing equipped", 1, true)
    and tipText():find("Nothing in this list beats", 1, true), "K1: folded line tooltip lists each slot's worn item and explains")
  captureTip(); gt._scripts.OnEnter(gt)
  check(tipText():find("didn't load", 1, true), "unloaded trinket: tooltip says it wasn't compared")
  captureTip(); r._scripts.OnEnter(r)
  check(tipText():find("Rings", 1, true) and tipText():find("Ring 1: Ring A", 1, true) and tipText():find("Ring 2: Ring B", 1, true) or tipText():find("Finger", 1, true),
    "K5: rings worn row tooltip lists both rings")
  local clicked
  HandleModifiedItemClick = function(l) clicked = l end
  h._scripts.OnClick(h)
  check(clicked == "|Hitem:4244|h[Worn Vest]|h", "worn row click links the real hyperlink")
  -- ScrollTo is clamped to the scroll range (J1: the gear-row jump is gone; ScrollTo stays for the reset)
  -- (K1: with the folded line this list is shorter than the view, so a longer one is used here)
  local saveData = sl.data
  sl:SetData(UIx.SectionRows(fakeSections({ [1] = { fakeSug({ slot = 1 }), fakeSug({ slot = 1 }), fakeSug({ slot = 1 }) },
    [3] = { fakeSug({ slot = 3 }), fakeSug({ slot = 3 }), fakeSug({ slot = 3 }) }, [5] = { fakeSug(), fakeSug(), fakeSug() },
    [7] = { fakeSug({ slot = 7 }), fakeSug({ slot = 7 }), fakeSug({ slot = 7 }) } })))
  local viewH = sl.viewH
  check(sl.contentH > viewH and sl:ScrollTo(1e6) == sl.contentH - viewH and sl:Offset() == sl.contentH - viewH and sl:ScrollTo(-5) == 0,
    "ScrollTo clamped to [0, content - view]")
  sl:SetData(saveData)
  check(data[1].anchor == nil, "J1: section entries carry no jump anchor any more")
  -- another member starts at the top; a refresh of the same member keeps the position (a member with a long list)
  local origML = GCA.GetMemberList
  -- (J2: the default view is taller now, so the list needs more rows to be "long")
  -- (K1: the grey lines are folded into one, so more rows are needed to be "long")
  local long = fakeSections({ [1] = { fakeSug({ slot = 1 }), fakeSug({ slot = 1 }), fakeSug({ slot = 1 }) },
    [5] = { fakeSug(), fakeSug(), fakeSug() }, [9] = { fakeSug({ slot = 9 }), fakeSug({ slot = 9 }), fakeSug({ slot = 9 }) },
    [10] = { fakeSug({ slot = 10 }), fakeSug({ slot = 10 }), fakeSug({ slot = 10 }) } })
  GCA.GetMemberList = function()
    return { { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", state = "ok",
      member = { items = {}, time = time(), source = "inspect" }, suggestions = long, best = long[1], knownCount = 1 } }
  end
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  GCA.db.settings.memberView = "list" -- K4: the list variant (the character sheet is the default)
  UIx:Refresh()
  sl:ScrollTo(100)
  UIx.listKey = "Someone Else|Leatherworking"
  UIx:Refresh()
  check(sl.contentH > sl.viewH + 100 and sl:Offset() == 0 and UIx.listKey == "Bud Stone|Leatherworking",
    "member/profession change scrolls the list to the top")
  sl:ScrollTo(50)
  UIx:Refresh()
  check(sl:Offset() == 50, "a refresh of the same member keeps the scroll position")
  GCA.db.settings.memberView = "sheet"
  GCA.GetMemberList = origML
  -- pooled: a smaller list hides the rest of both pools
  sl:SetData(UIx.SectionRows(fakeSections({ [9] = { fakeSug({ slot = 9 }) } })))
  local shownH = 0
  for _, x in ipairs(H) do if x._shown then shownH = shownH + 1 end end
  check(shownH == 1 and FP[1]._shown and sl.rows[1]._shown and not sl.rows[2]._shown and not sl.rows[3]._shown, "pools reused; unused rows hidden")
  check(UIx.errorCount == before, "no error reported")
  HandleModifiedItemClick = function() end

  print("== Window: slot sections in German (plan I)")
  ns.locale = "deDE"
  f:Hide()
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  UIx.sugList:SetData(UIx.SectionRows(fakeSections({ [5] = { fakeSug() } })))
  local byKey = {}
  for _, x in ipairs(UIx.sugList.pools.section) do byKey[x.data.sec.key] = x end
  local gf = UIx.sugList.pools.fold[1]
  check((gf.text._text or ""):find("^Keine herstellbare Verbesserung: Head, ") and gf.text._text:find("Ringe", 1, true)
    and gf.text._text:find("Schmuckstücke (nicht geladen)", 1, true), "German folded line: " .. tostring(gf.text._text))
  captureTip(); gf._scripts.OnEnter(gf)
  check(tipText():find("Plätze ohne Verbesserung", 1, true) and tipText():find("nichts angelegt", 1, true), "German folded-line tooltip")
  captureTip(); byKey[5]._scripts.OnEnter(byKey[5])
  check(plainTip(), "K17: German header tooltip = the plain item tooltip: " .. tipText():gsub("\n", " / "))
  check(UIx.errorCount == before, "no error reported (German)")
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
end

-- Plan J2: resizable window. A small anchor resolver turns the mock's SetPoint/SetSize records into rectangles
-- (window coordinates: x right, y down from the window's top-left), so overlaps and "fills the panel" can be
-- checked at different sizes. Font strings have no height in the mock: 12 px (one line of the small/normal fonts).
local FS_H = 12
local function rectOf(fr, win, depth)
  depth = (depth or 0) + 1
  assert(depth < 30, "anchor loop")
  if fr == win then return { l = 0, t = 0, r = win._w, b = win._h } end
  if fr._SetAllPoints then return rectOf(fr._SetAllPoints[1] or fr._parent, win, depth) end
  local w, h = fr._w or 0, fr._h or 0
  if fr._type == "FontString" and h == 0 then h = FS_H end
  local l, r, t, b, cx, cy
  for _, p in ipairs(fr._points) do
    local point, rel, relPoint, x, y
    if type(p[2]) == "table" then point, rel, relPoint, x, y = p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0
    else point, rel, relPoint, x, y = p[1], fr._parent, p[1], p[2] or 0, p[3] or 0 end
    local R = rectOf(rel, win, depth)
    local ax = relPoint:find("LEFT") and R.l or (relPoint:find("RIGHT") and R.r or (R.l + R.r) / 2)
    local ay = relPoint:find("TOP") and R.t or (relPoint:find("BOTTOM") and R.b or (R.t + R.b) / 2)
    ax, ay = ax + x, ay - y
    if point:find("LEFT") then l = ax elseif point:find("RIGHT") then r = ax else cx = ax end
    if point:find("TOP") then t = ay elseif point:find("BOTTOM") then b = ay else cy = ay end
  end
  if not (l and r) then
    if l then r = l + w elseif r then l = r - w else l, r = cx - w / 2, cx + w / 2 end
  end
  if not (t and b) then
    if t then b = t + h elseif b then t = b - h else t, b = cy - h / 2, cy + h / 2 end
  end
  return { l = l, t = t, r = r, b = b }
end
local function overlap(a, b) return a.l < b.r and b.l < a.r and a.t < b.b and b.t < a.b end
local function rstr(a) return string.format("(%g,%g)-(%g,%g)", a.l, a.t, a.r, a.b) end

-- a long sectioned list (15 headers + 15 rows) and 40 members, to count visible rows
local function longList()
  local rows = {}
  for _, slot in ipairs({ 1, 3, 5, 7, 8 }) do
    rows[slot] = { fakeSug({ slot = slot }), fakeSug({ slot = slot }), fakeSug({ slot = slot }) }
  end
  return fakeSections(rows)
end
local function manyMembers()
  local m = {}
  -- K2: recorded (member set), so they are listed on top, not in the collapsed "Not recorded" group
  for i = 1, 40 do m[i] = { key = "Member" .. i .. " Stone", level = 30, class = "ROGUE", online = true, member = { items = {} } } end
  return m
end

local function layoutChecks(UIx, f, label)
  local W, H = f._w, f._h
  local R = function(fr) return rectOf(fr, f) end
  -- K1/K2: the header strip (profession selector + sync dot), the bottom bar and each view's controls: inside the
  -- window and no overlaps (checked per view, since only one view is shown at a time)
  local common = {
    { "drag bar", UIx.dragBar }, { "profession selector", UIx.profButton }, { "sync dot", UIx.syncDot },
    { "K6 leveling-bonus slider", UIx.survival }, -- K5: the "Inspect target" / "Scan group" buttons are gone; K6: Options too
    { "resize grip", UIx.resizeGrip },
  }
  if not UIx.tabsTemplated then
    for i, t in ipairs(UIx.tabs) do common[#common + 1] = { "view button " .. i, t } end
  end
  -- K8: per view the list panel and the detail panel's controls (the detail panel itself contains them, so it is
  -- checked separately: right of the list panel, filling to the window's edges)
  local views = {
    member = { { "member panel", UIx.memberInset }, { "name", UIx.nameText }, { "spec button", UIx.specButton },
      { "sub-line", UIx.subText }, { "(i) icon", UIx.infoIcon }, { "list header", UIx.sugHeader }, { "suggestion panel", UIx.sugInset },
      { "K4 view switch", UIx.modeToggle } },
    needs = { { "needs panel", UIx.needsInset }, { "craft detail panel", UIx.needDetail } },
  }
  for _, vname in ipairs({ "member", "needs" }) do
    local named = {}
    for _, x in ipairs(common) do named[#named + 1] = x end
    for _, x in ipairs(views[vname]) do named[#named + 1] = x end
    local bad, outside = {}, {}
    for i, a in ipairs(named) do
      local ra = R(a[2])
      if ra.l < 0 or ra.t < 0 or ra.r > W or ra.b > H then outside[#outside + 1] = a[1] .. rstr(ra) end
      for j = i + 1, #named do
        local rb = R(named[j][2])
        if overlap(ra, rb) then bad[#bad + 1] = a[1] .. rstr(ra) .. " x " .. named[j][1] .. rstr(rb) end
      end
    end
    check(#bad == 0, label .. " (" .. vname .. " view): no overlaps among " .. #named .. " controls " .. table.concat(bad, "; "))
    check(#outside == 0, label .. " (" .. vname .. " view): every control inside the window " .. table.concat(outside, "; "))
  end
  -- K8 header: the rank bar centred under the title (27..56), the sync label right of it on the same line
  local pb, dot = R(UIx.profButton), R(UIx.syncDot)
  check(pb.l + pb.r == W and pb.t == 27 and pb.b == 56 and pb.r + 10 <= dot.l and dot.r == W - 20 and dot.b <= 62,
    label .. ": K8 rank bar centred under the title, sync label right of it, both above the panels (62) " .. rstr(pb) .. " " .. rstr(dot))
  -- tabs under the window (PanelTabButtonTemplate path)
  if UIx.tabsTemplated then
    local t1, t2 = R(UIx.tabs[1]), R(UIx.tabs[2])
    check(t1.t == H - 2 and t1.l == 12 and t2.l >= t1.r, label .. ": view tabs hang under the window's bottom edge, side by side")
  end
  -- member view: the list panel keeps its width; the detail panel fills to the right, both down to the bottom bar
  local mi, md, si = R(UIx.memberInset), R(UIx.memberDetail), R(UIx.sugInset)
  check(mi.l == 10 and mi.r - mi.l == 260 and mi.t == 62 and mi.b == H - 40, label .. ": K8 member list panel 260 wide, 62..H-40 " .. rstr(mi))
  check(md.l == 278 and md.r == W - 12 and md.t == 62 and md.b == H - 40, label .. ": K8 member detail panel fills 278..W-12, 62..H-40 " .. rstr(md))
  check(si.l == md.l + 6 and si.r == md.r - 6 and si.t == md.t + 76 and si.b == md.b - 6,
    label .. ": K8 sheet / list area inside the detail panel, below its header (76) " .. rstr(si))
  local ml, sl = R(UIx.memberList), R(UIx.sugList)
  check(ml.b == mi.b - 5 and ml.r == mi.r - 25 and sl.b == si.b - 5 and sl.r == si.r - 29,
    label .. ": both scroll frames fill their panel (25 / 29 px left for the scroll bar, as in 0.5.0) " .. rstr(ml) .. " " .. rstr(sl))
  check(UIx.sugList.content._w == UIx.sugList.viewW and UIx.memberList.content._w == UIx.memberList.viewW and UIx.listW == UIx.sugList.viewW,
    label .. ": scroll content as wide as the view (rows anchored to its right edge)")
  -- texts that grow with the width
  local nt, sb = R(UIx.nameText), R(UIx.specButton)
  local ic, hd0, tg = R(UIx.infoIcon), R(UIx.sugHeader), R(UIx.modeToggle)
  check(nt.r < sb.l and R(UIx.subText).r == W - 12 - 224 and R(UIx.subText).r < sb.l and hd0.r == tg.l - 10 and tg.r == W - 24 and ic.r <= hd0.l
    and UIx.emptyText._w == (W - 302) - 60 and nt.l == md.l + 14 and sb.r == md.r - 12,
    label .. ": header texts span the detail panel, (i) icon left of the list header, K4 switch right of it")
  -- K8 guild-needs view: list panel (search | Filter on top, list, count at the bottom) + the craft detail panel
  local ni, nl, sbx, cnt, nd = R(UIx.needsInset), R(UIx.needsList), R(UIx.searchBox), R(UIx.needsCount), R(UIx.needDetail)
  check(ni.l == 10 and ni.r == 270 and ni.t == 62 and ni.b == H - 40 and nl.r == ni.r - 25 and nl.b == ni.b - 23 and nl.t == ni.t + 34,
    label .. ": K8 guild-needs list panel 10..270, 62..H-40, its list between the search and the count " .. rstr(ni) .. " " .. rstr(nl))
  check(nd.l == 278 and nd.r == W - 12 and nd.t == 62 and nd.b == H - 40 and UIx.needDetail.w == W - 290 and UIx.needDetail.h == H - 102,
    label .. ": K8 craft detail panel fills 278..W-12, 62..H-40 " .. rstr(nd))
  local obx = R(UIx.filterButton)
  check(sbx.l >= ni.l and sbx.t >= ni.t and sbx.b <= nl.t and obx.r == ni.r - 8 and obx.b <= nl.t and sbx.r < obx.l
    and cnt.t >= nl.b and cnt.b <= ni.b and cnt.l == ni.l + 10 and cnt.r == ni.r - 10
    and UIx.needsList.content._w == UIx.needsList.viewW and UIx.needsW == UIx.needsList.viewW,
    label .. ": K8 search | Filter above the list, the count under it, all inside the list panel " .. rstr(sbx) .. " " .. rstr(obx) .. " " .. rstr(cnt))
  -- K5: the member search sits in the member panel above the list
  local ms = R(UIx.memberSearch)
  check(ms.l >= mi.l and ms.r <= mi.r and ms.t >= mi.t and ms.b <= ml.t, label .. ": member search inside the member panel, above the list " .. rstr(ms))
  -- art follows the window
  local art = f.gcaArt
  local cv, hd = R(art.canvas), R(art.page)
  check(cv.l == 2 and cv.t == 21 and cv.r == W - 2 and cv.b == H - 3 and hd.l == 3 and hd.r == W - 3 and hd.t == 21 and hd.b == H - 3,
    label .. ": K6 art canvas (Overview, 2,-21) and the Template2 page (3,-21) fill the window at every size " .. rstr(cv) .. " " .. rstr(hd))
  local g = R(UIx.resizeGrip)
  check(g.r == W - 4 and g.b == H - 4 and g.t >= md.b and g.t >= nd.b, label .. ": grip in the bottom-right corner, below the panels")
end

do
  print("== Window: resizable (plan J2)")
  GCA.db.settings.window = nil
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local before = UIx.errorCount
  local g = UIx.resizeGrip
  check(g and f._resizable == true and UIx.boundsVia == "SetResizeBounds" and f._bounds[1] == 840 and f._bounds[2] == 560
    and f._bounds[3] == 1920 and f._bounds[4] == 1080, "grip created; SetResizable(true); SetResizeBounds(840, 560, screen)")
  check(g._SetNormalTexture[1] == "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" and g._SetPushedTexture[1]:find("Down$")
    and g._level > f.content._level and g._level > f.NineSlice._level, "grip: size-grabber art, above the content and the border")
  check(f._w == 980 and f._h == 640 and UIx.layoutW == 980 and UIx.layoutH == 640, "default 980x640, laid out for it")
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  UIx.sugList:SetData(UIx.SectionRows(longList()))
  UIx.memberList:SetData(UIx.MemberRows(manyMembers()))

  -- drag the corner: mouse down pins the top-left and starts sizing; size changes are throttled; mouse up lays out and saves
  local function drag(w, h, steps)
    g._scripts.OnMouseDown(g, "LeftButton")
    local n0 = UIx.layoutCount
    for i = 1, steps or 1 do f:SetSize(f._w + (w - f._w) * i / (steps or 1), f._h + (h - f._h) * i / (steps or 1)) end
    local during = UIx.layoutCount - n0
    advance(0.06)
    local afterTimer = UIx.layoutCount - n0
    g._scripts.OnMouseUp(g, "LeftButton")
    return during, afterTimer
  end
  local left0, top0 = f:GetLeft(), f:GetTop()
  g._scripts.OnMouseDown(g, "LeftButton")
  check(f.isSizing and f._sizingFrom == "BOTTOMRIGHT" and f._points[1][1] == "TOPLEFT" and f._points[1][4] == left0 and f._points[1][5] == top0,
    "mouse down: StartSizing(\"BOTTOMRIGHT\") with the window pinned by its top-left corner (" .. left0 .. ", " .. top0 .. ")")
  g._scripts.OnMouseUp(g, "LeftButton")
  check(not f.isSizing, "mouse up: sizing stopped")
  local during, afterTimer = drag(1400, 900, 10)
  check(during == 0 and afterTimer == 1, "10 size changes while dragging -> no relayout until the 50 ms timer, then exactly one (" .. during .. "/" .. afterTimer .. ")")

  local vis = {}
  for _, sz in ipairs({ { 840, 560, "minimum" }, { 980, 640, "default" }, { 1600, 1000, "large" } }) do
    drag(sz[1], sz[2], 3)
    check(f._w == sz[1] and f._h == sz[2] and UIx.layoutW == sz[1] and UIx.layoutH == sz[2], sz[3] .. ": " .. sz[1] .. "x" .. sz[2] .. " laid out")
    layoutChecks(UIx, f, sz[3] .. " " .. sz[1] .. "x" .. sz[2])
    UIx.sugList:ScrollTo(0); UIx.memberList:ScrollTo(0)
    vis[#vis + 1] = { UIx.sugList:VisibleRows(), UIx.memberList:VisibleRows(), UIx.sugList.viewH, UIx.memberList.viewH }
  end
  check(vis[1][3] == 366 and vis[1][4] == 419, "K8 minimum: list views 366 px (inside the member detail panel) and 419 px (" .. vis[1][3] .. ", " .. vis[1][4] .. ")")
  check(vis[1][1] < vis[2][1] and vis[2][1] < vis[3][1] and vis[1][2] < vis[2][2] and vis[2][2] < vis[3][2],
    string.format("visible rows grow with the height: suggestions %d/%d/%d, members %d/%d/%d", vis[1][1], vis[2][1], vis[3][1], vis[1][2], vis[2][2], vis[3][2]))
  check(vis[1][2] == 16 and vis[3][2] == 34, "K8: 25 px recipe-list member rows visible (incl. the Online header): 16 at 560 high, 34 at 1000 high (K6: 11/23 with 34 px rows) ("
    .. vis[1][2] .. "/" .. vis[3][2] .. ")")
  -- section rows re-laid out: the worn-item buttons split the wider row
  -- (K4: the header chips are as wide as their text; the header line, the cards' texts and the folded box grow)
  local hdr, card, fold = UIx.sugList.pools.section[1], UIx.sugList.rows[1], UIx.sugList.pools.fold[1]
  local function lineW() return hdr.textW end -- K5: the worn row's name width
  local wide = { lineW(), card.textW, fold.text._SetWidth[1] }
  drag(840, 560)
  local narrow = { lineW(), card.textW, fold.text._SetWidth[1] }
  check(wide[1] - narrow[1] == 1600 - 840 and wide[2] - narrow[2] == 1600 - 840 and wide[3] - narrow[3] == 1600 - 840,
    "K5: worn-row text, card texts and the folded box grow with the width (" .. narrow[1] .. "/" .. narrow[2] .. "/" .. narrow[3]
    .. " -> " .. wide[1] .. "/" .. wide[2] .. "/" .. wide[3] .. ")")
  -- scrolled to the end, then made taller: the offset is clamped to the new range
  UIx.sugList:ScrollTo(1e6)
  local endAt = UIx.sugList.scrolledTo
  drag(840, 1000)
  check(UIx.sugList.scrolledTo == math.max(0, UIx.sugList.contentH - UIx.sugList.viewH) and UIx.sugList.scrolledTo < endAt,
    "taller window: scroll offset clamped to the new range (" .. endAt .. " -> " .. UIx.sugList.scrolledTo .. ")")

  -- saved and restored
  drag(1200, 800)
  local win = GCA.db.settings.window
  check(win and win.w == 1200 and win.h == 800 and win.left == left0 and win.top == top0, "size and position saved after the drag")
  check(f._SetUserPlaced and f._SetUserPlaced[1] == false, "client layout cache not used (SetUserPlaced(false)): SavedVariables own the geometry")
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 900) -- the drag bar moved it
  UIx.dragBar._scripts.OnMouseDown(UIx.dragBar, "LeftButton")
  UIx.dragBar._scripts.OnMouseUp(UIx.dragBar, "LeftButton")
  check(GCA.db.settings.window.left == 100 and GCA.db.settings.window.top == 900 and GCA.db.settings.window.w == 1200, "moving saves the position")
  f:Hide()
  local function reopen()
    GCA.UI.frame = nil
    SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
    return GCA.UI.frame
  end
  f = reopen()
  local p = f._points[1]
  check(f._w == 1200 and f._h == 800 and p[1] == "TOPLEFT" and p[2] == UIParent and p[3] == "BOTTOMLEFT" and p[4] == 100 and p[5] == 900
    and GCA.UI.layoutW == 1200, "reopened (new session): 1200x800 at (100, 900), laid out")
  -- clamped on restore
  GCA.db.settings.window = { w = 5000, h = 3000, left = -500, top = 5000 }
  f:Hide(); f = reopen()
  check(f._w == 1920 and f._h == 1080 and f._points[1][4] == 0 and f._points[1][5] == 1080, "too big / off screen -> screen size at (0, 1080)")
  GCA.db.settings.window = { w = 100, h = 100, left = 1800, top = 50 }
  f:Hide(); f = reopen()
  check(f._w == 840 and f._h == 560 and f._points[1][4] == 1920 - 840 and f._points[1][5] == 560, "too small -> 840x560, pushed back on screen")
  GCA.db.settings.window = "junk"
  f:Hide(); f = reopen()
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "corrupt saved value -> default, centred")
  GCA.db.settings.window = { w = 0 / 0, h = "x", left = 0 / 0, top = 10 }
  f:Hide(); f = reopen()
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "NaN / strings -> default, centred")
  -- right-click on the grip: default size again
  UIx = GCA.UI
  local gg = UIx.resizeGrip
  gg._scripts.OnMouseDown(gg, "LeftButton"); f:SetSize(1500, 900); gg._scripts.OnMouseUp(gg, "LeftButton")
  gg._scripts.OnMouseUp(gg, "RightButton")
  check(f._w == 980 and f._h == 640 and GCA.db.settings.window.w == 980 and UIx.layoutW == 980, "right-click on the grip: back to 980x640, saved")
  -- hiding the window mid-drag (ESC) stops sizing and saves
  gg._scripts.OnMouseDown(gg, "LeftButton"); f:SetSize(1111, 777)
  f:Hide()
  check(not f.isSizing and GCA.db.settings.window.w == 1111 and GCA.db.settings.window.h == 777 and UIx.layoutW == 1111, "hidden while sizing: stopped, laid out, saved")
  advance(1)
  -- tooltips (English, then German below)
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  captureTip(); gg._scripts.OnEnter(gg)
  check(tipText():find("Resize", 1, true) and tipText():find("Right-click: back to the default size", 1, true), "grip tooltip")
  check(UIx.errorCount == before, "no error reported (J2)")
  f:Hide()

  print("== Window: resize on older / missing APIs (J2)")
  local srb = Frame.SetResizeBounds
  Frame.SetResizeBounds = nil
  local minCalls = {}
  Frame.SetMinResize = function(self, w, h) minCalls[#minCalls + 1] = { w, h } end
  f = reopen()
  check(GCA.UI.boundsVia == "SetMinResize" and minCalls[1] and minCalls[1][1] == 840 and minCalls[1][2] == 560, "no SetResizeBounds: SetMinResize(840, 560)")
  f:Hide()
  Frame.SetMinResize = nil
  f = reopen()
  local g3 = GCA.UI.resizeGrip
  check(g3 and GCA.UI.boundsVia == nil, "no bounds API at all: grip still there")
  g3._scripts.OnMouseDown(g3, "LeftButton"); f:SetSize(500, 300); g3._scripts.OnMouseUp(g3, "LeftButton")
  check(f._w == 840 and f._h == 560 and GCA.UI.layoutW == 840 and GCA.db.settings.window.w == 840, "...a drag below the minimum is clamped to 840x560 on release")
  g3._scripts.OnMouseDown(g3, "LeftButton"); f:SetSize(3000, 2000); g3._scripts.OnMouseUp(g3, "LeftButton")
  check(f._w == 1920 and f._h == 1080, "...and above the screen to the screen size")
  f:Hide()
  Frame.SetResizeBounds = srb
  local sr, ss = Frame.SetResizable, Frame.StartSizing
  Frame.SetResizable, Frame.StartSizing = nil, nil
  local errs = GCA.UI.errorCount
  f = reopen()
  check(f._shown and GCA.UI.resizeGrip == nil and GCA.UI.errorCount == errs and GCA.UI.layoutW == f._w, "no SetResizable/StartSizing: no grip, window works, no error")
  f:Hide()
  Frame.SetResizable, Frame.StartSizing = sr, ss
  GCA.db.settings.window = nil

  print("== Window: resize grip in German (J2)")
  ns.locale = "deDE"
  f = reopen()
  local g4 = GCA.UI.resizeGrip
  captureTip(); g4._scripts.OnEnter(g4)
  check(tipText():find("Größe ändern", 1, true) and tipText():find("Rechtsklick", 1, true), "German grip tooltip")
  f:Hide()
  ns.locale = "enUS"
  GCA.UI.frame = nil
  GCA.db.settings.window = nil
end

-- Review H-1: every OnEnter (and OnClick where it only opens/toggles something) of every button, slider, checkbox,
-- popup row, the whisper editor and the minimap button, in English and German. OnEnter handlers go through the
-- error reporter, so an error shows as UI.errorCount / db.lastError rather than a Lua error.
IsShiftKeyDown = function() return false end
HandleModifiedItemClick = function() end
GetNumSubgroupMembers = function() return 0 end
IsInRaid = function() return false end
local function sweep(locale)
  print("== Sweep: every OnEnter / OnClick (" .. locale .. ")")
  ns.locale = locale
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local settings = {}
  for k, v in pairs(GCA.db.settings) do settings[k] = v end
  local printFn = GCA.Print
  GCA.Print = function() end
  local function fill()
    UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE",
      member = { items = {}, time = time(), source = "inspect" }, spec = "COMBAT", specHow = "manual" }
    -- plan I: the rows inside slot sections (headers, grey lines, rings with two worn items, an unloaded trinket)
    local swList = fakeSections({ [5] = { fakeSug(), fakeSug({ future = true, wearAt = 42, levelsToGo = 3 }), fakeSug({ known = false }) },
      [9] = { fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
        cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } }, status = "weapon-enchant",
        sets = { { name = "Set", gained = { { n = 2, stats = { MeleeHit = 1, SpellHit = 1 } } }, lost = { { n = 3, stats = {} } }, value = 1 } } }) } },
      { [5] = 7 })
    UIx.sugList:SetData(UIx.SectionRows(swList))
    -- K4: the character sheet with the same member (its slot buttons, cards and alternatives get swept too)
    UIx.sheetFor, UIx.sheetAuto = nil, true
    UIx:UpdateSheet(UIx.current, swList, "Leatherworking", "")
    -- K2: guild-needs rows (online + the offline group opened) and member-list groups
    local bud = UIx.current
    local off = { key = "Olga Field", online = false, prof = "Leatherworking", level = 30, class = "MAGE", member = { items = {} } }
    UIx.collapsed.online, UIx.collapsed.offline = false, false
    -- K5: craft groups (real Core grouping), all expanded, offline members included
    local budE = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {} },
      suggestions = { fakeSug(), fakeSug({ slot = 11, future = true, wearAt = 42, levelsToGo = 3, known = false,
        cand = { spellID = 3999, itemID = 5, recipe = { skill = 1, src = "trainer", r = {} } } }) } }
    local offE = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {} }, suggestions = { fakeSug() } }
    GCA.needsCache = nil
    local nd = GCA:GuildNeeds({ budE, offE })
    -- K8: slot categories + craft rows on the left, the first craft (with its member rows and reagents) in the detail panel
    UIx.needsCollapsed = {}
    local ndData, _, _, _, ndAll = UIx.NeedsRows(nd, "", true)
    UIx.needsList:SetData(ndData)
    UIx:UpdateCraftDetail(ndAll[1])
    UIx.memberList:SetData(UIx.MemberRows({ { key = "Me Stone", isSelf = true, online = true, level = 36, class = "ROGUE", member = {} },
      off, { key = "Nobody Yet", online = true, level = 20, class = "WARRIOR" } }))
    -- K6: the native dropdowns have no popups: their menu generators run on a recording menu instead
    for _, dd in ipairs({ UIx.specButton.dropdown, UIx.profButton.drop, UIx.filterButton, UIx.memberFilter, UIx.modeToggle }) do
      if dd._gen then menuOf(dd) end
    end
  end
  fill()
  UIx:OpenWhisperEditor()
  local ed = UIx.whisperEditor
  GCA.db.lastError = nil
  local errBefore = UIx.errorCount
  local frames = descendants(f)
  frames[#frames + 1] = ed
  for _, c in ipairs(descendants(ed)) do frames[#frames + 1] = c end
  frames[#frames + 1] = _G.GuildCraftAdvisorMinimapButton
  local nEnter, bad, nSecEnter, gripEnter = 0, {}, 0, false
  local foldEnter, needEnter, groupEnter, dotEnter, infoEnter, searchEnter = false, 0, 0, false, false, false
  local craftEnter = 0
  local sheetSlotEnter, sheetCardEnter, sheetAltEnter, toggleEnter = 0, 0, 0, 0
  for _, fr in ipairs(frames) do
    if fr._scripts and fr._scripts.OnEnter then
      captureTip()
      local ok, err = pcall(fr._scripts.OnEnter, fr)
      nEnter = nEnter + 1
      if fr == UIx.resizeGrip then gripEnter = #tip >= 2 end -- title + text
      -- plan I row kinds: section headers / grey lines (data.rowKind) and their worn-item buttons (.worn set)
      if (fr.data and fr.data.rowKind == "section") or (fr.worn and fr._shown and fr.slot == nil) then nSecEnter = nSecEnter + 1 end -- (K4: not the sheet slots/card)
      if fr.data and fr.data.rowKind == "fold" then foldEnter = ok end
      if fr.data and fr.data.rowKind == "need" and fr._shown then needEnter = needEnter + 1 end
      if ok and fr.data and fr.data.group and fr.data.rows and fr._shown then craftEnter = craftEnter + 1 end
      if fr.data and fr.data.rowKind == "group" and fr._shown then groupEnter = groupEnter + 1 end
      if fr == UIx.syncDot then dotEnter = ok end
      if fr == UIx.infoIcon then infoEnter = ok end
      if fr == UIx.searchBox then searchEnter = ok end
      if ok and fr.slot and fr.badge then sheetSlotEnter = sheetSlotEnter + 1 end
      if ok and fr.isBest ~= nil then sheetCardEnter = sheetCardEnter + 1 end
      if ok and fr._parent == UIx.sheet.centre and fr.tag and fr.data then sheetAltEnter = sheetAltEnter + 1 end
      if ok and fr == UIx.modeToggle then toggleEnter = toggleEnter + 1 end
      if not ok then bad[#bad + 1] = tostring(err) end
    end
  end
  check(gripEnter, locale .. ": the sweep reached the resize grip's tooltip (J2)")
  check(nSecEnter == 2, locale .. ": the sweep reached both worn rows (K5: no separate worn-item buttons any more) (" .. nSecEnter .. ")")
  check(foldEnter and needEnter >= 2 and craftEnter == 2 and groupEnter >= 2 and dotEnter and infoEnter and searchEnter,
    locale .. ": the sweep reached the folded line, 2 craft rows + their member rows, group headers, sync dot, (i) icon and search box ("
    .. needEnter .. "/" .. craftEnter .. "/" .. groupEnter .. ")")
  check(sheetSlotEnter == 17 and sheetCardEnter == 2 and sheetAltEnter == 2 and toggleEnter == 1,
    locale .. ": K4: the sweep reached the 17 sheet slots, both cards, 2 alternatives and the K6 view dropdown ("
    .. sheetSlotEnter .. "/" .. sheetCardEnter .. "/" .. sheetAltEnter .. "/" .. toggleEnter .. ")")
  check(nEnter >= 30 and #bad == 0 and UIx.errorCount == errBefore and GCA.db.lastError == nil,
    locale .. ": " .. nEnter .. " OnEnter handlers ran without an error (" .. table.concat(bad, "; ")
    .. (GCA.db.lastError and (" reported: " .. GCA.db.lastError.where .. " " .. GCA.db.lastError.msg:match("^[^\n]*")) or "") .. ")")
  -- clicks: everything except the editor's buttons (tested separately) and the window's close button
  fill()
  local skip = { [ed.saveBtn] = true, [ed.resetBtn] = true, [ed.closeBtn] = true, [f.CloseButton] = true }
  local nClick, badClick, nWornClick = 0, {}, 0
  frames = descendants(f)
  frames[#frames + 1] = _G.GuildCraftAdvisorMinimapButton
  for _, fr in ipairs(frames) do
    local fn = fr._scripts and fr._scripts.OnClick
    if fn and not skip[fr] then
      captureTip()
      local ok, err = pcall(fn, fr, "LeftButton")
      nClick = nClick + 1
      if fr.data and fr.data.rowKind == "section" and fr._shown then nWornClick = nWornClick + 1 end -- K5: the worn rows
      if not ok then badClick[#badClick + 1] = tostring(err) end
      if not f._shown then f:Show() end
      if UIx.current == nil or UIx.current.key ~= "Bud Stone" then fill() end
    end
  end
  check(nWornClick == 2, locale .. ": OnClick of both worn rows swept (" .. nWornClick .. ")")
  -- J2: every OnMouseDown / OnMouseUp (drag bar, resize grip) with the left button, then the grip's right-click
  local nMouse, badMouse, gripMouse = 0, {}, 0
  for _, fr in ipairs(descendants(f)) do
    for _, ev in ipairs({ "OnMouseDown", "OnMouseUp" }) do
      local fn = fr._scripts and fr._scripts[ev]
      if fn then
        local ok, err = pcall(fn, fr, "LeftButton")
        nMouse = nMouse + 1
        if fr == UIx.resizeGrip then gripMouse = gripMouse + 1 end
        if not ok then badMouse[#badMouse + 1] = tostring(err) end
      end
    end
  end
  local okR, errR = pcall(UIx.resizeGrip._scripts.OnMouseUp, UIx.resizeGrip, "RightButton")
  if not okR then badMouse[#badMouse + 1] = tostring(errR) end
  check(gripMouse == 2 and nMouse >= 4 and #badMouse == 0 and UIx.errorCount == errBefore and not f.isSizing and not f.isMoving,
    locale .. ": " .. nMouse .. " OnMouseDown/Up handlers (incl. the grip's) + grip right-click ran without an error ("
    .. table.concat(badMouse, "; ") .. ")")
  check(nClick >= 25 and #badClick == 0 and UIx.errorCount == errBefore, locale .. ": " .. nClick .. " OnClick handlers ran without an error ("
    .. table.concat(badClick, "; ") .. ")")
  -- restore what the clicks toggled
  for k in pairs(GCA.db.settings) do GCA.db.settings[k] = nil end
  for k, v in pairs(settings) do GCA.db.settings[k] = v end
  GCA.db.crafted, GCA.db.specManual = nil, {}
  UIx.collapsed.online, UIx.collapsed.offline = false, true
  UIx.needsCollapsed, UIx.needSel = {}, nil
  GCA.needsCache = nil
  GCA:SelectProfession("Leatherworking")
  GCA.Print = printFn
  ed:Hide(); advance(0.1)
  f:Hide()
  ns.locale = "enUS"
end
sweep("enUS")
sweep("deDE")

do
  print("== Error reporter wraps tooltips (H-1)")
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  local saved = ns.Locales.enUS.SLIDER_TIP
  ns.Locales.enUS.SLIDER_TIP = "broken 0 % = on purpose"
  local printed = {}
  local printFn = GCA.Print
  GCA.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
  GCA.db.lastError = nil
  local before = UIx.errorCount
  captureTip()
  local ok = pcall(UIx.survival.slider._scripts.OnEnter, UIx.survival.slider)
  check(ok and UIx.errorCount == before + 1 and GCA.db.lastError and GCA.db.lastError.where == "tooltip: slider"
    and table.concat(printed, "\n"):find("tooltip: slider", 1, true), "a broken tooltip text is caught and reported (" .. tostring(GCA.db.lastError and GCA.db.lastError.msg:match("^[^\n]*")) .. ")")
  ns.Locales.enUS.SLIDER_TIP = saved
  GCA.Print = printFn
  GCA.db.lastError = nil
  captureTip(); UIx.survival.slider._scripts.OnEnter(UIx.survival.slider)
  check(tipText():find("0 % = pure damage", 1, true), "slider tooltip shows '0 % =' (escaped %%): " .. (tip[2] or "?"):sub(1, 60))
  UIx.frame:Hide()
end

do
  print("== Whisper editor: ESC (L-1)")
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  -- the game's CloseSpecialWindows: hides every listed frame that is shown
  local function pressEsc()
    local found = false
    for _, name in pairs(UISpecialFrames) do
      local fr = _G[name]
      if fr and fr:IsShown() then fr:Hide(); found = true end
    end
    return found
  end
  local function listed(name) local n = 0 for _, v in ipairs(UISpecialFrames) do if v == name then n = n + 1 end end return n end
  local printed = {}
  local printFn = GCA.Print
  GCA.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
  UIx:OpenWhisperEditor()
  local ed = UIx.whisperEditor
  check(ed._shown and listed("GuildCraftAdvisorFrame") == 0, "editor open: the main window is out of UISpecialFrames")
  ed.craft:SetText("Draft {item}")
  check(pressEsc() and not ed._shown and f._shown, "ESC closes the editor only, the main window stays open")
  check(GCA.db.settings.whisperCraft == nil and UIx.whisperDraft and UIx.whisperDraft.craft == "Draft {item}"
    and table.concat(printed, "\n"):find("draft is kept", 1, true), "unsaved text kept as a draft, chat says so")
  advance(0.1)
  check(listed("GuildCraftAdvisorFrame") == 1, "main window back in UISpecialFrames after the editor closed")
  UIx:OpenWhisperEditor()
  check(ed.craft._text == "Draft {item}" and ed.draftNote._shown, "reopening shows the draft and the 'unsaved draft' note")
  ed.enchant:SetText("Changed too")
  UIx:OpenWhisperEditor() -- already open: must not reload over the typing
  check(ed.enchant._text == "Changed too", "/gca whisper while open keeps the typing")
  ed.closeBtn._scripts.OnClick(ed.closeBtn)
  check(UIx.whisperDraft and UIx.whisperDraft.enchant == "Changed too", "Close keeps the draft as well")
  UIx:OpenWhisperEditor()
  ed.saveBtn._scripts.OnClick(ed.saveBtn)
  check(GCA.db.settings.whisperCraft == "Draft {item}" and GCA.db.settings.whisperEnchant == "Changed too" and UIx.whisperDraft == nil
    and not ed._shown, "Save stores the draft and clears it")
  advance(0.1)
  UIx:OpenWhisperEditor()
  check(not ed.draftNote._shown and ed.craft._text == "Draft {item}", "after Save: no draft note, saved text shown")
  ed.craft:SetText("another edit")
  ed.resetBtn._scripts.OnClick(ed.resetBtn)
  check(UIx.whisperDraft == nil and GCA.db.settings.whisperCraft == nil and ed.craft._text == UIx.DefaultTemplate("craft"), "Reset drops draft and saved text")
  printed = {}
  pressEsc(); advance(0.1)
  check(f._shown and #printed == 0, "ESC on an unchanged editor: closes it, no draft message, window stays")
  check(pressEsc() and not f._shown, "next ESC closes the main window as before")
  GCA.Print = printFn
end

do
  print("== No members: nothing stale (L-4)")
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  UIx.emptyText:SetText("stale empty text")
  UIx.sugHeader:SetText("stale header")
  local orig = GCA.GetMemberList
  GCA.GetMemberList = function() return {} end
  local before = UIx.errorCount
  UIx:Refresh()
  GCA.GetMemberList = orig
  check(UIx.errorCount == before and UIx.nameText._text == "No guild members yet" and UIx.emptyText._text == "" and UIx.sugHeader._text == ""
    and UIx.subText._text == "" and UIx.sourceLine == "" and not UIx.infoIcon._shown, "L-4: name says so; empty text, header, sub-line, source line cleared")
  UIx.frame:Hide()
end

do
  print("== Window: atlases missing (fallbacks)")
  atlasMode = "missing"
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  check(f.gcaArt and not f.gcaArt.painted and f.gcaArt.overview == nil and f.gcaArt.header == nil, "no art drawn without atlases")
  check(f.Bg._shown and f.gcaArt.fill._SetColorTexture[4] < 1, "native Bg kept, translucent dark wash")
  local nIns = 0
  for _, c in ipairs(descendants(f)) do
    if c.NineSlice and c ~= f and c.Bg then nIns = nIns + 1; check(c.Bg._alpha == nil, "L-3: no art -> inset Bg untouched") end
  end
  check(nIns == 2, "L-3/K8: two list insets in the no-art pass (the detail panels have none)")
  check(UIx.optionsPopup == nil and UIx.profPopup == nil and UIx.profButton.art == "plain" and UIx.profButton.drop.arrowKind == "file",
    "K6: no atlases: the rank bar falls back to a plain track, the dropdown arrow to the caret file (no popups: native menus)")
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39 }
  UIx.sugList:SetData({ fakeSug() })
  local b = UIx.sugList.rows[1]
  check(not b.slotFrame and b.qual._shown ~= false and b.qual._SetColorTexture, "row icon: quality square instead of the slot frame")
  f:Hide()
  atlasMode = "ok"
  GCA.UI.frame = nil
end

-- fallback: CreateFrame with the template errors; InsetFrameTemplate also missing
templateMode = "fail"
local origCF = CreateFrame
CreateFrame = function(otype, name, parent, template)
  if template == "InsetFrameTemplate" then error("no InsetFrameTemplate") end
  return origCF(otype, name, parent, template)
end
-- insets fall back to BackdropTemplate frames without NineSlice; patch the count expectation
do
  print("== Window: fallback path")
  atlasMode = "missing" -- K6: the list panels are the atlas; only without it do insets (and here their backdrop fallback) appear
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local f = GCA.UI.frame
  check(f and f._shown and f._backdrop, "fallback window opens with backdrop")
  local ok = pcall(f.CloseButton._scripts.OnClick, f.CloseButton)
  check(ok and not f._shown, "fallback close button hides")
  local bd = 0
  for _, c in ipairs(descendants(f)) do if c._backdrop and c._shown then bd = bd + 1 end end -- (hidden popups don't count)
  check(bd == 2, "K8: two fallback list panels with backdrop (guild needs, members) (" .. bd .. ")")
  local alphas = {}
  for _, c in ipairs(descendants(f)) do if c._backdrop and c._shown and c._SetBackdropColor then alphas[#alphas + 1] = c._SetBackdropColor[4] end end
  check(#alphas == 2 and alphas[1] == 0.6 and alphas[2] == 0.6, "L-3: fallback look unchanged (panel alpha 0.6)")
  atlasMode = "ok"
end
CreateFrame = origCF

-- K0/L2: Offer opens a real whisper to "First Surname" (edit box chat type + tell target), fallback kept
do
  print("== K0/L2: whisper to a name with a space; K0/L3: spec reasons + slash replies localized")
  local box = { text = "" }
  function box:SetChatType(t) self.chatType = t end
  function box:SetTellTarget(n) self.tell = n end
  function box:GetChatType() return self.chatType end
  function box:GetTellTarget() return self.tell end
  function box:UpdateHeader() self.header = true end
  function box:SetText(t) self.text = t end
  function box:GetText() return self.text end
  function box:SetFocus() self.focus = true end
  local opened = {}
  local savedCFU = ChatFrameUtil
  ChatFrameUtil = { OpenChat = function(text) opened[#opened + 1] = text; return box end, GetActiveWindow = function() return box end }
  local savedUI = GCA.UI
  local uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  assert(loadfile(ROOT .. "UI.lua"))("RavenquillExpedition_CraftAdvisor", uiNs)
  local UIw = GCA.UI
  GCA.UI = savedUI
  UIw.OpenWhisper("Dora Field", "Hi Dora, I can craft X")
  check(box.chatType == "WHISPER" and box.tell == "Dora Field" and box.text == "Hi Dora, I can craft X" and box.focus
    and opened[1] == "", "whisper box: WHISPER to 'Dora Field' (full name), text inserted, no '/w' command")
  -- a box that ignores the tell target (another chat addon): falls back to the 0.5.0 '/w' route
  local box2 = { text = "" }
  function box2:SetChatType(t) self.chatType = t end
  function box2:SetTellTarget() end
  function box2:GetChatType() return self.chatType end
  function box2:GetTellTarget() return nil end
  function box2:SetText(t) self.text = t end
  function box2:GetText() return self.text end
  opened = {}
  ChatFrameUtil = { OpenChat = function(text) opened[#opened + 1] = text; box2.text = text; return box2 end, GetActiveWindow = function() return box2 end }
  uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  assert(loadfile(ROOT .. "UI.lua"))("RavenquillExpedition_CraftAdvisor", uiNs)
  UIw = GCA.UI
  GCA.UI = savedUI
  UIw.OpenWhisper("Dora Field", "Hello")
  advance(1)
  check(opened[1] == "" and opened[2] == "/w Dora Field Hello", "unverified target: falls back to the '/w' route (" .. tostring(opened[2]) .. ")")
  -- no ChatFrameUtil at all: no error
  ChatFrameUtil = nil
  uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  assert(loadfile(ROOT .. "UI.lua"))("RavenquillExpedition_CraftAdvisor", uiNs)
  UIw = GCA.UI
  GCA.UI = savedUI
  check(pcall(UIw.OpenWhisper, "Dora Field", "Hello"), "no chat API: no error")
  ChatFrameUtil = savedCFU

  -- K0/L3: spec reasons in the client's language
  ns.locale = "deDE"
  check(UIw.SpecWhyText("class unknown") == "Klasse unbekannt" and UIw.SpecWhyText("tie") == "zwei Bäume gleich stark"
    and UIw.SpecWhyText("no C_Traits") == "Talente nicht lesbar", "spec reasons in German")
  ns.locale = "enUS"
  check(UIw.SpecWhyText("talents not read yet") == "talents not read yet" and UIw.SpecWhyText("config has no tree") == "talents not readable",
    "spec reasons in English; technical ones -> 'talents not readable'")
  -- slash replies through the locale
  local printed = {}
  local savedPrint = print
  print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
  ns.locale = "deDE"
  SlashCmdList.GUILDCRAFTADVISOR("verbose"); SlashCmdList.GUILDCRAFTADVISOR("verbose")
  SlashCmdList.GUILDCRAFTADVISOR("spec inspect off")
  SlashCmdList.GUILDCRAFTADVISOR("minimap reset")
  ns.locale = "enUS"
  print = savedPrint
  local all = table.concat(printed, "\n")
  check(all:find("Ausführliche Meldungen an", 1, true) and all:find("Ausführliche Meldungen aus", 1, true)
    and all:find("Talente werden ignoriert", 1, true) and all:find("Minimap-Knopf in die größte freie Lücke verschoben", 1, true)
    and not all:find("Verbose", 1, true), "slash replies in German: " .. all:gsub("\n", " | "))
end

-- Section K (K1 polish, K2 guild needs + member list): new checks
do
  print("== K2: Core GuildNeeds (order, grouping, cache)")
  -- this section runs on the template window with your own profession (earlier blocks leave the fallback
  -- window / a browse state behind)
  local savedTM, savedBrowse = templateMode, GCA.IsBrowse
  templateMode = "ok"
  GCA.IsBrowse = function() return false end
  local UIx = GCA.UI
  local bud = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {} } }
  local olga = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {} } }
  local me = { key = "Me Stone", isSelf = true, online = true, class = "ROGUE", level = 36, prof = "Leatherworking", member = { items = {} } }
  local nobody = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20 }
  local b1 = fakeSug()
  local bx = fakeSug({ extra = true, info = { name = "Extra Vest", quality = 2, icon = "x", minLevel = 20 }, sortPct = 99 })
  local b2 = fakeSug({ slot = 12, future = true, wearAt = 42, levelsToGo = 3, sortPct = 50,
    info = { name = "Craft Ring", quality = 3, icon = "x", minLevel = 42, link = "|Hitem:5|h[Craft Ring]|h" } })
  local o1 = fakeSug({ slot = 9, sortPct = 30, info = { name = "Olga Bracers", quality = 2, icon = "x", minLevel = 20 } })
  local m1 = fakeSug({ sortPct = 80 })
  bud.suggestions = fakeSections({ [5] = { b1, bx }, [11] = { b2 } })
  olga.suggestions = fakeSections({ [9] = { o1 } })
  me.suggestions = fakeSections({ [5] = { m1 } })
  local entries = { me, bud, olga, nobody }
  GCA.needsCache = nil
  local n0 = GCA.needsBuilds or 0
  local needs = GCA:GuildNeeds(entries)
  local function names(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.member.key .. ":" .. r.sug.info.name end return table.concat(t, ",") end
  check(names(needs.online) == "Bud Stone:Hillman's Leather Vest,Bud Stone:Craft Ring" and names(needs.offline) == "Olga Field:Olga Bracers",
    "GuildNeeds: online rows by SuggestionOrder (wearable 12% before the look-ahead 50%), offline apart; no extras, not you, nothing without gear: "
    .. names(needs.online) .. " | " .. names(needs.offline))
  check(needs.online[1].rowKind == "need" and needs.online[1].sug == b1 and needs.online[1].member == bud, "rows carry the suggestion and the member entry")
  local b3 = fakeSug({ sortPct = 40, info = { name = "Big Vest", quality = 2, icon = "x", minLevel = 20 } })
  local cara = { key = "Cara Field", online = true, class = "DRUID", level = 30, prof = "Leatherworking", member = { items = {} },
    suggestions = fakeSections({ [5] = { b3 } }) }
  GCA.needsCache = nil
  local n2 = GCA:GuildNeeds({ bud, cara })
  check(names(n2.online) == "Cara Field:Big Vest,Bud Stone:Hillman's Leather Vest,Bud Stone:Craft Ring", "biggest gain first across members: " .. names(n2.online))
  -- cache: same entries -> same result, no rebuild; a changed online flag or InvalidateScores -> rebuilt
  local nb = GCA.needsBuilds
  check(GCA:GuildNeeds({ bud, cara }) == n2 and GCA.needsBuilds == nb, "cached: same entries give the same rows without a rebuild")
  local cara2 = {}
  for k, v in pairs(cara) do cara2[k] = v end
  cara2.online = false
  local n3 = GCA:GuildNeeds({ bud, cara2 })
  check(n3 ~= n2 and GCA.needsBuilds == nb + 1 and names(n3.offline) == "Cara Field:Big Vest", "an online change rebuilds (Cara now offline)")
  GCA:InvalidateScores()
  local n4 = GCA:GuildNeeds({ bud, cara2 })
  check(n4 ~= n3 and GCA.needsBuilds == nb + 2, "InvalidateScores (new sugCache) rebuilds")
  advance(1)

  print("== K5: GuildNeedsByCraft + NeedsRows (grouped by craft, search, offline box)")
  -- crafts with their own recipe IDs (fakeSug's default spellID is shared)
  local function sg(id, over)
    over = over or {}
    over.cand = { spellID = id, itemID = id, recipe = { skill = 100, src = "trainer", r = {} } }
    return fakeSug(over)
  end
  local function vinfo() return { name = "Vest", quality = 2, icon = "x", minLevel = 20, link = "|Hitem:9001|h[Vest]|h" } end
  K5 = {}
  K5.vestA = sg(9001, { sortPct = 12, pct = 0.12, info = vinfo() })
  K5.vestB = sg(9001, { sortPct = 38, pct = 0.38, info = vinfo(), equipped = { name = "Old Vest", quality = 2 } })
  K5.vestO = sg(9001, { sortPct = 60, pct = 0.6, info = vinfo() })
  K5.belt = sg(9002, { slot = 6, sortPct = 20, pct = 0.2, info = { name = "Belt", quality = 2, icon = "x", minLevel = 20, link = "|Hitem:9002|h[Belt]|h" } })
  K5.ringF = sg(9003, { slot = 11, future = true, wearAt = 42, levelsToGo = 3, sortPct = 90, pct = 0.9,
    info = { name = "Future Ring", quality = 3, icon = "x", minLevel = 42, link = "|Hitem:9003|h[Future Ring]|h" } })
  K5.ringF2 = sg(9003, { slot = 12, future = true, wearAt = 42, levelsToGo = 3, sortPct = 80, pct = 0.8, extra = nil,
    info = { name = "Future Ring", quality = 3, icon = "x", minLevel = 42 } })
  K5.mine = sg(9004, { sortPct = 99, pct = 0.99, info = { name = "My Gloves", quality = 2, icon = "x", minLevel = 20 } })
  K5.bud = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {}, time = time(), source = "inspect" },
    suggestions = fakeSections({ [5] = { K5.vestA }, [6] = { K5.belt }, [11] = { K5.ringF, K5.ringF2 } }), best = K5.belt, knownCount = 3, state = "ok" }
  K5.cara = { key = "Cara Field", online = true, class = "DRUID", level = 30, prof = "Leatherworking", member = { items = {}, time = time(), source = "inspect" },
    suggestions = fakeSections({ [5] = { K5.vestB } }), best = K5.vestB, knownCount = 1, state = "ok" }
  K5.olga = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {}, time = time(), source = "relay" },
    suggestions = fakeSections({ [5] = { K5.vestO } }), best = K5.vestO, knownCount = 1, state = "ok" }
  K5.me = { key = "Me Stone", isSelf = true, online = true, class = "ROGUE", level = 36, prof = "Leatherworking", member = { items = {} },
    suggestions = fakeSections({ [10] = { K5.mine } }), best = K5.mine, knownCount = 1, state = "ok" }
  K5.nobody = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20, prof = "Leatherworking" }
  K5.list = { K5.me, K5.bud, K5.cara, K5.olga, K5.nobody }
  GCA.needsCache = nil
  local nb0 = GCA.needsBuilds or 0
  local crafts, nd = GCA:GuildNeedsByCraft(K5.list)
  local function gnames(gs) local t = {} for i, g in ipairs(gs) do t[i] = g.sug.info.name .. "(" .. #g.rows .. ")" end return table.concat(t, ",") end
  local function rnames(g) local t = {} for i, r in ipairs(g.rows) do t[i] = r.member.key end return table.concat(t, ",") end
  check(crafts == nd.crafts and gnames(crafts) == "Vest(2),Belt(1),Future Ring(1)" and crafts[1].rowKind == "craft",
    "K5: one group per craft, online members only by default, best gain first, the look-ahead-only craft last (90% but too high level): " .. gnames(crafts))
  check(rnames(crafts[1]) == "Cara Field,Bud Stone" and crafts[1].best.sug == K5.vestB and crafts[1].sug == K5.vestB and not crafts[1].future,
    "K5: a craft's members best first (Cara +38% before Bud +12%); its best row / suggestion = Cara's")
  check(#crafts[3].rows == 1 and crafts[3].rows[1].sug == K5.ringF and crafts[3].future, "K5: one row per member and craft (the better ring of Bud's two); look-ahead group flagged future")
  local all = GCA:GuildNeedsByCraft(K5.list, true)
  check(all == nd.craftsAll and gnames(all) == "Vest(3),Belt(1),Future Ring(1)" and rnames(all[1]) == "Olga Field,Cara Field,Bud Stone",
    "K5: with offline members: Olga (+60%) leads the vest group: " .. rnames(all[1]))
  check(not gnames(all):find("My Gloves", 1, true), "K5: you get no guild-needs group (as K2)")
  local again = GCA:GuildNeedsByCraft(K5.list)
  check(again == crafts and GCA.needsBuilds == nb0 + 1, "K5: groups cached with the rows (no rebuild for the same entries)")
  -- K8: per slot category a header (order of its best craft), its crafts under it; collapsed categories keep counting
  UIx.needsCollapsed = {}
  local function kinds(d) local t = {} for i, e in ipairs(d) do t[i] = e.rowKind == "cat" and ("#" .. e.cat) or e.group.sug.info.name end return table.concat(t, ",") end
  local data, nc, nm, offN, allE = UIx.NeedsRows(nd, "", false)
  check(kinds(data) == "#5,Vest,#6,Belt,#11,Future Ring" and data[2].group == crafts[1] and #data[2].rows == 2 and data[2].cat == 5
    and nc == 3 and nm == 2 and offN == 1 and #allE == 3 and data[1].n == 1,
    "K8: NeedsRows: slot categories (Chest, Waist, Rings) each with its crafts, 2 members, 1 offline member with upgrades: " .. kinds(data))
  UIx.needsCollapsed[5] = true
  data, nc, _, _, allE = UIx.NeedsRows(nd, "", false)
  check(kinds(data) == "#5,#6,Belt,#11,Future Ring" and nc == 3 and #allE == 3 and allE[1].group == crafts[1],
    "K8: a collapsed category hides its crafts (still counted, still selectable): " .. kinds(data))
  UIx.needsCollapsed = {}
  data, nc, nm = UIx.NeedsRows(nd, "", true)
  check(#data[2].rows == 3 and nm == 3, "K5: offline box on: Olga's row joins the vest group (3 members)")
  data, nc, nm = UIx.NeedsRows(nd, "  BELT ", false)
  check(kinds(data) == "#6,Belt" and data[2].group == crafts[2] and nc == 1 and nm == 1, "search by item name (case-insensitive, trimmed): the whole craft")
  data, nc, nm = UIx.NeedsRows(nd, "cara", false)
  check(kinds(data) == "#5,Vest" and #data[2].rows == 1 and data[2].rows[1].member.key == "Cara Field" and nm == 1, "search by member name: only that member's rows")
  check(#UIx.NeedsRows(nd, "olga", false) == 0 and #UIx.NeedsRows(nd, "olga", true) == 2, "an offline member is found only with the offline box")
  check(#UIx.NeedsRows(nd, "zzz", false) == 0 and #UIx.NeedsRows(nd, "50%", false) == 0, "no match: nothing; a '%' is plain text")

  print("== K1: TagLine, pair slots, gain text")
  check(plain(UIx.TagLine({ { "a", "|cffff0000" }, { "b" }, { "c", "|cff00ff00" }, { "d", "|cff0000ff" } })) == "a  ·  b  ·  c  ·  d"
    and select(2, UIx.TagLine({ { "a", "|cffff0000" }, { "b" }, { "c", "|cff00ff00" }, { "d", "|cff0000ff" } }):gsub("|c", "")) == 2,
    "TagLine: at most two coloured tags")
  check(UIx.PairSlotName(11) == "Ring 1" and UIx.PairSlotName(14) == "Trinket 2" and UIx.PairSlotName(5) == nil
    and UIx.ShortSlotName(5) == "Chest", "pair slots get 'Ring 1' / 'Trinket 2', others the slot name")
  check(plain(UIx.RowGainText(fakeSug())) == "+12 pts" and not UIx.RowGainText(fakeSug()):find("|cff33ff33", 1, true),
    "row gain: '+12 pts' (user 2026-11-14: no %), not in the big green")
  check(UIx.GainNum(12.4) == "+12" and UIx.GainNum(9.94) == "+9.9" and UIx.GainNum(-12.6) == "-13" and UIx.GainNum(0.05) == "+0.1",
    "gain number: one decimal below 10, whole numbers from 10 on")
  local eb, es = UIx.CardGain(fakeSug({ status = "empty-slot" }))
  check(eb == "+12 pts" and es == "(empty slot)" and UIx.ChipGain(fakeSug({ points = 7 })) == "+7.0" and UIx.Pips == nil,
    "user 2026-11-15: no pips; card '+12 pts' over '(empty slot)', Gildenbedarf '+7.0'")

  print("== K5: window opens on guild needs (grouped by craft); offline box; expand; click-through")
  ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
  local selected = {}
  PanelTemplates_SelectTab = function(t) selected[t] = true end
  PanelTemplates_DeselectTab = function(t) selected[t] = false end
  local origML = GCA.GetMemberList
  local list = K5.list
  GCA.GetMemberList = function() return list end
  GCA.needsCache = nil
  GCA.db.settings.needsOffline = nil
  GCA.UI.frame = nil
  UIx.selected, UIx.autoKey = nil, nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  local f = UIx.frame
  local before = UIx.errorCount
  check(UIx.view == "needs" and UIx.needsView._shown and not UIx.memberView._shown, "opens on guild needs (member view hidden)")
  check(UIx.tabsTemplated and #UIx.tabs == 2 and UIx.tabs[1]._text == "Guild needs" and UIx.tabs[2]._text == "By member"
    and selected[UIx.tabs[1]] == true and selected[UIx.tabs[2]] == false, "two PanelTabButtonTemplate tabs, 'Guild needs' selected")
  check(UIx.inspectButton == nil and UIx.scanButton == nil and UIx.optionsButton == nil and UIx.survival._points[1][1] == "BOTTOMLEFT",
    "K5: no 'Inspect target' / 'Scan group' buttons; K6: no Options button, the slider in the bottom-left corner")
  -- K8: the recipe list on the left (slot categories, one plain text row per craft), the selected craft on the right
  local nl, nd = UIx.needsList, UIx.needDetail
  local function nkinds() local t = {} for i, e in ipairs(nl.data) do t[i] = e.rowKind == "cat" and ("#" .. e.cat) or e.group.sug.info.name end return table.concat(t, ",") end
  check(nkinds() == "#5,Vest,#6,Belt,#11,Future Ring", "K8: slot categories with their crafts: " .. nkinds())
  local r1, r3 = nl.rows[1], nl.rows[3]
  check(plain(r1.label._text) == "Vest" and not r1.label._text:find("|c", 1, true) and r1.count._text == " [2]" and r1.count._points[1][2] == r1.label
    and r1.gain._text == "+38" and r1.icon == nil and r1.caret == nil and r1.members == nil and r1._h == 25 and r1.label._points[1][4] == 22,
    "K8 craft row = a recipe row: plain white name, its count ' [2]' right after it, best gain right, no icon / caret / member run, 25 px: " .. plain(r1.label._text))
  check(r1.hl._atlas == "Professions_Recipe_Hover" and r1.hl._alpha == 0.5 and r1.hl._h == 21 and r1.hl._points[1][5] == -1
    and r1.sel._atlas == "Professions_Recipe_Active" and r1.sel._h == 19 and r1.sel._shown and not nl.rows[2].sel._shown,
    "K8 row art from the probe: hover Professions_Recipe_Hover (21 px, alpha 0.5, y -1), the selected craft Professions_Recipe_Active (19 px)")
  check(plain(r3.label._text) == "Future Ring" and r3.dimmed and r3.label._alpha == 0.55 and r3.gain._text == "+90",
    "K5: the look-ahead-only craft last and dimmed")
  local cp = nl.pools.cat
  check(cp and cp[1].text._text == "Chest" and cp[2].text._text == "Waist" and cp[3].text._text == "Rings" and cp[1]._h == 25
    and cp[1].bg._atlas == "common-button-list-collapseExpand" and cp[1].hl._atlas == "common-button-list-collapseExpand"
    and cp[1].hl._SetBlendMode[1] == "ADD" and cp[1].hl._alpha == 0.4 and cp[1].text._points[1][1] == "LEFT" and cp[1].text._points[1][4] == 8
    and cp[1].CollapseButton._w == 20 and cp[1].CollapseButton._points[1][1] == "RIGHT" and cp[1].CollapseButton._points[1][4] == -6
    and cp[1].CollapseButton.text._text == "–" and UIx.collapseIconKind == "text" and cp[1].native == nil,
    "K8 category header replicated from the probe: collapseExpand art + ADD hover 0.4, gold text at 8, 20 px CollapseButton at -6 ('–', no icon atlas in this mock)")
  local fm = menuOf(UIx.filterButton)
  check(plain(UIx.needsCount._text) == "3 crafts are worth it for 2 members" and plain(fm[5].text) == "Include offline members (1)" and not fm[5]:on(),
    "K5 count line; K6: Filter menu entry 'Include offline members (1)', off by default: " .. plain(UIx.needsCount._text))
  -- the detail panel: the best craft selected
  local s1, s2 = nd.members.rows[1], nd.members.rows[2]
  check(UIx.needSel == "i9001" and nd.entry and nd.entry.group == K5.crafts1 or (nd.entry and nd.entry.group.key == "i9001"),
    "K8: the best craft is selected and shown in the detail panel")
  check(nd.name._text == "Vest" and plain(nd.desc._text) == "Chest" and nd.forTitle._text == "Would be an upgrade for 2 members:"
    and nd.iconBtn.icon._tex == "x" and nd.iconBtn.iconShape and nd.name._shown and not nd.srcTitle._shown and not nd.reagTitle._shown,
    "K8 detail: icon, name, slot line, 'Would be an upgrade for 2 members:' (known recipe: no sources; no reagents in this fake)")
  check(plain(s1.name._text) == "Cara Field" and plain(s1.state._text) == "Old Vest" and plain(s2.state._text) == "Slot empty" and s1.wornBtn ~= nil
    and s1.state._points[1][1] == "LEFT" and s1.state._points[1][2] == s1.wornBtn and s1.wornBtn._points[1][4] == 8 + UIx.NEED_MEMBER_W + 8
    and s1.offer._shown and not s1.offer.isIcon and s1.offer._text == "Offer" and s1.offer._w == 80 and s1.crafted._shown
    and s1.crafted.template == "MinimalCheckboxTemplate" and plain(s1.gain._text) == "+38" and s1.chip == nil and s1._shown and s2._shown,
    "K10 / user 2026-11-15: member row on one line: member column | worn icon + its name beside it | gain, 'Offer', box: " .. plain(s1.state._text))
  check(nd.members.viewH == 2 * 42 and UIx.detailListW == nd.w - 44 and s1.stateW >= 40,
    "K10: the member list is as tall as its rows (2 x 42), as wide as the detail panel")
  -- offline members: on (saved), Olga joins the vest craft; off again
  fm[5]:click()
  r1 = nl.rows[1]
  check(GCA.db.settings.needsOffline == true and r1.count._text == " [3]" and nd.members.rows[1].data.member.key == "Olga Field"
    and nd.members.rows[1].name._alpha == 1 and nd.members.rows[1].name._text:find("StatusIcon-Offline", 1, true)
    and not nd.members.rows[1].name._text:find("|cff7f7f7f", 1, true) and not nd.members.rows[1].offer._shown and menuOf(UIx.filterButton)[5]:on()
    and plain(UIx.needsCount._text) == "3 crafts are worth it for 3 members", "K6/K8: offline members on: saved, Olga (offline dot + softened class colour, no Offer) leads the vest craft")
  check(UIx.filterButton.resetButton and UIx.filterButton.resetButton._shown and UIx.filterButton.resetButton.icon._atlas == "auctionhouse-ui-filter-redx"
    and UIx.memberFilter.resetButton._shown, "K8: a filter off its default -> the red reset badge on both Filter buttons")
  menuOf(UIx.memberFilter)[5]:click()
  check(GCA.db.settings.needsOffline == false and nl.rows[1].count._text == " [2]" and not UIx.filterButton.resetButton._shown,
    "K6: the member list's Filter turns it off again (one setting); the badge goes")
  GCA.db.settings.showUnlearned = true; UIx:RefreshFilters()
  check(UIx.filterButton.resetButton._shown, "K8: badge for 'Show missing recipes' too")
  UIx.filterButton.resetButton._scripts.OnClick(UIx.filterButton.resetButton)
  check(GCA.db.settings.showUnlearned == false and GCA.db.settings.lookahead == true and not UIx.filterButton.resetButton._shown,
    "K8: the badge resets the list filters to their defaults")
  -- select another craft
  nl.rows[2]._scripts.OnClick(nl.rows[2])
  check(UIx.needSel == "i9002" and nd.name._text == "Belt" and nl.rows[2].sel._shown and not nl.rows[1].sel._shown and #nd.members.data == 1,
    "K8: a click on a craft shows it in the detail panel (selection moves)")
  nl.rows[1]._scripts.OnClick(nl.rows[1])
  s1, s2 = nd.members.rows[1], nd.members.rows[2]
  captureTip(); s1._scripts.OnEnter(s1)
  check(plainTip(), "K17: member row under a craft: the craft's plain item tooltip: " .. tipText() .. " / " .. table.concat(hyper, ","))
  captureTip(); nl.rows[1]._scripts.OnEnter(nl.rows[1])
  check(plainTip(), "K17: craft row tooltip = the plain item tooltip (no member list / hints): " .. tipText() .. " / " .. table.concat(hyper, ","))
  s1.crafted:SetChecked(true); s1.crafted._scripts.OnClick(s1.crafted)
  check(GCA:CraftedMark("Cara Field", "Leatherworking", 9001) ~= nil, "crafted box on a member row marks it for that member")
  GCA:SetCrafted("Cara Field", "Leatherworking", K5.vestB, false)
  -- shift-click links (craft and member rows), plain click on a member opens them
  local linked
  HandleModifiedItemClick = function(l) linked = l end
  IsShiftKeyDown = function() return true end
  nl.rows[1]._scripts.OnClick(nl.rows[1])
  check(linked == "|Hitem:9001|h[Vest]|h" and UIx.needSel == "i9001", "shift-click on a craft row links the item (selection unchanged)")
  linked = nil
  nd.members.rows[2]._scripts.OnClick(nd.members.rows[2])
  IsShiftKeyDown = function() return false end
  check(linked == "|Hitem:9001|h[Vest]|h" and UIx.view == "needs", "shift-click on a member row links, stays on guild needs")
  nd.members.rows[2]._scripts.OnClick(nd.members.rows[2])
  check(UIx.view == "member" and UIx.selected == "Bud Stone" and UIx.autoKey == nil and UIx.memberView._shown and selected[UIx.tabs[2]] == true
    and UIx.current == K5.bud, "click on a member opens Bud in 'By member' (tab follows)")
  check(UIx.MemberMode() == "sheet" and UIx.sheet._shown and UIx.sheetSlot == 5 and UIx.sheet.centre.featured == K5.vestA,
    "sheet: that slot selected, that craft compared (" .. tostring(UIx.sheetSlot) .. ")")
  check(UIx.sugList.minimalBar == nil or not UIx.sugList.minimalBar._shown,
    "K12: in the sheet view the hidden list's scroll bar is hidden too")
  GCA.db.settings.memberView = "list"
  UIx:SetView("needs")
  UIx.needSel = "i9003"
  UIx:RefreshNeeds()
  local ringRow = nd.members.rows[1]
  check(ringRow and ringRow.data.sug == K5.ringF and ringRow.chip == nil and plain(ringRow.name._text) == "Bud Stone" and plain(ringRow.state._text) == "Slot empty (Ring 1)  from level 42 · 3 to go"
    and ringRow.state._text:find("|cfff0b44c", 1, true) and ringRow.dimmed and plain(nd.desc._text) == "Rings  ·  from level 42 · 3 to go",
    "K10: a look-ahead member row: 'Slot empty (Ring 1)' + the orange level tag beside the icon, dimmed; the detail line names the level: " .. plain(ringRow.state._text))
  ringRow._scripts.OnClick(ringRow)
  local secY = UIx.sugList:FindY(function(d) return d.rowKind == "section" and d.sec.key == 11 end)
  check(secY and secY > 0 and UIx.sugList.scrolledTo == math.min(secY, math.max(0, UIx.sugList.contentH - UIx.sugList.viewH)),
    "list: ...scrolled to the rings section (" .. tostring(secY) .. ")")
  GCA.db.settings.memberView = "sheet"
  UIx:SetView("needs")
  -- K8: collapsing a category hides its crafts, the selection stays
  UIx.needSel = "i9001"; UIx:RefreshNeeds()
  cp[1]._scripts.OnClick(cp[1])
  check(UIx.needsCollapsed[5] and nkinds() == "#5,#6,Belt,#11,Future Ring" and cp[1].CollapseButton.text._text == "+" and UIx.needSel == "i9001"
    and nd.name._text == "Vest", "K8: a click on 'Chest' collapses it ('+'), the selected craft stays in the detail panel")
  cp[1].CollapseButton._scripts.OnClick(cp[1].CollapseButton)
  check(not UIx.needsCollapsed[5] and nkinds() == "#5,Vest,#6,Belt,#11,Future Ring", "K8: the collapse button opens it again")
  -- K8: reagents (have/need in the reagent slot frame) and sources of a recipe you don't know
  local rsug = fakeSug({ known = false, cand = { spellID = 9100, itemID = 9100, recipe = { skill = 100, src = "trainer", r = { { 2318, 5 }, { 2320, 2 }, { 4231, 1 } } } } })
  local rentry = { group = { key = "i9100", sug = rsug, best = { member = K5.bud, sug = rsug }, rows = { { rowKind = "need", member = K5.bud, sug = rsug } } },
    rows = { { rowKind = "need", member = K5.bud, sug = rsug } }, cat = 5 }
  UIx:UpdateCraftDetail(rentry)
  local rg = nd.reag
  check(nd.reagTitle._shown and nd.reagTitle._text == "Reagents:" and rg[1]._shown and rg[3]._shown and plain(rg[1].text._text):find("^0/5 ") and rg[1].count == nil
    and rg[1].iconBorder._atlas == "Professions-Slot-Frame" and rg[1].qual._atlas == "Professions-Slot-bg" and not rg[1].enough
    and rg[1]._points[1][4] == 16 and rg[2]._points[1][4] == 16 and rg[2]._points[1][5] - rg[1]._points[1][5] == -UIx.REAGENT_STEP
    and rg[3]._points[1][5] < rg[2]._points[1][5],
    "K8 / user 2026-11-15: reagents as in the crafting window: one column, '0/5 Name' beside the icon: " .. plain(rg[1].text._text))
  check(nd.srcTitle._shown and nd.srcTitle._text == "Where to get it:" and plain(nd.src[1]._text) == "Trainer (skill 100)" and nd.src[1]._shown and not nd.src[2]._shown
    and plain(nd.desc._text) == "Chest  ·  Not learned" and nd.srcBox._scripts.OnClick,
    "K8 sources of a missing recipe under the reagents (right-click: K7 menu): " .. plain(nd.src[1]._text))
  local rTop = -nd.reagTitle._points[1][5]
  check(rTop == 92 + 42 + 10 and -nd.srcTitle._points[1][5] == rTop + 18 + 2 * 38, "K8: members, then reagents, then sources stacked")
  UIx:RefreshNeeds()
  -- search box (K6: the client's SearchBoxTemplate; its own instructions / clear button, our OnTextChanged hook)
  local sb = UIx.searchBox
  check(sb.native and sb._template == "SearchBoxTemplate" and sb.placeholder == sb.Instructions and sb.Instructions._text == "Search"
    and sb._w == UIx.SEARCH_W and sb._parent == UIx.needsInset, "K6/K8: guild-needs search = SearchBoxTemplate on top of the list panel")
  sb:SetText("belt"); sb._scripts.OnTextChanged(sb)
  check(nkinds() == "#6,Belt" and plain(UIx.needsCount._text) == "1 craft is worth it for 1 member" and nd.name._text == "Belt",
    "search 'belt': one craft, singular count, the detail follows (the selected vest is not listed)")
  sb:SetText("zzz"); sb._scripts.OnTextChanged(sb)
  check(#nl.data == 0 and UIx.needsEmpty._text == 'No upgrade matches "zzz".' and not nd.name._shown and not nd.members._shown,
    "no match: the detail panel's empty text says so")
  sb:SetText(""); sb._scripts.OnTextChanged(sb)
  check(sb._text == "" and UIx.needsEmpty._text == "", "clearing the search resets it")
  -- only offline members need something: the empty text points at the box
  local savedKC = GCA.knownCount
  GCA.knownCount = 5
  list = { K5.me, K5.olga }
  GCA.needsCache = nil
  UIx:Refresh()
  check(UIx.needsEmpty._text:find("1 offline member(s) do", 1, true), "K5: nothing online, an offline member needs something: the empty text says so")
  list = K5.list
  GCA.knownCount = savedKC
  GCA.needsCache = nil
  UIx:OpenMember("Olga Field", 5)
  check(UIx.collapsed.offline == false and UIx.selected == "Olga Field" and UIx.current == K5.olga, "opening an offline member expands the offline group")
  UIx.needsCollapsed[6] = true
  f:Hide(); SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  check(UIx.view == "needs" and UIx.needsView._shown and next(UIx.needsCollapsed) == nil and UIx.needSel == "i9001" and UIx.collapsed.offline == true
    and UIx.collapsed.online == false, "reopened: guild needs, every category open, the best craft selected, offline group collapsed (not saved)")
  UIx.tabs[2]._scripts.OnClick(UIx.tabs[2])
  check(UIx.view == "member" and UIx.memberView._shown, "tab 2 switches to the member view")
  UIx.tabs[1]._scripts.OnClick(UIx.tabs[1])
  check(UIx.view == "needs", "tab 1 back to guild needs")
  local nbB = GCA.needsBuilds
  f:SetSize(1300, 900); advance(0.1); UIx:Layout(); UIx:Refresh(); UIx:Refresh()
  sb:SetText("vest"); sb._scripts.OnTextChanged(sb); sb:SetText(""); sb._scripts.OnTextChanged(sb)
  check(GCA.needsBuilds == nbB and UIx.layoutW == 1300 and nd.w == 1300 - 290, "resizing, refreshing and searching reuse the cached groups (no rebuild); the detail panel follows")
  f:SetSize(980, 640); advance(0.1)

  print("== K5/K6: member list (search, Online / Offline groups = native category headers, native rows)")
  UIx:SetView("member")
  UIx.collapsed.online, UIx.collapsed.offline = false, true
  UIx.selected = "Bud Stone"
  UIx:Refresh()
  local ml = UIx.memberList
  local kinds = {}
  for i, d in ipairs(ml.data) do kinds[i] = d.rowKind and (d.group .. "(" .. d.count .. ")") or d.key end
  check(table.concat(kinds, ",") == "online(3),Me Stone,Bud Stone,Cara Field,offline(1)",
    "K5: 'Online 3' (you + recorded online), 'Offline 1' collapsed, nobody without gear: " .. table.concat(kinds, ","))
  check(ml.rowY[1][2] == 27 and ml.rowY[2][2] == 25 and ml.rows[1]._SetHeight[1] == 25, "K8: recipe rows 25 px, category headers 25 (+2) px")
  local gp = ml.pools.group
  check(gp[1].text._text == "Online" and gp[2].text._text == "Offline" and gp[1].open == true and gp[2].open == false
    and gp[1].CollapseButton.text._text == "–" and gp[2].CollapseButton.text._text == "+" and gp[1].bg._atlas == "common-button-list-collapseExpand"
    and gp[1].count == nil and gp[1].RankBar == nil and gp[1]._template == nil,
    "K8 group headers = the replicated category header: 'Online' (open, '–') / 'Offline' (collapsed, '+'), no count, no template instance")
  local mb = ml.rows[2]
  check(mb.data == K5.bud and mb.badge == nil and mb.classIcon == nil and mb.line == nil and plain(mb.name._text) == "Bud Stone  39" and mb.name._text:find("^|TInterface\\FriendsFrame\\StatusIcon%-Online") and mb.name._text:find("|cff", 1, true)
    and mb.gain._text == "+20" and mb.name._points[1][4] == 22,
    "K8 / user 2026-11-15: member row: online dot + name in class colour + level, '+20' right (no class icon, no second line): " .. plain(mb.name._text))
  check(plain(ml.rows[1].name._text) == "Me Stone  36 (you)", "you marked")
  check(mb.sel._shown and mb.sel._atlas == "Professions_Recipe_Active" and not ml.rows[1].sel._shown
    and mb.hl._atlas == "Professions_Recipe_Hover" and mb.hl._alpha == 0.5,
    "K8: the selected member = Professions_Recipe_Active, hover = Professions_Recipe_Hover")
  check(mb.textW == UIx.memberListW - 22 - UIx.MEMBER_GAIN_W - 10 and mb.name._SetWordWrap[1] == false, "name left of the gain, one line")
  captureTip(); mb._scripts.OnEnter(mb)
  check(tipText():find("3 upgrades · best: Waist", 1, true), "K8: the former second line is in the row's tooltip")
  captureTip(); ml.rows[3]._scripts.OnEnter(ml.rows[3])
  check(tipText():find("1 upgrade · best: Chest", 1, true), "singular line (tooltip)")
  gp[2]._scripts.OnClick(gp[2])
  local olgaRow
  for _, r in ipairs(ml.rows) do if r._shown and r.data == K5.olga then olgaRow = r end end
  local r, g, b = UIx.OfflineColor(0.25, 0.78, 0.92)
  check(olgaRow and olgaRow.offline and olgaRow.name._alpha == 1 and olgaRow.name._text:find("StatusIcon-Offline", 1, true)
    and UIx.MemberName({ key = "X", class = "MAGE", online = true }):find("StatusIcon-Online", 1, true)
    and r < 0.25 + 0.5 and math.abs(r - g) < math.abs(0.25 - 0.78),
    "offline group expanded: Olga listed with the grey offline dot, class colour softened (not dimmed)")
  captureTip(); gp[2]._scripts.OnEnter(gp[2])
  check(tipText():find("Offline (1)", 1, true), "group header tooltip")
  local ms = UIx.memberSearch
  ms:SetText("cara"); ms._scripts.OnTextChanged(ms)
  kinds = {}
  for i, d in ipairs(ml.data) do kinds[i] = d.rowKind and d.group or d.key end
  check(table.concat(kinds, ",") == "online,Cara Field" and ms.native and ms._template == "SearchBoxTemplate", "K5 member search 'cara': only Cara (K6: SearchBoxTemplate)")
  UIx:OpenMember("Bud Stone")
  check(ms._text == "" and UIx.selected == "Bud Stone", "opening a member hidden by the search clears the search")
  UIx.collapsed.offline = true
  check(UIx.syncDot.text._text == "Guild sync · 3 recorded", "K5 sync label: 'Guild sync · 3 recorded' (members with gear, not you): " .. tostring(UIx.syncDot.text._text))

  print("== K1/K6: header strip, (i) icon, sync label")
  check(UIx.syncText == nil and UIx.syncDot and UIx.syncDot.dot == nil and UIx.survival._parent == f.content, "sync text gone from the header strip; K6: no dot; slider in the bottom bar")
  local sync = GCA.SyncState
  for _, st in ipairs({ "ok", "idle", "paused", "off" }) do
    GCA.SyncState = function() return st end
    UIx.syncDot:Update()
    local c = UIx.SYNC_COLORS[st]
    check(UIx.syncDot.state == st and UIx.syncDot.text._SetTextColor[1] == c[1] and UIx.syncDot.text._SetTextColor[2] == c[2], "K6: sync label coloured for '" .. st .. "'")
  end
  GCA.SyncState = sync
  GCA.SyncStatusLine = function() return "Guild sync: 2 guildie(s) with the addon seen" end
  captureTip(); UIx.syncDot._scripts.OnEnter(UIx.syncDot)
  check(tipText():find("Guild sync", 1, true) and tipText():find("2 guildie", 1, true) and tipText():find("Green:", 1, true), "sync dot tooltip = status line + legend")
  GCA.SyncStatusLine = nil
  check(UIx.infoIcon.kind == "text" and UIx.infoIcon.text._text == "(i)", "(i) icon: text fallback (no info atlas / file check in this mock)")
  UIx:Refresh()
  captureTip(); UIx.infoIcon._scripts.OnEnter(UIx.infoIcon)
  check(tip[1] == "Scoring" and (UIx.sourceLine == "" or tipText():find(UIx.sourceLine, 1, true)), "(i) tooltip shows the source line")
  check(UIx.errorCount == before, "no error reported (K2 window)")
  UIx:SetView("needs")
  f:Hide()
  GCA.GetMemberList = origML

  print("== K5: skill bar (StatusBar path), class icon, skin table")
  Frame.SetStatusBarTexture = function(self, t) self._sbTex = t end
  Frame.SetStatusBarColor = function(self, ...) self._sbColor = { ... } end
  UIx.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local pb2 = GCA.UI.profButton
  pb2:SetSkill("Leatherworking  150 / 225", 150, 225)
  check(pb2.barKind == "statusbar" and pb2.bar._sbTex == "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" and pb2.bar._sbColor
    and math.abs(pb2.bar._value - 150 / 225) < 1e-9 and pb2.label._parent == pb2.top and pb2.border._atlas == "Professions-skillbar-frame", "K5/K6: StatusBar API present: skill-bar file, value = 150/225, text + rank-bar frame above the fill")
  pb2:SetSkill("Blacksmithing (browse)")
  check(pb2.bar._value == 0 and pb2.ratio == 0, "K5: no rank (browse): empty bar")
  Frame.SetStatusBarTexture, Frame.SetStatusBarColor = nil, nil
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  pb2 = GCA.UI.profButton
  pb2:SetSkill("x", 60, 300)
  check(pb2.barKind == "fill" and pb2.fill._SetColorTexture and math.abs(pb2.fill._w - (GCA.UI.PROF_BAR_W - 10) * 0.2) < 1e-9, "K5: skill-bar file not there: plain fill in the skin colour, 20 %")
  GetFileIDFromPath = nil
  local ic = GCA.UI.specButton.icon
  CLASS_ICON_TCOORDS = { ROGUE = { 0.5, 0.75, 0, 0.25 } }
  check(GCA.UI.SetClassIcon(ic, "ROGUE") == "file" and ic._tex == "Interface\\TargetingFrame\\UI-Classes-Circles" and ic._SetTexCoord[1] == 0.5,
    "K5 class icon: the class-circles file + CLASS_ICON_TCOORDS where the atlas is missing")
  ATLASES["classicon-rogue"] = true
  check(GCA.UI.SetClassIcon(ic, "ROGUE") == "atlas" and ic._atlas == "classicon-rogue", "K5 class icon: the atlas when GetAtlasInfo knows it")
  ATLASES["classicon-rogue"] = nil
  GetFileIDFromPath = function() return nil end
  check(GCA.UI.SetClassIcon(ic, "MAGE") == nil and GCA.UI.SetClassIcon(ic, nil) == nil, "K5 class icon: neither -> none (text only)")
  GetFileIDFromPath = nil
  CLASS_ICON_TCOORDS = nil
  GCA.UI.specButton:SetClass("WARRIOR")
  check(not GCA.UI.specButton.icon._shown and GCA.UI.specButton.iconKind == nil and GCA.UI.specButton.dropdown._shown ~= false, "spec picker without an icon: just the dropdown")
  local tx = UIx.frame:CreateTexture()
  check(GCA.UI.Skin(tx, "rowSelected") == "atlas" and tx._atlas == "Professions_Recipe_Active" and GCA.UI.Skin(tx, "rowHover") == "atlas"
    and tx._atlas == "Professions_Recipe_Hover" and tx._alpha == 0.5 and GCA.UI.Skin(tx, "listBg") == "atlas"
    and GCA.UI.SKIN.disc == nil and GCA.UI.SKIN.chipBg == nil and GCA.UI.SKIN.selectBar == nil and GCA.UI.SKIN.treeLine == nil and GCA.UI.TEX.disc == nil,
    "K8 skin table: the recipe row's own hover / selected atlases, summarylist panel; no disc/chip/select-bar/tree roles")
  ATLASES["Professions_Recipe_Hover"] = nil
  local tx2 = UIx.frame:CreateTexture()
  check(GCA.UI.Skin(tx2, "rowHover") == "file" and tx2._tex == GCA.UI.TEX.rowHL and tx2._SetBlendMode[1] == "ADD", "K8 skin: without the hover atlas the list-row file (ADD)")
  ATLASES["Professions_Recipe_Hover"] = true
  local sk = GCA.UI.SKIN
  check(type(sk.detailBorder) == "table" and sk.category.atlas == "common-button-list-collapseExpand" and sk.categoryHover.atlasBlend == "ADD"
    and #sk.collapseIcon.pairs >= 1 and sk.detailRing.file == "Interface\\Common\\GoldRing",
    "K8 skin roles: detailBorder (pluggable), category / categoryHover, collapseIcon candidates, detailRing")
  GCA.UI.frame:Hide()
  UIx = GCA.UI

  print("== K1: German texts on the new parts")
  ns.locale = "deDE"
  GCA.GetMemberList = function() return list end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(UIx.tabs[1]._text == "Gildenbedarf" and UIx.tabs[2]._text == "Nach Mitglied", "German tabs")
  check(plain(UIx.needsCount._text) == "3 Herstellungen lohnen für 2 Mitglieder" and UIx.searchBox.placeholder._text == "Suchen"
    and plain(menuOf(UIx.filterButton)[5].text) == "Offline-Mitglieder einbeziehen (1)" and plain(menuOf(UIx.filterButton)[7].text):find("^Levelbonus") and plain(menuOf(UIx.filterButton)[8].text):find("^Flüstertext"),
    "K5 German count, search instructions; K6 Filter menu entries: " .. plain(UIx.needsCount._text))
  local gr1 = UIx.needsList.rows[1]
  check(gr1.count._text == " [2]" and UIx.needsList.pools.cat[1].text._text == "Chest" and UIx.needsList.pools.cat[3].text._text == "Ringe"
    and UIx.needDetail.forTitle._text == "Wäre eine Verbesserung für 2 Mitglieder:", "K8 German: craft row ' [2]', categories 'Chest' (client global, absent in the mock) / 'Ringe', detail title")
  local gs = UIx.needDetail.members.rows[1]
  check(plain(gs.state._text) == "Old Vest" and gs.offer._text == "Anbieten",
    "K5 German member row: 'Old Vest' beside the icon, K6 red 'Anbieten' button: " .. plain(gs.state._text))
  UIx.searchBox:SetText("zzz"); UIx.searchBox._scripts.OnTextChanged(UIx.searchBox)
  check(UIx.needsEmpty._text == "Keine Verbesserung passt zu „zzz“.", "German no-match text")
  UIx.searchBox:SetText(""); UIx.searchBox._scripts.OnTextChanged(UIx.searchBox)
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local gml = UIx.memberList
  check(gml.pools.group[1].text._text == "Online" and plain(gml.rows[2].name._text) == "Bud Stone  39"
    and UIx.modeToggle._override == "Ansicht: Charakterbogen" and UIx.syncDot.text._text == "Gilden-Sync · 3 erfasst" and UIx.memberSearch.placeholder._text == "Mitglied suchen"
    and menuTexts(menuOf(UIx.modeToggle)) == "Charakterbogen|Liste",
    "K6/K8 German: 'Online' header, member row, 'Ansicht: Charakterbogen' (radios Charakterbogen|Liste), 'Gilden-Sync · 3 erfasst', 'Mitglied suchen'")
  check(UIx.MemberRows(list)[1].group == "online" and ns.L.CARDS_WORN_CAPS == "ANGELEGT", "German: groups, 'ANGELEGT'")
  -- German layout (K5: 840x560 and 980x640), both views
  for _, sz in ipairs({ { 840, 560 }, { 980, 640 } }) do
    UIx.frame:SetSize(sz[1], sz[2]); UIx:Layout()
    layoutChecks(UIx, UIx.frame, "German " .. sz[1] .. "x" .. sz[2])
  end
  -- rough text fit at 840 (the mock can't measure text: ~5.6 px per character of the small font, ~6.5 normal,
  -- ~8 large, in the narrowest place each text gets). Heuristic only; the real check is in game.
  local function fits(text, px, per) return #plain(text):gsub("[\128-\191]", "") * per <= px end
  local tooWide = {}
  local function fit(name, text, px, per) if not fits(text, px, per) then tooWide[#tooWide + 1] = name .. " '" .. plain(text) .. "'" end end
  UIx.frame:SetSize(840, 560); UIx:Layout()
  fit("rank bar", "Lederverarbeitung  300 / 300", UIx.PROF_BAR_W - 60, 5.6)
  fit("view switch", string.format(ns.Locales.deDE.MVIEW_LABEL, ns.Locales.deDE.MVIEW_SHEET), UIx.TOGGLE_W - 30, 5.6)
  fit("search placeholder", ns.Locales.deDE.NEEDS_SEARCH, UIx.SEARCH_W - 35, 5.6)
  fit("offline filter entry", string.format(ns.Locales.deDE.NEEDS_OFFLINE, 12), 260, 5.6)
  fit("needs count", "12 Herstellungen lohnen für 45 Mitglieder", UIx.LEFT_W - 20, 5.6)
  fit("member row", "Mitglied Nachname  60", UIx.memberListW - 22 - UIx.MEMBER_GAIN_W - 10, 6.5) -- longer ones end in "…"
  fit("member search", ns.Locales.deDE.MEMBER_SEARCH, UIx.SEARCH_W - 35, 5.6)
  fit("category header", "Schmuckstücke", UIx.needsW - 8 - 32, 8)
  fit("craft row", "Dunkler Ledergürtel [3]", UIx.needsW - 22 - UIx.NEED_GAIN_W - 10, 6.5)
  fit("detail title", string.format(ns.Locales.deDE.DETAIL_FOR_N, 12), UIx.needDetail.w - 36, 5.6)
  fit("filter reset tip", ns.Locales.deDE.FILTER_RESET, 200, 6.5)
  fit("spec label", "Göttliche Pein (Schaden)", UIx.SPEC_BTN_W - 28 - 30, 5.6)
  fit("sync label", "Gilden-Sync · 123 erfasst", 200, 5.6)
  fit("member-view sub-line", "tragbar ab Stufe 42 (in 3 Stufen)  ·  nicht erlernt", UIx.subText._w, 5.6)
  fit("fold tip title", ns.Locales.deDE.FOLD_TIP_TITLE, 300, 6.5)
  fit("tab", "Nach Mitglied", 130 - 20, 6.5)
  fit("fallback tab button", "Nach Mitglied", 92 - 6, 6.5)
  check(#tooWide == 0, "German text fit at 840x560 (estimate): " .. table.concat(tooWide, "; "))
  UIx.frame:Hide()
  ns.locale = "enUS"
  GCA.GetMemberList = origML

  print("== K: fallbacks (no tab template, no texture files, slider template present)")
  -- 1) PanelTabButtonTemplate missing -> two buttons in the header strip, nothing overlaps at 840x560
  local origCF = CreateFrame
  CreateFrame = function(otype, name, parent, template)
    if template == "PanelTabButtonTemplate" then error("Couldn't find inherited node 'PanelTabButtonTemplate'") end
    return origCF(otype, name, parent, template)
  end
  GCA.GetMemberList = function() return list end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  local errs = UIx.errorCount
  check(not UIx.tabsTemplated and #UIx.tabs == 2 and UIx.tabs[1]._parent == UIx.frame.content and UIx.tabs[1]._text == "Guild needs",
    "no tab template: two plain buttons in the header strip")
  UIx.tabs[2]._scripts.OnClick(UIx.tabs[2])
  check(UIx.view == "member" and UIx.errorCount == errs, "fallback buttons switch the view")
  UIx.frame:SetSize(840, 560); UIx:Layout()
  layoutChecks(UIx, UIx.frame, "tab fallback 840x560")
  UIx.frame:Hide()
  CreateFrame = origCF
  -- 2) GetFileIDFromPath says no file exists -> ASCII +/- and marks (K6: Offer is always the red text button)
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  local ns1 = UIx.needDetail.members.rows[1]
  check(ns1.offer._shown and not ns1.offer.isIcon and ns1.offer._text == "Offer" and ns1.offer._w == UIx.OFFER_SMALL_W, "K6: Offer = the red text button 'Offer' (no file needed)")
  check(UIx.needsList.pools.cat[1].CollapseButton.text._text == "–" and UIx.needDetail.iconBtn.iconShape == "square",
    "no files: the category's '–' text; K8 the detail icon falls back to the square reagent-slot icon (mask / ring files not confirmed)")
  check(UIx.infoIcon.kind == "text", "info icon file not confirmed: text '(i)'")
  UIx.frame:Hide()
  -- 3) GetFileIDFromPath confirms the files -> the info file is used (no atlas); Offer stays the text button
  GetFileIDFromPath = function(p) return 12345 end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(not UIx.needDetail.members.rows[1].offer.isIcon and UIx.infoIcon.kind == "file" and UIx.infoIcon.tex._tex == UIx.INFO_FILE, "files confirmed: info file; Offer still the button")
  UIx.frame:Hide()
  GetFileIDFromPath = nil
  -- 4) K6: the native templates missing -> plain fallbacks, the window still works (DropdownButton, SearchBoxTemplate,
  -- the category template, MinimalScrollBar, MinimalCheckboxTemplate)
  for k in pairs(nativeMode) do nativeMode[k] = "fail" end
  GetFileIDFromPath = function() return nil end
  GCA.UI.frame = nil
  local errs4 = UIx.errorCount
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(not UIx.filterButton.native and UIx.filterButton._text == "Filter" and UIx.filterPopup and not UIx.searchBox.native
    and UIx.searchBox.placeholder and UIx.searchBox.clear and UIx.needsList.ScrollBar and UIx.needsList.minimalBar == nil,
    "K6 fallbacks: red 'Filter' button + popup, the K2 search box, UIPanelScrollFrameTemplate")
  UIx.filterButton._scripts.OnClick(UIx.filterButton)
  local fp = UIx.filterPopup
  check(fp._shown and #fp.buttons == 6 and plain(fp.buttons[5].text._text) == "Include offline members (1)", "fallback Filter popup: 4 toggles, offline members, edit whisper")
  fp.buttons[5]._scripts.OnClick(fp.buttons[5])
  check(GCA.db.settings.needsOffline == true and fp.buttons[5].check._shown, "fallback popup toggles 'Include offline members'")
  fp.buttons[5]._scripts.OnClick(fp.buttons[5]); fp:Hide()
  UIx:SetView("member")
  check(not UIx.modeToggle.native and UIx.modeToggle._text == "View: Character sheet", "fallback view switch: a red button naming the shown variant")
  UIx.modeToggle._scripts.OnClick(UIx.modeToggle)
  check(UIx.MemberMode() == "list" and UIx.modeToggle._text == "View: List", "...a click switches to the other variant")
  UIx.modeToggle._scripts.OnClick(UIx.modeToggle)
  local sdd = UIx.specButton.dropdown
  check(not sdd.native and UIx.specPopup, "fallback spec picker: button + popup")
  sdd._scripts.OnClick(sdd)
  check(UIx.specPopup._shown and #UIx.specPopup.buttons >= 2, "fallback spec popup lists Automatic + the specs")
  UIx.specPopup:Hide()
  check(not UIx.profButton.drop.native and UIx.profPopup and UIx.profButton.drop.arrow._atlas == "common-dropdown-a-button", "fallback profession arrow: plain button + popup")
  UIx.profButton._scripts.OnClick(UIx.profButton)
  local picked
  for _, pbn in ipairs(UIx.profPopup.buttons) do if plain(pbn.text._text):find("^> Leatherworking") then picked = pbn end end
  check(UIx.profPopup._shown and picked and not picked.mark._shown, "no check file: '> ' marks the pick in the fallback popup")
  UIx.profPopup:Hide()
  local g1 = UIx.memberList.pools.group and UIx.memberList.pools.group[1]
  check(g1 and not g1.native and g1.text._text and g1.CollapseButton, "K8 group header: the replicated category row (no template involved)")
  check(UIx.errorCount == errs4, "K6 fallbacks: no error reported")
  UIx.frame:Hide()
  for k in pairs(nativeMode) do nativeMode[k] = "ok" end
  GetFileIDFromPath = nil
  -- 4) the info atlas exists -> atlas
  ATLASES[UIx.INFO_ATLAS] = true
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(UIx.infoIcon.kind == "atlas" and UIx.infoIcon.tex._atlas == UIx.INFO_ATLAS, "info atlas present: drawn from the atlas (GetAtlasInfo-guarded)")
  UIx.frame:Hide()
  ATLASES[UIx.INFO_ATLAS] = nil
  -- 5) MinimalSliderWithSteppersTemplate present (shape as Spoken uses it): Init + callback + SetValue
  local made
  MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = "OnValueChanged" } }
  CreateFrame = function(otype, name, parent, template)
    local fr = origCF(otype, name, parent, template)
    if template == "MinimalSliderWithSteppersTemplate" then
      made = fr
      fr.Slider = origCF("Slider", nil, fr)
      function fr:Init(v, lo, hi, steps, fmt) self.init = { v, lo, hi, steps, fmt } ; self._value = v end
      function fr:RegisterCallback(ev, fn, owner) self.cb = { ev, fn, owner } end
      function fr:SetValue(v) local old = self._value; self._value = v; if old ~= v and self.cb then self.cb[2](self.cb[3], v) end end
    end
    return fr
  end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  CreateFrame = origCF
  UIx = GCA.UI
  local hs = UIx.survival
  check(hs.templated and hs.slider == made and made.init[1] == 50 and made.init[2] == 0 and made.init[3] == 100 and made.init[4] == 20
    and made.cb[1] == "OnValueChanged", "slider template: Init(50, 0, 100, 20 steps) + OnValueChanged callback")
  local inv, realInv = 0, GCA.InvalidateScores
  GCA.InvalidateScores = function(...) inv = inv + 1; return realInv(...) end
  made:SetValue(70); advance(0.1); made:SetValue(75)
  check(hs.label._text:find("75%%") and math.abs(GCA:SurvivalShare() - 0.5) < 1e-9, "template slider: label follows at once, value waits (K0 debounce kept)")
  advance(0.5)
  check(math.abs(GCA:SurvivalShare() - 0.75) < 1e-9 and inv == 1, "...applied once after 0.4 s")
  hs:Sync()
  check(made._value == 75, "Sync sets the template slider's value without firing a change")
  GCA.InvalidateScores = realInv
  GCA.db.settings.survival = 0.5
  captureTip(); local okTip = pcall(made.Slider._scripts.OnEnter, made.Slider)
  check(okTip and tipText():find("Leveling bonus", 1, true), "template slider: our tooltip hooked onto its inner Slider")
  UIx.frame:Hide()
  MinimalSliderWithSteppersMixin = nil
  -- 6) a template that exists but lacks the API -> plain slider
  CreateFrame = function(otype, name, parent, template)
    local fr = origCF(otype, name, parent, template)
    if template == "MinimalSliderWithSteppersTemplate" then fr.Init = function() error("bad") end; fr.RegisterCallback = function() end end
    return fr
  end
  MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = 1 } }
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  CreateFrame = origCF
  MinimalSliderWithSteppersMixin = nil
  check(not GCA.UI.survival.templated and GCA.UI.survival.slider._type == "Slider" and GCA.UI.errorCount == errs,
    "a slider template whose Init fails: plain slider instead, no error")
  GCA.UI.frame:Hide()
  GCA.GetMemberList = origML
  ITEM_QUALITY_COLORS = nil
  PanelTemplates_SelectTab, PanelTemplates_DeselectTab = nil, nil
  HandleModifiedItemClick = function() end
  GCA.UI.frame = nil
  templateMode, GCA.IsBrowse = savedTM, savedBrowse
end

-- Section K4: two switchable member views ("Character sheet" default, "List" cards)
do
  print("== K4: member view variants (character sheet / list)")
  local savedTM, savedBrowse = templateMode, GCA.IsBrowse
  templateMode = "ok"
  GCA.IsBrowse = function() return false end
  ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
  local printFn = GCA.Print
  local printed = {}
  GCA.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
  local linked
  HandleModifiedItemClick = function(l) linked = l end
  -- a fake weight entry (Core shape: key + set.weights; no unitW -> "pts")
  local E = { key = "k4", set = { weights = { Agility = 1, Stamina = 0.5, Armor = 0.05, MeleeHit = 10, Strength = 0.8 }, source = {} },
    raw = { source = { kind = "sim", minLevel = 30, maxLevel = 40 } }, class = "ROGUE", spec = "COMBAT", level = 39, share = 0.5, t = 1 }
  local function eq(name, q, cstats) return { name = name, quality = q, icon = 134, link = "|Hitem:9|h[" .. name .. "]|h", cstats = cstats or {}, scores = {} } end
  local eqInfo = { [5] = eq("Worn Vest", 2, { Strength = 2 }), [11] = eq("Ring A", 3), [12] = eq("Ring B", 2), [9] = eq("Bracers", 1) }
  local items = { [5] = "item:4244", [11] = "item:5001", [12] = "item:5002", [9] = "item:4245" }
  local function rec(id) return { skill = 100, src = "trainer", r = {} } end
  local s1 = fakeSug({ e = E, equipped = eqInfo[5], oldScore = 1.6, newScore = 20, sortPct = 12, hint = nil,
    info = { name = "Hillman's Leather Vest", link = "|Hitem:4244|h[Hillman's Leather Vest]|h", quality = 2, icon = "x", minLevel = 20,
      cstats = { Agility = 6, Stamina = 4, Armor = 35, MeleeHit = 1, SpellHit = 1 } } })
  local s2 = fakeSug({ e = E, equipped = eqInfo[5], pct = 0.05, sortPct = 5, extra = true,
    cand = { spellID = 3763, itemID = 4245, recipe = rec() }, info = { name = "Second Vest", quality = 2, icon = "x", minLevel = 20, cstats = { Agility = 2 } } })
  local ring = fakeSug({ e = E, slot = 12, equipped = eqInfo[12], pct = 0.5, sortPct = 50,
    cand = { spellID = 3770, itemID = 5, recipe = rec() }, info = { name = "Craft Ring", quality = 3, icon = "x", minLevel = 20, link = "|Hitem:5|h[Craft Ring]|h" } })
  local glove = fakeSug({ e = E, slot = 10, future = true, wearAt = 42, levelsToGo = 3, pct = 0.2, sortPct = 20,
    cand = { spellID = 3771, itemID = 6, recipe = rec() }, info = { name = "Future Gloves", quality = 2, icon = "x", minLevel = 42 } })
  local ench1 = fakeSug({ e = E, kind = "enchant", slot = 9, pct = 0.08, sortPct = 8, enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" },
    cand = { spellID = 7779, enchant = true, recipe = rec() }, info = { name = "Enchant Bracer - Minor Agility", quality = 1, icon = "x", cstats = { Agility = 1 } },
    equipped = { name = "Minor Stamina", cstats = { Stamina = 1 } } })
  local ench2 = fakeSug({ e = E, kind = "enchant", slot = 9, pct = 0.04, sortPct = 4, extra = true, enchant = { enchant = 248, name = "Minor Spirit" }, item = { name = "Bracers" },
    cand = { spellID = 7780, enchant = true, recipe = rec() }, info = { name = "Enchant Bracer - Minor Spirit", quality = 1, icon = "x", cstats = {} },
    equipped = { name = "Minor Stamina", cstats = { Stamina = 1 } } })
  -- shoulders: 3 crafts, the first with 7 stat changes (the sheet's worst case: 6 shown + "more", tags, 2 alternatives)
  local sh1 = fakeSug({ e = E, slot = 3, pct = 0.3, sortPct = 30, hint = "Set hint", known = false,
    cand = { spellID = 3780, itemID = 7, recipe = rec() }, info = { name = "Shoulders of Many Stats", quality = 2, icon = "x", minLevel = 20,
      cstats = { Agility = 1, Stamina = 1, Armor = 1, Strength = 1, Intellect = 1, Spirit = 1, Defense = 1 }, unknownStats = { "ITEM_MOD_X" } } })
  local sh2 = fakeSug({ e = E, slot = 3, pct = 0.2, sortPct = 20, extra = true, cand = { spellID = 3781, itemID = 8, recipe = rec() },
    info = { name = "Second Shoulders", quality = 2, icon = "x", minLevel = 20 } })
  local sh3 = fakeSug({ e = E, slot = 3, pct = 0.1, sortPct = 10, extra = true, future = true, wearAt = 44, levelsToGo = 5,
    cand = { spellID = 3782, itemID = 10, recipe = rec() }, info = { name = "Third Shoulders", quality = 2, icon = "x", minLevel = 44 } })
  -- a member entry with REAL Core sections (GCA:BuildSections: sections sorted by their best row)
  local function member(key, rowsBy, online)
    local list = {}
    for _, rows in pairs(rowsBy) do for _, r in ipairs(rows) do list[#list + 1] = r end end
    table.sort(list, GCA.SuggestionOrder)
    list.sections = GCA:BuildSections(rowsBy, {}, items, eqInfo, {}, E)
    return { key = key, online = online ~= false, class = "ROGUE", level = 39, prof = "Leatherworking", state = "ok", weights = E,
      member = { items = items, time = time(), source = "inspect" }, suggestions = list, best = list[1], knownCount = #list,
      spec = "COMBAT", specHow = "manual" }
  end
  local bud = member("Bud Stone", { [5] = { s1, s2 }, [11] = { ring }, [10] = { glove }, [9] = { ench1, ench2 }, [3] = { sh1, sh2, sh3 } })
  local cara = member("Cara Field", {}) -- recorded and compared, nothing craftable
  cara.best, cara.knownCount = nil, 0
  local olga = member("Olga Field", { [5] = { s1 } }, false)
  local nogear = { key = "Nobody Yet", online = true, class = "WARRIOR", level = 20, prof = "Leatherworking" }
  local list = { bud, cara, olga, nogear }
  local origML = GCA.GetMemberList
  GCA.GetMemberList = function() return list end
  GCA.db.settings.memberView = nil
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  local f = UIx.frame
  local errs = UIx.errorCount
  local mt = UIx.modeToggle
  local mm = menuOf(mt)
  check(UIx.MemberMode() == "sheet" and mt.native and mt._template == "WowStyle1DropdownTemplate" and mt.buttons == nil and #mm == 2
    and menuTexts(mm) == "Character sheet|List" and mm[1].kind == "radio" and mm[1]:on() and not mm[2]:on() and mt._override == "View: Character sheet",
    "K6: the view switch is a WowStyle1DropdownTemplate (radios Character sheet|List, text View: Character sheet), the sheet is the default")
  GCA.db.settings.memberView = "junk"
  check(UIx.MemberMode() == "sheet", "a junk saved value means the sheet")
  GCA.db.settings.memberView = nil
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local sh, c = UIx.sheet, UIx.sheet.centre
  check(sh._shown and not UIx.sugList._shown and UIx.current == bud and UIx.emptyText._text == "", "member view: the sheet is shown, the list hidden")

  print("== K4: sheet: default slot, badges, selection")
  check(UIx.sheetSlot == 12 and UIx.sheetAuto and UIx.SheetDefaultSlot(bud.suggestions) == 12,
    "default slot = the biggest upgrade (Craft Ring +50% replaces Ring 2), not the first in character order")
  local badges, sel = {}, {}
  for slot, b in pairs(sh.slots) do
    if b.badge._shown then badges[#badges + 1] = slot end
    if b.sel._shown then sel[#sel + 1] = slot end
  end
  table.sort(badges)
  check(table.concat(badges, ",") == "3,5,9,10,12" and table.concat(sel, ",") == "12",
    "up-arrow badge on the 5 slots with an upgrade (ring badge on Ring 2 only), the selected slot keeps the item-button highlight: " .. table.concat(badges, ","))
  local b12 = sh.slots[12]
  check(b12.badgeKind == "file" and b12.badge._tex == "Interface\\BUTTONS\\Arrow-Up-Up" and b12.badge._SetVertexColor[2] == 1
    and b12.badge._alpha ~= 0.5, "badge = GearQuestForever's Arrow-Up-Up file tinted green")
  check(sh.slots[10].badge._alpha == 0.5, "a slot with only too-high-level crafts: dimmed badge")
  check(sh.slots[5].icon._tex == 134 and not sh.slots[5].icon._SetDesaturated[1] and sh.slots[5].iconBorder._tex == "Interface\\Common\\WhiteIconFrame"
    and sh.slots[5].iconBorder._SetVertexColor[2] == 1, "worn item: its icon in a quality-coloured frame")
  check(sh.slots[1].icon._tex == "Interface\\PaperDoll\\UI-PaperDoll-Slot-HeadSlot" and sh.slots[1].icon._SetDesaturated[1] == true
    and sh.slots[1].icon._alpha == 0.45 and sh.slots[1].empty, "empty slot: the character window's slot art, desaturated and dimmed")
  check(plain(c.header._text) == "Ring 2" and c.count._text == "1 craftable upgrade" and c.mode == "upgrade" and c.featured == ring
    and plain(c.worn.name._text) == "Ring B" and c.worn.label._text == "Equipped" and c.best.label._text == "Best craft"
    and plain(c.best.name._text) == "Craft Ring" and c.best.gain._text == "+50 pts" and c.best.points._text == ""
    and c.best._shown and c.arrow._shown, "middle: 'Ring 2 · 1 craftable upgrade', Ring B -> Craft Ring, big '+50 pts' (no size line without a share)")
  check(c.worn.score._text == "1.0 pts" and c.best.score._text == "2.0 pts", "card scores = the comparison's old/new score (as the tooltip)")
  -- click the chest
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  check(UIx.sheetSlot == 5 and not UIx.sheetAuto and sh.slots[5].sel._shown and not sh.slots[12].sel._shown and c.featured == s1
    and c.count._text == "2 craftable upgrades" and plain(c.header._text) == "Chest", "slot click: the chest in the middle, highlight moves")
  local stats = {}
  for i = 1, c.nStats do stats[i] = plain(c.stats[i]._text) end
  check(c.nStats == 5 and table.concat(stats, ", ") == "+1% Hit, +6 Agility, +4 Stamina, +35 Armor, -2 Strength"
    and c.stats[5]._text:find("|cffff5555-2", 1, true) and c.stats[1]._text:find("|cff33ff33+1%", 1, true),
    "stat differences new - worn, biggest weighted first, hit twins merged, loss in red: " .. table.concat(stats, ", "))
  check(c.nAlts == 1 and c.alts[1]._shown and c.alts[1].data == s2 and c.moreTitle._text == "More options" and c.moreTitle._shown and c.sep._shown,
    "'More options': the slot's other craft")
  check(c.offer._shown and c.offer._text == "Offer" and c.crafted._shown and c.craftedLabel._text == "Crafted" and not c.crafted._checked,
    "actions: 'Crafted' box + 'Offer' button")
  -- crafted mark from the sheet (same store as the rows)
  c.crafted:SetChecked(true); c.crafted._scripts.OnClick(c.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) ~= nil and c.crafted._checked == true and UIx.sheetSlot == 5,
    "sheet crafted box stores the mark for Bud, the box shows it after the refresh, slot kept")
  captureTip(); c.crafted._scripts.OnEnter(c.crafted)
  check(tip[1] == "Crafted" and tipText():find("Crafted for Bud Stone", 1, true), "sheet crafted box tooltip (shared)")
  c.crafted:SetChecked(false); c.crafted._scripts.OnClick(c.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) == nil, "...unticked: mark gone")
  -- Offer from the sheet (no chat API in this mock -> the text is printed)
  printed = {}
  c.offer._scripts.OnClick(c.offer)
  check(table.concat(printed, "\n"):find("Hi Bud! I'm a leatherworker and could craft you |Hitem:4244", 1, true), "sheet Offer writes the whisper for the featured craft")
  captureTip(); c.offer._scripts.OnEnter(c.offer)
  check(tip[1] == "Offer" and #tip >= 5, "sheet Offer tooltip (shared with the rows)")
  -- alternative: click compares it, label says so; the featured one moves into the list
  c.alts[1]._scripts.OnClick(c.alts[1])
  check(c.featured == s2 and c.best.label._text == "Compared" and c.alts[1].data == s1 and UIx.sheetSlot == 5, "alternative clicked: compared above ('Compared'), the best one listed below")
  captureTip(); c.alts[1]._scripts.OnEnter(c.alts[1])
  check(plainTip(), "K17: alternative tooltip = the plain item tooltip (no click hint): " .. tipText())
  linked = nil
  IsShiftKeyDown = function() return true end
  c.alts[1]._scripts.OnClick(c.alts[1])
  sh.slots[11]._scripts.OnClick(sh.slots[11])
  IsShiftKeyDown = function() return false end
  check(linked == "|Hitem:9|h[Ring A]|h" and UIx.sheetSlot == 5 and c.featured == s2, "shift-click on a slot links the worn item (selection unchanged)")
  -- enchants are reachable: bracers slot, enchant marker on the alternative
  sh.slots[9]._scripts.OnClick(sh.slots[9])
  check(c.featured == ench1 and c.best.label._text == "Best enchant" and c.alts[1].data == ench2 and c.alts[1].tag._shown
    and plain(c.alts[1].tag._text) == "Enchant" and c.craftedLabel._text == "Enchanted"
    and plain(c.tags._text) == "replaces Minor Stamina on Bracers", "enchants: 'Best enchant', alternative with an 'Enchant' marker, 'Enchanted' box")
  local es = {}
  for i = 1, c.nStats do es[i] = plain(c.stats[i]._text) end
  check(table.concat(es, ", ") == "+1 Agility, -1 Stamina", "enchant stat differences = new enchant - current enchant: " .. table.concat(es, ", "))
  -- too high level: dimmed card + orange level tag
  sh.slots[10]._scripts.OnClick(sh.slots[10])
  check(c.featured == glove and c.best.dimmed and c.best.icon._alpha == 0.55 and plain(c.tags._text) == "from level 42 · 3 to go"
    and c.tags._text:find("|cfff0b44c", 1, true), "too-high-level craft: dimmed card, orange 'from level 42 · 3 to go'")
  -- a slot without an upgrade
  sh.slots[1]._scripts.OnClick(sh.slots[1])
  check(c.mode == "none" and not c.best._shown and not c.arrow._shown and not c.offer._shown and c.none._shown
    and c.none._text == "No craftable upgrade" and plain(c.worn.name._text) == "nothing equipped" and c.count._text == "0 craftable upgrades",
    "slot without an upgrade: worn card + 'No craftable upgrade', nothing else")
  sh.slots[2]._scripts.OnClick(sh.slots[2])
  check(c.mode == "none" and c.none._shown, "...also for another empty slot")
  -- tooltips
  captureTip(); sh.slots[5]._scripts.OnEnter(sh.slots[5])
  check(plainTip(), "K17: slot with a worn item: the plain item tooltip only: " .. tipText())
  captureTip(); sh.slots[1]._scripts.OnEnter(sh.slots[1])
  check(tipText():find("Head (empty / unknown)", 1, true) and tipText():find("Nothing in this list beats", 1, true), "empty slot tooltip")
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  captureTip(); c.best._scripts.OnEnter(c.best)
  check(plainTip("4244") and UIx.modWatcher == nil, "K17: best card tooltip = the plain item tooltip (no Shift re-render any more)")
  captureTip(); c.worn._scripts.OnEnter(c.worn)
  check(plainTip(), "K17: worn card tooltip = the plain item tooltip: " .. tipText())
  -- worst case content (shoulders: 6 of 7 stats + 'more' + partial + tags, 2 alternatives) stays inside the middle panel
  sh.slots[3]._scripts.OnClick(sh.slots[3])
  check(c.nStats == 6 and c.nAlts == 2 and plain(c.tags._text):find("+1 more", 1, true) and plain(c.tags._text):find("some stats not readable", 1, true)
    and plain(c.tags._text):find("Not learned", 1, true) and not c.offer._shown,
    "7 stat changes: 6 shown + '+1 more', 'some stats not readable', 'not learned' (no Offer for an unlearned recipe)")
  check(c.alts[2].data == sh3 and c.alts[2].offer._shown and plain(c.alts[2].tag._text) == "from level 44 · 5 to go" and c.alts[2].dimmed
    and (c.alts[2].offer._alpha or 1) == 1, "alternatives: level tag (orange text) + dimmed for too-high-level (Offer stays at full alpha)")
  print("== K4: switch keeps the member and the slot; saved (K6: the dropdown's radios)")
  menuOf(UIx.modeToggle)[2]:click()
  check(GCA.db.settings.memberView == "list" and UIx.selected == "Bud Stone" and UIx.current == bud and UIx.sugList._shown and not sh._shown
    and menuOf(UIx.modeToggle)[2]:on() and not menuOf(UIx.modeToggle)[1]:on() and UIx.modeToggle._override == "View: List",
    "-> List: saved, Bud still selected, cards shown, dropdown text 'View: List'")
  local sl = UIx.sugList
  check(sl.pools.section and sl.pools.section[1]._shown and sl.rows[1]._shown and sl.rows[1].data == ring, "list: section headers + cards, biggest first")
  menuOf(UIx.modeToggle)[1]:click()
  check(GCA.db.settings.memberView == "sheet" and UIx.selected == "Bud Stone" and UIx.sheetSlot == 3 and sh._shown and not sl._shown,
    "-> Character sheet: Bud and the shoulders slot kept")
  f:Hide(); SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx:SetMemberMode("list")
  f:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(UIx.MemberMode() == "list" and menuOf(UIx.modeToggle)[2]:on() and UIx.modeToggle._override == "View: List" and not UIx.sheet._shown,
    "a new window (reload) opens the saved variant: List")
  UIx:SetMemberMode("sheet")
  sh, c = UIx.sheet, UIx.sheet.centre
  -- another member: back to that member's best slot; the same member refreshed keeps your slot
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  UIx:Refresh()
  check(UIx.sheetSlot == 5, "a refresh keeps the picked slot")
  UIx.selected = "Olga Field"; UIx:Refresh()
  check(UIx.current == olga and UIx.sheetSlot == 5 and UIx.sheetAuto and not c.offer._shown and c.crafted._shown,
    "another member (offline Olga): her best slot, no Offer (offline), crafted box")
  UIx.selected = "Bud Stone"; UIx:Refresh()
  check(UIx.sheetSlot == 12 and UIx.sheetAuto, "back to Bud: his best slot again (the pick belonged to the member shown then)")

  print("== K4: members without upgrades / without gear")
  UIx.selected = "Cara Field"; UIx:Refresh()
  local anyBadge = false
  for _, b in pairs(sh.slots) do if b.badge._shown then anyBadge = true end end
  check(sh._shown and not anyBadge and UIx.sheetSlot == 1 and c.mode == "none" and c.none._shown
    and c.none._text == string.format(ns.Locales.enUS.EMPTY_NOKNOWN, "Leatherworking", "Leatherworking") and UIx.emptyText._text == "", "no upgrade at all: the sheet (worn gear), no badge, the empty-state reason in the middle: " .. tostring(c.none._text))
  UIx.selected = "Nobody Yet"; UIx:Refresh()
  check(not sh._shown and UIx.emptyText._text == ns.Locales.enUS.EMPTY_NOGEAR, "no gear recorded: no sheet, the empty-state text explains: " .. tostring(UIx.emptyText._text))

  print("== K4: list cards (MemberCards)")
  UIx.selected = "Bud Stone"
  UIx:SetMemberMode("list")
  sl = UIx.sugList
  local card
  for _, r in ipairs(sl.rows) do if r._shown and r.data == s1 then card = r end end
  check(card and plain(card.title._text) == "Hillman's Leather Vest" and plain(card.sub._text) == ""
    and card.gain._text == "+12 pts" and card.points._text == "" and card.offer._shown and card.crafted._shown,
    "card (user 2026-11-15): name, no stat-difference line, '+12 pts', box, Offer: " .. plain(card and card.sub._text))
  check(card.textW + (16 + 4 + 38 + 4 + 10) + (6 + 84 + 4 + 22 + 6 + 84 + 10) == UIx.listW, "K6: card texts (16 px indent) end where the gain / box / Offer block starts (no overlap)")
  card.crafted:SetChecked(true); card.crafted._scripts.OnClick(card.crafted)
  check(GCA:CraftedMark("Bud Stone", "Leatherworking", 3762) ~= nil, "card crafted box stores the mark")
  GCA:SetCrafted("Bud Stone", "Leatherworking", s1, false)
  printed = {}
  for _, r in ipairs(sl.rows) do if r._shown and r.data == s1 then card = r end end
  card.offer._scripts.OnClick(card.offer)
  check(table.concat(printed, "\n"):find("could craft you |Hitem:4244", 1, true), "card Offer writes the whisper")
  local hdr
  for _, h in ipairs(sl.pools.section) do if h._shown and h.data.sec.key == 11 then hdr = h end end
  check(hdr and plain(hdr.wornName._text) == "Ring A  ·  Ring B" and hdr.label == nil and hdr.count._text == "1 upgrade",
    "K5 ring worn row: 'EQUIPPED', both rings named, '1 upgrade'")
  local fold = sl.pools.fold[1]
  check(fold._shown and fold.edges == nil and fold.line and fold.text._text:find("^No craftable upgrade: Head, Neck, ") and sl.data[#sl.data].rowKind == "fold",
    "the slots without an upgrade: one grey line at the end (K6: no box border)")
  -- empty worn slot chip
  local glHdr
  for _, h in ipairs(sl.pools.section) do if h._shown and h.data.sec.key == 10 then glHdr = h end end
  check(glHdr and plain(glHdr.wornName._text) == UIx.SectionTitle(glHdr.data.sec) .. " (empty)" and glHdr.empty and glHdr.box.bg == nil and glHdr.box.icon._SetDesaturated[1] == true
    and glHdr.box.icon._alpha == 0.45, "K5 empty slot: dimmed '<Slot> (empty)', (K6: no box at all), the slot art desaturated")
  local gcard
  for _, r in ipairs(sl.rows) do if r._shown and r.data == glove then gcard = r end end
  check(gcard and gcard.dimmed and gcard.chip == nil and plain(gcard.sub._text):find("^from level 42 · 3 to go") and gcard.title._alpha == 0.55,
    "too-high-level card: dimmed, the orange level tag first on its second line")
  local ecard
  for _, r in ipairs(sl.rows) do if r._shown and r.data == ench1 then ecard = r end end
  check(ecard and plain(ecard.sub._text) == "replaces Minor Stamina on Bracers", "enchant card: what it replaces (no stat changes): " .. plain(ecard and ecard.sub._text))
  check(UIx.errorCount == errs, "no error reported (K4 English)")

  print("== K4: German")
  ns.locale = "deDE"
  f = UIx.frame
  f:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  check(menuTexts(menuOf(UIx.modeToggle)) == "Charakterbogen|Liste" and UIx.modeToggle._override:find("^Ansicht: "), "German switch: radios Charakterbogen|Liste, text Ansicht: …")
  local sl2 = UIx.sugList
  local gh
  for _, h in ipairs(sl2.pools.section) do if h._shown and h.data.sec.key == 10 then gh = h end end
  check(gh and gh.label == nil and plain(gh.wornName._text) == UIx.SectionTitle(gh.data.sec) .. " (leer)" and gh.count._text == "1 Verbesserung"
    and sl2.pools.fold[1].text._text:find("^Keine herstellbare Verbesserung: "),
    "German cards: '<Platz> (leer)', '1 Verbesserung', 'Keine herstellbare Verbesserung: …'")
  UIx:SetMemberMode("sheet")
  sh, c = UIx.sheet, UIx.sheet.centre
  sh.slots[5]._scripts.OnClick(sh.slots[5])
  check(c.worn.label._text == "Getragen" and c.best.label._text == "Beste Herstellung" and c.count._text == "2 herstellbare Verbesserungen"
    and c.moreTitle._text == "Weitere Möglichkeiten" and c.craftedLabel._text == "Hergestellt" and c.offer._text == "Anbieten",
    "German sheet: Getragen / Beste Herstellung / 2 herstellbare Verbesserungen / Weitere Möglichkeiten / Hergestellt / Anbieten")
  check(plain(c.stats[1]._text) == "+1% Treffer" and plain(c.stats[2]._text) == "+6 Beweglichkeit", "German stat names: " .. plain(c.stats[1]._text))
  sh.slots[1]._scripts.OnClick(sh.slots[1])
  check(c.none._text == "Keine herstellbare Verbesserung", "German: 'Keine herstellbare Verbesserung'")
  sh.slots[10]._scripts.OnClick(sh.slots[10])
  check(plain(c.tags._text) == "ab Stufe 42 · noch 3", "German level tag: " .. plain(c.tags._text))

  print("== K4: layout of both variants (840x560 / 980x640 / 1600x1000, both languages)")
  local function sheetLayout(UIy, label)
    local fw = UIy.frame
    local R = function(fr) return rectOf(fr, fw) end
    local sh3, c3 = UIy.sheet, UIy.sheet.centre
    local si, sr, cr = R(UIy.sugInset), R(sh3), R(c3)
    local bad = {}
    local function inside(a, b) return a.l >= b.l and a.r <= b.r and a.t >= b.t and a.b <= b.b end
    if not inside(sr, si) then bad[#bad + 1] = "sheet outside the panel " .. rstr(sr) end
    local slots = {}
    for slot, b in pairs(sh3.slots) do
      local r = R(b)
      slots[#slots + 1] = { slot, r }
      if not inside(r, sr) then bad[#bad + 1] = "slot " .. slot .. " outside " .. rstr(r) end
      if overlap(r, cr) then bad[#bad + 1] = "slot " .. slot .. " over the middle panel " .. rstr(r) end
      if r.r - r.l ~= 40 or r.b - r.t ~= 40 then bad[#bad + 1] = "slot " .. slot .. " not 40x40" end
    end
    for i = 1, #slots do for j = i + 1, #slots do
      if overlap(slots[i][2], slots[j][2]) then bad[#bad + 1] = "slots " .. slots[i][1] .. "/" .. slots[j][1] .. " overlap" end
    end end
    -- the middle panel's shown parts: inside it, no two overlapping, everything above its bottom
    local parts = { { "header", c3.header }, { "count", c3.count }, { "worn card", c3.worn } }
    if c3.mode == "upgrade" then
      for _, x in ipairs({ { "best card", c3.best }, { "arrow", c3.arrow } }) do parts[#parts + 1] = x end
      for i = 1, c3.nStats do parts[#parts + 1] = { "stat " .. i, c3.stats[i] } end
      if c3.hasTags then parts[#parts + 1] = { "tags", c3.tags } end
      if c3.offer._shown then parts[#parts + 1] = { "offer", c3.offer } end
      if c3.crafted._shown then parts[#parts + 1] = { "crafted", c3.crafted }; parts[#parts + 1] = { "crafted label", c3.craftedLabel } end
      if c3.nAlts > 0 then parts[#parts + 1] = { "sep", c3.sep }; parts[#parts + 1] = { "more", c3.moreTitle } end
      for i = 1, c3.nAlts do parts[#parts + 1] = { "alt " .. i, c3.alts[i] } end
    else
      parts[#parts + 1] = { "message", c3.none }
    end
    local rects = {}
    for _, p in ipairs(parts) do
      local r = R(p[2])
      rects[#rects + 1] = { p[1], r }
      if not inside(r, cr) then bad[#bad + 1] = p[1] .. " outside the middle " .. rstr(r) .. " in " .. rstr(cr) end
    end
    for i = 1, #rects do for j = i + 1, #rects do
      local a, b = rects[i], rects[j]
      if overlap(a[2], b[2]) and not (a[1] == "sep" or b[1] == "sep") then bad[#bad + 1] = a[1] .. " x " .. b[1] end
    end end
    if c3.contentH > cr.b - cr.t then bad[#bad + 1] = "content " .. c3.contentH .. " > panel " .. (cr.b - cr.t) end
    -- the alternatives' parts inside their row
    for i = 1, c3.nAlts do
      local a = c3.alts[i]
      local ar, nr, gr = R(a), R(a.name), R(a.gain)
      if nr.r > (a.tag._shown and R(a.tag).l or gr.l) then bad[#bad + 1] = "alt " .. i .. " name runs under its tag/gain" end
      if a.offer._shown and gr.r > R(a.offer).l then bad[#bad + 1] = "alt " .. i .. " gain under the Offer button" end
      if R(a.offer).r > ar.r then bad[#bad + 1] = "alt " .. i .. " Offer outside" end
    end
    check(#bad == 0, label .. ": sheet slots inside the panel, the middle panel's parts inside it, nothing overlaps " .. table.concat(bad, "; "))
  end
  for _, loc in ipairs({ "deDE" }) do -- K5: deDE only (the longer texts)
    ns.locale = loc
    UIx.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
    UIx = GCA.UI
    UIx.selected, UIx.autoKey = "Bud Stone", nil
    UIx:SetView("member")
    for _, sz in ipairs({ { 840, 560 }, { 980, 640 } }) do -- K5: 840x560 and 980x640
      UIx.frame:SetSize(sz[1], sz[2]); UIx:Layout()
      for _, slot in ipairs({ 3, 5, 9, 1 }) do
        UIx.sheet.slots[slot]._scripts.OnClick(UIx.sheet.slots[slot])
        sheetLayout(UIx, loc .. " " .. sz[1] .. "x" .. sz[2] .. " slot " .. slot)
      end
      layoutChecks(UIx, UIx.frame, "K4 " .. loc .. " " .. sz[1] .. "x" .. sz[2] .. " (sheet)")
      UIx:SetMemberMode("list")
      layoutChecks(UIx, UIx.frame, "K4 " .. loc .. " " .. sz[1] .. "x" .. sz[2] .. " (list)")
      local okCards = true
      for _, r in ipairs(UIx.sugList.rows) do
        if r._shown and r.textW then
          local showO, showC = r.offer._shown, r.crafted._shown
          local rightW = 6 + (showO and 88 or 0) + (showC and 28 or 0) + 84 + 10
          if r.textW + 72 + rightW ~= UIx.listW or r.textW < 60 then okCards = false end
        end
      end
      check(okCards, "K4 " .. loc .. " " .. sz[1] .. "x" .. sz[2] .. ": every card's texts end at its right block, at least 60 px wide (K6: 16 px indent)")
      UIx:SetMemberMode("sheet")
    end
  end
  ns.locale = "enUS"
  -- German text fit (estimate, as K): the switch buttons, the cards' labels at 840
  local function fits(text, px, per) return #plain(text):gsub("[\128-\191]", "") * per <= px end
  local tooWide = {}
  local function fit(name, text, px, per) if not fits(text, px, per) then tooWide[#tooWide + 1] = name .. " '" .. plain(text) .. "'" end end
  local D = ns.Locales.deDE
  fit("switch sheet", D.MVIEW_SHEET, 100 - 8, 5.6)
  fit("switch list", D.MVIEW_LIST, 56 - 8, 5.6)
  -- 840: the cards' label columns = card width - icon (10 + 40 + 8) - right margin (10; the craft card: gain 74 + 16)
  UIx.frame:SetSize(840, 560); UIx:Layout()
  local shx = UIx.sheet
  fit("worn label", D.SHEET_WORN, shx.wornW - 58 - 10, 5.6)
  fit("best label", D.SHEET_BEST_ENCH, shx.bestW - 58 - 90, 5.6)
  fit("compared label", D.SHEET_PICKED, shx.bestW - 58 - 90, 5.6)
  fit("more title", D.SHEET_MORE, shx.iw, 5.6)
  fit("count", string.format(D.SHEET_COUNT_ENCH, 3), shx.iw - 100, 5.6)
  fit("level tag", string.format(D.LEVEL_TAG, 60, 10), 160, 5.6)
  fit("card label", D.CARDS_WORN, 80, 5.6)
  check(#tooWide == 0, "K4 German text fit at 840x560 (estimate): " .. table.concat(tooWide, "; "))

  print("== K4: fallbacks")
  -- no texture files (GetFileIDFromPath says no): text badge, quality squares instead of WhiteIconFrame
  GetFileIDFromPath = function() return nil end
  UIx.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  UIx.selected, UIx.autoKey = "Bud Stone", nil
  UIx:SetView("member")
  local s12 = UIx.sheet.slots[12]
  check(s12.badgeKind == "text" and s12.badge._text == "+" and s12.badge._shown and not s12.frameArt and s12.qual._SetColorTexture[2] == 1
    and not s12.iconBorder._shown, "no files: badge = a green '+', the quality colour as a square behind the icon")
  UIx:SetMemberMode("list")
  check(UIx.sugList.rows[1].frameArt == "atlas" and UIx.sugList.rows[1].slotBg and UIx.errorCount == errs, "K6 no files: cards keep the reagent-slot atlas (no file needed)")
  UIx:SetMemberMode("sheet")
  GetFileIDFromPath = nil
  -- K6: the big gain in the client's GameFontGreenLarge where it exists
  GameFontGreenLarge = {}
  Frame.SetFontObject = function(self, fo) self._font = fo; fontSet = true end
  UIx.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  check(fontSet and UIx.sheet.centre.best.gain._font == GameFontGreenLarge and UIx.sheet.centre.best.gain.nativeFont == "GameFontGreenLarge", "K6: GameFontGreenLarge exists: the sheet's big gain uses it")
  GameFontGreenLarge, Frame.SetFontObject = nil, nil
  -- button / check templates failing: plain fallbacks with the same API
  local origCF = CreateFrame
  CreateFrame = function(otype, name, parent, template)
    if template == "UIPanelButtonTemplate" or template == "UICheckButtonTemplate" or template == "MinimalCheckboxTemplate" then error("no " .. template) end
    return origCF(otype, name, parent, template)
  end
  local tb = UIx.NewTextButton(UIx.frame, 84, 22, "Offer")
  local cb = UIx.NewCheck(UIx.frame, 22)
  CreateFrame = origCF
  check(tb.plain and tb:GetText() == "Offer" and tb.label._text == "Offer" and tb._w == 84 and tb.edges and cb.plain and cb._w == 22 and cb.edges,
    "button / check-box templates missing: plain button with its own label, bordered box")
  -- StatDiff: nothing reliable -> nil (no stat line), the rest of the card unchanged
  check(UIx.StatDiff(fakeSug()) == nil and UIx.StatDiff(fakeSug({ info = { cstats = {} }, equipped = { name = "x" } })) == nil
    and #UIx.StatDiff(fakeSug({ info = { cstats = { Agility = 2 } } })) == 1, "StatDiff: no stats on a side -> nil; empty slot -> all stats of the new item")
  -- sheet handlers with nothing filled in (fresh window, member view never shown): no error
  UIx.frame:Hide(); GCA.UI.frame = nil; SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  local errs2 = UIx.errorCount
  for _, fr in ipairs({ UIx.sheet.slots[1], UIx.sheet.centre.worn, UIx.sheet.centre.best }) do
    captureTip(); pcall(fr._scripts.OnEnter, fr); pcall(fr._scripts.OnClick, fr, "LeftButton")
  end
  check(UIx.errorCount == errs2, "sheet handlers before any data: no error")
  check(UIx.errorCount == errs2 and badAtlas == 0, "no error reported (K4)")
  UIx.frame:Hide()
  GCA.GetMemberList = origML
  GCA.Print = printFn
  HandleModifiedItemClick = function() end
  IsShiftKeyDown = function() return false end
  ITEM_QUALITY_COLORS = nil
  GCA.db.settings.memberView = nil
  GCA.UI.frame = nil
  templateMode, GCA.IsBrowse = savedTM, savedBrowse
end

check(badAtlas == 0, "SetAtlas was never called for an atlas the client lacks (" .. badAtlas .. ")")
do
  print("== K6: native look (no mockup gimmicks left, atlases from the probe, slot art, fallbacks)")
  local fh = assert(io.open(ROOT .. "UI.lua", "rb"))
  local src = fh:read("*a")
  fh:close()
  local gone = {}
  for _, word in ipairs({ "CreateRing", "CreateModeToggle", "CreateChip", "CreateMemberChip", "SetRingColor",
    "selectBar", "treeLine", "chipBg", "sectionHeader", "rowAlt", "BigFont", "CreateOptionsMenu", "CreateOfflineBox" }) do
    if src:find(word, 1, true) then gone[#gone + 1] = word end
  end
  check(#gone == 0, "K6: no custom circle / segmented control / chip / select-bar / tree-line / Options-popup code left in UI.lua " .. table.concat(gone, ", "))
  -- every atlas UI.lua names: one the in-game probe found in the client's own ProfessionsFrame / CharacterFrame, or one of
  -- the three pre-K6 guarded names (common-dropdown-bg: fallback popups, WhatsTraining Menu.lua; the K1 info icon; K5 classicon-*)
  local PROBE = { ["Profession-Background-Overview"] = 1, ["Profession-Background-Template2"] = 1, ["Professions-Slot-Frame"] = 1,
    ["Professions-Slot-bg"] = 1, ["Professions-background-summarylist"] = 1, ["Professions-skillbar-bg"] = 1, ["Professions-skillbar-frame"] = 1,
    ["UI-Character-Info-GearSlot"] = 1, ["common-dropdown-a-button"] = 1, ["search-highlight"] = 1,
    ["UI-Frame-InnerTopLeft"] = 1, ["UI-Frame-InnerTopRight"] = 1, ["UI-Frame-InnerBotLeftCorner"] = 1, ["UI-Frame-InnerBotRight"] = 1,
    ["_UI-Frame-InnerTopTile"] = 1, ["_UI-Frame-InnerBotTile"] = 1, ["!UI-Frame-InnerLeftTile"] = 1, ["!UI-Frame-InnerRightTile"] = 1,
    ["Skillbar_Fill_Flipbook_Leatherworking"] = 1, ["Skillbar_Flare_Leatherworking"] = 1,
    -- K8: tpl:ProfessionsRecipeListRecipeTemplate / ...CategoryTemplate regions and the Filter reset badge (ProfessionsFrame)
    ["Professions_Recipe_Hover"] = 1, ["Professions_Recipe_Active"] = 1, ["common-button-list-collapseExpand"] = 1,
    ["auctionhouse-ui-filter-redx"] = 1,
    -- K9: the open window's schematic frame and profession card (probe ProfessionsFrame@open)
    ["common-insideframe"] = 1 }
  -- K8: the collapse button's icon is set by the client's mixin at runtime (not in the probe): guarded candidates only
  for _, pair in ipairs(GCA.UI.SKIN.collapseIcon.pairs) do PROBE[pair[1]] = 1; PROBE[pair[2]] = 1 end
  local OLD = { ["common-dropdown-bg"] = 1, ["glueannouncementpopup-icon-info"] = 1, ["classicon-"] = 1 }
  local unknown, n = {}, 0
  for _, pat in ipairs({ 'SetAtlasSafe%([^,]+, "([^"]+)"', 'HasAtlas%("([^"]+)"%)', 'atlas = "([^"]+)"', 'INFO_ATLAS = "([^"]+)"' }) do
    for name in src:gmatch(pat) do
      n = n + 1
      if not (PROBE[name] or OLD[name]) then unknown[#unknown + 1] = name end
    end
  end
  check(n >= 12 and #unknown == 0, "K6: every atlas named in UI.lua (" .. n .. ") is from the probe or an older guarded one " .. table.concat(unknown, ", "))
  -- the sheet's gear slots: the character window's own slot look
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  local s5 = UIx.sheet.slots[5]
  check(s5.gearArt and s5.bg._atlas == "UI-Character-Info-GearSlot" and s5.bg._w == 59 and s5.frameArt == "file"
    and s5.iconBorder._tex == "Interface\\Common\\WhiteIconFrame" and s5.hl._tex == UIx.TEX.iconHL and s5.selKind == "file",
    "K6 sheet slot: UI-Character-Info-GearSlot behind (55/37 scaled), WhiteIconFrame border, ButtonHilight-Square hover + kept on when selected")
  check(UIx.sheet.centre.edges == nil and UIx.sheet.centre.bg == nil and UIx.sheet.centre.best.edges == nil and UIx.sheet.centre.best.tint == nil,
    "K6 sheet: no hand-drawn boxes / green tint around the middle panel and the cards")
  -- crafted boxes: MinimalCheckboxTemplate; Offer: the red UIPanelButtonTemplate button
  local cb, tb = UIx.NewCheck(UIx.frame, 22), UIx.NewTextButton(UIx.frame, 84, 22, "x")
  check(cb.template == "MinimalCheckboxTemplate" and not cb.plain and not tb.plain, "K6: check boxes from MinimalCheckboxTemplate, buttons from UIPanelButtonTemplate")
  -- K8: no custom row boxes / pills / extra highlights left: the K5/K6 craft-row build (caret, member text run, icon
  -- per row, expand state) is gone; list rows draw only the recipe row's own art (no colour textures, no borders)
  check(UIx.MemberRun == nil and UIx.expanded == nil and UIx.NEED_RIGHT_W == nil and not src:find("caretText", 1, true)
    and not src:find("membersShown", 1, true), "K8: no member text runs / carets / expand state left (the detail panel lists the members)")
  local boxy = {}
  local function scanRow(name, b)
    for _, t in ipairs(descendants(b)) do
      if t._SetColorTexture or t.edges or t._backdrop then boxy[#boxy + 1] = name end
    end
    if b.edges or b._backdrop then boxy[#boxy + 1] = name end
  end
  scanRow("member row", UIx.memberList.rows[1])
  scanRow("group header", UIx.memberList.pools.group[1])
  if UIx.needsList.rows[1] then scanRow("craft row", UIx.needsList.rows[1]) end
  if UIx.needsList.pools.cat then scanRow("slot category", UIx.needsList.pools.cat[1]) end
  check(UIx.memberList.rows[1] and #boxy == 0, "K8: list rows and category headers draw no colour boxes / borders (atlas art only) " .. table.concat(boxy, ", "))
  -- K8 detailBorder is pluggable: a NineSliceUtil layout, a piece list, else the inner border
  local skinDB = UIx.SKIN.detailBorder
  UIx.SKIN.detailBorder = { pieces = { { key = "TopLeftCorner", atlas = "UI-Frame-InnerTopLeft", w = 12, p = { "TOPLEFT", -2, 2 } },
    { key = "TopRightCorner", atlas = "UI-Frame-InnerTopRight", w = 12, p = { "TOPRIGHT", 2, 2 } },
    { key = "TopEdge", atlas = "_UI-Frame-InnerTopTile", h = 5, a = { "TOPLEFT", "TopLeftCorner", "TOPRIGHT" }, b = { "TOPRIGHT", "TopRightCorner", "TOPLEFT" }, horiz = true } } }
  local pb = UIx.AddDetailBorder(CreateFrame("Frame", nil, UIParent))
  check(pb.how == "pieces" and pb.role == "detailBorder" and pb.TopLeftCorner._w == 12 and pb.TopEdge._h == 5 and pb.TopLeftCorner._points[1][4] == -2,
    "K8 detailBorder: a piece list from the skin (sizes / offsets per piece)")
  UIx.SKIN.detailBorder = { pieces = { { key = "TopLeftCorner", atlas = "NotAnAtlas-K8", p = { "TOPLEFT", 0, 0 } } } }
  local pf = UIx.AddDetailBorder(CreateFrame("Frame", nil, UIParent))
  check(pf.how == "atlas" and pf.role == "detailBorder" and pf.TopLeftCorner._atlas == "UI-Frame-InnerTopLeft", "K8 detailBorder: a missing piece atlas -> the inner border")
  NineSliceUtil = { ApplyLayoutByName = function(f, name) if name == "K8TestLayout" then f.TopLeftCorner = { layout = name } else error("no layout") end end }
  UIx.SKIN.detailBorder = { layout = "K8TestLayout" }
  local pl = UIx.AddDetailBorder(CreateFrame("Frame", nil, UIParent))
  check(pl.how == "layout" and pl.TopLeftCorner.layout == "K8TestLayout", "K8 detailBorder: a NineSliceUtil layout name from the skin")
  UIx.SKIN.detailBorder = { layout = "Missing" }
  local pm = UIx.AddDetailBorder(CreateFrame("Frame", nil, UIParent))
  check(pm.how == "atlas" and pm.role == "detailBorder", "K8 detailBorder: an unknown layout -> the inner border")
  NineSliceUtil = nil
  UIx.SKIN.detailBorder = skinDB
  -- K8 round detail icon: masked + gold ring where the client has masks and the files
  local rf = CreateFrame("Button", nil, UIParent)
  local masked
  rf.CreateMaskTexture = function(self) local m = Tex(); m._parent = self; return m end
  local origCT = Frame.CreateTexture
  Frame.CreateTexture = function(self, ...) local t = origCT(self, ...); t.AddMaskTexture = function(tt, m) masked = m end; return t end
  UIx.AddRoundIcon(rf, 46)
  Frame.CreateTexture = origCT
  check(rf.iconShape == "round" and masked == rf.mask and rf.mask._tex == "Interface\\CharacterFrame\\TempPortraitAlphaMask" and rf.ring._tex == "Interface\\Common\\GoldRing"
    and rf.ring._w == 57 and rf.icon._w == 46, "K8 round icon: TempPortraitAlphaMask on the icon, GoldRing 57 px around 46 px (FDJ's 37/30)")
  local sq = CreateFrame("Button", nil, UIParent)
  UIx.AddRoundIcon(sq, 46)
  check(sq.iconShape == "square" and sq.iconBorder._atlas == "Professions-Slot-Frame", "K8 round icon: no mask API -> the square reagent-slot icon")
  UIx.frame:Hide()
end

do
  print("== K7: where to get missing recipes (CraftersJournal optional) + inner border")
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  local UIx = GCA.UI
  local Src = UIx.Src
  local cur = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE" }
  local function show(d, c)
    UIx.current = c or cur
    UIx.sugList:SetData({ d })
    return UIx.sugList.rows[1]
  end
  -- 1. CJ missing: coarse labels, trainer with the skill from our data
  _G.CraftersJournal = nil
  Src.Reset()
  local dT = fakeSug({ known = false })
  local dP = fakeSug({ known = false, cand = { spellID = 999001, itemID = 4244, recipe = { skill = 120, src = "pattern", r = {} } } })
  check(plain(UIx.SourceLine(dT, cur)) == "Trainer (skill 100)" and plain(UIx.SourceLine(dP, cur)) == "Pattern"
    and UIx.SourceLine(fakeSug(), cur) == nil, "K7 no CJ: 'Trainer (skill 100)' / 'Pattern', known recipe -> no line")
  captureTip()
  Src.AddTooltip(UIx.SourceInfo(dP, cur))
  check(tipText():find("Crafter's Journal", 1, true) and not tipText():find("Right-click", 1, true),
    "K7 no CJ: tooltip points at Crafter's Journal, no waypoint hint")
  -- 2. CJ present (fake with CJ's shapes): vendor with coordinates, drop without, quest
  local calls = {}
  local NPCS = {
    [101] = { name = "Androd Fadran", side = "A", map = 1417, x = 0.45, y = 0.6 },
    [102] = { name = "Far Vendor", side = "A", map = 1417, x = 0.1, y = 0.1 },
    [201] = { name = "Defias Bandit", side = "", area = 40 },
  }
  local WP = {
    NPC = function(id) return NPCS[id] end,
    ZoneName = function(npc) return npc.map and "Arathi Highlands" or "Westfall" end,
    NPCLevel = function(id) return id == 201 and "12-14" or nil end,
    Vendors = function(item) return item == 5000 and { 101, 102 } or {} end,
    Usable = function(ids) return ids end,
    Nearest = function(ids) return ids[1] end,
    QuestsFor = function() return {} end,
    Drops = function(item) return item == 5000 and { npcs = { 201 } } or nil end,
    Trainers = function() return {} end,
    SetWaypoint = function(id) calls[#calls + 1] = id; return true end,
  }
  _G.CraftersJournal = { Data = { Leatherworking = { recipes = { [999001] = { scroll = 5000, scrollPrice = 12500, rep = { 59, 6 } } } } },
    Waypoints = WP, RepMet = function() return false end, FactionName = function(_, id) return "Thorium Brotherhood" end,
    StandingName = function(n) return "Honored" end }
  Src.Reset()
  local line = plain(UIx.SourceLine(dP, cur))
  check(line == "Vendor: Androd Fadran (Arathi Highlands)  +1 more", "K7 CJ: best source + '+n more': " .. line)
  local info = UIx.SourceInfo(dP, cur)
  check(info.cj and info.scroll == 5000 and info.canWaypoint and info.list[2].kind == "drop" and info.list[2].npc.map == nil,
    "K7 CJ: pattern item, vendor with coordinates, drop without")
  captureTip()
  Src.AddTooltip(info)
  local t = tipText()
  check(t:find("Vendor: Androd Fadran | Arathi Highlands 45, 60", 1, true) and t:find("Drop: Defias Bandit (12-14) | Westfall", 1, true)
    and t:find("Requires Honored with Thorium Brotherhood", 1, true) and t:find("+1 more vendors", 1, true)
    and t:find("show it on the map", 1, true) and t:find("Shift-right-click", 1, true),
    "K7 tooltip: vendor + coords, drop + level/zone, reputation, more vendors, click hints")
  -- 3. waypoint offered only with coordinates
  local entries = Src.MenuEntries(info)
  check(#entries == 2 and entries[1].waypoint and entries[1].waypoint.name == "Androd Fadran" and entries[2].waypoint == nil,
    "K7 menu: one waypoint (vendor with coordinates; not the drop without) + 'Link pattern'")
  entries[1].fn()
  check(calls[1] == 101, "K7 waypoint goes through CJ's WP.SetWaypoint(npcID)")
  -- native fallback when CJ's helper is gone
  WP.SetWaypoint = nil
  local native = {}
  C_Map = { SetUserWaypoint = function(p) native.p = p end, CanSetUserWaypointOnMap = function() return true end }
  UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) native.st = v end }
  check(Src.SetWaypoint(info.list[1].npc) and native.p and native.p[1] == 1417 and native.p[2] == 0.45 and native.st == true,
    "K7 waypoint fallback: C_Map.SetUserWaypoint(UiMapPoint 1417 / 0.45 / 0.6) + super-track")
  check(Src.SetWaypoint(info.list[2].npc) == false, "K7 no coordinates -> no waypoint")
  C_Map, UiMapPoint, C_SuperTrack = nil, nil, nil
  -- menu: MenuUtil context menu; none -> first entry directly; nothing to offer -> false
  local made
  MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { items = {} }
    function root:CreateTitle(x) self.title = x end
    function root:CreateButton(x) self.items[#self.items + 1] = x end
    gen(owner, root); made = root
  end }
  check(Src.Menu(UIParent, info, "Vest") and made and made.title == "Vest" and #made.items == 2
    and made.items[1] == "Show on map: Androd Fadran (vendor)", "K14 right-click menu via MenuUtil.CreateContextMenu (show on map)")
  -- K14: "show on the map" = waypoint (CJ's helper / the client's) + the world map opened on the NPC's map
  local openedMap
  OpenWorldMap = function(id) openedMap = id end
  local vn = info.list[1].npc
  Src.ShowOnMap(vn)
  check(openedMap == vn.map, "K14: clicking a source opens the world map on its zone (" .. tostring(openedMap) .. ")")
  OpenWorldMap = nil
  check(Src.ShowOnMap({ name = "x" }) == false, "K14: no coordinates -> nothing happens")
  MenuUtil = nil
  check(Src.Menu(UIParent, { list = {} }) == false, "K7 no coordinates and no pattern -> no menu")
  -- right-click on a known row is swallowed (never runs the left-click action), left click passes through
  check(UIx.SourceClick(UIParent, "RightButton", fakeSug(), cur) == true and UIx.SourceClick(UIParent, "LeftButton", dP, cur) == false,
    "K7 SourceClick: right-click handled, left click not")
  -- 4. CJ erroring / renamed: no error, coarse fallback
  _G.CraftersJournal = { Data = setmetatable({}, { __index = function() error("boom") end }), Waypoints = WP }
  Src.Reset()
  check(plain(UIx.SourceLine(dP, cur)) == "Pattern" and plain(UIx.SourceLine(dT, cur)) == "Trainer (skill 100)", "K7 CJ data erroring -> coarse label")
  WP.Vendors = function() error("renamed internals") end
  WP.NPC = nil
  _G.CraftersJournal = { Data = { Leatherworking = { recipes = { [999001] = { scroll = 5000 } } } }, Waypoints = WP }
  Src.Reset()
  local ok = pcall(UIx.SourceLine, dP, cur)
  check(ok and UIx.SourceInfo(dP, cur).cj and plain(UIx.SourceLine(dP, cur)) == "Pattern", "K7 CJ functions erroring/missing -> no error, 'Pattern'")
  _G.CraftersJournal = { Data = 5 }
  Src.Reset()
  check(Src.CJ() == nil and plain(UIx.SourceLine(dP, cur)) == "Pattern", "K7 CJ renamed (no Data/Waypoints tables) -> treated as missing")
  _G.CraftersJournal = nil
  Src.Reset()
  -- 5. the grey 'Not learned' tag + the card's source line (+10 px)
  local tags = UIx.CraftTags(dT, cur)
  local tag
  for _, x in ipairs(tags) do if x[1] == "Not learned" then tag = x end end
  check(tag and tag[2] == UIx.COLORS.notLearned and UIx.COLORS.notLearned == "|cff9d9d9d", "K7 unlearned tag: grey 'Not learned'")
  local b = show(dT)
  check(not b.hasSource and b.source == nil and b.nl._shown and plain(b.nl.text._text) == "Not learned"
    and b.nl.text._text:find(UIx.COLORS.notLearnedTag, 1, true) and b._SetHeight[1] == 50,
    "user 2026-11-15: unlearned card = red 'Not learned' button, no third source line, 50 px")
  tip, hyper = {}, {}
  b.nl._scripts.OnEnter(b.nl)
  check(tipText():find("Not learned", 1, true) and tipText():find("Trainer", 1, true),
    "hovering 'Not learned' shows where to get the recipe: " .. tipText():gsub("\n", " | "))
  local okClick = pcall(b.nl._scripts.OnClick, b.nl, "LeftButton")
  local okRight = pcall(b.nl._scripts.OnClick, b.nl, "RightButton")
  check(okClick and okRight, "clicking 'Not learned' (left: map marker / right: menu) raises no error")
  b = show(fakeSug())
  check(not b.hasSource and not b.nl._shown and b._SetHeight[1] == 50, "known recipe -> no 'Not learned' button, 50 px")
  -- 6. format strings of the new keys are well-formed in German too
  local de = ns.Locales.deDE
  check(string.format(de.SRC_LINE_VENDOR, "A", "B") == "Händler: A (B)" and string.format(de.SRC_LINE_TRAINER_HAVE, 170, 150) == "Lehrer (Fertigkeit 170, du hast 150)"
    and de.FILTER_UNLEARNED == "Fehlende Rezepte zeigen" and de.NOT_LEARNED == "Nicht erlernt", "K7 German texts")
  -- 7. inner border (lead): every native inner panel has the 8-piece NineSlice from the probe atlases
  local inset = UIx.frame and (UIx.needsInset or nil)
  local nsf = UIx.AddInnerBorder(CreateFrame("Frame", nil, UIParent))
  check(nsf and nsf.how == "atlas" and nsf.TopLeftCorner._atlas == "UI-Frame-InnerTopLeft" and nsf.RightEdge._atlas == "!UI-Frame-InnerRightTile"
    and nsf.BottomLeftCorner._points[1][5] == -1 and nsf.TopEdge._h == 3 and nsf.LeftEdge._w == 3,
    "K7 inner border: 6x6 corners (bottom at y -1), 3 px tiles, probe atlases")
  NineSliceUtil = { ApplyLayoutByName = function(f, name) f.TopLeftCorner = { layout = name } end }
  local nsu = UIx.AddInnerBorder(CreateFrame("Frame", nil, UIParent))
  check(nsu.how == "util" and nsu.TopLeftCorner.layout == "InsetFrameTemplate", "K7 inner border: NineSliceUtil 'InsetFrameTemplate' layout when present")
  NineSliceUtil = nil
  -- 8. rank bar (lead): per-profession fill flipbook + flare when the atlas info has texcoords
  local origInfo = C_Texture.GetAtlasInfo
  C_Texture.GetAtlasInfo = function(name)
    local i = origInfo(name)
    if i and name:find("^Skillbar_") then i.leftTexCoord, i.rightTexCoord, i.topTexCoord, i.bottomTexCoord = 0.1, 0.9, 0, 1 end
    if name == "Skillbar_Fill_Flipbook_Tailoring" then return { width = 1, height = 1, file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end
    return i
  end
  local rb = UIx.CreateProfessionPicker and UIx.CreateProfessionPicker(UIx.frame, UIx.frame)
  if rb then
    rb:SetSkill("Lederverarbeitung 150/300", 150, 300, "Leatherworking")
    local tc = rb.fill._SetTexCoord
    check(rb.barKind == "atlas" and rb.fill._atlas == "Skillbar_Fill_Flipbook_Leatherworking" and rb.flare._atlas == "Skillbar_Flare_Leatherworking"
      and rb.clip and rb.fill._w == UIx.PROF_BAR_W - 10 and math.abs(rb.clip._w - (UIx.PROF_BAR_W - 10) * 0.5) < 1e-9
      and tc and math.abs(tc[1] - 0.1) < 1e-9 and math.abs(tc[2] - 0.5) < 1e-9 and math.abs(tc[4] - 1 / 30) < 1e-9
      and rb.flare._shown and rb.flare._points[1][2] == rb.clip,
      "K7/K8 rank bar: LW flipbook fill at full width in a clipping frame cut to 50 %, one frame (row 1 of 30, column 1 of 2), flare at the cut")
    -- K8: the FlipBook animation (rows 30, columns 2, 60 frames, 2 s, once) where the client has animation groups
    local anim = {}
    local fakeAG = { Play = function() anim.played = (anim.played or 0) + 1 end, Stop = function() end, SetLooping = function(_, v) anim.loop = v end,
      CreateAnimation = function(_, kind)
        anim.kind = kind
        return { SetFlipBookRows = function(_, v) anim.rows = v end, SetFlipBookColumns = function(_, v) anim.cols = v end,
          SetFlipBookFrames = function(_, v) anim.frames = v end, SetDuration = function(_, v) anim.dur = v end }
      end }
    local origCT2 = Frame.CreateTexture
    Frame.CreateTexture = function(self, ...) local t = origCT2(self, ...); t.CreateAnimationGroup = function() return fakeAG end; return t end
    local rb2 = UIx.CreateProfessionPicker(UIx.frame, UIx.frame)
    Frame.CreateTexture = origCT2
    rb2:SetSkill("x", 150, 300, "Leatherworking"); rb2:SetSkill("x", 150, 300, "Leatherworking")
    check(rb2.anim == fakeAG and anim.kind == "FlipBook" and anim.rows == 30 and anim.cols == 2 and anim.frames == 60 and anim.dur == 2
      and anim.loop == "NONE" and anim.played == 1, "K8 rank bar: FlipBook 30x2, 60 frames, 2 s, played once per new rank (not on every refresh)")
    rb2:SetSkill("x", 151, 300, "Leatherworking")
    check(anim.played == 2, "K8 rank bar: a new rank plays it again")
    rb:SetSkill("Schneiderei 300/300", 300, 300, "Tailoring")
    check(rb.fill._atlas == "Skillbar_Fill_Flipbook_Tailoring" and rb.flare._atlas == "Skillbar_Flare_Leatherworking" and not rb.flare._shown,
      "K7 rank bar: the profession's own fill when the client has it, LW flare as fallback, no flare at 100 %")
  else
    check(false, "K7 rank bar: UI.CreateProfessionPicker exported for the test")
  end
  C_Texture.GetAtlasInfo = origInfo
  UIx.frame:Hide()
end

-- W (weapons): weapon rows reach the list sections, the guild-needs categories and the character sheet; texts
-- "(off hand)", "needs an off hand", "replaces both hands", "Speed 2.60 → 3.40" (deDE "Tempo 2,60 → 3,40"); Offer as for armour
do
  print("== W: weapon rows in the list, the sheet and guild needs")
  local errBefore = GCA.UI.errorCount or 0
  local E = { key = "kw", set = { weights = { Strength = 1, MainHandDps = 2, TwoHandDps = 2, OffHandDps = 1 }, source = {} },
    raw = { source = { kind = "sim", minLevel = 30, maxLevel = 40 } }, class = "WARRIOR", spec = "FURY", level = 40, share = 0.5, t = 1 }
  local function eq(name, cstats, speed) return { name = name, quality = 2, icon = 135, link = "|Hitem:77|h[" .. name .. "]|h", cstats = cstats, speed = speed, scores = {} } end
  local eqInfo = { [16] = eq("Old Sword", { Strength = 2, MainHandDps = 15 }, 2.6), [17] = eq("Old Left Sword", { MainHandDps = 10 }, 2.4),
    [18] = eq("Old Gun", { Agility = 1, RangedDps = 8 }, 3.0) }
  local items = { [16] = "item:77", [17] = "item:78", [18] = "item:79" }
  local function rec() return { skill = 100, src = "trainer", r = {} } end
  local twoH = fakeSug({ e = E, slot = 16, points = 9, pct = 0.3, bothHands = true, equipped = { name = "Old Sword + Old Left Sword", quality = 2,
      cstats = { Strength = 2, MainHandDps = 15, OffHandDps = 10 }, speed = 2.6 },
    cand = { spellID = 9101, itemID = 9101, recipe = rec() }, info = { name = "Craft Greatsword", quality = 3, icon = "x", minLevel = 30,
      link = "|Hitem:9101|h[Craft Greatsword]|h", cstats = { Strength = 20, TwoHandDps = 45 }, speed = 3.4 } })
  local offH = fakeSug({ e = E, slot = 17, hand = "off", points = 4, pct = 0.1, equipped = eqInfo[17],
    cand = { spellID = 9102, itemID = 9102, recipe = rec() }, info = { name = "Craft Sword", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9102|h[Craft Sword]|h", cstats = { Strength = 8, MainHandDps = 30 }, speed = 2.6 } })
  local partner = fakeSug({ e = E, slot = 16, status = "needs-partner", tier = 2, pct = nil, points = 3, equipped = eqInfo[16],
    cand = { spellID = 9103, itemID = 9103, recipe = rec() }, info = { name = "Lonely Sword", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9103|h[Lonely Sword]|h", cstats = { Strength = 4, MainHandDps = 20 } } })
  local gun = fakeSug({ e = E, slot = 18, points = 2, pct = 0.2, equipped = eqInfo[18],
    cand = { spellID = 9104, itemID = 9104, recipe = rec() }, info = { name = "Craft Gun", quality = 2, icon = "x", minLevel = 30,
      link = "|Hitem:9104|h[Craft Gun]|h", cstats = { Agility = 5, RangedDps = 30 }, speed = 3.0 } })
  local UIx = GCA.UI
  -- texts
  check(UIx.RowPair(offH) == "off hand" and UIx.RowPair(twoH) == nil and UIx.RowPair({ kind = "item", slot = 12 }) == "Ring 2",
    "RowPair: 'off hand' for a one-hander scored in the off hand; rings keep 'Ring 2'")
  local tags = {}
  for _, t in ipairs(UIx.CraftTags(partner)) do tags[#tags + 1] = t[1] end
  local tags2 = {}
  for _, t in ipairs(UIx.CraftTags(twoH)) do tags2[#tags2 + 1] = t[1] end
  local shieldP = fakeSug({ e = E, slot = 17, status = "needs-partner", equipped = eqInfo[16] })
  check(table.concat(tags, "|"):find("needs an off hand", 1, true) and table.concat(tags2, "|"):find("replaces both hands", 1, true)
    and UIx.CraftTags(shieldP)[1][1] == "needs a main hand", "tags: 'needs an off hand' / 'needs a main hand' / 'replaces both hands'")
  local d1 = UIx.StatDiff(twoH)
  check(d1[1].speed == 3.4 and UIx.StatText(d1[1]) == "Speed 2.60 → 3.40", "stat differences: speed first, 'Speed 2.60 → 3.40': " .. UIx.StatText(d1[1]))
  local dps = {}
  for _, r in ipairs(d1) do if r.key == "TwoHandDps" or r.key == "MainHandDps" or r.key == "OffHandDps" then dps[#dps + 1] = UIx.StatText(r) end end
  check(table.concat(dps, ", "):find("+45 DPS", 1, true), "DPS lines in the stat differences: " .. table.concat(dps, ", "))
  local same = fakeSug({ e = E, equipped = eq("Same", { MainHandDps = 1 }, 2.6), info = { name = "S", cstats = { MainHandDps = 2 }, speed = 2.6 } })
  check(UIx.StatDiff(same)[1].key ~= "Speed" and UIx.StatDiff(partner)[1].key ~= "Speed", "same speed / no speed read: no speed line")
  -- the list: sections 16/17/18 with their rows and the weapon section names
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx.current = { key = "Bud Stone", online = true, prof = "Blacksmithing", level = 40, class = "WARRIOR" }
  UIx.sugList:SetData(UIx.SectionRows(fakeSections({ [16] = { twoH, partner }, [17] = { offH }, [18] = { gun } })))
  local secs, titles = {}, {}
  for _, x in ipairs(UIx.sugList.pools.section) do if x._shown ~= false and x.data and x.data.sec then secs[x.data.sec.key] = x; titles[x.data.sec.key] = UIx.SectionTitle(x.data.sec) end end
  check(secs[16] and secs[17] and secs[18] and titles[16] == "Main Hand" and titles[17] == "Off Hand" and titles[18] == "Ranged",
    "list: weapon sections Main Hand / Off Hand / Ranged: " .. tostring(titles[16]) .. "/" .. tostring(titles[17]) .. "/" .. tostring(titles[18]))
  local cards = {}
  for _, b in ipairs(UIx.sugList.rows) do if b.data and b.data.cand then cards[b.data.cand.itemID] = b end end
  check(cards[9102] and plain(cards[9102].title._text) == "Craft Sword (off hand)" and cards[9102].offer._shown,
    "card: 'Craft Sword (off hand)', Offer shown as for armour")
  check(cards[9103] and plain(cards[9103].sub._text):find("needs an off hand", 1, true), "card: the needs-partner row says 'needs an off hand': " .. plain(cards[9103] and cards[9103].sub._text))
  -- user 2026-11-15: no stat differences on cards (speed included); the character sheet keeps them
  check(cards[9101] and not plain(cards[9101].sub._text):find("Speed", 1, true) and plain(cards[9101].sub._text):find("replaces both hands", 1, true),
    "card: second line = 'replaces both hands' (no speed/stat changes on cards): " .. plain(cards[9101] and cards[9101].sub._text))
  check(UIx.NeedsCatTitle(16) == "Main Hand" and UIx.NeedsCatTitle(17) == "Off Hand" and UIx.NeedsCatTitle(18) == "Ranged", "guild needs categories Main Hand / Off Hand / Ranged")
  captureTip(); cards[9101]._scripts.OnEnter(cards[9101])
  check(plainTip("9101"), "K17: a weapon row's tooltip = the item + only the stat-change block: " .. tipText())
  -- German
  ns.locale = "deDE"
  check(UIx.StatText(UIx.StatDiff(twoH)[1]) == "Tempo 2,60 → 3,40" and UIx.NeedsCatTitle(16) == "Haupthand" and UIx.NeedsCatTitle(17) == "Nebenhand"
    and UIx.NeedsCatTitle(18) == "Distanz" and UIx.RowPair(offH) == "Nebenhand" and UIx.CraftTags(partner)[1][1] == "braucht eine Nebenhand"
    and UIx.CraftTags(twoH)[1][1] == "ersetzt beide Hände", "German: 'Tempo 2,60 → 3,40', Haupthand/Nebenhand/Distanz, 'braucht eine Nebenhand', 'ersetzt beide Hände'")
  ns.locale = "enUS"
  UIx.frame:Hide()
  -- the sheet: weapon slots get their rows (badge, featured craft, stat lines incl. speed)
  local function member(key, rowsBy)
    local list = {}
    for _, rows in pairs(rowsBy) do for _, r in ipairs(rows) do list[#list + 1] = r end end
    table.sort(list, GCA.SuggestionOrder)
    list.sections = GCA:BuildSections(rowsBy, {}, items, eqInfo, {}, E)
    return { key = key, online = true, class = "WARRIOR", level = 40, prof = "Blacksmithing", state = "ok", weights = E,
      member = { items = items, time = time(), source = "inspect" }, suggestions = list, best = list[1], knownCount = #list,
      spec = "FURY", specHow = "manual" }
  end
  local wm = member("Wes Arms", { [16] = { twoH, partner }, [17] = { offH }, [18] = { gun } })
  local origML = GCA.GetMemberList
  GCA.GetMemberList = function() return { wm } end
  GCA.UI.frame = nil
  SlashCmdList.GUILDCRAFTADVISOR(""); advance(1)
  UIx = GCA.UI
  UIx:SetMemberMode("sheet")
  UIx.selected, UIx.autoKey = "Wes Arms", nil
  UIx:SetView("member")
  local sh, c = UIx.sheet, UIx.sheet.centre
  check(sh.slots[16].badge._shown and sh.slots[17].badge._shown and sh.slots[18].badge._shown and not sh.slots[5].badge._shown,
    "sheet: upgrade badges on main hand, off hand and ranged")
  sh.slots[16]._scripts.OnClick(sh.slots[16])
  local st = {}
  for i = 1, c.nStats do st[i] = plain(c.stats[i]._text) end
  check(UIx.sheetSlot == 16 and c.featured == twoH and plain(c.best.name._text) == "Craft Greatsword" and st[1] == "Speed 2.60 → 3.40"
    and plain(c.tags._text):find("replaces both hands", 1, true), "sheet main hand: the greatsword featured, speed line first, 'replaces both hands': " .. table.concat(st, ", "))
  sh.slots[17]._scripts.OnClick(sh.slots[17])
  check(c.featured == offH and c.offer._shown, "sheet off hand: the off-hand one-hander, Offer shown")
  check((UIx.errorCount or 0) == errBefore, "W: no error reported: " .. tostring(GCA.db.lastError and GCA.db.lastError.msg or ""))
  UIx.frame:Hide()
  GCA.GetMemberList = origML
  UIx:SetMemberMode("list")
end

print("== Keys looked up that the mock lacks (nil here; fine if the addon checks for them):")
local names = {}
for k in pairs(missing) do names[#names + 1] = k end
table.sort(names)
print("  " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
print(("%d passed, %d failed"):format(passes, fails))
print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
