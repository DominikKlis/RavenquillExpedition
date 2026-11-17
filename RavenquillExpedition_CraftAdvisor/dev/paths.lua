local P = {}
local dev = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
if dev == "" then dev = "./" end
P.DEV = dev
P.ROOT = dev .. "../"
P.ADDONS = dev .. "../../"
local function slash(d) return d and (d:match("[/\\]$") and d or d .. "/") end
local function exists(f) local h = io.open(f, "rb"); if h then h:close() return true end return false end
local function first(list, probe)
  for i = 1, #list do
    local d = slash(list[i])
    if d and exists(d .. probe) then return d end
  end
end
function P.SimGear(given)
  return first({ given or false, os.getenv("RQ_SIMGEAR") or false, P.ADDONS .. ".cache/simgear/", P.ADDONS }, "SimGearForever/Score.lua")
end
return P
