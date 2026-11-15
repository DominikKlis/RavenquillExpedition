-- Template module: tells guildmates who run it when you level up. Copy the folder, rename "Example" (README.md).
local ADDON = ...
local RQ = RavenquillExpedition

local mod = RQ:NewModule("Example", {
  addon = ADDON, api = 2, title = "Example", slash = "example",
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
  table.insert(mod:GuildStore("levels"), { who = sender, level = msg.level, t = RQ:Now() })
  if mod.settings.announce then mod:Print(L.LEVEL:format(sender, msg.level)) end
end)

mod:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
  if mod.settings.share then ch:Send("lvl", { who = RQ:PlayerKey(), level = level }) end
end)

mod:SetOptions({
  { type = "toggle", key = "share", label = L.SHARE },
  { type = "toggle", key = "announce", label = L.ANNOUNCE },
})
