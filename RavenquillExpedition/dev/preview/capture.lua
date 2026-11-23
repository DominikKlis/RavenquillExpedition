local HERE = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):gsub("[^/]*$", ""))
if HERE == "" then HERE = "./" end
local REPO = HERE .. "../../../"
local Kit = dofile(REPO .. "RavenquillExpedition/dev/testkit.lua")
local Layout = dofile(REPO .. "RavenquillExpedition_Highlights/dev/layout.lua")
local SMF = dofile(REPO .. "RavenquillExpedition_Highlights/dev/smf.lua")
local Json = dofile(HERE .. "json.lua")

local SCREEN_W, SCREEN_H = 1920, 1080
local Capture = { REPO = REPO, Kit = Kit, Layout = Layout }

local FX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
local FONT_SIZE = { GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12, GameFontNormalSmall = 10,
  GameFontHighlightSmall = 10, GameFontDisableSmall = 10, GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
  GameFontNormalHuge = 20, GameFontNormalMed3 = 14, GameFontHighlightMedium = 14, GameFontNormalMed2 = 13,
  GameFontNormalMed1 = 13, GameFontHighlightMed2 = 13, SystemFont_Shadow_Med1 = 12, NumberFontNormal = 12 }
local CHAR_EM, LINE_EM = 0.55, 1.2

local Solve = {}

local function PlainText(t)
  return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("|H.-|h(.-)|h", "%1"))
end

local function FontSize(s)
  if s._fontExplicit then return s._fontSize or 12 end
  return FONT_SIZE[s._fontObj or ""] or s._fontSize or 12
end
Solve.FontSize = FontSize

local widthsOk, GLYPH = pcall(dofile, REPO .. ".cache/preview-art/fontwidths.lua")
if not widthsOk or type(GLYPH) ~= "table" then GLYPH = {} end
local FONT_SCALE = tonumber(os.getenv("RQ_FONT_SCALE") or "") or 1.038

local function Em(text)
  local em = 0
  for _, code in utf8.codes(text) do em = em + (GLYPH[utf8.char(code)] or CHAR_EM) end
  return em
end

local function TextWidth(s)
  local widest = 0
  for para in (PlainText(s._text or "") .. "\n"):gmatch("([^\n]*)\n") do widest = math.max(widest, Em(para)) end
  return widest * FontSize(s) * FONT_SCALE
end

local function Lines(text, size, width)
  local k, lines = size * FONT_SCALE, 0
  local cw = (GLYPH[" "] or CHAR_EM) * k
  for para in (PlainText(text) .. "\n"):gmatch("([^\n]*)\n") do
    local n, used = 1, 0
    for word in para:gmatch("%S+") do
      local w = Em(word) * k
      local need = used == 0 and w or used + cw + w
      if width and need > width + 0.5 and used > 0 then n, used = n + 1, w else used = need end
    end
    lines = lines + n
  end
  return lines
end

local Axis

local function Fixes(s, horizontal)
  local fixes, fracs = {}, horizontal and FX or FY
  for point, a in pairs(s._points or {}) do
    local lo, size = Axis(a.rel or s._parent, horizontal)
    if lo == nil then return nil end
    fixes[#fixes + 1] = { f = fracs[point], v = lo + fracs[a.relPoint] * size + (horizontal and a.x or a.y) }
  end
  return fixes
end

local function TextHeight(s)
  if not s._text or s._text == "" then return 0 end
  local _, width = Axis(s, true, true)
  local size = FontSize(s)
  local lines = Lines(s._text, size, s._w or width)
  if s._maxLines and s._maxLines > 0 then lines = math.min(lines, s._maxLines) end
  return lines * size * LINE_EM + (lines - 1) * (s._spacing or 0)
end

local function Intrinsic(s, horizontal, noWrap)
  local explicit = horizontal and s._w or (not horizontal and s._h)
  if explicit then return explicit end
  if s._type ~= "FontString" then return 0 end
  if horizontal then return noWrap and nil or TextWidth(s) end
  return TextHeight(s)
end

Axis = function(s, horizontal, forWrap)
  if not s then return nil end
  if s._pin then
    if horizontal then return s._pin[1], s._pin[3] end
    return s._pin[2], s._pin[4]
  end
  local fixes = Fixes(s, horizontal)
  if not (fixes and fixes[1]) then return nil end
  local lo, hi, mid = nil, nil, nil
  for _, x in ipairs(fixes) do
    if x.f == 0 then lo = x.v elseif x.f == 1 then hi = x.v else mid = x.v end
  end
  if lo and hi then return lo, hi - lo end
  local size = Intrinsic(s, horizontal, forWrap)
  if size == nil then return nil end
  if lo then return lo, size end
  if hi then return hi - size, size end
  return mid - size / 2, size
end

function Solve.Rect(s)
  local left, width = Axis(s, true)
  local bottom, height = Axis(s, false)
  if left == nil or bottom == nil then return nil end
  return { left = left, right = left + width, bottom = bottom, top = bottom + height, width = width, height = height }
end
Capture.Solve = Solve
Capture.PlainText = PlainText

local atlasOk, ATLAS_SIZE = pcall(dofile, REPO .. ".cache/preview-art/atlas.lua")
if not atlasOk or type(ATLAS_SIZE) ~= "table" then ATLAS_SIZE = {} end
Capture.ATLAS_SIZE = ATLAS_SIZE

local function AtlasTexture(owner, layer, atlas, sub)
  local t = owner:CreateTexture(nil, layer, nil, sub)
  t._atlas = atlas
  local size = ATLAS_SIZE[atlas:lower()]
  if size then t._w, t._h = size[1], size[2] end
  return t
end

local NINE_SLICE = {
  { "TopLeftCorner", "UI-Frame-PortraitMetal-CornerTopLeft", "TOPLEFT", -13, 16 },
  { "TopRightCorner", "UI-Frame-Metal-CornerTopRight", "TOPRIGHT", 2, 16 },
  { "BottomLeftCorner", "UI-Frame-Metal-CornerBottomLeft", "BOTTOMLEFT", -13, -8 },
  { "BottomRightCorner", "UI-Frame-Metal-CornerBottomRight", "BOTTOMRIGHT", 2, -8 },
}
local NINE_EDGES = {
  { "TopEdge", "_UI-Frame-Metal-EdgeTop", "TOPLEFT", "TopLeftCorner", "TOPRIGHT", "TopRightCorner", "h" },
  { "BottomEdge", "_UI-Frame-Metal-EdgeBottom", "BOTTOMLEFT", "BottomLeftCorner", "BOTTOMRIGHT", "BottomRightCorner", "h" },
  { "LeftEdge", "!UI-Frame-Metal-EdgeLeft", "TOPLEFT", "TopLeftCorner", "BOTTOMLEFT", "BottomLeftCorner", "v" },
  { "RightEdge", "!UI-Frame-Metal-EdgeRight", "TOPRIGHT", "TopRightCorner", "BOTTOMRIGHT", "BottomRightCorner", "v" },
}
local OPPOSITE = { TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT" }
local VERTICAL = { TOPLEFT = "BOTTOMLEFT", BOTTOMLEFT = "TOPLEFT", TOPRIGHT = "BOTTOMRIGHT", BOTTOMRIGHT = "TOPRIGHT" }

local function NineSlice(frame)
  local pieces = {}
  for _, p in ipairs(NINE_SLICE) do
    local t = AtlasTexture(frame, "OVERLAY", p[2])
    t:SetPoint(p[3], frame, p[3], p[4], p[5])
    pieces[p[1]] = t
  end
  for _, e in ipairs(NINE_EDGES) do
    local t = AtlasTexture(frame, "OVERLAY", e[2])
    local relA = e[7] == "h" and OPPOSITE[e[3]] or VERTICAL[e[3]]
    local relB = e[7] == "h" and OPPOSITE[e[5]] or VERTICAL[e[5]]
    t:SetPoint(e[3], pieces[e[4]], relA, 0, 0)
    t:SetPoint(e[5], pieces[e[6]], relB, 0, 0)
    if e[7] == "h" then t._w = nil else t._h = nil end
    pieces[e[1]] = t
  end
  return pieces
end

local function PortraitTemplate(f, Child)
  f.Bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
  f.Bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21)
  f.Bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  f.Bg._file = [[Interface\FrameGeneral\UI-Background-Rock]]
  f.Bg._tile = true
  f.TopTileStreaks = AtlasTexture(f, "BORDER", "_UI-Frame-TopTileStreaks")
  f.TopTileStreaks:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -21)
  f.TopTileStreaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  f.TopTileStreaks._w = nil
  f.NineSlice = Child()
  f.NineSlice:SetAllPoints(f)
  f.NineSlice._level = 500
  NineSlice(f.NineSlice)
  f.PortraitContainer = Child()
  f.PortraitContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.PortraitContainer:SetSize(1, 1)
  f.PortraitContainer._level = 400
  f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture(nil, "OVERLAY")
  f.PortraitContainer.portrait:SetSize(62, 62)
  f.PortraitContainer.portrait:SetPoint("TOPLEFT", f.PortraitContainer, "TOPLEFT", -5, 7)
  f.PortraitContainer.portrait._mask = "circle"
  f.CloseButton = Child("Button")
  f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 3)
  f.CloseButton:SetSize(28, 28)
  f.CloseButton._level = 510
  f.CloseButton._normal = "atlas:RedButton-Exit"
  f.TitleContainer = Child()
  f.TitleContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -1)
  f.TitleContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
  f.TitleContainer:SetHeight(20)
  f.TitleContainer._level = 600
  f.TitleText = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.TitleText:SetPoint("TOP", f.TitleContainer, "TOP", 0, -5)
  f.TitleText:SetPoint("LEFT", f.TitleContainer, "LEFT", 0, 0)
  f.TitleText:SetPoint("RIGHT", f.TitleContainer, "RIGHT", 0, 0)
  function f.SetTitle(s, t) s._title = t; s.TitleText._text = t end
  function f.SetPortraitToAsset(s, p) s.PortraitContainer.portrait._file = p end
end

local function Templated(c, base, otype, name, parent, template)
  local f = base(otype, name, parent)
  f._shown = true
  f._template = template
  local function Child(kind) local ch = base(kind or "Frame", nil, f); ch._shown = true; return ch end
  if template == "PortraitFrameTemplate" or template == "ButtonFrameTemplate" or template == "BasicFrameTemplateWithInset" then
    PortraitTemplate(f, Child)
  elseif template == "InsetFrameTemplate" then
    f.NineSlice = Child()
    f.NineSlice:SetAllPoints(f)
    f.Bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg:SetAllPoints(f)
    f.Bg:SetColorTexture(0, 0, 0, 0.5)
  elseif template == "SearchBoxTemplate" then
    f.Instructions = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    f.Instructions:SetPoint("LEFT", f, "LEFT", 16, 0)
    f.clearButton = Child("Button")
    f._role = "editbox"
  elseif template == "ProfessionsRecipeListCategoryTemplate" then
    f.ButtonText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.ButtonText:SetPoint("LEFT", f, "LEFT", 20, 0)
    f.CollapseButton, f.RankBar = Child("Button"), Child()
    function f.SetHeaderText(s, t) s.ButtonText._text = t end
    function f.UpdateCollapsedState(s, v) s._collapsed = v end
  elseif template == "MinimalScrollBar" then
    function f.ScrollStepInDirection() end
    function f.SetHideIfUnscrollable() end
    f._role = "scrollbar"
  elseif template == "UIPanelScrollFrameTemplate" then
    f.ScrollBar = Child("Slider")
  elseif template == "UIPanelButtonTemplate" or template == "UIPanelCloseButton" or template == "WowStyle1DropdownTemplate" then
    f._role = template == "WowStyle1DropdownTemplate" and "dropdown" or "button"
  elseif template == "PanelTabButtonTemplate" then
    f._role = "tab"
    f._w, f._h = 110, 32
  end
  if otype == "DropdownButton" then
    function f.SetupMenu(s, gen) s._gen = gen end
    function f.GenerateMenu() end
    function f.OverrideText(s, t) s._text = t end
    f._role = "dropdown"
  elseif otype == "EditBox" then
    f._role = "editbox"
  elseif otype == "CheckButton" then
    f._role = "check"
  elseif otype == "Slider" then
    f._role = f._role or "slider"
  end
  if name then c.env[name] = f end
  return f
end

local function Install(c, env)
  Layout.Install(c)
  Layout.Pin(env.UIParent, 0, 0, SCREEN_W, SCREEN_H)
  env.UIParent._shown = true
  local base = c.newFrame
  c.newFrame = function(otype, name, parent, template) return Templated(c, base, otype, name, parent, template) end
  SMF.Install(c)
  local fm = c.frameMethods
  local createFS = fm.CreateFontString
  fm.CreateFontString = function(s, name, layer, fontObj)
    local fs = createFS(s, name, layer)
    fs._fontObj = fontObj
    return fs
  end
  fm.SetFontObject = function(s, obj) s._fontObj = type(obj) == "table" and obj._name or obj end
  fm.SetNormalFontObject = fm.SetFontObject
  fm.SetTextColor = function(s, r, g, b, a) s._ink = { r, g, b, a or 1 } end
  fm.SetVertexColor = function(s, r, g, b, a) s._tint = { r, g, b, a or 1 } end
  fm.SetJustifyH = function(s, j) s._justify = j end
  fm.SetJustifyV = function(s, j) s._justifyV = j end
  fm.SetAtlas = function(s, a, useSize)
    s._atlas, s._file, s._color = a, nil, nil
    local size = useSize and type(a) == "string" and ATLAS_SIZE[a:lower()]
    if size then s._w, s._h = size[1], size[2] end
  end
  fm.SetNormalTexture = function(s, t) s._normal = type(t) == "string" and t or (type(t) == "table" and (t._file or (t._atlas and "atlas:" .. t._atlas))) end
  fm.SetCheckedTexture = function(s, t) s._checkedTex = type(t) == "string" and t or nil end
  fm.SetNormalAtlas = function(s, a) s._normal = "atlas:" .. a end
  fm.SetBackdrop = function(s, b) s._backdrop = b end
  fm.SetBackdropColor = function(s, r, g, b, a) s._bdColor = { r, g, b, a or 1 } end
  fm.SetBackdropBorderColor = function(s, r, g, b, a) s._bdBorder = { r, g, b, a or 1 } end
  fm.SetFrameStrata = function(s, v) s._strata = v end
  fm.SetFrameLevel = function(s, v) s._level = v end
  fm.GetFrameLevel = function(s) return s._level or 0 end
  fm.SetChecked = function(s, v) s._checked = v and true or false end
  fm.Disable = function(s) s._disabled = true end
  fm.Enable = function(s) s._disabled = false end
  fm.SetEnabled = function(s, v) s._disabled = not v end
  fm.IsEnabled = function(s) return not s._disabled end
  fm.SetMinMaxValues = function(s, lo, hi) s._min, s._max = lo, hi end
  fm.SetValue = function(s, v) s._value = v end
  fm.GetValue = function(s) return s._value or 0 end
  fm.GetEffectiveScale = function() return 1 end
  fm.GetScale = function() return 1 end
  fm.SetScale = function(s, v) s._scale = v end
  fm.SetClipsChildren = function(s, v) s._clips = v and true or nil end
  fm.SetDesaturated = function(s, v) s._desat = v end
  local setFont = fm.SetFont
  fm.SetFont = function(s, ...) s._fontExplicit = true; return setFont(s, ...) end
  fm.GetWidth = function(s) local _, w = Axis(s, true); return w or 0 end
  fm.GetHeight = function(s) local _, h = Axis(s, false); return h or 0 end
  fm.GetSize = function(s) return fm.GetWidth(s), fm.GetHeight(s) end
  fm.GetStringHeight = TextHeight
  fm.GetStringWidth = TextWidth
  fm.GetUnboundedStringWidth = TextWidth
  fm.GetNumLines = function(s)
    local _, width = Axis(s, true)
    return Lines(s._text or "", FontSize(s), s._w or width)
  end
  fm.GetLeft = function(s) local r = Solve.Rect(s); return r and r.left end
  fm.GetRight = function(s) local r = Solve.Rect(s); return r and r.right end
  fm.GetTop = function(s) local r = Solve.Rect(s); return r and r.top end
  fm.GetBottom = function(s) local r = Solve.Rect(s); return r and r.bottom end
  fm.GetCenter = function(s)
    local r = Solve.Rect(s)
    if r then return (r.left + r.right) / 2, (r.bottom + r.top) / 2 end
  end
  env.C_Texture = { GetAtlasInfo = function(name)
    local size = ATLAS_SIZE[tostring(name):lower()] or { 64, 64 }
    return { width = size[1], height = size[2], file = "atlas:" .. tostring(name), leftTexCoord = 0, rightTexCoord = 1,
      topTexCoord = 0, bottomTexCoord = 1 }
  end }
  env.ScrollUtil = { InitScrollFrameWithScrollBar = function() end }
  env.PanelTemplates_TabResize = function(tab, pad)
    tab._w = math.max(70, TextWidth({ _text = tab._text or "", _fontObj = "GameFontNormalSmall" }) + 40 + (pad or 0))
  end
  env.PanelTemplates_SetNumTabs = function() end
  env.PanelTemplates_SetTab = function(f, id) f._selectedTab = id end
  fm.SetScrollChild = function(s, child)
    s._scrollChild = child
    if child and not next(child._points or {}) then
      child._points = { TOPLEFT = { rel = s, relPoint = "TOPLEFT", x = 0, y = 0 } }
    end
  end
  fm.GetScrollChild = function(s) return s._scrollChild end
  env.GameFontNormal = { _name = "GameFontNormal" }
  env.GameFontHighlight = { _name = "GameFontHighlight" }
  env.GameFontHighlightSmall = { _name = "GameFontHighlightSmall" }
  env.GameFontNormalSmall = { _name = "GameFontNormalSmall" }
  env.GameFontNormalLarge = { _name = "GameFontNormalLarge" }
  env.GameFontDisable = { _name = "GameFontDisable" }
end
Capture.Install = Install

local function Children(c)
  local kids = {}
  local function add(p, x)
    if p then kids[p] = kids[p] or {}; kids[p][#kids[p] + 1] = x end
  end
  local seen = {}
  local function walk(f)
    if seen[f] then return end
    seen[f] = true
    for _, ch in ipairs(f._children or {}) do add(f, ch); walk(ch) end
  end
  for _, f in ipairs(c.frames) do walk(f) end
  for _, r in ipairs(c.regions) do add(r._parent, r) end
  return kids
end

local function Color(t) if t then return { t[1], t[2], t[3], t[4] or 1 } end end

local function Plain(v)
  if v == nil then return nil end
  return tostring(v)
end

function Capture.BoundW(s)
  if s._type ~= "FontString" then return nil end
  if s._w then return true end
  local lo, hi
  for point in pairs(s._points or {}) do
    if FX[point] == 0 then lo = true elseif FX[point] == 1 then hi = true end
  end
  return (lo and hi) or false
end

function Capture.AnchorX(s)
  if s._type ~= "FontString" then return nil end
  for point in pairs(s._points or {}) do
    if FX[point] == 0 then return "LEFT" elseif FX[point] == 1 then return "RIGHT" end
  end
  return "CENTER"
end

function Capture.Snapshot(c, root, id, title, notes)
  SMF.TickAll(c)
  local kids = Children(c)
  local nodes, rootRect = {}, Solve.Rect(root)
  assert(rootRect, "root has no rect: " .. id)
  local function visit(f, depth, parentId)
    if f._shown == false then return end
    local r = Solve.Rect(f)
    local myId = #nodes + 1
    local node = {
      id = myId, parent = parentId, depth = depth, type = f._type, name = f._name, role = f._role, template = f._template,
      layer = f._layer, sub = f._sublevel, level = f._level, strata = f._strata,
      text = Plain(f._text), font = f._fontObj, fontSize = Solve.FontSize(f), fontFile = f._fontFile and tostring(f._fontFile), justify = f._justify, ink = Color(f._ink),
      color = Color(f._color), atlas = f._atlas, file = Plain(f._file), tint = Color(f._tint), alpha = f._alpha,
      tc = f._tc, backdrop = f._backdrop and true or nil, bdColor = Color(f._bdColor), bdBorder = Color(f._bdBorder),
      checked = f._checked, normal = f._normal, checkedTex = f._checkedTex, tile = f._tile, mask = f._mask, disabled = f._disabled, clips = f._clips, title = f._title,
      click = f._scripts and (f._scripts.OnClick or f._scripts.OnMouseUp or f._scripts.OnMouseDown) and true or nil,
      enter = f._scripts and f._scripts.OnEnter and true or nil, maxLines = f._maxLines, boundW = Capture.BoundW(f), anchorX = Capture.AnchorX(f),
    }
    if r then
      node.x, node.y = r.left - rootRect.left, rootRect.top - r.top
      node.w, node.h = r.width, r.height
    end
    nodes[#nodes + 1] = node
    for _, ch in ipairs(kids[f] or {}) do visit(ch, depth + 1, myId) end
  end
  visit(root, 0, nil)
  return { id = id, title = title, w = rootRect.width, h = rootRect.height, nodes = nodes, notes = notes }
end

local function MenuEntries(gen, owner)
  local entries = {}
  local function add(kind, text, isSel, data, depth)
    local e = { kind = kind, text = text and tostring(text) or nil, depth = depth or 0 }
    if isSel then
      local ok, v = pcall(isSel, data)
      e.on = ok and v and true or false
    end
    entries[#entries + 1] = e
    local sub = {}
    function sub.CreateRadio(_, t, i, _, d) return add("radio", t, i, d, (depth or 0) + 1) end
    function sub.CreateCheckbox(_, t, i, _, d) return add("check", t, i, d, (depth or 0) + 1) end
    function sub.CreateButton(_, t) return add("button", t, nil, nil, (depth or 0) + 1) end
    function sub.CreateDivider() return add("divider", nil, nil, nil, (depth or 0) + 1) end
    function sub.CreateTitle(_, t) return add("title", t, nil, nil, (depth or 0) + 1) end
    function sub.SetTooltip() end
    function sub.SetEnabled(_, v) e.disabled = not v end
    function sub.AddInitializer() end
    function sub.SetScrollMode() end
    return sub
  end
  local root = {}
  function root.CreateRadio(_, t, i, _, d) return add("radio", t, i, d) end
  function root.CreateCheckbox(_, t, i, _, d) return add("check", t, i, d) end
  function root.CreateButton(_, t) return add("button", t) end
  function root.CreateDivider() return add("divider") end
  function root.CreateTitle(_, t) return add("title", t) end
  function root.SetTag() end
  function root.SetScrollMode() end
  local ok, err = pcall(gen, owner, root)
  if not ok then io.write("MENU FAILED: ", tostring(err), "\n") end
  return entries
end

function Capture.MenuScreen(id, title, gen, owner)
  local entries = MenuEntries(gen, owner)
  local nodes, y, w = {}, 10, 260
  nodes[1] = { id = 1, type = "Frame", role = "menu", x = 0, y = 0, w = w, h = 0 }
  for _, e in ipairs(entries) do
    local n = { id = #nodes + 1, parent = 1, type = "FontString", font = "GameFontHighlightSmall", fontSize = 12, justify = "LEFT",
      x = 12 + e.depth * 16, y = y, w = w - 24 - e.depth * 16, h = 18, text = e.text, menuKind = e.kind, on = e.on, disabled = e.disabled }
    if e.kind == "divider" then n.h, n.text = 8, nil end
    if e.kind == "title" then n.font = "GameFontNormalSmall" end
    if e.kind == "radio" or e.kind == "check" then n.x, n.w = n.x + 20, n.w - 20 end
    nodes[#nodes + 1] = n
    y = y + n.h
  end
  nodes[1].h = y + 10
  return { id = id, title = title, w = w, h = y + 10, nodes = nodes, menu = entries }
end

function Capture.Write(path, screens)
  local fh = assert(io.open(path, "w"))
  fh:write(Json.encode({ screens = screens }))
  fh:close()
end

return Capture
