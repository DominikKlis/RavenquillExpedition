local H = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "uikit.lua")
local env = H.env
local GCA, check, section, rectOf, plain = H.GCA, H.check, H.section, H.rectOf, H.plain
H.lateGlobals()

env.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
  PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 } }
env.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior", PRIEST = "Priest", DRUID = "Druid" }
env.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
local HAT = "|cff1eff00|Hitem:4244::::::::60:::::|h[Hat]|h|r"
local HOUR, DAY = 3600, 86400
GCA.db.members["Hans Wurst"] = { class = "MAGE", level = 60, source = "self", time = env.time() - 3 * HOUR,
  items = { [1] = HAT, [5] = "item:4244", [16] = "item:4244", [18] = "item:4244" } }
GCA.db.members["Olga Feld"] = { class = "WARRIOR", level = 42, source = "inspect", from = "Bud Stone", time = env.time(),
  items = { [17] = "item:4244" } }
GCA.db.members["Empty Hands"] = { class = "MAGE", level = 10, source = "self", time = env.time(), items = {} }
GCA.db.specs["Hans Wurst"] = { class = "MAGE", spec = "FIRE", src = "sync", ts = env.time() - 3 * HOUR }
GCA.db.specs["Sol Shadow"] = { class = "PRIEST", spec = "SHADOW", src = "sync", ts = env.time() - 2 * DAY }
GCA.db.specs["Fera Kat"] = { class = "DRUID", tree = "FERAL", src = "inspect", ts = env.time() }

local look = {}
env.PanelTemplates_SelectTab = function(t) look[t] = "selected" end
env.PanelTemplates_DeselectTab = function(t) look[t] = "open" end
env.PanelTemplates_SetDisabledTabState = function(t) look[t] = "off" end
local origCreateFrame = env.CreateFrame
local function TabTemplate(works)
  env.CreateFrame = works and origCreateFrame or function(otype, name, parent, template)
    if template == "PanelTabButtonTemplate" then error("Couldn't find inherited node 'PanelTabButtonTemplate'") end
    return origCreateFrame(otype, name, parent, template)
  end
end

local function window() return GCA.UI.inspect end
local function title(f) return f.titleText and f.titleText._text or f._title end
local function listed(name)
  local n = 0
  for _, v in ipairs(env.UISpecialFrames) do if v == name then n = n + 1 end end
  return n
end
local function TabState(t, templated)
  if templated then return look[t] end
  if t._locked then return "selected" end
  return t._enabled == false and "off" or "open"
end
local function tabs(f, templated)
  local out = {}
  for i, t in ipairs(f.tabs) do out[i] = tostring(t._text) .. "=" .. tostring(TabState(t, templated)) end
  return table.concat(out, " ")
end
local function page(f)
  return (f.slots[1]:IsVisible() and "gear" or "") .. (f.specIcon:IsVisible() and "talents" or "")
end
local function click(tab) tab._scripts.OnClick(tab) end

section("Inspect window: unknown members")
check(not GCA:HasStoredGear("Nobody Here") and not GCA:HasStoredGear("Empty Hands") and GCA:HasStoredGear("Hans Wurst"),
  "stored gear: only for a member with recorded items")
check(GCA:HasStoredSpec("Hans Wurst") and GCA:HasStoredSpec("Sol Shadow") and GCA:HasStoredSpec("Fera Kat")
  and not GCA:HasStoredSpec("Olga Feld") and not GCA:HasStoredSpec("Nobody Here") and not GCA:HasStoredSpec(nil),
  "stored spec: synced or inspected ones count; a member without one or an unknown name does not")
check(GCA:ShowInspect("Nobody Here") == false and GCA:ShowInspect("Empty Hands") == false and GCA:ShowInspect("Nobody Here", "talents") == false
  and window() == nil, "an unknown member or one without items or spec opens nothing")

local function gearChecks(f)
  check(f and f._shown and env.RavenquillExpeditionCraftInspect == f and listed("RavenquillExpeditionCraftInspect") == 1,
    "the window shows, is named and closes with Escape (UISpecialFrames once)")
  check(title(f) == "|cff40c7ebHans Wurst|r", "title: the name in class colour: " .. tostring(title(f)))
  check(f.level._text == "Level 60 Mage" and f.spec._text == "Spec: Fire",
    "level, class and spec under the title: " .. tostring(f.level._text) .. " / " .. tostring(f.spec._text))
  check(f.footer._text == "Gear shared by them over guild sync, 3 h ago", "footer says how and when the gear was shared: " .. tostring(f.footer._text))
  local n = 0
  for _ in pairs(f.slots) do n = n + 1 end
  local head, shirt = f.slots[1], f.slots[4]
  check(n == 19 and head.icon._tex == 134 and head.iconBorder._SetVertexColor[1] == 0.12 and f.slots[16].icon._tex == 134,
    "19 gear slots; filled ones show the item icon with its quality border")
  check(shirt.icon._tex == "Interface\\PaperDoll\\UI-PaperDoll-Slot-ShirtSlot" and f.slots[17].icon._tex == "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHandSlot",
    "empty slots show the slot's own empty texture: " .. tostring(shirt.icon._tex))
  local R = function(slot) return rectOf(f.slots[slot], f) end
  local left, right, ok = { 1, 2, 3, 15, 5, 4, 19, 9 }, { 10, 6, 7, 8, 11, 12, 13, 14 }, true
  for i = 2, 8 do
    if R(left[i]).l ~= R(left[1]).l or R(left[i]).t <= R(left[i - 1]).b then ok = false end
    if R(right[i]).r ~= R(right[1]).r or R(right[i]).t <= R(right[i - 1]).b then ok = false end
  end
  check(ok and R(1).l < R(16).l and R(16).r < R(17).l and R(17).r < R(18).l and R(18).r < R(10).l and R(16).t == R(9).t
    and R(10).r == f._w - 12 and R(1).l == 12, "the game's layout: left and right columns top to bottom, weapons in a row between them at the bottom")
  H.captureTip()
  head._scripts.OnEnter(head)
  check(H.hyper[1] == HAT, "hovering an item shows the game tooltip for its link")
  H.captureTip()
  shirt._scripts.OnEnter(shirt)
  check(#H.hyper == 0 and H.tipText():find("Shirt (empty / unknown)", 1, true), "hovering an empty slot names it: " .. H.tipText())
  local linked
  env.IsShiftKeyDown = function() return true end
  env.HandleModifiedItemClick = function(l) linked = l end
  head._scripts.OnClick(head, "LeftButton")
  local headLinked = linked
  linked = nil
  shirt._scripts.OnClick(shirt, "LeftButton")
  env.IsShiftKeyDown = function() return false end
  check(headLinked and headLinked:find("|Hitem:4244", 1, true) and linked == nil, "shift-click links the item into chat; an empty slot links nothing")
  check(GCA:ShowInspect("Olga Feld") == true and window() == f and listed("RavenquillExpeditionCraftInspect") == 1,
    "another member reuses the one window")
  check(title(f) == "|cffc79c6eOlga Feld|r" and f.level._text == "Level 42 Warrior" and f.spec._text == ""
    and f.slots[1].icon._tex == "Interface\\PaperDoll\\UI-PaperDoll-Slot-HeadSlot" and f.slots[17].icon._tex == 134,
    "refilled for her: name, level, no spec, the previous member's items gone, hers shown")
  check(f.footer._text == "Gear inspected by Bud Stone, shared over guild sync, just now", "footer for relayed gear: " .. tostring(f.footer._text))
  check(GCA:ShowInspect("Nobody Here") == false and plain(title(f)) == "Olga Feld", "an unknown member leaves the window as it was")
  GCA.db.members["Olga Feld"].items[1] = HAT
  GCA:RefreshUI()
  check(f.slots[1].icon._tex == 134, "new data for the shown member appears without reopening")
  GCA.db.members["Olga Feld"].items[1] = nil
end

local function talentChecks(f, templated)
  local R1, R2 = rectOf(f.tabs[1], f), rectOf(f.tabs[2], f)
  check(#f.tabs == 2 and R1.l == 12 and R1.t >= f._h - 2 and R2.l > R1.l and R2.t == R1.t,
    "two tabs hang under the window's bottom edge, side by side like the game's inspect frame")
  check(GCA:ShowInspect("Hans Wurst", "talents") == true and window() == f and f._shown and page(f) == "talents",
    "asked for talents: the window opens on the talents page, the gear hidden: " .. page(f))
  check(f.specIcon._tex == "Interface\\Icons\\Spell_Fire_FireBolt02" and plain(f.specName._text) == "Fire" and plain(f.specClass._text) == "Mage",
    "talents page: the spec's icon, its name and the class: " .. tostring(f.specIcon._tex) .. " / " .. tostring(f.specName._text))
  check(f.footer._text == "Spec sent by their addon, 3 h ago" and title(f) == "|cff40c7ebHans Wurst|r" and f.spec._text == "Spec: Fire",
    "footer says how and when the spec was learned; the header stays: " .. tostring(f.footer._text))
  check(tabs(f, templated) == "Gear=open Talents=selected", "tabs: gear then talents, the shown one selected: " .. tabs(f, templated))
  click(f.tabs[1])
  check(page(f) == "gear" and tabs(f, templated) == "Gear=selected Talents=open" and f.footer._text == "Gear shared by them over guild sync, 3 h ago",
    "the gear tab switches to the gear with its footer: " .. tabs(f, templated))
  click(f.tabs[2])
  check(page(f) == "talents" and tabs(f, templated) == "Gear=open Talents=selected" and f.footer._text == "Spec sent by their addon, 3 h ago",
    "the talents tab switches back")
  check(GCA:ShowInspect("Sol Shadow") == true and page(f) == "talents" and tabs(f, templated) == "Gear=off Talents=selected",
    "a member with only a spec opens on the talents page, the gear tab disabled: " .. tabs(f, templated))
  check(plain(title(f)) == "Sol Shadow" and f.level._text == "Level ? Priest" and f.specIcon._tex == "Interface\\Icons\\Spell_Shadow_ShadowWordPain"
    and plain(f.specName._text) == "Shadow" and f.footer._text == "Spec sent by their addon, 2 days ago",
    "refilled for him: name, class from the spec, his spec and when: " .. tostring(f.level._text) .. " / " .. tostring(f.footer._text))
  click(f.tabs[1])
  check(page(f) == "talents" and plain(title(f)) == "Sol Shadow", "the disabled gear tab does nothing")
  check(GCA:ShowInspect("Olga Feld", "talents") == true and page(f) == "gear" and tabs(f, templated) == "Gear=selected Talents=off"
    and plain(title(f)) == "Olga Feld", "talents asked for a member without a spec: her gear instead, the talents tab disabled")
  click(f.tabs[2])
  check(page(f) == "gear", "the disabled talents tab does nothing")
  check(GCA:ShowInspect("Fera Kat", "talents") == true and plain(f.specName._text) == "Feral (Cat) assumed"
    and f.specIcon._tex == "Interface\\Icons\\Ability_Druid_CatForm" and f.footer._text == "Spec from inspected talents, just now",
    "an inspected tree whose variant was guessed is marked assumed: " .. tostring(plain(f.specName._text)))
  GCA:SetManualSpec("Hans Wurst", "MAGE", "FROST")
  GCA:ShowInspect("Hans Wurst", "talents")
  check(plain(f.specName._text) == "Frost" and f.spec._text == "Spec: Frost" and f.footer._text == "Spec picked by you",
    "your own pick wins on the page and in the header, says so, and has no time: " .. tostring(f.footer._text))
  GCA:SetManualSpec("Hans Wurst", "MAGE", nil)
  GCA:ShowInspect("Sol Shadow", "talents")
  GCA.db.specs["Sol Shadow"].spec = "DISCIPLINE"
  GCA.db.members["Sol Shadow"] = { class = "PRIEST", level = 30, source = "self", time = env.time(), items = { [1] = HAT } }
  GCA:RefreshUI()
  check(page(f) == "talents" and plain(f.specName._text) == "Discipline" and f.level._text == "Level 30 Priest"
    and tabs(f, templated) == "Gear=open Talents=selected", "new spec and gear for the shown member appear without reopening, the page kept, the gear tab enabled")
  GCA.db.specs["Sol Shadow"].spec, GCA.db.members["Sol Shadow"] = "SHADOW", nil
  local ok, err = pcall(f.CloseButton._scripts.OnClick, f.CloseButton)
  check(ok and not f._shown, "the close button hides the window (no protected call)" .. (ok and "" or (": " .. tostring(err))))
end

local function inspectChecks(label, templated)
  section("Inspect window: " .. label)
  GCA.UI.inspect = nil
  TabTemplate(templated)
  check(GCA:ShowInspect("Hans Wurst") == true, "a member with stored gear opens the window")
  local f = window()
  check(page(f) == "gear", "it opens on the gear")
  gearChecks(f)
  talentChecks(f, templated)
  TabTemplate(true)
end

H.templateMode = "ok"
inspectChecks("ButtonFrameTemplate path", true)
H.templateMode = "fail"
inspectChecks("fallback frame and tab buttons", false)
H.templateMode = "ok"

section("Inspect window: German")
H.ns.locale = "deDE"
GCA.UI.inspect = nil
GCA:ShowInspect("Sol Shadow", "talents")
local de = window()
check(de.tabs[1]._text == "Ausrüstung" and de.tabs[2]._text == "Talente", "German tabs: Ausrüstung and Talente: " .. tostring(de.tabs[1]._text))
check(plain(de.specName._text) == "Schatten" and de.footer._text == "Spezialisierung von ihrem Addon gesendet, vor 2 Tagen",
  "German talents page: spec name and how/when: " .. tostring(de.footer._text))
env.TALENTS = "Talente (Spiel)"
GCA.UI.inspect = nil
GCA:ShowInspect("Sol Shadow")
check(window().tabs[2]._text == "Talente (Spiel)", "the talents tab uses the game's own TALENTS string when it has one")
env.TALENTS = nil
H.ns.locale = "enUS"

section("Inspect window: every spec has its own icon")
local bad, seen = {}, {}
for _, e in ipairs(GCA.SPEC_LIST) do
  GCA.db.specs["Icon Probe"] = { class = e[1], spec = e[2], src = "sync", ts = env.time() }
  local ok = pcall(GCA.ShowInspect, GCA, "Icon Probe", "talents")
  local tex = ok and window().specIcon._tex
  seen[e[1]] = seen[e[1]] or {}
  if not (type(tex) == "string" and tex:find("^Interface\\Icons\\%w") and not seen[e[1]][tex]) then bad[#bad + 1] = e[1] .. "/" .. e[2] end
  if tex then seen[e[1]][tex] = true end
end
GCA.db.specs["Icon Probe"] = nil
check(#bad == 0, "every spec shows an icon, no two specs of a class share one: " .. table.concat(bad, ", "))

H.finish(true)
