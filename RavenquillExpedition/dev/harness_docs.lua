-- docs/module-api.md and the code agree: every `RQ:Name` / `RQ.Name`, `mod:Name` and `ch:Name` the document names
-- exists on the core, on a module, or on a schema channel. A renamed or removed function fails here.
-- Run: lua RavenquillExpedition/dev/harness_docs.lua
local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "testkit.lua")
local check = Kit.check

local f = assert(io.open(Kit.ADDONS .. "docs/module-api.md", "rb"))
local doc = f:read("*a")
f:close()

local sched, bus = Kit.Setup()
local c = Kit.Client(sched, bus, "Anna Stone")
c.login()
local RQ = c.RQ
local mod = RQ:NewModule("DocProbe", { addon = "DocProbe" })
local ch = mod:NewChannel({ tag = "DP", version = 1 })
local raw = mod:NewRawChannel({ prefix = "DocProbe", lane = "event" })

local function names(pattern)
  local seen, out = {}, {}
  for name in doc:gmatch(pattern) do
    if not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local missing = {}
local function want(obj, label, list)
  for _, n in ipairs(list) do
    if obj[n] == nil then missing[#missing + 1] = label .. n end
  end
  return #list
end
local nCore = want(RQ, "RQ.", names("RQ[:.]([%a_][%w_]*)"))
local nWire = want(RQ.Wire, "RQ.Wire.", names("RQ%.Wire%.([%a_][%w_]*)"))
-- callbacks the module defines itself (the doc lists them as such) are not methods the core provides
local CALLBACKS = { OnLoad = true, OnLogin = true, OnGuildChanged = true, OnSlash = true, Open = true, OverviewStatus = true,
  OverviewRecent = true, OnOptionChanged = true }
local modNames = {}
for _, n in ipairs(names("mod:([%a_][%w_]*)")) do if not CALLBACKS[n] then modNames[#modNames + 1] = n end end
local nMod = want(mod, "mod:", modNames)
local nCh = want(ch, "ch:", names("ch:([%a_][%w_]*)"))
-- the raw channel's methods are listed in Comm.lua's header; check them against the object too
for _, n in ipairs({ "OnMessage", "OnEcho", "Send", "TrySend", "SendNow", "SendRecord", "Cancel", "Status" }) do
  if raw[n] == nil then missing[#missing + 1] = "raw:" .. n end
end
check(nCore > 20 and nMod > 8 and nCh >= 4, ("the document names %d core, %d Wire, %d module and %d channel functions"):format(nCore, nWire, nMod, nCh))
check(not missing[1], "every one of them exists" .. (missing[1] and (": missing " .. table.concat(missing, ", ")) or ""))
Kit.finish()
