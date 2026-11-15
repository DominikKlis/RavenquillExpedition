-- The real Ravenquill Expedition core for the CraftAdvisor harnesses that build their own WoW mock (harness.lua,
-- harness_rq.lua, uikit.lua, scorekit.lua): loads the core's .toc files into the harness's environment
-- (the global one by default) and returns fire(event, ...) for the frames the core and the addon register events
-- on. Multi-client tests use RavenquillExpedition/dev/testkit.lua instead.
--   local K = dofile(DEV .. "corekit.lua")(env)   -- before the addon's files are loaded
--   ... load the addon ...
--   K.done()                                     -- stop watching new frames (UI frames don't register events)
--   K.fire("PLAYER_LOGIN")                       -- the first ADDON_LOADED also loads the core (its own event first)
--   K.RQ                                         -- the core (RavenquillExpedition)
local DEV = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", ""))
local ADDONS = DEV .. "../../"
local TocFiles = dofile(ADDONS .. "RavenquillExpedition/dev/toc.lua")

return function(env)
  env = env or _G
  local K = { frames = {} }
  if env.SlashCmdList == nil then env.SlashCmdList = {} end
  if rawget(env, "_G") == nil then rawset(env, "_G", env) end -- the core reads SavedVariables through _G[name]
  local create = env.CreateFrame
  local watching = true
  env.CreateFrame = function(...)
    local f = create(...)
    if watching and type(f) == "table" then
      local rec = { f = f, events = {} }
      K.frames[#K.frames + 1] = rec
      local reg, unreg, set = f.RegisterEvent, f.UnregisterEvent, f.SetScript
      rawset(f, "RegisterEvent", function(self, ev, ...)
        rec.events[ev] = true
        if reg then return reg(self, ev, ...) end
      end)
      rawset(f, "UnregisterEvent", function(self, ev, ...)
        rec.events[ev] = nil
        if unreg then return unreg(self, ev, ...) end
      end)
      rawset(f, "SetScript", function(self, script, fn, ...)
        if script == "OnEvent" then rec.onEvent = fn end
        if set then return set(self, script, fn, ...) end
      end)
    end
    return f
  end
  function K.done() watching = false; env.CreateFrame = create end

  local ns = {}
  for _, f in ipairs(TocFiles(ADDONS .. "RavenquillExpedition")) do
    local chunk = assert(loadfile(ADDONS .. "RavenquillExpedition/" .. f, "t", env))
    chunk("RavenquillExpedition", ns)
  end
  K.ns = ns
  K.RQ = env.RavenquillExpedition

  local coreLoaded = false
  function K.fire(ev, ...)
    if ev == "ADDON_LOADED" and not coreLoaded and ... ~= "RavenquillExpedition" then K.fire("ADDON_LOADED", "RavenquillExpedition") end
    if ev == "ADDON_LOADED" and ... == "RavenquillExpedition" then coreLoaded = true end
    for _, rec in ipairs(K.frames) do
      if rec.events[ev] and rec.onEvent then rec.onEvent(rec.f, ev, ...) end
    end
  end
  return K
end
