local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local Kit = dofile(DEV .. "../../RavenquillExpedition/dev/testkit.lua")
local NK = { Kit = Kit, HL = "RavenquillExpedition_Highlights", Layout = dofile(DEV .. "layout.lua") }

function NK.At(day, hour, min) return os.time({ year = 2026, month = 11, day = day, hour = hour, min = min or 0, sec = 0 }) end
NK.START = 1000
NK.NOW = NK.At(20, 21, 30)

NK.ITEMS = {
  [5001] = { name = "Klinge der Morgenröte", q = 4, il = 50, loc = "INVTYPE_WEAPON", icon = 135274 },
  [5002] = { name = "Ring der stillen Wasser", q = 3, il = 41, loc = "INVTYPE_FINGER", icon = 133345 },
  [5003] = { name = "Ungeladenes Schwert", q = 4, il = 52, loc = "INVTYPE_WEAPON", icon = 135275, unloaded = true },
  [5004] = { name = "Foliant der Glut", q = 3, il = 55, loc = "INVTYPE_HOLDABLE", icon = 133733 },
}
local ITEMS = NK.ITEMS

local function ItemApi(env)
  env.C_Item = {
    GetItemInfo = function(id)
      local it = ITEMS[id]
      if it and not it.unloaded then return it.name, "|cffa335ee|Hitem:" .. id .. "|h[" .. it.name .. "]|h|r", it.q, it.il end
    end,
    GetItemInfoInstant = function(id)
      local it = ITEMS[id]
      if it then return id, "Waffe", "Schwert", it.loc, it.icon end
    end,
    GetDetailedItemLevelInfo = function() end,
    RequestLoadItemDataByID = function() end,
  }
end

function NK.Stubs(env, c)
  env.RAID_CLASS_COLORS = {}
  env.Enum = { QuestTag = {} }
  ItemApi(env)
  env.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end }
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.BANK_CONTAINER = 4, 4, 6, -1
  function env.GetInventoryItemLink() end
  env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
  env.FACTION_STANDING_LABEL7, env.FACTION_STANDING_LABEL8 = "Respektvoll", "Ehrfürchtig"
  function env.CreateFrame(otype, name, parent, template)
    if template == "ButtonFrameTemplate" then error("no template in mock") end
    local f = c.newFrame(otype, name, parent, template)
    c.frames[#c.frames + 1] = f
    return f
  end
  local fm = c.frameMethods
  fm.AddMessage = function(s, m) s._lines = s._lines or {}; s._lines[#s._lines + 1] = m end
  fm.Clear = function(s) s._lines = {} end
  fm.Disable = function(s) s._disabled = true end
  fm.Enable = function(s) s._disabled = false end
  fm.IsEnabled = function(s) return not s._disabled end
end

NK.sched = Kit.Scheduler({ start = NK.START })

function NK.Client(name, locale, extra)
  local c = Kit.Client(NK.sched, nil, name, { guild = "Die Gilde", realm = "Forever", locale = locale or "deDE", class = "MAGE",
    level = 40, epoch = NK.NOW - NK.START, random = function() return 0.5 end, addons = { NK.HL },
    setup = function(env, cl)
      NK.Stubs(env, cl)
      if extra then extra(env, cl) end
    end })
  c.H = c.ns[NK.HL].H
  c.login()
  NK.sched:advance(5)
  return c
end

local seq = 0
function NK.E(k, who, t, fields)
  seq = seq + 1
  local e = { k = k, who = who, t = t, id = ("%s#%d#%d"):format(who, t, seq) }
  for key, v in pairs(fields or {}) do e[key] = v end
  return e
end

function NK.Ctx()
  return { maxLevel = 60, time = function(t) return os.date("%H:%M", t) end,
    standing = function(st) return ({ [7] = "Respektvoll", [8] = "Ehrfürchtig" })[st] end,
    item = function(id)
      local it = ITEMS[id]
      if not it then return {} end
      return { name = not it.unloaded and it.name or nil, il = not it.unloaded and it.il or nil, equipLoc = it.loc, icon = it.icon }
    end }
end

return NK
