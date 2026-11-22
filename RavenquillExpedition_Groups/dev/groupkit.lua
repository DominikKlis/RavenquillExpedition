local HERE = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", ""))
local Kit = dofile(HERE .. "../../RavenquillExpedition/dev/testkit.lua")

local GK = { Kit = Kit, ADDON = "RavenquillExpedition_Groups" }

local CLASS_COLORS = {
  ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
}

local function Stubs(opts)
  return function(env, c)
    c.whispers, c.invites, c.tells, c.menus = {}, {}, {}, {}
    env.RAID_CLASS_COLORS = CLASS_COLORS
    env.SendChatMessage = function(msg, kind, _, target)
      c.whispers[#c.whispers + 1] = { msg = msg, kind = kind, target = target }
    end
    env.C_PartyInfo = { InviteUnit = function(name) c.invites[#c.invites + 1] = name end }
    env.ChatFrameUtil = { SendTell = function(name) c.tells[#c.tells + 1] = name end }
    env.MenuUtil = { CreateContextMenu = function(owner, gen) c.menus[#c.menus + 1] = { owner = owner, gen = gen } end }
    if opts.setup then opts.setup(env, c) end
  end
end

function GK.Client(sched, bus, name, opts)
  opts = opts or {}
  local c = Kit.Client(sched, bus, name, { locale = opts.locale or "deDE", class = opts.class, level = opts.level,
    random = opts.random, addons = { GK.ADDON }, setup = Stubs(opts) })
  c.G = c.ns[GK.ADDON].G
  return c
end

function GK.Login(sched, c, settle)
  c.login()
  sched:advance(settle or 5)
  return c
end

function GK.Click(button, ...)
  local fn = rawget(button, "_scripts").OnClick
  return fn(button, ...)
end

function GK.Shown(f) return rawget(f, "_shown") == true end

return GK
