local Layout = {}

Layout.CHAR_EM, Layout.LINE_EM = 0.55, 1.2

local FX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1,
  BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0,
  BOTTOMRIGHT = 0 }

local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Chars(text) return utf8.len(text) or #text end

function Layout.Lines(text, size, width)
  local cw, lines = size * Layout.CHAR_EM, 0
  for para in (Plain(text) .. "\n"):gmatch("([^\n]*)\n") do
    local n, used = 1, 0
    for word in para:gmatch("%S+") do
      local w = Chars(word) * cw
      local need = used == 0 and w or used + cw + w
      if width and need > width and used > 0 then n, used = n + 1, w else used = need end
    end
    lines = lines + n
  end
  return lines
end

local function TextWidth(s)
  local widest = 0
  for para in (Plain(s._text or "") .. "\n"):gmatch("([^\n]*)\n") do widest = math.max(widest, Chars(para)) end
  return widest * (s._fontSize or 12) * Layout.CHAR_EM
end

local Axis

local function StringHeight(s)
  if not s._text or s._text == "" then return 0 end
  local _, width = Axis(s, true)
  local lines = Layout.Lines(s._text, s._fontSize or 12, width)
  if s._maxLines and s._maxLines > 0 then lines = math.min(lines, s._maxLines) end
  return lines * (s._fontSize or 12) * Layout.LINE_EM
end

local function Intrinsic(s, horizontal)
  local explicit = horizontal and s._w or s._h
  if explicit then return explicit end
  if s._type ~= "FontString" then return 0 end
  if horizontal then return TextWidth(s) end
  return StringHeight(s)
end

local function Fixes(s, horizontal)
  local fixes, fracs = {}, horizontal and FX or FY
  for point, a in pairs(s._points or {}) do
    local lo, size = Axis(a.rel or s._parent, horizontal)
    if lo == nil then return nil end
    fixes[#fixes + 1] = { f = fracs[point], v = lo + fracs[a.relPoint] * size + (horizontal and a.x or a.y) }
  end
  table.sort(fixes, function(p, q) return p.f < q.f end)
  return fixes
end

Axis = function(s, horizontal)
  if not s then return nil end
  if s._pin then
    if horizontal then return s._pin[1], s._pin[3] end
    return s._pin[2], s._pin[4]
  end
  local fixes = Fixes(s, horizontal)
  if not (fixes and fixes[1]) then return nil end
  local first, last = fixes[1], fixes[#fixes]
  if last.f > first.f then
    local size = (last.v - first.v) / (last.f - first.f)
    return first.v - first.f * size, size
  end
  local size = Intrinsic(s, horizontal)
  return first.v - first.f * size, size
end

function Layout.Rect(s)
  local left, width = Axis(s, true)
  local bottom, height = Axis(s, false)
  if left == nil or bottom == nil then return nil end
  return { left = left, right = left + width, bottom = bottom, top = bottom + height, width = width, height = height }
end

function Layout.Pin(s, left, bottom, width, height) s._pin = { left, bottom, width, height } end

local function SetPoint(s, point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" or a == nil then
    rel, relPoint, x, y = nil, point, a or 0, b or 0
  elseif type(b) == "string" then
    rel, relPoint, x, y = a, b, c or 0, d or 0
  else
    rel, relPoint, x, y = a, point, b or 0, c or 0
  end
  s._points = s._points or {}
  s._points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
end

local function Region(c, otype, parent, layer, sublevel)
  local r = c.newFrame(otype)
  r._parent, r._layer, r._sublevel, r._shown = parent, layer, sublevel or 0, true
  c.regions[#c.regions + 1] = r
  return r
end

function Layout.Install(c)
  local fm = c.frameMethods
  c.regions = {}
  fm.CreateTexture = function(s, _, layer, _, sublevel) return Region(c, "Texture", s, layer, sublevel) end
  fm.CreateFontString = function(s, _, layer)
    local fs = Region(c, "FontString", s, layer)
    fs._fontSize = 12
    return fs
  end
  fm.SetFont = function(s, _, size) s._fontSize = size; return true end
  fm.SetMaxLines = function(s, n) s._maxLines = n end
  fm.SetPoint = SetPoint
  fm.ClearAllPoints = function(s) s._points = {} end
  fm.SetAllPoints = function(s, rel)
    s._points = {}
    SetPoint(s, "TOPLEFT", rel or s._parent, "TOPLEFT", 0, 0)
    SetPoint(s, "BOTTOMRIGHT", rel or s._parent, "BOTTOMRIGHT", 0, 0)
  end
  fm.SetWidth = function(s, w) s._w = w end
  fm.SetHeight = function(s, h) s._h = h end
  fm.SetSize = function(s, w, h) s._w, s._h = w, h end
  fm.GetWidth = function(s) local _, w = Axis(s, true); return w or 0 end
  fm.GetHeight = function(s) local _, h = Axis(s, false); return h or 0 end
  fm.GetStringHeight = StringHeight
  fm.GetStringWidth = TextWidth
  fm.SetColorTexture = function(s, r, g, b, a) s._color, s._file = { r, g, b, a or 1 }, nil end
  fm.SetTexture = function(s, path) s._file, s._color = path, nil end
  fm.SetTexCoord = function(s, l, r, t, b) s._tc = { l, r, t, b } end
end

local function Within(parent, s)
  while s do
    if s == parent then return true end
    s = s._parent
  end
  return false
end

local function Visible(s, root)
  while s and s ~= root do
    if not s._shown then return false end
    s = s._parent
  end
  return true
end

function Layout.Texts(c, root)
  local out = {}
  for _, r in ipairs(c.regions) do
    if r._type == "FontString" and Within(root, r) and Visible(r, root) and r._text and r._text ~= "" then out[#out + 1] = r end
  end
  return out
end

function Layout.Inside(outer, inner, slack)
  slack = slack or 0.5
  return inner.left >= outer.left - slack and inner.right <= outer.right + slack and inner.bottom >= outer.bottom - slack
    and inner.top <= outer.top + slack
end

function Layout.Truncated(s)
  if not (s._maxLines and s._maxLines > 0) then return false end
  local _, width = Axis(s, true)
  return Layout.Lines(s._text or "", s._fontSize or 12, width) > s._maxLines
end

return Layout
