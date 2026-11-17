local ADDON, ns = ...
local GCA = ns.GCA
local UI = GCA.UI
local P = UI.P
local SafeCall, HasAtlas, SetAtlasSafe, SingleLine = P.SafeCall, P.HasAtlas, P.SetAtlasSafe, P.SingleLine
local NativeFont, GROUP_ROW_H = P.NativeFont, P.GROUP_ROW_H

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
    sf:HookScript("OnShow", function(self) if self.UpdateBar then self:UpdateBar() end end)
    sf:HookScript("OnHide", function() bar:Hide() end)
  else
    bar:Hide()
    sf:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:Offset() - delta * 30) end)
  end
end

local function NextRow(sf, kinds, used, d)
  local name = kinds[d.rowKind] and d.rowKind or "default"
  local n = (used[name] or 0) + 1
  used[name] = n
  local pool = sf.pools[name] or {}
  sf.pools[name] = pool
  pool[n] = pool[n] or kinds[name].create(sf.content)
  return pool[n], kinds[name]
end

local function CreateScrollList(parent, width, height, kinds)
  local sf = NewScrollFrame(parent)
  sf:SetSize(width, height)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(width, 1)
  sf:SetScrollChild(content)
  LinkScrollBar(sf)
  sf.content = content
  sf.pools, sf.rowY, sf.viewW, sf.viewH, sf.contentH = { default = {} }, {}, width, height, 0
  function sf:SetData(data)
    local used, y = {}, 0
    self.data = data
    self.rowY = {}
    for _, d in ipairs(data) do
      local row, kind = NextRow(self, kinds, used, d)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -y)
      row:SetPoint("RIGHT", content, "RIGHT")
      row.data = d
      kind.update(row, d, self.viewW)
      local h = kind.height
      if type(h) == "function" then
        h = h(row, d, self.viewW)
        row:SetHeight(h - 2)
      end
      self.rowY[#self.rowY + 1] = { y, h }
      row:Show()
      y = y + h
    end
    for name, pool in pairs(self.pools) do
      for i = (used[name] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.contentH = y
    content:SetHeight(math.max(1, y))
    self:UpdateBar()
  end
  function sf:UpdateBar()
    local bar = self.minimalBar
    if not bar then return end
    local need = (self.contentH or 0) > (self.viewH or 0) + 0.5
    local shown = self.IsVisible and self:IsVisible() or (self.IsShown and self:IsShown())
    bar:SetShown(need and shown and true or false)
    if not need and (self.scrolledTo or 0) > 0 then self:ScrollTo(0) end
  end
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
  function sf:FindY(match)
    for i, d in ipairs(self.data or {}) do
      if match(d) and self.rowY[i] then return self.rowY[i][1] end
    end
  end
  function sf:Offset()
    local get = self.GetVerticalScroll; local v = get and SafeCall(get, self)
    if type(v) == "number" and not GCA.IsSecret(v) then return v end
    return self.scrolledTo or 0
  end
  function sf:VisibleRows()
    local top = self:Offset()
    local bottom, n = top + (self.viewH or 0), 0
    for _, r in ipairs(self.rowY) do
      if r[1] >= top and r[1] + r[2] <= bottom then n = n + 1 end
    end
    return n
  end
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
function UI.RowFont(fs)
  NativeFont(fs, "GameFontHighlight_NoShadow")
  return fs
end

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
  function b:SetCategory(text, open, rowW)
    self.text:SetText(text)
    self.text:SetWidth(math.max(20, rowW - 8 - 32))
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

P.CreateScrollList = CreateScrollList
