local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local IsSecret = GCA.IsSecret
local function Print(...) GCA:Print(...) end

function GCA:OnSlash(rest)
  local raw = (type(rest) == "string" and rest or ""):match("^%s*(.-)%s*$")
  local low = raw:lower()
  if low == "stats" or low:match("^stats%s") then self:StatsDebug(raw:match("^%S+%s+(.+)$"))
  elseif low:match("^enchant%s+debug") then self:EnchantDebug(raw:match("^%S+%s+%S+%s+(.+)$"))
  else self:OpenWindow() end
end

function RavenquillExpedition_CraftAdvisor_OnCompartmentClick() RQ:Call(GCA.UI.Toggle, GCA.UI) end

local function PlainLine(s)
  return (s:gsub("|c[nN][^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function Lines(dump, ...)
  local lines, done = {}, false
  local function P(text)
    text = IsSecret(text) and "?" or tostring(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = PlainLine(line) end
  end
  local args = { n = select("#", ...), ... }
  args.n = args.n + 1
  args[args.n] = P
  if type(dump) == "function" then RQ:Call(function() dump(unpack(args, 1, args.n)); done = true end) end
  if not done then
    local e = RavenquillExpeditionDB and RavenquillExpeditionDB.lastError
    lines[#lines + 1] = "error: " .. PlainLine(tostring(type(e) == "table" and e.msg or "not available"))
  end
  return lines
end
GCA.DiagLines = Lines

function GCA:OpenWindow()
  local UI = self.UI
  if not UI then return end
  if UI.frame and UI.frame:IsShown() then return end
  UI:Toggle()
end

function GCA:SetSetting(key, value)
  local s = self:Settings()
  if not s or s[key] == value then return false end
  s[key] = value
  if key == "sync" and value and self.CheckOwn then self:CheckOwn(false) end
  return true
end
function GCA:SetSurvival(percent)
  percent = tonumber(percent)
  local s = self:Settings()
  if not (percent and s) then return false end
  percent = math.max(0, math.min(100, percent))
  if math.abs(self:SurvivalShare() * 100 - percent) < 0.5 then return false end
  s.survival = percent / 100
  self:InvalidateScores()
  return true
end

local function SettingToggle(key, label, tip)
  return { type = "toggle", label = L[label], tooltip = tip and L[tip] or nil,
    get = function() local s = GCA:Settings(); return s and s[key] and true or false end,
    set = function(v) if GCA:SetSetting(key, v and true or false) then GCA:RefreshUI() end end }
end
function GCA:ForgetStoredGear()
  if not self.db then return end
  wipe(self.db.members)
  self:CaptureSelf()
  Print(L.CMD_RESET)
  self:RefreshUI()
end

local function Action(label, tip, func)
  return { type = "button", label = L[label], tooltip = L[tip], func = func }
end

local function LevelingBonus(stamina, spirit)
  return { type = "range", label = string.format(L.SLIDER_TIP_TITLE, stamina, spirit),
    tooltip = string.format(L.SLIDER_TIP, stamina, spirit), min = 0, max = 100, step = 25, format = "%d %%",
    get = function() return math.floor(GCA:SurvivalShare() * 100 + 0.5) end,
    set = function(v) GCA:SetSurvival(v) end }
end

function GCA:BuildOptions()
  local stamina, spirit = GCA.G("SPELL_STAT3_NAME"), GCA.G("SPELL_STAT5_NAME")
  return {
    { type = "header", label = L.OPT_H_SYNC },
    SettingToggle("sync", "OPT_SHARE_GEAR", "OPT_SHARE_GEAR_TIP"),
    { type = "header", label = L.OPT_H_INSPECT },
    SettingToggle("autoInspect", "OPT_AUTO_INSPECT", "OPT_AUTO_INSPECT_TIP"),
    Action("OPT_INSPECT_NOW", "OPT_INSPECT_NOW_TIP", function() GCA:InspectTarget() end),
    Action("OPT_SCAN_NOW", "OPT_SCAN_NOW_TIP", function() GCA:ScanGroup() end),
    { type = "header", label = L.OPT_H_SCORING },
    LevelingBonus(stamina, spirit),
    { type = "note", label = string.format(L.OPT_LEVEL_BONUS_NOTE, stamina, spirit) },
    { type = "header", label = L.OPT_H_OFFERS },
    Action("EDIT_WHISPER", "EDIT_WHISPER_TIP", function() GCA.UI:OpenWhisperEditor() end),
  }
end

local function LastErrorLines()
  local e = GCA.db and GCA.db.diag and GCA.db.diag.lastError
  if type(e) ~= "table" then return { L.OPT_NO_ERROR } end
  local out = { tostring(e.at or "?") .. "  " .. tostring(e.where or "?") }
  for line in (tostring(e.msg or "") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = PlainLine(line) end
  return out
end

local DIAG_SECTIONS = {
  { "OPT_SYNC_STATUS", function() return GCA.SyncStatus and Lines(GCA.SyncStatus, GCA) or { L.CMD_SYNC_NOT_LOADED } end },
  { "OPT_DIAG_SPEC", function() return Lines(GCA.SpecDebug, GCA) end },
  { "OPT_DIAG_KNOWN", function() return Lines(GCA.KnownDebug, GCA) end },
  { "OPT_DIAG_ERROR", LastErrorLines },
}

function GCA:OverviewDiagnostics()
  local out = {}
  for _, section in ipairs(DIAG_SECTIONS) do
    out[#out + 1] = "-- " .. L[section[1]]
    for _, line in ipairs(section[2]() or {}) do out[#out + 1] = line end
  end
  return out
end

GCA.openHint = L.OPEN_HINT
function GCA:Open() self:OpenWindow() end

function GCA:OpenView(view)
  self:OpenWindow()
  self.UI:SetView(view)
end

function GCA.NeedsCountText(prof, crafts, members)
  local who = members == 1 and L.NEEDS_MEMBERS_1 or string.format(L.NEEDS_MEMBERS, members)
  if prof == "Enchanting" then
    return crafts == 1 and string.format(L.NEEDS_COUNT_ENCH_1, who) or string.format(L.NEEDS_COUNT_ENCH, crafts, who)
  end
  return crafts == 1 and string.format(L.NEEDS_COUNT_1, who) or string.format(L.NEEDS_COUNT, crafts, who)
end

local function NeedsLine(self, members)
  local matched, who = self:MatchNeeds(self:GuildNeeds(members), "", self.db.settings.needsOffline)
  if #matched == 0 then return L.ENTRY_NEEDS_NONE end
  return self.NeedsCountText(self:SelectedProfession(), #matched, who)
end

local function MemberLine(self, members)
  local top = self.DefaultMember(members)
  if not top then return L.ENTRY_MEMBER_NONE end
  return string.format(L.ENTRY_MEMBER_TOP, top.key, self.UI.GainNum(top.best.points))
end

local function CraftersLine(self)
  local n = #self:CrafterRoster()
  if n == 0 then return L.ENTRY_CRAFTERS_NONE end
  return n == 1 and L.ENTRY_CRAFTERS_1 or string.format(L.ENTRY_CRAFTERS, n)
end

local ENTRIES = {
  { view = "needs", icon = "Interface\\Icons\\INV_Chest_Leather_09", line = NeedsLine },
  { view = "member", icon = "Interface\\Icons\\INV_Helmet_41", line = MemberLine },
  { view = "crafters", icon = "Interface\\Icons\\INV_Shoulder_08", line = CraftersLine },
}

function GCA:OverviewEntries()
  if not self.db then return end
  local members, out = self:GetMemberList(), {}
  for i, e in ipairs(ENTRIES) do
    out[i] = { icon = e.icon, title = L[self.UI.ViewDef(e.view).label], line = e.line(self, members),
      open = function() self:OpenView(e.view) end }
  end
  return out
end

function GCA:OverviewStatus()
  if not self.db then return end
  local recorded = 0
  for key in pairs(self.db.members) do if key ~= self.playerKey then recorded = recorded + 1 end end
  local s = self:Settings()
  return string.format(L.OV_STATUS, recorded, s and s.sync and L.OV_ON or L.OV_OFF)
end

GCA:SetOptions(GCA:BuildOptions())
