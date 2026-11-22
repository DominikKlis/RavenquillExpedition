local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local GS = RavenquillExpedition
local SafeCall, Plain = GS.SafeCall, GS.Plain

local NEARBY_UNITS = { "target", "mouseover", "focus" }
for i = 1, 4 do NEARBY_UNITS[#NEARBY_UNITS + 1] = "party" .. i end
for i = 1, 40 do NEARBY_UNITS[#NEARBY_UNITS + 1] = "raid" .. i end

local function Whisper(name)
  SafeCall((ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell, name)
end

local function Invite(name)
  SafeCall((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit, name)
end

local function NearbyUnit(key)
  for _, unit in ipairs(NEARBY_UNITS) do
    if GS:UnitKey(unit) == key then return unit end
  end
end

local function Stores(craft, has, key)
  return craft ~= nil and type(craft[has]) == "function" and craft[has](craft, key) and true or false
end

local function Inspect(t)
  if t.gear then return t.craft:ShowInspect(t.key, "gear") end
  SafeCall(InspectUnit, t.unit)
end

local ENTRIES = {
  { label = "PARTY_INVITE", text = "MENU_INVITE", needs = "name", run = function(t) Invite(t.name) end },
  { label = "WHISPER", text = "MENU_WHISPER", needs = "name", run = function(t) Whisper(t.name) end },
  { label = "INSPECT", text = "MENU_INSPECT", needs = "gear-or-unit", run = Inspect },
  { text = "MENU_TALENTS", needs = "spec", run = function(t) t.craft:ShowInspect(t.key, "talents") end },
}

local NEEDS = {
  name = function() return true end,
  ["gear-or-unit"] = function(t) return t.gear or (t.unit ~= nil and GS.Bool(SafeCall(CanInspect, t.unit))) end,
  spec = function(t) return t.spec end,
}

local function Label(e)
  return e.label and Plain(_G[e.label], "string") or L[e.text]
end

local function Build(m, root)
  local craft = GS:GetModule("Craft")
  local t = { key = m.key, name = m.whisper or m.name, unit = NearbyUnit(m.key), craft = craft,
    gear = Stores(craft, "HasStoredGear", m.key), spec = Stores(craft, "HasStoredSpec", m.key) }
  root:CreateTitle(m.name)
  for _, e in ipairs(ENTRIES) do
    local enabled = NEEDS[e.needs](t)
    local button = root:CreateButton(Label(e), function() if enabled then e.run(t) end end)
    if not enabled then button:SetEnabled(false) end
  end
end

function M:Contact(owner, m)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return Invite(m.whisper or m.name) end
  GS:Call(MenuUtil.CreateContextMenu, owner, function(_, root) Build(m, root) end)
end
