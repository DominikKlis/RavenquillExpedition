local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, C, HasAtlas, SetAtlasSafe, TexOK = P.SafeCall, P.C, P.HasAtlas, P.SetAtlasSafe, P.TexOK
local StatLabel, Backdrop = P.StatLabel, P.Backdrop
local SetTip = P.SetTip

local function AddBorder(f, r, g, b, a)
  local e = {}
  for i = 1, 4 do e[i] = f:CreateTexture(nil, "BORDER") end
  e[1]:SetPoint("TOPLEFT", f, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT"); e[1]:SetHeight(1)
  e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); e[2]:SetHeight(1)
  e[3]:SetPoint("TOPLEFT", f, "TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); e[3]:SetWidth(1)
  e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); e[4]:SetWidth(1)
  f.edges = e
  function f:SetBorderColor(r2, g2, b2, a2)
    for _, t in ipairs(self.edges) do t:SetColorTexture(r2, g2, b2, a2 or 1) end
  end
  f:SetBorderColor(r, g, b, a)
end
UI.AddBorder = AddBorder

local function TextWidth(fs)
  for _, m in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[m]
    if type(fn) == "function" then
      local w = SafeCall(fn, fs)
      if type(w) == "number" and not GCA.IsSecret(w) and w > 0 then return math.ceil(w) end
    end
  end
  local t = tostring(fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\128-\191]", "")
  return math.ceil(#t * 6)
end
UI.TextWidth = TextWidth

local function ShiftDown()
  return IsShiftKeyDown and SafeCall(IsShiftKeyDown) and true or false
end

local function ModifiedDown()
  if ShiftDown() then return true end
  return IsControlKeyDown and SafeCall(IsControlKeyDown) and true or false
end

local function OnItemClick(btn, ctxFn, primaryFn)
  btn:SetScript("OnClick", function(self, button)
    local d, cur, link = ctxFn(self)
    if d and UI.SourceClick(self, button, d, cur) then return end
    if ModifiedDown() then
      if link then SafeCall(HandleModifiedItemClick, link) end
      return
    end
    if primaryFn then primaryFn(d, cur, self) end
  end)
end

local function NewTextButton(parent, w, h, text)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not (ok and b) then
    b = CreateFrame("Button", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.3, 0.06, 0.04, 0.95)
    AddBorder(b, 0.72, 0.54, 0.18, 1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end
    b.plain = true
  end
  b:SetSize(w, h)
  b:SetText(text)
  return b
end
UI.NewTextButton = NewTextButton

local function NewCheck(parent, size)
  local ok, c
  for _, tpl in ipairs({ "MinimalCheckboxTemplate", "UICheckButtonTemplate" }) do
    ok, c = pcall(CreateFrame, "CheckButton", nil, parent, tpl)
    if ok and c then c.template = tpl; break end
  end
  if not (ok and c) then
    c = CreateFrame("CheckButton", nil, parent)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0.05, 0.05, 0.04, 0.9)
    AddBorder(c, 0.42, 0.38, 0.31, 1)
    if c.SetCheckedTexture and TexOK("check") then pcall(c.SetCheckedTexture, c, UI.TEX.check) end
    c.plain = true
  end
  c:SetSize(size, size)
  return c
end
UI.NewCheck = NewCheck

local function NativeFont(fs, name, r, g, b)
  local obj = rawget(_G, name)
  if obj and fs.SetFontObject and pcall(fs.SetFontObject, fs, obj) then fs.nativeFont = name; return true end
  if r and fs.SetTextColor then fs:SetTextColor(r, g, b) end
  return false
end
UI.NativeFont = NativeFont

local function KeepNativeHover(b, name, tip)
  local onEnter, onLeave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
  SetTip(b, name, function(self)
    if onEnter then pcall(onEnter, self) end
    tip(self)
  end)
  b:SetScript("OnLeave", function(self)
    if onLeave then pcall(onLeave, self) end
    GameTooltip_Hide()
  end)
end

local GAIN_RGB = { 0.31, 0.88, 0.35 }
local function GainFont(fs, large) return NativeFont(fs, large and "GameFontGreenLarge" or "GameFontGreen", GAIN_RGB[1], GAIN_RGB[2], GAIN_RGB[3]) end

local function LevelTag(d) return string.format(L.LEVEL_TAG, d.wearAt or 0, d.levelsToGo or 0) end
UI.LevelTag = LevelTag

local function CardGain(d)
  return UI.GainUnit(d), d.status == "empty-slot" and L.GAIN_EMPTY or ""
end
UI.CardGain = CardGain

local PCT_STATS = { MeleeHit = true, SpellHit = true, MeleeCrit = true, SpellCrit = true, Dodge = true, Parry = true, Block = true }
local STAT_TWINS = { { "MeleeHit", "SpellHit", "STATD_HIT" }, { "MeleeCrit", "SpellCrit", "STATD_CRIT" } }
local Stat = { MIN_SHOWN = 0.005, EPS = 1e-9 }

function Stat.Old(d)
  if not d.equipped then return {} end
  if type(d.equipped.cstats) ~= "table" then return nil end
  return d.equipped.cstats
end

function Stat.Diff(new, old)
  local diff = {}
  for k, v in pairs(new) do if type(v) == "number" then diff[k] = v end end
  for k, v in pairs(old) do if type(v) == "number" then diff[k] = (diff[k] or 0) - v end end
  return diff
end

function Stat.Row(key, amount, label, pct, w)
  return { key = key, amount = amount, label = label, pct = pct and true or false, value = amount * (w or 0) }
end

function Stat.AddTwins(rows, done, diff, weights)
  for _, tw in ipairs(STAT_TWINS) do
    local a, b = diff[tw[1]], diff[tw[2]]
    if a and b and math.abs(a - b) < Stat.EPS then
      if math.abs(a) >= Stat.MIN_SHOWN then
        rows[#rows + 1] = Stat.Row(tw[1], a, L[tw[3]], true, (weights[tw[1]] or 0) + (weights[tw[2]] or 0))
      end
      done[tw[1]], done[tw[2]] = true, true
    end
  end
end

function Stat.AddSingles(rows, done, diff, weights)
  for k, v in pairs(diff) do
    if not done[k] and math.abs(v) >= Stat.MIN_SHOWN then
      rows[#rows + 1] = Stat.Row(k, v, (StatLabel(k):gsub("%s*%%$", "")), PCT_STATS[k], weights[k])
    end
  end
end

function Stat.Before(a, b)
  if math.abs(math.abs(a.value) - math.abs(b.value)) > Stat.EPS then return math.abs(a.value) > math.abs(b.value) end
  if math.abs(math.abs(a.amount) - math.abs(b.amount)) > Stat.EPS then return math.abs(a.amount) > math.abs(b.amount) end
  return a.key < b.key
end

function Stat.SpeedRow(d)
  local newSpeed, oldSpeed = d.info.speed, d.equipped and d.equipped.speed
  if type(newSpeed) ~= "number" then return nil end
  local hasOld = type(oldSpeed) == "number"
  if hasOld and math.abs(newSpeed - oldSpeed) < Stat.MIN_SHOWN then return nil end
  return { key = "Speed", speed = newSpeed, oldSpeed = hasOld and oldSpeed or nil, amount = 0, value = 0, label = L.STATD_SPEED_LABEL }
end

function Stat.Unmapped(info)
  return type(info) == "table" and type(info.unknownStats) == "table" and #info.unknownStats > 0
end

function UI.StatDiff(d)
  local new = d and d.info and d.info.cstats
  if type(new) ~= "table" then return nil end
  local old = Stat.Old(d)
  if not old then return nil end
  local weights = d.e and d.e.set and d.e.set.weights or {}
  local diff = Stat.Diff(new, old)
  local rows, done = {}, {}
  Stat.AddTwins(rows, done, diff, weights)
  Stat.AddSingles(rows, done, diff, weights)
  table.sort(rows, Stat.Before)
  local speed = Stat.SpeedRow(d)
  if speed then table.insert(rows, 1, speed) end
  return rows, Stat.Unmapped(d.info) or Stat.Unmapped(d.equipped)
end

function UI.StatText(row, coloured)
  if row.speed then
    local function n(v) return (string.format("%.2f", v):gsub("%.", L.DECIMAL_MARK)) end
    if row.oldSpeed then return string.format(L.STATD_SPEED, n(row.oldSpeed), n(row.speed)) end
    return string.format(L.STATD_SPEED_ONE, n(row.speed))
  end
  local a = math.floor(math.abs(row.amount) * 100 + 0.5) / 100
  local t = (row.amount < 0 and "-" or "+") .. string.format("%g", a) .. (row.pct and "%" or "")
  if coloured then t = (row.amount < 0 and C.bad or C.upgrade) .. t .. "|r" end
  return t .. " " .. tostring(row.label)
end

local function Tag(text, colour) return (colour or "") .. tostring(text) .. (colour and "|r" or "") end
UI.Tag = Tag

UI.INNER_BORDER = {
  { key = "TopLeftCorner", atlas = "UI-Frame-InnerTopLeft", p = { "TOPLEFT", 0, 0 } },
  { key = "TopRightCorner", atlas = "UI-Frame-InnerTopRight", p = { "TOPRIGHT", 0, 0 } },
  { key = "BottomLeftCorner", atlas = "UI-Frame-InnerBotLeftCorner", p = { "BOTTOMLEFT", 0, -1 } },
  { key = "BottomRightCorner", atlas = "UI-Frame-InnerBotRight", p = { "BOTTOMRIGHT", 0, -1 } },
  { key = "TopEdge", atlas = "_UI-Frame-InnerTopTile", a = { "TOPLEFT", "TopLeftCorner", "TOPRIGHT" }, b = { "TOPRIGHT", "TopRightCorner", "TOPLEFT" }, horiz = true },
  { key = "BottomEdge", atlas = "_UI-Frame-InnerBotTile", a = { "BOTTOMLEFT", "BottomLeftCorner", "BOTTOMRIGHT" }, b = { "BOTTOMRIGHT", "BottomRightCorner", "BOTTOMLEFT" }, horiz = true },
  { key = "LeftEdge", atlas = "!UI-Frame-InnerLeftTile", a = { "TOPLEFT", "TopLeftCorner", "BOTTOMLEFT" }, b = { "BOTTOMLEFT", "BottomLeftCorner", "TOPLEFT" } },
  { key = "RightEdge", atlas = "!UI-Frame-InnerRightTile", a = { "TOPRIGHT", "TopRightCorner", "BOTTOMRIGHT" }, b = { "BOTTOMRIGHT", "BottomRightCorner", "TOPRIGHT" } },
}
function UI.DrawBorderPieces(nine, pieces)
  for _, def in ipairs(pieces) do
    if not HasAtlas(def.atlas) then return false end
  end
  for _, def in ipairs(pieces) do
    local t = nine:CreateTexture(nil, "BORDER")
    nine[def.key] = t
    if def.p then
      SetAtlasSafe(t, def.atlas, true)
      t:SetSize(def.w or 6, def.h or def.w or 6)
      t:SetPoint(def.p[1], nine, def.p[1], def.p[2], def.p[3])
    else
      SetAtlasSafe(t, def.atlas)
      t:SetPoint(def.a[1], nine[def.a[2]], def.a[3], 0, 0)
      t:SetPoint(def.b[1], nine[def.b[2]], def.b[3], 0, 0)
      if def.horiz then
        t:SetHeight(def.h or 3)
        if t.SetHorizTile then pcall(t.SetHorizTile, t, true) end
      else
        t:SetWidth(def.w or 3)
        if t.SetVertTile then pcall(t.SetVertTile, t, true) end
      end
    end
  end
  return true
end
function UI.AddInnerBorder(p)
  local nine = CreateFrame("Frame", nil, p)
  nine:SetAllPoints()
  p.NineSlice = nine
  if NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function"
    and pcall(NineSliceUtil.ApplyLayoutByName, nine, "InsetFrameTemplate") and type(nine.TopLeftCorner) == "table" then
    nine.how = "util"
    return nine
  end
  if not UI.DrawBorderPieces(nine, UI.INNER_BORDER) then nine:Hide(); nine.how = nil; return nil end
  nine.how = "atlas"
  return nine
end

UI.detailPanels = UI.detailPanels or {}
function UI.UpdateDetailCards()
  local def = UI.SKIN.detailBorder or {}
  if not def.card then return end
  local prof = GCA.SelectedProfession and GCA:SelectedProfession() or "Leatherworking"
  local atlas = def.card .. string.lower(tostring(prof))
  for _, p in ipairs(UI.detailPanels) do
    if p.cardBg then
      if HasAtlas(atlas) and SetAtlasSafe(p.cardBg, atlas) then p.cardBg:Show()
      elseif HasAtlas(def.card .. "leatherworking") and SetAtlasSafe(p.cardBg, def.card .. "leatherworking") then p.cardBg:Show()
      else p.cardBg:Hide() end
    end
  end
end
function UI.AddDetailBorder(p)
  local def = UI.SKIN.detailBorder or {}
  if def.atlas and HasAtlas(def.atlas) then
    p.cardBg = p:CreateTexture(nil, "BACKGROUND")
    p.cardBg:SetAllPoints()
    p.cardBg:Hide()
    local nine = CreateFrame("Frame", nil, p)
    nine:SetAllPoints()
    local t = nine:CreateTexture(nil, "BORDER")
    t:SetAllPoints()
    if SetAtlasSafe(t, def.atlas) then
      nine.frameTex = t
      p.NineSlice, nine.how, nine.role = nine, "atlas1", "detailBorder"
      UI.detailPanels[#UI.detailPanels + 1] = p
      RavenquillExpedition:Call(UI.UpdateDetailCards)
      return nine
    end
    nine:Hide()
  end
  if def.layout and NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function" then
    local nine = CreateFrame("Frame", nil, p)
    nine:SetAllPoints()
    if pcall(NineSliceUtil.ApplyLayoutByName, nine, def.layout) and type(nine.TopLeftCorner) == "table" then
      p.NineSlice, nine.how, nine.role = nine, "layout", "detailBorder"
      return nine
    end
    nine:Hide()
  end
  if type(def.pieces) == "table" and #def.pieces > 0 then
    local nine = CreateFrame("Frame", nil, p)
    nine:SetAllPoints()
    if UI.DrawBorderPieces(nine, def.pieces) then
      p.NineSlice, nine.how, nine.role = nine, "pieces", "detailBorder"
      return nine
    end
    nine:Hide()
  end
  local nine = UI.AddInnerBorder(p)
  if nine then nine.role = "detailBorder" end
  return nine
end

local function NewInset(parent, overArt)
  if HasAtlas(UI.SKIN.listBg.atlas) then
    local p = CreateFrame("Frame", nil, parent)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    UI.Skin(p.bg, "listBg")
    p.native = true
    return p
  end
  return UI.NewPlainInset(parent, overArt)
end
UI.INSET_ART_ALPHA = 0.75
function UI.NewPlainInset(parent, overArt)
  local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if ok and inset then
    inset.templated = true
    if overArt and type(inset.Bg) == "table" and inset.Bg.SetAlpha then inset.Bg:SetAlpha(UI.INSET_ART_ALPHA) end
    return inset
  end
  inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if inset.SetBackdrop then Backdrop(inset, overArt and UI.INSET_ART_ALPHA or 0.6) end
  return inset
end

local function RaiseInsetBorder(inset, content)
  if type(inset.NineSlice) == "table" and inset.NineSlice.SetFrameLevel and content.GetFrameLevel then
    local lvl = content:GetFrameLevel()
    if type(lvl) == "number" then inset.NineSlice:SetFrameLevel(lvl + 5) end
  end
end

local function NewPopup(parent)
  local pop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  pop:SetFrameStrata("DIALOG")
  pop:EnableMouse(true)
  pop.backing = pop:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(pop.backing, "common-dropdown-bg") then
    pop.backing:SetPoint("TOPLEFT", -10, 3)
    pop.backing:SetPoint("BOTTOMRIGHT", 10, -3)
    if pop.backing.SetAlpha then pop.backing:SetAlpha(0.925) end
    pop.atlas = true
  else
    pop.backing:Hide()
    if pop.SetBackdrop then Backdrop(pop, 0.97) end
  end
  pop:Hide()
  return pop
end
UI.NewPopup = NewPopup

local function PaintArt(f)
  local base = f:GetFrameLevel() or 0
  local art = {}
  f.gcaArt = art
  local canvas = CreateFrame("Frame", nil, f)
  canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21)
  canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 3)
  canvas:SetFrameLevel(base)
  art.canvas = canvas
  art.fill = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
  art.fill:SetAllPoints()
  local overview = canvas:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(overview, "Profession-Background-Overview") then
    overview:SetAllPoints()
    art.overview = overview
  else
    overview:Hide()
  end
  if HasAtlas("Profession-Background-Template2") then
    local page = CreateFrame("Frame", nil, canvas)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -21)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    page:SetFrameLevel(base + 1)
    local pageArt = page:CreateTexture(nil, "BACKGROUND")
    if SetAtlasSafe(pageArt, "Profession-Background-Template2") then
      pageArt:SetAllPoints()
      art.page, art.pageArt = page, pageArt
    else
      page:Hide()
    end
  end
  art.painted = art.overview ~= nil or art.page ~= nil
  if art.painted then
    art.fill:SetColorTexture(0.06, 0.05, 0.04, 1)
    if type(f.Bg) == "table" and f.Bg.Hide then f.Bg:Hide() end
  else
    art.fill:SetColorTexture(0.06, 0.05, 0.04, 0.85)
  end
  return art
end

local function ApplyLevels(f)
  local art = f.gcaArt
  if not art then return end
  local base = art.canvas:GetFrameLevel() or 0
  local function lift(fr, n)
    if type(fr) == "table" and fr.SetFrameLevel then fr:SetFrameLevel(base + n) end
  end
  lift(f.content, 2)
  lift(f.PortraitContainer, 2)
  lift(f.TitleContainer, 3)
  lift(f.NineSlice, 3)
  lift(f.CloseButton, 4)
end

local function NewWindow(name, title)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
  if ok and f and type(f.SetTitle) == "function" then
    f.templated = true
    SafeCall(f.SetTitle, f, title)
    if f.SetPortraitToAsset then SafeCall(f.SetPortraitToAsset, f, "Interface\\Icons\\Trade_LeatherWorking") end
    PaintArt(f)
    return f
  end
  f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOP", f, "TOP", 0, -14)
  text:SetText(title)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
  f.CloseButton = close
  return f
end

P.AddBorder = AddBorder
P.ApplyLevels = ApplyLevels
P.CardGain = CardGain
P.GAIN_RGB = GAIN_RGB
P.GainFont = GainFont
P.KeepNativeHover = KeepNativeHover
P.LevelTag = LevelTag
P.ModifiedDown = ModifiedDown
P.NativeFont = NativeFont
P.NewCheck = NewCheck
P.NewInset = NewInset
P.NewPopup = NewPopup
P.NewTextButton = NewTextButton
P.NewWindow = NewWindow
P.OnItemClick = OnItemClick
P.RaiseInsetBorder = RaiseInsetBorder
P.ShiftDown = ShiftDown
P.Tag = Tag
P.TextWidth = TextWidth
