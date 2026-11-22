local HERE = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", ""))
local Kit = dofile(HERE .. "../../RavenquillExpedition/dev/testkit.lua")

local GK = { Kit = Kit, ADDON = "RavenquillExpedition_Groups" }

local CLASS_COLORS = {
  ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
  HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
}

local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end
GK.Copy = Copy

local function Stubs(opts)
  return function(env, c)
    c.whispers, c.invites, c.tells, c.menus = {}, {}, {}, {}
    c.frameMethods.SetEnabled = function(s, v) s._disabled = not v end
    c.frameMethods.Enable = function(s) s._disabled = false end
    c.frameMethods.Disable = function(s) s._disabled = true end
    c.frameMethods.IsEnabled = function(s) return not s._disabled end
    env.RAID_CLASS_COLORS = CLASS_COLORS
    env.SendChatMessage = function(msg, kind, _, target)
      c.whispers[#c.whispers + 1] = { msg = msg, kind = kind, target = target }
    end
    env.C_PartyInfo = { InviteUnit = function(name) c.invites[#c.invites + 1] = name end }
    env.ChatFrameUtil = { SendTell = function(name) c.tells[#c.tells + 1] = name end }
    env.MenuUtil = { CreateContextMenu = function(owner, gen) c.menus[#c.menus + 1] = { owner = owner, gen = gen } end }
    local create = env.CreateFrame
    env.CreateFrame = function(kind, ...)
      local f = create(kind, ...)
      if kind == "DropdownButton" then
        function f.SetupMenu(s, gen)
          if s.menu then s.menu:Close() end
          s._gen = gen
        end
        function f.GenerateMenu(s) if s.menu then s.menu:Close() end end
        function f.OverrideText(s, text) s._choice = text end
      end
      return f
    end
    if opts.sv then env.RavenquillExpeditionGroupsDB = Copy(opts.sv) end
    if opts.setup then opts.setup(env, c) end
  end
end

function GK.Client(sched, bus, name, opts)
  opts = opts or {}
  local c = Kit.Client(sched, bus, name, { locale = opts.locale or "deDE", class = opts.class, level = opts.level,
    random = opts.random, addons = { GK.ADDON }, setup = Stubs(opts) })
  local ns = c.ns[GK.ADDON]
  c.G, c.A, c.P, c.V, c.Sync = ns.G, ns.Activities, ns.Posts, ns.View, ns.Sync
  return c
end

function GK.Guild(members, opts)
  opts = opts or {}
  local sched, bus = Kit.Setup()
  local cs, by = {}, {}
  for i, m in ipairs(members) do
    bus:member(m[1], m[2], m[3], true, m[4])
    cs[i] = GK.Client(sched, bus, m[1], { class = m[2], level = m[3], locale = m.locale or opts.locale,
      random = Kit.Random(i * 13) })
    by[m[1]] = cs[i]
  end
  for _, c in ipairs(cs) do c.login() end
  sched:advance(opts.settle or 60)
  return sched, bus, cs, by
end

function GK.Join(sched, bus, member, opts)
  opts = opts or {}
  bus:member(member[1], member[2], member[3], true, member[4])
  bus:setOnline(member[1], true)
  local c = GK.Client(sched, bus, member[1], { class = member[2], level = member[3], sv = opts.sv,
    random = Kit.Random(opts.seed or 99), locale = opts.locale })
  c.login()
  return c
end

function GK.Leave(bus, c)
  c.online = false
  bus:setOnline(c.name, false)
end

function GK.Spec(c, activity, have, extra)
  local need = c.A.Needs(c.A.Get(activity))
  local roles = {}
  for _, role in ipairs({ "tank", "heal", "dps" }) do roles[role] = { need = need[role], have = (have or {})[role] or 0 } end
  local spec = { activity = activity, roles = roles, note = "" }
  for k, v in pairs(extra or {}) do spec[k] = v end
  return spec
end

function GK.PostOf(c, poster) return c.G:GuildStore("posts")[poster] end

function GK.Counts(p)
  if not p then return "none" end
  local r = p.roles
  return ("%d/%d %d/%d %d/%d"):format(r.tank.have, r.tank.need, r.heal.have, r.heal.need, r.dps.have, r.dps.need)
end

function GK.Wire(bus, pred)
  local out = {}
  for _, e in ipairs(bus.log) do
    if e.prefix == "RQE1" and e.msg:sub(1, 5) == "GF;1;" and (not pred or pred(e)) then out[#out + 1] = e end
  end
  return out
end

function GK.Since(t, typ, from)
  return function(e)
    return e.t >= t and (not typ or e.msg:sub(6, 6) == typ) and (not from or e.sender == from)
  end
end

function GK.Hear(c, sender, text) c.fire("CHAT_MSG_ADDON", "RQE1", text, "GUILD", sender .. "-Realm") end

function GK.Plain(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function GK.OpenPage(c)
  c.RQ:ShowModulePage("Groups")
  return c.G.page
end

function GK.Cards(c)
  local page, byData, out = c.G.page, {}, {}
  for _, f in ipairs(c.frames) do
    if f.data ~= nil and rawget(f, "_shown") then byData[f.data] = f end
  end
  for i, d in ipairs(page.list.data or {}) do out[i] = byData[d] end
  return out
end

function GK.PillTexts(card)
  local out = {}
  for _, pill in ipairs(card.pills) do
    if rawget(pill, "_shown") then out[#out + 1] = pill.text:GetText() .. " [" .. pill.style .. "]" end
  end
  return table.concat(out, ", ")
end

function GK.Menu(gen, owner)
  local entries = {}
  local root = {}
  local function add(kind, text, fn, data, isSel)
    entries[#entries + 1] = { kind = kind, text = text, fn = fn, data = data, isSel = isSel }
  end
  function root.CreateTitle(_, text) add("title", text) end
  function root.CreateButton(_, text, fn) add("button", text, fn) end
  function root.CreateRadio(_, text, isSel, fn, data) add("radio", text, fn, data, isSel) end
  gen(owner, root)
  return entries
end

function GK.Pick(entries, text)
  for _, e in ipairs(entries) do
    if e.text and GK.Plain(e.text):find(text, 1, true) == 1 then return e.fn(e.data) end
  end
  error("no menu entry " .. text)
end

function GK.Click(button, ...)
  local fn = rawget(button, "_scripts").OnClick
  return fn(button, ...)
end

function GK.Shown(f) return rawget(f, "_shown") == true end

return GK
