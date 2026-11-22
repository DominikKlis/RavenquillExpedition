local ADDON, ns = ...
local GS = RavenquillExpedition

local G = GS:NewModule("Groups", {
  addon = ADDON, api = 2, slash = "groups", icon = "Interface\\Icons\\INV_Misc_Bandana_01",
  sv = "RavenquillExpeditionGroupsDB", dbVersion = 1, locale = ns.Locales,
  defaults = { announce = true },
})
local L = G.L
G.title = L.TITLE
ns.G, ns.L = G, L

G:SetOptions({
  { type = "toggle", key = "announce", label = L.OPT_ANNOUNCE, tooltip = L.OPT_ANNOUNCE_TIP },
})
