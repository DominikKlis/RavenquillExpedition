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

Kit.finish()
