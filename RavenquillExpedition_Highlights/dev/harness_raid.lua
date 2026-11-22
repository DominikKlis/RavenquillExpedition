local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local check = Kit.check
local HL = "RavenquillExpedition_Highlights"

local EPOCH = 1800000000
local TITLES = { [4322] = "Gefängnisausbruch!", [6403] = "Die große Maskerade", [7848] = "Einstimmung auf den Kern" }

local function Stubs(env, faction)
  env.RAID_CLASS_COLORS = {}
  env.Enum = { QuestTag = {} }
  env.C_Item = { GetItemInfo = function() end, GetDetailedItemLevelInfo = function() end, RequestLoadItemDataByID = function() end }
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  function env.GetInventoryItemLink() end
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, GetTitleForQuestID = function(id) return TITLES[id] end }
  env.UnitFactionGroup = function() return faction or "Alliance" end
end

local function NewWorld()
  local sched, bus = Kit.Setup()
  local w = { sched = sched, bus = bus, seed = 0 }

  function w.join(name, opts)
    opts = opts or {}
    w.seed = w.seed + 1
    local c = Kit.Client(sched, bus, name, { guild = "Die Gilde", realm = "Forever", locale = opts.locale or "deDE",
      class = opts.class or "PALADIN", level = opts.level or 60, epoch = EPOCH, random = Kit.Random(w.seed * 7919),
      addons = { HL }, setup = function(env, cl)
        Stubs(env, opts.faction)
        if opts.setup then opts.setup(env, cl) end
      end })
    c.H = c.ns[HL].H
    bus:setOnline(name, true)
    c.login()
    return c
  end

  function w.sent(pattern, sender)
    return bus:count(function(x) return x.msg:find(pattern) ~= nil and (not sender or x.sender == sender) end)
  end

  return w
end

Kit.section("Every attunement step quest is a milestone the guild hears about")
do
  local w = NewWorld()
  local mira = w.join("Mira Sturmfeder")
  local rika = w.join("Rika Steinbeck")
  w.sched:advance(60)
  mira.fire("QUEST_TURNED_IN", 4322, 1000, 500)
  w.sched:advance(120)
  local events = rika.H:Log()
  local heard = events[#events]
  check(heard and heard.k == "quest" and heard.qid == 4322 and heard.who == "Mira Sturmfeder" and heard.tag == "special",
    "a mid-chain step (Gefängnisausbruch!) reaches a guildmate as a milestone highlight")
  check(w.sent("^H;1;q;%d+;%d+;Mira Sturmfeder;60;%d+;4322;", "Mira Sturmfeder") == 1, "it took one guild message")
  local activity = 0
  for _, a in ipairs(mira.H.cdb.activity) do if a.k == "quest" and a.qid == 4322 then activity = activity + 1 end end
  check(activity == 0, "and it is not tucked away as unshared activity")
  check(#mira.errors == 0 and #rika.errors == 0, "no Lua errors (" .. tostring(mira.errors[1] or rika.errors[1]) .. ")")
end

local GUILD = {
  { "Mira Sturmfeder", "PRIEST", 60, true }, { "Rika Steinbeck", "WARRIOR", 58, true },
  { "Tamo Eichengrund", "HUNTER", 57, true }, { "Bodo Kesselring", "PALADIN", 56, true },
  { "Kael Wintermoor", "WARLOCK", 50, true }, { "Ilsa Brunnhold", "SHAMAN", 60, false },
}
local MILESTONES = {
  ["Mira Sturmfeder"] = { 7848, 4322, 6403, 6502, 4743 },
  ["Rika Steinbeck"] = { 7848, 4322, 6403 },
  ["Tamo Eichengrund"] = { 6502 },
  ["Kael Wintermoor"] = { 7848 },
}

local seq = 0
local function Milestone(c, who, qid, t)
  seq = seq + 1
  local e = { k = "quest", t = t, who = who, lvl = 60, cls = "PRIEST", id = ("%s#%d#%d"):format(who, t, seq), qid = qid,
    tag = "special", title = TITLES[qid] or ("#" .. qid) }
  return c.H:Add(e, "wire")
end

local function Roster(w, c)
  for _, m in ipairs(GUILD) do
    w.bus:member(m[1], m[2], m[3], true)
    if m[4] then c.RQ:NotePeer(m[1]) end
  end
  c.fire("GUILD_ROSTER_UPDATE")
end

local function Guild(w, c)
  Roster(w, c)
  local t = c.env.time() - 86400
  for _, m in ipairs(GUILD) do
    for i, qid in ipairs(MILESTONES[m[1]] or {}) do Milestone(c, m[1], qid, t + i * 60) end
  end
end

local function Cells(row)
  local out = {}
  for _, st in ipairs(row.raids) do
    out[#out + 1] = st.raid .. "=" .. (st.state == "partial" and (st.n .. "/" .. st.m) or st.state)
      .. (st.next and (">" .. st.next.label) or "")
  end
  return row.who .. ": " .. table.concat(out, " ")
end

local function Table(model)
  local out = {}
  for i, row in ipairs(model.rows) do out[i] = Cells(row) end
  return out
end

local function Missing(summary)
  local out = {}
  for i, m in ipairs(summary.missing) do out[i] = m.who .. ">" .. m.step.label end
  return table.concat(out, ", ")
end

Kit.section("Readiness: milestone highlights give each member done, partial or none per raid, with the next step")
do
  local w = NewWorld()
  local lyra = w.join("Lyra Distelbach", { class = "MAGE" })
  Guild(w, lyra)
  local model = lyra.H:ReadinessModel()
  local got = Table(model)
  local want = {
    "Mira Sturmfeder: mc=done ony=done bwl=1/2>STEP_ORB",
    "Rika Steinbeck: mc=done ony=2/3>STEP_AMULET bwl=none>STEP_SEAL",
    "Tamo Eichengrund: mc=none>STEP_CORE_FRAGMENT ony=done bwl=none>STEP_SEAL",
    "Lyra Distelbach: mc=none>STEP_CORE_FRAGMENT ony=none>STEP_WINDSOR bwl=none>STEP_SEAL",
    "Bodo Kesselring: mc=none>STEP_CORE_FRAGMENT ony=none>STEP_WINDSOR bwl=none>STEP_SEAL",
  }
  for i = 1, math.max(#want, #got) do
    check(got[i] == want[i], ("row %d: %s"):format(i, tostring(got[i])))
  end
  check(model.low == 1 and model.away == 1,
    "Kael (level 50) and Ilsa (no Ravenquill, nothing heard) are left out of the table, counted (" .. model.low .. ", " .. model.away .. ")")
  local H = lyra.H
  local horde = H.Readiness({ [4974] = 1, [4322] = 1, [6403] = 1 }, H.RaidsFor("Horde"))
  check(horde[2].raid == "ony" and horde[2].state == "partial" and horde[2].n == 1 and horde[2].next.label == "STEP_SKULLS",
    "a Horde guild follows the Horde chain: Rend done, the Tests of Skulls next; Alliance quests do not count")
  check(#H.RaidsFor(nil) == 3 and #H.RaidsFor("Alliance") == 3, "one column per raid, whatever the faction")
  check(#lyra.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1]) .. ")")
end

Kit.section("Readiness summary: who is attuned, who is almost there, and what each one still needs")
do
  local w = NewWorld()
  local lyra = w.join("Lyra Distelbach", { class = "MAGE" })
  Guild(w, lyra)
  local model = lyra.H:ReadinessModel()
  local ony = lyra.H.RaidSummary(model, "ony")
  check(ony.raid == "ony" and ony.done == 2 and ony.almost == 1 and ony.total == 5,
    ("Onyxia: 2 attuned, 1 almost, of 5 listed (%d, %d, %d)"):format(ony.done, ony.almost, ony.total))
  check(Missing(ony) == "Rika Steinbeck>STEP_AMULET, Lyra Distelbach>STEP_WINDSOR, Bodo Kesselring>STEP_WINDSOR",
    "the almost-attuned come first, each with their next step (" .. Missing(ony) .. ")")
  local mc = lyra.H.RaidSummary(model, "mc")
  check(mc.done == 2 and mc.almost == 0 and Missing(mc) == "Tamo Eichengrund>STEP_CORE_FRAGMENT, Lyra Distelbach>STEP_CORE_FRAGMENT, Bodo Kesselring>STEP_CORE_FRAGMENT",
    "Molten Core: 2 attuned, nobody halfway on a one-step attunement (" .. Missing(mc) .. ")")
  check(lyra.H.RaidSummary(model, "nope").raid == "mc", "an unknown raid falls back to the first column")
end

Kit.section("Readiness outlives the log: milestones pruned from the 1500-entry log still count, also after a reload")
do
  local w = NewWorld()
  local lyra = w.join("Lyra Distelbach", { class = "MAGE" })
  Guild(w, lyra)
  local H = lyra.H
  local cap = H.MAX_EVENTS
  H.MAX_EVENTS = 3
  local t = lyra.env.time()
  for i = 1, 3 do H:Add({ k = "level", t = t - 100 + i, who = "Bodo Kesselring", lvl = 56, id = "Bodo Kesselring#" .. (t + i) .. "#" .. i }, "wire") end
  H.MAX_EVENTS = cap
  local left = 0
  for _, e in ipairs(H:Log()) do if e.k == "quest" then left = left + 1 end end
  check(left == 0, "setup: every milestone left the log")
  check(Table(H:ReadinessModel())[1] == "Mira Sturmfeder: mc=done ony=done bwl=1/2>STEP_ORB", "Mira still reads attuned")
  lyra.fire("PLAYER_LOGOUT")
  lyra.online = false
  local saved = { db = lyra.env.RavenquillExpeditionHighlightsDB, cdb = lyra.env.RavenquillExpeditionHighlightsCharDB }
  local again = w.join("Lyra Distelbach", { class = "MAGE", setup = function(env)
    env.RavenquillExpeditionHighlightsDB, env.RavenquillExpeditionHighlightsCharDB = saved.db, saved.cdb
  end })
  Roster(w, again)
  check(#again.H:Log() == 3 and Table(again.H:ReadinessModel())[2] == "Rika Steinbeck: mc=done ony=2/3>STEP_AMULET bwl=none>STEP_SEAL",
    "after a reload Rika's progress is still there")
end

Kit.section("Readiness ignores test entries once they are removed")
do
  local w = NewWorld()
  local lyra = w.join("Lyra Distelbach", { class = "MAGE" })
  Guild(w, lyra)
  local function Mine()
    for _, row in ipairs(lyra.H:ReadinessModel().rows) do if row.who == "Lyra Distelbach" then return Cells(row) end end
  end
  lyra.H:AddTests()
  check(Mine():find("mc=done", 1, true), "the test entries attune me to Molten Core while they are there (" .. Mine() .. ")")
  lyra.H:ClearTests()
  check(Mine():find("mc=none", 1, true), "removing them takes it back (" .. Mine() .. ")")
end

local function RowOf(c, who)
  for _, row in ipairs(c.H:ReadinessModel().rows) do if row.who == who then return row end end
end

local function Three(w)
  local mira = w.join("Mira Sturmfeder", { class = "PALADIN" })
  local rika = w.join("Rika Steinbeck", { class = "WARRIOR", level = 58 })
  w.sched:advance(60)
  return mira, rika
end

Kit.section("Tick: a raid attuned before install, ticked once, shows on a guildmate's client")
do
  local w = NewWorld()
  local mira, rika = Three(w)
  check(mira.H:DeclareAttuned("mc") ~= nil, "Mira ticks Molten Core")
  w.sched:advance(120)
  local row = RowOf(rika, "Mira Sturmfeder")
  check(row and Cells(row) == "Mira Sturmfeder: mc=done ony=none>STEP_WINDSOR bwl=none>STEP_SEAL" and row.raids[1].declared,
    "Rika's table shows Mira attuned to Molten Core, marked as added by hand (" .. (row and Cells(row) or "no row") .. ")")
  local own = RowOf(mira, "Mira Sturmfeder")
  check(own and own.raids[1].state == "done", "and so does Mira's own")
  local events = rika.H:Log()
  local line = rika.H:Format(events[#events])
  check(line:find("Mira Sturmfeder", 1, true) and line:find("schon eingestimmt: |cffffd100Geschmolzener Kern|r (selbst nachgetragen)", 1, true),
    "Rika's chronicle has the line (" .. line .. ")")
  check(mira.H:DeclareAttuned("mc") == nil, "a second tick for the same raid adds nothing")
  Milestone(mira, "Mira Sturmfeder", 7761, mira.env.time() - 60)
  check(mira.H:DeclareAttuned("bwl") == nil, "nor does a tick for a raid the quests already attuned")
  check(mira.H:DeclareAttuned("naxx") == nil, "nor one for a raid not in the table")
  check(#mira.errors == 0 and #rika.errors == 0, "no Lua errors (" .. tostring(mira.errors[1] or rika.errors[1]) .. ")")
end

Kit.section("Tick cost: one guild message per raid, ever")
do
  local w = NewWorld()
  local mira = Three(w)
  local before = #w.bus.log
  for _, raid in ipairs({ "mc", "ony", "bwl", "mc", "ony" }) do
    mira.H:DeclareAttuned(raid)
    w.sched:advance(5)
  end
  w.sched:advance(3600)
  local ticks = {}
  for i = before + 1, #w.bus.log do
    local x = w.bus.log[i]
    if x.sender == "Mira Sturmfeder" and x.msg:find("^H;1;a;") then ticks[#ticks + 1] = x end
  end
  check(#ticks == 3, "three raids ticked, two repeats: three messages in an hour (" .. #ticks .. ")")
  local shape = true
  for _, x in ipairs(ticks) do shape = shape and x.msg:match("^H;1;a;%d+;%d+;Mira Sturmfeder;60;2;%l+$") ~= nil and #x.msg < 60 end
  check(shape, "each is one short record: time, sequence, name, level, class, raid (" .. tostring(ticks[1] and ticks[1].msg) .. ")")
  local C = mira.RQ.CommConst
  local cap60, most = C.BURST + 60 * C.RATE, w.bus:maxPer(60, "Mira Sturmfeder")
  check(most <= cap60, ("all of Mira's guild messages, ticks included, stay within the core's %d per minute (%d)"):format(cap60, most))
  w.sched:advance(86400)
  local later = 0
  for i = before + 1, #w.bus.log do
    if w.bus.log[i].sender == "Mira Sturmfeder" and w.bus.log[i].msg:find("^H;1;a;") then later = later + 1 end
  end
  check(later == 3, "nothing is resent a day later (" .. later .. ")")
end

Kit.section("Tick catch-up: a guildmate who was offline gets the tick from the others")
do
  local w = NewWorld()
  local mira = Three(w)
  mira.H:DeclareAttuned("ony")
  w.sched:advance(120)
  local bodo = w.join("Bodo Kesselring", { class = "PALADIN", level = 56 })
  w.sched:advance(600)
  local row = RowOf(bodo, "Mira Sturmfeder")
  check(row and row.raids[2].state == "done" and row.raids[2].declared,
    "Bodo logs in later and his table shows Mira's tick (" .. (row and Cells(row) or "no row") .. ")")
  check(w.sent("^H;1;Ra;") >= 1, "it came as a catch-up relay")
end

Kit.section("Tick: the newspaper leaves ticks out, the chronicle keeps them")
do
  local w = NewWorld()
  local mira = Three(w)
  mira.H:DeclareAttuned("mc")
  w.sched:advance(10)
  local list = mira.H:LogLines()
  check(list[#list] and list[#list].k == "attune", "the chronicle lists the tick")
  check(#mira.H:Issues() == 0, "the paper has no issue made of a tick alone (" .. #mira.H:Issues() .. ")")
end

local Layout = dofile(DEV .. "layout.lua")

local function ViewWorld(locale, level)
  local w = NewWorld()
  local lyra = w.join("Lyra Distelbach", { class = "MAGE", locale = locale, level = level, setup = function(env, c)
    Layout.Install(c)
    Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
    local fm = c.frameMethods
    fm.Disable = function(s) s._disabled = true end
    fm.Enable = function(s) s._disabled = false end
    fm.IsEnabled = function(s) return not s._disabled end
    fm.SetTextColor = function(s, r, g, b) s._ink = { r, g, b } end
    fm.Hide = function(s) s._off = true; Kit.FrameMethods.Hide(s) end
    fm.Show = function(s) s._off = nil; Kit.FrameMethods.Show(s) end
    fm.SetShown = function(s, on) if on then s:Show() else s:Hide() end end
  end })
  Guild(w, lyra)
  return w, lyra
end

local PAGE_W, PAGE_H = 632, 480

local function Page(c)
  c.RQ:ShowModulePage("Highlights")
  local page = c.env.RavenquillExpeditionOverview.optView.pages.Highlights
  Layout.Pin(page, 600, 300, PAGE_W, PAGE_H)
  return page
end

local function Click(b) b._scripts.OnClick(b) end

local function Plain(s)
  return (tostring(s or ""):gsub("|T[^|]*ReadyCheck%-Ready[^|]*|t", "✔"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Under(region, root)
  while region and region ~= root do
    if region._off then return false end
    region = region._parent
  end
  return region == root
end

local function TableRows(view)
  local rows, at = {}, {}
  for i, d in ipairs(view.list.data or {}) do at[d] = i end
  for _, r in ipairs(view.list.content._children) do
    if r._shown and r.row and at[r.row] then
      local line = { Plain(r.name._text), Plain(r.level._text) }
      for _, cell in ipairs(r.cells) do line[#line + 1] = Plain(cell._text) end
      rows[at[r.row]] = table.concat(line, " | ")
    end
  end
  return rows
end

local function Heads(view)
  local out = {}
  for i, b in ipairs(view.heads) do out[i] = Plain(b.label._text) .. (b.underline._shown and "*" or "") end
  return table.concat(out, " | ")
end

local function PlaceRows(view)
  local r, at = Layout.Rect(view.list), {}
  for i, d in ipairs(view.list.data or {}) do at[d] = i end
  for _, row in ipairs(view.list.content._children) do
    local i = row._shown and at[row.row]
    if i then Layout.Pin(row, r.left, r.top - i * 20, r.width, 20) end
  end
end

local function OnScreen(c, page)
  local list, out = Layout.Rect(page.raid.list), {}
  for _, fs in ipairs(c.regions) do
    if fs._type == "FontString" and (fs._text or "") ~= "" and Under(fs, page.raid) then
      local r = Layout.Rect(fs)
      local scrolledAway = r and Under(fs, page.raid.list) and r.top <= list.bottom + 0.5
      if not scrolledAway then out[#out + 1] = fs end
    end
  end
  return out
end

local function Overlap(a, b)
  return a.left < b.right - 0.5 and b.left < a.right - 0.5 and a.bottom < b.top - 0.5 and b.bottom < a.top - 0.5
end

local function Misfits(c, page)
  local pr, texts, out = Layout.Rect(page), OnScreen(c, page), {}
  for i, fs in ipairs(texts) do
    local r = Layout.Rect(fs)
    local bad = not (r and Layout.Inside(pr, r)) or Layout.Truncated(fs)
    for j = i + 1, #texts do bad = bad or (r and Overlap(r, Layout.Rect(texts[j]))) end
    if bad then out[#out + 1] = Plain(fs._text):sub(1, 40) end
  end
  return out, #texts
end

local function Below(upper, lower)
  local a, b = Layout.Rect(upper), Layout.Rect(lower)
  return a and b and a.bottom >= b.top - 0.5
end

Kit.section("View: the Highlights page switches between Chronik and Raidbereitschaft, the header buttons stay")
do
  local _, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  local opt = lyra.env.RavenquillExpeditionOverview.optView
  check(Plain(page.links[1].label._text) == "Chronik" and Plain(page.links[2].label._text) == "Raidbereitschaft"
    and not page.raid._shown and page.links[1].underline._shown and not page.links[2].underline._shown,
    "the page opens on the Chronik, both views offered")
  Click(page.links[2])
  check(page.raid._shown and not page.msg._shown and not page.onlyHL._shown and page.links[2].underline._shown
    and not page.links[1].underline._shown, "Raidbereitschaft swaps the log for the table")
  check(opt.openWindow._shown and opt.openWindow:GetText() == "Zeitung öffnen" and opt.gear:GetText() == "Einstellungen",
    "the header keeps 'Zeitung öffnen' and 'Einstellungen'")
  Click(page.links[1])
  check(page.msg._shown and page.onlyHL._shown and not page.raid._shown, "Chronik brings the log back")
  check(#lyra.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1]) .. ")")
end

local TABLE_DE = {
  "Mira Sturmfeder | 60 | ✔ | ✔ | 1 von 2",
  "Rika Steinbeck | 58 | ✔ | 2 von 3 | –",
  "Tamo Eichengrund | 57 | – | ✔ | –",
  "Lyra Distelbach | 60 | – | – | –",
  "Bodo Kesselring | 56 | – | – | –",
}

Kit.section("View: the table and the summary read as the guild's readiness, and every text fits (deDE)")
do
  local _, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  Click(page.links[2])
  local view = page.raid
  PlaceRows(view)
  local rows = TableRows(view)
  for i = 1, math.max(#rows, #TABLE_DE) do check(rows[i] == TABLE_DE[i], ("row %d: %s"):format(i, tostring(rows[i]))) end
  check(Heads(view) == "Gesch. Kern* | Onyxia | Pechschwingen", "the raid columns, Molten Core summed up (" .. Heads(view) .. ")")
  check(Plain(view.hidden._text) == "Nicht gelistet: 1 unter Stufe 55 · 1 ohne Ravenquill", "the footnote: " .. Plain(view.hidden._text))
  check(view.head._text == "Bereit für den Gildenraid: Geschmolzener Kern" and view.bar.text._text == "2 eingestimmt · 0 fast",
    "summary: " .. tostring(view.head._text) .. " / " .. tostring(view.bar.text._text))
  local missing = Plain(view.missing._text)
  check(missing == "Tamo Eichengrund fehlt noch: Kernfragment aus den Schwarzfelstiefen.\n"
    .. "Lyra Distelbach fehlt noch: Kernfragment aus den Schwarzfelstiefen.\n"
    .. "Bodo Kesselring fehlt noch: Kernfragment aus den Schwarzfelstiefen.", "each missing member with the next step: " .. missing)
  check(view.bar.done._shown and not view.bar.almost._shown and math.abs(view.bar.done._w - 360 * 2 / 5) < 0.01,
    "the bar fills two fifths green, nothing amber")
  local misfits, seen = Misfits(lyra, page)
  check(#misfits == 0 and seen >= 39, ("all %d texts lie inside the page, none cut or overlapping (%s)"):format(seen, table.concat(misfits, " / ")))
  check(Below(view.missing, view.tickLabel), "the missing lines end above the tick row")
  check(#lyra.errors == 0, "no Lua errors (" .. tostring(lyra.errors[1]) .. ")")
end

Kit.section("View: the same page in English fits too")
do
  local w, lyra = ViewWorld("enUS")
  for i = 1, 6 do
    local name = "Neu Mitglied" .. string.char(64 + i)
    w.bus:member(name, "ROGUE", 60, true)
    lyra.RQ:NotePeer(name)
  end
  lyra.fire("GUILD_ROSTER_UPDATE")
  local page = Page(lyra)
  Click(page.links[2])
  local view = page.raid
  PlaceRows(view)
  check(Plain(page.links[1].label._text) == "Chronicle" and Plain(page.links[2].label._text) == "Raid readiness"
    and Heads(view) == "Molten Core* | Onyxia | Blackwing", "links and columns in English (" .. Heads(view) .. ")")
  check(view.head._text == "Ready for the guild raid: Molten Core" and view.bar.text._text == "2 attuned · 0 almost",
    "summary: " .. tostring(view.head._text) .. " / " .. tostring(view.bar.text._text))
  local missing = Plain(view.missing._text)
  check(missing:find("^Rika") == nil and missing:find("still needs a Core Fragment from Blackrock Depths.", 1, true)
    and missing:find("\n… and 6 more.$"), "three missing lines, the rest counted: " .. missing)
  check(#view.list.data == 11 and view.list.viewH == 8 * 20, "eleven rows scroll in a list eight rows high")
  local misfits, seen = Misfits(lyra, page)
  check(#misfits == 0 and seen >= 54, ("all %d texts lie inside the page, none cut or overlapping (%s)"):format(seen, table.concat(misfits, " / ")))
  check(Below(view.missing, view.tickLabel), "the missing lines end above the tick row")
end

Kit.section("View: a raid header sums up that raid, and the choice is kept")
do
  local _, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  Click(page.links[2])
  local view = page.raid
  Click(view.heads[2])
  check(Heads(view) == "Gesch. Kern | Onyxia* | Pechschwingen" and view.head._text == "Bereit für den Gildenraid: Onyxias Hort"
    and view.bar.text._text == "2 eingestimmt · 1 fast", "Onyxia: " .. tostring(view.head._text) .. " / " .. tostring(view.bar.text._text))
  check(Plain(view.missing._text):find("^Rika Steinbeck fehlt noch: Drachenfeueramulett von General Drakkisath %(Obere Schwarzfelsspitze%)%.\n"),
    "the almost-attuned Rika comes first: " .. Plain(view.missing._text))
  check(view.bar.done._shown and view.bar.almost._shown and math.abs(view.bar.almost._w - 360 / 5) < 0.01,
    "one fifth of the bar is amber for her")
  Click(page.links[1])
  Click(page.links[2])
  check(view.head._text == "Bereit für den Gildenraid: Onyxias Hort", "back on the view, Onyxia is still summed up")
end

Kit.section("View: ticking a box sends the tick once and leaves it checked and locked")
do
  local w, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  Click(page.links[2])
  local view = page.raid
  local box = view.ticks[3]
  check(box._shown and view.tickLabel._text == "Schon vorher eingestimmt:" and box.text._text == "Pechschwingenhort"
    and not box._checked and box:IsEnabled(), "a level 60 sees an open box per raid")
  box:SetChecked(true)
  Click(box)
  check(box._checked and not box:IsEnabled(), "after the click the box stays checked and locked")
  PlaceRows(view)
  check(TableRows(view)[3] == "Lyra Distelbach | 60 | – | – | ✔", "my row shows the tick (" .. tostring(TableRows(view)[3]) .. ")")
  w.sched:advance(120)
  check(w.sent("^H;1;a;%d+;%d+;Lyra Distelbach;60;7;bwl$", "Lyra Distelbach") == 1, "one guild message went out for it")
  local low = select(2, ViewWorld("deDE", 50))
  local lowPage = Page(low)
  Click(lowPage.links[2])
  check(not lowPage.raid.ticks[1]._shown and not lowPage.raid.tickLabel._shown and Plain(lowPage.raid.note._text):find("^Einstimmungen zählen ab Installation"),
    "below level 55 there is nothing to tick, only the note")
end

Kit.section("View: Raidbereitschaft on screen leaves 'new since your last look' alone")
do
  local _, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  Click(page.links[2])
  page:Hide()
  local t = lyra.env.time()
  lyra.H:Add({ k = "level", t = t, who = "Bodo Kesselring", lvl = 60, cls = "PALADIN", id = "Bodo Kesselring#" .. t .. "#77" }, "wire")
  Page(lyra)
  lyra.sched:advance(1)
  check(lyra.H:NewSinceLastLook() == 1, "the table on screen keeps the new entry new")
  Click(page.links[1])
  check(lyra.H:NewSinceLastLook() == 0, "the Chronik clears it")
end

Kit.section("View: a guildmate reaching level 55 shows up when the roster updates")
do
  local w, lyra = ViewWorld("deDE")
  local page = Page(lyra)
  Click(page.links[2])
  for _, r in ipairs(w.bus.roster) do if r.name == "Kael Wintermoor" then r.level = 55 end end
  lyra.fire("GUILD_ROSTER_UPDATE")
  PlaceRows(page.raid)
  local rows = TableRows(page.raid)
  check(#rows == 6 and rows[4] == "Kael Wintermoor | 55 | ✔ | – | –", "Kael is listed with his Molten Core attunement (" .. tostring(rows[4]) .. ")")
end

Kit.finish()
