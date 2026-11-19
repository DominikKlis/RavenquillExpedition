local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local RQ = GCA.RQ
local UI = GCA.UI
local P = UI.P
local G, SetTip, Backdrop, Hex = P.G, P.SetTip, P.Backdrop, P.Hex
local AddGearSlotArt, AddQualityIcon, FillWornIcon, WornTip = P.AddGearSlotArt, P.AddQualityIcon, P.FillWornIcon, P.WornTip
local OnItemClick, WornHyperlink, NewTextButton = P.OnItemClick, P.WornHyperlink, P.NewTextButton
local ClassColor, ClassName, SourceText, Ago = P.ClassColor, P.ClassName, P.SourceText, P.Ago
local SpecHowWords, AssumedTag = P.SpecHowWords, P.AssumedTag

local FRAME_NAME = "RavenquillExpeditionCraftInspect"
local WIDTH, HEIGHT = 338, 424
local SLOT, GAP, ROW_GAP, TOP, SIDE = 37, 4, 6, 64, 12
local SPEC_ICON = 64

local POSITIONS = {}
local function Column(slots, point, x)
  for i, slot in ipairs(slots) do POSITIONS[slot] = { point, x, -(TOP + (i - 1) * (SLOT + GAP)) } end
end
Column({ 1, 2, 3, 15, 5, 4, 19, 9 }, "TOPLEFT", SIDE)
Column({ 10, 6, 7, 8, 11, 12, 13, 14 }, "TOPRIGHT", -SIDE)
local ROW_Y = -(TOP + 7 * (SLOT + GAP))
local ROW_X = math.floor((WIDTH - (3 * SLOT + 2 * ROW_GAP)) / 2)
for i, slot in ipairs({ 16, 17, 18 }) do POSITIONS[slot] = { "TOPLEFT", ROW_X + (i - 1) * (SLOT + ROW_GAP), ROW_Y } end

local SPEC_ICONS = {
  DRUID = { BALANCE = "Spell_Nature_StarFall", FERAL_CAT = "Ability_Druid_CatForm", FERAL_BEAR = "Ability_Racial_BearForm",
    RESTORATION = "Spell_Nature_HealingTouch" },
  HUNTER = { BEAST_MASTERY = "Ability_Hunter_BeastTaming", MARKSMANSHIP = "Ability_Marksmanship",
    SURVIVAL = "Ability_Hunter_SwiftStrike", SURVIVAL_MELEE = "Ability_MeleeDamage" },
  MAGE = { ARCANE = "Spell_Holy_MagicalSentry", FIRE = "Spell_Fire_FireBolt02", FROST = "Spell_Frost_FrostBolt02" },
  PALADIN = { HOLY = "Spell_Holy_HolyBolt", PROTECTION = "Spell_Holy_DevotionAura", RETRIBUTION = "Spell_Holy_AuraOfLight" },
  PRIEST = { DISCIPLINE = "Spell_Holy_WordFortitude", HOLY = "Spell_Holy_GreaterHeal", SHADOW = "Spell_Shadow_ShadowWordPain",
    SMITE = "Spell_Holy_HolySmite" },
  ROGUE = { ASSASSINATION = "Ability_Rogue_Eviscerate", COMBAT = "Ability_BackStab", SUBTLETY = "Ability_Stealth" },
  SHAMAN = { ELEMENTAL = "Spell_Nature_Lightning", ENHANCEMENT = "Spell_Nature_LightningShield",
    ENHANCEMENT_DW = "Ability_DualWield", RESTORATION = "Spell_Nature_MagicImmunity" },
  WARLOCK = { AFFLICTION = "Spell_Shadow_DeathCoil", DEMONOLOGY = "Spell_Shadow_Metamorphosis",
    DESTRUCTION = "Spell_Shadow_RainOfFire" },
  WARRIOR = { ARMS = "Ability_Warrior_SavageBlow", FURY = "Ability_Warrior_InnerRage",
    PROTECTION = "Ability_Warrior_DefensiveStance" },
}
local TIMED_HOW = { synced = true, own = true, inspected = true }
local TAB_LOOK = { selected = "PanelTemplates_SelectTab", open = "PanelTemplates_DeselectTab",
  off = "PanelTemplates_SetDisabledTabState" }

local function Identity(key)
  local r, m, s = RQ:RosterEntry(key) or {}, GCA.db.members[key] or {}, GCA.db.specs[key] or {}
  return r.class or m.class or s.class, r.level or m.level, m.items
end

local function SpecOf(key)
  local class, _, items = Identity(key)
  local spec, how, assumed = GCA:MemberSpec(key, class, items)
  return spec, how, assumed, class
end

function GCA:HasStoredGear(key)
  local m = key and self.db and self.db.members[key]
  return type(m) == "table" and type(m.items) == "table" and next(m.items) ~= nil
end

function GCA:HasStoredSpec(key)
  return self.db ~= nil and SpecOf(key) ~= nil
end

local function CreateSlot(parent, slot)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SLOT, SLOT)
  b.slot = slot
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  AddGearSlotArt(b, SLOT)
  AddQualityIcon(b, SLOT - 4, "CENTER", b, "CENTER", 0, 0, true)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  UI.Skin(b.hl, "slotHover")
  OnItemClick(b, function(self) return nil, nil, WornHyperlink(self.worn) end)
  SetTip(b, "inspect slot", function(self) WornTip(self, self.worn, self.slot) end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function CenteredText(c, template, width)
  local fs = c:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH("CENTER")
  fs:SetWidth(width)
  return fs
end

local function FillSlot(b, link)
  local x = link and { slot = b.slot, link = link, info = GCA:GetInfo(link) or {} } or nil
  b.worn = x
  FillWornIcon(b, x, b.slot)
end

local function BuildGear(f, v)
  f.slots = {}
  for slot, at in pairs(POSITIONS) do
    local b = CreateSlot(v, slot)
    b:SetPoint(at[1], v, at[1], at[2], at[3])
    f.slots[slot] = b
  end
end

local function FillGear(f, key)
  local m = GCA.db.members[key]
  f.footer:SetText(string.format(L.MEMBER_TIP_GEAR, SourceText(m, key == GCA.playerKey), Ago(m.time)))
  for slot, b in pairs(f.slots) do FillSlot(b, m.items[slot]) end
end

local function BuildTalents(f, v)
  local holder = CreateFrame("Frame", nil, v)
  holder:SetSize(SPEC_ICON, SPEC_ICON)
  holder:SetPoint("TOP", v, "TOP", 0, -(TOP + 56))
  AddGearSlotArt(holder, SPEC_ICON)
  f.specIcon = holder:CreateTexture(nil, "ARTWORK")
  f.specIcon:SetAllPoints(holder)
  f.specName = CenteredText(v, "GameFontNormalLarge", WIDTH - 2 * SIDE)
  f.specName:SetPoint("TOP", holder, "BOTTOM", 0, -18)
  f.specClass = CenteredText(v, "GameFontHighlight", WIDTH - 2 * SIDE)
  f.specClass:SetPoint("TOP", f.specName, "BOTTOM", 0, -4)
end

local function FillTalents(f, key)
  local spec, how, assumed, class = SpecOf(key)
  f.specIcon:SetTexture("Interface\\Icons\\" .. SPEC_ICONS[class][spec])
  f.specName:SetText(GCA:SpecName(class, spec) .. (assumed and AssumedTag() or ""))
  f.specClass:SetText(Hex(ClassColor(class)) .. ClassName(class) .. "|r")
  local ts = TIMED_HOW[how] and (GCA.db.specs[key] or {}).ts
  local words = SpecHowWords(how)
  f.footer:SetText(ts and string.format(L.INSPECT_SPEC_WHEN, words, Ago(ts)) or string.format(L.INSPECT_SPEC_HOW, words))
end

local PAGES = {
  { key = "gear", text = "INSPECT_TAB_GEAR", build = BuildGear, fill = FillGear,
    available = function(key) return GCA:HasStoredGear(key) end },
  { key = "talents", global = "TALENTS", text = "INSPECT_TAB_TALENTS", build = BuildTalents, fill = FillTalents,
    available = function(key) return GCA:HasStoredSpec(key) end },
}
for _, page in ipairs(PAGES) do PAGES[page.key] = page end

local function PickPage(key, want)
  local page = PAGES[want] or PAGES[1]
  if page.available(key) then return page end
  for _, p in ipairs(PAGES) do
    if p.available(key) then return p end
  end
end

local function SetTitle(f, text)
  if f.titleText then return f.titleText:SetText(text) end
  f:SetTitle(text)
end

local function FillHeader(f, key)
  local class, level = Identity(key)
  local spec = SpecOf(key)
  SetTitle(f, Hex(ClassColor(class)) .. key .. "|r")
  if f.portrait then UI.SetClassIcon(f.portrait, class) end
  f.level:SetText(string.format(L.MEMBER_TIP_LEVEL, G("LEVEL"), tostring(level or "?"), ClassName(class)))
  f.spec:SetText(spec and string.format(L.MEMBER_TIP_SPEC, GCA:SpecName(class, spec)) or "")
end

local function PaintTab(tab, state)
  if tab.templated then
    local look = _G[TAB_LOOK[state]]
    if type(look) == "function" then pcall(look, tab) end
    return
  end
  tab:SetEnabled(state ~= "off")
  if state == "selected" then tab:LockHighlight() else tab:UnlockHighlight() end
end

local function Fill(f, key, page)
  f.key, f.page = key, page.key
  FillHeader(f, key)
  for _, tab in ipairs(f.tabs) do
    local p = tab.page
    f.views[p.key]:SetShown(p == page)
    PaintTab(tab, p == page and "selected" or (p.available(key) and "open" or "off"))
  end
  page.fill(f, key)
end

local function NewTab(f, i, page)
  local label = page.global and G(page.global, page.text) or L[page.text]
  local ok, tab = pcall(CreateFrame, "Button", FRAME_NAME .. "Tab" .. i, f, "PanelTabButtonTemplate")
  if ok and tab then
    tab.templated = true
    if tab.SetID then tab:SetID(i) end
    tab:SetText(label)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
  else
    tab = NewTextButton(f, 92, 22, label)
  end
  tab.page = page
  tab:SetScript("OnClick", function(self) if self.page.available(f.key) then Fill(f, f.key, self.page) end end)
  if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) else tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 3, 0) end
  return tab
end

local function NewFrame()
  local ok, f = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
  if ok and f then
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
    return f
  end
  f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
  if f.SetBackdrop then Backdrop(f) end
  f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  return f
end

local function Chrome(f)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
  f.portrait = f.PortraitContainer and f.PortraitContainer.portrait or f.portrait
  if type(f.SetTitle) ~= "function" then
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.titleText:SetPoint("TOP", f, "TOP", 0, -14)
  end
  UI.SetEscCloses(FRAME_NAME, true)
end

local function Content(f)
  local c = CreateFrame("Frame", nil, f)
  c:SetAllPoints(f)
  c:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
  f.level = CenteredText(c, "GameFontHighlightSmall", WIDTH - 140)
  f.level:SetPoint("TOP", c, "TOP", 0, -32)
  f.spec = CenteredText(c, "GameFontHighlightSmall", WIDTH - 140)
  f.spec:SetPoint("TOP", f.level, "BOTTOM", 0, -2)
  f.footer = CenteredText(c, "GameFontDisableSmall", WIDTH - 2 * SIDE)
  f.footer:SetPoint("BOTTOM", c, "BOTTOM", 0, 10)
  f.views, f.tabs = {}, {}
  for i, page in ipairs(PAGES) do
    local v = CreateFrame("Frame", nil, c)
    v:SetAllPoints(c)
    page.build(f, v)
    f.views[page.key] = v
    f.tabs[i] = NewTab(f, i, page)
  end
end

local function CreateInspect()
  local f = NewFrame()
  Chrome(f)
  Content(f)
  f:Hide()
  return f
end

function GCA:ShowInspect(key, view)
  local page = PickPage(key, view)
  if not page then return false end
  UI.inspect = UI.inspect or CreateInspect()
  Fill(UI.inspect, key, page)
  UI.inspect:Show()
  if UI.inspect.Raise then UI.inspect:Raise() end
  return true
end

function UI:RefreshInspect()
  local f = self.inspect
  local page = f and f:IsShown() and PickPage(f.key, f.page)
  if page then Fill(f, f.key, page) end
end
