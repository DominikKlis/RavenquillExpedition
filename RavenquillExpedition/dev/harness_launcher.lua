unpack = table.unpack
local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local ADDONS = DEV .. "../../"
local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1; io.write("  ok   ", what, "\n") else fail = fail + 1; io.write("  FAIL ", what, "\n") end
end
local function section(s) io.write("== ", s, "\n") end

local now = 100
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function advance(sec)
  local stop = now + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1); now = math.max(now, t.at); t.fn()
  end
  now = stop
end
function GetTime() return now end
function GetServerTime() return 1800000000 + math.floor(now) end
time = GetServerTime
date = os.date
local errors, printed = {}, {}
function geterrorhandler() return function(msg) errors[#errors + 1] = msg end end
function debugstack() return "" end
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end

local frames = {}
local Frame = {}
local FrameMT = { __index = function(_, k)
  if Frame[k] then return Frame[k] end
  if type(k) == "string" and k:match("^%u") then return function() end end
end }
local function New(otype, parent, name)
  local f = setmetatable({ _type = otype or "Frame", _children = {}, _scripts = {}, _events = {}, _shown = true, _w = 0, _h = 0,
    _points = {} }, FrameMT)
  if parent and parent._children then parent._children[#parent._children + 1] = f end
  if name then f._name = name; _G[name] = f end
  return f
end
function Frame:SetScript(ev, fn) self._scripts[ev] = fn end
function Frame:HookScript(ev, fn) local old = self._scripts[ev]; self._scripts[ev] = function(...) if old then old(...) end fn(...) end end
function Frame:RegisterEvent(ev) self._events[ev] = true end
function Frame:UnregisterEvent(ev) self._events[ev] = nil end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetCenter() return self._cx, self._cy end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetName() return self._name end
function Frame:GetObjectType() return self._type end
function Frame:IsForbidden() return self._forbidden end
function Frame:GetChildren() return unpack(self._children) end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:ClearAllPoints() self._points = {} end
function Frame:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Frame:CreateTexture() return New("Texture") end
function CreateFrame(otype, name, parent) local f = New(otype, parent, name); frames[#frames + 1] = f; return f end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
local tip = { lines = {} }
GameTooltip = setmetatable(tip, { __index = function(_, k)
  if k == "AddLine" then return function(_, t) tip.lines[#tip.lines + 1] = t end end
  if k == "SetOwner" then return function() tip.lines = {} end end
  return function() end
end })
UIParent = New("Frame")
UISpecialFrames, SlashCmdList = {}, {}
Minimap = New("Frame", nil, "Minimap")
Minimap._w, Minimap._h, Minimap._cx, Minimap._cy = 140, 140, 1000, 700
local cursor = { 0, 0 }
function GetCursorPosition() return cursor[1], cursor[2] end
local function Child(name, otype, angle, w, opts)
  local c = New(otype, Minimap, name)
  c._w, c._h = w, w
  c._cx = Minimap._cx + math.cos(math.rad(angle)) * 75
  c._cy = Minimap._cy + math.sin(math.rad(angle)) * 75
  for k, v in pairs(opts or {}) do c[k] = v end
  return c
end

function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function GetLocale() return "enUS" end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function UnitNameUnmodified(u) if u == "player" then return "Me", "Smith" end end
UnitName = UnitNameUnmodified
function GetRealmName() return "Realm" end
function IsInGuild() return true end
function GetGuildInfo() return "Die Gilde" end
function IsInInstance() return false end
function InCombatLockdown() return false end
function GetNumGuildMembers() return 0 end
C_GuildInfo = { GuildRoster = function() end }

RavenquillExpeditionCraftDB = { settings = { minimapAngle = 200 } }
local coreNS = {}
for _, f in ipairs(dofile(DEV .. "toc.lua")(ADDONS .. "RavenquillExpedition")) do
  assert(loadfile(ADDONS .. "RavenquillExpedition/" .. f))("RavenquillExpedition", coreNS)
end
local RQ = RavenquillExpedition
local opened = 0
local craft = RQ:NewModule("Craft", { addon = "CraftTest", title = "Guild Craft Advisor" })
function craft:OverviewStatus() return "Guild sync: 2 guildies" end
function craft:Open() opened = opened + 1 end
local quiet = RQ:NewModule("Quiet", { addon = "QuietTest", title = "Quiet" })
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "CraftTest")
fire("ADDON_LOADED", "QuietTest")
Child("OverlordMinimapButton", "Button", 200, 33)
Child("SpokenMinimapButton", "Button", 204, 31)
Child("GearQuestMinimapButton", "Button", 129.5, 31)
Child("HBD_Pin1", "Button", 20, 12)
Child("QuestiePin", "Frame", 40, 30)
Child("ForbiddenThing", "Button", 60, 31, { _forbidden = true })
Child("HiddenButton", "Button", 80, 31, { _shown = false })
local inner = Child("InnerButton", "Button", 100, 31); inner._cx, inner._cy = Minimap._cx + 10, Minimap._cy
fire("PLAYER_LOGIN")

section("Settings: one-time copy of the Craft Advisor's button")
local s = RavenquillExpeditionDB.launcher
check(type(s) == "table" and s.angle == 200 and not s.dragged and not s.hide, "launcher settings copied from the old Craft Advisor button (angle 200)")
RavenquillExpeditionCraftDB.settings.minimapHide = true
check(RQ:LauncherSettings() == s and not s.hide, "copied once: later changes to the old settings don't matter")
RavenquillExpeditionCraftDB.settings.minimapHide = nil

section("Placement")
local btn = coreNS.LauncherButton()
check(btn ~= nil and btn == _G.RavenquillExpeditionLauncher and btn._shown, "button created at PLAYER_LOGIN")
check(btn and btn._strata == "MEDIUM" and btn._level == 8, "strata MEDIUM, level 8")
local a = RQ:LauncherFreeAngle()
check(math.abs(a - 346.75) < 0.01, ("largest-gap angle = %.2f (expect 346.75)"):format(a))
Child("LateAddonButton", "Button", 300, 31)
local a2 = RQ:LauncherFreeAngle()
check(math.abs(a2 - 34.75) < 0.01, ("with the late button: %.2f (expect 34.75)"):format(a2))

section("Delayed auto-place, drag, re-place")
fire("PLAYER_ENTERING_WORLD")
check(s.angle == 200, "angle untouched before the 5 s delay")
advance(5)
check(math.abs(s.angle - 34.75) < 0.01, ("auto-placed after 5 s: %.2f"):format(s.angle))
local p = btn._points[1]
check(p and p[1] == "CENTER" and p[2] == Minimap, "button anchored to the Minimap centre")
cursor[1], cursor[2] = 1000, 800
btn._scripts.OnDragStart(btn); btn._scripts.OnUpdate(btn); btn._scripts.OnDragStop(btn)
check(math.abs(s.angle - 90) < 0.01 and s.dragged, "drag sets 90° and marks it dragged")
s.angle = 200
fire("PLAYER_ENTERING_WORLD"); advance(6)
check(s.angle == 200, "a dragged button is not auto-moved")
local placed = RQ:LauncherReplace()
check(math.abs(placed - 34.75) < 0.01 and math.abs(s.angle - 34.75) < 0.01 and not s.dragged, "re-place: back into the largest gap, drag forgotten")
local saved = Minimap._children; Minimap._children = { btn }
check(RQ:LauncherFreeAngle() == 225, "no other buttons -> 225")
Minimap._children = saved
Minimap.GetChildren = function() error("boom") end
check(RQ:LauncherFreeAngle() == 225 and #errors == 0, "a scan error -> 225, no Lua error")
Minimap.GetChildren = nil
local dbg = {}
RQ:LauncherDebug(function(l) dbg[#dbg + 1] = l end)
check(dbg[1] and dbg[1]:find("Launcher: shown=true", 1, true) and dbg[#dbg]:find("Largest free gap centre: 35", 1, true),
  "LauncherDebug lists the button and the gap (" .. #dbg .. " lines)")

section("Hide / show, clicks, tooltip")
RQ:SetLauncherShown(false)
check(not btn._shown and s.hide and not RQ:LauncherShown(), "hidden by its setting")
RQ:SetLauncherShown(true)
check(btn._shown and not s.hide and RQ:LauncherShown(), "shown again")
local toggled = 0
local realToggle = RQ.ToggleOverview
RQ.ToggleOverview = function() toggled = toggled + 1 end
btn._scripts.OnClick(btn, "LeftButton")
btn._scripts.OnClick(btn, "RightButton")
RQ.ToggleOverview = realToggle
check(toggled == 1 and opened == 1, "left-click: the /rq overview; right-click: the Craft module's window")
btn._scripts.OnEnter(btn)
local text = table.concat(tip.lines, " | ")
check(text:find("Guild Craft Advisor: Guild sync: 2 guildies", 1, true) and text:find("Quiet: no status", 1, true)
  and text:find("Right-click", 1, true), "tooltip: every loaded module's status line: " .. text)
check(#errors == 0, "no Lua errors (" .. tostring(errors[1]) .. ")")

io.write(("%d passed, %d failed, 0 skipped\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
