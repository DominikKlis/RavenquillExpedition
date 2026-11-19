local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env = H.env
local section = H.section
local ns, GCA, advance, fakeSections, fakeSug, menuOf = H.ns, H.GCA, H.advance, H.fakeSections, H.fakeSug, H.menuOf
local descendants, captureTip, check, tipText, Files = H.descendants, H.captureTip, H.check, H.tipText, H.Files
H.lateGlobals()

local function sweep(locale)
  section("Sweep: every OnEnter / OnClick (" .. locale .. ")")
  ns.locale = locale
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local settings = {}
  for k, v in pairs(GCA.db.settings) do settings[k] = v end
  local printFn = GCA.Print
  GCA.Print = function() end
  local function fill()
    UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39, class = "ROGUE",
      member = { items = {}, time = env.time(), source = "inspect" }, spec = "COMBAT", specHow = "manual" }
    local swList = fakeSections({ [5] = { fakeSug(), fakeSug({ future = true, wearAt = 42, levelsToGo = 3 }), fakeSug({ known = false }) },
      [9] = { fakeSug({ kind = "enchant", enchant = { enchant = 247, name = "Minor Agility" }, item = { name = "Bracers" }, slot = 9,
        cand = { spellID = 7779, enchant = true, recipe = { skill = 80, src = "trainer", r = {} } }, status = "weapon-enchant",
        sets = { { name = "Set", gained = { { n = 2, stats = { MeleeHit = 1, SpellHit = 1 } } }, lost = { { n = 3, stats = {} } }, value = 1 } } }) } },
      { [5] = 7 })
    UIx.sugList:SetData(UIx.SectionRows(swList))
    UIx.sheetFor, UIx.sheetAuto = nil, true
    UIx:UpdateSheet(UIx.current, swList, "Leatherworking", "")
    local off = { key = "Olga Field", online = false, prof = "Leatherworking", level = 30, class = "MAGE", member = { items = {} } }
    UIx.collapsed.online, UIx.collapsed.offline = false, false
    local budE = { key = "Bud Stone", online = true, class = "ROGUE", level = 39, prof = "Leatherworking", member = { items = {} },
      suggestions = { fakeSug(), fakeSug({ slot = 11, future = true, wearAt = 42, levelsToGo = 3, known = false,
        cand = { spellID = 3999, itemID = 5, recipe = { skill = 1, src = "trainer", r = {} } } }) } }
    local offE = { key = "Olga Field", online = false, class = "MAGE", level = 30, prof = "Leatherworking", member = { items = {} }, suggestions = { fakeSug() } }
    GCA.needsCache = nil
    local nd = GCA:GuildNeeds({ budE, offE })
    UIx.needsCollapsed = {}
    local ndData, _, _, _, ndAll = UIx.NeedsRows(nd, "", true)
    UIx.needsList:SetData(ndData)
    UIx:UpdateCraftDetail(ndAll[1])
    UIx.memberList:SetData(UIx.MemberRows({ { key = "Me Stone", isSelf = true, online = true, level = 36, class = "ROGUE", member = {} },
      off, { key = "Nobody Yet", online = true, level = 20, class = "WARRIOR" } }))
    for _, dd in ipairs({ UIx.specButton.dropdown, UIx.profButton.drop, UIx.filterButton, UIx.memberFilter, UIx.modeToggle }) do
      if dd._gen then menuOf(dd) end
    end
  end
  fill()
  UIx:OpenWhisperEditor()
  local ed = UIx.whisperEditor
  GCA:Diag().lastError = nil
  local errBefore = UIx.errorCount
  local frames = descendants(f)
  frames[#frames + 1] = ed
  for _, c in ipairs(descendants(ed)) do frames[#frames + 1] = c end
  local nEnter, bad, nSecEnter, gripEnter = 0, {}, 0, false
  local foldEnter, needEnter, groupEnter, dotEnter, infoEnter, searchEnter = false, 0, 0, false, false, false
  local craftEnter = 0
  local sheetSlotEnter, sheetCardEnter, sheetAltEnter, toggleEnter = 0, 0, 0, 0
  for _, fr in ipairs(frames) do
    if fr._scripts and fr._scripts.OnEnter then
      captureTip()
      local ok, err = pcall(fr._scripts.OnEnter, fr)
      nEnter = nEnter + 1
      if fr == UIx.resizeGrip then gripEnter = #H.tip >= 2 end
      if (fr.data and fr.data.rowKind == "section") or (fr.worn and fr._shown and fr.slot == nil) then nSecEnter = nSecEnter + 1 end
      if fr.data and fr.data.rowKind == "fold" then foldEnter = ok end
      if fr.data and fr.data.rowKind == "need" and fr._shown then needEnter = needEnter + 1 end
      if ok and fr.data and fr.data.group and fr.data.rows and fr._shown then craftEnter = craftEnter + 1 end
      if fr.data and fr.data.rowKind == "group" and fr._shown then groupEnter = groupEnter + 1 end
      if fr == UIx.syncDot then dotEnter = ok end
      if fr == UIx.infoIcon then infoEnter = ok end
      if fr == UIx.searchBox then searchEnter = ok end
      if ok and fr.slot and fr.badge then sheetSlotEnter = sheetSlotEnter + 1 end
      if ok and fr.isBest ~= nil then sheetCardEnter = sheetCardEnter + 1 end
      if ok and fr._parent == UIx.sheet.centre and fr.tag and fr.data then sheetAltEnter = sheetAltEnter + 1 end
      if ok and fr == UIx.modeToggle then toggleEnter = toggleEnter + 1 end
      if not ok then bad[#bad + 1] = tostring(err) end
    end
  end
  check(gripEnter, locale .. ": the sweep reached the resize grip's tooltip (J2)")
  check(nSecEnter == 2, locale .. ": the sweep reached both worn rows (K5: no separate worn-item buttons any more) (" .. nSecEnter .. ")")
  check(foldEnter and needEnter >= 2 and craftEnter == 2 and groupEnter >= 2 and dotEnter and infoEnter and searchEnter,
    locale .. ": the sweep reached the folded line, 2 craft rows + their member rows, group headers, sync dot, (i) icon and search box ("
    .. needEnter .. "/" .. craftEnter .. "/" .. groupEnter .. ")")
  check(sheetSlotEnter == 17 and sheetCardEnter == 2 and sheetAltEnter == 2 and toggleEnter == 1,
    locale .. ": the sweep reached the 17 sheet slots, both cards, 2 alternatives and the K6 view dropdown ("
    .. sheetSlotEnter .. "/" .. sheetCardEnter .. "/" .. sheetAltEnter .. "/" .. toggleEnter .. ")")
  check(nEnter >= 30 and #bad == 0 and UIx.errorCount == errBefore and GCA:Diag().lastError == nil,
    locale .. ": " .. nEnter .. " OnEnter handlers ran without an error (" .. table.concat(bad, "; ")
    .. (GCA:Diag().lastError and (" reported: " .. GCA:Diag().lastError.where .. " " .. GCA:Diag().lastError.msg:match("^[^\n]*")) or "") .. ")")
  fill()
  local skip = { [ed.saveBtn] = true, [ed.resetBtn] = true, [ed.closeBtn] = true, [f.CloseButton] = true }
  local nClick, badClick, nWornClick = 0, {}, 0
  frames = descendants(f)
  for _, fr in ipairs(frames) do
    local fn = fr._scripts and fr._scripts.OnClick
    if fn and not skip[fr] then
      captureTip()
      local ok, err = pcall(fn, fr, "LeftButton")
      nClick = nClick + 1
      if fr.data and fr.data.rowKind == "section" and fr._shown then nWornClick = nWornClick + 1 end
      if not ok then badClick[#badClick + 1] = tostring(err) end
      if not f._shown then f:Show() end
      if UIx.current == nil or UIx.current.key ~= "Bud Stone" then fill() end
    end
  end
  check(nWornClick == 2, locale .. ": OnClick of both worn rows swept (" .. nWornClick .. ")")
  local nMouse, badMouse, gripMouse = 0, {}, 0
  for _, fr in ipairs(descendants(f)) do
    for _, ev in ipairs({ "OnMouseDown", "OnMouseUp" }) do
      local fn = fr._scripts and fr._scripts[ev]
      if fn then
        local ok, err = pcall(fn, fr, "LeftButton")
        nMouse = nMouse + 1
        if fr == UIx.resizeGrip then gripMouse = gripMouse + 1 end
        if not ok then badMouse[#badMouse + 1] = tostring(err) end
      end
    end
  end
  local okR, errR = pcall(UIx.resizeGrip._scripts.OnMouseUp, UIx.resizeGrip, "RightButton")
  if not okR then badMouse[#badMouse + 1] = tostring(errR) end
  check(gripMouse == 2 and nMouse >= 4 and #badMouse == 0 and UIx.errorCount == errBefore and not f.isSizing and not f.isMoving,
    locale .. ": " .. nMouse .. " OnMouseDown/Up handlers (incl. the grip's) + grip right-click ran without an error ("
    .. table.concat(badMouse, "; ") .. ")")
  check(nClick >= 25 and #badClick == 0 and UIx.errorCount == errBefore, locale .. ": " .. nClick .. " OnClick handlers ran without an error ("
    .. table.concat(badClick, "; ") .. ")")
  for k in pairs(GCA.db.settings) do GCA.db.settings[k] = nil end
  for k, v in pairs(settings) do GCA.db.settings[k] = v end
  GCA.db.crafted, GCA.db.specManual = nil, {}
  UIx.collapsed.online, UIx.collapsed.offline = false, true
  UIx.needsCollapsed, UIx.needSel = {}, nil
  GCA.needsCache = nil
  GCA:SelectProfession("Leatherworking")
  GCA.Print = printFn
  ed:Hide(); advance(0.1)
  f:Hide()
  ns.locale = "enUS"
end
sweep("enUS")
sweep("deDE")

do
  section("Error reporter wraps tooltips (H-1)")
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  local saved = ns.Locales.enUS.SLIDER_TIP
  ns.Locales.enUS.SLIDER_TIP = "broken 0 % = on purpose"
  local printed = {}
  local printFn = GCA.Print
  GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
  GCA:Diag().lastError = nil
  local before = UIx.errorCount
  captureTip()
  local ok = pcall(UIx.survival.slider._scripts.OnEnter, UIx.survival.slider)
  check(ok and UIx.errorCount == before + 1 and GCA:Diag().lastError and GCA:Diag().lastError.where == "tooltip: slider"
    and table.concat(printed, "\n"):find("tooltip: slider", 1, true), "a broken tooltip text is caught and reported (" .. tostring(GCA:Diag().lastError and GCA:Diag().lastError.msg:match("^[^\n]*")) .. ")")
  ns.Locales.enUS.SLIDER_TIP = saved
  GCA.Print = printFn
  GCA:Diag().lastError = nil
  captureTip(); UIx.survival.slider._scripts.OnEnter(UIx.survival.slider)
  check(tipText():find("0 % = pure damage", 1, true), "slider tooltip shows '0 % =' (escaped %%): " .. (H.tip[2] or "?"):sub(1, 60))
  UIx.frame:Hide()
end

do
  section("Whisper editor: ESC (L-1)")
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  local function pressEsc()
    local found = false
    for _, name in pairs(env.UISpecialFrames) do
      local fr = env[name]
      if fr and fr:IsShown() then fr:Hide(); found = true end
    end
    return found
  end
  local function listed(name) local n = 0 for _, v in ipairs(env.UISpecialFrames) do if v == name then n = n + 1 end end return n end
  local printed = {}
  local printFn = GCA.Print
  GCA.Print = function(_, ...) printed[#printed + 1] = table.concat({ ... }, " ") end
  UIx:OpenWhisperEditor()
  local ed = UIx.whisperEditor
  check(ed._shown and listed("RavenquillExpeditionCraftFrame") == 0, "editor open: the main window is out of UISpecialFrames")
  ed.craft:SetText("Draft {item}")
  check(pressEsc() and not ed._shown and f._shown, "ESC closes the editor only, the main window stays open")
  check(GCA.db.settings.whisperCraft == nil and UIx.whisperDraft and UIx.whisperDraft.craft == "Draft {item}"
    and table.concat(printed, "\n"):find("draft is kept", 1, true), "unsaved text kept as a draft, chat says so")
  advance(0.1)
  check(listed("RavenquillExpeditionCraftFrame") == 1, "main window back in UISpecialFrames after the editor closed")
  UIx:OpenWhisperEditor()
  check(ed.craft._text == "Draft {item}" and ed.draftNote._shown, "reopening shows the draft and the 'unsaved draft' note")
  ed.enchant:SetText("Changed too")
  UIx:OpenWhisperEditor()
  check(ed.enchant._text == "Changed too", "/gca whisper while open keeps the typing")
  ed.closeBtn._scripts.OnClick(ed.closeBtn)
  check(UIx.whisperDraft and UIx.whisperDraft.enchant == "Changed too", "Close keeps the draft as well")
  UIx:OpenWhisperEditor()
  ed.saveBtn._scripts.OnClick(ed.saveBtn)
  check(GCA.db.settings.whisperCraft == "Draft {item}" and GCA.db.settings.whisperEnchant == "Changed too" and UIx.whisperDraft == nil
    and not ed._shown, "Save stores the draft and clears it")
  advance(0.1)
  UIx:OpenWhisperEditor()
  check(not ed.draftNote._shown and ed.craft._text == "Draft {item}", "after Save: no draft note, saved text shown")
  ed.craft:SetText("another edit")
  ed.resetBtn._scripts.OnClick(ed.resetBtn)
  check(UIx.whisperDraft == nil and GCA.db.settings.whisperCraft == nil and ed.craft._text == UIx.DefaultTemplate("craft"), "Reset drops draft and saved text")
  printed = {}
  pressEsc(); advance(0.1)
  check(f._shown and #printed == 0, "ESC on an unchanged editor: closes it, no draft message, window stays")
  check(pressEsc() and not f._shown, "next ESC closes the main window as before")
  GCA.Print = printFn
end

do
  section("No members: nothing stale (L-4)")
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx = GCA.UI
  UIx.emptyText:SetText("stale empty text")
  UIx.sugHeader:SetText("stale header")
  local orig = GCA.GetMemberList
  GCA.GetMemberList = function() return {} end
  local before = UIx.errorCount
  UIx:Refresh()
  GCA.GetMemberList = orig
  check(UIx.errorCount == before and UIx.nameText._text == "No guild members yet" and UIx.emptyText._text == "" and UIx.sugHeader._text == ""
    and UIx.subText._text == "" and UIx.sourceLine == "" and not UIx.infoIcon._shown, "name says so; empty text, header, sub-line, source line cleared")
  UIx.frame:Hide()
end

do
  section("Window: atlases missing (fallbacks)")
  H.atlasMode = "missing"
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx, f = GCA.UI, GCA.UI.frame
  check(f.gcaArt and not f.gcaArt.painted and f.gcaArt.overview == nil and f.gcaArt.header == nil, "no art drawn without atlases")
  check(f.Bg._shown and f.gcaArt.fill._SetColorTexture[4] < 1, "native Bg kept, translucent dark wash")
  local nIns = 0
  for _, c in ipairs(descendants(f)) do
    if c.NineSlice and c ~= f and c.Bg then nIns = nIns + 1; check(c.Bg._alpha == nil, "no art -> inset Bg untouched") end
  end
  check(nIns == 2, "two list insets in the no-art pass (the detail panels have none)")
  check(UIx.optionsPopup == nil and UIx.profPopup == nil and UIx.profButton.art == "plain" and UIx.profButton.drop.arrowKind == "file",
    "no atlases: the rank bar falls back to a plain track, the dropdown arrow to the caret file (no popups: native menus)")
  UIx.current = { key = "Bud Stone", online = true, prof = "Leatherworking", level = 39 }
  UIx.sugList:SetData({ fakeSug() })
  local b = UIx.sugList.pools.default[1]
  check(not b.slotFrame and b.qual._shown ~= false and b.qual._SetColorTexture, "row icon: quality square instead of the slot frame")
  f:Hide()
  H.atlasMode = "ok"
  GCA.UI.frame = nil
end

H.templateMode = "fail"
local origCF = env.CreateFrame
env.CreateFrame = function(otype, name, parent, template)
  if template == "InsetFrameTemplate" then error("no InsetFrameTemplate") end
  return origCF(otype, name, parent, template)
end
do
  section("Window: fallback path")
  H.atlasMode = "missing"
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local f = GCA.UI.frame
  check(f and f._shown and f._backdrop, "fallback window opens with backdrop")
  local ok = pcall(f.CloseButton._scripts.OnClick, f.CloseButton)
  check(ok and not f._shown, "fallback close button hides")
  local bd = 0
  for _, c in ipairs(descendants(f)) do if c._backdrop and c._shown then bd = bd + 1 end end
  check(bd == 2, "two fallback list panels with backdrop (guild needs, members) (" .. bd .. ")")
  local alphas = {}
  for _, c in ipairs(descendants(f)) do if c._backdrop and c._shown and c._SetBackdropColor then alphas[#alphas + 1] = c._SetBackdropColor[4] end end
  check(#alphas == 2 and alphas[1] == 0.6 and alphas[2] == 0.6, "fallback look unchanged (panel alpha 0.6)")
  H.atlasMode = "ok"
end
env.CreateFrame = origCF

do
  section("whisper to a name with a space; K0/L3: spec reasons + slash replies localized")
  local box = { text = "" }
  function box:SetChatType(t) self.chatType = t end
  function box:SetTellTarget(n) self.tell = n end
  function box:GetChatType() return self.chatType end
  function box:GetTellTarget() return self.tell end
  function box:UpdateHeader() self.header = true end
  function box:SetText(t) self.text = t end
  function box:GetText() return self.text end
  function box:SetFocus() self.focus = true end
  local opened = {}
  local savedCFU = env.ChatFrameUtil
  env.ChatFrameUtil = { OpenChat = function(text) opened[#opened + 1] = text; return box end, GetActiveWindow = function() return box end }
  local savedUI = GCA.UI
  local uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  Files.loadUI(uiNs, env)
  local UIw = GCA.UI
  GCA.UI = savedUI
  UIw.OpenWhisper("Dora Field", "Hi Dora, I can craft X")
  check(box.chatType == "WHISPER" and box.tell == "Dora Field" and box.text == "Hi Dora, I can craft X" and box.focus
    and opened[1] == "", "whisper box: WHISPER to 'Dora Field' (full name), text inserted, no '/w' command")
  local box2 = { text = "" }
  function box2:SetChatType(t) self.chatType = t end
  function box2:SetTellTarget() end
  function box2:GetChatType() return self.chatType end
  function box2:GetTellTarget() return nil end
  function box2:SetText(t) self.text = t end
  function box2:GetText() return self.text end
  opened = {}
  env.ChatFrameUtil = { OpenChat = function(text) opened[#opened + 1] = text; box2.text = text; return box2 end, GetActiveWindow = function() return box2 end }
  uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  Files.loadUI(uiNs, env)
  UIw = GCA.UI
  GCA.UI = savedUI
  UIw.OpenWhisper("Dora Field", "Hello")
  advance(1)
  check(opened[1] == "" and opened[2] == "/w Dora Field Hello", "unverified target: falls back to the '/w' route (" .. tostring(opened[2]) .. ")")
  env.ChatFrameUtil = nil
  uiNs = { GCA = GCA, L = ns.L, G = ns.G, LGet = ns.LGet }
  Files.loadUI(uiNs, env)
  UIw = GCA.UI
  GCA.UI = savedUI
  check(pcall(UIw.OpenWhisper, "Dora Field", "Hello"), "no chat API: no error")
  env.ChatFrameUtil = savedCFU

  ns.locale = "deDE"
  check(UIw.SpecWhyText("no-class") == "Klasse unbekannt" and UIw.SpecWhyText("tie") == "zwei Bäume gleich stark"
    and UIw.SpecWhyText("no C_Traits") == "Talente nicht lesbar", "spec reasons in German")
  ns.locale = "enUS"
  check(UIw.SpecWhyText("not-read") == "talents not read yet" and UIw.SpecWhyText("config has no tree") == "talents not readable",
    "spec reasons in English; technical ones -> 'talents not readable'")
  local savedOwn, me = GCA.ownSpec, GCA.playerKey
  local savedManual = me and GCA.db.specManual[me]
  GCA.ownSpec = nil
  if me then GCA.db.specManual[me] = nil end
  local _, noClass = GCA:MemberSpec("Nobody Here", nil)
  local _, notRead = GCA:MemberSpec(me, "WARRIOR")
  GCA.ownSpec = savedOwn
  if me then GCA.db.specManual[me] = savedManual end
  check(me ~= nil and UIw.SpecWhyText(noClass) == "class unknown" and UIw.SpecWhyText(notRead) == "talents not read yet",
    "MemberSpec reasons reach the member tooltip as 'class unknown' / 'talents not read yet'")
  local printed = {}
  local savedPrint = env.print
  env.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
  ns.locale = "deDE"
  GCA:InspectTarget()
  ns.locale = "enUS"
  env.print = savedPrint
  local all = table.concat(printed, "\n")
  check(all:find("Visiere zuerst ein Gildenmitglied an", 1, true) and not all:find("Target a guild member", 1, true),
    "chat replies in German: " .. all:gsub("\n", " | "))
end

do
  section("Settings: one writer (GCA:SetSetting / GCA:SetSurvival) for the /rq options and the window")
  GCA.UI.frame = nil
  GCA.UI:Toggle(); advance(1)
  local UIx, s = GCA.UI, GCA.db.settings
  local savedSurvival, savedSync, savedCheckOwn = s.survival, s.sync, GCA.CheckOwn
  s.survival = 0.5
  GCA.sugCache = { marker = true }
  check(GCA.SetSurvival and GCA:SetSurvival(130) and s.survival == 1 and GCA.sugCache.marker == nil,
    "SetSurvival clamps to 100 % and drops the cached suggestions")
  check(not GCA:SetSurvival(100.2) and not GCA:SetSurvival("x") and s.survival == 1, "under half a point, or not a number: no change")
  UIx.survival.slider:SetValue(25); advance(1)
  check(s.survival == 0.25, "the window's slider applies 25 % after its debounce: " .. tostring(s.survival))
  local rqSurvival
  for _, o in ipairs(GCA.options) do if o.type == "range" then rqSurvival = o end end
  check(rqSurvival == nil, "the leveling weight lives only in the window, not in /rq")
  local owed = 0
  GCA.CheckOwn = function() owed = owed + 1 end
  s.sync = false
  UIx.ToggleSetting("sync")
  local rqSync
  for _, o in ipairs(GCA.options) do if o.label == ns.Locales.enUS.OPT_SHARE_GEAR then rqSync = o end end
  rqSync.set(false); rqSync.set(true)
  check(s.sync == true and owed == 2, "sync back on from the Filter menu and from /rq: own gear checked both times (" .. owed .. ")")
  GCA.CheckOwn, s.survival, s.sync = savedCheckOwn, savedSurvival, savedSync
  local bad = {}
  for _, file in ipairs(Files.group("UI")) do
    local aliases, i = {}, 0
    for l in io.lines(Files.ROOT .. file) do
      i = i + 1
      local code = l:gsub("%-%-.*$", "")
      local alias = code:match("local%s+([%w_]+)%s*=.*db%.settings")
      if alias then aliases[alias] = true end
      local ASSIGN = "[%.%[][^=]*[^=~<>]=[^=]"
      local wrote = code:find("db%.settings" .. ASSIGN) ~= nil
      for a in pairs(aliases) do
        if code:find("%f[%w_]" .. a .. ASSIGN) then wrote = true end
      end
      if wrote then bad[#bad + 1] = file .. ":" .. i end
    end
  end
  check(#bad == 0, "no UI file writes db.settings (they call GCA:SetSetting / SetSurvival): " .. table.concat(bad, ", "))
end

H.finish(true)
