local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local H = {}
local env = setmetatable({}, { __index = _G })
local missing = {}
local check = Kit.check
local sched = Kit.Scheduler({ start = 1000 })
local function advance(sec) sched:advance(sec) end

local Frame = {}
local FrameMT = { __index = function(t, k)
  if Frame[k] then return Frame[k] end
  if type(k) == "string" and k:match("^%u") then missing[k] = (missing[k] or 0) + 1 end
  return nil
end }
local function New(otype, parent, name)
  local o = setmetatable({ _type = otype or "Frame", _parent = parent, _children = {}, _scripts = {}, _events = {},
    _shown = true, _w = 0, _h = 0, _points = {}, _level = parent and (parent._level or 0) + 1 or 0,
    _strata = parent and parent._strata or "MEDIUM", _scale = 1 }, FrameMT)
  if parent and parent._children then table.insert(parent._children, o) end
  if name then env[name] = o; o._name = name end
  return o
end
local function Tex()
  local t = New("Texture")
  t.SetAtlas = function(self, a, useSize)
    if not env.C_Texture.GetAtlasInfo(a) then H.badAtlas = H.badAtlas + 1 end
    self._atlas, self._atlasSize = a, useSize
  end
  return t
end
for _, m in ipairs({ "SetTexCoord", "SetVertexColor", "SetDesaturated", "SetJustifyH",
  "SetHighlightTexture", "SetNormalTexture", "SetPushedTexture", "SetUserPlaced", "RegisterForClicks", "RegisterForDrag", "SetToplevel", "SetClampedToScreen", "SetMovable",
  "EnableMouse", "StartMoving", "StopMovingOrSizing", "SetScrollChild", "SetTextColor", "SetFixedFrameStrata",
  "SetFixedFrameLevel", "SetChecked", "SetBackdropColor", "SetBackdropBorderColor",
  "SetColorTexture", "SetAllPoints",
  "SetOrientation", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture",
  "SetWordWrap", "SetMaxLines", "SetNonSpaceWrap", "SetClipsChildren", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
  "SetCursorPosition",
  "SetBlendMode", "EnableMouseWheel", "SetDrawLayer" }) do
  Frame[m] = function(self, ...) self["_" .. m] = { ... } end
end
function Frame:SetTexture(t) self._tex = t end
function Frame:GetTexture() return self._tex end
function Frame:SetText(t) self._text = t end
function Frame:SetValue(v) local old = self._value; self._value = v; if old ~= v and self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end
function Frame:GetValue() return self._value end
function Frame:SetVerticalScroll(v) self._vscroll = v end
function Frame:GetVerticalScroll() return self._vscroll or 0 end
function Frame:GetText() return self._text end
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
function Frame:SetResizable(v) self._resizable = v end
function Frame:StartSizing(point) self._sizingFrom = point end
function Frame:SetResizeBounds(...) self._bounds = { ... } end
function Frame:GetLeft()
  local p = self._points[1]
  if self._parent == env.UIParent and p then
    if p[1] == "CENTER" then return (env.UIParent._w - self._w) / 2 end
    if p[1] == "TOPLEFT" and p[2] == env.UIParent and p[3] == "BOTTOMLEFT" then return p[4] end
  end
  return self._left
end
function Frame:GetTop()
  local p = self._points[1]
  if self._parent == env.UIParent and p then
    if p[1] == "CENTER" then return (env.UIParent._h + self._h) / 2 end
    if p[1] == "TOPLEFT" and p[2] == env.UIParent and p[3] == "BOTTOMLEFT" then return p[5] end
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
function Frame:RegisterEvent(ev) self._events[ev] = true end
function Frame:UnregisterEvent(ev) self._events[ev] = nil end
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
function Frame:GetChildren() return env.unpack(self._children) end
function Frame:GetEffectiveScale() return self._scale end
function Frame:GetCenter() return self._cx, self._cy end
function Frame:IsForbidden() return self._forbidden or false end
function Frame:GetChecked() return self._checked end
function Frame:SetBackdrop(b) self._backdrop = b end
function Frame:SetChecked(v) self._checked = v and true or false end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha or 1 end
function Frame:GetParent() return self._parent end
function Frame:SetEnabled(on) self._enabled = on and true or false end
function Frame:LockHighlight() self._locked = true end
function Frame:UnlockHighlight() self._locked = false end
H.badAtlas = 0
H.atlasMode = "ok"
local ATLASES = { ["Profession-Background-Overview"] = true, ["Profession-Background-Template2"] = true,
  ["Professions-Slot-Frame"] = true, ["common-dropdown-bg"] = true,
  ["Professions-Slot-bg"] = true, ["Professions-background-summarylist"] = true, ["search-highlight"] = true,
  ["Professions-skillbar-bg"] = true, ["Professions-skillbar-frame"] = true, ["common-dropdown-a-button"] = true,
  ["UI-Character-Info-GearSlot"] = true,
  ["UI-Frame-InnerTopLeft"] = true, ["UI-Frame-InnerTopRight"] = true, ["UI-Frame-InnerBotLeftCorner"] = true,
  ["UI-Frame-InnerBotRight"] = true, ["_UI-Frame-InnerTopTile"] = true, ["_UI-Frame-InnerBotTile"] = true,
  ["!UI-Frame-InnerLeftTile"] = true, ["!UI-Frame-InnerRightTile"] = true,
  ["Skillbar_Fill_Flipbook_Leatherworking"] = true, ["Skillbar_Flare_Leatherworking"] = true,
  ["Professions_Recipe_Hover"] = true, ["Professions_Recipe_Active"] = true, ["common-button-list-collapseExpand"] = true, ["common-insideframe"] = true, ["Profession-background-card-"] = true, ["Profession-background-card-leatherworking"] = true,
  ["auctionhouse-ui-filter-redx"] = true }
env.C_Texture = { GetAtlasInfo = function(name)
  if H.atlasMode == "ok" and ATLASES[name] then return { width = 100, height = 100, file = 1 } end
  return nil
end }

H.templateMode = "ok"
H.nativeMode = { dropdown = "ok", search = "ok", category = "ok", scroll = "ok", check = "ok" }
env.ScrollUtil = { InitScrollFrameWithScrollBar = function(sf, bar) sf._linkedBar = bar end }
local function NewUIFrame(otype, name, parent, template)
  if otype == "DropdownButton" then
    if H.nativeMode.dropdown == "fail" then error("Unknown frame type 'DropdownButton'") end
    local f = New(otype, parent, name)
    f._template = template
    function f:SetupMenu(gen) self._gen = gen end
    function f:GenerateMenu() self._generated = (self._generated or 0) + 1 end
    function f:OverrideText(t) self._override = t end
    f._scripts.OnEnter = function(self) self._nativeEnter = (self._nativeEnter or 0) + 1 end
    f._scripts.OnLeave = function() end
    return f
  end
  if template == "SearchBoxTemplate" and H.nativeMode.search == "fail" then error("Couldn't find inherited node 'SearchBoxTemplate'") end
  if template == "ProfessionsRecipeListCategoryTemplate" and H.nativeMode.category == "fail" then error("Couldn't find inherited node") end
  if template == "MinimalScrollBar" and H.nativeMode.scroll == "fail" then error("Couldn't find inherited node 'MinimalScrollBar'") end
  if template == "MinimalCheckboxTemplate" and H.nativeMode.check == "fail" then error("Couldn't find inherited node 'MinimalCheckboxTemplate'") end
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
  if template == "PortraitFrameTemplate" or template == "ButtonFrameTemplate" then
    if H.templateMode == "fail" then error("Couldn't find inherited node '" .. template .. "'") end
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

local Files = dofile(ROOT .. "dev/files.lua")
local files = Files.kitFiles(Files.list({ except = { "Sync" } }))
local client = Kit.Client(sched, nil, "Me Stone", { env = env, epoch = 1800000000, files = files, setup = function(_, c)
  c.newFrame = NewUIFrame
  env.C_ChatInfo, env.C_GuildInfo = nil, nil
  env.UIParent = New("Frame"); env.UIParent._w, env.UIParent._h = 1920, 1080; env.GameTooltip = New("GameTooltip"); env.GameTooltip_Hide = function() end
  for _, m in ipairs({ "SetOwner", "AddLine", "AddDoubleLine", "SetHyperlink" }) do env.GameTooltip[m] = function() end end
  function env.InCombatLockdown() return false end
  function env.IsInGuild() return true end
  function env.GetRealmName() return "Realm" end
  function env.UnitName(u) if u == "player" then return "Me", "Stone" end end
  function env.UnitNameUnmodified(u) return env.UnitName(u) end
  function env.UnitClass(u) if u == "player" then return "Schurke", "ROGUE" end end
  function env.UnitLevel(u) if u == "player" then return 36 end end
  function env.UnitIsUnit(a, b) return a == b end
  function env.UnitIsPlayer(u) return u == "player" end
  function env.UnitGUID(u) if u == "player" then return "G-me" end end
  function env.GetInventoryItemLink(u, slot) if u == "player" and slot == 5 then return "item:4244::::::::36:1488::11" end end
  function env.GetInventorySlotInfo(t) return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. t end
  function env.GetNumGuildMembers() return 0 end
  function env.GetProfessions() return nil end
  env.C_Item = {
    GetItemInfoInstant = function(item) return 4244, "Armor", "x", "INVTYPE_CHEST", 134, 4, 2 end,
    GetItemInfo = function(item) return "Hillman's Vest", "|Hitem:4244|h[Hillman's Vest]|h", 2, 20, 20, nil, nil, nil, "INVTYPE_CHEST", 134, nil, 4, 2, 2 end,
    GetItemStats = function() return {} end,
  }
  env.C_SpellBook = { IsSpellKnown = function() return false end }

  env.Minimap = New("Frame", nil, "Minimap")
  env.Minimap._w, env.Minimap._h, env.Minimap._cx, env.Minimap._cy, env.Minimap._scale = 140, 140, 1000, 700, 1
end })

local ns = client.ns.RavenquillExpedition_CraftAdvisor
local SOURCES = ns.Sources
ns.Sources = nil
local GCA = ns.GCA
local fire = function(_, ev, ...) client.fire(ev, ...) end
env.RavenquillExpeditionCraftDB = { settings = { minimapAngle = 200 } }
fire(GCA, "ADDON_LOADED", "RavenquillExpedition")
fire(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
fire(GCA, "PLAYER_LOGIN")
advance(3)

local function menuOf(dd)
  local entries, root = {}, {}
  local function add(kind, text, isSel, set, data)
    local e = { kind = kind, text = text, isSel = isSel, set = set, data = data }
    function e:SetTooltip(fn) self.tip = fn end
    function e:on() return self.isSel ~= nil and self.isSel(self.data) and true or false end
    function e:click() return self.set(self.data) end
    e.sub = {}
    function e:CreateRadio(t, i, s2, d)
      local r = { kind = "radio", text = t, isSel = i, set = s2, data = d }
      function r.on() return r.isSel(r.data) and true or false end
      function r.click() return r.set(r.data) end
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

local function plain(t) return (tostring(t or ""):gsub("|T.-|t ?", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function windowChecks(label)
  Kit.section("Window: " .. label)
  GCA.UI.frame = nil
  GCA.UI:Toggle()
  advance(1)
  local f = GCA.UI.frame
  check(f and f._shown, "window opens")
  check(f._w == 980 and f._h == 640 and f._points[1][1] == "CENTER", "nothing saved -> default size 980x640, centred")
  if H.templateMode == "ok" then
    check(f._title == "Guild Craft Advisor", "title set via SetTitle")
    check(f.PortraitContainer.portrait._tex == "Interface\\Icons\\Trade_LeatherWorking", "portrait set")
    local art = f.gcaArt
    check(art and art.overview and art.overview._atlas == "Profession-Background-Overview", "overview atlas drawn")
    check(art and art.pageArt and art.pageArt._atlas == "Profession-Background-Template2" and art.header == nil
      and art.page._points[1][4] == 3 and art.page._points[1][5] == -21, "Template2 over the whole page from 3,-21 as the client's CraftingPage (no 54 px clipped strip)")
    check(art and art.fill._SetColorTexture and art.fill._SetColorTexture[4] == 1, "dark fill under the art")
    check(not f.Bg._shown, "template Bg hidden under the art")
    check(art and f.NineSlice._level > art.canvas._level and f.NineSlice._level > art.page._level
      and f.content._level > art.page._level, "levels: canvas < page < content, border above the art")
  else
    check(f._backdrop ~= nil, "fallback backdrop")
  end
  local ok, err = pcall(f.CloseButton._scripts.OnClick, f.CloseButton)
  check(ok and not f._shown, "close button hides the window" .. (ok and "" or (": " .. tostring(err))))
  GCA.UI:Toggle(); advance(1)
  check(f._shown, "reopens")
  local insets = 0
  for _, c in ipairs(descendants(f)) do
    if c.native and c.bg and c.bg._atlas == "Professions-background-summarylist" then
      insets = insets + 1
      local sf
      for _, cc in ipairs(c._children) do if cc.minimalBar then sf = cc end end
      check(sf and sf._linkedBar == sf.minimalBar and sf.minimalBar._template == "MinimalScrollBar" and sf._scripts.OnMouseWheel
        and sf.ScrollBar == nil, "list panel holds a plain scroll frame + MinimalScrollBar (ScrollUtil), wheel scrolls")
    end
  end
  check(insets == 3, "three list panels on Professions-background-summarylist: guild needs, member list, crafters (the suggestions sit in the member's detail panel) (" .. insets .. ")")
  local nd, md = GCA.UI.needDetail, GCA.UI.memberDetail
  check(nd and md and nd.NineSlice and md.NineSlice and nd.NineSlice.role == "detailBorder" and md.NineSlice.role == "detailBorder"
    and nd.NineSlice.how == "atlas1" and nd.NineSlice.frameTex._atlas == "common-insideframe" and nd.cardBg and md.cardBg
    and nd.bg == nil and md.bg == nil and GCA.UI.sugInset._parent == md and GCA.UI.sugInset.bg == nil,
    "craft + member detail panels framed by common-insideframe with the profession card behind, the list/sheet inside")
  local slotLike = 0
  for _, c in ipairs(descendants(f)) do if c.slot ~= nil and c.up ~= nil then slotLike = slotLike + 1 end end
  check(GCA.UI.slotButtons == nil and GCA.UI.ScrollToSlot == nil and GCA.UI.sugList.ScrollToAnchor == nil and slotLike == 0,
    "no gear-slot buttons, no ScrollToSlot/ScrollToAnchor (" .. slotLike .. " slot-like frames)")
  check(GCA.DISPLAY_SLOTS == nil, "Core's DISPLAY_SLOTS (only the gear row used it) removed")
  local ins = GCA.UI.sugInset
  check(ins._points[1][5] == -76 and GCA.UI.sugHeader._points[1][5] == -54 and GCA.UI.infoIcon._points[1][5] == -52
    and GCA.UI.sourceText == nil, "header -54 beside the (i) icon, list area -76 inside the member detail panel")
  check((GCA.UI.subText._text or ""):find("gear your own, read from your character", 1, true),
    "for yourself the sub-line says the gear is read from your own character: " .. tostring(GCA.UI.subText._text))
  local sb = GCA.UI.specButton
  GCA.db.specManual = {}; GCA:InvalidateScores(); GCA.UI:Refresh()
  local sdd = sb.dropdown
  check(sb._shown and sdd.native and sdd._template == "WowStyle1DropdownTemplate" and plain(sdd._override):find("unknown – pick", 1, true)
    and sb.small == nil, "spec picker = native WowStyle1DropdownTemplate, text 'unknown – pick' (no 'SPEC' label box): " .. plain(sdd._override))
  check((GCA.UI.emptyText._text or ""):find("Spec unknown"), "empty text asks for a spec")
  local sm = menuOf(sdd)
  check(#sm == 4 and sm[1].kind == "radio" and sm[1]:on() and menuTexts(sm):find("^Automatic.*|Assassination|Combat|Subtlety$"),
    "spec menu radios: Automatic (selected) + 3 Rogue specs: " .. menuTexts(sm))
  sm[3]:click()
  GCA.UI:Refresh()
  check(GCA.db.specManual["Me Stone"] and GCA.db.specManual["Me Stone"].spec == "COMBAT", "manual pick saved")
  check(menuOf(sdd)[3]:on() and not menuOf(sdd)[1]:on(), "the Combat radio is selected now")
  check(plain(sdd._override):find("Combat") and not sb.icon._shown and sb.iconKind == nil,
    "spec dropdown shows the pick; no class icon in this mock (no atlas, no CLASS_ICON_TCOORDS): " .. plain(sdd._override))
  check((GCA.UI.sourceLine or ""):find("SimGear Forever 0.14.0 · Combat Lv40 %(nearest set for Lv36%) · simmed · leveling bonus 50%%")
    and GCA.UI.infoIcon._shown, "source line in the (i) icon's tooltip: " .. tostring(GCA.UI.sourceLine))
  local sl = GCA.UI.survival.slider
  check(sl._value == 50 and (GCA.UI.survival.label._text or ""):find("50%%"), "slider starts at 50 %")
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
  menuOf(sdd)[1]:click()
  check(GCA.db.specManual["Me Stone"] == nil, "Automatic clears the pick")
  f:Hide()
end

H.tip, H.hyper = {}, {}
local function captureTip()
  H.tip, H.hyper = {}, {}
  env.GameTooltip.AddLine = function(_, t) H.tip[#H.tip + 1] = tostring(t) end
  env.GameTooltip.AddDoubleLine = function(_, a, b) H.tip[#H.tip + 1] = tostring(a) .. " | " .. tostring(b) end
  env.GameTooltip.SetText = function(_, t) H.tip[#H.tip + 1] = tostring(t) end
  env.GameTooltip.SetHyperlink = function(_, l) H.hyper[#H.hyper + 1] = tostring(l) end
end
local function tipText() return table.concat(H.tip, "\n") end
local function onlyChanges()
  if #H.tip == 0 then return true end
  local head = tostring(H.tip[2] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return H.tip[1] == " " and (head:find("^Stat changes") or head:find("^Werteänderungen")) ~= nil and #H.tip >= 3
end
local function plainTip(frag) return onlyChanges() and #H.hyper == 1 and (frag == nil or H.hyper[1]:find(frag, 1, true) ~= nil) end
local function fakeSug(over)
  local d = { kind = "item", cand = { spellID = 3762, itemID = 4244, recipe = { skill = 100, src = "trainer", r = {} } },
    info = { name = "Hillman's Leather Vest", link = "|Hitem:4244|h[Hillman's Leather Vest]|h", quality = 2, icon = "x", minLevel = 20 },
    slot = 5, known = true, status = "upgrade", pct = 0.12, points = 12, tier = 1, oldScore = 1, newScore = 2 }
  for k, v in pairs(over or {}) do d[k] = v end
  if over and over.sortPct and over.points == nil then d.points = over.sortPct end
  d.sortPct = nil
  return d
end

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

local function longList()
  local rows = {}
  for _, slot in ipairs({ 1, 3, 5, 7, 8 }) do
    rows[slot] = { fakeSug({ slot = slot }), fakeSug({ slot = slot }), fakeSug({ slot = slot }) }
  end
  return fakeSections(rows)
end
local function manyMembers()
  local m = {}
  for i = 1, 40 do m[i] = { key = "Member" .. i .. " Stone", level = 30, class = "ROGUE", online = true, member = { items = {} } } end
  return m
end

local function layoutChecks(UIx, f, label)
  local winW, winH = f._w, f._h
  local R = function(fr) return rectOf(fr, f) end
  local common = {
    { "drag bar", UIx.dragBar }, { "profession selector", UIx.profButton }, { "sync dot", UIx.syncDot },
    { "leveling-bonus slider", UIx.survival },
    { "resize grip", UIx.resizeGrip },
  }
  if not UIx.tabsTemplated then
    for i, t in ipairs(UIx.tabs) do common[#common + 1] = { "view button " .. i, t } end
  end
  local views = {
    member = { { "member panel", UIx.memberInset }, { "name", UIx.nameText }, { "spec button", UIx.specButton },
      { "sub-line", UIx.subText }, { "(i) icon", UIx.infoIcon }, { "list header", UIx.sugHeader }, { "suggestion panel", UIx.sugInset },
      { "view switch", UIx.modeToggle } },
    needs = { { "needs panel", UIx.needsInset }, { "craft detail panel", UIx.needDetail } },
    crafters = { { "crafter panel", UIx.crafterInset }, { "crafter name", UIx.crafterName }, { "crafter sub-line", UIx.crafterSub },
      { "recipe search", UIx.recipeSearch }, { "upgrades toggle", UIx.upgradesOnly }, { "recipe list", UIx.recipeArea } },
  }
  for _, vname in ipairs({ "member", "needs", "crafters" }) do
    local named = {}
    for _, x in ipairs(common) do named[#named + 1] = x end
    for _, x in ipairs(views[vname]) do named[#named + 1] = x end
    local bad, outside = {}, {}
    for i, a in ipairs(named) do
      local ra = R(a[2])
      if ra.l < 0 or ra.t < 0 or ra.r > winW or ra.b > winH then outside[#outside + 1] = a[1] .. rstr(ra) end
      for j = i + 1, #named do
        local rb = R(named[j][2])
        if overlap(ra, rb) then bad[#bad + 1] = a[1] .. rstr(ra) .. " x " .. named[j][1] .. rstr(rb) end
      end
    end
    check(#bad == 0, label .. " (" .. vname .. " view): no overlaps among " .. #named .. " controls " .. table.concat(bad, "; "))
    check(#outside == 0, label .. " (" .. vname .. " view): every control inside the window " .. table.concat(outside, "; "))
  end
  local pb, dot = R(UIx.profButton), R(UIx.syncDot)
  check(pb.l + pb.r == winW and pb.t == 27 and pb.b == 56 and pb.r + 10 <= dot.l and dot.r == winW - 20 and dot.b <= 62,
    label .. ": rank bar centred under the title, sync label right of it, both above the panels (62) " .. rstr(pb) .. " " .. rstr(dot))
  if UIx.tabsTemplated then
    local t1, t2 = R(UIx.tabs[1]), R(UIx.tabs[2])
    check(t1.t == winH - 2 and t1.l == 12 and t2.l >= t1.r, label .. ": view tabs hang under the window's bottom edge, side by side")
  end
  local mi, md, si = R(UIx.memberInset), R(UIx.memberDetail), R(UIx.sugInset)
  check(mi.l == 10 and mi.r - mi.l == 260 and mi.t == 62 and mi.b == winH - 40, label .. ": member list panel 260 wide, 62..H-40 " .. rstr(mi))
  check(md.l == 278 and md.r == winW - 12 and md.t == 62 and md.b == winH - 40, label .. ": member detail panel fills 278..W-12, 62..H-40 " .. rstr(md))
  check(si.l == md.l + 6 and si.r == md.r - 6 and si.t == md.t + 76 and si.b == md.b - 6,
    label .. ": sheet / list area inside the detail panel, below its header (76) " .. rstr(si))
  local ml, sl = R(UIx.memberList), R(UIx.sugList)
  check(ml.b == mi.b - 5 and ml.r == mi.r - 25 and sl.b == si.b - 5 and sl.r == si.r - 29,
    label .. ": both scroll frames fill their panel (25 / 29 px left for the scroll bar, as in 0.5.0) " .. rstr(ml) .. " " .. rstr(sl))
  check(UIx.sugList.content._w == UIx.sugList.viewW and UIx.memberList.content._w == UIx.memberList.viewW,
    label .. ": scroll content as wide as the view (rows anchored to its right edge)")
  local nt, sb = R(UIx.nameText), R(UIx.specButton)
  local ic, hd0, tg = R(UIx.infoIcon), R(UIx.sugHeader), R(UIx.modeToggle)
  check(nt.r < sb.l and R(UIx.subText).r == winW - 12 - 224 and R(UIx.subText).r < sb.l and hd0.r == tg.l - 10 and tg.r == winW - 24 and ic.r <= hd0.l
    and UIx.emptyText._w == (winW - 302) - 60 and nt.l == md.l + 14 and sb.r == md.r - 12,
    label .. ": header texts span the detail panel, (i) icon left of the list header, K4 switch right of it")
  local ni, nl, sbx, cnt, nd = R(UIx.needsInset), R(UIx.needsList), R(UIx.searchBox), R(UIx.needsCount), R(UIx.needDetail)
  check(ni.l == 10 and ni.r == 270 and ni.t == 62 and ni.b == winH - 40 and nl.r == ni.r - 25 and nl.b == ni.b - 23 and nl.t == ni.t + 34,
    label .. ": guild-needs list panel 10..270, 62..H-40, its list between the search and the count " .. rstr(ni) .. " " .. rstr(nl))
  check(nd.l == 278 and nd.r == winW - 12 and nd.t == 62 and nd.b == winH - 40 and UIx.needDetail.w == winW - 290 and UIx.needDetail.h == winH - 102,
    label .. ": craft detail panel fills 278..W-12, 62..H-40 " .. rstr(nd))
  local obx = R(UIx.filterButton)
  check(sbx.l >= ni.l and sbx.t >= ni.t and sbx.b <= nl.t and obx.r == ni.r - 8 and obx.b <= nl.t and sbx.r < obx.l
    and cnt.t >= nl.b and cnt.b <= ni.b and cnt.l == ni.l + 10 and cnt.r == ni.r - 10
    and UIx.needsList.content._w == UIx.needsList.viewW,
    label .. ": search | Filter above the list, the count under it, all inside the list panel " .. rstr(sbx) .. " " .. rstr(obx) .. " " .. rstr(cnt))
  local ci, cl, cs, cd, ra = R(UIx.crafterInset), R(UIx.crafterList), R(UIx.crafterSearch), R(UIx.crafterDetail), R(UIx.recipeArea)
  check(ci.l == 10 and ci.r == 270 and ci.t == 62 and ci.b == winH - 40 and cl.r == ci.r - 25 and cl.b == ci.b - 5
    and cs.l >= ci.l and cs.r <= ci.r and cs.b <= cl.t and cd.l == 278 and cd.r == winW - 12 and cd.t == 62 and cd.b == winH - 40
    and ra.l == cd.l + 6 and ra.r == cd.r - 6 and ra.t == cd.t + 76 and ra.b == cd.b - 6
    and UIx.recipeList.content._w == UIx.recipeList.viewW and UIx.crafterList.content._w == UIx.crafterList.viewW,
    label .. ": crafters view: list panel 10..270 with its search above the list, detail panel 278..W-12, recipes below its header "
    .. rstr(ci) .. " " .. rstr(cd) .. " " .. rstr(ra))
  local ms = R(UIx.memberSearch)
  check(ms.l >= mi.l and ms.r <= mi.r and ms.t >= mi.t and ms.b <= ml.t, label .. ": member search inside the member panel, above the list " .. rstr(ms))
  local art = f.gcaArt
  local cv, hd = R(art.canvas), R(art.page)
  check(cv.l == 2 and cv.t == 21 and cv.r == winW - 2 and cv.b == winH - 3 and hd.l == 3 and hd.r == winW - 3 and hd.t == 21 and hd.b == winH - 3,
    label .. ": art canvas (Overview, 2,-21) and the Template2 page (3,-21) fill the window at every size " .. rstr(cv) .. " " .. rstr(hd))
  local g = R(UIx.resizeGrip)
  check(g.r == winW - 4 and g.b == winH - 4 and g.t >= md.b and g.t >= nd.b, label .. ": grip in the bottom-right corner, below the panels")
end

function H.lateGlobals()
  env.IsShiftKeyDown = function() return false end
  env.HandleModifiedItemClick = function() end
  env.GetNumSubgroupMembers = function() return 0 end
  env.IsInRaid = function() return false end
end

function H.finish(atlasCheck)
  if atlasCheck then check(H.badAtlas == 0, "SetAtlas was never called for an atlas the client lacks (" .. H.badAtlas .. ")") end
  Kit.section("Keys looked up that the mock lacks (nil here; fine if the addon checks for them):")
  local names = {}
  for k in pairs(missing) do names[#names + 1] = k end
  table.sort(names)
  io.write("  ", #names > 0 and table.concat(names, ", ") or "(none)", "\n")
  Kit.finish()
end

H.ATLASES = ATLASES
H.Files = Files
H.Frame = Frame
H.GCA = GCA
H.New = New
H.ROOT = ROOT
H.SOURCES = SOURCES
H.Tex = Tex
H.advance = advance
H.captureTip = captureTip
H.check = check
H.descendants = descendants
H.env = env
H.fakeSections = fakeSections
H.fakeSug = fakeSug
H.layoutChecks = layoutChecks
H.longList = longList
H.manyMembers = manyMembers
H.menuOf = menuOf
H.menuTexts = menuTexts
H.ns = ns
H.overlap = overlap
H.plain = plain
H.plainTip = plainTip
H.rectOf = rectOf
H.rstr = rstr
H.section = Kit.section
H.tipText = tipText
H.windowChecks = windowChecks
return H
