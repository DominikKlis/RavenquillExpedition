local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check, section = Kit.check, Kit.section

local Geometry = {}
function Geometry.SetSize(s, w, h) s._w, s._h = w, h end
function Geometry.GetWidth(s) return s._w or 0 end
function Geometry.GetHeight(s) return s._h or 0 end
function Geometry.GetCenter(s) return s._cx, s._cy end
function Geometry.GetEffectiveScale() return 1 end
function Geometry.IsForbidden(s) return s._forbidden end
function Geometry.SetFrameStrata(s, v) s._strata = v end
function Geometry.SetFrameLevel(s, l) s._level = l end
function Geometry.ClearAllPoints(s) s._points = {} end
function Geometry.SetTexture(s, path) s._texture = path end
function Geometry.SetTexCoord(s, ...) s._texCoord = { ... } end
function Geometry.SetPoint(s, ...) s._points = s._points or {}; s._points[#s._points + 1] = { ... } end

local cursor = { 0, 0 }
local sched = Kit.Scheduler({ start = 100 })
local me = Kit.Client(sched, nil, "Me Smith", { guild = "Die Gilde", epoch = 1800000000, setup = function(env, c)
  for k, fn in pairs(Geometry) do c.frameMethods[k] = fn end
  env.GetCursorPosition = function() return cursor[1], cursor[2] end
  local create = env.CreateFrame
  function env.CreateFrame(otype, name, parent, template)
    if template == "ButtonFrameTemplate" then error("no template in mock") end
    return create(otype, name, parent, template)
  end
  env.RavenquillExpeditionCraftDB = { settings = { minimapAngle = 200 } }
end })
local env, coreNS, RQ, fire, tip = me.env, me.coreNs, me.RQ, me.fire, me.tip
local Minimap = env.Minimap
Minimap._shown = true
Minimap._w, Minimap._h, Minimap._cx, Minimap._cy = 140, 140, 1000, 700
local function Child(name, otype, angle, w, opts)
  local c = env.CreateFrame(otype, name, Minimap)
  c._w, c._h, c._shown = w, w, true
  c._cx = Minimap._cx + math.cos(math.rad(angle)) * 75
  c._cy = Minimap._cy + math.sin(math.rad(angle)) * 75
  for k, v in pairs(opts or {}) do c[k] = v end
  return c
end

local opened = 0
local craft = RQ:NewModule("Craft", { addon = "CraftTest", title = "Guild Craft Advisor", launcherRightClick = true })
function craft:OverviewStatus() return "Guild sync: 2 guildies" end
function craft:Open() opened = opened + 1 end
RQ:NewModule("Quiet", { addon = "QuietTest", title = "Quiet" })
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
local unplaced = Child("UnplacedButton", "Button", 0, 31); unplaced._cx, unplaced._cy = nil, nil
fire("PLAYER_LOGIN")

section("Settings: one-time copy of the Craft Advisor's button")
local s = env.RavenquillExpeditionDB.launcher
check(type(s) == "table" and s.angle == 200 and not s.dragged and not s.hide, "launcher settings copied from the old Craft Advisor button (angle 200)")
env.RavenquillExpeditionCraftDB.settings.minimapHide = true
check(RQ:LauncherSettings() == s and not s.hide, "copied once: later changes to the old settings don't matter")
env.RavenquillExpeditionCraftDB.settings.minimapHide = nil

section("Placement")
local btn = coreNS.LauncherButton()
check(btn ~= nil and btn == env.RavenquillExpeditionLauncher and btn._shown, "button created at PLAYER_LOGIN")

section("Icon: the game's raven icon, its baked-in border cropped")
check(btn.icon._texture == "Interface\\Icons\\Spell_Nature_RavenForm",
  "button icon is the game's raven icon: " .. tostring(btn.icon._texture))
check(table.concat(btn.icon._texCoord or {}, ",") == "0.08,0.92,0.08,0.92",
  "the icon's square border is cropped so only the bird shows inside the round frame")
check(btn and btn._strata == "MEDIUM" and btn._level == 8, "strata MEDIUM, level 8")
local a = RQ:LauncherFreeAngle()
check(math.abs(a - 346.75) < 0.01, ("largest-gap angle = %.2f (expect 346.75)"):format(a))
Child("LateAddonButton", "Button", 300, 31)
local a2 = RQ:LauncherFreeAngle()
check(math.abs(a2 - 34.75) < 0.01, ("with the late button: %.2f (expect 34.75)"):format(a2))

section("Delayed auto-place, drag, re-place")
fire("PLAYER_ENTERING_WORLD")
check(s.angle == 200, "angle untouched before the 5 s delay")
sched:advance(5)
check(math.abs(s.angle - 34.75) < 0.01, ("auto-placed after 5 s: %.2f"):format(s.angle))
local p = btn._points[1]
check(p and p[1] == "CENTER" and p[2] == Minimap, "button anchored to the Minimap centre")
cursor[1], cursor[2] = 1000, 800
btn._scripts.OnDragStart(btn); btn._scripts.OnUpdate(btn); btn._scripts.OnDragStop(btn)
check(math.abs(s.angle - 90) < 0.01 and s.dragged, "drag sets 90° and marks it dragged")
s.angle = 200
fire("PLAYER_ENTERING_WORLD"); sched:advance(6)
check(s.angle == 200, "a dragged button is not auto-moved")
local placed = RQ:LauncherReplace()
check(math.abs(placed - 34.75) < 0.01 and math.abs(s.angle - 34.75) < 0.01 and not s.dragged, "re-place: back into the largest gap, drag forgotten")
local saved = Minimap._children; Minimap._children = { btn }
check(RQ:LauncherFreeAngle() == 225, "no other buttons -> 225")
Minimap._children = saved
Minimap.GetChildren = function() error("boom") end
check(RQ:LauncherFreeAngle() == 225 and #me.errors == 0, "a scan error -> 225, no Lua error")
Minimap.GetChildren = nil
local dbg = {}
RQ:LauncherDebug(function(l) dbg[#dbg + 1] = l end)
check(dbg[1] and dbg[1]:find("Launcher: shown=true", 1, true) and dbg[#dbg]:find("Largest free gap centre: 35", 1, true),
  "LauncherDebug lists the button and the gap (" .. #dbg .. " lines)")
local expectDebug = table.concat({
  "Launcher: shown=true angle=35 dragged=false",
  "  [ ] ForbiddenThing  angle=- dist=- w=-  forbidden",
  "  [ ] UnplacedButton  angle=- dist=- w=31  no position",
  "  [ ] InnerButton  angle=0 dist=10 w=31  not on rim",
  "  [ ] HBD_Pin1  angle=20 dist=75 w=12  size 12",
  "  [ ] HiddenButton  angle=80 dist=75 w=31  hidden",
  "  [x] GearQuestMinimapButton  angle=129 dist=75 w=31  ",
  "  [x] OverlordMinimapButton  angle=200 dist=75 w=33  ",
  "  [x] SpokenMinimapButton  angle=204 dist=75 w=31  ",
  "  [x] LateAddonButton  angle=300 dist=75 w=31  ",
  "Largest free gap centre: 35.",
}, "\n")
local gotDebug = table.concat(dbg, "\n")
check(gotDebug == expectDebug, "LauncherDebug: every exclusion reason, byte for byte" .. (gotDebug == expectDebug and "" or (":\n" .. gotDebug)))

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
check(toggled == 1 and opened == 1, "left-click: the /rq overview; right-click: the Craft module's window")
btn._scripts.OnEnter(btn)
local text = table.concat(tip.lines, " | ")
check(text:find("Guild Craft Advisor: Guild sync: 2 guildies", 1, true) and text:find("Quiet: no status", 1, true)
  and text:find("Right-click", 1, true), "tooltip: every loaded module's status line: " .. text)
craft.launcherRightClick = nil
btn._scripts.OnClick(btn, "RightButton")
btn._scripts.OnEnter(btn)
check(toggled == 2 and opened == 1 and not table.concat(tip.lines, " | "):find("Right-click", 1, true),
  "no module claims the right-click: it opens the overview and the tooltip has no right-click line")
local quiet = RQ:GetModule("Quiet")
quiet.launcherRightClick = true
function quiet:Open() end
btn._scripts.OnEnter(btn)
local rightLine
for _, line in ipairs(tip.lines) do if tostring(line):find("^Right%-click") then rightLine = line end end
check(rightLine == "Right-click: open Quiet", "the right-click line names the module that claims it: " .. tostring(rightLine))
quiet.launcherRightClick, quiet.Open = nil, nil
craft.launcherRightClick = true
RQ.ToggleOverview = realToggle

section("The /rq overview's minimap-button option")
RQ:ToggleOverview()
local overview = env.RavenquillExpeditionOverview
local launcherBox = overview and overview.home.options and overview.home.options.controls[1]
check(launcherBox and launcherBox:GetChecked() == true, "the overview has a 'show minimap button' checkbox, ticked while the button shows")
if launcherBox then launcherBox:SetChecked(false); launcherBox._scripts.OnClick(launcherBox) end
check(not btn._shown and s.hide == true and not RQ:LauncherShown(), "unticking it hides the button (the setting the Craft Advisor's toggle uses)")
RQ:SetLauncherShown(true)
RQ:RefreshOverview()
check(btn._shown and launcherBox and launcherBox:GetChecked() == true, "shown again from elsewhere: the checkbox follows")
check(#me.errors == 0, "no Lua errors (" .. tostring(me.errors[1]) .. ")")

Kit.finish()
