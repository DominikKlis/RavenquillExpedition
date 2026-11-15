-- Minimap button: left-click toggles the window, right-click inspects your
-- target, drag to move it around the minimap.
-- On first use the button is placed in the largest free gap between the other
-- addons' minimap buttons (plan rev 4, C1).
local ADDON, ns = ...
local GCA = ns.GCA
local SafeCall = GCA.SafeCall
local L = ns.L

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local DEFAULT_ANGLE = 200   -- v0.1 default; treated as "never placed"
local EMPTY_ANGLE = 225     -- used when there are no other buttons
local RIM_SLACK = 12        -- how far inside the rim a button may sit and still count
local MIN_W, MAX_W = 24, 40 -- size of a minimap button (map pins are smaller)

local btn

local function Radius()
  local w, h = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140
  return math.min(w, h) / 2 + 5
end

local function UpdatePosition()
  if not btn then return end
  local angle = math.rad(GCA.db.settings.minimapAngle or EMPTY_ANGLE)
  local r = Radius()
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

---------------------------------------------------------------------------
-- Finding the other buttons on the rim
---------------------------------------------------------------------------
local function Call(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return end
  local ok, a, b = pcall(fn, obj, ...)
  if ok then return a, b end
end

-- Returns a list of { name, angle, dist, w, type, counted, why } for every Minimap child.
local function ScanChildren()
  local out = {}
  local children = { Minimap:GetChildren() }
  local ms = Minimap:GetEffectiveScale() or 1
  local mx, my = Minimap:GetCenter()
  if not (mx and my) then return out end
  mx, my = mx * ms, my * ms
  local rim = math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2
  for _, c in ipairs(children) do
    if c ~= btn then
      local e = { name = Call(c, "GetName") or "?", type = Call(c, "GetObjectType") or "?" }
      out[#out + 1] = e
      if Call(c, "IsForbidden") then
        e.why = "forbidden"
      else
        local cx, cy = Call(c, "GetCenter")
        local cs = Call(c, "GetEffectiveScale") or 1
        e.w = Call(c, "GetWidth") or 0
        e.visible = Call(c, "IsVisible") and true or false
        if cx and cy then
          local dx, dy = (cx * cs - mx) / ms, (cy * cs - my) / ms
          e.dist = math.sqrt(dx * dx + dy * dy)
          e.angle = math.deg(atan2(dy, dx)) % 360
        end
        if e.type ~= "Button" then e.why = "not a button"
        elseif not e.visible then e.why = "hidden"
        elseif e.w < MIN_W or e.w > MAX_W then e.why = "size " .. math.floor(e.w + 0.5)
        elseif not e.dist then e.why = "no position"
        elseif e.dist < rim - RIM_SLACK then e.why = "not on rim"
        else e.counted = true end
      end
    end
  end
  return out
end

-- Middle of the largest gap between the counted buttons' angles.
function GCA:MinimapFreeAngle()
  local ok, list = pcall(ScanChildren)
  if not ok then return EMPTY_ANGLE end
  local angles = {}
  for _, e in ipairs(list) do if e.counted then angles[#angles + 1] = e.angle end end
  if #angles == 0 then return EMPTY_ANGLE end
  table.sort(angles)
  local bestGap, bestMid = -1, EMPTY_ANGLE
  for i, a in ipairs(angles) do
    local nxt = angles[i + 1] or (angles[1] + 360)
    local gap = nxt - a
    if gap > bestGap then bestGap, bestMid = gap, (a + gap / 2) % 360 end
  end
  return bestMid
end

function GCA:MinimapAutoPlace()
  if not self.db then return end
  self.db.settings.minimapAngle = self:MinimapFreeAngle()
  UpdatePosition()
end

function GCA:MinimapDebug()
  local P = self.Print
  if not btn then
    P("Minimap button not created" .. (self.db.settings.minimapHide and (self.onCore and " (hidden: option 'show minimap button' is off)." or " (hidden by /gca minimap).") or "."))
  else
    P(string.format("Our button: shown=%s visible=%s angle=%.0f strata=%s level=%s",
      tostring(btn:IsShown()), tostring(btn:IsVisible()), self.db.settings.minimapAngle or -1,
      tostring(btn:GetFrameStrata()), tostring(btn:GetFrameLevel())))
  end
  local ok, list = pcall(ScanChildren)
  if not ok then P("Scan failed: " .. tostring(list)) return end
  table.sort(list, function(a, b) return (a.angle or -1) < (b.angle or -1) end)
  for _, e in ipairs(list) do
    if e.counted or e.type == "Button" then
      P(string.format("  %s %s  angle=%s dist=%s w=%s  %s", e.counted and "|cff33ff33[x]|r" or "[ ]", e.name,
        e.angle and string.format("%.0f", e.angle) or "-", e.dist and string.format("%.0f", e.dist) or "-",
        e.w and string.format("%.0f", e.w) or "-", e.why or ""))
    end
  end
  P(string.format("Largest free gap centre: %.0f.", self:MinimapFreeAngle()) .. (self.onCore
    and " The option 're-place minimap button' moves the button there." or " /gca minimap reset moves the button there."))
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  GCA.db.settings.minimapAngle = math.deg(atan2(py - my, px - mx)) % 360
  GCA.db.settings.minimapDragged = true
  UpdatePosition()
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Guild Craft Advisor")
  -- only recipes you know, per profession of yours; browsing another profession never counts (G7.11)
  local counts, recorded = GCA:UpgradeCounts()
  GameTooltip:AddLine(string.format(L.MM_RECORDED, recorded), 1, 1, 1)
  for _, c in ipairs(counts) do
    local name = GCA.UI and GCA.UI.ProfName and GCA.UI.ProfName(c.prof) or c.prof
    GameTooltip:AddLine(string.format(L.MM_COUNT, name, c.upgrades, c.members), 0.3, 1, 0.3)
  end
  if #counts == 0 then GameTooltip:AddLine(L.MM_NONE, 0.7, 0.7, 0.7) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.MM_LEFT, 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.MM_RIGHT, 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.MM_DRAG, 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

local function Create()
  btn = CreateFrame("Button", "GuildCraftAdvisorMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\Trade_LeatherWorking")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)
  btn.icon = icon

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then GCA:InspectTarget() else GCA.UI:Toggle() end
  end)
  btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
  btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)
  btn:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    icon:SetPoint("TOPLEFT", 7, -6)
  end)
  -- through UI.lua's error reporter when it is loaded (review H-1: a tooltip error must not be silent)
  btn:SetScript("OnEnter", (GCA.UI and GCA.UI.Guard) and GCA.UI.Guard("tooltip: minimap", ShowTooltip) or ShowTooltip)
  btn:SetScript("OnLeave", GameTooltip_Hide)

  if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", UpdatePosition) end
  UpdatePosition()
end

function GCA:UpdateMinimapButton()
  if not self.db then return end
  if self.db.settings.minimapHide then
    if btn then btn:Hide() end
    return
  end
  if not btn then
    local ok, err = pcall(Create)
    if not ok then
      btn = nil
      self.Print("Couldn't create the minimap button: " .. tostring(err))
      return
    end
  end
  btn:Show()
end

local function NeedsAutoPlace(s)
  if s.minimapDragged then return false end
  return s.minimapAngle == nil or s.minimapAngle == DEFAULT_ANGLE
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    SafeCall(GCA.UpdateMinimapButton, GCA)
  elseif event == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- other addons (Overlord, Questie, Spoken) load after us and create their buttons late
    C_Timer.After(5, function()
      if NeedsAutoPlace(GCA.db.settings) then SafeCall(GCA.MinimapAutoPlace, GCA) end
    end)
  end
end)

-- ---------------------------------------------------------------------------
-- Dev probe (temporary, for the texture rebuild): the first time the native
-- profession window or character window is shown this session, record the
-- textures, atlases and fonts Blizzard uses there into RavenquillExpeditionCraftDB.probe.
-- Read-only; never changes any frame. Manual: /gcaprobe [FrameName]
-- ---------------------------------------------------------------------------
do
  local MAX_ENTRIES, MAX_DEPTH = 4000, 14
  local function S(f, ...)
    local ok, a, b, c, d, e = pcall(f, ...)
    if ok then return a, b, c, d, e end
  end
  local function Num(v) if type(v) == "number" then return math.floor(v * 10 + 0.5) / 10 end end
  local function Str(v) if type(v) == "string" and not (issecretvalue and issecretvalue(v)) then return v end end

  local function Record(out, obj, depth)
    if #out >= MAX_ENTRIES then return end
    local t = S(obj.GetObjectType, obj)
    local e = { d = depth, t = t, n = Str(S(obj.GetDebugName, obj)) or Str(S(obj.GetName, obj)) or "?" }
    e.w, e.h = Num(S(obj.GetWidth, obj)), Num(S(obj.GetHeight, obj))
    e.shown = S(obj.IsShown, obj) and true or false
    if t == "Texture" or t == "MaskTexture" then
      e.atlas = Str(S(obj.GetAtlas, obj))
      local tex = S(obj.GetTexture, obj)
      if type(tex) == "number" or Str(tex) then e.tex = tex end
      e.layer = Str(S(obj.GetDrawLayer, obj))
      e.blend = Str(S(obj.GetBlendMode, obj))
      e.alpha = Num(S(obj.GetAlpha, obj))
      local r, g, b, a = S(obj.GetVertexColor, obj)
      if type(r) == "number" then e.vc = string.format("%.2f,%.2f,%.2f,%.2f", r, g or 0, b or 0, a or 1) end
      local l, rr, tt, bb = S(obj.GetTexCoord, obj)
      if type(l) == "number" then e.tc = string.format("%.3f,%.3f,%.3f,%.3f", l, rr or 0, tt or 0, bb or 0) end
    elseif t == "FontString" then
      local fo = S(obj.GetFontObject, obj)
      e.font = fo and Str(S(fo.GetName, fo)) or nil
      local path, size, flags = S(obj.GetFont, obj)
      e.fpath, e.fsize, e.fflags = Str(path), Num(size), Str(flags)
      local r, g, b = S(obj.GetTextColor, obj)
      if type(r) == "number" then e.color = string.format("%.2f,%.2f,%.2f", r, g or 0, b or 0) end
      local txt = Str(S(obj.GetText, obj))
      if txt then e.text = txt:sub(1, 40) end
    end
    local p, _, rp, x, y = S(obj.GetPoint, obj, 1)
    if Str(p) then e.pt = Str(p) .. ">" .. tostring(Str(rp)) .. " " .. tostring(Num(x)) .. "," .. tostring(Num(y)) end
    out[#out + 1] = e
  end

  local function Walk(out, frame, depth)
    if not frame or depth > MAX_DEPTH or #out >= MAX_ENTRIES then return end
    Record(out, frame, depth)
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if ok and regions then for _, r in ipairs(regions) do Record(out, r, depth + 1) end end
    local ok2, kids = pcall(function() return { frame:GetChildren() } end)
    if ok2 and kids then for _, c in ipairs(kids) do Walk(out, c, depth + 1) end end
  end

  local TEMPLATES = { "PortraitFrameTemplate", "ButtonFrameTemplate", "InsetFrameTemplate", "SearchBoxTemplate",
    "WowStyle1DropdownTemplate", "WowStyle1FilterDropdownTemplate", "MinimalScrollBar", "WowScrollBoxList",
    "PanelTabButtonTemplate", "UIPanelButtonTemplate", "MinimalCheckboxTemplate", "UICheckButtonTemplate",
    "ProfessionsRecipeListCategoryTemplate", "ProfessionsRecipeListRecipeTemplate", "ListHeaderVisualTemplate",
    "MinimalSliderWithSteppersTemplate", "UIPanelCloseButton" }

  local done = {}
  local function Scan(name, quiet, key)
    if not (RavenquillExpeditionCraftDB and _G[name]) then return end
    key = key or name
    local db = RavenquillExpeditionCraftDB
    db.probe = db.probe or { frames = {} }
    db.probe.frames = db.probe.frames or {}
    local out = {}
    Walk(out, _G[name], 0)
    db.probe.frames[key] = { when = date and date("%Y-%m-%d %H:%M:%S"), count = #out, entries = out }
    db.probe.build = { S(GetBuildInfo) }
    db.probe.templates = {}
    for _, tpl in ipairs(TEMPLATES) do
      db.probe.templates[tpl] = (C_XMLUtil and C_XMLUtil.GetTemplateInfo and S(C_XMLUtil.GetTemplateInfo, tpl)) and true or false
    end
    done[name] = true
    if not quiet then
      print("|cffffd100Guild Craft Advisor|r: " .. name .. " gelesen (" .. #out .. "). Jetzt /reload und \"check\" sagen.")
    end
  end

  -- K7 lead request: the recipe list's rows are only made inside its ScrollBox (not in the first probe), so make one
  -- hidden throwaway instance of each row template and record it (collapsed and expanded for the category header),
  -- plus which mixin methods it has. Stored as frames["tpl:<template>"] / ["tpl:<template>:expanded"].
  local ROW_TEMPLATES = { "ProfessionsRecipeListCategoryTemplate", "ProfessionsRecipeListRecipeTemplate" }
  local METHODS = { "Init", "SetCollapseState", "SetHeaderText", "UpdateCollapsedState", "SetLabelFontColors", "OnEnter", "OnLeave" }
  local function ScanTemplates()
    local db = RavenquillExpeditionCraftDB
    if not db then return end
    db.probe = db.probe or { frames = {} }
    db.probe.frames = db.probe.frames or {}
    for i, tpl in ipairs(ROW_TEMPLATES) do
      local ok, f = pcall(CreateFrame, "Button", "GCAProbeRow" .. i, UIParent, tpl)
      if ok and f then
        f:Hide()
        local has = {}
        for _, m in ipairs(METHODS) do has[m] = type(f[m]) == "function" end
        if has.SetCollapseState then S(f.SetCollapseState, f, true) end
        local out = {}
        Walk(out, f, 0)
        db.probe.frames["tpl:" .. tpl] = { when = date and date("%Y-%m-%d %H:%M:%S"), count = #out, entries = out, methods = has }
        if has.SetCollapseState then
          S(f.SetCollapseState, f, false)
          local out2 = {}
          Walk(out2, f, 0)
          db.probe.frames["tpl:" .. tpl .. ":expanded"] = { count = #out2, entries = out2 }
        end
      else
        db.probe.frames["tpl:" .. tpl] = { error = tostring(f) }
      end
    end
    -- the rank bar fill's flipbook animation (rows/columns/frames/duration) and which per-profession atlases exist
    local rb = {}
    local bar = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RankBar
    if bar and bar.GetAnimationGroups then
      for _, ag in ipairs({ S(bar.GetAnimationGroups, bar) }) do
        for _, a in ipairs({ S(ag.GetAnimations, ag) }) do
          local tgt = S(a.GetTarget, a)
          rb[#rb + 1] = { group = Str(S(ag.GetDebugName, ag)), t = S(a.GetObjectType, a), target = tgt and Str(S(tgt.GetDebugName, tgt)),
            rows = S(a.GetFlipBookRows, a), cols = S(a.GetFlipBookColumns, a), frames = S(a.GetFlipBookFrames, a),
            fw = S(a.GetFlipBookFrameWidth, a), fh = S(a.GetFlipBookFrameHeight, a), dur = S(a.GetDuration, a),
            looping = Str(S(ag.GetLooping, ag)) }
        end
      end
    end
    local atl = {}
    for _, prof in ipairs({ "Leatherworking", "Blacksmithing", "Tailoring", "Engineering", "Enchanting", "Alchemy",
      "Cooking", "FirstAid", "Fishing", "Mining", "Herbalism", "Skinning", "Jewelcrafting", "Inscription" }) do
      for _, pre in ipairs({ "Skillbar_Fill_Flipbook_", "Skillbar_Flare_" }) do
        local info = C_Texture and C_Texture.GetAtlasInfo and S(C_Texture.GetAtlasInfo, pre .. prof)
        if type(info) == "table" then
          atl[pre .. prof] = { w = info.width, h = info.height, l = info.leftTexCoord, r = info.rightTexCoord,
            t = info.topTexCoord, b = info.bottomTexCoord, file = info.file }
        else
          atl[pre .. prof] = false
        end
      end
    end
    db.probe.rankbar = { anims = rb, atlases = atl }
  end

  local function HookOnce(name)
    local f = _G[name]
    if not f or done["hook:" .. name] then return end
    done["hook:" .. name] = true
    -- once per session, 3 s after the window opens (list filled, a recipe selected): record the OPEN
    -- state under "<name>@open" -- the login scan only sees the closed window's static art
    f:HookScript("OnShow", function()
      if done["open:" .. name] then return end
      done["open:" .. name] = true
      C_Timer.After(3, function() pcall(Scan, name, true, name .. "@open") end)
    end)
  end

  local ev = CreateFrame("Frame", "GuildCraftAdvisorProbeFrame")
  ev:RegisterEvent("ADDON_LOADED")
  ev:RegisterEvent("PLAYER_LOGIN")
  ev:RegisterEvent("TRADE_SKILL_SHOW")
  ev:SetScript("OnEvent", function(_, event, arg)
    if event == "TRADE_SKILL_SHOW" then
      -- once per session: read the OPEN profession window (list filled, a recipe selected) 3 s after it opened
      if done["open:tsshow"] then return end
      done["open:tsshow"] = true
      C_Timer.After(3, function()
        for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
          local f = _G[name]
          if f and S(f.IsShown, f) then pcall(Scan, name, true, name .. "@open") end
        end
      end)
      return
    end
    if event == "PLAYER_LOGIN" then
      pcall(HookOnce, "CharacterFrame")
      pcall(HookOnce, "ProfessionsFrame")
      -- automatic: once, a few seconds after login, read both windows even while
      -- closed (their static art exists from XML); no user action needed.
      local db = RavenquillExpeditionCraftDB
      -- probe round 2 (K7): runs once more (autoV) to add the row templates
      if not (db and db.probe and db.probe.auto and db.probe.autoV == 2) then
        C_Timer.After(8, function()
          if InCombatLockdown and InCombatLockdown() then return end
          local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
          if load then pcall(load, "Blizzard_Professions") end
          pcall(Scan, "ProfessionsFrame", true)
          pcall(Scan, "CharacterFrame", true)
          pcall(ScanTemplates)
          if RavenquillExpeditionCraftDB and RavenquillExpeditionCraftDB.probe then
            RavenquillExpeditionCraftDB.probe.auto, RavenquillExpeditionCraftDB.probe.autoV = true, 2
          end
        end)
      end
    elseif arg == "Blizzard_Professions" then
      pcall(HookOnce, "ProfessionsFrame")
    end
  end)

  SLASH_GCAPROBE1 = "/gcaprobe"
  SlashCmdList.GCAPROBE = function(msg)
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_Professions") end
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg ~= "" then pcall(Scan, msg) else pcall(Scan, "ProfessionsFrame"); pcall(Scan, "CharacterFrame"); pcall(ScanTemplates) end
  end
end
