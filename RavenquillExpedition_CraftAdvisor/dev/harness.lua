local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local Kit = dofile(ROOT .. "../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check
local CA = "RavenquillExpedition_CraftAdvisor"
local Files = dofile(ROOT .. "dev/files.lua")
local files = Files.kitFiles({ "Locales/enUS.lua", "Locales/deDE.lua", "Data/Leatherworking.lua", "Data/Blacksmithing.lua",
  "Data/Tailoring.lua", "Data/Engineering.lua", "Data/Enchanting.lua", "Data/Enchants.lua" })
for _, f in ipairs(Files.kitFiles(Files.list({ from = "Data/Weights.lua", except = { "Data/Sources.lua", "Sync", "RecipeSources.lua" } }))) do
  files[#files + 1] = f
end
local units = {
  player = { name="Me", class="ROGUE", level=30, guid="G-me", items={ [8]="item:2302::::" } },
  target = { name="Buddy", class="DRUID", level=28, guid="G-buddy", items={ [5]="item:2300::::", [8]="item:2302::::" } },
  party1 = { name="Mage", class="MAGE", level=30, guid="G-mage", items={} },
}
local notified
local itemMeta = {}
itemMeta[2302] = { loc="INVTYPE_FEET", sub=2, lvl=1, stats={RESISTANCE0_NAME=30} }
itemMeta[2300] = { loc="INVTYPE_CHEST", sub=2, lvl=8, stats={RESISTANCE0_NAME=60, ITEM_MOD_AGILITY_SHORT=1} }
itemMeta[4244] = { loc="INVTYPE_CHEST", sub=2, lvl=20, stats={RESISTANCE0_NAME=90, ITEM_MOD_AGILITY_SHORT=4, ITEM_MOD_STAMINA_SHORT=3} }
local sched = Kit.Scheduler()
local client = Kit.Client(sched, nil, "Me", { files = files, setup = function(env)
  env.C_ChatInfo = nil
  function env.UnitNameUnmodified(u) if u=="target" then return "Buddy","Stone" end return env.UnitName(u) end
  env.RavenquillExpeditionCraftDB = { members = { ["Old-Timer"] = { time = 5, items = {} } } }
  env.GameTooltip_Hide = function() end
  env.C_SpellBook = { IsSpellKnown = function(id) return id == 2149 or id == 2160 or id == 3762 end }
  env.RAID_CLASS_COLORS = { DRUID = {r=1,g=.49,b=.04}, ROGUE={r=1,g=.96,b=.41}, MAGE={r=.41,g=.8,b=.94} }
  env.ITEM_QUALITY_COLORS = { [1]={r=1,g=1,b=1}, [2]={r=.1,g=1,b=.1}, [3]={r=0,g=.4,b=1} }
  env.LOCALIZED_CLASS_NAMES_MALE = { DRUID="Druide", ROGUE="Schurke", MAGE="Magier" }
  function env.InCombatLockdown() return false end
  function env.IsInGuild() return true end
  function env.IsInRaid() return false end
  function env.GetNumSubgroupMembers() return 1 end
  function env.GetNumGroupMembers() return 2 end
  function env.GetRealmName() return "Realm" end
  function env.Ambiguate(n) return (n:gsub("%-Realm$","")) end
  function env.UnitName(u) local x=units[u]; return x and x.name end
  function env.UnitClass(u) local x=units[u]; return x and x.class, x and x.class end
  function env.UnitLevel(u) local x=units[u]; return x and x.level end
  function env.UnitGUID(u) local x=units[u]; return x and x.guid end
  function env.UnitIsPlayer(u) return units[u] ~= nil end
  function env.UnitIsUnit(a,b) return units[a] and units[a]==units[b] end
  function env.UnitIsInMyGuild(u) return units[u] ~= nil end
  function env.UnitExists(u) return units[u] ~= nil end
  function env.CanInspect() return true end
  function env.NotifyInspect(u) notified = u end
  function env.GetInventoryItemLink(u, slot) local x=units[u]; return x and x.items[slot] end
  function env.GetInventorySlotInfo(t) return 1, "tex" end
  function env.GetNumGuildMembers() return 2 end
  function env.GetGuildRosterInfo(i) if i==1 then return "Buddy Stone",nil,nil,28,nil,nil,nil,nil,true,nil,"DRUID" else return "Offy-Realm",nil,nil,50,nil,nil,nil,nil,false,nil,"ROGUE" end end
  function env.GetProfessions() return 1, nil end
  function env.GetProfessionInfo(i) return "Lederverarbeitung", nil, 120, 150, nil, nil, 165 end
  env.C_Item = {
    GetItemInfoInstant = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id]; if not m then return id, "Misc","Misc","",1,15,0 end return id,"Armor","x",m.loc,1,4,m.sub end,
    GetItemInfo = function(item) local id = type(item)=="number" and item or tonumber(tostring(item):match("item:(%d+)")); local m = itemMeta[id] or {loc="",sub=0,lvl=1}; return "Item"..id, "|Hitem:"..id.."|h[Item"..id.."]|h", 2, 20, m.lvl, nil,nil,nil, m.loc, 1, nil, 4, m.sub, m.bind or 2 end,
    GetItemStats = function(link) local id = tonumber(link:match("item:(%d+)")); local m = itemMeta[id]; return m and m.stats or {} end,
    RequestLoadItemDataByID = function() end,
    GetItemNameByID = function(id) return "Reagent"..id end,
    GetItemCount = function() return 3 end,
  }
end })
local env = client.env
local ns, fire, printed = client.ns[CA], client.fire, client.printed
local printedSince = client.printedSince
local GCA = ns.GCA
local h = function(_, ev, ...) fire(ev, ...) end
h(GCA, "ADDON_LOADED", "RavenquillExpedition")
h(GCA, "ADDON_LOADED", "RavenquillExpedition_CraftAdvisor")
h(GCA, "PLAYER_LOGIN"); sched:flush(200)
h(GCA, "GUILD_ROSTER_UPDATE"); sched:flush(200)
env.print("known", GCA:KnownCount(GCA:SelectedProfession()))
check(GCA:KnownCount(GCA:SelectedProfession()) == 3, "3 recipes known (IsSpellKnown)")
GCA:InspectTarget(); env.print("notified", notified)
check(notified == "target", "Inspect target -> NotifyInspect(target)")
h(GCA, "INSPECT_READY", "G-buddy"); sched:flush(200)
GCA:ScanGroup(); sched:flush(200); h(GCA, "INSPECT_READY", "G-mage"); sched:flush(200)
for k, m in pairs(env.RavenquillExpeditionCraftDB.members) do env.print("member", k, m.class, m.level, m.source) end
local bud = env.RavenquillExpeditionCraftDB.members["Buddy Stone"]
check(bud and bud.class == "DRUID" and bud.level == 28 and bud.source == "inspect" and bud.items[5], "Buddy Stone recorded from the inspect (DRUID 28, chest)")
check(env.RavenquillExpeditionCraftDB.members["Old Timer"] and not env.RavenquillExpeditionCraftDB.members["Old-Timer"], "v0.1 key \"Old-Timer\" migrated to \"Old Timer\"")
check(env.RavenquillExpeditionCraftDB.members["Me"] and env.RavenquillExpeditionCraftDB.members["Me"].source == "self", "own gear recorded")
local byKey = {}
for _, e in ipairs(GCA:GetMemberList()) do
  env.print("entry (no spec yet)", e.key, e.level, e.online, e.member and "inspected" or "-", e.suggestions and #e.suggestions, e.state)
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
  env.print("entry", e.key, e.level, e.spec, e.specHow, e.suggestions and #e.suggestions, e.state)
  for _, s in ipairs(e.suggestions or {}) do
    env.print("   ", s.slot, s.info.name, s.status, string.format("%.2f -> %.2f  %s  pts %+.2f", s.oldScore, s.newScore, s.pct and string.format("%+.1f%%", s.pct * 100) or "-", s.points), s.known)
  end
  if e.weights then env.print("    source:", GCA:SourceLine(e.weights)) end
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
env.print("with unlearned:", #e)
check(#e >= 1, "show unlearned: still computes")
check(GCA.db.settings.memberView == "sheet", "member view defaults to the character sheet")
GCA.db.settings.memberView = "list"
GCA.UI:Toggle(); sched:flush(200)
env.print("UI shown", GCA.UI.frame:IsShown(), "selected", GCA.UI.selected, "auto", GCA.UI.autoKey, "first", GCA.UI.memberList.pools.default[1].data.key, GCA.UI.memberList.pools.default[1].data.best, "rows", #GCA.UI.sugList.pools.default)
check(GCA.UI.frame:IsShown() and GCA.UI.selected == "Buddy Stone" and #GCA.UI.sugList.pools.default >= 1, "/gca opens the window with Buddy selected and a suggestion row")
do
  local sl = GCA.UI.sugList
  local pools = rawget(sl, "pools")
  local secs, fold = pools.section or {}, (pools.fold or {})[1]
  local shownSecs = 0
  for _, s in ipairs(secs) do if rawget(s, "_shown") ~= false then shownSecs = shownSecs + 1 end end
  local first = secs[1]
  check(first and first.data.sec.key == 5 and #first.data.sec.rows == 1 and sl.pools.default[1].data == first.data.sec.rows[1]
    and shownSecs == 1 and fold and #fold.data.secs == 14 and sl.data[#sl.data] == fold.data
    and (GCA.UI.errorCount or 0) == 0 and GCA:Diag().lastError == nil,
    "real refresh -> chest section first with the vest row, the 14 others folded into one last line, no reported error ("
    .. shownSecs .. " sections, " .. (fold and #fold.data.secs or 0) .. " folded)")
  check(GCA.UI.view == "make" and GCA.UI:Pane().id == "member", "the window opens on 'Craft', by member")
  GCA.UI:SetView("make", "all")
  local nl = GCA.UI.needsList
  check(GCA.UI:Pane().id == "all" and nl.data[1] and nl.data[1].rowKind == "cat" and nl.data[1].cat == 5 and nl.data[2] and nl.data[2].group
    and nl.data[2].rows[1].member.key == "Buddy Stone"
    and nl.data[2].group.sug == first.data.sec.rows[1] and nl.data[2].group == GCA:GuildNeedsByCraft(GCA.UI.lastMembers)[1]
    and GCA.UI.needDetail.entry == nl.data[2] and GCA.UI.needDetail.members.pools.default[1].data.member.key == "Buddy Stone",
    "craft for everyone: 'Chest' category, first craft = Buddy's vest, shown in the detail panel (real Core GuildNeedsByCraft)")
  local mrow
  for _, r in ipairs(rawget(GCA.UI.memberList, "pools").default) do if r.data and r.data.key == "Buddy Stone" then mrow = r end end
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
check(GCA.UI.selected == "Buddy Stone" and GCA.UI.autoKey == "Buddy Stone" and GCA.UI.memberList.pools.default[1].data.key == "Me" and GCA.UI.memberList.pools.default[1].data.best ~= nil,
  "default = best non-self member with a known upgrade; you stay first in the list")
do
  local selfRow = GCA.UI.memberList.pools.default[1]
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
env.GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
env.GameTooltip.AddDoubleLine = function(_, a, b) tipLines[#tipLines + 1] = a .. " | " .. b end
local savedHyper = env.GameTooltip.SetHyperlink
env.GameTooltip.SetHyperlink = function(_, l) hyper[#hyper + 1] = l end
local row = GCA.UI.sugList.pools.default[1]
rawget(row, "_scripts").OnEnter(row)
env.IsShiftKeyDown = function() return true end
ns.locale = "deDE"
rawget(row, "_scripts").OnEnter(row)
env.IsShiftKeyDown = nil; ns.locale = "enUS"
local joined = table.concat(tipLines, " | ")
check(#hyper == 2 and tostring(hyper[1]):find("item:4244", 1, true) and joined:find("Stat changes for", 1, true)
  and joined:find("+3 Agility", 1, true) and joined:find("Werteänderungen für", 1, true) and joined:find("+3 Beweglichkeit", 1, true),
  "suggestion row tooltip = the craft's item tooltip + 'Stat changes for <member>:' (English / German): " .. joined)
env.GameTooltip.SetHyperlink = savedHyper
do
  ns.locale = "deDE"
  local d = { info = { cstats = { Agility = 4 } }, equipped = { cstats = {} }, e = nil }
  local r1 = GCA.UI.StatDiff(d)
  env.SPELL_STAT2_NAME = "Beweglichkeit (Client)"
  local r2 = GCA.UI.StatDiff(d)
  env.SPELL_STAT2_NAME = nil; ns.locale = "enUS"
  check(r1 and r1[1] and r1[1].label == "Beweglichkeit" and r2[1].label == "Beweglichkeit (Client)",
    "German stat names in the stat differences; the client's SPELL_STAT2_NAME wins when it exists")
end
local mrow = GCA.UI.memberList.pools.default[2]
tipLines = {}
rawget(mrow, "_scripts").OnEnter(mrow)
for _, l in ipairs(tipLines) do env.print("  member tip:", l) end
check(table.concat(tipLines, "\n"):find("craftable upgrade", 1, true), "member tooltip shows the upgrade count")
do
  local upgrades, recorded = 0, 0
  for _, en in ipairs(GCA:GetMemberList()) do
    if en.member and not en.isSelf then recorded = recorded + 1; upgrades = upgrades + (en.knownCount or 0) end
  end
  check(upgrades == 1 and recorded == 2, ("member list: 1 known Leatherworking upgrade, 2 guildies recorded (%d, %d)"):format(upgrades, recorded))
end
do
  local RQc, UIx = client.RQ, GCA.UI
  local function CraftPage()
    local ov = env.RavenquillExpeditionOverview
    return ov and ov.optView.pages.Craft
  end
  local function Rows() return (CraftPage() or {}).rows or {} end
  local function RowTexts()
    local out = {}
    for _, r in ipairs(Rows()) do out[#out + 1] = r.label:GetText() .. " " .. tostring(r.count:GetText()) end
    return table.concat(out, " | ")
  end
  local function RowTip(i)
    local lines, gt = {}, env.GameTooltip
    local setText, addLine = gt.SetText, gt.AddLine
    gt.SetText = function(_, t) lines[#lines + 1] = t end
    gt.AddLine = function(_, t) lines[#lines + 1] = t end
    rawget(Rows()[i], "_scripts").OnEnter(Rows()[i])
    gt.SetText, gt.AddLine = setText, addLine
    return table.concat(lines, " / ")
  end
  local function ShowCraftPage()
    RQc:ShowHome()
    RQc:ShowModulePage("Craft")
  end
  local function ClickRow(i) rawget(Rows()[i], "_scripts").OnClick(Rows()[i]) end
  local buddyGain
  for _, r in ipairs(rawget(UIx.memberList, "pools").default) do
    if r.data and r.data.key == "Buddy Stone" then buddyGain = r.gain:GetText() end
  end
  client.frameMethods.SetTexture = function(t, file) t._tex = file end
  ShowCraftPage()
  client.frameMethods.SetTexture = nil
  local rows = Rows()
  check(#rows == 2 and RowTexts() == "Craft 1 | Get crafted 0" and rows[1].icon._tex == "Interface\\Icons\\INV_Hammer_20"
    and rows[2].icon._tex == "Interface\\Icons\\INV_Scroll_03" and rows[1].more:GetText() == "›",
    "/rq craft: two rows, hammer 'Craft' with 1 craft worth making, recipe scroll 'Get crafted' with 0 crafters: " .. RowTexts())
  check(#CraftPage()._children == 2 and CraftPage()._children[1] == rows[1] and CraftPage()._children[2] == rows[2] and CraftPage().entries == nil,
    "the page holds only the two clickable rows: no cards with subtitles, no 'Open' buttons")
  check(tostring(buddyGain):match("^%+%d") and RowTip(1) == "Craft / 1 craft is worth it for 1 member / Buddy Stone gains the most: " .. tostring(buddyGain)
    and RowTip(2) == "Get crafted / Nobody has shared recipes yet",
    "the details sit in the row tooltips (the gain the member list shows): " .. RowTip(1) .. " | " .. RowTip(2))
  local buddy = GCA.db.members["Buddy Stone"]
  GCA.db.members["Buddy Stone"] = nil
  GCA:StoreCrafter("Buddy Stone", 100, { Leatherworking = { rank = 150, ids = { 2149, 2160 } } })
  ShowCraftPage()
  check(RowTexts() == "Craft 0 | Get crafted 1" and RowTip(1) == "Craft / Nobody needs anything you can craft right now"
    and RowTip(2) == "Get crafted / 1 guildmate shares their recipes",
    "Buddy's gear gone and his recipes shared: counts and tooltips follow the next time the page is shown: " .. RowTexts())
  GCA.db.members["Buddy Stone"] = buddy
  GCA:ForgetCrafter("Buddy Stone")
  UIx.frame:Hide()
  ClickRow(1)
  check(UIx.frame:IsShown() and UIx:Pane().id == "member" and rawget(UIx.memberView, "_shown") and UIx.selected == "Buddy Stone",
    "a click anywhere on the Craft row opens the window on Craft by member, on Buddy")
  ClickRow(2)
  check(UIx.frame:IsShown() and UIx.view == "commission" and rawget(UIx.crafterView, "_shown") and not rawget(UIx.memberView, "_shown"),
    "with the window open, a click on the Get crafted row switches it to that tab")
  env.RavenquillExpeditionOverview:Hide()
end
do
  local RQc, UIx = client.RQ, GCA.UI
  local function CraftRow()
    RQc:ShowHome()
    local list = env.RavenquillExpeditionOverview.home.list
    for _, item in ipairs(list and list.items or {}) do
      if rawget(item, "_shown") and item.title:GetText() == "Guild Craft Advisor" then return item end
    end
  end
  local function Line() local item = CraftRow(); return item and item.line:GetText() end
  UIx.frame:Hide()
  RQc:ToggleOverview()
  check(Line() == "1 guildmate could use your crafts", "/rq home: the Craft row counts the guildmates your crafts would upgrade: " .. tostring(Line()))
  local craftRow = CraftRow()
  if craftRow then rawget(craftRow, "_scripts").OnClick(craftRow) end
  check(UIx.frame:IsShown() and UIx:Pane().id == "all" and rawget(UIx.needsView, "_shown")
    and tostring(UIx.needsCount:GetText()):find("for 1 member", 1, true) ~= nil,
    "clicking it opens the window on Craft for everyone, whose count names the same member: " .. tostring(UIx.needsCount:GetText()))
  local buddy = GCA.db.members["Buddy Stone"]
  GCA.db.members["Buddy Stone"] = nil
  check(Line() == "Nobody needs anything you can craft right now", "Buddy's gear gone: the row says so on the next refresh: " .. tostring(Line()))
  GCA.db.members["Buddy Stone"] = buddy
  check(Line() == "1 guildmate could use your crafts", "and counts him again once his gear is back: " .. tostring(Line()))
  UIx.frame:Hide()
  env.RavenquillExpeditionOverview:Hide()
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
check(out:find("announced over sync: COMBAT", 1, true) and out:find("inspected talents are used when plausible", 1, true), "/gca spec debug: announced spec, inspected talents used")
local box = { t = "" }
function box:GetText() return self.t end
function box:SetText(t) self.t = t end
env.ChatFrameUtil = { OpenChat = function(text) box.t = text:gsub("^/w %S+ ", "") end, GetActiveWindow = function() return box end }
Files.loadUI(ns, env)

env.Minimap = env.CreateFrame()
rawset(env.Minimap, "GetWidth", function() return 140 end)
rawset(env.Minimap, "GetCenter", function() return 100, 100 end)
rawset(env.Minimap, "GetEffectiveScale", function() return 1 end)
local RQ = client.RQ
RQ:UpdateLauncher()
local b = client.coreNs.LauncherButton()
check(b ~= nil and env.GuildCraftAdvisorMinimapButton == nil, "the suite launcher is the minimap button (no own Craft Advisor button)")
tipLines = {}
local mmEnter = b and rawget(b, "_scripts") and rawget(b, "_scripts").OnEnter
local okTip = mmEnter and pcall(mmEnter, b)
local tipText = table.concat(tipLines, " | ")
check(okTip and tipText:find("Guild Craft Advisor: " .. (GCA:OverviewStatus() or client.coreNs.LauncherL.NO_STATUS), 1, true) and tipText:find("Right-click", 1, true),
  "launcher tooltip: the Craft Advisor's status line, right-click opens our window: " .. tipText)
local minimapOpt
for _, o in ipairs(GCA.options) do if tostring(o.label):lower():find("minimap", 1, true) then minimapOpt = o end end
RQ:SetLauncherShown(false)
check(minimapOpt == nil and env.RavenquillExpeditionDB.launcher.hide == true and not b:IsShown(),
  "the minimap button is the suite's, switched in the /rq overview, not in the Craft Advisor's options")
RQ:SetLauncherShown(true)
check(not env.RavenquillExpeditionDB.launcher.hide and b:IsShown(), "and on shows it again")
do
  local F = GCA.FormatToPattern
  local p = F("Benötigt %1$s")
  check(p and ("Benötigt Ingenieurskunst (225)"):match(p) == "Ingenieurskunst (225)", "deDE positional format '%1$s' -> valid pattern")
  local q = F("Schaden: %1$d - %2$d")
  check(q and ("Schaden: 5 - 9"):match(q) == "5", "two positional %d specifiers")
  check(F("weird %q") == nil, "unknown specifier -> nil, no error")
  local oldReq = env.ITEM_REQ_SKILL
  env.ITEM_REQ_SKILL = "Benötigt %1$s"
  GCA.restrCache = nil
  local ok = pcall(GCA.ItemRestrictions, GCA, 4244)
  check(ok, "ItemRestrictions with a deDE template doesn't error")
  env.ITEM_REQ_SKILL = oldReq
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
  env.C_TradeSkillUI = recipeAPI({ spells[1], spells[3], 999999 })
  store.Leatherworking, GCA.db.knownAuth = { [spells[5]] = true }, nil
  GCA:ScanTradeSkill()
  local lw = store.Leatherworking
  check(lw[spells[1]] and lw[spells[5]] and not lw[spells[3]] and GCA.db.knownAuth == nil,
    "trade skill scan with few answered recipes: learned ones added, saved ones kept, not authoritative")
  local many = {}
  for i = 1, 12 do many[i] = spells[i] end
  env.C_TradeSkillUI = recipeAPI(many)
  GCA:ScanTradeSkill()
  lw = store.Leatherworking
  local n = 0
  for _ in pairs(lw) do n = n + 1 end
  check(n == 2 and lw[spells[1]] and lw[spells[2]] and GCA.db.knownAuth[GCA.charKey].Leatherworking ~= nil,
    "trade skill scan with 12 answered recipes: authoritative, only the 2 learned ones kept")
  env.C_TradeSkillUI = nil
  local item = GCA:RecipeTable("Leatherworking")[spells[7]].item
  env.GetNumTradeSkills = function() return 1 end
  env.GetTradeSkillLine = function() return "Lederverarbeitung" end
  env.GetTradeSkillItemLink = function() return "item:" .. item .. "::::" end
  env.GetTradeSkillRecipeLink = function() return "enchant:" .. spells[8] end
  GCA:ScanTradeSkill()
  lw = store.Leatherworking
  check(lw[GCA:ItemToSpell("Leatherworking")[item]] and lw[spells[8]],
    "legacy trade skill window: the item link and the recipe link both mark recipes")
  env.GetNumTradeSkills, env.GetTradeSkillLine, env.GetTradeSkillItemLink, env.GetTradeSkillRecipeLink = nil, nil, nil, nil
  store.Leatherworking, GCA.db.knownAuth = savedLW, savedAuth
  GCA:RefreshKnown()
end
do
  local db, members = GCA.db, GCA.db.members
  local function listed()
    local memberByKey, keys = {}, {}
    for _, en in ipairs(GCA:GetMemberList()) do memberByKey[en.key] = en; keys[#keys + 1] = en.key end
    return memberByKey, table.concat(keys, ", ")
  end
  local savedHide = db.settings.hideOffline
  db.settings.hideOffline = false
  local list, keys = listed()
  local offy = list["Offy"]
  check(offy and offy.online == false and offy.member == nil and offy.class == "ROGUE" and offy.level == 50
    and list["Old Timer"] and list["Old Timer"].online == false, "offline guildie without a record and an offline record outside the roster are both listed: " .. keys)
  db.settings.hideOffline = true
  list, keys = listed()
  check(list["Offy"] == nil and list["Old Timer"] and list["Buddy Stone"] and list["Me"], "'hide offline' drops only offline guildies without a record: " .. keys)
  members["Alt Char"] = { class = "MAGE", level = 12, source = "self", items = {} }
  members["Gone Guildie"] = { class = "MAGE", level = 12, source = "inspect", items = {} }
  list, keys = listed()
  check(list["Alt Char"] == nil and list["Gone Guildie"] and list["Gone Guildie"].class == "MAGE" and list["Gone Guildie"].level == 12,
    "a record of your own alt outside the roster is not listed, someone else's is (class and level from the record): " .. keys)
  members["Alt Char"], members["Gone Guildie"] = nil, nil
  local buddy = members["Buddy Stone"]
  local savedClass, savedLevel = buddy.class, buddy.level
  buddy.class, buddy.level = "MAGE", 20
  list = listed()
  check(list["Buddy Stone"].class == "DRUID" and list["Buddy Stone"].level == 28, "the live roster's class and level win over a stale record")
  buddy.class, buddy.level = savedClass, savedLevel
  itemMeta[9001] = { loc = "INVTYPE_WEAPON", sub = 0, lvl = 1, stats = {} }
  members["Wave Shammy"] = { class = "SHAMAN", level = 30, source = "inspect", items = { [17] = "item:9001::::" } }
  db.specs["Wave Shammy"] = { class = "SHAMAN", tree = "ENHANCEMENT", src = "inspect", ts = 1 }
  list = listed()
  check(list["Wave Shammy"] and list["Wave Shammy"].spec == "ENHANCEMENT_DW" and list["Wave Shammy"].specAssumed,
    "an inspected Enhancement tree with a one-hander in the stored off hand -> dual-wield spec, assumed")
  members["Wave Shammy"], db.specs["Wave Shammy"] = nil, nil
  db.settings.hideOffline = savedHide
end
Kit.finish()
