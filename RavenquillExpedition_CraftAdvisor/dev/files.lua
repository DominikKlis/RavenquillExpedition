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

function F.kitFiles(list)
  local out = {}
  for i, f in ipairs(list) do out[i] = { ROOT .. f, ADDON } end
  return out
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
