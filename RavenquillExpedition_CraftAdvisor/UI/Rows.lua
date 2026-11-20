local ADDON, ns = ...
local GCA = ns.GCA
local UI = GCA.UI
local P = UI.P
local HasAtlas, SetAtlasSafe, SingleLine = P.HasAtlas, P.SetAtlasSafe, P.SingleLine
local NativeFont, GROUP_ROW_H = P.NativeFont, P.GROUP_ROW_H

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
