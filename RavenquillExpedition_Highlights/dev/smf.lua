local SMF = {}
local Mixin = {}
local WHITE = { 1, 1, 1 }

local function Release(s)
  for _, fs in ipairs(s.active) do
    fs:Hide()
    fs:ClearAllPoints()
    s.inactive[#s.inactive + 1] = fs
  end
  s.active = {}
end

local function InitializeFontString(s, fs)
  fs:SetText(nil)
  fs:SetFontObject(s.font.object)
  if s.font.justifyH then fs:SetJustifyH(s.font.justifyH) end
end

local function Acquire(s)
  local fs = table.remove(s.inactive) or s.FontStringContainer:CreateFontString(nil, "BACKGROUND")
  s.active[#s.active + 1] = fs
  InitializeFontString(s, fs)
  return fs
end

local function LineSpacing(s)
  local fs = Acquire(s)
  fs:SetText("X")
  local spacing = fs:GetStringHeight()
  fs:SetText(nil)
  table.remove(s.active)
  fs:Hide()
  s.inactive[#s.inactive + 1] = fs
  return spacing
end

function Mixin.RefreshLayout(s)
  s.isLayoutDirty = false
  Release(s)
  local spacing, height, width = LineSpacing(s), s:GetHeight(), s:GetWidth()
  local n = spacing > 0 and math.ceil(height / spacing) + 1 or 0
  for i = 1, n do
    local fs = Acquire(s)
    s.visibleLines[i] = fs
    if i == 1 then fs:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT") else fs:SetPoint("BOTTOMLEFT", s.visibleLines[i - 1], "TOPLEFT", 0, 0) end
    fs:SetWidth(width)
  end
  for i = #s.visibleLines, n, -1 do s.visibleLines[i] = nil end
  s.laidOut = { width, height }
  s.isDisplayDirty = true
end

function Mixin.RefreshDisplay(s)
  for i, line in ipairs(s.visibleLines) do
    local info = s.history[i + s.scrollOffset]
    line.messageInfo = info
    if info then
      InitializeFontString(s, line)
      line:SetText(info.message)
      line:SetTextColor(info.r or WHITE[1], info.g or WHITE[2], info.b or WHITE[3])
      line:Show()
    else
      line:Hide()
    end
  end
  for _, callback in ipairs(s.onDisplayRefreshedCallbacks) do callback(s) end
  s.isDisplayDirty = false
end

function Mixin.AddMessage(s, message, r, g, b, ...)
  local extra = select("#", ...) > 0 and { n = select("#", ...), ... } or nil
  table.insert(s.history, 1, { message = message, r = r, g = g, b = b, extraData = extra })
  if #s.history > s.maxLines then table.remove(s.history) end
  if s.scrollOffset ~= 0 then s:ScrollUp() end
  s.isDisplayDirty = true
end

function Mixin.Clear(s)
  if not s.history[1] then return end
  s.history = {}
  s:SetScrollOffset(0)
  s.isDisplayDirty = true
end

function Mixin.SetScrollOffset(s, offset)
  local clamped = math.max(0, math.min(offset, s:GetMaxScrollRange()))
  if clamped ~= s.scrollOffset then
    s.scrollOffset = clamped
    s.isDisplayDirty = true
  end
end

function Mixin.GetScrollOffset(s) return s.scrollOffset end
function Mixin.GetMaxScrollRange(s) return math.max(#s.history - 1, 0) end
function Mixin.GetNumMessages(s) return #s.history end
function Mixin.GetNumVisibleLines(s) return #s.visibleLines end
function Mixin.ScrollUp(s) s:SetScrollOffset(s.scrollOffset + 1) end
function Mixin.ScrollDown(s) s:SetScrollOffset(s.scrollOffset - 1) end
function Mixin.ScrollToTop(s) s:SetScrollOffset(s:GetMaxScrollRange()) end
function Mixin.ScrollToBottom(s) s:SetScrollOffset(0) end
function Mixin.AtBottom(s) return s.scrollOffset == 0 end
function Mixin.SetMaxLines(s, n) s.maxLines = n end
function Mixin.GetMaxLines(s) return s.maxLines end
function Mixin.AddOnDisplayRefreshedCallback(s, callback) s.onDisplayRefreshedCallbacks[#s.onDisplayRefreshedCallbacks + 1] = callback end

function Mixin.SetFontObject(s, object)
  s.font = { object = object }
  s.isLayoutDirty = true
end

function Mixin.GetFontObject(s) return s.font.object end

function Mixin.SetJustifyH(s, justifyH)
  s.font.justifyH = justifyH
  s.isLayoutDirty = true
end

local function Resized(s)
  local size = s.laidOut
  return not size or size[1] ~= s:GetWidth() or size[2] ~= s:GetHeight()
end

function SMF.Tick(s)
  if Resized(s) then s.isLayoutDirty = true end
  if s.isLayoutDirty then s:RefreshLayout() end
  if s.isDisplayDirty then s:RefreshDisplay() end
end

local function Build(c, s)
  for name, fn in pairs(Mixin) do s[name] = fn end
  s.history, s.maxLines, s.scrollOffset = {}, 120, 0
  s.visibleLines, s.onDisplayRefreshedCallbacks = {}, {}
  s.active, s.inactive, s.font = {}, {}, {}
  s.FontStringContainer = c.newFrame("Frame", nil, s)
  s.FontStringContainer:SetAllPoints(s)
  s.FontStringContainer:SetClipsChildren(true)
  c.messageFrames[#c.messageFrames + 1] = s
end

function SMF.Install(c)
  c.messageFrames = {}
  local base = c.newFrame
  c.newFrame = function(otype, ...)
    local f = base(otype, ...)
    if otype == "ScrollingMessageFrame" then Build(c, f) end
    return f
  end
end

function SMF.TickAll(c)
  for _, s in ipairs(c.messageFrames or {}) do SMF.Tick(s) end
end

return SMF
