local Kit = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "../../RavenquillExpedition/dev/testkit.lua")
local check, section = Kit.check, Kit.section

local SECRET = setmetatable({}, { __tostring = function() error("used a secret") end })
local reloads = 0
local sched = Kit.Scheduler({ start = 100 })
local bus = Kit.Bus(sched)
local me = Kit.Client(sched, bus, "Me Smith", { guild = "Die Gilde", realm = "Forever", epoch = 1800000000,
  setup = function(env)
    env.issecretvalue = function(v) return rawequal(v, SECRET) end
    env.RAID_CLASS_COLORS = {}
    env.C_AddOns = { GetAddOnMetadata = function(a, f) if f == "Version" then return a == "RavenquillExpedition" and "1.2.3" or "dev" end end,
      IsAddOnLoaded = function() return true end, GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end }
    env.ReloadUI = function() reloads = reloads + 1 end
  end })
local env, RQ, fire = me.env, me.RQ, me.fire
RQ:Trace("early", "before the Dev addon loaded")
local devNS = me.loadAddon("RavenquillExpedition_Dev")
env.RQDevInbox = nil
local Dev = devNS.Dev
Dev.LOG_MAX = 50
RQ:Trace("pre", "traced before ADDON_LOADED")
env.RavenquillExpeditionDevDB = nil
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Dev")

section("Log")
check(RQ:GetModule("Dev") == Dev.mod and Dev.mod.api == 2, "Dev is the core's module \"Dev\" and declares core API 2")
local db = env.RavenquillExpeditionDevDB
check(type(db) == "table" and db.on == true, "SavedVariables created, logging on by default")
local all = Dev.Entries()
check(all[1] and all[1][3] == "pre", "an entry traced before the SavedVariables were ready is kept")
check(db.sessions[1] and db.sessions[1].core == "1.2.3", "session header with the core version from the .toc")
RQ:Trace("x", string.rep("é", 200), SECRET)
local e = Dev.Entries()[#Dev.Entries()]
check(#e[4] <= 120 and e[5] == "<secret>", "message cut to 120 bytes, a secret value is never stored")
for i = 1, 120 do RQ:Trace("fill", "n" .. i) end
all = Dev.Entries()
check(#all == 50 and all[#all][4] == "n120" and all[1][4] == "n71", "ring keeps the newest 50, oldest first")
local nBefore = #Dev.Entries()
env.print("[Cara Moss] whispers: meet me at the bank")
check(#Dev.Entries() == nBefore, "other chat lines (whispers) are not logged by default")
RQ.Print("Map", "hello chat")
check(Dev.Entries()[#Dev.Entries()][3] == "chat", "the suite's own chat lines are captured")
db.chatAll = true
env.print("[Cara Moss] whispers: again")
check(Dev.Entries()[#Dev.Entries()][4]:find("again", 1, true) ~= nil, "with the switch on, every chat line is")
db.chatAll = false
db.on = false
RQ:Trace("off", "x")
check(Dev.Entries()[#Dev.Entries()][3] ~= "off", "nothing logged while logging is off")
db.on = true
local okErr = pcall(RQ.Trace, RQ, "bad", setmetatable({}, { __tostring = function() error("boom") end }))
check(okErr, "a value that can't be printed doesn't break the caller")

section("Login and core traces")
fire("PLAYER_LOGIN")
check(db.sessions[#db.sessions].char == "Me Smith", "session gets the character at login")
local hch = Dev.mod:NewChannel({ tag = "HX", version = 1 })
hch:Define("v", { fields = { { "n", "int", 0, 99 } } })
hch:Send("v", { n = 1 })
sched:advance(10)
local cats = {}
for _, x in ipairs(Dev.Entries()) do cats[x[3]] = (cats[x[3]] or 0) + 1 end
check(cats["comm.tx"] and cats["comm.echo"] and cats["wire.tx"] and cats["wire.rx"], "core lane send, echo and wire tx/rx are logged")

section("Test runner")
Dev.tests, Dev.testOrder = {}, {}
Dev:Register("t.pass", function(t) t:ok(true, "fine") t:done() end)
Dev:Register("t.fail", function(t) t:ok(false, "broken") t:done() end)
Dev:Register("t.error", function() error("kaputt") end)
Dev:Register("t.timeout", function() end, 3)
Dev:Register("t.async", function(t) t:after(2, function() t:ok(true, "later") t:done() end) end)
Dev:Register("other", function(t) t:done() end)
local finished
Dev:Run({ "t" }, "r1", function(run) finished = run end)
sched:advance(30)
local st = {}
for _, r in ipairs(finished and finished.results or {}) do st[r.name] = r.status end
check(finished and #finished.results == 5, "selecting 't' runs the 5 tests named t.*")
check(st["t.pass"] == "pass" and st["t.fail"] == "fail" and st["t.error"] == "error" and st["t.timeout"] == "timeout"
  and st["t.async"] == "pass", "pass / fail / error / timeout / async results")
check(finished and finished.summary == "2/5 passed", "summary: " .. tostring(finished and finished.summary))

section("Inbox")
env.RQDevInbox = { id = "abc", run = { "other" } }
db.lastId = nil
Dev:OnLoginTests()
sched:advance(30)
check(db.lastId == "abc" and reloads == 0 and me.printed[#me.printed].text:find("/reload", 1, true), "inbox run once; no ReloadUI (protected), the chat asks for /reload")
local runsBefore = #db.runs
Dev:OnLoginTests()
sched:advance(30)
check(#db.runs == runsBefore, "same id after the reload: nothing runs again")
local last = db.runs[#db.runs]
check(last.id == "abc" and last.summary == "1/1 passed", "the inbox run is saved under its id")

section("Shipped tests in the mock")
Dev.tests, Dev.testOrder = {}, {}
Kit.loadchunk(Kit.ADDONS .. "RavenquillExpedition_Dev/Tests.lua", env)("RavenquillExpedition_Dev", devNS)
Dev:Run({ "comm.echo", "env.info" }, "r2", function(run) finished = run end)
sched:advance(200)
st = {}
for _, r in ipairs(finished.results) do st[r.name] = r.status end
check(st["comm.echo"] == "pass", "comm.echo passes with a guild echo: " .. tostring(st["comm.echo"]))
check(st["env.info"] == "pass (no checks)", "env.info only notes")
do
  local config = { files = {} }
  local chunk = loadfile(Kit.ADDONS .. ".luacheckrc", "t", config)
  if chunk then chunk() end
  local want, have = {}, {}
  for _, name in ipairs(config.read_globals or {}) do want[name] = true end
  for _, name in ipairs(Dev.GAME_GLOBALS) do have[name] = true end
  local drift = {}
  for name in pairs(want) do if not have[name] then drift[#drift + 1] = "+" .. name end end
  for name in pairs(have) do if not want[name] then drift[#drift + 1] = "-" .. name end end
  table.sort(drift)
  check(next(want) ~= nil and #drift == 0,
    "env.globals checks exactly the read_globals of .luacheckrc: " .. (#drift > 0 and table.concat(drift, " ") or "in step"))
end
section("Craft Advisor reset")
do
  local forgot, realGet = 0, RQ.GetModule
  local craft = { ForgetStoredGear = function() forgot = forgot + 1 end }
  RQ.GetModule = function(self, name) if name == "Craft" then return craft end return realGet(self, name) end
  local reset
  for _, o in ipairs(Dev.mod.options) do if o.label == "Craft Advisor: forget stored gear" then reset = o end end
  check(reset and reset.type == "button" and reset.confirm == RQ.OverviewL.CONFIRM,
    "the dev tools offer the Craft Advisor reset, behind a second click")
  if reset then reset.func() end
  RQ.GetModule = function(self, name) if name == "Craft" then return nil end return realGet(self, name) end
  if reset then reset.func() end
  RQ.GetModule = realGet
  check(forgot == 1, "it forgets the stored gear once, and does nothing without the Craft Advisor")
end

section("Suite diagnostics")
do
  local diag
  for _, o in ipairs(Dev.mod.options) do if o.label == "Diagnostics (whole suite)" then diag = o end end
  local text = diag and diag.type == "text" and table.concat(diag.lines(), " | ") or ""
  check(text:find("Ravenquill Expedition v", 1, true) and text:find("== minimap button", 1, true),
    "the dev tools show the whole suite's diagnostics, now that the overview has no button for it")
end

check(#me.errors == 0, "no Lua errors (" .. #me.errors .. ")" .. (me.errors[1] and (": " .. tostring(me.errors[1])) or ""))

Kit.finish()
