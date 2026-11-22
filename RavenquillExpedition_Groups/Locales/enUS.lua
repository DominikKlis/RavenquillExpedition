local ADDON, ns = ...
ns.Locales = ns.Locales or {}

ns.Locales.enUS = {
  TITLE = "Group Finder",
  OPT_ANNOUNCE = "Tell me in chat when a guildmate looks for a group at my level",
  OPT_ANNOUNCE_TIP = "One line per new post that fits your level. Sign-ups for your own post are always shown.",

  ROLE_tank = "Tank", ROLE_heal = "Healer", ROLE_dps = "DPS",
  RAID_TITLE = "Guild raid: %s",
  LEVEL_RANGE = "Level %d-%d",
  TODAY = "Today", TOMORROW = "Tomorrow", WHEN = "%s %s",
  WEEKDAY_1 = "Sunday", WEEKDAY_2 = "Monday", WEEKDAY_3 = "Tuesday", WEEKDAY_4 = "Wednesday",
  WEEKDAY_5 = "Thursday", WEEKDAY_6 = "Friday", WEEKDAY_7 = "Saturday",
  AGO_NOW = "just now", AGO_MIN = "%d min ago", AGO_HOURS = "%d h ago",

  ANNOUNCE = "%s is looking for %s: %s. Sign up in /rq groups",
  ANNOUNCE_RAID = "%s plans %s, %s. Sign up in /rq groups",
  SIGNUP_NOTE = "%s signs up as %s. Invite them in /rq groups",
  WHISPER = "Hi! I'd like to join your group for %s as %s. (Ravenquill)",
  WHISPER_WHEN = "Hi! I'm in for %s on %s as %s. (Ravenquill)",

  STATUS = "%d groups open · %d online", STATUS_ONE = "1 group open · %d online", STATUS_NONE = "No group open · %d online",
  HEAD_NONE = "Nobody is looking for a group right now", HEAD_POST = "%s is looking for %s", HEAD_FITS = " · fits you",
  HEAD_RAID = "%s plans %s · %s", HEAD_SIGNUP = "%s signed up for your post (%s)", HEAD_SIGNUPS = "%d sign-ups for your post",
  HEAD_OWN = "Your post for %s is open",

  FIND = "Find group", FIND_EDIT = "Edit my post",
  HINT = "Posts expire after an hour, raids after their start.",
  EMPTY = "Nobody is looking for a group right now. Post one with \"Find group\".",
  ROLE_WANTED = "%s wanted", ROLE_COUNT = "%s %d/%d",
  FITS = "Fits your level", YOUR_POST = "Your post",
  SIGN_UP = "Sign up", COMMIT = "I'm in", SIGNED_UP = "Signed up", COMMITTED = "You're in", FULL = "Full",
  SIGN_UP_AS = "Sign up as",
  EDIT = "Edit", CLOSE = "Close", INVITE = "Invite",
  SIGNUP_ROW = "%s · %s", NO_SIGNUPS = "No sign-ups yet.",

  FORM_NEW = "New post", FORM_EDIT = "Edit your post", FORM_ACTIVITY = "Where to?", FORM_FILLED = "Already in the group",
  FORM_NOTE = "Note (optional)", FORM_WHEN = "Start", POST = "Post", UPDATE = "Update", CANCEL = "Cancel",
  PAST = "That time has passed.", DUNGEONS = "Dungeons", RAIDS = "Raids",

  ZONE_389 = "Ragefire Chasm", ZONE_43 = "Wailing Caverns", ZONE_36 = "The Deadmines", ZONE_33 = "Shadowfang Keep",
  ZONE_48 = "Blackfathom Deeps", ZONE_34 = "The Stockade", ZONE_90 = "Gnomeregan", ZONE_47 = "Razorfen Kraul",
  ZONE_189 = "Scarlet Monastery", ZONE_129 = "Razorfen Downs", ZONE_70 = "Uldaman", ZONE_209 = "Zul'Farrak",
  ZONE_349 = "Maraudon", ZONE_109 = "The Temple of Atal'Hakkar", ZONE_230 = "Blackrock Depths",
  ZONE_429 = "Dire Maul", ZONE_329 = "Stratholme", ZONE_289 = "Scholomance", ZONE_309 = "Zul'Gurub",
  ZONE_509 = "Ruins of Ahn'Qiraj", ZONE_409 = "Molten Core", ZONE_249 = "Onyxia's Lair", ZONE_469 = "Blackwing Lair",
  ZONE_531 = "Temple of Ahn'Qiraj", ZONE_533 = "Naxxramas",
  WING_GRAVEYARD = "Graveyard", WING_LIBRARY = "Library", WING_ARMORY = "Armory", WING_CATHEDRAL = "Cathedral",
  WING_EAST = "East", WING_WEST = "West", WING_NORTH = "North",
  ACT_LBRS = "Lower Blackrock Spire", ACT_UBRS = "Upper Blackrock Spire",
}
