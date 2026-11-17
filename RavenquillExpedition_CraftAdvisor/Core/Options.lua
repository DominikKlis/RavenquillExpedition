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

local SCORED = { inspectTalents = true }
function GCA:SetSetting(key, value)
  local s = self:Settings()
  if not s or s[key] == value then return false end
  s[key] = value
  if key == "sync" and value and self.CheckOwn then self:CheckOwn(false) end
  if SCORED[key] then self:InvalidateScores() end
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

local function RefreshUI() if GCA.UI and GCA.UI.Refresh then GCA.UI:Refresh() end end
local function SettingToggle(key, label, tip)
  return { type = "toggle", label = L[label], tooltip = tip and L[tip] or nil,
    get = function() local s = GCA:Settings(); return s and s[key] and true or false end,
    set = function(v) if GCA:SetSetting(key, v and true or false) then RefreshUI() end end }
end
function GCA:BuildOptions()
  local a, b = ns.G("SPELL_STAT3_NAME"), ns.G("SPELL_STAT5_NAME")
  return {
    { type = "header", label = L.OPT_H_SUGGEST },
    SettingToggle("showUnlearned", "FILTER_UNLEARNED", "FILTER_UNLEARNED_TIP"),
    SettingToggle("lookahead", "FILTER_LOOKAHEAD", "FILTER_LOOKAHEAD_TIP"),
    { type = "range", label = string.format(L.OPT_SURVIVAL, a, b), tooltip = string.format(L.SLIDER_TIP, a, b),
      min = 0, max = 100, step = 5, format = "%d %%",
      get = function() return math.floor(GCA:SurvivalShare() * 100 + 0.5) end,
      set = function(v) if GCA:SetSurvival(v) then RefreshUI() end end },

    { type = "header", label = L.OPT_H_GEAR },
    SettingToggle("autoInspect", "FILTER_AUTOINSPECT", "FILTER_AUTOINSPECT_TIP"),
    SettingToggle("inspectTalents", "OPT_INSPECT_TALENTS", "OPT_INSPECT_TALENTS_TIP"),
    { type = "button", label = L.OPT_INSPECT_NOW, tooltip = L.OPT_INSPECT_NOW_TIP,
      func = function() if GCA.db then GCA:InspectTarget() end end },
    { type = "button", label = L.OPT_SCAN_NOW, tooltip = L.OPT_SCAN_NOW_TIP,
      func = function() if GCA.db then GCA:ScanGroup() end end },
    { type = "button", label = L.OPT_RESET, tooltip = L.OPT_RESET_TIP,
      func = function()
        if not GCA.db then return end
        wipe(GCA.db.members)
        GCA:CaptureSelf()
        Print(L.CMD_RESET)
        RefreshUI()
      end },

    { type = "header", label = L.OPT_H_SYNC },
    SettingToggle("sync", "FILTER_SYNC", "FILTER_SYNC_TIP"),
    { type = "button", label = L.OPT_SYNC_RETRY, tooltip = L.OPT_SYNC_RETRY_TIP,
      disabled = function() return not (GCA.SyncState and GCA:SyncState() == "paused") end,
      func = function() if GCA.SyncRetry then GCA:SyncRetry() end; RefreshUI() end },
    { type = "text", label = L.OPT_SYNC_STATUS,
      lines = function()
        if not GCA.SyncStatus then return { L.CMD_SYNC_NOT_LOADED } end
        return Lines(GCA.SyncStatus, GCA)
      end },

    { type = "header", label = L.OPT_H_WINDOW },
    { type = "button", label = L.OPT_OPEN, func = function() GCA:OpenWindow() end },
    { type = "toggle", label = L.OPT_MINIMAP,
      get = function() return RQ.LauncherShown and RQ:LauncherShown() or false end,
      set = function(v) if RQ.SetLauncherShown then RQ:SetLauncherShown(v and true or false) end end },
    { type = "button", label = L.OPT_MM_RESET, tooltip = L.OPT_MM_RESET_TIP,
      disabled = function() return not (RQ.LauncherShown and RQ:LauncherShown()) end,
      func = function()
        if not RQ.LauncherReplace then return end
        Print(string.format(L.CMD_MM_MOVED, RQ:LauncherReplace() or 0))
      end },
    { type = "button", label = L.EDIT_WHISPER, tooltip = L.EDIT_WHISPER_TIP,
      func = function() if GCA.UI and GCA.UI.OpenWhisperEditor then GCA.UI:OpenWhisperEditor() end end },

    { type = "header", label = L.OPT_H_DIAG },
    { type = "toggle", label = L.OPT_VERBOSE, tooltip = L.OPT_VERBOSE_TIP,
      get = function() return GCA.verbose and true or false end,
      set = function(v) GCA.verbose = v and true or false end },
    { type = "text", label = L.OPT_DIAG_SPEC, lines = function() return Lines(GCA.SpecDebug, GCA) end },
    { type = "text", label = L.OPT_DIAG_KNOWN, lines = function() return Lines(GCA.KnownDebug, GCA) end },
    { type = "text", label = L.OPT_DIAG_MINIMAP, lines = function() return Lines(RQ.LauncherDebug, RQ) end },
    { type = "text", label = L.OPT_DIAG_ERROR,
      lines = function()
        local e = GCA.db and GCA.db.diag and GCA.db.diag.lastError
        if type(e) ~= "table" then return { L.OPT_NO_ERROR } end
        local out = { tostring(e.at or "?") .. "  " .. tostring(e.where or "?") }
        for line in (tostring(e.msg or "") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = PlainLine(line) end
        return out
      end },
  }
end

function GCA:Open() self:OpenWindow() end
function GCA:OverviewStatus()
  local v = self.SyncStatusLine and self:SyncStatusLine()
  return RQ.Plain(v, "string")
end

GCA:SetOptions(GCA:BuildOptions())
