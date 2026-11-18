std = "lua51"
max_line_length = false
codes = true
exclude_files = { "**/libs/**", "**/Data/**", "**/dev/fixtures/**", ".cache/**" }
ignore = { "212", "542", "211/ADDON", "211/ns" }

globals = {
  "RQDevInbox", "RavenquillExpedition", "RavenquillExpeditionCraftDB", "RavenquillExpeditionDB",
  "RavenquillExpeditionDevDB", "RavenquillExpeditionHighlightsCharDB", "RavenquillExpeditionHighlightsDB",
  "RavenquillExpeditionMap", "RavenquillExpeditionMapDB", "RavenquillExpedition_CraftAdvisor_OnCompartmentClick",
  "RavenquillExpedition_OnCompartmentClick", "SLASH_RAVENQUILL1", "SLASH_RAVENQUILL2", "SlashCmdList",
}

read_globals = {
  "Ambiguate", "BACKSLOT", "BANK_CONTAINER", "ButtonFrameTemplate_HideButtonBar",
  "ButtonFrameTemplate_HidePortrait", "CHESTSLOT", "CLASS_ICON_TCOORDS", "CUSTOM_CLASS_COLORS", "C_AddOns",
  "C_CVar", "C_ChatInfo", "C_ClassTalents", "C_Container", "C_GuildInfo", "C_Item", "C_Map", "C_QuestLog",
  "C_Reputation", "C_Spell", "C_SpellBook", "C_SuperTrack", "C_Texture", "C_Timer", "C_TooltipInfo",
  "C_TradeSkillUI", "C_Traits", "C_XMLUtil", "CanInspect", "ChatEdit_GetActiveWindow", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_OpenChat", "ChatFrame_SendTell", "CheckInteractDistance", "Constants", "CreateFrame",
  "DEFAULT_CHAT_FRAME", "Enum", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "GameFontHighlightSmall", "GameTooltip",
  "GameTooltip_Hide", "GameTooltip_ShowCompareItem", "GetAddOnInfo", "GetAddOnMetadata", "GetBuildInfo",
  "GetCoinTextureString", "GetContainerItemLink", "GetContainerNumSlots", "GetCursorPosition",
  "GetDetailedItemLevelInfo", "GetFileIDFromPath", "GetGuildInfo", "GetGuildRosterInfo", "GetInstanceInfo",
  "GetInventoryItemLink", "GetInventorySlotInfo", "GetItemCount", "GetItemInfo", "GetItemInfoInstant",
  "GetItemStats", "GetLocale", "GetMaxPlayerLevel", "GetMoneyString", "GetNormalizedRealmName",
  "GetNumGroupMembers", "GetNumGuildMembers", "GetNumQuestLogEntries", "GetNumSubgroupMembers",
  "GetNumTradeSkills", "GetProfessionInfo", "GetProfessions", "GetQuestLogTitle", "GetQuestTagInfo",
  "GetRealZoneText", "GetRealmName", "GetServerTime", "GetSpellInfo", "GetTime", "debugprofilestop", "GetTradeSkillItemLink",
  "GetTradeSkillLine", "GetTradeSkillRecipeLink", "GuildRoster", "HANDSSLOT", "HBD_PINS_WORLDMAP_SHOW_WORLD",
  "HEADSLOT", "HandleModifiedItemClick", "ITEM_CLASSES_ALLOWED", "ITEM_QUALITY_COLORS", "ITEM_REQ_SKILL",
  "InCombatLockdown", "InspectFrame", "IsAddOnLoaded", "IsControlKeyDown", "IsInGuild", "IsInInstance", "IsInRaid",
  "IsIndoors", "IsModifiedClick", "IsPlayerSpell", "IsShiftKeyDown", "LEGSSLOT", "LOCALIZED_CLASS_NAMES_FEMALE",
  "LOCALIZED_CLASS_NAMES_MALE", "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LibStub", "LoadAddOn", "MAINHANDSLOT", "MenuUtil", "MinimalSliderWithSteppersMixin", "Minimap", "NECKSLOT",
  "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil", "NotifyInspect",
  "OpenWorldMap", "PanelTemplates_DeselectTab", "PanelTemplates_SelectTab", "PanelTemplates_TabResize", "ReloadUI", "CreateVector2D", "UnitPosition", "GetFactionInfoByID",
  "ProfessionsFrame", "RAID_CLASS_COLORS", "RANGEDSLOT", "SECONDARYHANDSLOT", "SHOULDERSLOT", "SPEED",
  "ScrollUtil", "SendChatMessage", "SetItemRef", "ShoppingTooltip1", "ShoppingTooltip2", "ShowUIPanel",
  "TRINKET0SLOT", "TRINKET1SLOT", "ToggleWorldMap", "UIParent", "UISpecialFrames", "UNKNOWNOBJECT", "UiMapPoint",
  "UnitClass", "UnitFactionGroup", "UnitGUID", "UnitIsDeadOrGhost", "UnitIsInMyGuild", "UnitIsPlayer",
  "UnitIsUnit", "UnitLevel", "UnitName", "UnitNameUnmodified", "UnitOnTaxi", "UnitTokenFromGUID", "WAISTSLOT",
  "WOW_PROJECT_CAMELOT", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WRISTSLOT",
  "WorldMapFrame", "canaccessvalue", "date", "debugstack", "geterrorhandler", "hooksecurefunc", "issecretvalue",
  "strsplit", "time", "tinsert", "wipe",
}

files["**/dev/**"] = { std = "max", ignore = { "1", "4" } }
files["scripts/**"] = { std = "max" }
files["templates/**"] = { std = "lua51" }
