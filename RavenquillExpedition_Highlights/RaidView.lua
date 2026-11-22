local ADDON, ns = ...
local GS = RavenquillExpedition
local H, L = ns.H, ns.L
local SafeCall, Plain = GS.SafeCall, GS.Plain

local V = { top = 28, rowH = 20, rows = 8, listW = 606, nameX = 8, nameW = 172, levelX = 182, levelW = 44, raidX = 232,
  raidW = 124, bar = { 360, 18 }, missing = 3 }
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CHECK = "|T" .. READY .. ":16:16|t"
local GOLD, DIM, WHITE = { 1, 0.82, 0 }, { 0.75, 0.75, 0.75 }, { 1, 1, 1 }
local FILL = { done = { 0.18, 0.5, 0.2 }, almost = { 0.55, 0.42, 0.08 } }

local function Text(parent, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH("LEFT")
  return fs
end

local function Cell(parent, font, x, w)
  local fs = Text(parent, font)
  fs:SetPoint("LEFT", x, 0)
  fs:SetWidth(w)
  return fs
end

local function RaidX(i) return V.raidX + (i - 1) * V.raidW end

local function Tip(frame, text)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Paint(link)
  local c = (link.active and GOLD) or (link.hover and WHITE) or DIM
  link.label:SetTextColor(c[1], c[2], c[3])
  link.underline:SetShown(link.active and true or false)
end

local function Underline(owner, fs)
  local line = owner:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  line:SetHeight(2)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -3)
  return line
end

local function Link(page, text, mode)
  local b = CreateFrame("Button", nil, page)
  local fs = Text(b, "GameFontNormal")
  fs:SetPoint("LEFT")
  fs:SetText(text)
  b:SetSize(math.ceil(Plain(fs:GetStringWidth(), "number") or 0) + 4, 20)
  b.label, b.underline, b.mode = fs, Underline(b, fs), mode
  b:SetScript("OnEnter", function() b.hover = true; Paint(b) end)
  b:SetScript("OnLeave", function() b.hover = false; Paint(b) end)
  b:SetScript("OnClick", function() GS:Call(H.ShowPageView, H, page, mode) end)
  return b
end

local function ShowLog(page, on)
  for _, part in ipairs({ page.msg, page.onlyHL, page.onlyHLText, page.empty, page.footer }) do part:SetShown(on) end
end

function H:ShowPageView(page, mode)
  page.mode = mode
  page.raid:SetShown(mode == "raid")
  ShowLog(page, mode ~= "raid")
  for _, link in ipairs(page.links) do
    link.active = link.mode == mode
    Paint(link)
  end
  if mode ~= "raid" then return self:OpenLog(page) end
  GS:RequestRoster()
  self:Refresh()
end

local function CellText(st)
  if st.state == "done" then return CHECK end
  if st.state == "partial" then return "|cffffd100" .. L.RAID_PARTIAL:format(st.n, st.m) .. "|r" end
  return "|cff808080–|r"
end

local function StatusLine(st)
  local name = L["RAID_" .. st.raid]
  if st.state == "done" then return name .. ": " .. (st.declared and L.RAID_TIP_DECLARED or L.RAID_TIP_DONE) end
  local where = st.state == "partial" and L.RAID_PARTIAL:format(st.n, st.m) or L.RAID_TIP_NONE
  return name .. ": " .. where .. " · " .. L.RAID_TIP_NEXT:format(L[st.next.label])
end

local function RowTip(r)
  local row = r.row
  if not row then return end
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:AddLine(H.ClassColorName(row.who, row.class))
  for _, st in ipairs(row.raids) do GameTooltip:AddLine(StatusLine(st), 1, 1, 1, true) end
  GameTooltip:Show()
end

local function CreateRow(content)
  local r = CreateFrame("Button", nil, content)
  r:SetHeight(V.rowH)
  r.stripe = r:CreateTexture(nil, "BACKGROUND")
  r.stripe:SetAllPoints()
  r.stripe:SetColorTexture(1, 1, 1, 0.04)
  local hover = r:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
  r.name = Cell(r, "GameFontHighlight", V.nameX, V.nameW)
  r.level = Cell(r, "GameFontHighlight", V.levelX, V.levelW)
  r.cells = {}
  for i = 1, #H.RAID_KEYS do r.cells[i] = Cell(r, "GameFontHighlight", RaidX(i), V.raidW - 8) end
  r:SetScript("OnEnter", RowTip)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function RenderRow(r, row)
  r.row = row
  r.name:SetText(H.ClassColorName(row.who, row.class))
  r.level:SetText(tostring(row.level or ""))
  for i, cell in ipairs(r.cells) do cell:SetText(row.raids[i] and CellText(row.raids[i]) or "") end
  r.stripe:SetShown(row.odd or false)
end

local function BuildHeads(view)
  local head = CreateFrame("Frame", nil, view)
  head:SetPoint("TOPLEFT")
  head:SetSize(V.listW, V.rowH)
  Cell(head, "GameFontNormal", V.nameX, V.nameW):SetText(L.COL_NAME)
  Cell(head, "GameFontNormal", V.levelX, V.levelW):SetText(L.COL_LEVEL)
  view.heads = {}
  for i = 1, #H.RAID_KEYS do
    local b = CreateFrame("Button", nil, head)
    b:SetPoint("LEFT", RaidX(i) - 4, 0)
    b:SetSize(V.raidW, V.rowH)
    b.label = Text(b, "GameFontNormal")
    b.label:SetPoint("LEFT", 4, 0)
    b.underline = Underline(b, b.label)
    b:SetScript("OnClick", function() GS:Call(H.FocusRaid, H, b.raid) end)
    Tip(b, L.RAID_FOCUS_TIP)
    view.heads[i] = b
  end
end

local function BuildTable(view)
  BuildHeads(view)
  view.list = GS.CreateScrollList(view, V.listW, V.rows * V.rowH,
    { default = { create = CreateRow, update = RenderRow, height = V.rowH } })
  view.list:SetPoint("TOPLEFT", 0, -V.rowH - 2)
  view.empty = Text(view, "GameFontDisable")
  view.empty:SetPoint("TOPLEFT", view.list, "TOPLEFT", V.nameX, -6)
  view.empty:SetText(L.RAID_EMPTY:format(H.RAID_LEVEL))
  view.hidden = Text(view, "GameFontDisableSmall")
  view.hidden:SetPoint("TOPLEFT", view.list, "BOTTOMLEFT", V.nameX, -6)
end

local function Bar(view)
  local bar = CreateFrame("Frame", nil, view)
  bar:SetSize(V.bar[1], V.bar[2])
  local edge = bar:CreateTexture(nil, "BACKGROUND")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(GOLD[1] * 0.6, GOLD[2] * 0.6, GOLD[3] * 0.6, 1)
  local bg = bar:CreateTexture(nil, "BORDER")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.03, 0.03, 1)
  bar.done = bar:CreateTexture(nil, "ARTWORK")
  bar.done:SetPoint("TOPLEFT")
  bar.done:SetPoint("BOTTOMLEFT")
  bar.done:SetColorTexture(FILL.done[1], FILL.done[2], FILL.done[3], 1)
  bar.almost = bar:CreateTexture(nil, "ARTWORK")
  bar.almost:SetPoint("TOPLEFT", bar.done, "TOPRIGHT")
  bar.almost:SetPoint("BOTTOMLEFT", bar.done, "BOTTOMRIGHT")
  bar.almost:SetColorTexture(FILL.almost[1], FILL.almost[2], FILL.almost[3], 1)
  bar.text = Text(bar, "GameFontHighlight")
  bar.text:SetPoint("CENTER")
  return bar
end

local function BuildSummary(view)
  view.rule = view:CreateTexture(nil, "ARTWORK")
  view.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
  view.rule:SetHeight(1)
  view.rule:SetPoint("TOPLEFT", view.list, "BOTTOMLEFT", 0, -24)
  view.rule:SetPoint("RIGHT", view, "RIGHT", -8, 0)
  view.head = Text(view, "GameFontNormalLarge")
  view.head:SetPoint("TOPLEFT", view.rule, "BOTTOMLEFT", 0, -12)
  view.bar = Bar(view)
  view.bar:SetPoint("TOPLEFT", view.head, "BOTTOMLEFT", 10, -10)
  view.missing = Text(view, "GameFontHighlight")
  view.missing:SetPoint("TOPLEFT", view.bar, "BOTTOMLEFT", 0, -14)
  view.missing:SetPoint("RIGHT", view, "RIGHT", -8, 0)
  view.missing:SetSpacing(4)
end

local function BuildTicks(view)
  view.note = Text(view, "GameFontDisableSmall")
  view.note:SetPoint("BOTTOMLEFT", 8, 6)
  view.note:SetText(L.RAID_NOTE)
  view.tickLabel = Text(view, "GameFontHighlightSmall")
  view.tickLabel:SetPoint("BOTTOMLEFT", 8, 34)
  view.tickLabel:SetText(L.RAID_TICKS)
  view.ticks = {}
  local anchor = view.tickLabel
  for i, raid in ipairs(H.RAID_KEYS) do
    local box, text = H.CheckBox(view, L["RAID_" .. raid])
    box:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 14, 0)
    box.raid, box.text = raid, text
    box:SetScript("OnClick", function(self) GS:Call(H.TickRaid, H, self) end)
    Tip(box, L.RAID_TICK_TIP)
    view.ticks[i], anchor = box, text
  end
end

function H:BuildRaidView(page)
  page.links = { Link(page, L.VIEW_LOG, "log"), Link(page, L.VIEW_RAID, "raid") }
  page.links[1]:SetPoint("TOPLEFT", 6, -2)
  page.links[2]:SetPoint("LEFT", page.links[1], "RIGHT", 18, 0)
  for _, link in ipairs(page.links) do
    link.active = link.mode == "log"
    Paint(link)
  end
  local view = CreateFrame("Frame", nil, page)
  view:SetPoint("TOPLEFT", 0, -V.top)
  view:SetPoint("BOTTOMRIGHT")
  view:Hide()
  BuildTable(view)
  BuildSummary(view)
  BuildTicks(view)
  page.raid, self.raidPage = view, page
end

local function RenderHeads(view, model, focus)
  for i, b in ipairs(view.heads) do
    local a = model.raids[i]
    b.raid = a and a.raid
    b.label:SetText(a and L["COL_" .. a.raid] or "")
    b.underline:SetShown(b.raid ~= nil and b.raid == focus)
  end
end

local function Rows(model)
  for i, row in ipairs(model.rows) do row.odd = i % 2 == 0 end
  return model.rows
end

local function HiddenText(model)
  local parts = {}
  if model.low > 0 then parts[#parts + 1] = L.RAID_LOW:format(model.low, H.RAID_LEVEL) end
  if model.away > 0 then parts[#parts + 1] = L.RAID_AWAY:format(model.away) end
  return parts[1] and L.RAID_HIDDEN:format(table.concat(parts, " · ")) or ""
end

local function MissingText(s)
  if s.total > 0 and not s.missing[1] then return L.RAID_ALL end
  local lines = {}
  for i = 1, math.min(#s.missing, V.missing) do
    local m = s.missing[i]
    lines[i] = L.RAID_MISSING:format(H.ClassColorName(m.who, m.class), L[m.step.label])
  end
  if #s.missing > V.missing then lines[#lines + 1] = L.RAID_MORE:format(#s.missing - V.missing) end
  return table.concat(lines, "\n")
end

local function RenderBar(bar, s)
  local room = V.bar[1]
  local function Fill(t, n)
    t:SetWidth(math.max(1, room * n / math.max(1, s.total)))
    t:SetShown(n > 0)
  end
  Fill(bar.done, s.done)
  Fill(bar.almost, s.almost)
  bar.text:SetText(L.RAID_COUNT:format(s.done, s.almost))
end

local function RenderTicks(view, model)
  local level = Plain(SafeCall(UnitLevel, "player"), "number") or 0
  local shown = level >= H.RAID_LEVEL
  view.tickLabel:SetShown(shown)
  for i, box in ipairs(view.ticks) do
    local st = model.mine[i]
    local done = st and st.state == "done" or false
    box:SetChecked(done)
    if done then box:Disable() else box:Enable() end
    box:SetShown(shown)
    box.text:SetShown(shown)
  end
end

function H:RenderRaid(page)
  local view, model = page.raid, self:ReadinessModel()
  local summary = H.RaidSummary(model, self:Settings().raidFocus)
  RenderHeads(view, model, summary.raid)
  view.list:SetData(Rows(model))
  view.empty:SetShown(not model.rows[1])
  view.hidden:SetText(HiddenText(model))
  view.head:SetText(L.RAID_HEAD:format(L["RAID_" .. summary.raid]))
  RenderBar(view.bar, summary)
  view.missing:SetText(MissingText(summary))
  RenderTicks(view, model)
end

function H:FocusRaid(raid)
  self:Settings().raidFocus = raid
  self:RenderRaid(self.raidPage)
end

function H:TickRaid(box)
  if box:GetChecked() then self:DeclareAttuned(box.raid) end
  self:RenderRaid(self.raidPage)
end

H:RegisterEvent("GUILD_ROSTER_UPDATE", function(self)
  local page = self.raidPage
  if self.db and page and page:IsVisible() and page.mode == "raid" then self:RenderRaid(page) end
end)
