-- The CraftAdvisor files its .toc loads, for the harnesses that load the addon (or parts of it) themselves. The
-- .toc is the only list: a file added there is picked up here. Groups: "UI" = UI.lua and UI/*.lua, "Core" =
-- Core.lua and Core/*.lua.
--   local Files = dofile(DEV .. "files.lua")
--   Files.list({ except = { "Sync.lua", "UI" }, from = "Data/Weights.lua" })  -- .toc order; names or groups
--   Files.group("UI")                  -- the files of one group, in .toc order
--   Files.load(list, ns[, env])        -- run each as the game does: chunk("RavenquillExpedition_CraftAdvisor", ns)
--   Files.loadUI(ns[, env])            -- the UI files; a bare ns ({ GCA = GCA }) gets ns.L from GCA.L
--   Files.source(list)                 -- the files' text, concatenated (for checks that read the code)
--   Files.ROOT                         -- the addon folder, with a trailing slash
local DEV = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", ""))
if DEV == "" then DEV = "./" end
local ROOT = DEV .. "../"
local TocFiles = dofile(ROOT .. "../RavenquillExpedition/dev/toc.lua")
local ADDON = "RavenquillExpedition_CraftAdvisor"

local F = { ROOT = ROOT }
local GROUPS = {
  UI = function(f) return f == "UI.lua" or f:find("^UI/") ~= nil end,
  Core = function(f) return f == "Core.lua" or f:find("^Core/") ~= nil end,
}

function F.all() return TocFiles(ROOT .. "../" .. ADDON) end

function F.group(name)
  local out = {}
  for _, f in ipairs(F.all()) do if GROUPS[name](f) then out[#out + 1] = f end end
  assert(#out > 0, "no files in group " .. name)
  return out
end

function F.list(opts)
  opts = opts or {}
  local skip = {}
  for _, x in ipairs(opts.except or {}) do skip[x] = true end
  local out, started = {}, opts.from == nil
  for _, f in ipairs(F.all()) do
    if f == opts.from then started = true end
    local skipped = skip[f]
    for g, match in pairs(GROUPS) do if skip[g] and match(f) then skipped = true end end
    if started and not skipped then out[#out + 1] = f end
  end
  assert(started, "not in the .toc: " .. tostring(opts.from))
  return out
end

function F.load(list, ns, env)
  for _, f in ipairs(list) do
    local chunk
    if env then chunk = assert(loadfile(ROOT .. f, "t", env)) else chunk = assert(loadfile(ROOT .. f)) end
    chunk(ADDON, ns)
  end
end

function F.loadUI(ns, env)
  if ns.GCA and ns.L == nil then ns.L = ns.GCA.L end
  F.load(F.group("UI"), ns, env)
end

function F.source(list)
  local parts = {}
  for i, f in ipairs(list) do
    local h = assert(io.open(ROOT .. f, "rb"))
    parts[i] = h:read("a")
    h:close()
  end
  return table.concat(parts, "\n")
end

return F
