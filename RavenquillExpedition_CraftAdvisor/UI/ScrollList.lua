local ADDON, ns = ...
local GCA = ns.GCA
local UI = GCA.UI
local P = UI.P
local SafeCall = P.SafeCall

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
      update(row, d, n, #self.rowY + 1, data)
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

P.CreateScrollList = CreateScrollList
