unpack = table.unpack
local ADDONS = (arg[0]:gsub("[^/\\]*$", "")) .. "../../"
local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1; io.write("  ok   ", what, "\n") else fail = fail + 1; io.write("  FAIL ", what, "\n") end
end

local now, BASE = 100, 1800000000
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
function GetServerTime() return BASE + math.floor(now) end
time = function() return BASE + math.floor(now) end
date = os.date
local errors = {}
function geterrorhandler() return function(msg) errors[#errors + 1] = msg end end
function debugstack() return "" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SECRET = setmetatable({}, { __tostring = function() error("used a secret") end })
function issecretvalue(v) return rawequal(v, SECRET) end
local frames = {}
local function obj()
  return setmetatable({}, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "SetScript" then return function(s, ev, fn) local sc = rawget(s, "_scripts") or {}; rawset(s, "_scripts", sc); sc[ev] = fn end end
    if k == "RegisterEvent" then return function(s, ev) local e = rawget(s, "_ev") or {}; rawset(s, "_ev", e); e[ev] = true end end
    if k == "IsShown" then return function(s) return rawget(s, "_shown") end end
    if k == "Show" then return function(s) rawset(s, "_shown", true) end end
    if k == "Hide" then return function(s) rawset(s, "_shown", false) end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return obj() end end
    return function() end
  end })
end
function CreateFrame() local o = obj(); frames[#frames + 1] = o; return o end
local function fire(event, ...)
  for _, f in ipairs(frames) do
    local ev, sc = rawget(f, "_ev"), rawget(f, "_scripts")
    if ev and ev[event] and sc and sc.OnEvent then sc.OnEvent(f, event, ...) end
  end
end
UIParent, GameTooltip = obj(), obj()
UISpecialFrames, SlashCmdList, RAID_CLASS_COLORS = {}, {}, {}
local chatLines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chatLines[#chatLines + 1] = text end }
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
  DEFAULT_CHAT_FRAME:AddMessage(table.concat(t, " "))
end
function GetBuildInfo() return "1.60.1", "70938", "", 16001 end
function GetLocale() return "enUS" end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function UnitNameUnmodified(u) if u == "player" then return "Me", "Smith" end end
UnitName = UnitNameUnmodified
function Ambiguate(n) return n end
function GetGuildInfo() return "Die Gilde" end
function GetNormalizedRealmName() return "Forever" end
function GetRealmName() return "Forever" end
function IsInGuild() return true end
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
function GetNumGuildMembers() return 0 end
C_GuildInfo = { GuildRoster = function() end }
C_AddOns = { GetAddOnMetadata = function(a, f) if f == "Version" then return a == "RavenquillExpedition" and "1.2.3" or "dev" end end,
  IsAddOnLoaded = function() return true end, GetAddOnInfo = function(n) return n, nil, nil, false, "MISSING" end }
local echo = true
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, chan)
    if echo then C_Timer.After(1, function() fire("CHAT_MSG_ADDON", prefix, msg, chan, "Me Smith-Forever") end) end
    return 0
  end,
}
function hooksecurefunc(tbl, name, post)
  if type(tbl) == "string" then tbl, name, post = _G, tbl, name end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
end
local reloads = 0
function ReloadUI() reloads = reloads + 1 end

local function load(addon, file, ns) assert(loadfile(ADDONS .. addon .. "/" .. file))(addon, ns) end
local coreNS, devNS = {}, {}
for _, f in ipairs(dofile(ADDONS .. "RavenquillExpedition/dev/toc.lua")(ADDONS .. "RavenquillExpedition")) do load("RavenquillExpedition", f, coreNS) end
local RQ = RavenquillExpedition
RQ:Trace("early", "before the Dev addon loaded")
for _, f in ipairs({ "Inbox.lua", "Log.lua", "Test.lua", "Tests.lua" }) do load("RavenquillExpedition_Dev", f, devNS) end
RQDevInbox = nil
local Dev = devNS.Dev
Dev.LOG_MAX = 50
RQ:Trace("pre", "traced before ADDON_LOADED")
RavenquillExpeditionDevDB = nil
fire("ADDON_LOADED", "RavenquillExpedition")
fire("ADDON_LOADED", "RavenquillExpedition_Dev")

print("== Log")
local db = RavenquillExpeditionDevDB
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
print("[Cara Moss] whispers: meet me at the bank")
check(#Dev.Entries() == nBefore, "other chat lines (whispers) are not logged by default")
RQ.Print("Map", "hello chat")
check(Dev.Entries()[#Dev.Entries()][3] == "chat", "the suite's own chat lines are captured")
db.chatAll = true
print("[Cara Moss] whispers: again")
check(Dev.Entries()[#Dev.Entries()][4]:find("again", 1, true) ~= nil, "with the switch on, every chat line is")
db.chatAll = false
db.on = false
RQ:Trace("off", "x")
check(Dev.Entries()[#Dev.Entries()][3] ~= "off", "nothing logged while logging is off")
db.on = true
local okErr = pcall(RQ.Trace, RQ, "bad", setmetatable({}, { __tostring = function() error("boom") end }))
check(okErr, "a value that can't be printed doesn't break the caller")

print("== Login and core traces")
fire("PLAYER_LOGIN")
check(db.sessions[#db.sessions].char == "Me Smith", "session gets the character at login")
local hch = Dev.mod:NewChannel({ tag = "HX", version = 1 })
hch:Define("v", { fields = { { "n", "int", 0, 99 } } })
hch:Send("v", { n = 1 })
advance(10)
local cats = {}
for _, x in ipairs(Dev.Entries()) do cats[x[3]] = (cats[x[3]] or 0) + 1 end
check(cats["comm.tx"] and cats["comm.echo"] and cats["wire.tx"] and cats["wire.rx"], "core lane send, echo and wire tx/rx are logged")

print("== Test runner")
Dev.tests, Dev.testOrder = {}, {}
Dev:Register("t.pass", function(t) t:ok(true, "fine") t:done() end)
Dev:Register("t.fail", function(t) t:ok(false, "broken") t:done() end)
Dev:Register("t.error", function() error("kaputt") end)
Dev:Register("t.timeout", function() end, 3)
Dev:Register("t.async", function(t) t:after(2, function() t:ok(true, "later") t:done() end) end)
Dev:Register("other", function(t) t:done() end)
local finished
Dev:Run({ "t" }, "r1", function(run) finished = run end)
advance(30)
local st = {}
for _, r in ipairs(finished and finished.results or {}) do st[r.name] = r.status end
check(finished and #finished.results == 5, "selecting 't' runs the 5 tests named t.*")
check(st["t.pass"] == "pass" and st["t.fail"] == "fail" and st["t.error"] == "error" and st["t.timeout"] == "timeout"
  and st["t.async"] == "pass", "pass / fail / error / timeout / async results")
check(finished and finished.summary == "2/5 passed", "summary: " .. tostring(finished and finished.summary))

print("== Inbox")
RQDevInbox = { id = "abc", run = { "other" } }
db.lastId = nil
Dev:OnLoginTests()
advance(30)
check(db.lastId == "abc" and reloads == 0 and chatLines[#chatLines]:find("/reload", 1, true), "inbox run once; no ReloadUI (protected), the chat asks for /reload")
local runsBefore = #db.runs
Dev:OnLoginTests()
advance(30)
check(#db.runs == runsBefore, "same id after the reload: nothing runs again")
local last = db.runs[#db.runs]
check(last.id == "abc" and last.summary == "1/1 passed", "the inbox run is saved under its id")

print("== Shipped tests in the mock")
Dev.tests, Dev.testOrder = {}, {}
load("RavenquillExpedition_Dev", "Tests.lua", devNS)
Dev:Run({ "comm.echo", "env.info" }, "r2", function(run) finished = run end)
advance(200)
st = {}
for _, r in ipairs(finished.results) do st[r.name] = r.status end
check(st["comm.echo"] == "pass", "comm.echo passes with a guild echo: " .. tostring(st["comm.echo"]))
check(st["env.info"] == "pass (no checks)", "env.info only notes")
check(#errors == 0, "no Lua errors (" .. #errors .. ")" .. (errors[1] and (": " .. tostring(errors[1])) or ""))

io.write(("%d passed, %d failed, 0 skipped\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
