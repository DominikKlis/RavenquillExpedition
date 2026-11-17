local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local G, SetAtlasSafe, SingleLine, Guard, SetTip = P.G, P.SetAtlasSafe, P.SingleLine, P.Guard, P.SetTip
local Backdrop = P.Backdrop

local function NewEditBox(parent, width)
  local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
  if not (ok and eb) then
    eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    if eb.SetBackdrop then Backdrop(eb, 0.8) end
    if eb.SetFontObject and ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
  end
  eb:SetSize(width, 20)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(255)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end

local function SetEscCloses(name, on)
  if type(UISpecialFrames) ~= "table" then return end
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == name then
      if on then return end
      table.remove(UISpecialFrames, i)
    end
  end
  if on then tinsert(UISpecialFrames, name) end
end
UI.SetEscCloses = SetEscCloses

local function CreateWhisperEditor()
  local dlg = CreateFrame("Frame", "RavenquillExpeditionCraftWhisperEditor", UIParent, "BackdropTemplate")
  dlg:SetSize(560, 190)
  dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  dlg:SetFrameStrata("DIALOG")
  dlg:EnableMouse(true)
  dlg:SetClampedToScreen(true)
  dlg.backing = dlg:CreateTexture(nil, "BACKGROUND")
  if SetAtlasSafe(dlg.backing, "common-dropdown-bg") then
    dlg.backing:SetPoint("TOPLEFT", -10, 3)
    dlg.backing:SetPoint("BOTTOMRIGHT", 10, -3)
    dlg.atlas = true
  else
    dlg.backing:Hide()
    if dlg.SetBackdrop then Backdrop(dlg, 0.97) end
  end
  SetEscCloses("RavenquillExpeditionCraftWhisperEditor", true)
  dlg:Hide()
  dlg:SetScript("OnShow", function() SetEscCloses("RavenquillExpeditionCraftFrame", false) end)
  dlg:SetScript("OnHide", Guard("whisper editor: hide", function(self)
    if not self.closingSaved then
      local craft, enchant = self.craft:GetText() or "", self.enchant:GetText() or ""
      if craft ~= UI.Template("craft") or enchant ~= UI.Template("enchant") then
        UI.whisperDraft = { craft = craft, enchant = enchant }
        GCA:Print(L.WHISPER_DRAFT_KEPT)
      end
    end
    self.closingSaved = nil
    C_Timer.After(0, function()
      if not self:IsShown() and UI.frame then SetEscCloses("RavenquillExpeditionCraftFrame", true) end
    end)
  end))
  dlg.title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dlg.title:SetPoint("TOPLEFT", 16, -14)
  dlg.title:SetText(L.WHISPER_EDIT_TITLE)
  dlg.help = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dlg.help:SetPoint("TOPLEFT", 16, -34)
  dlg.help:SetWidth(528)
  dlg.help:SetJustifyH("LEFT")
  dlg.help:SetText(L.WHISPER_EDIT_HELP)
  local function labeled(label, y)
    local fs = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(label)
    local eb = NewEditBox(dlg, 528)
    eb:SetPoint("TOPLEFT", 20, y - 14)
    return eb
  end
  dlg.craft = labeled(L.WHISPER_EDIT_CRAFT, -66)
  dlg.enchant = labeled(L.WHISPER_EDIT_ENCHANT, -104)
  dlg.draftNote = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dlg.draftNote:SetPoint("BOTTOMLEFT", 152, 17)
  dlg.draftNote:SetWidth(180)
  dlg.draftNote:SetJustifyH("LEFT")
  dlg.draftNote:SetTextColor(1, 0.82, 0)
  dlg.draftNote:SetText(L.WHISPER_DRAFT_NOTE)
  function dlg:Load()
    local draft = UI.whisperDraft
    self.craft:SetText(draft and draft.craft or UI.Template("craft"))
    self.enchant:SetText(draft and draft.enchant or UI.Template("enchant"))
    self.draftNote:SetShown(draft ~= nil)
    if self.craft.SetCursorPosition then self.craft:SetCursorPosition(0) end
    if self.enchant.SetCursorPosition then self.enchant:SetCursorPosition(0) end
  end
  local function store(key, kind, text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" or text == UI.DefaultTemplate(kind) then text = nil end
    GCA:SetSetting(key, text)
  end
  function dlg:Save()
    store("whisperCraft", "craft", self.craft:GetText())
    store("whisperEnchant", "enchant", self.enchant:GetText())
    UI.whisperDraft = nil
    GCA:Print(L.WHISPER_SAVED)
    self.closingSaved = true
    self:Hide()
  end
  function dlg:Reset()
    GCA:SetSetting("whisperCraft", nil)
    GCA:SetSetting("whisperEnchant", nil)
    UI.whisperDraft = nil
    self:Load()
    GCA:Print(L.WHISPER_RESET)
  end
  local function button(text, w, fn)
    local b = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
  end
  dlg.closeBtn = button(L.CLOSE, 100, function() dlg:Hide() end)
  dlg.closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
  dlg.saveBtn = button(L.SAVE, 100, function() dlg:Save() end)
  dlg.saveBtn:SetPoint("RIGHT", dlg.closeBtn, "LEFT", -6, 0)
  dlg.resetBtn = button(L.RESET_DEFAULT, 130, function() dlg:Reset() end)
  dlg.resetBtn:SetPoint("BOTTOMLEFT", 14, 12)
  return dlg
end

function UI:OpenWhisperEditor()
  if not GCA.db then return end
  if not self.whisperEditor then self.whisperEditor = CreateWhisperEditor() end
  if self.whisperEditor:IsShown() then return self.whisperEditor end
  self.whisperEditor:Load()
  self.whisperEditor:Show()
  return self.whisperEditor
end

UI.SLIDER_DEBOUNCE = 0.4
local function BonusStats() return G("SPELL_STAT3_NAME"), G("SPELL_STAT5_NAME") end
UI.SLIDER_LABEL_W, UI.SLIDER_W = 250, 200

local function SliderTip(self)
  local a, b = BonusStats()
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(string.format(L.SLIDER_TIP_TITLE, a, b), 1, 1, 1)
  GameTooltip:AddLine(string.format(L.SLIDER_TIP, a, b), nil, nil, nil, true)
  GameTooltip:Show()
end

local function TemplatedSlider(holder, onValue)
  local ok, made = pcall(CreateFrame, "Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
  local mixin = MinimalSliderWithSteppersMixin
  local usable = ok and made and made.Init and made.RegisterCallback and made.SetValue and type(mixin) == "table"
    and type(mixin.Event) == "table" and mixin.Event.OnValueChanged ~= nil
  local inited = usable and pcall(function()
    made:SetWidth(UI.SLIDER_W)
    made:SetPoint("LEFT", holder.label, "RIGHT", 8, 0)
    made:Init(math.floor(GCA:SurvivalShare() * 100 + 0.5), 0, 100, 20, {})
    made:RegisterCallback(mixin.Event.OnValueChanged, onValue, made)
  end)
  if inited then return made end
  if made and made.Hide then made:Hide() end
end

local function PlainSlider(holder, onValue)
  local sl = CreateFrame("Slider", nil, holder)
  sl:SetSize(UI.SLIDER_W - 20, 16)
  sl:SetPoint("LEFT", holder.label, "RIGHT", 8, 0)
  sl:SetOrientation("HORIZONTAL")
  sl:SetMinMaxValues(0, 100)
  sl:SetValueStep(5)
  if sl.SetObeyStepOnDrag then pcall(sl.SetObeyStepOnDrag, sl, true) end
  sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  sl.bar = sl:CreateTexture(nil, "BACKGROUND")
  sl.bar:SetPoint("LEFT", 4, 0)
  sl.bar:SetPoint("RIGHT", -4, 0)
  sl.bar:SetHeight(4)
  sl.bar:SetColorTexture(0.35, 0.3, 0.2, 0.9)
  sl:EnableMouse(true)
  sl:SetScript("OnValueChanged", onValue)
  return sl
end

local function AttachSliderTip(sl, templated)
  if not templated then
    SetTip(sl, "slider", SliderTip)
    sl:SetScript("OnLeave", GameTooltip_Hide)
    return
  end
  local inner = type(sl.Slider) == "table" and sl.Slider or sl
  if inner.HookScript then
    inner:HookScript("OnEnter", Guard("tooltip: slider", SliderTip))
    inner:HookScript("OnLeave", GameTooltip_Hide)
  end
end

local function DebouncedSurvivalSetter(holder, label)
  return function(_, value)
    if holder.updating then return end
    local v = math.floor((value or 0) / 5 + 0.5) * 5
    label(v)
    holder.gen = holder.gen + 1
    local gen = holder.gen
    holder.pending = v
    C_Timer.After(UI.SLIDER_DEBOUNCE, function()
      if holder.gen ~= gen then return end
      holder.pending = nil
      GCA:SetSurvival(v)
    end)
  end
end

local function CreateSurvivalSlider(parent)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(UI.SLIDER_LABEL_W + 8 + UI.SLIDER_W, 22)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  holder.label:SetPoint("LEFT", 0, 0)
  holder.label:SetWidth(UI.SLIDER_LABEL_W)
  holder.label:SetJustifyH("LEFT")
  SingleLine(holder.label)
  local function label(v)
    local a, b = BonusStats()
    holder.label:SetText(string.format(L.SLIDER_LABEL, a, b, v))
  end
  holder.gen = 0
  local onValue = DebouncedSurvivalSetter(holder, label)
  local sl = TemplatedSlider(holder, onValue)
  holder.templated = sl and true or nil
  sl = sl or PlainSlider(holder, onValue)
  holder.slider = sl
  function holder:Sync()
    if self.pending then return end
    local v = math.floor(GCA:SurvivalShare() * 100 + 0.5)
    self.updating = true
    pcall(sl.SetValue, sl, v)
    self.updating = false
    label(v)
  end
  AttachSliderTip(sl, holder.templated)
  return holder
end

P.CreateSurvivalSlider = CreateSurvivalSlider
P.NewEditBox = NewEditBox
P.SetEscCloses = SetEscCloses
