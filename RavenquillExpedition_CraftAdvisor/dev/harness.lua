unpack = table.unpack
local fails, passes = 0, 0
local function check(cond, label)
  if cond then passes = passes + 1; io.write("  ok   ", label, "\n") else fails = fails + 1; io.write("  FAIL ", label, "\n") end
end
local printed = {}
local rawprint = print
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(t, " ")
  rawprint(...)
end
local function printedSince(n) return table.concat(printed, "\n", n + 1) end
function GetBuildInfo() return "1.60.1","70938","",16001 end
function UnitNameUnmodified(u) if u=="target" then return "Buddy","Stone" end return UnitName(u) end
RavenquillExpeditionCraftDB = { members = { ["Old-Timer"] = { time = 5, items = {} } } }
time = os.time
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
tinsert = table.insert
UISpecialFrames = {}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
local function runTimers() local n=0 while #timers>0 and n<200 do local t=table.remove(timers,1); t(); n=n+1 end end
local function obj()
  local o = {}
  return setmetatable(o, { __index = function(t, k) if not k:match("^%u") then return nil end
    if k == "GetChecked" or k=="IsShown" then return function(s) return rawget(s,"_shown") end end
    if k == "Show" then return function(s) s._shown = true; local sc=rawget(s,"_scripts"); if sc and sc.OnShow then sc.OnShow(s) end end end
    if k == "Hide" then return function(s) s._shown = false end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s,"_scripts") or {}; rawset(s,"_scripts",sc); sc[ev]=fn end end
    if k:match("^Create") then return function() return obj() end end
    if k == "RegisterEvent" then return function(s, ev) rawset(s,"_e",true) end end
    return function() end
  end })
end
CreateFrame = function(_, name) local o = obj(); if name then _G[name] = o end; return o end
UIParent = obj(); GameTooltip = obj(); GameTooltip_Hide = function() end
RAID_CLASS_COLORS = { DRUID = {r=1,g=.49,b=.04}, ROGUE={r=1,g=.96,b=.41}, MAGE={r=.41,g=.8,b=.94} }
ITEM_QUALITY_COLORS = { [1]={r=1,g=1,b=1}, [2]={r=.1,g=1,b=.1}, [3]={r=0,g=.4,b=1} }
LOCALIZED_CLASS_NAMES_MALE = { DRUID="Druide", ROGUE="Schurke", MAGE="Magier" }
function InCombatLockdown() return false end
function IsInGuild() return true end
function IsInRaid() return false end
function GetNumSubgroupMembers() return 1 end
function GetNumGroupMembers() return 2 end
function GetTime() return os.time() end
function GetRealmName() return "Realm" end
function Ambiguate(n) return (n:gsub("%-Realm$","")) end
SlashCmdList = {}
local units = {
  player = { name="Me", class="ROGUE", level=30, guid="G-me", items={ [8]="item:2302::::" } },
  target = { name="Buddy", class="DRUID", level=28, guid="G-buddy", items={ [5]="item:2300::::", [8]="item:2302::::" } },
  party1 = { name="Mage", class="MAGE", level=30, guid="G-mage", items={} },
}
function UnitName(u) local x=units[u]; return x and x.name end
function UnitClass(u) local x=units[u]; return x and x.class, x and x.class end
function UnitLevel(u) local x=units[u]; return x and x.level end
function UnitGUID(u) local x=units[u]; return x and x.guid end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitIsUnit(a,b) return units[a] and units[a]==units[b] end
function UnitIsInMyGuild(u) return units[u] ~= nil end
function UnitExists(u) return units[u] ~= nil end
function CanInspect() return true end
local notified
function NotifyInspect(u) notified = u end
function GetInventoryItemLink(u, slot) local x=units[u]; return x and x.items[slot] end
function GetInventorySlotInfo(t) return 1, "tex" end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i) if i==1 then return "Buddy Stone",nil,nil,28,nil,nil,nil,nil,true,nil,"DRUID" else return "Offy-Realm",nil,nil,50,nil,nil,nil,nil,false,nil,"ROGUE" end end
function GetProfessions() return 1, nil end
function GetProfessionInfo(i) return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
local itemMeta = {}
C_Item = {
  GetItemInfoInstant = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id]; if not m then return id, "Misc","Misc","",1,15,0 end return id,"Armor","x",m.loc,1,4,m.sub end,
  GetItemInfo = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id] or {loc="",sub=0,lvl=1}; return "Item"..id, "|Hitem:"..id.."|h[Item"..id.."]|h", 2, 20, m.lvl, nil,nil,nil, m.loc, 1, nil, 4, m.sub, m.bind or 2 end,
  GetItemStats = function(link) local id = tonumber(link:match("item:(%d+)")); local m = itemMeta[id]; return m and m.stats or {} end,
  RequestLoadItemDataByID = function() end,
  GetItemNameByID = function(id) return "Reagent"..id end,
  GetItemCount = function() return 3 end,
}
C_SpellBook = { IsSpellKnown = function(id) return id == 2149 or id == 2160 or id == 3762 end }
local ns = {}
local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local function load(f) local chunk = assert(loadfile(ROOT .. f)); chunk("RavenquillExpedition_CraftAdvisor", ns) end
local K = dofile(ROOT .. "dev/corekit.lua")()
local Files = dofile(ROOT .. "dev/files.lua")
load("Locales/enUS.lua"); load("Locales/deDE.lua")
load("Data/Leatherworking.lua"); load("Data/Blacksmithing.lua"); load("Data/Tailoring.lua"); load("Data/Engineering.lua")
load("Data/Enchanting.lua"); load("Data/Enchants.lua")
itemMeta[2302] = { loc="INVTYPE_FEET", sub=2, lvl=1, stats={RESISTANCE0_NAME=30} }
itemMeta[2300] = { loc="INVTYPE_CHEST", sub=2, lvl=8, stats={RESISTANCE0_NAME=60, ITEM_MOD_AGILITY_SHORT=1} }
itemMeta[4244] = { loc="INVTYPE_CHEST", sub=2, lvl=20, stats={RESISTANCE0_NAME=90, ITEM_MOD_AGILITY_SHORT=4, ITEM_MOD_STAMINA_SHORT=3} }
Files.load(Files.list({ from = "Data/Weights.lua", except = { "Data/Sources.lua", "Sync.lua", "RecipeSources.lua" } }), ns)
K.done()
local GCA = ns.GCA
local h = function(_, ev, ...) K.fire(ev, ...) end
h(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
h(GCA, "PLAYER_LOGIN"); runTimers()
h(GCA, "GUILD_ROSTER_UPDATE"); runTimers()
print("known", GCA.knownCount)
check(GCA.knownCount == 3, "3 recipes known (IsSpellKnown)")
check(GCA.db.settings.inspectTalents == false, "inspected talents default off")
GCA:InspectTarget(); print("notified", notified)
check(notified == "target", "Inspect target -> NotifyInspect(target)")
h(GCA, "INSPECT_READY", "G-buddy"); runTimers()
GCA:ScanGroup(); runTimers(); h(GCA, "INSPECT_READY", "G-mage"); runTimers()
for k, m in pairs(RavenquillExpeditionCraftDB.members) do print("member", k, m.class, m.level, m.source) end
local bud = RavenquillExpeditionCraftDB.members["Buddy Stone"]
check(bud and bud.class == "DRUID" and bud.level == 28 and bud.source == "inspect" and bud.items[5], "Buddy Stone recorded from the inspect (DRUID 28, chest)")
check(RavenquillExpeditionCraftDB.members["Old Timer"] and not RavenquillExpeditionCraftDB.members["Old-Timer"], "v0.1 key \"Old-Timer\" migrated to \"Old Timer\"")
check(RavenquillExpeditionCraftDB.members["Me"] and RavenquillExpeditionCraftDB.members["Me"].source == "self", "own gear recorded")
local byKey = {}
for _, e in ipairs(GCA:GetMemberList()) do
  print("entry (no spec yet)", e.key, e.level, e.online, e.member and "inspected" or "-", e.suggestions and #e.suggestions, e.state)
  byKey[e.key] = e
end
check(byKey["Me"] and byKey["Me"].state == "no-spec" and byKey["Buddy Stone"] and byKey["Buddy Stone"].state == "no-spec"
  and #byKey["Buddy Stone"].suggestions == 0, "no spec yet -> no suggestions")
check(byKey["Old Timer"] and byKey["Old Timer"].state == "no-class", "unknown class -> no-class")
GCA:SetManualSpec("Buddy Stone", "DRUID", "FERAL_CAT")
GCA:SetManualSpec("Me", "ROGUE", "COMBAT")
byKey = {}
for _, e in ipairs(GCA:GetMemberList()) do
  byKey[e.key] = e
  print("entry", e.key, e.level, e.spec, e.specHow, e.suggestions and #e.suggestions, e.state)
  for _, s in ipairs(e.suggestions or {}) do
    print("   ", s.slot, s.info.name, s.status, string.format("%.2f -> %.2f  %s  pts %+.2f", s.oldScore, s.newScore, s.pct and string.format("%+.1f%%", s.pct * 100) or "-", s.points), s.known)
  end
  if e.weights then print("    source:", GCA:SourceLine(e.weights)) end
end
local me, b2 = byKey["Me"], byKey["Buddy Stone"]
check(me and me.spec == "COMBAT" and me.specHow == "manual" and me.state == "ok" and #me.suggestions == 2
  and me.suggestions[1].status == "empty-slot" and me.suggestions[1].info.itemID == 4244 and me.suggestions[2].extra
  and me.knownCount == 1 and me.best == me.suggestions[1], "Me (Combat): Hillman's vest into the empty chest slot (2nd vest listed as extra, badge counts 1)")
check(b2 and b2.spec == "FERAL_CAT" and b2.state == "ok" and #b2.suggestions == 1 and b2.suggestions[1].status == "upgrade"
  and b2.suggestions[1].pct > 1 and b2.suggestions[1].tier == 1, "Buddy (Feral Cat): vest 2300 -> 4244 as a % upgrade")
check(b2 and b2.weights and GCA:SourceLine(b2.weights):find("Lv30 %(nearest set for Lv28%)"), "source line names the nearest bracket")
GCA.db.settings.showUnlearned = true
local e = GCA:ComputeSuggestions({class="DRUID", level=28, items=units.target.items, spec="FERAL_CAT"}, false)
print("with unlearned:", #e)
check(#e >= 1, "show unlearned: still computes")
check(GCA.db.settings.memberView == "sheet", "member view defaults to the character sheet")
GCA.db.settings.memberView = "list"
GCA.UI:Toggle(); runTimers()
print("UI shown", GCA.UI.frame:IsShown(), "selected", GCA.UI.selected, "auto", GCA.UI.autoKey, "first", GCA.UI.memberList.rows[1].data.key, GCA.UI.memberList.rows[1].data.best, "rows", #GCA.UI.sugList.rows)
check(GCA.UI.frame:IsShown() and GCA.UI.selected == "Buddy Stone" and #GCA.UI.sugList.rows >= 1, "/gca opens the window with Buddy selected and a suggestion row")
do
  local sl = GCA.UI.sugList
  local pools = rawget(sl, "pools")
  local secs, fold = pools.section or {}, (pools.fold or {})[1]
  local shownSecs = 0
  for _, s in ipairs(secs) do if rawget(s, "_shown") ~= false then shownSecs = shownSecs + 1 end end
  local first = secs[1]
  check(first and first.data.sec.key == 5 and #first.data.sec.rows == 1 and sl.rows[1].data == first.data.sec.rows[1]
    and shownSecs == 1 and fold and #fold.data.secs == 14 and sl.data[#sl.data] == fold.data
    and (GCA.UI.errorCount or 0) == 0 and GCA:Diag().lastError == nil,
    "real refresh -> chest section first with the vest row, the 14 others folded into one last line, no reported error ("
    .. shownSecs .. " sections, " .. (fold and #fold.data.secs or 0) .. " folded)")
  local nl = GCA.UI.needsList
  check(GCA.UI.view == "needs" and nl.data[1] and nl.data[1].rowKind == "cat" and nl.data[1].cat == 5 and nl.data[2] and nl.data[2].group
    and nl.data[2].rows[1].member.key == "Buddy Stone"
    and nl.data[2].group.sug == first.data.sec.rows[1] and nl.data[2].group == GCA:GuildNeedsByCraft(GCA.UI.lastMembers)[1]
    and GCA.UI.needDetail.entry == nl.data[2] and GCA.UI.needDetail.members.rows[1].data.member.key == "Buddy Stone",
    "opens on guild needs; 'Chest' category, first craft = Buddy's vest, shown in the detail panel (real Core GuildNeedsByCraft)")
  local mrow
  for _, r in ipairs(rawget(GCA.UI.memberList, "rows")) do if r.data and r.data.key == "Buddy Stone" then mrow = r end end
  local line = mrow and GCA.UI.MemberLine(mrow.data) or ""
  check(line:find("^%d+ upgrades? · best: Chest$"), "member row second line on real data: " .. line)
  local UIx = GCA.UI
  UIx:SetMemberMode("sheet")
  local c = UIx.sheet.centre
  local diffs = {}
  for i, r in ipairs(c.diffs or {}) do diffs[i] = UIx.StatText(r) end
  local all = table.concat(diffs, ", ")
  check(GCA.db.settings.memberView == "sheet" and UIx.selected == "Buddy Stone" and rawget(UIx.sheet, "_shown") and not rawget(sl, "_shown")
    and UIx.sheetSlot == 5 and c.mode == "upgrade" and c.featured == first.data.sec.rows[1] and UIx.sheet.slots[5].hasUpgrade
    and not UIx.sheet.slots[8].hasUpgrade and UIx.sheet.slots[8].worn and UIx.sheet.slots[8].worn.link,
    "sheet on real data: Buddy kept, chest selected (biggest upgrade, badge), the vest compared; feet worn, no badge")
  check(#diffs == 3 and all:find("+30 Armor", 1, true) and all:find("+3 Agility", 1, true) and all:find("+3 Stamina", 1, true),
    "stat differences from the real item stats: " .. all)
  check((UIx.errorCount or 0) == 0 and GCA:Diag().lastError == nil, "no error reported by the sheet")
  UIx:SetMemberMode("list")
end
GCA.UI.selected, GCA.UI.autoKey = nil, nil
GCA.UI:Refresh()
check(GCA.UI.selected == "Buddy Stone" and GCA.UI.autoKey == "Buddy Stone" and GCA.UI.memberList.rows[1].data.key == "Me" and GCA.UI.memberList.rows[1].data.best ~= nil,
  "default = best non-self member with a known upgrade; you stay first in the list")
do
  local selfRow = GCA.UI.memberList.rows[1]
  rawget(selfRow, "_scripts").OnClick(selfRow, "LeftButton")
  GCA.UI:Refresh()
  check(GCA.UI.selected == "Me" and GCA.UI.autoKey == nil, "clicking yourself sticks (no automatic re-pick)")
  GCA.UI.frame:Hide(); GCA.UI.frame:Show()
  check(GCA.UI.selected == "Me", "a manual pick survives closing and reopening")
  GCA.UI.selected, GCA.UI.autoKey = "Buddy Stone", "Buddy Stone"
  GCA.UI.frame:Hide(); GCA.UI.frame:Show()
  check(GCA.UI.selected == "Buddy Stone" and GCA.UI.autoKey == "Buddy Stone", "an automatic pick is redone on open")
end
local tipLines, hyper = {}, {}
GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
GameTooltip.AddDoubleLine = function(_, a, b) tipLines[#tipLines + 1] = a .. " | " .. b end
local savedHyper = GameTooltip.SetHyperlink
GameTooltip.SetHyperlink = function(_, l) hyper[#hyper + 1] = l end
local row = GCA.UI.sugList.rows[1]
rawget(row, "_scripts").OnEnter(row)
IsShiftKeyDown = function() return true end
ns.locale = "deDE"
rawget(row, "_scripts").OnEnter(row)
IsShiftKeyDown = nil; ns.locale = "enUS"
local joined = table.concat(tipLines, " | ")
check(#hyper == 2 and tostring(hyper[1]):find("item:4244", 1, true) and joined:find("Stat changes for", 1, true)
  and joined:find("+3 Agility", 1, true) and joined:find("Werteänderungen für", 1, true) and joined:find("+3 Beweglichkeit", 1, true),
  "suggestion row tooltip = the craft's item tooltip + 'Stat changes for <member>:' (English / German): " .. joined)
GameTooltip.SetHyperlink = savedHyper
do
  ns.locale = "deDE"
  local d = { info = { cstats = { Agility = 4 } }, equipped = { cstats = {} }, e = nil }
  local r1 = GCA.UI.StatDiff(d)
  SPELL_STAT2_NAME = "Beweglichkeit (Client)"
  local r2 = GCA.UI.StatDiff(d)
  SPELL_STAT2_NAME = nil; ns.locale = "enUS"
  check(r1 and r1[1] and r1[1].label == "Beweglichkeit" and r2[1].label == "Beweglichkeit (Client)",
    "German stat names in the stat differences; the client's SPELL_STAT2_NAME wins when it exists")
end
local mrow = GCA.UI.memberList.rows[2]
tipLines = {}
rawget(mrow, "_scripts").OnEnter(mrow)
for _, l in ipairs(tipLines) do print("  member tip:", l) end
check(table.concat(tipLines, "\n"):find("craftable upgrade", 1, true), "member tooltip shows the upgrade count")
do
  local upgrades, recorded = 0, 0
  for _, en in ipairs(GCA:GetMemberList()) do
    if en.member and not en.isSelf then recorded = recorded + 1; upgrades = upgrades + (en.knownCount or 0) end
  end
  check(upgrades == 1 and recorded == 2, ("member list: 1 known Leatherworking upgrade, 2 guildies recorded (%d, %d)"):format(upgrades, recorded))
end
local mark = #printed
GCA:KnownDebug()
check(printedSince(mark):find("Leatherworking item recipes: 501 in data, IsSpellKnown 3", 1, true), "/gca known debug: 501 LW recipes, 3 known")
mark = #printed
GCA:OnSlash("stats item:4244::::")
local out = printedSince(mark)
check(out:find("ITEM_MOD_AGILITY_SHORT=4", 1, true) and out:find("Canonical: Agility=4, Armor=90, Stamina=3", 1, true)
  and out:find("Score for Buddy Stone", 1, true), "/gca stats prints raw, canonical and the score")
mark = #printed
GCA:SpecDebug()
out = printedSince(mark)
check(out:find("announced over sync: COMBAT", 1, true) and out:find("ignored (off by default)", 1, true), "/gca spec debug: announced spec, inspect setting")
local box = { t = "" }
function box:GetText() return self.t end
function box:SetText(t) self.t = t end
ChatFrameUtil = { OpenChat = function(text) box.t = text:gsub("^/w %S+ ", "") end, GetActiveWindow = function() return box end }
Files.loadUI(ns)
local row = ns.GCA.UI

Minimap = CreateFrame()
rawset(Minimap, "GetWidth", function() return 140 end)
rawset(Minimap, "GetCenter", function() return 100, 100 end)
rawset(Minimap, "GetEffectiveScale", function() return 1 end)
local RQ = K.RQ
RQ:UpdateLauncher()
local b = K.ns.LauncherButton()
check(b ~= nil and _G.GuildCraftAdvisorMinimapButton == nil, "the suite launcher is the minimap button (no own Craft Advisor button)")
tipLines = {}
local mmEnter = b and rawget(b, "_scripts") and rawget(b, "_scripts").OnEnter
local okTip = mmEnter and pcall(mmEnter, b)
local tipText = table.concat(tipLines, " | ")
check(okTip and tipText:find("Guild Craft Advisor: " .. (GCA:OverviewStatus() or K.ns.LauncherL.NO_STATUS), 1, true) and tipText:find("Right-click", 1, true),
  "launcher tooltip: the Craft Advisor's status line, right-click opens our window: " .. tipText)
local showOpt
for _, o in ipairs(GCA.options) do if o.label == ns.L.OPT_MINIMAP then showOpt = o end end
showOpt.set(false)
check(showOpt.get() == false and RavenquillExpeditionDB.launcher.hide == true and not b:IsShown(), "option 'show minimap button' off hides the launcher")
showOpt.set(true)
check(showOpt.get() == true and not RavenquillExpeditionDB.launcher.hide and b:IsShown(), "and on shows it again")
do
  local F = GCA.FormatToPattern
  local p = F("Benötigt %1$s")
  check(p and ("Benötigt Ingenieurskunst (225)"):match(p) == "Ingenieurskunst (225)", "deDE positional format '%1$s' -> valid pattern")
  local q = F("Schaden: %1$d - %2$d")
  check(q and ("Schaden: 5 - 9"):match(q) == "5", "two positional %d specifiers")
  check(F("weird %q") == nil, "unknown specifier -> nil, no error")
  local oldReq = ITEM_REQ_SKILL
  ITEM_REQ_SKILL = "Benötigt %1$s"
  GCA.restrCache = nil
  local ok = pcall(GCA.ItemRestrictions, GCA, 4244)
  check(ok, "ItemRestrictions with a deDE template doesn't error")
  ITEM_REQ_SKILL = oldReq
end
do
  local store = GCA:KnownStore()
  local savedLW, savedAuth = store.Leatherworking, GCA.db.knownAuth
  local spells = {}
  for id in pairs(GCA:RecipeTable("Leatherworking")) do spells[#spells + 1] = id end
  table.sort(spells)
  local learned = { [spells[1]] = true, [spells[2]] = true }
  local function recipeAPI(ids)
    return { GetAllRecipeIDs = function() return ids end,
      GetRecipeInfo = function(id) return { learned = learned[id] == true } end }
  end
  C_TradeSkillUI = recipeAPI({ spells[1], spells[3], 999999 })
  store.Leatherworking, GCA.db.knownAuth = { [spells[5]] = true }, nil
  GCA:ScanTradeSkill()
  local lw = store.Leatherworking
  check(lw[spells[1]] and lw[spells[5]] and not lw[spells[3]] and GCA.db.knownAuth == nil,
    "trade skill scan with few answered recipes: learned ones added, saved ones kept, not authoritative")
  local many = {}
  for i = 1, 12 do many[i] = spells[i] end
  C_TradeSkillUI = recipeAPI(many)
  GCA:ScanTradeSkill()
  lw = store.Leatherworking
  local n = 0
  for _ in pairs(lw) do n = n + 1 end
  check(n == 2 and lw[spells[1]] and lw[spells[2]] and GCA.db.knownAuth[GCA.charKey].Leatherworking ~= nil,
    "trade skill scan with 12 answered recipes: authoritative, only the 2 learned ones kept")
  C_TradeSkillUI = nil
  local item = GCA:RecipeTable("Leatherworking")[spells[7]].item
  GetNumTradeSkills = function() return 1 end
  GetTradeSkillLine = function() return "Lederverarbeitung" end
  GetTradeSkillItemLink = function() return "item:" .. item .. "::::" end
  GetTradeSkillRecipeLink = function() return "enchant:" .. spells[8] end
  GCA:ScanTradeSkill()
  lw = store.Leatherworking
  check(lw[GCA:ItemToSpell("Leatherworking")[item]] and lw[spells[8]],
    "legacy trade skill window: the item link and the recipe link both mark recipes")
  GetNumTradeSkills, GetTradeSkillLine, GetTradeSkillItemLink, GetTradeSkillRecipeLink = nil, nil, nil, nil
  store.Leatherworking, GCA.db.knownAuth = savedLW, savedAuth
  GCA:RefreshKnown()
end
print = rawprint
print(("\n%d passed, %d failed"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
