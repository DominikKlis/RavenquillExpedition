local ADDON, ns = ...
local GCA = ns.GCA
local L = ns.L
local RQ = RavenquillExpedition
local priv = GCA.priv
local Print, IsSecret = priv.Print, priv.IsSecret

---------------------------------------------------------------------------
-- "/rq craft <args>" (the core's slash): only the commands that need an item link stay in chat
---------------------------------------------------------------------------
-- "/rq craft" alone shows our options in the core's window (mod.options); "/rq craft stats <link>" and
-- "/rq craft enchant debug [link]" run the debug dumps; anything else opens our window.
function GCA:OnSlash(rest)
  local raw = (type(rest) == "string" and rest or ""):match("^%s*(.-)%s*$")
  local low = raw:lower()
  if low == "stats" or low:match("^stats%s") then self:StatsDebug(raw:match("^%S+%s+(.+)$"))
  elseif low:match("^enchant%s+debug") then self:EnchantDebug(raw:match("^%S+%s+%S+%s+(.+)$"))
  else self:OpenWindow() end
end

-- the AddOns compartment button (## AddonCompartmentFunc)
function RavenquillExpedition_CraftAdvisor_OnCompartmentClick() RQ:Call(GCA.UI.Toggle, GCA.UI) end

---------------------------------------------------------------------------
-- K15: the read-only copy boxes in the core's options view. Lines(dump) runs a debug dump (it takes a sink P(line))
-- and returns its lines plain (colour codes stripped, one entry per line). It runs under RQ:Call: an error reaches
-- BugSack and becomes the last line.
---------------------------------------------------------------------------
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

-- open (never close) our window: the core's "Open" row button, the options' "Open window", "/rq craft <other>"
function GCA:OpenWindow()
  local UI = self.UI
  if not UI then return end
  if UI.frame and UI.frame:IsShown() then return end
  UI:Toggle()
end

-- every option in the core's /rq UI (contract: RavenquillExpedition Overview.lua).
-- get/disabled are re-read when the view shows and after each change; lines() runs when its box is opened.
local function Settings() return GCA.db and GCA.db.settings end
local function RefreshUI() if GCA.UI and GCA.UI.Refresh then GCA.UI:Refresh() end end
local function SettingToggle(key, label, tip)
  return { type = "toggle", label = L[label], tooltip = tip and L[tip] or nil,
    get = function() local s = Settings(); return s and s[key] and true or false end,
    set = function(v)
      local s = Settings()
      if not s or (s[key] and true or false) == (v and true or false) then return end
      if GCA.UI and GCA.UI.ToggleSetting then GCA.UI.ToggleSetting(key) else s[key] = v and true or false end
    end }
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
      set = function(v)
        v = tonumber(v)
        local s = Settings()
        if not (v and s) then return end
        v = math.max(0, math.min(100, v))
        if GCA.UI and GCA.UI.SetSurvival then GCA.UI.SetSurvival(v)
        elseif math.abs(GCA:SurvivalShare() * 100 - v) >= 0.5 then s.survival = v / 100; GCA:InvalidateScores() end
      end },

    { type = "header", label = L.OPT_H_GEAR },
    SettingToggle("autoInspect", "FILTER_AUTOINSPECT", "FILTER_AUTOINSPECT_TIP"),
    { type = "toggle", label = L.OPT_INSPECT_TALENTS, tooltip = L.OPT_INSPECT_TALENTS_TIP,
      get = function() local s = Settings(); return s and s.inspectTalents and true or false end,
      set = function(v)
        local s = Settings()
        if not s then return end
        s.inspectTalents = v and true or false
        GCA:InvalidateScores()
        RefreshUI()
      end },
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
    -- the suite's minimap button (the core's launcher, RavenquillExpedition/Launcher.lua)
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

-- The core's overview row: "Open" opens our window, the status line is the sync state.
function GCA:Open() self:OpenWindow() end
function GCA:OverviewStatus()
  local v = self.SyncStatusLine and self:SyncStatusLine()
  return RQ.Plain(v, "string")
end

GCA:SetOptions(GCA:BuildOptions())
