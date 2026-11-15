local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local G, SetAtlasSafe, SingleLine, Guard, SetTip = P.G, P.SetAtlasSafe, P.SingleLine, P.Guard, P.SetTip
local Backdrop = P.Backdrop

-- Whisper template editor (U2): two single-line boxes, Save / Reset to default / Close.
-- Saved in db.settings.whisperCraft / whisperEnchant; nil = the default of the client language.
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

-- Add / remove a frame name in UISpecialFrames (the frames ESC closes).
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

-- Review L-1: ESC closes only the editor. While it is open the main window is taken out of UISpecialFrames
-- (CloseSpecialWindows hides EVERY listed frame that is shown), and put back right after the editor hides.
-- Closing without Save (ESC or Close) never drops your typing: the text stays as a draft (UI.whisperDraft),
-- the chat says so, and the next open shows the draft. Save uses it; Reset to default drops it.
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
    -- put the main window back after this ESC press has been handled (not while CloseSpecialWindows iterates)
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
    if text == "" or text == UI.DefaultTemplate(kind) then GCA.db.settings[key] = nil else GCA.db.settings[key] = text end
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
    GCA.db.settings.whisperCraft, GCA.db.settings.whisperEnchant = nil, nil
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
  -- already open: keep what is being typed (a reload would overwrite it, review L-1)
  if self.whisperEditor:IsShown() then return self.whisperEditor end
  self.whisperEditor:Load()
  self.whisperEditor:Show()
  return self.whisperEditor
end

-- Leveling bonus slider 0-100 %, default 50 % (renamed from "Survival"). One setting for everybody.
UI.SLIDER_DEBOUNCE = 0.4
local function BonusStats() return G("SPELL_STAT3_NAME"), G("SPELL_STAT5_NAME") end
-- K1: the game's MinimalSliderWithSteppersTemplate where the client has it (created inside pcall and used as
-- Spoken UI\Layout.lua:1033-1042 does on Forever: Init(value, min, max, steps, formatters) + RegisterCallback(
-- MinimalSliderWithSteppersMixin.Event.OnValueChanged, fn, owner) + SetValue); else the 0.5.0 plain slider.
-- K6: one line in the bottom bar (label, then the slider), no longer inside the custom Options popup.
UI.SLIDER_LABEL_W, UI.SLIDER_W = 250, 200
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
  local changed -- (value) from either slider kind
  local sl
  local ok, made = pcall(CreateFrame, "Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
  local mixin = MinimalSliderWithSteppersMixin
  if ok and made and made.Init and made.RegisterCallback and made.SetValue and type(mixin) == "table"
     and type(mixin.Event) == "table" and mixin.Event.OnValueChanged ~= nil then
    local inited = pcall(function()
      made:SetWidth(UI.SLIDER_W)
      made:SetPoint("LEFT", holder.label, "RIGHT", 8, 0)
      made:Init(math.floor(GCA:SurvivalShare() * 100 + 0.5), 0, 100, 20, {})
      made:RegisterCallback(mixin.Event.OnValueChanged, function(_, value) changed(value) end, made)
    end)
    if inited then sl = made; holder.templated = true end
  end
  if not sl then
    if made and made.Hide then made:Hide() end
    sl = CreateFrame("Slider", nil, holder)
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
    sl:SetScript("OnValueChanged", function(_, value) changed(value) end)
  end
  holder.slider = sl
  function holder:Sync()
    if self.pending then return end -- a drag is waiting to be applied; don't snap back
    local v = math.floor(GCA:SurvivalShare() * 100 + 0.5)
    self.updating = true
    pcall(sl.SetValue, sl, v)
    self.updating = false
    label(v)
  end
  -- the label follows at once; the value (which recomputes every member) is applied
  -- UI.SLIDER_DEBOUNCE s after the last change
  holder.gen = 0
  changed = function(value)
    if holder.updating then return end
    local v = math.floor((value or 0) / 5 + 0.5) * 5
    label(v)
    holder.gen = holder.gen + 1
    local gen = holder.gen
    holder.pending = v
    C_Timer.After(UI.SLIDER_DEBOUNCE, function()
      if holder.gen ~= gen then return end
      holder.pending = nil
      if math.abs(GCA:SurvivalShare() * 100 - v) < 0.5 then return end
      GCA.db.settings.survival = v / 100
      GCA:InvalidateScores()
    end)
  end
  local function tip(self)
    local a, b = BonusStats()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(string.format(L.SLIDER_TIP_TITLE, a, b), 1, 1, 1)
    GameTooltip:AddLine(string.format(L.SLIDER_TIP, a, b), nil, nil, nil, true)
    GameTooltip:Show()
  end
  if holder.templated then
    -- the template's own scripts stay; ours are added (its inner Slider takes the mouse)
    local inner = type(sl.Slider) == "table" and sl.Slider or sl
    if inner.HookScript then
      inner:HookScript("OnEnter", Guard("tooltip: slider", tip))
      inner:HookScript("OnLeave", GameTooltip_Hide)
    end
  else
    SetTip(sl, "slider", tip)
    sl:SetScript("OnLeave", GameTooltip_Hide)
  end
  return holder
end

-- shared with the files loaded after this one (P)
P.CreateSurvivalSlider = CreateSurvivalSlider
P.NewEditBox = NewEditBox
P.SetEscCloses = SetEscCloses
