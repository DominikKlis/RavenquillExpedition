-- Paths for the dev tools, found relative to the running script (no machine-specific paths).
--   local P = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "paths.lua")
--   P.ROOT       the addon folder, with a trailing slash
--   P.ADDONS     the AddOns folder (the repository root), with a trailing slash
--   P.SimGear(x) SimGear Forever's unzipped addons: x, $RQ_SIMGEAR, <repo>/.cache/simgear/, or installed next to
--                this addon; nil when none has SimGearForever/Score.lua (sections that need it then SKIP)
--   P.CraftersJournal(x)  CraftersJournal's Data folder: x, $RQ_CRAFTERSJOURNAL, or installed next to this addon
--   P.QuestieDB(x)  the QuestieDB addon folder (has QuestieDB_Forever.toc): x, $RQ_QUESTIEDB, or installed next to this addon
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
function P.CraftersJournal(given)
  return first({ given or false, os.getenv("RQ_CRAFTERSJOURNAL") or false, P.ADDONS .. "CraftersJournal/Data/" }, "Leatherworking.lua")
end
function P.QuestieDB(given)
  return first({ given or false, os.getenv("RQ_QUESTIEDB") or false, P.ADDONS .. "QuestieDB/" }, "QuestieDB_Forever.toc")
end
return P
