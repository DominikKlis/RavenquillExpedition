local _, ns = ...

local WHEEL_STEP = 40
local BAR_WIDTH, ART_WIDTH, CAP, MIN_THUMB = 12, 8, 8, 24
local FADE_STEPS, FADE_STEP_HEIGHT, FADE_ALPHA = 16, 3, 0.92
local FADE_RGB = { 0.06, 0.045, 0.03 }
local FADE_LEVEL_ABOVE_CONTENT = 10
local TRACK_ART = { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom" }
local THUMB_ART = { "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-middle", "minimal-scrollbar-small-thumb-bottom" }

local function Height(frame) return frame and frame:GetHeight() or 0 end

local function Range(sf) return math.max(0, Height(sf.page) - Height(sf)) end

local function Thumb(viewH, max, offset)
  local h = math.min(viewH, math.max(MIN_THUMB, viewH * viewH / (viewH + max)))
  local top = max > 0 and (viewH - h) * offset / max or 0
  return h, top
end

local function Refresh(sf)
  local bar, fade = sf.scrollBar, sf.scrollFade
  if not bar then return end
  local viewH, max = Height(sf), Range(sf)
  local offset = math.min(sf:GetVerticalScroll(), max)
  local scrollable = sf:IsShown() and max > 0
  bar:SetShown(scrollable)
  fade:SetShown(scrollable and max - offset > 0.5)
  if not scrollable then return end
  local h, top = Thumb(viewH, max, offset)
  bar.thumb:SetHeight(h)
  bar.thumb:SetPoint("TOP", bar, "TOP", 0, -top)
end

function ns.ScrollTo(sf, offset)
  sf:SetVerticalScroll(math.max(0, math.min(Range(sf), offset)))
  Refresh(sf)
end

function ns.SetScrollPage(sf, page)
  sf.page = page
  sf:SetScrollChild(page)
  ns.ScrollTo(sf, 0)
end

local function Wheel(sf, delta) ns.ScrollTo(sf, sf:GetVerticalScroll() - delta * WHEEL_STEP) end

function ns.WheelScroll(sf)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", Wheel)
end

local function Column(frame, layer, art, r, g, b, a)
  local top, mid, bottom = frame:CreateTexture(nil, layer), frame:CreateTexture(nil, layer), frame:CreateTexture(nil, layer)
  top:SetSize(ART_WIDTH, CAP)
  top:SetPoint("TOP")
  bottom:SetSize(ART_WIDTH, CAP)
  bottom:SetPoint("BOTTOM")
  mid:SetWidth(ART_WIDTH)
  mid:SetPoint("TOP", top, "BOTTOM")
  mid:SetPoint("BOTTOM", bottom, "TOP")
  local pieces = { top, mid, bottom }
  local drawn = true
  for i, t in ipairs(pieces) do drawn = ns.SetAtlas(t, art[i]) and drawn end
  if drawn then return end
  for _, t in ipairs(pieces) do t:SetColorTexture(r, g, b, a) end
end

local function CursorFromTop(bar)
  local _, y = GetCursorPosition()
  return bar:GetTop() - y / bar:GetEffectiveScale()
end

local function DragTo(sf, bar)
  local viewH, max = Height(sf), Range(sf)
  local h = Thumb(viewH, max, 0)
  if viewH <= h then return end
  ns.ScrollTo(sf, (CursorFromTop(bar) - bar.grab) * max / (viewH - h))
end

local function StopDrag(bar) bar:SetScript("OnUpdate", nil) end

local function StartDrag(sf, bar)
  local max = Range(sf)
  local h, top = Thumb(Height(sf), max, math.min(sf:GetVerticalScroll(), max))
  local at = CursorFromTop(bar)
  bar.grab = (at >= top and at <= top + h) and at - top or h / 2
  DragTo(sf, bar)
  bar:SetScript("OnUpdate", function() DragTo(sf, bar) end)
end

local function ScrollBar(sf, parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(BAR_WIDTH)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", -7, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", -7, 0)
  bar:EnableMouse(true)
  bar:EnableMouseWheel(true)
  bar:SetScript("OnMouseWheel", function(_, delta) Wheel(sf, delta) end)
  Column(bar, "BACKGROUND", TRACK_ART, 0, 0, 0, 0.45)
  bar.thumb = CreateFrame("Frame", nil, bar)
  bar.thumb:SetWidth(ART_WIDTH)
  Column(bar.thumb, "ARTWORK", THUMB_ART, 0.72, 0.56, 0.25, 0.95)
  bar:SetScript("OnMouseDown", function() StartDrag(sf, bar) end)
  bar:SetScript("OnMouseUp", StopDrag)
  bar:SetScript("OnHide", StopDrag)
  bar:Hide()
  return bar
end

local function Fade(sf, parent, bar)
  local fade = CreateFrame("Frame", nil, parent)
  fade:SetPoint("BOTTOMLEFT", sf, "BOTTOMLEFT")
  fade:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT")
  fade:SetHeight(FADE_STEPS * FADE_STEP_HEIGHT)
  fade:SetFrameLevel(sf:GetFrameLevel() + FADE_LEVEL_ABOVE_CONTENT)
  for i = 1, FADE_STEPS do
    local t = fade:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 0, -(i - 1) * FADE_STEP_HEIGHT)
    t:SetPoint("TOPRIGHT", 0, -(i - 1) * FADE_STEP_HEIGHT)
    t:SetHeight(FADE_STEP_HEIGHT)
    t:SetColorTexture(FADE_RGB[1], FADE_RGB[2], FADE_RGB[3], FADE_ALPHA * i / FADE_STEPS)
  end
  fade:Hide()
  return fade
end

function ns.PageScroll(sf)
  local parent = sf:GetParent()
  ns.WheelScroll(sf)
  sf.scrollBar = ScrollBar(sf, parent)
  sf.scrollFade = Fade(sf, parent, sf.scrollBar)
  local function OnChange() Refresh(sf) end
  for _, event in ipairs({ "OnShow", "OnHide", "OnSizeChanged", "OnScrollRangeChanged", "OnVerticalScroll" }) do
    sf:HookScript(event, OnChange)
  end
end
