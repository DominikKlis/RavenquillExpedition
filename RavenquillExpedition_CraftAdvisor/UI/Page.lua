local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P

local ROW = { height = 42, gap = 10, icon = 30, inset = 12, top = 10, more = "›" }

local function RowTip(row)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(L[row.view.label], 1, 0.82, 0)
  for _, line in ipairs(row.view.tooltip()) do GameTooltip:AddLine(line, 1, 1, 1, true) end
  GameTooltip:Show()
end

local function RowText(row, template, point, rel, relPoint, x)
  local fs = row:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint(point, rel, relPoint, x, 0)
  return fs
end

local function NewRow(page, i, view)
  local row = CreateFrame("Button", nil, page, "BackdropTemplate")
  row.view = view
  row:SetHeight(ROW.height)
  row:SetPoint("TOPLEFT", 6, -ROW.top - (i - 1) * (ROW.height + ROW.gap))
  row:SetPoint("RIGHT", page, "RIGHT", -2, 0)
  if row.SetBackdrop then P.Backdrop(row, 0.7) end
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 0.82, 0, 0.08)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW.icon, ROW.icon)
  row.icon:SetPoint("LEFT", ROW.inset, 0)
  row.icon:SetTexture(view.icon)
  row.label = RowText(row, "GameFontNormalLarge", "LEFT", row.icon, "RIGHT", ROW.inset)
  row.label:SetText(L[view.label])
  row.more = RowText(row, "GameFontNormalLarge", "RIGHT", row, "RIGHT", -ROW.inset)
  row.more:SetText(ROW.more)
  row.count = RowText(row, "GameFontHighlightLarge", "RIGHT", row.more, "LEFT", -2 * ROW.inset)
  row:SetScript("OnClick", function(self) GCA:OpenView(self.view.id) end)
  P.SetTip(row, "page row", RowTip)
  row:SetScript("OnLeave", GameTooltip_Hide)
  return row
end

function GCA:BuildPage(page)
  page.rows = {}
  for i, view in ipairs(UI.VIEWS) do page.rows[i] = NewRow(page, i, view) end
  self.page = page
end

function GCA:RefreshPage()
  if not (self.page and self.db) then return end
  for _, row in ipairs(self.page.rows) do
    local n = row.view.count()
    row.count:SetText(n and tostring(n) or "")
  end
end
