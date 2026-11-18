local ADDON, ns = ...
local RQ = RavenquillExpedition
local Dev = {}
ns.Dev = Dev

Dev.LOG_MAX = 2000
Dev.CUT = 120
Dev.SESSIONS_MAX = 10
local SUITE_PREFIXES = { RQE1 = true, RQEMap1 = true, GCAdv1 = true }

local db
local pending = {}

local function Text(v)
  if v == nil then return nil end
  if RQ.IsSecret(v) then return "<secret>" end
  local s = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c]", " ")
  return RQ.Cut(s, Dev.CUT)
end

local function Store(e)
  local log = db.log
  log.e[log.head] = e
  log.head = log.head % log.max + 1
  if log.n < log.max then log.n = log.n + 1 end
end

function Dev.Add(cat, msg, data)
  if db and not db.on then return end
  local e = { time(), GetTime(), tostring(cat or "?"), Text(msg) or "", Text(data) }
  if db then Store(e) elseif #pending < 300 then pending[#pending + 1] = e end
end

function RQ:Trace(cat, msg, data) pcall(Dev.Add, cat, msg, data) end

function Dev.Entries()
  local out, log = {}, db and db.log
  if not log then return out end
  local start = log.n < log.max and 1 or log.head
  for i = 0, log.n - 1 do out[#out + 1] = log.e[(start - 1 + i) % log.max + 1] end
  return out
end

function Dev.Clear()
  db.log = { head = 1, n = 0, max = Dev.LOG_MAX, e = {} }
end

if DEFAULT_CHAT_FRAME and hooksecurefunc then
  hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text)
    pcall(function()
      if type(text) ~= "string" or RQ.IsSecret(text) then return end
      if (db and db.chatAll) or text:find("Ravenquill Expedition", 1, true) then Dev.Add("chat", text) end
    end)
  end)
end
if C_ChatInfo and C_ChatInfo.SendAddonMessage and hooksecurefunc then
  hooksecurefunc(C_ChatInfo, "SendAddonMessage", function(prefix, msg, chan)
    pcall(function()
      if RQ.Plain(prefix, "string") and SUITE_PREFIXES[prefix] then Dev.Add("wire.tx", prefix .. " " .. tostring(chan), msg) end
    end)
  end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  pcall(function()
    if event == "CHAT_MSG_ADDON" then
      if RQ.Plain(a1, "string") and SUITE_PREFIXES[a1] then
        Dev.Add("wire.rx", a1 .. " " .. tostring(Text(a4)), a2)
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      Dev.Add("event", "PLAYER_ENTERING_WORLD", "instance=" .. tostring(RQ:InInstance()))
    else
      Dev.Add("event", "PLAYER_LOGOUT")
    end
  end)
end)

local mod = RQ:NewModule("Dev", { addon = ADDON, api = 2, slash = "dev", title = "Dev tools",
  icon = "Interface\\Icons\\INV_Misc_Gear_01" })
Dev.mod = mod

function mod:OnLoad()
  db = type(RavenquillExpeditionDevDB) == "table" and RavenquillExpeditionDevDB or {}
  RavenquillExpeditionDevDB = db
  if db.on == nil then db.on = true end
  db.chatAll = db.chatAll == true
  if type(db.log) ~= "table" or type(db.log.e) ~= "table" then Dev.Clear() end
  db.log.max = Dev.LOG_MAX
  db.runs = type(db.runs) == "table" and db.runs or {}
  db.sessions = type(db.sessions) == "table" and db.sessions or {}
  Dev.db = db
  local _, build, _, iface = GetBuildInfo()
  table.insert(db.sessions, { started = time(), gt = GetTime(), build = build, interface = iface, core = RQ.version })
  while #db.sessions > Dev.SESSIONS_MAX do table.remove(db.sessions, 1) end
  for _, e in ipairs(pending) do Store(e) end
  pending = {}
  Dev.Add("session", "loaded", "core " .. tostring(RQ.version))
end

function mod:OnLogin()
  local s = db.sessions[#db.sessions]
  s.char, s.guild = RQ:PlayerKey(), RQ:GuildKey()
  s.modules = {}
  for _, name in ipairs(RQ.moduleOrder) do
    local m = RQ.modules[name]
    s.modules[name] = m.addon and RQ:AddOnVersion(m.addon) or "?"
  end
  Dev.Add("session", "login", tostring(s.char) .. " @ " .. tostring(s.guild))
  if Dev.OnLoginTests then RQ:Call(Dev.OnLoginTests, Dev) end
end

function mod:OnSlash(rest)
  local name = rest and rest:match("^%s*(%S+)")
  if not (name and Dev.tests and Dev.tests[name]) then
    local names = {}
    for _, n in ipairs(Dev.testOrder or {}) do names[#names + 1] = n end
    RQ.Print("Dev", "/rq dev <test>: " .. table.concat(names, ", "))
    return
  end
  Dev:Run({ name }, "slash-" .. name .. "-" .. time(), function(run)
    RQ.Print("Dev", ("|cffffff00%s: %s. Type /reload to save the results.|r"):format(name, run.summary or "?"))
  end)
end

function mod:OverviewStatus()
  return ("logging %s, %d entries"):format(db and db.on and "on" or "off", db and db.log.n or 0)
end

mod.options = {
  { type = "header", label = "Log" },
  { type = "toggle", label = "Log to SavedVariables", tooltip = "Traces, suite addon messages and the suite's chat lines go into RavenquillExpeditionDevDB.",
    get = function() return db and db.on or false end, set = function(v) db.on = v and true or false end },
  { type = "toggle", label = "Also log all other chat lines", tooltip = "Every chat line, including whispers and guild chat, into the log file. Off by default.",
    get = function() return db and db.chatAll or false end, set = function(v) db.chatAll = v and true or false end },
  { type = "button", label = "Clear the log", func = function() Dev.Clear() end },
  { type = "toggle", label = "Craft Advisor: verbose chat messages",
    get = function() local c = RQ:GetModule("Craft"); return c and c.verbose and true or false end,
    set = function(v) local c = RQ:GetModule("Craft"); if c then c.verbose = v and true or false end end },
  { type = "button", label = "Run all tests (then /reload to save)", func = function() if Dev.RunAll then Dev:RunAll() end end },
  { type = "text", label = "Last 50 entries", lines = function()
    local out, all = {}, Dev.Entries()
    for i = math.max(1, #all - 49), #all do
      local e = all[i]
      out[#out + 1] = ("%s %s %s %s"):format(date("%H:%M:%S", e[1]), e[3], e[4], e[5] or "")
    end
    return out
  end },
}
