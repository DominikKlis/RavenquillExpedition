-- The Lua files an addon's .toc loads, in order (what the game does at login), for the offline harnesses.
--   local TocFiles = dofile(<AddOns>/RavenquillExpedition/dev/toc.lua)
--   for _, f in ipairs(TocFiles(<AddOns> .. "RavenquillExpedition")) do ... end
-- Paths come back relative to the addon folder with "/" separators; lines starting with "#" and non-.lua lines are
-- skipped.
return function(addonDir)
  local name = addonDir:gsub("[/\\]+$", ""):match("([^/\\]+)$")
  local f = assert(io.open(addonDir:gsub("[/\\]+$", "") .. "/" .. name .. ".toc", "rb"), "no .toc for " .. addonDir)
  local out = {}
  for line in f:lines() do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then out[#out + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return out
end
