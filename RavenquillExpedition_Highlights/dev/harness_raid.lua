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

Kit.finish()
