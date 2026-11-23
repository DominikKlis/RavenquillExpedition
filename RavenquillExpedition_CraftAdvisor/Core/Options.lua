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
  local tip = string.format(L.OPT_LEVEL_BONUS_NOTE, stamina, spirit) .. "\n\n" .. string.format(L.SLIDER_TIP, stamina, spirit)
  return { type = "range", label = string.format(L.OPT_LEVEL_BONUS, stamina, spirit), tooltip = tip,
    min = 0, max = 100, step = 25, format = "%d %%",
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
    { type = "header", label = L.OPT_H_LEVEL_BONUS },
    LevelingBonus(stamina, spirit),
    { type = "header", label = L.OPT_H_WHISPER },
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

function GCA:Open() self:OpenWindow() end

function GCA:OpenView(view, scope)
  self:OpenWindow()
  self.UI:SetView(view, scope)
end

function GCA:CraftNeeds()
  return self:MatchNeeds(self:GuildNeeds(self:GetMemberList()), "", self.db.settings.needsOffline)
end

function GCA:OverviewHeadline()
  if not self.db then return end
  local _, who = self:CraftNeeds()
  local line = who == 0 and L.ENTRY_NEEDS_NONE or who == 1 and L.OV_NEEDS_1 or string.format(L.OV_NEEDS, who)
  return { line = line, open = function() self:OpenView("make", "all") end }
end

function GCA:OverviewStatus() return "" end

GCA:SetOptions(GCA:BuildOptions())
