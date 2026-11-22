local ADDON, ns = ...
local GS = RavenquillExpedition
local G, L, P = ns.G, ns.L, ns.Posts

local UI = {}
ns.UI = UI

local SIZE = { listW = 612, listH = 436, top = 34, pad = 14, pill = 20, pillGap = 6, button = 100, row = 22, signup = 24,
  base = 130, rowsExtra = 4, gap = 8 }
UI.SIZE = SIZE

local CARD_BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local PILL_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } }
local PILL_STYLE = {
  wanted = { 0.42, 0.11, 0.07, 0.78, 0.33, 0.24 },
  full = { 0.12, 0.36, 0.14, 0.38, 0.72, 0.38 },
  part = { 0.24, 0.21, 0.16, 0.58, 0.52, 0.42 },
  fit = { 0.52, 0.39, 0.06, 0.88, 0.72, 0.26 },
  own = { 0.16, 0.27, 0.42, 0.42, 0.6, 0.85 },
}

function UI.Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

function UI.Button(parent, width, text, onClick, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or SIZE.row)
  b:SetText(text or "")
  b:SetScript("OnClick", onClick)
  return b
end

function UI.Backdrop(f, backdrop, bg, border)
  if not f.SetBackdrop then return end
  f:SetBackdrop(backdrop)
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
end

function UI.Card(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  UI.Backdrop(f, CARD_BACKDROP, { 0.05, 0.035, 0.02, 0.8 }, { 0.36, 0.28, 0.18 })
  return f
end

local function TextWidth(fs, text)
  local w = fs:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = #text * 6 end
  return w
end

local function NewPill(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetHeight(SIZE.pill)
  f.text = UI.Text(f, "GameFontHighlight", "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  return f
end

local function FillPill(f, text, style)
  local s = PILL_STYLE[style]
  UI.Backdrop(f, PILL_BACKDROP, { s[1], s[2], s[3], 0.95 }, { s[4], s[5], s[6] })
  f.text:SetText(text)
  f:SetWidth(math.floor(TextWidth(f.text, text) + 20))
  f.style = style
  f:Show()
end

local function SignupRow(card, i)
  local row = card.rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, card.box)
  row:SetHeight(SIZE.signup)
  row:SetPoint("TOPLEFT", card.pillRow, "BOTTOMLEFT", 0, -10 - (i - 1) * SIZE.signup)
  row:SetPoint("RIGHT", card.box, "RIGHT", -SIZE.pad, 0)
  row.text = UI.Text(row, "GameFontHighlight")
  row.text:SetPoint("LEFT", 2, 0)
  row.invite = UI.Button(row, 90, L.INVITE, function(b) G:Invite(b.who) end, 20)
  row.invite:SetPoint("RIGHT", 0, 0)
  card.rows[i] = row
  return row
end

function UI.SignUpMenu(button, p)
  local roles = P.OpenRoles(p)
  if #roles == 1 or not (MenuUtil and MenuUtil.CreateContextMenu) then return G:SignUp(p.poster, roles[1]) end
  GS:Call(MenuUtil.CreateContextMenu, button, function(_, root)
    root:CreateTitle(L.SIGN_UP_AS)
    for _, role in ipairs(roles) do
      root:CreateButton(ns.View.RoleName(role), function() G:SignUp(p.poster, role) end)
    end
  end)
end

local function NewCard(parent)
  local c = CreateFrame("Frame", nil, parent)
  c.box = UI.Card(c)
  c.box:SetPoint("TOPLEFT", 0, 0)
  c.box:SetPoint("BOTTOMRIGHT", 0, SIZE.gap)
  c.title = UI.Text(c.box, "GameFontNormalLarge")
  c.title:SetPoint("TOPLEFT", SIZE.pad, -SIZE.pad)
  c.total = UI.Text(c.box, "GameFontHighlightLarge", "RIGHT")
  c.total:SetPoint("TOPRIGHT", -SIZE.pad, -SIZE.pad)
  c.title:SetPoint("RIGHT", c.total, "LEFT", -8, 0)
  c.line = UI.Text(c.box, "GameFontHighlight")
  c.line:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -8)
  c.line:SetPoint("RIGHT", c.box, "RIGHT", -SIZE.pad, 0)
  c.line:SetMaxLines(1)
  c.pillRow = CreateFrame("Frame", nil, c.box)
  c.pillRow:SetHeight(SIZE.pill)
  c.pillRow:SetPoint("TOPLEFT", c.line, "BOTTOMLEFT", 0, -12)
  c.pillRow:SetPoint("RIGHT", c.box, "RIGHT", -SIZE.pad, 0)
  c.pills, c.rows = {}, {}
  c.tag = NewPill(c.box)
  c.tag:SetPoint("BOTTOMLEFT", SIZE.pad, SIZE.pad + 1)
  c.action = UI.Button(c.box, SIZE.button, "", function(b) UI.SignUpMenu(b, c.data.post) end)
  c.action:SetPoint("BOTTOMRIGHT", -SIZE.pad, SIZE.pad)
  c.close = UI.Button(c.box, SIZE.button, L.CLOSE, function() G:Close() end)
  c.close:SetPoint("BOTTOMRIGHT", -SIZE.pad, SIZE.pad)
  c.edit = UI.Button(c.box, SIZE.button, L.EDIT, function() ns.Form.Open(G.page.form, G:OwnPost()) end)
  c.edit:SetPoint("RIGHT", c.close, "LEFT", -6, 0)
  return c
end

local function FillPills(c, pills)
  for i, pill in ipairs(pills) do
    local f = c.pills[i] or NewPill(c.pillRow)
    c.pills[i] = f
    f:ClearAllPoints()
    if i == 1 then f:SetPoint("LEFT", c.pillRow, "LEFT", 0, 0) else f:SetPoint("LEFT", c.pills[i - 1], "RIGHT", SIZE.pillGap, 0) end
    FillPill(f, pill.text, pill.style)
  end
  for i = #pills + 1, #c.pills do c.pills[i]:Hide() end
end

local function FillSignups(c, signups)
  local list = signups or {}
  local shown = signups and math.max(1, #list) or 0
  for i = 1, shown do
    local row, s = SignupRow(c, i), list[i]
    row.text:SetText(s and s.text or L.NO_SIGNUPS)
    row.invite.who = s and s.who
    row.invite:SetShown(s ~= nil)
    row:Show()
  end
  for i = shown + 1, #c.rows do c.rows[i]:Hide() end
end

local function FillActions(c, vm)
  local a = vm.action
  c.action:SetShown(a ~= nil)
  if a then
    c.action:SetText(a.label)
    c.action:SetEnabled(a.enabled)
  end
  c.close:SetShown(vm.own)
  c.edit:SetShown(vm.own)
  if vm.own then FillPill(c.tag, L.YOUR_POST, "own") elseif vm.fits then FillPill(c.tag, L.FITS, "fit") else c.tag:Hide() end
end

function UI.FillCard(c, vm)
  c.title:SetText(vm.title)
  c.total:SetText(vm.total)
  c.line:SetText(vm.line)
  FillPills(c, vm.pills)
  FillSignups(c, vm.signups)
  FillActions(c, vm)
end

function UI.BoxHeight(vm)
  if not vm.signups then return SIZE.base end
  return SIZE.base + SIZE.rowsExtra + math.max(1, #vm.signups) * SIZE.signup
end

function UI.CardHeight(_, vm) return UI.BoxHeight(vm) + SIZE.gap + 2 end

function G:BuildPage(page)
  page.find = UI.Button(page, 150, L.FIND, function() ns.Form.Open(page.form, G:OwnPost()) end)
  page.find:SetPoint("TOPRIGHT", -2, -2)
  page.hint = UI.Text(page, "GameFontHighlightSmall")
  page.hint:SetPoint("TOPLEFT", 4, -8)
  page.hint:SetPoint("RIGHT", page.find, "LEFT", -10, 0)
  page.hint:SetTextColor(0.8, 0.8, 0.8)
  page.hint:SetText(L.HINT)
  page.list = GS.CreateScrollList(page, SIZE.listW, SIZE.listH,
    { default = { create = NewCard, update = UI.FillCard, height = UI.CardHeight } })
  page.list:SetPoint("TOPLEFT", 0, -SIZE.top)
  page.empty = UI.Text(page, "GameFontDisable", "CENTER")
  page.empty:SetPoint("TOP", page, "TOP", 0, -SIZE.top - 40)
  page.empty:SetText(L.EMPTY)
  page.form = ns.Form.Build(page)
  page:SetScript("OnShow", function() G:RenderPage() end)
  self.page = page
end

function G:Cards()
  local out = {}
  for i, p in ipairs(self:ActivePosts()) do out[i] = ns.View.Card(p) end
  return out
end

function G:RenderPage()
  local page = self.page
  if not (page and page:IsVisible()) then return end
  local editing = page.form:IsShown()
  local cards = editing and {} or self:Cards()
  page.list:SetData(cards)
  page.list:SetShown(not editing)
  page.empty:SetShown(not editing and #cards == 0)
  page.hint:SetShown(not editing)
  page.find:SetShown(not editing)
  page.find:SetText(self:OwnPost() and L.FIND_EDIT or L.FIND)
end

function G:RefreshPage() self:RenderPage() end
