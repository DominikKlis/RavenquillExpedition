-- Template module: tells guildmates who run it when you level up. Copy the folder, rename "Example" (README.md).
local ADDON = ...
local RQ = RavenquillExpedition

local mod = RQ:NewModule("Example", {
  addon = ADDON, api = 2, title = "Example", slash = "example", -- addon: required for sv, defaults and OnLoad
  sv = "RavenquillExpeditionExampleDB", dbVersion = 1,
  defaults = { share = true, announce = true },
  locale = {
    enUS = { LEVEL = "%s reached level %d", SHARE = "Share my level-ups", ANNOUNCE = "Show guildmates' level-ups" },
    deDE = { LEVEL = "%s hat Stufe %d erreicht", SHARE = "Meine Stufenaufstiege teilen", ANNOUNCE = "Stufenaufstiege anzeigen" },
  },
})
local L = mod.L

-- the wire format: the core checks every field before the handler sees it; "self": only about the sender
local ch = mod:NewChannel({ tag = "EX", version = 1 })
ch:Define("lvl", { from = "self", fields = { { "who", "key" }, { "level", "int", 1, 200 } } })

ch:On("lvl", function(sender, msg)
  -- keyed by sender: one entry per guildmate, so the store never grows past the guild's size
  mod:GuildStore("levels")[sender] = { level = msg.level, t = RQ:Now() }
  if mod.settings.announce then mod:Print(L.LEVEL:format(sender, msg.level)) end
end)

-- Nothing is sent in combat or an instance (Send reports "dropped"): keep the newest level until it is delivered
-- and try again when combat ends or after a loading screen.
local pending, busy
local function Share()
  if not pending or busy or not mod.settings.share then return end
  local level = pending
  busy = true
  ch:Send("lvl", { who = RQ:PlayerKey(), level = level }, { onResult = function(status)
    busy = false
    if status == "delivered" then
      if pending == level then pending = nil else Share() end -- a newer level came in meanwhile
    end
  end })
end
mod:RegisterEvent("PLAYER_LEVEL_UP", function(_, level) pending = level; Share() end)
mod:RegisterEvent("PLAYER_REGEN_ENABLED", Share)
mod:RegisterEvent("PLAYER_ENTERING_WORLD", Share)

mod:SetOptions({
  { type = "toggle", key = "share", label = L.SHARE },
  { type = "toggle", key = "announce", label = L.ANNOUNCE },
})
